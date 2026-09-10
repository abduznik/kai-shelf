import 'package:flutter/material.dart';

class KavitaAuthFields extends StatelessWidget {
  const KavitaAuthFields({super.key, required this.onApiKeyChanged});

  final ValueChanged<String> onApiKeyChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
              labelText: 'API Key', border: OutlineInputBorder()),
          onChanged: onApiKeyChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'Find your API key in Kavita under Settings → Account.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
