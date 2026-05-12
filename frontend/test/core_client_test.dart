import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/src/api_client.dart';
import 'package:streambox/src/core/core_client.dart';
import 'package:streambox/src/core/rust_core_client.dart';
import 'package:streambox/src/models.dart';
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

  test('rust core client reads and writes history through native json', () async {
    final item = _samplePlaybackItem('native');
    final nativeCore = _HistoryNativeCore(historyItems: [item.toJson()]);
    final rustClient = RustCoreClient(
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      nativeCore: nativeCore,
      dbPath: '/tmp/streambox-test.db',
    );

    await rustClient.addHistory(item);
    final history = await rustClient.history();

    expect(nativeCore.addedItems.single['id'], 'native');
    expect(nativeCore.lastDbPath, '/tmp/streambox-test.db');
    expect(history.single.id, 'native');
  });

  test('rust core client clears history through native json', () async {
    final nativeCore = _HistoryNativeCore(
      historyItems: [_samplePlaybackItem('clear').toJson()],
    );
    final rustClient = RustCoreClient(
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      nativeCore: nativeCore,
    );

    await rustClient.clearHistory();

    expect(nativeCore.historyItems, isEmpty);
  });

  test('hybrid core client falls back to FastAPI when rust history fails',
      () async {
    var postCount = 0;
    var getCount = 0;
    final item = _samplePlaybackItem('fallback');
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/history');
        if (request.method == 'POST') {
          postCount++;
          return http.Response('', 201);
        }
        getCount++;
        return http.Response('[${item.toJsonString()}]', 200);
      }),
    );
    final nativeCore = _FailingHistoryNativeCore();
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: nativeCore,
      rustCoreClient: RustCoreClient(
        fallbackApiClient: apiClient,
        nativeCore: nativeCore,
      ),
    );

    await coreClient.addHistory(item);
    final history = await coreClient.history();

    expect(postCount, 1);
    expect(getCount, 1);
    expect(history.single.id, 'fallback');
  });
}

PlaybackItem _samplePlaybackItem(String id) {
  return PlaybackItem(
    id: id,
    track: TrackMetadata(
      id: 'track-$id',
      title: 'Track $id',
      artists: const [ArtistMetadata(id: 'artist-1', name: 'Artist')],
    ),
    addedAt: DateTime.utc(2026, 5, 12, 10),
  );
}

extension on PlaybackItem {
  String toJsonString() => jsonEncode(toJson());
}

class _HistoryNativeCore implements NativeCore {
  _HistoryNativeCore({required this.historyItems});

  final List<Map<String, dynamic>> historyItems;
  final List<Map<String, dynamic>> addedItems = [];
  String? lastDbPath;

  @override
  Future<NativeCoreHealth> health() async {
    return const NativeCoreHealth(available: true, version: 'test');
  }

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async {
    return {'ok': true, 'data': {'echo': input}};
  }

  @override
  Future<Map<String, dynamic>> historyAddJson(
    Map<String, dynamic> input,
  ) async {
    lastDbPath = input['db_path'] as String?;
    addedItems.add(input['item'] as Map<String, dynamic>);
    return {'ok': true, 'data': input['item']};
  }

  @override
  Future<Map<String, dynamic>> historyListJson(
    Map<String, dynamic> input,
  ) async {
    lastDbPath = input['db_path'] as String?;
    return {'ok': true, 'data': historyItems};
  }

  @override
  Future<Map<String, dynamic>> historyClearJson(
    Map<String, dynamic> input,
  ) async {
    historyItems.clear();
    return {'ok': true, 'data': <String, dynamic>{}};
  }
}

class _FailingHistoryNativeCore extends _HistoryNativeCore {
  _FailingHistoryNativeCore() : super(historyItems: []);

  @override
  Future<Map<String, dynamic>> historyAddJson(
    Map<String, dynamic> input,
  ) async {
    return {'ok': false, 'error': {'code': 'boom', 'message': 'nope'}};
  }

  @override
  Future<Map<String, dynamic>> historyListJson(
    Map<String, dynamic> input,
  ) async {
    return {'ok': false, 'error': {'code': 'boom', 'message': 'nope'}};
  }
}
