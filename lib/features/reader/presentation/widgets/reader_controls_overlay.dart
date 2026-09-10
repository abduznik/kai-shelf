import 'package:flutter/material.dart';

import '../../../../core/providers/reader_prefs_provider.dart';

class ReaderControlsOverlay extends StatelessWidget {
  const ReaderControlsOverlay({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
  });

  final bool visible;
  final int currentPage;
  final int totalPages;
  final ReaderMode mode;
  final ValueChanged<ReaderMode> onModeChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top, bottom: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onClose,
                    ),
                    Expanded(
                      child: Text(
                        totalPages > 0
                            ? '${currentPage + 1} / $totalPages'
                            : '',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        mode == ReaderMode.paged
                            ? Icons.view_carousel
                            : Icons.view_day,
                        color: Colors.white,
                      ),
                      tooltip: mode == ReaderMode.paged
                          ? 'Switch to continuous scroll'
                          : 'Switch to paged view',
                      onPressed: () => onModeChanged(mode == ReaderMode.paged
                          ? ReaderMode.webtoon
                          : ReaderMode.paged),
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
