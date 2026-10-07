import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const incognitoPrefKey = 'privacy.incognito';

/// Reads the saved flag. main() awaits this before the first frame and feeds
/// it to [incognitoInitialProvider], so there is no window at startup where
/// the flag still reads "off" while the real value loads, which would let a
/// first page change leak into history.
Future<bool> loadIncognitoFlag() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(incognitoPrefKey) ?? false;
  } catch (_) {
    return false;
  }
}

final incognitoInitialProvider = Provider<bool>((ref) => false);

/// Global incognito switch. While on, the reader records nothing: no local
/// progress, no server progress sync (and so nothing in history), no
/// mark-as-read, and no background downloads. Everything that honours it
/// reads this one provider, so auditing incognito means grepping for it.
class IncognitoNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(incognitoInitialProvider);

  Future<void> setEnabled(bool enabled) async {
    // State flips first so the very next page change already sees it; the
    // write to disk can lag behind without weakening the guarantee.
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(incognitoPrefKey, enabled);
    } catch (_) {
      // Not persisting only means the toggle resets on restart.
    }
  }
}

final incognitoProvider =
    NotifierProvider<IncognitoNotifier, bool>(IncognitoNotifier.new);
