import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/backend/auth_credentials.dart';
import '../../../core/backend/komga/komga_backend.dart';
import '../../../core/backend/kavita/kavita_backend.dart';
import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/backend/suwayomi/suwayomi_backend.dart';
import '../../../core/providers/backend_providers.dart';
import 'server_form_state.dart';
import 'widgets/kavita_auth_fields.dart';
import 'widgets/komga_auth_fields.dart';
import 'widgets/suwayomi_auth_fields.dart';

class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  String _password = '';
  String _email = '';
  String _apiKey = '';
  String? _submitError;
  bool _isSubmitting = false;

  Future<void> _submit(ServerFormState formState) async {
    final detection = formState.detectionResult;
    if (detection == null) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final serverId = const Uuid().v4();
    final draftConnection = ServerConnectionInfo(
      serverId: serverId,
      displayName: detection.normalizedBaseUrl.host,
      baseUrl: detection.normalizedBaseUrl,
      type: detection.type,
    );

    final ServerBackend backend = switch (detection.type) {
      BackendType.suwayomi => SuwayomiBackend(draftConnection),
      BackendType.komga => KomgaBackend(draftConnection),
      BackendType.kavita => KavitaBackend(draftConnection),
    };

    final credentials = switch (detection.type) {
      BackendType.suwayomi => AuthCredentials.suwayomi(
          password: _password.isEmpty ? null : _password),
      BackendType.komga => _apiKey.isNotEmpty
          ? AuthCredentials.komgaApiKey(apiKey: _apiKey)
          : AuthCredentials.komgaPassword(email: _email, password: _password),
      BackendType.kavita => AuthCredentials.kavita(apiKey: _apiKey),
    };

    final result = await backend.login(credentials);

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isSubmitting = false;
        _submitError = result.error ?? 'Login failed';
      });
      return;
    }

    ref.read(activeConnectionProvider.notifier).state = result.connectionInfo;
    setState(() => _isSubmitting = false);

    if (mounted) context.go('/library');
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(serverFormControllerProvider);
    final controller = ref.read(serverFormControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Connect to a server')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.100:4567',
                border: OutlineInputBorder(),
              ),
              onChanged: controller.setUrl,
              enabled: !formState.isDetecting && !_isSubmitting,
            ),
            const SizedBox(height: 12),
            if (formState.detectionResult == null)
              FilledButton(
                onPressed: formState.isDetecting || formState.url.trim().isEmpty
                    ? null
                    : controller.detect,
                child: formState.isDetecting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            if (formState.error != null) ...[
              const SizedBox(height: 12),
              Text(formState.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (formState.detectionResult != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                      'Detected: ${backendTypeLabel(formState.detectionResult!.type)}'),
                  const Spacer(),
                  TextButton(
                      onPressed: controller.reset, child: const Text('Change')),
                ],
              ),
              const SizedBox(height: 16),
              switch (formState.detectionResult!.type) {
                BackendType.suwayomi => SuwayomiAuthFields(
                    onPasswordChanged: (v) => setState(() => _password = v),
                  ),
                BackendType.komga => KomgaAuthFields(
                    onEmailChanged: (v) => setState(() => _email = v),
                    onPasswordChanged: (v) => setState(() => _password = v),
                    onApiKeyChanged: (v) => setState(() => _apiKey = v),
                  ),
                BackendType.kavita => KavitaAuthFields(
                    onApiKeyChanged: (v) => setState(() => _apiKey = v),
                  ),
              },
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(_submitError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : () => _submit(formState),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
