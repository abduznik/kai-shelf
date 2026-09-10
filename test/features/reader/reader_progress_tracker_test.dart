import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/features/reader/domain/reader_progress_tracker.dart';

void main() {
  group('ReaderProgressTracker', () {
    test('debounces rapid page changes into a single persisted save', () async {
      var saveCount = 0;
      double? lastSavedPage;

      final tracker = ReaderProgressTracker(
        totalPages: 10,
        debounceDuration: const Duration(milliseconds: 20),
        onSaveLocal: ({required read, required lastPageRead}) async {
          saveCount++;
          lastSavedPage = lastPageRead;
        },
      );

      for (var i = 0; i < 5; i++) {
        tracker.onPageChanged(i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tracker.dispose();

      expect(saveCount, 1);
      expect(lastSavedPage, 4);
    });

    test('marks the chapter read only once the last page is reached', () async {
      bool? savedRead;

      final tracker = ReaderProgressTracker(
        totalPages: 3,
        debounceDuration: const Duration(milliseconds: 10),
        onSaveLocal: ({required read, required lastPageRead}) async {
          savedRead = read;
        },
      );

      tracker.onPageChanged(1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(savedRead, isFalse);

      tracker.onPageChanged(2);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(savedRead, isTrue);

      tracker.dispose();
    });

    test('a disposed tracker does not fire a pending save', () async {
      var saveCount = 0;

      final tracker = ReaderProgressTracker(
        totalPages: 5,
        debounceDuration: const Duration(milliseconds: 30),
        onSaveLocal: ({required read, required lastPageRead}) async {
          saveCount++;
        },
      );

      tracker.onPageChanged(1);
      tracker.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(saveCount, 0);
    });

    test('a server sync failure does not throw or block the local save',
        () async {
      var localSaved = false;

      final tracker = ReaderProgressTracker(
        totalPages: 5,
        debounceDuration: const Duration(milliseconds: 10),
        onSaveLocal: ({required read, required lastPageRead}) async {
          localSaved = true;
        },
        onSyncServer: ({required read, required lastPageRead}) async {
          throw Exception('network down');
        },
      );

      tracker.onPageChanged(1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      tracker.dispose();

      expect(localSaved, isTrue);
    });
  });
}
