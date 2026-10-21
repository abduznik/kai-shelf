import 'package:flutter/material.dart';

class OpdsAuthFields extends StatelessWidget {
  const OpdsAuthFields({
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
            labelText: 'Username (optional — HTTP Basic protected catalogs)',
            border: OutlineInputBorder(),
          ),
          onChanged: onUsernameChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (optional)',
            border: OutlineInputBorder(),
          ),
          onChanged: onPasswordChanged,
        ),
      ],
    );
  }
}
