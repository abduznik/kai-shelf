import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/incognito_provider.dart';

/// Small "Incognito" pill shown wherever the mode matters, and nothing at
/// all when it is off so it can sit unconditionally in a layout.
class IncognitoBadge extends ConsumerWidget {
  const IncognitoBadge({super.key}) : _positioned = false;

  /// For use inside a Stack (the reader): pinned to the top-left corner,
  /// below the status bar, and transparent to taps so it never blocks the
  /// page gestures underneath.
  const IncognitoBadge.positioned({super.key}) : _positioned = true;

  final bool _positioned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(incognitoProvider)) {
      return _positioned
          ? const Positioned(child: SizedBox.shrink())
          : const SizedBox.shrink();
    }
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text('Incognito',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
    if (!_positioned) return pill;
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IgnorePointer(child: pill),
        ),
      ),
    );
  }
}
