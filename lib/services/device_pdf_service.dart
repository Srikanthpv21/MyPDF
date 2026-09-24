import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pdf_document_item.dart';
import 'permission_service.dart';

class DevicePdfService {
  DevicePdfService._();
  static final DevicePdfService instance = DevicePdfService._();

  /// Picks a PDF file using the system file picker
  Future<PdfDocumentItem?> pickPdfFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final formattedSize = '${(file.size / 1024).toStringAsFixed(1)} KB';

        if (file.bytes != null) {
          return PdfDocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: file.name,
            subtitle: 'Device Storage | $formattedSize',
            type: PdfSourceType.memory,
            bytes: file.bytes,
            fileSize: formattedSize,
          );
        } else if (file.path != null) {
          return PdfDocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: file.name,
            subtitle: 'Device Storage | $formattedSize',
            type: PdfSourceType.file,
            path: file.path!,
            fileSize: formattedSize,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking PDF file: $e');
      rethrow;
    }
    return null;
  }

  /// Renames a PDF file on the device filesystem (if file-backed) or in-memory.
  /// Throws an [Exception] if validation fails or the operation cannot be completed.
  Future<PdfDocumentItem> renamePdf({
    required PdfDocumentItem doc,
    required String newBaseName,
  }) async {
    String cleanBaseName = newBaseName.trim();
    if (cleanBaseName.toLowerCase().endsWith('.pdf')) {
      cleanBaseName = cleanBaseName.substring(0, cleanBaseName.length - 4).trim();
    }

    if (cleanBaseName.isEmpty) {
      throw Exception('File name cannot be empty');
    }

    final invalidChars = RegExp(r'[\\/:*?"<>|]');
    if (invalidChars.hasMatch(cleanBaseName)) {
      throw Exception('File name cannot contain invalid characters: \\ / : * ? " < > |');
    }

    final finalFileName = '$cleanBaseName.pdf';

    if (doc.type == PdfSourceType.file && doc.path.isNotEmpty) {
      final oldFile = File(doc.path);
      if (!await oldFile.exists()) {
        throw Exception('File not found at ${doc.path}');
      }

      final parentDir = oldFile.parent;
      final newPath = '${parentDir.path}${Platform.pathSeparator}$finalFileName';

      if (newPath == oldFile.path) {
        return doc; // Same name, no-op
      }

      final targetFile = File(newPath);
      if (await targetFile.exists()) {
        throw Exception('A file named "$finalFileName" already exists in this folder');
      }

      File renamedFile;
      try {
        renamedFile = await oldFile.rename(newPath);
      } catch (e) {
        // Fallback: copy and delete if atomic rename syscall fails across storage mounts
        try {
          renamedFile = await oldFile.copy(newPath);
          await oldFile.delete();
        } catch (fallbackError) {
          throw Exception(
            'Unable to rename file: ${e is FileSystemException ? e.message : e.toString()}',
          );
        }
      }

      return doc.copyWith(
        id: renamedFile.path,
        title: finalFileName,
        path: renamedFile.path,
      );
    } else {
      // For memory, asset, or network documents: update title in-memory
      return doc.copyWith(
        title: finalFileName,
      );
    }
  }

  /// Shares a PDF document item via the native system share sheet
  Future<void> sharePdf(PdfDocumentItem doc) async {
    try {
      String? sharePath;
      if (doc.type == PdfSourceType.file && doc.path.isNotEmpty && File(doc.path).existsSync()) {
        sharePath = doc.path;
      } else if (doc.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = doc.title.toLowerCase().endsWith('.pdf') ? doc.title : '${doc.title}.pdf';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(doc.bytes!);
        sharePath = tempFile.path;
      }

      if (sharePath != null && File(sharePath).existsSync()) {
        final xFile = XFile(
          sharePath,
          mimeType: 'application/pdf',
          name: doc.title,
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [xFile],
            subject: doc.title,
          ),
        );
      } else {
        throw Exception('PDF document file is not accessible for sharing');
      }
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
      rethrow;
    }
  }

  /// Scans device storage for PDF documents in common public directories

  Future<List<PdfDocumentItem>> scanCommonPdfDirectories() async {
    final List<PdfDocumentItem> results = [];
    if (kIsWeb || !Platform.isAndroid) return results;

    final hasPerm = await PermissionService.instance.hasStoragePermission();
    if (!hasPerm) return results;

    final Set<String> visitedPaths = {};
    final candidateDirs = <Directory>[
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Documents'),
      Directory('/storage/emulated/0/Books'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/Download/Telegram'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Documents'),
      Directory('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents'),
      Directory('/storage/emulated/0'),
    ];

    // Check for SD card or external secondary storage mounts
    try {
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        final entries = storageDir.listSync(recursive: false);
        for (final entry in entries) {
          if (entry is Directory &&
              !entry.path.contains('emulated') &&
              !entry.path.contains('self')) {
            candidateDirs.add(Directory('${entry.path}/Download'));
            candidateDirs.add(Directory('${entry.path}/Documents'));
            candidateDirs.add(Directory('${entry.path}/Books'));
          }
        }
      }
    } catch (_) {}

    void scanDirectory(Directory dir, int currentDepth, int maxDepth) {
      if (currentDepth > maxDepth) return;
      try {
        if (!dir.existsSync()) return;
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final name = segments.isNotEmpty ? segments.last : '';
          if (name.startsWith('.')) continue; // ignore hidden files/folders

          if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
            if (visitedPaths.add(entity.path)) {
              try {
                final stat = entity.statSync();
                final sizeInBytes = stat.size;
                final formattedSize = sizeInBytes >= 1024 * 1024
                    ? '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                    : '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
                final parentFolder = segments.length >= 2 ? segments[segments.length - 2] : 'Storage';

                results.add(
                  PdfDocumentItem(
                    id: entity.path,
                    title: name,
                    subtitle: '$parentFolder | $formattedSize',
                    type: PdfSourceType.file,
                    path: entity.path,
                    fileSize: formattedSize,
                    lastModified: stat.modified,
                  ),
                );
              } catch (_) {}
            }
          } else if (entity is Directory && currentDepth < maxDepth) {
            final path = entity.path;
            // Never enter restricted Android system app/data directories
            if (path.contains('/Android/data') || path.contains('/Android/obb')) {
              continue;
            }
            scanDirectory(entity, currentDepth + 1, maxDepth);
          }
        }
      } catch (e) {
        debugPrint('Skip inaccessible folder: ${dir.path} ($e)');
      }
    }

    for (final dir in candidateDirs) {
      // Deeper scan for Download/Documents/Books, shallow for root storage
      final maxDepth = dir.path == '/storage/emulated/0' ? 1 : 2;
      scanDirectory(dir, 0, maxDepth);
    }

    // Sort newest modified first
    results.sort((a, b) {
      if (a.lastModified != null && b.lastModified != null) {
        return b.lastModified!.compareTo(a.lastModified!);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return results;
  }
}
