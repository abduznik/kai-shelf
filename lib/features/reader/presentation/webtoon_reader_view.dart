import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backend/models.dart';
import 'reader_jump_controller.dart';
import 'widgets/page_image.dart';

class WebtoonReaderView extends StatefulWidget {
  const WebtoonReaderView({
    super.key,
    required this.pages,
    required this.onPageChanged,
    this.initialPage = 0,
    this.jumpController,
  });

  final List<KsPage> pages;
  final ValueChanged<int> onPageChanged;
  final int initialPage;
  final ReaderJumpController? jumpController;

  @override
  State<WebtoonReaderView> createState() => _WebtoonReaderViewState();
}

class _WebtoonReaderViewState extends State<WebtoonReaderView> {
  late final ScrollController _controller;
  int _lastReportedPage = -1;

  // Page heights are unknown until their images load, so a jump can only be
  // aimed at an estimate that keeps shifting as the pages above the target
  // resolve. Jumps are therefore retried until the estimate settles, and
  // scroll reports are muted meanwhile so the intermediate positions don't
  // get saved as reading progress.
  static const _settleInterval = Duration(milliseconds: 120);
  static const _maxSettleAttempts = 25;
  Timer? _settleTimer;
  int _settleAttempts = 0;
  int _settleTarget = 0;
  int _stableChecks = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
    widget.jumpController?.attach(_jumpTo);
    if (widget.initialPage > 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _jumpTo(widget.initialPage));
    }
  }

  @override
  void dispose() {
    widget.jumpController?.detach(_jumpTo);
    _settleTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  double get _estimatedPageHeight {
    final position = _controller.position;
    final viewportHeight = position.viewportDimension;
    return position.maxScrollExtent > 0
        ? (position.maxScrollExtent + viewportHeight) / widget.pages.length
        : viewportHeight;
  }

  int get _estimatedIndex => (_controller.offset / _estimatedPageHeight)
      .floor()
      .clamp(0, widget.pages.length - 1);

  void _jumpTo(int page) {
    if (widget.pages.isEmpty) return;
    _settleTarget = page.clamp(0, widget.pages.length - 1);
    _settleAttempts = 0;
    _stableChecks = 0;
    _settleTimer?.cancel();
    _settleTimer = Timer.periodic(_settleInterval, (_) => _settleStep());
    _settleStep();
  }

  void _settleStep() {
    if (!mounted || !_controller.hasClients) return;
    _settleAttempts++;
    final position = _controller.position;
    final target = (_settleTarget * _estimatedPageHeight)
        .clamp(0.0, position.maxScrollExtent);
    if (_estimatedIndex == _settleTarget &&
        (_controller.offset - target).abs() < 1) {
      _stableChecks++;
    } else {
      _stableChecks = 0;
      _controller.jumpTo(target);
    }
    if (_stableChecks >= 2 || _settleAttempts >= _maxSettleAttempts) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _lastReportedPage = _estimatedIndex;
      widget.onPageChanged(_lastReportedPage);
    }
  }

  void _onScroll() {
    if (widget.pages.isEmpty || !_controller.hasClients) return;
    if (_settleTimer != null) return;
    final estimatedIndex = _estimatedIndex;
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
