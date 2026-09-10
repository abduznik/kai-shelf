import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../../core/backend/models.dart';
import 'widgets/page_image.dart';

class PagedReaderView extends StatefulWidget {
  const PagedReaderView({
    super.key,
    required this.pages,
    required this.onPageChanged,
    this.rightToLeft = false,
    this.initialPage = 0,
  });

  final List<KsPage> pages;
  final ValueChanged<int> onPageChanged;
  final bool rightToLeft;
  final int initialPage;

  @override
  State<PagedReaderView> createState() => _PagedReaderViewState();
}

class _PagedReaderViewState extends State<PagedReaderView> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      reverse: widget.rightToLeft,
      itemCount: widget.pages.length,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (context, index) {
        final page = widget.pages[index];
        return PhotoView.customChild(
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          child: PageImage(page: page, fit: BoxFit.contain),
        );
      },
    );
  }
}
