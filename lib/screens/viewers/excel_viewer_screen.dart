import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as xl;
import 'package:open_filex/open_filex.dart';
import '../../models/pdf_document_item.dart';
import '../../services/device_pdf_service.dart';

class ExcelViewerScreen extends StatefulWidget {
  final PdfDocumentItem document;

  const ExcelViewerScreen({
    super.key,
    required this.document,
  });

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

class _ExcelViewerScreenState extends State<ExcelViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  final Map<String, List<List<String>>> _sheets = {};
  final List<String> _sheetNames = [];
  int _activeSheetIndex = 0;
  int _rowsToDisplay = 300;

  String? _selectedCellCoord;
  String? _selectedCellValue;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadExcelData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static Map<String, List<List<String>>> _parseExcelBytes(Uint8List bytes) {
    final Map<String, List<List<String>>> result = {};
    final excel = xl.Excel.decodeBytes(bytes);
    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;

      final List<List<String>> rows = [];
      for (final row in sheet.rows) {
        final rowData = row.map((cell) => cell?.value?.toString() ?? '').toList();
        if (rowData.any((s) => s.trim().isNotEmpty)) {
          rows.add(rowData);
        }
      }

      if (rows.isNotEmpty) {
        result[table] = rows;
      }
    }
    return result;
  }

  Future<void> _loadExcelData() async {
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

      if (pathLower.endsWith('.csv')) {
        final csvString = utf8.decode(bytes, allowMalformed: true);
        final stringRows = _parseCsv(csvString);

        _sheets['Sheet 1'] = stringRows;
        _sheetNames.add('Sheet 1');
      } else {
        Map<String, List<List<String>>> parsedSheets;
        try {
          parsedSheets = await Isolate.run(() => _parseExcelBytes(bytes));
        } catch (_) {
          parsedSheets = _parseExcelBytes(bytes);
        }

        for (final entry in parsedSheets.entries) {
          _sheets[entry.key] = entry.value;
          _sheetNames.add(entry.key);
        }

        if (_sheetNames.isEmpty) {
          _sheets['Sheet 1'] = [
            ['No data found in this workbook']
          ];
          _sheetNames.add('Sheet 1');
        }
      }

      if (mounted) {
        setState(() {
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

  String _colIndexToName(int col) {
    String result = '';
    int c = col;
    while (c >= 0) {
      result = String.fromCharCode(65 + (c % 26)) + result;
      c = (c ~/ 26) - 1;
    }
    return result;
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

  static List<List<String>> _parseCsv(String csvString) {
    final List<List<String>> rows = [];
    final List<String> currentRow = [];
    final StringBuffer currentCell = StringBuffer();
    bool insideQuotes = false;

    for (int i = 0; i < csvString.length; i++) {
      final char = csvString[i];

      if (char == '"') {
        if (insideQuotes && i + 1 < csvString.length && csvString[i + 1] == '"') {
          currentCell.write('"');
          i++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (char == ',' && !insideQuotes) {
        currentRow.add(currentCell.toString().trim());
        currentCell.clear();
      } else if ((char == '\n' || char == '\r') && !insideQuotes) {
        if (char == '\r' && i + 1 < csvString.length && csvString[i + 1] == '\n') {
          i++;
        }
        currentRow.add(currentCell.toString().trim());
        currentCell.clear();

        if (currentRow.any((c) => c.isNotEmpty)) {
          rows.add(List.from(currentRow));
        }
        currentRow.clear();
      } else {
        currentCell.write(char);
      }
    }

    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentCell.toString().trim());
      if (currentRow.any((c) => c.isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }

  void _shareDocument() {
    DevicePdfService.instance.sharePdf(widget.document);
  }

  Map<int, TableColumnWidth> _buildColumnWidths(List<List<String>> rows, int maxCols) {
    final Map<int, TableColumnWidth> widths = {
      0: const FixedColumnWidth(48.0),
    };
    final sampleSize = math.min(rows.length, 50);
    for (int c = 0; c < maxCols; c++) {
      int maxLen = _colIndexToName(c).length;
      for (int r = 0; r < sampleSize; r++) {
        if (c < rows[r].length) {
          final len = rows[r][c].length;
          if (len > maxLen) maxLen = len;
        }
      }
      final width = (maxLen * 8.5 + 28.0).clamp(85.0, 260.0);
      widths[c + 1] = FixedColumnWidth(width);
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFF16A34A); // Excel Green
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final headerBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    final currentSheetName = _sheetNames.isNotEmpty ? _sheetNames[_activeSheetIndex] : '';
    final currentRows = _sheets[currentSheetName] ?? [];

    int maxCols = 0;
    for (final row in currentRows) {
      if (row.length > maxCols) maxCols = row.length;
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: cardBg,
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
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Search cells in $currentSheetName...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
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
                        ? 'Loading spreadsheet...'
                        : '$currentSheetName (${currentRows.length} rows, $maxCols columns)',
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
            tooltip: _isSearching ? 'Close Search' : 'Search Cells',
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
                    'Parsing spreadsheet...',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
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
                          'Spreadsheet Preview Limited',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This spreadsheet could not be parsed directly. You can open it in Microsoft Excel, Google Sheets, or WPS Office directly.',
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
              : Column(
                  children: [
                    // Cell formula / coordinate bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: headerBg,
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              _selectedCellCoord ?? 'A1',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('=', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedCellValue ?? (currentRows.isNotEmpty && currentRows[0].isNotEmpty ? currentRows[0][0] : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Spreadsheet 2D Table View
                    Expanded(
                      child: InteractiveViewer(
                        constrained: false,
                        scaleEnabled: true,
                        minScale: 0.6,
                        maxScale: 2.5,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Table(
                                columnWidths: _buildColumnWidths(currentRows, maxCols),
                                border: TableBorder.all(
                                  color: borderColor,
                                  width: 0.8,
                                ),
                                children: [
                                  // Column header row (A, B, C...)
                                  TableRow(
                                    decoration: BoxDecoration(color: headerBg),
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                        alignment: Alignment.center,
                                        child: const Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      for (int c = 0; c < maxCols; c++)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          alignment: Alignment.center,
                                          child: Text(
                                            _colIndexToName(c),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  // Data rows (chunked for maximum performance)
                                  for (int r = 0; r < (currentRows.length > _rowsToDisplay ? _rowsToDisplay : currentRows.length); r++)
                                    TableRow(
                                      decoration: BoxDecoration(
                                        color: r % 2 == 1
                                            ? (isDark ? const Color(0xFF131B2A) : const Color(0xFFFAFAFA))
                                            : cardBg,
                                      ),
                                      children: [
                                        // Row number
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                          color: headerBg,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${r + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                        // Cells
                                        for (int c = 0; c < maxCols; c++)
                                          Builder(
                                            builder: (context) {
                                              final cellText = c < currentRows[r].length ? currentRows[r][c] : '';
                                              final coord = '${_colIndexToName(c)}${r + 1}';
                                              final isSelected = _selectedCellCoord == coord;
                                              final isMatch = _searchQuery.isNotEmpty && cellText.toLowerCase().contains(_searchQuery);

                                              return InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedCellCoord = coord;
                                                    _selectedCellValue = cellText;
                                                  });
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? primaryColor.withValues(alpha: 0.25)
                                                        : (isMatch ? Colors.amber.withValues(alpha: 0.35) : null),
                                                    border: isSelected
                                                        ? Border.all(color: primaryColor, width: 2)
                                                        : null,
                                                  ),
                                                  child: Text(
                                                    cellText,
                                                    maxLines: 4,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                      fontWeight: isSelected || isMatch ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                              if (currentRows.length > _rowsToDisplay)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                                  child: Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _rowsToDisplay += 300;
                                          });
                                        },
                                        icon: const Icon(Icons.expand_more_rounded, size: 18),
                                        label: Text('Load next 300 rows (${currentRows.length - _rowsToDisplay} remaining)'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        onPressed: _openInExternalApp,
                                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                        label: const Text('Open in Office App'),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Sheet Switcher Tabs
                    if (_sheetNames.length > 1)
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: cardBg,
                          border: Border(top: BorderSide(color: borderColor)),
                        ),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          itemCount: _sheetNames.length,
                          separatorBuilder: (_, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final name = _sheetNames[index];
                            final isSelected = _activeSheetIndex == index;

                            return ChoiceChip(
                              label: Text(name),
                              selected: isSelected,
                              selectedColor: primaryColor.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? primaryColor : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              side: BorderSide(
                                color: isSelected ? primaryColor : borderColor,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _activeSheetIndex = index;
                                  _selectedCellCoord = null;
                                  _selectedCellValue = null;
                                  _rowsToDisplay = 300;
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
    );
  }
}
