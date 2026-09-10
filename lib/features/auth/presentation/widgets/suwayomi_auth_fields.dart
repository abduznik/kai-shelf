import 'package:flutter/material.dart';

class SuwayomiAuthFields extends StatelessWidget {
  const SuwayomiAuthFields({super.key, required this.onPasswordChanged});

  final ValueChanged<String> onPasswordChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: true,
      decoration: const InputDecoration(
        labelText: 'Password (leave blank if none)',
        border: OutlineInputBorder(),
      ),
      onChanged: onPasswordChanged,
    );
  }
}
