import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pdf_document_item.dart';
import 'permission_service.dart';

class DevicePdfService {
  DevicePdfService._();
  static final DevicePdfService instance = DevicePdfService._();

  Future<PdfDocumentItem?> pickPdfFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final formattedSize = '${(file.size / 1024).toStringAsFixed(1)} KB';

        if (file.path != null && file.path!.isNotEmpty) {
          return PdfDocumentItem(
            id: file.path!,
            title: file.name,
            subtitle: 'Device Storage | $formattedSize',
            type: PdfSourceType.file,
            path: file.path!,
            fileSize: formattedSize,
          );
        } else if (file.bytes != null) {
          return PdfDocumentItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: file.name,
            subtitle: 'Device Storage | $formattedSize',
            type: PdfSourceType.memory,
            bytes: file.bytes,
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
        return doc;
      }

      final targetFile = File(newPath);
      if (await targetFile.exists()) {
        throw Exception('A file named "$finalFileName" already exists in this folder');
      }

      File renamedFile;
      try {
        renamedFile = await oldFile.rename(newPath);
      } catch (e) {
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
      return doc.copyWith(
        title: finalFileName,
      );
    }
  }

  /// Shares a single PDF document item via the native system share sheet
  Future<void> sharePdf(PdfDocumentItem doc) async {
    return sharePdfs([doc]);
  }

  /// Shares multiple PDF documents via the native system share sheet
  Future<void> sharePdfs(List<PdfDocumentItem> docs) async {
    try {
      final List<XFile> xFiles = [];
      for (final doc in docs) {
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
          xFiles.add(XFile(sharePath, mimeType: 'application/pdf', name: doc.title));
        }
      }

      if (xFiles.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            files: xFiles,
            subject: xFiles.length == 1 ? docs.first.title : '${xFiles.length} PDF Documents',
          ),
        );
      } else {
        throw Exception('No valid PDF files available for sharing');
      }
    } catch (e) {
      debugPrint('Error sharing PDFs: $e');
      rethrow;
    }
  }

  /// Deletes a PDF file from device storage
  Future<void> deletePdf(PdfDocumentItem doc) async {
    await deletePdfs([doc]);
  }

  /// Deletes multiple PDF files from device storage
  Future<int> deletePdfs(List<PdfDocumentItem> docs) async {
    int deletedCount = 0;
    for (final doc in docs) {
      try {
        if (doc.type == PdfSourceType.file && doc.path.isNotEmpty) {
          final file = File(doc.path);
          if (!file.path.toLowerCase().endsWith('.pdf')) {
            continue;
          }
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        } else {
          deletedCount++;
        }
      } catch (e) {
        debugPrint('Error deleting ${doc.path}: $e');
      }
    }
    return deletedCount;
  }

  static const String _cacheFileName = 'pdf_library_cache.json';
  static const String _readingProgressFileName = 'pdf_reading_progress.json';

  String? _cachedAppDocPath;
  String? _lastSavedCacheContent;
  String? _lastSavedProgressContent;

  Future<String> _getAppDocPath() async {
    if (_cachedAppDocPath != null) return _cachedAppDocPath!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedAppDocPath = dir.path;
    return _cachedAppDocPath!;
  }

  Future<File> _getCacheFile() async {
    final path = await _getAppDocPath();
    return File('$path/$_cacheFileName');
  }

  Future<List<PdfDocumentItem>> loadCachedPdfs() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          _lastSavedCacheContent = content;
          final List<dynamic> list = jsonDecode(content);
          final items = <PdfDocumentItem>[];
          for (final raw in list) {
            try {
              if (raw is Map<String, dynamic>) {
                final doc = PdfDocumentItem.fromJson(raw);
                if (doc.path.isNotEmpty && File(doc.path).existsSync()) {
                  items.add(doc);
                }
              }
            } catch (_) {}
          }
          return items;
        }
      }
    } catch (e) {
      debugPrint('Error loading cached PDFs: $e');
    }
    return [];
  }

  Future<void> saveCachedPdfs(List<PdfDocumentItem> pdfs) async {
    try {
      final jsonList = pdfs.where((d) => d.type == PdfSourceType.file).map((d) => d.toJson()).toList();
      final content = jsonEncode(jsonList);
      if (content == _lastSavedCacheContent) return;
      _lastSavedCacheContent = content;

      final file = await _getCacheFile();
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Error saving cached PDFs: $e');
    }
  }

  Future<File> _getReadingProgressFile() async {
    final path = await _getAppDocPath();
    return File('$path/$_readingProgressFileName');
  }

  Future<Map<String, int>> loadReadingProgress() async {
    try {
      final file = await _getReadingProgressFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          _lastSavedProgressContent = content;
          final Map<String, dynamic> raw = jsonDecode(content);
          return raw.map((k, v) => MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 1));
        }
      }
    } catch (e) {
      debugPrint('Error loading reading progress: $e');
    }
    return {};
  }

  Future<void> saveReadingProgress(Map<String, int> progress) async {
    try {
      final content = jsonEncode(progress);
      if (content == _lastSavedProgressContent) return;
      _lastSavedProgressContent = content;

      final file = await _getReadingProgressFile();
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Error saving reading progress: $e');
    }
  }

  Future<List<PdfDocumentItem>> scanCommonPdfDirectories() async {
    if (kIsWeb || !Platform.isAndroid) return [];

    final hasPerm = await PermissionService.instance.hasStoragePermission();
    if (!hasPerm) return [];

    try {
      return await Isolate.run(_scanFileSystemForPdfs);
    } catch (e) {
      debugPrint('Error scanning PDFs in background isolate: $e');
      return _scanFileSystemForPdfs();
    }
  }

  static List<PdfDocumentItem> _scanFileSystemForPdfs() {
    final List<PdfDocumentItem> results = [];
    final Set<String> visitedFilePaths = {};
    final Set<String> visitedDirPaths = {};

    final candidateDirs = <Directory>[
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Documents'),
      Directory('/storage/emulated/0/Books'),
      Directory('/storage/emulated/0/WhatsApp/Media/WhatsApp Documents'),
      Directory('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents'),
    ];

    try {
      final storageDir = Directory('/storage');
      if (storageDir.existsSync()) {
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
        final canonical = dir.path;
        if (!visitedDirPaths.add(canonical)) return;
        if (!dir.existsSync()) return;

        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final name = segments.isNotEmpty ? segments.last : '';
          if (name.startsWith('.')) continue;

          if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
            if (visitedFilePaths.add(entity.path)) {
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
            if (path.contains('/Android/data') ||
                path.contains('/Android/obb') ||
                path.contains('/DCIM') ||
                path.contains('/Pictures') ||
                path.contains('/Music') ||
                path.contains('/Movies')) {
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
      scanDirectory(dir, 0, 2);
    }

    results.sort((a, b) {
      if (a.lastModified != null && b.lastModified != null) {
        return b.lastModified!.compareTo(a.lastModified!);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return results;
  }
}
