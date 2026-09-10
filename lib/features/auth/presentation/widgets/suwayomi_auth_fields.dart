import 'package:flutter/material.dart';

class SuwayomiAuthFields extends StatelessWidget {
  const SuwayomiAuthFields({
    super.key,
    required this.onUsernameChanged,
    required this.onPasswordChanged,
  });

  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onPasswordChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Username (leave blank if no auth is configured)',
            border: OutlineInputBorder(),
          ),
          onChanged: onUsernameChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (leave blank if no auth is configured)',
            border: OutlineInputBorder(),
          ),
          onChanged: onPasswordChanged,
        ),
      ],
    );
  }
}
