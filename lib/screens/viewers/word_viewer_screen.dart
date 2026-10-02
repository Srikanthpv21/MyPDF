import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:open_filex/open_filex.dart';
import '../../models/pdf_document_item.dart';
import '../../services/device_pdf_service.dart';

enum WordReadingMode { light, sepia, night }

class WordBlock {
  final String type; // 'title', 'heading1', 'heading2', 'paragraph', 'bullet', 'table'
  final String text;
  final List<List<String>>? tableData;
  final bool isBold;
  final bool isItalic;

  WordBlock({
    required this.type,
    this.text = '',
    this.tableData,
    this.isBold = false,
    this.isItalic = false,
  });
}

class WordViewerScreen extends StatefulWidget {
  final PdfDocumentItem document;

  const WordViewerScreen({
    super.key,
    required this.document,
  });

  @override
  State<WordViewerScreen> createState() => _WordViewerScreenState();
}

class _WordViewerScreenState extends State<WordViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  final List<WordBlock> _blocks = [];
  int _wordCount = 0;
  double _fontSizeScale = 1.0;
  WordReadingMode _readingMode = WordReadingMode.light;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWordDocument();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _extractDocxBlocks(Uint8List bytes) {
    final List<Map<String, dynamic>> blocks = [];
    final archive = ZipDecoder().decodeBytes(bytes);
    final docEntry = archive.findFile('word/document.xml');
    if (docEntry == null) {
      throw Exception('Unable to locate document content inside DOCX package');
    }

    final content = utf8.decode(docEntry.content as List<int>, allowMalformed: true);
    final doc = xml.XmlDocument.parse(content);
    final body = doc.findAllElements('w:body').firstOrNull;
    if (body == null) return blocks;

    for (final node in body.children) {
      if (node is! xml.XmlElement) continue;

      if (node.name.local == 'p') {
        String type = 'paragraph';
        final pStyle = node.findAllElements('w:pStyle').firstOrNull?.getAttribute('w:val');
        final numPr = node.findAllElements('w:numPr').firstOrNull;

        if (pStyle != null) {
          final s = pStyle.toLowerCase();
          if (s.contains('title')) {
            type = 'title';
          } else if (s.contains('heading1') || s.contains('heading 1')) {
            type = 'heading1';
          } else if (s.contains('heading2') || s.contains('heading 2')) {
            type = 'heading2';
          } else if (s.contains('heading3') || s.contains('heading 3')) {
            type = 'heading3';
          }
        }

        if (numPr != null) {
          type = 'bullet';
        }

        final textBuffer = StringBuffer();
        bool hasBold = false;
        bool hasItalic = false;

        for (final run in node.findAllElements('w:r')) {
          final rPr = run.findAllElements('w:rPr').firstOrNull;
          if (rPr != null) {
            if (rPr.findElements('w:b').isNotEmpty) hasBold = true;
            if (rPr.findElements('w:i').isNotEmpty) hasItalic = true;
          }

          for (final t in run.findAllElements('w:t')) {
            textBuffer.write(t.innerText);
          }
        }

        final fullText = textBuffer.toString().trim();
        if (fullText.isNotEmpty) {
          blocks.add({
            'type': type,
            'text': fullText,
            'isBold': hasBold,
            'isItalic': hasItalic,
          });
        }
      } else if (node.name.local == 'tbl') {
        final List<List<String>> tableData = [];
        for (final tr in node.findAllElements('w:tr')) {
          final List<String> row = [];
          for (final tc in tr.findAllElements('w:tc')) {
            final cellBuffer = StringBuffer();
            for (final t in tc.findAllElements('w:t')) {
              cellBuffer.write(t.innerText);
            }
            row.add(cellBuffer.toString().trim());
          }
          if (row.isNotEmpty) {
            tableData.add(row);
          }
        }
        if (tableData.isNotEmpty) {
          blocks.add({
            'type': 'table',
            'tableData': tableData,
          });
        }
      }
    }
    return blocks;
  }

  static List<Map<String, dynamic>> _extractLegacyDocBlocks(Uint8List bytes) {
    final sampleSize = math.min(bytes.length, 2 * 1024 * 1024);
    final sampleBytes = bytes.sublist(0, sampleSize);
    final decoded = String.fromCharCodes(sampleBytes);
    final cleanAscii = decoded.replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), ' ');
    final paragraphs = cleanAscii
        .split(RegExp(r'[\r\n]+'))
        .map((p) => p.trim())
        .where((p) => p.length > 3)
        .toList();

    return paragraphs.map((p) => {
      'type': 'paragraph',
      'text': p,
      'isBold': false,
      'isItalic': false,
    }).toList();
  }

  Future<void> _loadWordDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final file = File(widget.document.path);
      if (!await file.exists()) {
        throw Exception('File not found on device storage');
      }

      final bytes = await file.readAsBytes();
      final pathLower = widget.document.path.toLowerCase();

      List<Map<String, dynamic>> rawBlocks;
      if (pathLower.endsWith('.docx')) {
        try {
          rawBlocks = await Isolate.run(() => _extractDocxBlocks(bytes));
        } catch (_) {
          rawBlocks = _extractDocxBlocks(bytes);
        }
      } else {
        try {
          rawBlocks = await Isolate.run(() => _extractLegacyDocBlocks(bytes));
        } catch (_) {
          rawBlocks = _extractLegacyDocBlocks(bytes);
        }
      }

      _blocks.clear();
      for (final raw in rawBlocks) {
        _blocks.add(
          WordBlock(
            type: raw['type'] as String,
            text: raw['text'] as String? ?? '',
            tableData: (raw['tableData'] as List<dynamic>?)
                ?.map((r) => (r as List<dynamic>).map((c) => c.toString()).toList())
                .toList(),
            isBold: raw['isBold'] as bool? ?? false,
            isItalic: raw['isItalic'] as bool? ?? false,
          ),
        );
      }

      if (_blocks.isEmpty) {
        _blocks.add(WordBlock(type: 'paragraph', text: 'This document has no readable text content.'));
      }

      // Calculate total words
      int words = 0;
      for (final block in _blocks) {
        if (block.text.isNotEmpty) {
          words += block.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
        } else if (block.tableData != null) {
          for (final row in block.tableData!) {
            for (final cell in row) {
              words += cell.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _wordCount = words;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _openInExternalApp() async {
    try {
      final result = await OpenFilex.open(widget.document.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file: ${result.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  void _shareDocument() {
    DevicePdfService.instance.sharePdf(widget.document);
  }

  Color _getBgColor(bool isDark) {
    switch (_readingMode) {
      case WordReadingMode.night:
        return const Color(0xFF0F172A);
      case WordReadingMode.sepia:
        return const Color(0xFFFBF0D9);
      case WordReadingMode.light:
        return isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    }
  }

  Color _getPageBgColor(bool isDark) {
    switch (_readingMode) {
      case WordReadingMode.night:
        return const Color(0xFF1E293B);
      case WordReadingMode.sepia:
        return const Color(0xFFFFF8EC);
      case WordReadingMode.light:
        return isDark ? const Color(0xFF1E293B) : Colors.white;
    }
  }

  Color _getTextColor(bool isDark) {
    switch (_readingMode) {
      case WordReadingMode.night:
        return Colors.white.withValues(alpha: 0.9);
      case WordReadingMode.sepia:
        return const Color(0xFF3F2B1D);
      case WordReadingMode.light:
        return isDark ? Colors.white : const Color(0xFF0F172A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFF2563EB); // Word Blue
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final pageBg = _getPageBgColor(isDark);
    final textColor = _getTextColor(isDark);

    return Scaffold(
      backgroundColor: _getBgColor(isDark),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: borderColor),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                decoration: const InputDecoration(
                  hintText: 'Search text in document...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.document.fileExtension,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.document.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _isLoading
                        ? 'Loading document...'
                        : '$_wordCount words · ~${(_wordCount / 200).ceil()} min read',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? 'Close Search' : 'Search Text',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          PopupMenuButton<WordReadingMode>(
            icon: const Icon(Icons.style_outlined),
            tooltip: 'Reading Theme',
            onSelected: (mode) => setState(() => _readingMode = mode),
            itemBuilder: (_) => const [
              PopupMenuItem(value: WordReadingMode.light, child: Text('Light Mode')),
              PopupMenuItem(value: WordReadingMode.sepia, child: Text('Sepia Mode')),
              PopupMenuItem(value: WordReadingMode.night, child: Text('Night Mode')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: 'Change Font Size',
            onPressed: () {
              setState(() {
                _fontSizeScale = _fontSizeScale >= 1.4 ? 0.9 : _fontSizeScale + 0.15;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share File',
            onPressed: _shareDocument,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open in Office App',
            onPressed: _openInExternalApp,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    'Extracting document content...',
                    style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: Colors.amber.shade700),
                        const SizedBox(height: 14),
                        const Text(
                          'Document Preview Limited',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This Word document could not be rendered inline. You can open it with Microsoft Word, Google Docs, or WPS Office directly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _openInExternalApp,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Open in Office App'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 820),
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: pageBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SelectionArea(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                          itemCount: _blocks.length,
                          itemBuilder: (context, index) {
                            final block = _blocks[index];
                            return _buildWordBlock(block, textColor, isDark, primaryColor);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildWordBlock(WordBlock block, Color textColor, bool isDark, Color primaryColor) {
    final isMatch = _searchQuery.isNotEmpty && block.text.toLowerCase().contains(_searchQuery);

    if (block.type == 'table' && block.tableData != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            children: [
              for (final row in block.tableData!)
                TableRow(
                  children: [
                    for (final cell in row)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          cell,
                          style: TextStyle(
                            fontSize: 13 * _fontSizeScale,
                            color: textColor,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    TextStyle style;
    EdgeInsets padding;

    switch (block.type) {
      case 'title':
        style = TextStyle(
          fontSize: 24 * _fontSizeScale,
          fontWeight: FontWeight.w900,
          color: textColor,
          letterSpacing: -0.4,
          height: 1.3,
        );
        padding = const EdgeInsets.only(top: 16, bottom: 12);
        break;
      case 'heading1':
        style = TextStyle(
          fontSize: 20 * _fontSizeScale,
          fontWeight: FontWeight.w800,
          color: primaryColor,
          letterSpacing: -0.2,
          height: 1.35,
        );
        padding = const EdgeInsets.only(top: 20, bottom: 8);
        break;
      case 'heading2':
        style = TextStyle(
          fontSize: 17 * _fontSizeScale,
          fontWeight: FontWeight.w700,
          color: textColor,
          height: 1.4,
        );
        padding = const EdgeInsets.only(top: 16, bottom: 6);
        break;
      case 'heading3':
        style = TextStyle(
          fontSize: 15 * _fontSizeScale,
          fontWeight: FontWeight.w600,
          color: textColor.withValues(alpha: 0.85),
          height: 1.4,
        );
        padding = const EdgeInsets.only(top: 12, bottom: 4);
        break;
      case 'bullet':
        style = TextStyle(
          fontSize: 14.5 * _fontSizeScale,
          color: textColor,
          height: 1.6,
        );
        padding = const EdgeInsets.symmetric(vertical: 3);
        break;
      default:
        style = TextStyle(
          fontSize: 14.5 * _fontSizeScale,
          fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
          color: textColor,
          height: 1.65,
        );
        padding = const EdgeInsets.symmetric(vertical: 6);
    }

    return Container(
      color: isMatch ? Colors.amber.withValues(alpha: 0.35) : null,
      padding: padding,
      child: block.type == 'bullet'
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: Text(block.text, style: style)),
              ],
            )
          : Text(block.text, style: style),
    );
  }
}
