import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/src/api_client.dart';
import 'package:streambox/src/core/core_client.dart';
import 'package:streambox/src/core/rust_core_client.dart';
import 'package:streambox/src/native/native_core.dart';

void main() {
  test('hybrid core client delegates unmigrated search to FastAPI', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/discover');
        expect(request.url.queryParameters['q'], 'bella');
        expect(request.url.queryParameters['scope'], 'songs');
        return http.Response(
          '{"query":"bella","mode":"stream","scope":"songs","items":[],"warnings":[]}',
          200,
        );
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(
          available: true,
          version: 'streambox-core 0.1.0',
          platform: 'test',
        ),
      ),
    );

    final response = await coreClient.discover('bella', scope: 'songs');

    expect(response.query, 'bella');
    expect(response.scope, 'songs');
  });

  test('hybrid core client exposes native core diagnostics', () async {
    const health = NativeCoreHealth(
      available: true,
      version: 'streambox-core 0.1.0',
      platform: 'test-platform',
    );
    final coreClient = HybridCoreClient(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      nativeCore: const StaticNativeCore(health),
    );

    final result = await coreClient.nativeHealth();

    expect(result.available, isTrue);
    expect(result.version, 'streambox-core 0.1.0');
    expect(result.platform, 'test-platform');
  });

  test('rust core client exposes native echo json protocol', () async {
    final rustClient = RustCoreClient(
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(
          available: true,
          version: 'streambox-core 0.1.0',
          platform: 'test-platform',
        ),
      ),
    );

    final result = await rustClient.echoJson({'message': 'bonjour'});

    expect(result['ok'], isTrue);
    expect(result['data']['echo']['message'], 'bonjour');
  });

  test('native core ffi reports unavailable when the library cannot be loaded',
      () async {
    final nativeCore = FfiNativeCore(libraryName: 'missing_streambox_core');

    final health = await nativeCore.health();

    expect(health.available, isFalse);
    expect(health.version, isNull);
    expect(health.error, contains('missing_streambox_core'));
  });
test('hybrid playlist list falls back when the Rust library is unavailable', () async {
  final apiClient = ApiClient(
    baseUrl: 'http://127.0.0.1:8000',
    httpClient: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/playlists');
      return http.Response(
        '[{"id":"playlist-missing-rust","name":"FastAPI","description":"","tracks":[]}]',
        200,
      );
    }),
  );
  final nativeCore = FfiNativeCore(libraryName: 'missing_streambox_core');
  final coreClient = HybridCoreClient(
    apiClient: apiClient,
    nativeCore: nativeCore,
    rustCoreClient: RustCoreClient(
      nativeCore: nativeCore,
      fallbackApiClient: apiClient,
    ),
  );

  final playlists = await coreClient.playlists();

  expect(playlists.single.id, 'playlist-missing-rust');
  expect(playlists.single.name, 'FastAPI');
});

test('hybrid playlist list falls back to FastAPI when Rust is unsupported', () async {
  final apiClient = ApiClient(
    baseUrl: 'http://127.0.0.1:8000',
    httpClient: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/playlists');
      return http.Response(
        '[{"id":"playlist-1","name":"Fallback","description":"","tracks":[]}]',
        200,
      );
    }),
  );
  final coreClient = HybridCoreClient(
    apiClient: apiClient,
    nativeCore: const StaticNativeCore(
      NativeCoreHealth(available: false, error: 'missing native library'),
    ),
    rustCoreClient: RustCoreClient(
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(available: false, error: 'missing native library'),
      ),
      fallbackApiClient: apiClient,
    ),
  );

  final playlists = await coreClient.playlists();

  expect(playlists.single.id, 'playlist-1');
  expect(playlists.single.name, 'Fallback');
});

test('hybrid playlist create falls back after controlled Rust failure', () async {
  final apiClient = ApiClient(
    baseUrl: 'http://127.0.0.1:8000',
    httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/playlists');
      return http.Response(
        '{"id":"playlist-2","name":"Fallback Create","description":"","tracks":[]}',
        201,
      );
    }),
  );
  final coreClient = HybridCoreClient(
    apiClient: apiClient,
    nativeCore: const StaticNativeCore(NativeCoreHealth(available: true)),
    rustCoreClient: RustCoreClient(
      nativeCore: const _FailingPlaylistNativeCore(),
      fallbackApiClient: apiClient,
    ),
  );

  final playlist = await coreClient.createPlaylist('Fallback Create', const []);

  expect(playlist.id, 'playlist-2');
  expect(playlist.name, 'Fallback Create');
});

}

class _FailingPlaylistNativeCore implements NativeCore {
  const _FailingPlaylistNativeCore();

  @override
  Future<NativeCoreHealth> health() async =>
      const NativeCoreHealth(available: true);

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async => {
        'ok': true,
        'data': {'echo': input},
      };

  @override
  Future<Map<String, dynamic>> playlistsListJson(
    Map<String, dynamic> input,
  ) async =>
      _error();

  @override
  Future<Map<String, dynamic>> playlistsCreateJson(
    Map<String, dynamic> input,
  ) async =>
      _error();

  @override
  Future<Map<String, dynamic>> playlistsDeleteJson(
    Map<String, dynamic> input,
  ) async =>
      _error();

  @override
  Future<Map<String, dynamic>> playlistsUpdateJson(
    Map<String, dynamic> input,
  ) async =>
      _error();

  Map<String, dynamic> _error() => {
        'ok': false,
        'error': {
          'code': 'database_error',
          'message': 'test controlled failure',
        },
      };
}
