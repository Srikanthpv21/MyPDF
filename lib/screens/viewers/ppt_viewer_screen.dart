import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:open_filex/open_filex.dart';
import '../../models/pdf_document_item.dart';
import '../../services/device_pdf_service.dart';

class PptSlideData {
  final int index;
  final String title;
  final List<String> bulletPoints;
  final List<String> otherTexts;
  final List<Uint8List> images;

  PptSlideData({
    required this.index,
    required this.title,
    required this.bulletPoints,
    required this.otherTexts,
    this.images = const [],
  });
}

class PptViewerScreen extends StatefulWidget {
  final PdfDocumentItem document;

  const PptViewerScreen({
    super.key,
    required this.document,
  });

  @override
  State<PptViewerScreen> createState() => _PptViewerScreenState();
}

class _PptViewerScreenState extends State<PptViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  final List<PptSlideData> _slides = [];
  final PageController _pageController = PageController();
  int _currentSlideIndex = 0;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _loadPptPresentation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _extractPptxSlides(Uint8List bytes) {
    final List<Map<String, dynamic>> results = [];
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find all slide XML files
    final slideEntries = archive.files.where((f) {
      final name = f.name.toLowerCase();
      return name.startsWith('ppt/slides/slide') && name.endsWith('.xml');
    }).toList();

    // Sort slides by numerical index: slide1.xml, slide2.xml...
    final numberedEntries = slideEntries.map((e) {
      final match = RegExp(r'slide(\d+)\.xml').firstMatch(e.name.toLowerCase());
      final num = match != null ? (int.tryParse(match.group(1) ?? '0') ?? 0) : 0;
      return (entry: e, slideNum: num);
    }).toList();

    numberedEntries.sort((a, b) => a.slideNum.compareTo(b.slideNum));

    int slideIdx = 1;
    for (final item in numberedEntries) {
      final xmlStr = utf8.decode(item.entry.content as List<int>, allowMalformed: true);
      final slideMap = _parseSlideXmlMap(xmlStr, slideIdx++);
      results.add(slideMap);
    }

    return results;
  }

  static Map<String, dynamic> _parseSlideXmlMap(String xmlString, int slideIndex) {
    String title = '';
    final List<String> bullets = [];
    final List<String> others = [];

    try {
      final doc = xml.XmlDocument.parse(xmlString);

      // Find shape elements
      for (final sp in doc.findAllElements('p:sp')) {
        final ph = sp.findAllElements('p:ph').firstOrNull;
        final phType = ph?.getAttribute('type')?.toLowerCase() ?? '';

        final textRuns = sp.findAllElements('a:t').map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).toList();
        final combinedText = textRuns.join(' ').trim();

        if (combinedText.isEmpty) continue;

        if (phType.contains('title') || phType.contains('ctrtitle')) {
          if (title.isEmpty) {
            title = combinedText;
          } else {
            others.add(combinedText);
          }
        } else if (phType.contains('body') || phType.contains('sub') || sp.findAllElements('a:buChar').isNotEmpty) {
          // Paragraphs inside body
          for (final p in sp.findAllElements('a:p')) {
            final pText = p.findAllElements('a:t').map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).join(' ').trim();
            if (pText.isNotEmpty) {
              bullets.add(pText);
            }
          }
        } else {
          others.add(combinedText);
        }
      }

      if (title.isEmpty) {
        if (bullets.isNotEmpty) {
          title = bullets.removeAt(0);
        } else if (others.isNotEmpty) {
          title = others.removeAt(0);
        } else {
          title = 'Slide $slideIndex';
        }
      }
    } catch (e) {
      debugPrint('Error parsing slide XML: $e');
      title = 'Slide $slideIndex';
    }

    return {
      'index': slideIndex,
      'title': title,
      'bulletPoints': bullets,
      'otherTexts': others,
    };
  }

  Future<void> _loadPptPresentation() async {
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

      _slides.clear();
      if (pathLower.endsWith('.pptx')) {
        List<Map<String, dynamic>> rawSlides;
        try {
          rawSlides = await Isolate.run(() => _extractPptxSlides(bytes));
        } catch (_) {
          rawSlides = _extractPptxSlides(bytes);
        }

        for (final raw in rawSlides) {
          _slides.add(
            PptSlideData(
              index: raw['index'] as int,
              title: raw['title'] as String,
              bulletPoints: (raw['bulletPoints'] as List<dynamic>).map((e) => e.toString()).toList(),
              otherTexts: (raw['otherTexts'] as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          );
        }

        if (_slides.isEmpty) {
          _slides.add(
            PptSlideData(
              index: 1,
              title: 'Empty Presentation',
              bulletPoints: ['No slides found inside this presentation.'],
              otherTexts: [],
            ),
          );
        }
      } else {
        // Fallback for .ppt binary format
        _slides.add(
          PptSlideData(
            index: 1,
            title: widget.document.title,
            bulletPoints: [
              'Legacy PowerPoint (.ppt) presentation format.',
              'Tap "Open in Office App" above to view full slide animations and transitions.',
            ],
            otherTexts: [],
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFFEA580C); // PPT Orange
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9),
      appBar: _isFullScreen
          ? null
          : AppBar(
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
              title: Column(
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
                        ? 'Loading presentation...'
                        : 'Slide ${_currentSlideIndex + 1} of ${_slides.length}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen_rounded),
                  tooltip: 'Fullscreen Slideshow',
                  onPressed: () => setState(() => _isFullScreen = true),
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
                    'Loading presentation slides...',
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
                          'Presentation Preview Limited',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This PowerPoint presentation could not be parsed inline. You can open it directly in Microsoft PowerPoint, Google Slides, or WPS Office.',
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
              : Stack(
                  children: [
                    Column(
                      children: [
                        // Main Slide Area
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _slides.length,
                            onPageChanged: (idx) => setState(() => _currentSlideIndex = idx),
                            itemBuilder: (context, index) {
                              final slide = _slides[index];
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildSlideCard(slide, isDark, primaryColor, cardBg, borderColor),
                                ),
                              );
                            },
                          ),
                        ),

                        // Bottom Slide Navigation & Thumbnail Rail
                        if (!_isFullScreen)
                          Container(
                            height: 84,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: cardBg,
                              border: Border(top: BorderSide(color: borderColor)),
                            ),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _slides.length,
                              separatorBuilder: (_, index) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final isSelected = _currentSlideIndex == index;
                                final slide = _slides[index];

                                return InkWell(
                                  onTap: () {
                                    _pageController.animateToPage(
                                      index,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 110,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primaryColor.withValues(alpha: 0.15)
                                          : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? primaryColor : borderColor,
                                        width: isSelected ? 2.0 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          slide.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected
                                                ? primaryColor
                                                : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              '#${index + 1}',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? primaryColor : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),

                    // Fullscreen Exit Overlay Button
                    if (_isFullScreen)
                      Positioned(
                        top: 24,
                        right: 24,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                            tooltip: 'Exit Fullscreen',
                            onPressed: () => setState(() => _isFullScreen = false),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildSlideCard(PptSlideData slide, bool isDark, Color primaryColor, Color cardBg, Color borderColor) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slide Title & Index
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    slide.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${slide.index} / ${_slides.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 14),

            // Bullet points & Slide body text
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final bullet in slide.bulletPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 10),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              bullet,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.45,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final other in slide.otherTexts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        other,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
