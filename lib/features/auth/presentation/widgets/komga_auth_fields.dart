import 'package:flutter/material.dart';

class KomgaAuthFields extends StatefulWidget {
  const KomgaAuthFields({
    super.key,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onApiKeyChanged,
  });

  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onApiKeyChanged;

  @override
  State<KomgaAuthFields> createState() => _KomgaAuthFieldsState();
}

class _KomgaAuthFieldsState extends State<KomgaAuthFields> {
  bool _useApiKey = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_useApiKey) ...[
          TextField(
            decoration: const InputDecoration(
                labelText: 'Email', border: OutlineInputBorder()),
            onChanged: widget.onEmailChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password', border: OutlineInputBorder()),
            onChanged: widget.onPasswordChanged,
          ),
        ] else
          TextField(
            decoration: const InputDecoration(
                labelText: 'API Key', border: OutlineInputBorder()),
            onChanged: widget.onApiKeyChanged,
          ),
        TextButton(
          onPressed: () => setState(() => _useApiKey = !_useApiKey),
          child: Text(_useApiKey
              ? 'Use email & password instead'
              : 'Use an API key instead'),
        ),
      ],
    );
  }
}
