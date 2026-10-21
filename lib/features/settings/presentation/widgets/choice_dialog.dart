import 'package:flutter/material.dart';

/// Single-choice dialog behind the settings pickers: a title plus one option
/// per value, the current choice ticked. Returns the picked value, or null
/// when the dialog is dismissed without choosing.
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<(T, String)> choices,
}) =>
    showDialog<T>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label) in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  if (value == selected) const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
      ),
    );
