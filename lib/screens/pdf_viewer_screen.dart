import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<PdfDocumentItem> _filteredDocs = [];
  bool _isScanningDevicePdfs = false;
  String _homeSearchFilter = '';
  final TextEditingController _homeSearchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();
  final Set<String> _selectedDocumentIds = {};
  bool get _isSelectionMode => _selectedDocumentIds.isNotEmpty;

  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDocumentOpenTime = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, int> _readingProgress = {};
  File? _cachedFile;
  Timer? _searchDebounceTimer;
  Timer? _homeSearchDebounceTimer;

  void _updateFilteredDocs() {
    final query = _homeSearchFilter.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredDocs = List.unmodifiable(_devicePdfs);
    } else {
      _filteredDocs = _devicePdfs.where((doc) => doc.matchesQuery(query)).toList();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pdfViewerController = PdfViewerController();
    _currentDocument = widget.initialDocument;
    _totalPages = _currentDocument?.pageCount ?? 0;
    _currentPageNotifier.value = _currentPage;
    _updateFilteredDocs();

    _loadCachedPdfLibrary();
    _setupIntentChannel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptPdfAccess();
    });
  }

  static const _intentChannel = MethodChannel('com.example.pdf_viewer/intent');

  void _setupIntentChannel() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPdfOpened') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty && mounted) {
          _openDocumentFromPath(path);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _intentChannel.invokeMethod<String>('getInitialPdf').then((path) {
        if (path != null && path.isNotEmpty && mounted) {
          _openDocumentFromPath(path);
        }
      }).catchError((_) {});
    });
  }

  void _openDocumentFromPath(String path) {
    if (!path.toLowerCase().endsWith('.pdf')) {
      debugPrint('Security warning: Refused to open non-PDF file: $path');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) return;

    final fileName = file.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'Document.pdf');
    int sizeInBytes = 0;
    DateTime? modified;
    try {
      final stat = file.statSync();
      sizeInBytes = stat.size;
      modified = stat.modified;
    } catch (_) {}

    final formattedSize = sizeInBytes >= 1024 * 1024
        ? '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';

    final docItem = PdfDocumentItem(
      id: file.path,
      title: fileName,
      subtitle: 'External File | $formattedSize',
      type: PdfSourceType.file,
      path: file.path,
      fileSize: formattedSize,
      lastModified: modified,
    );

    if (!_devicePdfs.any((d) => d.id == docItem.id || (d.path.isNotEmpty && d.path == docItem.path))) {
      _devicePdfs.insert(0, docItem);
      _updateFilteredDocs();
      DevicePdfService.instance.saveCachedPdfs(_devicePdfs);
    }
    _openDocument(docItem);
  }

  Future<void> _loadCachedPdfLibrary() async {
    final cached = await DevicePdfService.instance.loadCachedPdfs();
    final progress = await DevicePdfService.instance.loadReadingProgress();
    if (mounted) {
      setState(() {
        _readingProgress = progress;
        if (cached.isNotEmpty && _devicePdfs.isEmpty) {
          _devicePdfs = cached;
          _updateFilteredDocs();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _homeSearchDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _currentPageNotifier.dispose();
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveCurrentReadingProgress();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _saveCurrentReadingProgress() {
    if (_currentDocument != null) {
      _readingProgress[_currentDocument!.id] = _currentPage;
      DevicePdfService.instance.saveReadingProgress(_readingProgress);
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

      final savedPage = _currentDocument != null ? (_readingProgress[_currentDocument!.id] ?? 1) : 1;
      if (savedPage > 1 && savedPage <= _totalPages) {
        _currentPage = savedPage;
        _currentPageNotifier.value = savedPage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _pdfViewerController.jumpToPage(savedPage);
          } catch (_) {}
        });
      } else {
        _currentPage = 1;
        _currentPageNotifier.value = 1;
      }
    });
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    _currentPage = details.newPageNumber;
    _currentPageNotifier.value = details.newPageNumber;
    if (_currentDocument != null) {
      _readingProgress[_currentDocument!.id] = details.newPageNumber;
    }
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
      _currentPage = pageNumber;
      _currentPageNotifier.value = pageNumber;
    }
  }

  void _toggleBookmark(int pageNumber) {
    HapticFeedback.mediumImpact();
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
          _updateFilteredDocs();
          _isScanningDevicePdfs = false;
        });
        // Save scan result to persistent cache asynchronously
        DevicePdfService.instance.saveCachedPdfs(pdfs);
      }
    } catch (e) {
      debugPrint('Error scanning PDFs: $e');
      if (mounted) {
        setState(() => _isScanningDevicePdfs = false);
      }
    }
  }

  void _openDocument(PdfDocumentItem doc) {
    if (_isSelectionMode) {
      _toggleSelect(doc);
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastDocumentOpenTime).inMilliseconds < 350) {
      return;
    }
    _lastDocumentOpenTime = now;

    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    _searchController.clear();
    _isSearchOpen = false;
    _searchResult = null;
    _currentMatchIndex = 0;
    _totalMatches = 0;
    _isSearching = false;

    try {
      _pdfViewerController.dispose();
    } catch (_) {}

    _cachedFile = doc.type == PdfSourceType.file && doc.path.isNotEmpty ? File(doc.path) : null;
    _pdfViewerController = PdfViewerController();

    final savedPage = _readingProgress[doc.id] ?? 1;
    _currentPage = savedPage;
    _currentPageNotifier.value = savedPage;
    _totalPages = doc.pageCount;
    _bookmarkedPages.clear();

    setState(() {
      _currentDocument = doc;
      _isDocumentLoaded = false;
      _hasLoadError = false;
      _loadErrorMessage = null;
    });
  }

  void _closeDocument() {
    if (_currentDocument != null) {
      _readingProgress[_currentDocument!.id] = _currentPage;
      DevicePdfService.instance.saveReadingProgress(_readingProgress);
    }
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.clear();
    _searchController.clear();
    _isSearchOpen = false;
    _searchResult = null;
    _cachedFile = null;

    try {
      _pdfViewerController.dispose();
    } catch (_) {}
    _pdfViewerController = PdfViewerController();

    setState(() {
      _currentDocument = null;
      _isDocumentLoaded = false;
      _hasLoadError = false;
      _loadErrorMessage = null;
      _isFullScreen = false;
    });
  }

  void _toggleSelect(PdfDocumentItem doc) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedDocumentIds.contains(doc.id)) {
        _selectedDocumentIds.remove(doc.id);
      } else {
        _selectedDocumentIds.add(doc.id);
      }
    });
  }

  void _selectAll(List<PdfDocumentItem> docs) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedDocumentIds.length == docs.length) {
        _selectedDocumentIds.clear();
      } else {
        _selectedDocumentIds.addAll(docs.map((d) => d.id));
      }
    });
  }

  void _clearSelection() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDocumentIds.clear();
    });
  }

  Future<void> _shareSelectedDocuments() async {
    final selectedDocs = _devicePdfs.where((d) => _selectedDocumentIds.contains(d.id)).toList();
    if (selectedDocs.isEmpty) return;

    try {
      await DevicePdfService.instance.sharePdfs(selectedDocs);
    } catch (e) {
      if (mounted) {
        _showNotification('Could not share selected files: $e');
      }
    }
  }

  Future<void> _renameSingleSelected() async {
    if (_selectedDocumentIds.length != 1) return;
    final selectedId = _selectedDocumentIds.first;
    final index = _devicePdfs.indexWhere((d) => d.id == selectedId);
    if (index != -1) {
      await _promptRenameDocument(_devicePdfs[index]);
    }
    _clearSelection();
  }

  Future<void> _promptDeleteDocuments(List<PdfDocumentItem> docsToDelete) async {
    if (docsToDelete.isEmpty) return;

    final count = docsToDelete.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1 ? 'Delete PDF?' : 'Delete $count PDFs?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            count == 1
                ? 'Are you sure you want to permanently delete "${docsToDelete.first.title}" from your device storage? This action cannot be undone.'
                : 'Are you sure you want to permanently delete these $count selected documents from your device storage? This action cannot be undone.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final idsToDelete = docsToDelete.map((d) => d.id).toSet();
      final pathsToDelete = docsToDelete.map((d) => d.path).where((p) => p.isNotEmpty).toSet();
      final deletedCount = await DevicePdfService.instance.deletePdfs(docsToDelete);

      setState(() {
        _devicePdfs.removeWhere((d) => idsToDelete.contains(d.id) || pathsToDelete.contains(d.path));
        _selectedDocumentIds.removeWhere((id) => idsToDelete.contains(id));
        _updateFilteredDocs();

        if (_currentDocument != null &&
            (idsToDelete.contains(_currentDocument!.id) || pathsToDelete.contains(_currentDocument!.path))) {
          _closeDocument();
        }
      });

      DevicePdfService.instance.saveCachedPdfs(_devicePdfs);

      _showNotification(
        deletedCount == 1 ? 'Document deleted' : '$deletedCount documents deleted',
      );
    }
  }

  Future<void> _promptDeleteSelectedDocuments() async {
    final selectedDocs = _devicePdfs.where((d) => _selectedDocumentIds.contains(d.id)).toList();
    await _promptDeleteDocuments(selectedDocs);
  }

  Future<void> _promptDeleteSingleDocument(PdfDocumentItem doc) async {
    await _promptDeleteDocuments([doc]);
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
          _updateFilteredDocs();
        }
        if (_currentDocument != null &&
            (_currentDocument!.id == doc.id ||
                (_currentDocument!.path.isNotEmpty && _currentDocument!.path == doc.path))) {
          _currentDocument = updatedDoc;
          _cachedFile = updatedDoc.type == PdfSourceType.file && updatedDoc.path.isNotEmpty
              ? File(updatedDoc.path)
              : null;
        }
      });
      DevicePdfService.instance.saveCachedPdfs(_devicePdfs);
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

  Future<void> _checkAndPromptPdfAccess({bool openPickerIfGranted = false}) async {
    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = hasPermission);
    }

    if (hasPermission) {
      if (openPickerIfGranted) {
        await _pickAndOpenDevicePdf();
      } else {
        await _scanAndLoadDevicePdfs();
      }
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

  Future<void> _promptPermissionOrPick() => _checkAndPromptPdfAccess(openPickerIfGranted: true);

  Future<void> _pickAndOpenDevicePdf() async {
    try {
      final item = await DevicePdfService.instance.pickPdfFile();
      if (item != null && mounted) {
        if (!_devicePdfs.any((d) => d.id == item.id || (d.path.isNotEmpty && d.path == item.path))) {
          _devicePdfs.insert(0, item);
          _updateFilteredDocs();
          DevicePdfService.instance.saveCachedPdfs(_devicePdfs);
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

  void _onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResult?.removeListener(_onSearchResultChanged);
      _searchResult?.clear();
      setState(() {
        _searchResult = null;
        _currentMatchIndex = 0;
        _totalMatches = 0;
        _isSearching = false;
      });
      return;
    }
    if (trimmed.length < 2) return;
    _searchDebounceTimer = Timer(const Duration(milliseconds: 380), () {
      if (mounted) {
        _startSearch(trimmed);
      }
    });
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
    _searchDebounceTimer?.cancel();
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

  void _onHomeSearchChanged(String val) {
    _homeSearchFilter = val;
    _homeSearchDebounceTimer?.cancel();
    if (val.isEmpty) {
      _updateFilteredDocs();
      setState(() {});
    } else {
      _homeSearchDebounceTimer = Timer(const Duration(milliseconds: 180), () {
        if (mounted) {
          setState(() {
            _updateFilteredDocs();
          });
        }
      });
    }
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

    final filteredDocs = _filteredDocs;

    return RefreshIndicator(
      onRefresh: _scanAndLoadDevicePdfs,
      color: primaryColor,
      child: Scrollbar(
        controller: _homeScrollController,
        interactive: true,
        thickness: 6.0,
        radius: const Radius.circular(8),
        child: CustomScrollView(
          key: const PageStorageKey<String>('home_pdf_library_scroll'),
          controller: _homeScrollController,
          physics: const FastMomentumScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
          if (!_hasStoragePermission)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
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
              ),
            ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedSearchBarDelegate(
              height: 68.0,
              backgroundColor: _canvasBackgroundColor(isDark),
              child: Container(
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
                  onChanged: _onHomeSearchChanged,
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
                              _onHomeSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'PDF DOCUMENTS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
            ),
          ),

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
              sliver: SliverPrototypeExtentList(
                prototypeItem: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(width: 0.8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 44, height: 44),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Prototype Document Title.pdf',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    'Downloads | 1.0 MB',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 24, height: 24),
                      ],
                    ),
                  ),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = filteredDocs[index];
                    final isSelected = _selectedDocumentIds.contains(doc.id);
                    final savedPage = _readingProgress[doc.id] ?? 1;
                    final hasProgress = savedPage > 1;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelect(doc);
                          } else {
                            _openDocument(doc);
                          }
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          _toggleSelect(doc);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.08)
                                : cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? primaryColor : borderColor,
                              width: isSelected ? 2.0 : 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? primaryColor.withValues(alpha: isDark ? 0.25 : 0.12)
                                    : Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                                blurRadius: isSelected ? 10 : 8,
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
                                  color: isSelected
                                      ? primaryColor
                                      : (_isSelectionMode
                                          ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                                          : primaryColor.withValues(alpha: 0.12)),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: _isSelectionMode
                                      ? Icon(
                                          isSelected ? Icons.check_rounded : Icons.radio_button_unchecked_rounded,
                                          color: isSelected ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                                          size: 22,
                                        )
                                      : Icon(
                                          Icons.picture_as_pdf_rounded,
                                          color: primaryColor,
                                          size: 24,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      doc.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            doc.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.3,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                        if (hasProgress) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.10),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              doc.pageCount > 0 ? 'P. $savedPage / ${doc.pageCount}' : 'P. $savedPage',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: primaryColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (_isSelectionMode)
                                Icon(
                                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  color: isSelected ? primaryColor : (isDark ? Colors.white24 : Colors.black26),
                                  size: 22,
                                )
                              else
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
                                    } else if (action == 'select') {
                                      _toggleSelect(doc);
                                    } else if (action == 'rename') {
                                      _promptRenameDocument(doc);
                                    } else if (action == 'share') {
                                      _shareDocument(doc);
                                    } else if (action == 'delete') {
                                      _promptDeleteSingleDocument(doc);
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
                                      value: 'select',
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.indigoAccent),
                                          SizedBox(width: 10),
                                          Text('Select'),
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
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                          SizedBox(width: 10),
                                          Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
      ),
    );
  }

  void _onViewerTap(PdfGestureDetails details) {
    final now = DateTime.now();
    // Guard against accidental tap triggers during pinch-to-zoom or double-tap
    if (now.difference(_lastTapTime).inMilliseconds < 400) return;
    _lastTapTime = now;
    setState(() => _isFullScreen = !_isFullScreen);
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
    if (doc.type == PdfSourceType.memory && doc.bytes != null) {
      viewer = SfPdfViewer.memory(
        doc.bytes!,
        key: key,
        controller: _pdfViewerController,
        pageLayoutMode: layoutMode,
        scrollDirection: PdfScrollDirection.vertical,
        enableDoubleTapZooming: true,
        canShowPaginationDialog: false,
        enableTextSelection: false,
        interactionMode: PdfInteractionMode.pan,
        maxZoomLevel: 4.0,
        onTap: _onViewerTap,
        onDocumentLoaded: _onDocumentLoaded,
        onPageChanged: _onPageChanged,
        onDocumentLoadFailed: _onDocumentLoadFailed,
      );
    } else {
      viewer = SfPdfViewer.file(
        _cachedFile ?? File(doc.path),
        key: key,
        controller: _pdfViewerController,
        pageLayoutMode: layoutMode,
        scrollDirection: PdfScrollDirection.vertical,
        enableDoubleTapZooming: true,
        canShowPaginationDialog: false,
        enableTextSelection: false,
        interactionMode: PdfInteractionMode.pan,
        maxZoomLevel: 4.0,
        onTap: _onViewerTap,
        onDocumentLoaded: _onDocumentLoaded,
        onPageChanged: _onPageChanged,
        onDocumentLoadFailed: _onDocumentLoadFailed,
      );
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
    if (_currentDocument == null) {
      return isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    }
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
      canPop: !_isSearchOpen && !_isFullScreen && _currentDocument == null && !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _clearSelection();
        } else if (_isSearchOpen) {
          _closeSearch();
        } else if (_isFullScreen) {
          setState(() => _isFullScreen = false);
        } else if (_currentDocument != null) {
          _closeDocument();
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
                        onSearchChanged: _onSearchQueryChanged,
                        onNextMatch: _nextMatch,
                        onPreviousMatch: _previousMatch,
                        onClose: _closeSearch,
                      ),
                    ),
                  )
                : (_currentDocument == null
                    ? (_isSelectionMode
                        ? AppBar(
                            backgroundColor: barBg,
                            elevation: 2,
                            scrolledUnderElevation: 0,
                            bottom: PreferredSize(
                              preferredSize: const Size.fromHeight(1),
                              child: Container(
                                height: 1,
                                color: borderColor,
                              ),
                            ),
                            leading: IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Cancel Selection',
                              onPressed: _clearSelection,
                            ),
                            title: Text(
                              '${_selectedDocumentIds.length} selected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            actions: [
                              if (_selectedDocumentIds.length == 1)
                                IconButton(
                                  icon: const Icon(Icons.drive_file_rename_outline_rounded),
                                  tooltip: 'Rename',
                                  onPressed: _renameSingleSelected,
                                ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded),
                                tooltip: 'Share',
                                onPressed: _shareSelectedDocuments,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete',
                                onPressed: _promptDeleteSelectedDocuments,
                              ),
                              IconButton(
                                icon: Icon(
                                  _selectedDocumentIds.length == _devicePdfs.length
                                      ? Icons.deselect_rounded
                                      : Icons.select_all_rounded,
                                ),
                                tooltip: _selectedDocumentIds.length == _devicePdfs.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                onPressed: () => _selectAll(_devicePdfs),
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
                            leading: Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.asset(
                                    'assets/icon/app_logo.png',
                                    width: 32,
                                    height: 32,
                                    cacheWidth: 64,
                                    cacheHeight: 64,
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
                                    fontSize: 18,
                                    letterSpacing: -0.2,
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
                          ))
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
                          onPressed: _closeDocument,
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
                                ValueListenableBuilder<int>(
                                  valueListenable: _currentPageNotifier,
                                  builder: (context, page, _) {
                                    return Text(
                                      _totalPages > 0
                                          ? 'Page $page of $_totalPages'
                                          : (_hasLoadError ? 'Error loading' : 'Loading document...'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                      ),
                                    );
                                  },
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
                                  _closeDocument();
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
        body: _currentDocument == null
            ? _buildHomeDocumentListView(isDark)
            : Stack(
                children: [
                  _buildPdfView(),
                  if (!_isDocumentLoaded && !_hasLoadError)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
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
              ),
      ),
    );
  }
}

class FastMomentumScrollPhysics extends BouncingScrollPhysics {
  const FastMomentumScrollPhysics({super.parent, super.decelerationRate});

  @override
  FastMomentumScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastMomentumScrollPhysics(
      parent: buildParent(ancestor),
      decelerationRate: decelerationRate,
    );
  }

  @override
  double get dragStartDistanceMotionThreshold => 3.5;

  @override
  double get minFlingVelocity => 40.0;

  @override
  double get maxFlingVelocity => 15000.0;

  @override
  double carriedMomentum(double existingVelocity) {
    return existingVelocity.sign *
        math.min(0.0012 * math.pow(existingVelocity.abs(), 1.95).toDouble(), 6000.0);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    return super.createBallisticSimulation(position, velocity * 1.35);
  }
}

class _PinnedSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  _PinnedSearchBarDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchBarDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
