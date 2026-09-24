import 'dart:io';
import 'package:flutter/material.dart';
import '../models/pdf_document_item.dart';
import '../services/device_pdf_service.dart';

class RenamePdfDialog extends StatefulWidget {
  final PdfDocumentItem document;

  const RenamePdfDialog({
    super.key,
    required this.document,
  });

  /// Displays the rename dialog and returns the updated [PdfDocumentItem] if renamed, or null if dismissed.
  static Future<PdfDocumentItem?> show(BuildContext context, PdfDocumentItem document) {
    return showDialog<PdfDocumentItem>(
      context: context,
      barrierDismissible: true,
      builder: (context) => RenamePdfDialog(document: document),
    );
  }

  @override
  State<RenamePdfDialog> createState() => _RenamePdfDialogState();
}

class _RenamePdfDialogState extends State<RenamePdfDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;
  bool _isRenaming = false;

  @override
  void initState() {
    super.initState();
    String baseName = widget.document.title;
    if (baseName.toLowerCase().endsWith('.pdf')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }
    _controller = TextEditingController(text: baseName);
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: baseName.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _validate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return 'File name cannot be empty';
    }

    final invalidChars = RegExp(r'[\\/:*?"<>|]');
    if (invalidChars.hasMatch(trimmed)) {
      return 'Name cannot contain: \\ / : * ? " < > |';
    }

    if (widget.document.type == PdfSourceType.file && widget.document.path.isNotEmpty) {
      try {
        final oldFile = File(widget.document.path);
        final parentDir = oldFile.parent.path;
        final targetPath = '$parentDir${Platform.pathSeparator}$trimmed.pdf';
        if (targetPath.toLowerCase() != oldFile.path.toLowerCase() && File(targetPath).existsSync()) {
          return 'A file named "$trimmed.pdf" already exists';
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _handleRename() async {
    final newName = _controller.text.trim();
    final error = _validate(newName);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    String currentBase = widget.document.title;
    if (currentBase.toLowerCase().endsWith('.pdf')) {
      currentBase = currentBase.substring(0, currentBase.length - 4);
    }

    // If identical, simply dismiss
    if (newName == currentBase) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isRenaming = true;
      _errorText = null;
    });

    try {
      final updatedDoc = await DevicePdfService.instance.renamePdf(
        doc: widget.document,
        newBaseName: newName,
      );

      if (mounted) {
        Navigator.of(context).pop(updatedDoc);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRenaming = false;
          _errorText = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Icon & Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.drive_file_rename_outline_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rename PDF',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.document.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Text Input Field
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              enabled: !_isRenaming,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleRename(),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                labelText: 'Document Name',
                hintText: 'Enter new name',
                errorText: _errorText,
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                prefixIcon: const Icon(Icons.description_outlined, size: 20),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_controller.text.isNotEmpty && !_isRenaming)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '.pdf',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isRenaming ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isRenaming ? null : _handleRename,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isRenaming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Rename',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
