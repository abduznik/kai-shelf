import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/features/reader/domain/reader_progress_tracker.dart';

void main() {
  group('ReaderProgressTracker with incognito', () {
    late int localSaves;
    late int serverSyncs;
    late bool incognito;

    ReaderProgressTracker build() => ReaderProgressTracker(
          totalPages: 5,
          debounceDuration: const Duration(milliseconds: 10),
          isIncognito: () => incognito,
          onSaveLocal: ({required read, required lastPageRead}) async {
            localSaves++;
          },
          onSyncServer: ({required read, required lastPageRead}) async {
            serverSyncs++;
          },
        );

    setUp(() {
      localSaves = 0;
      serverSyncs = 0;
      incognito = false;
    });

    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 40));

    test('persists and syncs normally when off', () async {
      final tracker = build();
      tracker.onPageChanged(2);
      await flush();
      tracker.dispose();
      expect([localSaves, serverSyncs], [1, 1]);
    });

    test('saves nothing locally and syncs nothing when on', () async {
      incognito = true;
      final tracker = build();
      tracker.onPageChanged(2);
      tracker.onPageChanged(4); // the last page would normally mark it read
      await flush();
      tracker.dispose();
      expect([localSaves, serverSyncs], [0, 0]);
    });

    test('turning it on mid-session takes effect on the next page change',
        () async {
      final tracker = build();
      tracker.onPageChanged(1);
      await flush();
      expect([localSaves, serverSyncs], [1, 1]);

      incognito = true;
      tracker.onPageChanged(2);
      await flush();
      expect([localSaves, serverSyncs], [1, 1]);
      tracker.dispose();
    });

    test('turning it on while a save is pending suppresses that save',
        () async {
      final tracker = build();
      tracker.onPageChanged(3);
      incognito = true; // flipped inside the debounce window
      await flush();
      tracker.dispose();
      expect([localSaves, serverSyncs], [0, 0]);
    });

    test('turning it off resumes saving', () async {
      incognito = true;
      final tracker = build();
      tracker.onPageChanged(1);
      await flush();
      incognito = false;
      tracker.onPageChanged(2);
      await flush();
      tracker.dispose();
      expect([localSaves, serverSyncs], [1, 1]);
    });
  });
}
