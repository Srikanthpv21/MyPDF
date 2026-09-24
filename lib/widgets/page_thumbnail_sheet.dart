import 'package:flutter/material.dart';

class PageThumbnailSheet extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final Set<int> bookmarkedPages;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<int> onBookmarkToggled;

  const PageThumbnailSheet({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.bookmarkedPages,
    required this.onPageSelected,
    required this.onBookmarkToggled,
  });

  @override
  State<PageThumbnailSheet> createState() => _PageThumbnailSheetState();
}

class _PageThumbnailSheetState extends State<PageThumbnailSheet> {
  bool _filterBookmarkedOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayedPages = List.generate(
      widget.totalPages,
      (index) => index + 1,
    ).where((p) {
      if (_filterBookmarkedOnly) {
        return widget.bookmarkedPages.contains(p);
      }
      return true;
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151C2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Pages & Thumbnails',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                FilterChip(
                  avatar: Icon(
                    Icons.bookmark_rounded,
                    size: 16,
                    color: _filterBookmarkedOnly
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  label: Text('Saved (${widget.bookmarkedPages.length})'),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _filterBookmarkedOnly
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  selected: _filterBookmarkedOnly,
                  selectedColor: theme.colorScheme.primary,
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  side: BorderSide(
                    color: _filterBookmarkedOnly
                        ? Colors.transparent
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  ),
                  onSelected: (val) => setState(() => _filterBookmarkedOnly = val),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          Expanded(
            child: displayedPages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bookmark_border_rounded,
                          size: 48,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No bookmarked pages yet',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap the bookmark icon in the viewer to save a page',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: displayedPages.length,
                    itemBuilder: (context, index) {
                      final pageNum = displayedPages[index];
                      final isCurrent = pageNum == widget.currentPage;
                      final isBookmarked = widget.bookmarkedPages.contains(pageNum);

                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onPageSelected(pageNum);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              width: isCurrent ? 2.5 : 1.0,
                            ),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 6,
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? theme.colorScheme.primary.withValues(alpha: 0.7)
                                            : (isDark ? Colors.white30 : Colors.black26),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildLineSkeleton(isDark, 0.9),
                                    const SizedBox(height: 4),
                                    _buildLineSkeleton(isDark, 0.75),
                                    const SizedBox(height: 4),
                                    _buildLineSkeleton(isDark, 0.85),
                                    const SizedBox(height: 4),
                                    _buildLineSkeleton(isDark, 0.6),
                                    const SizedBox(height: 4),
                                    _buildLineSkeleton(isDark, 0.7),
                                    const Spacer(),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? theme.colorScheme.primary
                                              : (isDark ? const Color(0xFF0F172A) : Colors.white),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isCurrent
                                                ? theme.colorScheme.primary
                                                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                          ),
                                        ),
                                        child: Text(
                                          'P. $pageNum',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isCurrent
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : Colors.black87),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => widget.onBookmarkToggled(pageNum),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: isBookmarked
                                          ? Colors.amber.withValues(alpha: 0.2)
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isBookmarked
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                      size: 16,
                                      color: isBookmarked
                                          ? Colors.amber
                                          : (isDark ? Colors.white24 : Colors.black26),
                                    ),
                                  ),
                                ),
                              ),

                              if (isCurrent)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLineSkeleton(bool isDark, double widthRatio) {
    return FractionallySizedBox(
      widthFactor: widthRatio,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black12,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
