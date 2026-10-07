import 'package:flutter/material.dart';

import '../../../../core/providers/reader_prefs_provider.dart';

class ReaderControlsOverlay extends StatefulWidget {
  const ReaderControlsOverlay({
    super.key,
    required this.visible,
    required this.currentPage,
    required this.totalPages,
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
    this.onPageSelected,
    this.onPreviousChapter,
    this.onNextChapter,
  });

  final bool visible;
  final int currentPage;
  final int totalPages;
  final ReaderMode mode;
  final ValueChanged<ReaderMode> onModeChanged;
  final VoidCallback onClose;
  final ValueChanged<int>? onPageSelected;

  /// Null disables the button (no chapter in that direction).
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  @override
  State<ReaderControlsOverlay> createState() => _ReaderControlsOverlayState();
}

class _ReaderControlsOverlayState extends State<ReaderControlsOverlay> {
  /// Slider position while dragging. The jump is only committed on release,
  /// so scrubbing doesn't load every page it passes over.
  double? _dragValue;

  @override
  void didUpdateWidget(ReaderControlsOverlay old) {
    super.didUpdateWidget(old);
    // After release the view takes a moment to report the new page (webtoon
    // jumps settle over several frames); hold the thumb in place until it
    // does instead of snapping back to the old page.
    if (old.currentPage != widget.currentPage ||
        old.totalPages != widget.totalPages) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible;
    final currentPage = widget.currentPage;
    final totalPages = widget.totalPages;
    final mode = widget.mode;
    final shownPage = _dragValue?.round() ?? currentPage;
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
                      onPressed: widget.onClose,
                    ),
                    const Spacer(),
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
                      onPressed: () => widget.onModeChanged(
                          mode == ReaderMode.paged
                              ? ReaderMode.webtoon
                              : ReaderMode.paged),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 4, top: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.skip_previous, color: Colors.white),
                      disabledColor: Colors.white24,
                      tooltip: 'Previous chapter',
                      onPressed: widget.onPreviousChapter,
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: (totalPages - 1).clamp(1, totalPages).toDouble(),
                        divisions: totalPages > 1 ? totalPages - 1 : null,
                        value: shownPage
                            .clamp(0, (totalPages - 1).clamp(1, totalPages))
                            .toDouble(),
                        label: '${shownPage + 1}',
                        onChanged: totalPages > 1
                            ? (v) => setState(() => _dragValue = v)
                            : null,
                        onChangeEnd: totalPages > 1
                            ? (v) {
                                if (v.round() == currentPage) {
                                  setState(() => _dragValue = null);
                                }
                                widget.onPageSelected?.call(v.round());
                              }
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        totalPages > 0 ? '${shownPage + 1} / $totalPages' : '',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      disabledColor: Colors.white24,
                      tooltip: 'Next chapter',
                      onPressed: widget.onNextChapter,
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
