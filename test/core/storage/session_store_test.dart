import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/storage/session_store.dart';

ServerConnectionInfo _info(BackendType type) => ServerConnectionInfo(
      serverId: 's1',
      displayName: 'home',
      baseUrl: Uri.parse('http://192.168.1.5:4567'),
      type: type,
      apiKey: 'key',
      sessionToken: 'tok',
      extraHeaders: const {'Authorization': 'Basic abc'},
    );

/// Backend whose library call and login behave as scripted.
class _FakeBackend implements ServerBackend {
  _FakeBackend({this.libraries, this.loginResult});

  final Future<List<KsLibrary>> Function()? libraries;
  final AuthResult? loginResult;
  int logins = 0;

  @override
  Future<List<KsLibrary>> getLibraries() => libraries!();

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    logins++;
    return loginResult!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a saved connection survives a restart, headers and tokens included',
      () async {
    await SessionStore().save(_info(BackendType.suwayomi));

    final loaded =
        await SessionStore().load(); // a "new" store, as after restart
    expect(loaded!.serverId, 's1');
    expect(loaded.baseUrl, Uri.parse('http://192.168.1.5:4567'));
    expect(loaded.type, BackendType.suwayomi);
    expect(loaded.extraHeaders, {'Authorization': 'Basic abc'});
    expect(loaded.apiKey, 'key');
    expect(loaded.sessionToken, 'tok');
  });

  test('nothing saved, or clear(), means signed out', () async {
    final store = SessionStore();
    expect(await store.load(), isNull);
    await store.save(_info(BackendType.komga));
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('corrupt stored data is treated as signed out, not a crash', () async {
    FlutterSecureStorage.setMockInitialValues(
        {'session.activeConnection': '{not json'});
    expect(await SessionStore().load(), isNull);
  });

  test('restore keeps a session the server still accepts', () async {
    final store = SessionStore(
        backendFactory: (_) => _FakeBackend(libraries: () async => []));
    await store.save(_info(BackendType.komga));
    expect((await store.restore())!.serverId, 's1');
  });

  test('restore signs out when the server rejects the session', () async {
    final store = SessionStore(
        backendFactory: (_) => _FakeBackend(
            libraries: () async => throw const BackendAuthException()));
    await store.save(_info(BackendType.suwayomi));
    expect(await store.restore(), isNull);
    expect(await store.load(), isNull);
  });

  test('restore keeps the session when the server is just unreachable',
      () async {
    final store = SessionStore(
        backendFactory: (_) => _FakeBackend(
            libraries: () async => throw Exception('SocketException')));
    await store.save(_info(BackendType.komga));
    expect((await store.restore())!.serverId, 's1');
    expect(await store.load(), isNotNull);
  });

  test('an expired Kavita token is re-minted from the stored API key',
      () async {
    final fresh = _info(BackendType.kavita).copyWith(sessionToken: 'new');
    final backend = _FakeBackend(
      libraries: () async => throw const BackendAuthException(),
      loginResult: AuthResult.success(fresh),
    );
    final store = SessionStore(backendFactory: (_) => backend);
    await store.save(_info(BackendType.kavita));

    final restored = await store.restore();
    expect(backend.logins, 1);
    expect(restored!.sessionToken, 'new');
    expect((await store.load())!.sessionToken, 'new');
  });
}
