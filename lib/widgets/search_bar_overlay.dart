import 'package:flutter/material.dart';

class SearchBarOverlay extends StatelessWidget {
  final TextEditingController controller;
  final int currentMatchIndex;
  final int totalMatches;
  final bool isSearching;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onNextMatch;
  final VoidCallback onPreviousMatch;
  final VoidCallback onClose;

  const SearchBarOverlay({
    super.key,
    required this.controller,
    required this.currentMatchIndex,
    required this.totalMatches,
    required this.isSearching,
    required this.onSearchSubmitted,
    required this.onNextMatch,
    required this.onPreviousMatch,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(18),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Find in document...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: onSearchSubmitted,
                    onChanged: (text) {
                      if (text.length >= 2) {
                        onSearchSubmitted(text);
                      }
                    },
                  ),
                ),

                if (totalMatches > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$currentMatchIndex / $totalMatches',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                else if (controller.text.isNotEmpty && !isSearching)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'No matches',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),

                if (isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),

                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  onPressed: totalMatches > 0 ? onPreviousMatch : null,
                  tooltip: 'Previous occurrence',
                ),

                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  onPressed: totalMatches > 0 ? onNextMatch : null,
                  tooltip: 'Next occurrence',
                ),

                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  tooltip: 'Dismiss search',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
