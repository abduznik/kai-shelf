import 'package:flutter/material.dart';

import '../../../core/backend/models.dart';
import 'widgets/page_image.dart';

class WebtoonReaderView extends StatefulWidget {
  const WebtoonReaderView({
    super.key,
    required this.pages,
    required this.onPageChanged,
    this.initialPage = 0,
  });

  final List<KsPage> pages;
  final ValueChanged<int> onPageChanged;
  final int initialPage;

  @override
  State<WebtoonReaderView> createState() => _WebtoonReaderViewState();
}

class _WebtoonReaderViewState extends State<WebtoonReaderView> {
  late final ScrollController _controller;
  int _lastReportedPage = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.pages.isEmpty || !_controller.hasClients) return;
    final viewportHeight = _controller.position.viewportDimension;
    final estimatedPageHeight = _controller.position.maxScrollExtent > 0
        ? (_controller.position.maxScrollExtent + viewportHeight) /
            widget.pages.length
        : viewportHeight;
    final estimatedIndex =
        (_controller.offset / estimatedPageHeight).floor().clamp(
              0,
              widget.pages.length - 1,
            );
    if (estimatedIndex != _lastReportedPage) {
      _lastReportedPage = estimatedIndex;
      widget.onPageChanged(estimatedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: widget.pages.length,
      itemBuilder: (context, index) {
        final page = widget.pages[index];
        return SizedBox(
          width: double.infinity,
          child: PageImage(page: page, fit: BoxFit.fitWidth),
        );
      },
    );
  }
}
