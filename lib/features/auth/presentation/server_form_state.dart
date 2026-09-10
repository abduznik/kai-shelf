import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/detector/backend_detector.dart';
import '../../../core/backend/models.dart';
import '../../../core/providers/backend_providers.dart';

class ServerFormState {
  const ServerFormState({
    this.url = '',
    this.detectionResult,
    this.isDetecting = false,
    this.isSubmitting = false,
    this.error,
  });

  final String url;
  final DetectionResult? detectionResult;
  final bool isDetecting;
  final bool isSubmitting;
  final String? error;

  ServerFormState copyWith({
    String? url,
    DetectionResult? detectionResult,
    bool clearDetectionResult = false,
    bool? isDetecting,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return ServerFormState(
      url: url ?? this.url,
      detectionResult: clearDetectionResult
          ? null
          : (detectionResult ?? this.detectionResult),
      isDetecting: isDetecting ?? this.isDetecting,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ServerFormController extends Notifier<ServerFormState> {
  @override
  ServerFormState build() => const ServerFormState();

  void setUrl(String url) {
    state =
        state.copyWith(url: url, clearDetectionResult: true, clearError: true);
  }

  Future<void> detect() async {
    if (state.url.trim().isEmpty) return;
    state = state.copyWith(
        isDetecting: true, clearError: true, clearDetectionResult: true);

    try {
      final detector = ref.read(backendDetectorProvider);
      final result = await detector.detect(state.url);
      if (result == null) {
        state = state.copyWith(
          isDetecting: false,
          error: "Couldn't identify the server type at that address.",
        );
        return;
      }
      state = state.copyWith(isDetecting: false, detectionResult: result);
    } catch (e) {
      state = state.copyWith(
          isDetecting: false, error: 'Could not reach that server: $e');
    }
  }

  void reset() {
    state = const ServerFormState();
  }
}

final serverFormControllerProvider =
    NotifierProvider<ServerFormController, ServerFormState>(
  ServerFormController.new,
);

String backendTypeLabel(BackendType type) {
  switch (type) {
    case BackendType.suwayomi:
      return 'Suwayomi';
    case BackendType.komga:
      return 'Komga';
    case BackendType.kavita:
      return 'Kavita';
  }
}
