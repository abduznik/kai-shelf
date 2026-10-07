import 'package:flutter/material.dart';

/// Shown over the last page so finishing a chapter leads straight into the
/// next one without opening the controls.
class NextChapterPrompt extends StatelessWidget {
  const NextChapterPrompt({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.skip_next),
        label: const Text('Next chapter'),
      ),
    );
  }
}
