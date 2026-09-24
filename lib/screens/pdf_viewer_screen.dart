import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/pdf_document_item.dart';
import '../services/device_pdf_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import '../widgets/page_thumbnail_sheet.dart';
import '../widgets/rename_pdf_dialog.dart';
import '../widgets/search_bar_overlay.dart';
import '../widgets/storage_permission_dialog.dart';

class PdfViewerScreen extends StatefulWidget {
  final PdfDocumentItem? initialDocument;

  const PdfViewerScreen({
    super.key,
    this.initialDocument,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> with WidgetsBindingObserver {
  late PdfViewerController _pdfViewerController;
  PdfDocumentItem? _currentDocument;

  int _currentPage = 1;
  int _totalPages = 0;
  bool _isDocumentLoaded = false;
  bool _hasLoadError = false;
  String? _loadErrorMessage;

  bool _isContinuous = true;
  ReadingMode _readingMode = ReadingMode.light;
  bool _isFullScreen = false;
  final Set<int> _bookmarkedPages = {};

  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  PdfTextSearchResult? _searchResult;
  int _currentMatchIndex = 0;
  int _totalMatches = 0;
  bool _isSearching = false;

  double _zoomLevel = 1.0;
  bool _hasStoragePermission = false;

  // Device PDF Library state
  List<PdfDocumentItem> _devicePdfs = [];
  bool _isScanningDevicePdfs = false;
  String _homeSearchFilter = '';
  final TextEditingController _homeSearchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pdfViewerController = PdfViewerController();
    _currentDocument = widget.initialDocument;
    _totalPages = _currentDocument?.pageCount ?? 0;

    // Ask for access to device PDF files and load documents when opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptPdfAccess();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeScrollController.dispose();
    _homeSearchController.dispose();
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    _searchController.dispose();
    _pdfViewerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    final hasPerm = await PermissionService.instance.hasStoragePermission();
    if (mounted) {
      final wasGranted = _hasStoragePermission;
      setState(() => _hasStoragePermission = hasPerm);
      if (hasPerm && (!wasGranted || _devicePdfs.isEmpty) && _currentDocument == null) {
        _scanAndLoadDevicePdfs();
      }
    }
  }

  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    setState(() {
      _totalPages = details.document.pages.count;
      _currentDocument?.pageCount = _totalPages;
      _isDocumentLoaded = true;
      _hasLoadError = false;
      _loadErrorMessage = null;
      _currentPage = 1;
    });
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    setState(() {
      _currentPage = details.newPageNumber;
    });
  }

  void _onDocumentLoadFailed(PdfDocumentLoadFailedDetails details) {
    setState(() {
      _isDocumentLoaded = false;
      _hasLoadError = true;
      _loadErrorMessage = details.description;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Load failed: ${details.description}')),
    );
  }

  void _jumpToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _totalPages) {
      _pdfViewerController.jumpToPage(pageNumber);
      setState(() {
        _currentPage = pageNumber;
      });
    }
  }

  void _toggleBookmark(int pageNumber) {
    setState(() {
      if (_bookmarkedPages.contains(pageNumber)) {
        _bookmarkedPages.remove(pageNumber);
        _showNotification('Bookmark removed for Page $pageNumber');
      } else {
        _bookmarkedPages.add(pageNumber);
        _showNotification('Page $pageNumber bookmarked');
      }
    });
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showThumbnailSheet() {
    if (_totalPages <= 0) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PageThumbnailSheet(
        currentPage: _currentPage,
        totalPages: _totalPages,
        bookmarkedPages: _bookmarkedPages,
        onPageSelected: _jumpToPage,
        onBookmarkToggled: (page) {
          setState(() {
            if (_bookmarkedPages.contains(page)) {
              _bookmarkedPages.remove(page);
            } else {
              _bookmarkedPages.add(page);
            }
          });
        },
      ),
    );
  }


  Future<void> _scanAndLoadDevicePdfs() async {
    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = hasPermission);
    }
    if (!hasPermission) return;

    if (mounted) setState(() => _isScanningDevicePdfs = true);

    try {
      final pdfs = await DevicePdfService.instance.scanCommonPdfDirectories();
      if (mounted) {
        setState(() {
          _devicePdfs = pdfs;
          _isScanningDevicePdfs = false;
        });
      }
    } catch (e) {
      debugPrint('Error scanning PDFs: $e');
      if (mounted) {
        setState(() => _isScanningDevicePdfs = false);
      }
    }
  }

  void _openDocument(PdfDocumentItem doc) {
    setState(() {
      _currentDocument = doc;
      _isDocumentLoaded = false;
      _hasLoadError = false;
      _loadErrorMessage = null;
      _currentPage = 1;
      _totalPages = doc.pageCount;
      _bookmarkedPages.clear();
      _closeSearch();
    });
  }

  Future<void> _promptRenameDocument(PdfDocumentItem doc) async {
    final updatedDoc = await RenamePdfDialog.show(context, doc);
    if (updatedDoc != null && mounted) {
      setState(() {
        final index = _devicePdfs.indexWhere(
          (item) => item.id == doc.id || (item.path.isNotEmpty && item.path == doc.path),
        );
        if (index != -1) {
          _devicePdfs[index] = updatedDoc;
        }
        if (_currentDocument != null &&
            (_currentDocument!.id == doc.id ||
                (_currentDocument!.path.isNotEmpty && _currentDocument!.path == doc.path))) {
          _currentDocument = updatedDoc;
        }
      });
      _showNotification('Renamed to "${updatedDoc.title}"');
    }
  }

  Future<void> _shareDocument(PdfDocumentItem doc) async {
    try {
      await DevicePdfService.instance.sharePdf(doc);
    } catch (e) {
      if (mounted) {
        _showNotification('Could not share document: $e');
      }
    }
  }

  Future<void> _checkAndPromptPdfAccess() async {
    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = hasPermission);
    }

    if (hasPermission) {
      await _scanAndLoadDevicePdfs();
      return;
    }

    if (mounted) {
      final result = await StoragePermissionDialog.show(context);
      if (!mounted) return;

      final updatedPermission = await PermissionService.instance.hasStoragePermission();
      if (mounted) {
        setState(() => _hasStoragePermission = updatedPermission);
      }

      if (updatedPermission || result == StoragePermissionDialogResult.granted) {
        _showNotification('Access granted! Scanning device for PDFs...');
        await _scanAndLoadDevicePdfs();
      } else if (result == StoragePermissionDialogResult.pickFile) {
        await _pickAndOpenDevicePdf();
      }
    }
  }

  Future<void> _promptPermissionOrPick() async {
    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (!hasPermission && mounted) {
      final result = await StoragePermissionDialog.show(context);
      if (!mounted) return;

      final updated = await PermissionService.instance.hasStoragePermission();
      if (mounted) {
        setState(() => _hasStoragePermission = updated);
      }

      if (updated || result == StoragePermissionDialogResult.granted) {
        await _scanAndLoadDevicePdfs();
      } else if (result == StoragePermissionDialogResult.pickFile) {
        await _pickAndOpenDevicePdf();
      }
    } else {
      await _pickAndOpenDevicePdf();
    }
  }

  Future<void> _pickAndOpenDevicePdf() async {
    try {
      final item = await DevicePdfService.instance.pickPdfFile();
      if (item != null && mounted) {
        if (!_devicePdfs.any((d) => d.id == item.id || (d.path.isNotEmpty && d.path == item.path))) {
          _devicePdfs.insert(0, item);
        }
        _openDocument(item);
        _showNotification('Opened: ${item.title}');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Failed to open PDF: $e');
      }
    }
  }

  void _startSearch(String query) {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);

    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult = _pdfViewerController.searchText(query);
    _searchResult?.addListener(_onSearchResultChanged);
  }

  void _onSearchResultChanged() {
    if (mounted) {
      setState(() {
        _isSearching = false;
        _currentMatchIndex = _searchResult?.currentInstanceIndex ?? 0;
        _totalMatches = _searchResult?.totalInstanceCount ?? 0;
      });
    }
  }

  void _nextMatch() {
    _searchResult?.nextInstance();
    setState(() {
      _currentMatchIndex = _searchResult?.currentInstanceIndex ?? 0;
    });
  }

  void _previousMatch() {
    _searchResult?.previousInstance();
    setState(() {
      _currentMatchIndex = _searchResult?.currentInstanceIndex ?? 0;
    });
  }

  void _closeSearch() {
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    _searchController.clear();
    setState(() {
      _isSearchOpen = false;
      _searchResult = null;
      _currentMatchIndex = 0;
      _totalMatches = 0;
      _isSearching = false;
    });
  }

  void _zoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel + 0.25).clamp(1.0, 4.0);
      _pdfViewerController.zoomLevel = _zoomLevel;
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel - 0.25).clamp(1.0, 4.0);
      _pdfViewerController.zoomLevel = _zoomLevel;
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
      _pdfViewerController.zoomLevel = 1.0;
    });
  }

  Widget _buildHomeDocumentListView(bool isDark) {
    final theme = Theme.of(context);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryColor = theme.colorScheme.primary;

    final query = _homeSearchFilter.trim().toLowerCase();
    final filteredDocs = _devicePdfs.where((doc) {
      if (query.isEmpty) return true;
      return doc.title.toLowerCase().contains(query) ||
          doc.subtitle.toLowerCase().contains(query) ||
          doc.path.toLowerCase().contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: _scanAndLoadDevicePdfs,
      color: primaryColor,
      child: CustomScrollView(
        key: const PageStorageKey<String>('home_pdf_library_scroll'),
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _homeSearchController,
                      onChanged: (val) => setState(() => _homeSearchFilter = val),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search PDF documents by name or folder...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                        suffixIcon: _homeSearchFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _homeSearchController.clear();
                                  setState(() => _homeSearchFilter = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Quick Action: Browse any folder via system file picker
                  InkWell(
                    onTap: _pickAndOpenDevicePdf,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.folder_open_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Browse Any PDF File',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Open files from Google Drive, SD Card & custom folders',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Permission required notice banner (if not yet granted)
                  if (!_hasStoragePermission) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Storage Permission Needed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Grant permission to list all PDF documents on your phone automatically.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _promptPermissionOrPick,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Allow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'PDF DOCUMENTS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${filteredDocs.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: _isScanningDevicePdfs
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                size: 20,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                        tooltip: 'Rescan Storage',
                        onPressed: _isScanningDevicePdfs ? null : _scanAndLoadDevicePdfs,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Scanning indicator or Empty state or PDF list
          if (_isScanningDevicePdfs && _devicePdfs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryColor),
                    const SizedBox(height: 16),
                    Text(
                      'Scanning device for PDF files...',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredDocs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _homeSearchFilter.isNotEmpty ? Icons.search_off_rounded : Icons.description_outlined,
                          size: 40,
                          color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _homeSearchFilter.isNotEmpty ? 'No Matching PDFs Found' : 'No PDFs Found in Common Folders',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _homeSearchFilter.isNotEmpty
                            ? 'Try a different search keyword.'
                            : 'Documents in Downloads, Documents or WhatsApp will appear here. You can also pick a PDF from any folder directly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _pickAndOpenDevicePdf,
                        icon: const Icon(Icons.file_open_rounded, size: 18),
                        label: const Text('Browse Files Directly'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = filteredDocs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _openDocument(doc),
                        onLongPress: () => _promptRenameDocument(doc),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: Colors.redAccent,
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
                                      doc.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      doc.subtitle,
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
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                tooltip: 'Document Options',
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: borderColor),
                                ),
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                onSelected: (action) {
                                  if (action == 'open') {
                                    _openDocument(doc);
                                  } else if (action == 'rename') {
                                    _promptRenameDocument(doc);
                                  } else if (action == 'share') {
                                    _shareDocument(doc);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'open',
                                    child: Row(
                                      children: [
                                        Icon(Icons.file_open_rounded, size: 18, color: primaryColor),
                                        const SizedBox(width: 10),
                                        const Text('Open'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(Icons.drive_file_rename_outline_rounded, size: 18, color: Colors.blueAccent),
                                        SizedBox(width: 10),
                                        Text('Rename PDF'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'share',
                                    child: Row(
                                      children: [
                                        Icon(Icons.share_rounded, size: 18, color: Colors.teal),
                                        SizedBox(width: 10),
                                        Text('Share PDF'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: filteredDocs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_currentDocument == null) {
      return _buildHomeDocumentListView(isDark);
    }

    final doc = _currentDocument!;
    final key = ValueKey('${doc.id}_${doc.path}_$_isContinuous');
    final layoutMode = _isContinuous ? PdfPageLayoutMode.continuous : PdfPageLayoutMode.single;

    Widget viewer;
    switch (doc.type) {
      case PdfSourceType.file:
        viewer = SfPdfViewer.file(
          File(doc.path),
          key: key,
          controller: _pdfViewerController,
          pageLayoutMode: layoutMode,
          scrollDirection: PdfScrollDirection.vertical,
          enableDoubleTapZooming: true,
          enableTextSelection: false,
          interactionMode: PdfInteractionMode.pan,
          maxZoomLevel: 3.5,
          onTap: (details) => setState(() => _isFullScreen = !_isFullScreen),
          onDocumentLoaded: _onDocumentLoaded,
          onPageChanged: _onPageChanged,
          onDocumentLoadFailed: _onDocumentLoadFailed,
        );
        break;

      case PdfSourceType.memory:
        viewer = SfPdfViewer.memory(
          doc.bytes!,
          key: key,
          controller: _pdfViewerController,
          pageLayoutMode: layoutMode,
          scrollDirection: PdfScrollDirection.vertical,
          enableDoubleTapZooming: true,
          enableTextSelection: false,
          interactionMode: PdfInteractionMode.pan,
          maxZoomLevel: 3.5,
          onTap: (details) => setState(() => _isFullScreen = !_isFullScreen),
          onDocumentLoaded: _onDocumentLoaded,
          onPageChanged: _onPageChanged,
          onDocumentLoadFailed: _onDocumentLoadFailed,
        );
        break;

      case PdfSourceType.asset:
        viewer = SfPdfViewer.asset(
          doc.path,
          key: key,
          controller: _pdfViewerController,
          pageLayoutMode: layoutMode,
          scrollDirection: PdfScrollDirection.vertical,
          enableDoubleTapZooming: true,
          enableTextSelection: false,
          interactionMode: PdfInteractionMode.pan,
          maxZoomLevel: 3.5,
          onTap: (details) => setState(() => _isFullScreen = !_isFullScreen),
          onDocumentLoaded: _onDocumentLoaded,
          onPageChanged: _onPageChanged,
          onDocumentLoadFailed: _onDocumentLoadFailed,
        );
        break;

      case PdfSourceType.network:
        viewer = SfPdfViewer.network(
          doc.path,
          key: key,
          controller: _pdfViewerController,
          pageLayoutMode: layoutMode,
          scrollDirection: PdfScrollDirection.vertical,
          enableDoubleTapZooming: true,
          enableTextSelection: false,
          interactionMode: PdfInteractionMode.pan,
          maxZoomLevel: 3.5,
          onTap: (details) => setState(() => _isFullScreen = !_isFullScreen),
          onDocumentLoaded: _onDocumentLoaded,
          onPageChanged: _onPageChanged,
          onDocumentLoadFailed: _onDocumentLoadFailed,
        );
        break;
    }

    if (_readingMode == ReadingMode.night) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(AppTheme.nightModeMatrix),
        child: viewer,
      );
    } else if (_readingMode == ReadingMode.sepia) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(AppTheme.sepiaModeMatrix),
        child: viewer,
      );
    }

    return viewer;
  }

  Color _canvasBackgroundColor(bool isDark) {
    switch (_readingMode) {
      case ReadingMode.night:
        return const Color(0xFF0F172A);
      case ReadingMode.sepia:
        return const Color(0xFFFBF0D9);
      case ReadingMode.light:
        return isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final barBg = isDark ? const Color(0xFF151C2C) : Colors.white;

    return PopScope(
      canPop: !_isSearchOpen && !_isFullScreen && _currentDocument == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchOpen) {
          _closeSearch();
        } else if (_isFullScreen) {
          setState(() => _isFullScreen = false);
        } else if (_currentDocument != null) {
          setState(() => _currentDocument = null);
        }
      },
      child: Scaffold(
        backgroundColor: _canvasBackgroundColor(isDark),
        appBar: _isFullScreen
            ? null
            : (_isSearchOpen
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: SafeArea(
                      child: SearchBarOverlay(
                        controller: _searchController,
                        currentMatchIndex: _currentMatchIndex,
                        totalMatches: _totalMatches,
                        isSearching: _isSearching,
                        onSearchSubmitted: _startSearch,
                        onNextMatch: _nextMatch,
                        onPreviousMatch: _previousMatch,
                        onClose: _closeSearch,
                      ),
                    ),
                  )
                : (_currentDocument == null
                    ? AppBar(
                        backgroundColor: barBg,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(1),
                          child: Container(
                            height: 1,
                            color: borderColor,
                          ),
                        ),
                        leading: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/icon/app_logo.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MYPDF',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              _isScanningDevicePdfs
                                  ? 'Scanning device storage...'
                                  : (_hasStoragePermission
                                      ? '${_devicePdfs.length} PDFs on Device'
                                      : 'Storage access required'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          IconButton(
                            icon: _isScanningDevicePdfs
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            tooltip: 'Scan Storage for PDFs',
                            onPressed: _isScanningDevicePdfs ? null : _scanAndLoadDevicePdfs,
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open_rounded),
                            tooltip: 'Browse Any PDF',
                            onPressed: _pickAndOpenDevicePdf,
                          ),
                          const SizedBox(width: 4),
                        ],
                      )
                    : AppBar(
                        backgroundColor: barBg,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        bottom: PreferredSize(
                          preferredSize: const Size.fromHeight(1),
                          child: Container(
                            height: 1,
                            color: borderColor,
                          ),
                        ),
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'Back to Library',
                          onPressed: () => setState(() => _currentDocument = null),
                        ),
                        title: InkWell(
                          onTap: () => _promptRenameDocument(_currentDocument!),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _currentDocument!.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 13,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                  ],
                                ),
                                Text(
                                  _totalPages > 0
                                      ? 'Page $_currentPage of $_totalPages | ${_currentDocument!.fileSize ?? "Document"}'
                                      : (_hasLoadError ? 'Error loading' : 'Loading document...'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.share_rounded),
                            tooltip: 'Share PDF',
                            onPressed: () {
                              if (_currentDocument != null) {
                                _shareDocument(_currentDocument!);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.search_rounded),
                            tooltip: 'Search in Document',
                            onPressed: () => setState(() => _isSearchOpen = true),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded),
                            tooltip: 'Menu Options',
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: borderColor),
                            ),
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            elevation: 10,
                            onSelected: (action) {
                              switch (action) {
                                case 'share':
                                  if (_currentDocument != null) {
                                    _shareDocument(_currentDocument!);
                                  }
                                  break;
                                case 'rename':
                                  if (_currentDocument != null) {
                                    _promptRenameDocument(_currentDocument!);
                                  }
                                  break;
                                case 'thumbnails':
                                  _showThumbnailSheet();
                                  break;
                                case 'scroll_mode':
                                  setState(() {
                                    _isContinuous = !_isContinuous;
                                    _showNotification(_isContinuous
                                        ? 'Switched to Continuous Scroll Mode'
                                        : 'Switched to Single Page Mode');
                                  });
                                  break;
                                case 'bookmark':
                                  _toggleBookmark(_currentPage);
                                  break;
                                case 'mode_light':
                                  setState(() => _readingMode = ReadingMode.light);
                                  _showNotification('Day / Light mode enabled');
                                  break;
                                case 'mode_sepia':
                                  setState(() => _readingMode = ReadingMode.sepia);
                                  _showNotification('Warm Sepia mode enabled');
                                  break;
                                case 'mode_night':
                                  setState(() => _readingMode = ReadingMode.night);
                                  _showNotification('Night mode enabled');
                                  break;
                                case 'zoom_in':
                                  _zoomIn();
                                  break;
                                case 'zoom_out':
                                  _zoomOut();
                                  break;
                                case 'zoom_reset':
                                  _resetZoom();
                                  break;
                                case 'library':
                                  setState(() => _currentDocument = null);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    Icon(Icons.share_rounded, size: 20, color: Colors.teal),
                                    SizedBox(width: 12),
                                    Text('Share PDF'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.drive_file_rename_outline_rounded, size: 20, color: Colors.blueAccent),
                                    SizedBox(width: 12),
                                    Text('Rename PDF'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'thumbnails',
                                child: Row(
                                  children: [
                                    Icon(Icons.grid_view_rounded, size: 20, color: theme.colorScheme.primary),
                                    const SizedBox(width: 12),
                                    const Text('Page Thumbnails'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'scroll_mode',
                                child: Row(
                                  children: [
                                    Icon(
                                      _isContinuous ? Icons.auto_stories_rounded : Icons.view_day_rounded,
                                      size: 20,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(_isContinuous ? 'Single Page Mode' : 'Continuous Scroll Mode'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'bookmark',
                                child: Row(
                                  children: [
                                    Icon(
                                      _bookmarkedPages.contains(_currentPage)
                                          ? Icons.bookmark_remove_rounded
                                          : Icons.bookmark_add_rounded,
                                      size: 20,
                                      color: _bookmarkedPages.contains(_currentPage)
                                          ? Colors.amber
                                          : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(_bookmarkedPages.contains(_currentPage)
                                        ? 'Remove Bookmark (Page $_currentPage)'
                                        : 'Bookmark Page $_currentPage'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'mode_light',
                                child: Row(
                                  children: [
                                    const Icon(Icons.light_mode_rounded, size: 20, color: Colors.orangeAccent),
                                    const SizedBox(width: 12),
                                    const Expanded(child: Text('Light Mode')),
                                    if (_readingMode == ReadingMode.light)
                                      Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'mode_sepia',
                                child: Row(
                                  children: [
                                    const Icon(Icons.coffee_rounded, size: 20, color: Colors.amber),
                                    const SizedBox(width: 12),
                                    const Expanded(child: Text('Warm Sepia Mode')),
                                    if (_readingMode == ReadingMode.sepia)
                                      Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'mode_night',
                                child: Row(
                                  children: [
                                    const Icon(Icons.dark_mode_rounded, size: 20, color: Colors.indigoAccent),
                                    const SizedBox(width: 12),
                                    const Expanded(child: Text('Night Inverted Mode')),
                                    if (_readingMode == ReadingMode.night)
                                      Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'zoom_in',
                                child: Row(
                                  children: [
                                    Icon(Icons.zoom_in_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                    const SizedBox(width: 12),
                                    Text('Zoom In (${((_zoomLevel + 0.25) * 100).round()}%)'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'zoom_out',
                                child: Row(
                                  children: [
                                    Icon(Icons.zoom_out_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                    const SizedBox(width: 12),
                                    Text('Zoom Out (${((_zoomLevel - 0.25).clamp(1.0, 4.0) * 100).round()}%)'),
                                  ],
                                ),
                              ),
                              if (_zoomLevel != 1.0)
                                PopupMenuItem(
                                  value: 'zoom_reset',
                                  child: Row(
                                    children: [
                                      Icon(Icons.restart_alt_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                      const SizedBox(width: 12),
                                      const Text('Reset Zoom (100%)'),
                                    ],
                                  ),
                                ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'library',
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_open_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                    const SizedBox(width: 12),
                                    const Text('Back to PDF Library'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),
                        ],
                      ))),
        body: Stack(
          children: [
            // Home library view is kept alive offstage so scroll position is permanently preserved
            Offstage(
              offstage: _currentDocument != null,
              child: TickerMode(
                enabled: _currentDocument == null,
                child: _buildHomeDocumentListView(isDark),
              ),
            ),
            if (_currentDocument != null) ...[
              _buildPdfView(),
              if (!_isDocumentLoaded && !_hasLoadError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Rendering document...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_hasLoadError)
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Failed to open document',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _loadErrorMessage ?? 'Unknown error occurred',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Open Another PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _promptPermissionOrPick,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
