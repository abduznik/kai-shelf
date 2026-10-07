/// Lets the reader screen ask whichever view is currently mounted (paged or
/// webtoon) to jump to a page, without the screen knowing which one it is.
class ReaderJumpController {
  void Function(int page)? _handler;

  void attach(void Function(int page) handler) => _handler = handler;

  void detach(void Function(int page) handler) {
    // A newly mounted view attaches before the old one detaches when the
    // reader mode is switched; only clear our own handler.
    if (_handler == handler) _handler = null;
  }

  void jumpTo(int page) => _handler?.call(page);
}
