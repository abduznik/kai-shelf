import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/download/byte_format.dart';

void main() {
  group('formatBytes', () {
    test('renders byte counts below a kilobyte as-is', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('scales through KB, MB and GB with one decimal', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(3221225472), '3.0 GB');
    });
  });
}
