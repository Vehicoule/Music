import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/src/api_client.dart';
import 'package:streambox/src/core/core_client.dart';
import 'package:streambox/src/core/rust_core_client.dart';
import 'package:streambox/src/models.dart';
import 'package:streambox/src/native/native_core.dart';

void main() {
  test('api client uses JSON detail for non-success responses', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': {'message': 'missing track'},
          }),
          404,
        );
      }),
    );

    expect(
      () => apiClient.search('missing'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'HTTP 404: {"message":"missing track"}',
        ),
      ),
    );
  });

  test('api client falls back to raw body for non-JSON errors', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        return http.Response('upstream unavailable', 503);
      }),
    );

    expect(
      () => apiClient.search('anything'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'HTTP 503: upstream unavailable',
        ),
      ),
    );
  });

  test('api client reports malformed successful JSON', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        return http.Response('{bad json', 200);
      }),
    );

    expect(
      () => apiClient.search('broken'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          startsWith('Invalid JSON response:'),
        ),
      ),
    );
  });

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

  test(
    'hybrid core client returns favorites from Rust when native call succeeds',
    () async {
    final item = _samplePlaybackItem();
    final nativeCore = _FavoritesNativeCore(
      listResponse: {
        'ok': true,
        'data': [
          {'id': 'rust-favorite', 'item': item.toJson()},
        ],
      },
    );
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        fail('FastAPI should not be called when Rust favorites succeed');
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: nativeCore,
      rustCoreClient: RustCoreClient(
        nativeCore: nativeCore,
        fallbackApiClient: apiClient,
        databasePath: '/tmp/streambox-test.sqlite3',
      ),
      routingConfig: const CoreClientRoutingConfig(useRustLocalLibrary: true),
    );

    final favorites = await coreClient.favorites();

    expect(favorites, hasLength(1));
    expect(favorites.single.id, 'rust-favorite');
    expect(favorites.single.item.track.title, 'Test Song');
    expect(nativeCore.listCalls, 1);
  });

  test(
    'hybrid core client falls back to FastAPI when Rust favorites fail',
    () async {
    final item = _samplePlaybackItem();
    final nativeCore = _FavoritesNativeCore(
      listResponse: {
        'ok': false,
        'error': {'code': 'database_error', 'message': 'locked'},
      },
    );
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/favorites');
        return http.Response(
          '[{"id":"api-favorite","item":${jsonEncode(item.toJson())}}]',
          200,
        );
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: nativeCore,
      rustCoreClient: RustCoreClient(
        nativeCore: nativeCore,
        fallbackApiClient: apiClient,
        databasePath: '/tmp/streambox-test.sqlite3',
      ),
      routingConfig: const CoreClientRoutingConfig(useRustLocalLibrary: true),
    );

    final favorites = await coreClient.favorites();

    expect(favorites, hasLength(1));
    expect(favorites.single.id, 'api-favorite');
    expect(favorites.single.item.track.title, 'Test Song');
    expect(nativeCore.listCalls, 1);
  });

  test('rust core client parses playlist JSON shaped like FastAPI fixtures',
      () async {
    final listFixture = _fixtureResponse('playlists/list.json') as List<dynamic>;
    final createFixture = _fixture('playlists/create.json');
    final createResponse = createFixture['response'] as Map<String, dynamic>;
    final createRequest = createFixture['request'] as Map<String, dynamic>;
    final nativeCore = _ContractNativeCore(
      playlistListResponse: {'ok': true, 'data': listFixture},
      playlistCreateResponse: {'ok': true, 'data': createResponse},
      playlistUpdateResponse: {
        'ok': true,
        'data': {...createResponse, 'name': 'Updated road trip'},
      },
      playlistDeleteResponse: {'ok': true, 'data': <String, dynamic>{}},
    );
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    final playlists = await rustClient.playlists();
    expect(playlists.single.id, 'playlist-001');
    expect(playlists.single.tracks.single.track.title, 'Fixture Song');
    expect(nativeCore.playlistListInputs.single['database_path'],
        '/tmp/streambox-contract.sqlite3');

    final created = await rustClient.createPlaylist(
      createRequest['name'] as String,
      (createRequest['tracks'] as List<dynamic>)
          .map((item) => PlaybackItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    expect(created.name, 'Road trip');
    expect(created.tracks.single.source?.headers['User-Agent'],
        'StreamboxFixture/1.0');
    expect(nativeCore.playlistCreateInputs.single['database_path'],
        '/tmp/streambox-contract.sqlite3');
    expect(nativeCore.playlistCreateInputs.single['description'], isNull);

    final updated = await rustClient.updatePlaylist(
      'playlist-001',
      name: 'Updated road trip',
      tracks: created.tracks,
    );
    expect(updated.name, 'Updated road trip');
    expect(
      nativeCore.playlistUpdateInputs.single['tracks'],
      isA<List<dynamic>>(),
    );

    await rustClient.deletePlaylist('playlist-001');
    expect(
      nativeCore.playlistDeleteInputs.single,
      containsPair('id', 'playlist-001'),
    );
  });

  test('rust core client parses favorites JSON shaped like FastAPI fixtures',
      () async {
    final listFixture = _fixtureResponse('favorites/list.json') as List<dynamic>;
    final addFixture = _fixture('favorites/add.json');
    final favoriteItem = PlaybackItem.fromJson(
      addFixture['request']['item'] as Map<String, dynamic>,
    );
    final nativeCore = _ContractNativeCore(
      favoritesListResponse: {'ok': true, 'data': listFixture},
      favoritesAddResponse: {'ok': true, 'data': addFixture['response']},
      favoritesRemoveResponse: {'ok': true, 'data': <String, dynamic>{}},
    );
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    final favorites = await rustClient.favorites();
    expect(favorites.single.id, 'favorite-001');
    expect(favorites.single.item.track.album?.title, 'Fixture Album');
    expect(nativeCore.favoritesListDatabasePaths.single,
        '/tmp/streambox-contract.sqlite3');

    await rustClient.favorite(favoriteItem);
    expect(nativeCore.favoritesAddItems.single['track']['canonical_title'],
        'Fixture Song');
    expect(nativeCore.favoritesAddDatabasePaths.single,
        '/tmp/streambox-contract.sqlite3');

    await rustClient.unfavorite('favorite-001');
    expect(nativeCore.favoritesRemoveIds.single, 'favorite-001');
  });

  test('rust core client parses history JSON shaped like FastAPI fixtures',
      () async {
    final listFixture = _fixtureResponse('history/list.json') as List<dynamic>;
    final addFixture = _fixture('history/add.json');
    final historyItem = PlaybackItem.fromJson(
      addFixture['request']['item'] as Map<String, dynamic>,
    );
    final nativeCore = _ContractNativeCore(
      historyListResponse: {'ok': true, 'data': listFixture},
      historyAddResponse: {'ok': true, 'data': addFixture['response']},
    );
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
      fallbackApiClient: ApiClient(baseUrl: 'http://127.0.0.1:8000'),
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    await rustClient.addHistory(historyItem);
    expect(nativeCore.historyAddInputs.single['db_path'],
        '/tmp/streambox-contract.sqlite3');
    expect(nativeCore.historyAddInputs.single['item']['track']['source_provider'],
        'ytmusic');

    final history = await rustClient.history();
    expect(history.single.id, 'playback-001');
    expect(history.single.track.canonicalArtist, 'Fixture Artist');
    expect(nativeCore.historyListInputs.single['db_path'],
        '/tmp/streambox-contract.sqlite3');
  });

  test('hybrid core client falls back to FastAPI when Rust returns ok false',
      () async {
    final nativeCore = _ContractNativeCore(
      playlistListResponse: {
        'ok': false,
        'error': {'code': 'database_error', 'message': 'locked'},
      },
    );
    var apiCalls = 0;
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        apiCalls += 1;
        expect(request.url.path, '/api/playlists');
        return http.Response(
          jsonEncode(_fixtureResponse('playlists/list.json')),
          200,
        );
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: nativeCore,
      rustCoreClient: RustCoreClient(
        nativeCore: nativeCore,
        fallbackApiClient: apiClient,
        databasePath: '/tmp/streambox-contract.sqlite3',
      ),
      routingConfig: const CoreClientRoutingConfig(useRustLocalLibrary: true),
    );

    final playlists = await coreClient.playlists();

    expect(playlists.single.id, 'playlist-001');
    expect(apiCalls, 1);
    expect(nativeCore.playlistListInputs.single['database_path'],
        '/tmp/streambox-contract.sqlite3');
  });

  test('native core ffi reports unavailable when the library cannot be loaded',
      () async {
    final nativeCore = FfiNativeCore(libraryName: 'missing_streambox_core');

    final health = await nativeCore.health();

    expect(health.available, isFalse);
    expect(health.version, isNull);
    expect(health.error, contains('missing_streambox_core'));
  });

  test('hybrid core client routes local playlists to Rust when enabled',
      () async {
    final rustClient = _RecordingCoreClient(
      playlistsResult: const [
        Playlist(id: 'rust-playlist', name: 'Rust', description: '', tracks: []),
      ],
    );
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        fail('FastAPI should not be called when Rust local library succeeds');
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(available: true, platform: 'test'),
      ),
      rustCoreClient: rustClient,
      routingConfig: const CoreClientRoutingConfig(useRustLocalLibrary: true),
    );

    final playlists = await coreClient.playlists();

    expect(playlists.single.id, 'rust-playlist');
    expect(rustClient.playlistsCalls, 1);
  });

  test('hybrid core client falls back to FastAPI when Rust local playlists fail',
      () async {
    final rustClient = _RecordingCoreClient(throwOnPlaylists: true);
    var apiCalls = 0;
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        apiCalls += 1;
        expect(request.url.path, '/api/playlists');
        return http.Response(
          '[{"id":"api-playlist","name":"FastAPI","description":"","tracks":[]}]',
          200,
        );
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(available: true, platform: 'test'),
      ),
      rustCoreClient: rustClient,
      routingConfig: const CoreClientRoutingConfig(useRustLocalLibrary: true),
    );

    final playlists = await coreClient.playlists();

    expect(playlists.single.id, 'api-playlist');
    expect(rustClient.playlistsCalls, 1);
    expect(apiCalls, 1);
  });

  test('hybrid core client uses FastAPI directly when Rust local library disabled',
      () async {
    final rustClient = _RecordingCoreClient(
      playlistsResult: const [
        Playlist(id: 'rust-playlist', name: 'Rust', description: '', tracks: []),
      ],
    );
    var apiCalls = 0;
    final apiClient = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      httpClient: MockClient((request) async {
        apiCalls += 1;
        expect(request.url.path, '/api/playlists');
        return http.Response(
          '[{"id":"api-playlist","name":"FastAPI","description":"","tracks":[]}]',
          200,
        );
      }),
    );
    final coreClient = HybridCoreClient(
      apiClient: apiClient,
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(available: true, platform: 'test'),
      ),
      rustCoreClient: rustClient,
    );

    final playlists = await coreClient.playlists();

    expect(playlists.single.id, 'api-playlist');
    expect(rustClient.playlistsCalls, 0);
    expect(apiCalls, 1);
  });
}

class _RecordingCoreClient implements CoreClient {
  _RecordingCoreClient({
    this.playlistsResult = const [],
    this.throwOnPlaylists = false,
  });

  final List<Playlist> playlistsResult;
  final bool throwOnPlaylists;
  int playlistsCalls = 0;

  @override
  Future<List<Playlist>> playlists() async {
    playlistsCalls += 1;
    if (throwOnPlaylists) {
      throw StateError('Rust local playlists failed');
    }
    return playlistsResult;
  }

  @override
  Future<AlbumDetail> albumDetail(String browseId) => throw UnimplementedError();

  @override
  Future<ArtistDetail> artistDetail(String browseId) =>
      throw UnimplementedError();

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) =>
      throw UnimplementedError();

  @override
  Future<void> deletePlaylist(String id) => throw UnimplementedError();

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) =>
      throw UnimplementedError();

  @override
  Future<DiscoverResponse> discoverPlayable(String query) =>
      throw UnimplementedError();

  @override
  Future<List<Favorite>> favorites() => throw UnimplementedError();

  @override
  Future<void> favorite(PlaybackItem item) => throw UnimplementedError();

  @override
  Future<void> unfavorite(String favoriteId) => throw UnimplementedError();

  @override
  Future<void> addHistory(PlaybackItem item) => throw UnimplementedError();

  @override
  Future<List<PlaybackItem>> history() => throw UnimplementedError();

  @override
  Future<Playlist> updatePlaylist(
    String id, {
    String? name,
    String? description,
    List<PlaybackItem>? tracks,
  }) =>
      throw UnimplementedError();

  @override
  Future<NativeCoreHealth> nativeHealth() => throw UnimplementedError();

  @override
  Future<ResolveResponse> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) =>
      throw UnimplementedError();

  @override
  Future<RuntimeDebug> runtimeDebug() => throw UnimplementedError();

  @override
  Future<List<AdapterCapability>> sources() => throw UnimplementedError();
}

PlaybackItem _samplePlaybackItem() {
  return PlaybackItem(
    id: 'item-1',
    track: const TrackMetadata(
      id: 'track-1',
      title: 'Test Song',
      artists: [ArtistMetadata(id: 'artist-1', name: 'Test Artist')],
    ),
  );
}

class _FavoritesNativeCore implements NativeCore {
  _FavoritesNativeCore({required this.listResponse});

  final Map<String, dynamic> listResponse;
  var listCalls = 0;

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async {
    return {
      'ok': true,
      'data': {'echo': input},
    };
  }

  @override
  Future<Map<String, dynamic>> favoritesAddJson(
    String? databasePath,
    Map<String, dynamic> item,
  ) async {
    return {
      'ok': true,
      'data': {'id': 'rust-favorite', 'item': item},
    };
  }

  @override
  Future<Map<String, dynamic>> favoritesListJson(String? databasePath) async {
    listCalls += 1;
    return listResponse;
  }

  @override
  Future<Map<String, dynamic>> favoritesRemoveJson(
    String? databasePath,
    String favoriteId,
  ) async {
    return {'ok': true, 'data': null};
  }

  @override
  Future<NativeCoreHealth> health() async {
    return const NativeCoreHealth(
      available: true,
      version: 'streambox-core 0.1.0',
      platform: 'test-platform',
    );
  }

  @override
  Future<Map<String, dynamic>> historyAddJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> historyClearJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> historyListJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsCreateJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsDeleteJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsListJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsUpdateJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  Map<String, dynamic> _unsupported() {
    return {'ok': false, 'error': {'code': 'unsupported'}};
  }
}

Map<String, dynamic> _fixture(String relativePath) {
  final candidates = [
    File('docs/api-contract-fixtures/$relativePath'),
    File('../docs/api-contract-fixtures/$relativePath'),
  ];
  final file = candidates.firstWhere((candidate) => candidate.existsSync());
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

dynamic _fixtureResponse(String relativePath) {
  return _fixture(relativePath)['response'];
}

class _ContractNativeCore implements NativeCore {
  _ContractNativeCore({
    Map<String, dynamic>? playlistListResponse,
    Map<String, dynamic>? playlistCreateResponse,
    Map<String, dynamic>? playlistUpdateResponse,
    Map<String, dynamic>? playlistDeleteResponse,
    Map<String, dynamic>? favoritesListResponse,
    Map<String, dynamic>? favoritesAddResponse,
    Map<String, dynamic>? favoritesRemoveResponse,
    Map<String, dynamic>? historyListResponse,
    Map<String, dynamic>? historyAddResponse,
    Map<String, dynamic>? historyClearResponse,
  })  : playlistListResponse = playlistListResponse ?? _unsupportedResponse,
        playlistCreateResponse = playlistCreateResponse ?? _unsupportedResponse,
        playlistUpdateResponse = playlistUpdateResponse ?? _unsupportedResponse,
        playlistDeleteResponse = playlistDeleteResponse ?? _unsupportedResponse,
        favoritesListResponse = favoritesListResponse ?? _unsupportedResponse,
        favoritesAddResponse = favoritesAddResponse ?? _unsupportedResponse,
        favoritesRemoveResponse = favoritesRemoveResponse ?? _unsupportedResponse,
        historyListResponse = historyListResponse ?? _unsupportedResponse,
        historyAddResponse = historyAddResponse ?? _unsupportedResponse,
        historyClearResponse = historyClearResponse ?? _unsupportedResponse;

  static final Map<String, dynamic> _unsupportedResponse = <String, dynamic>{
    'ok': false,
    'error': {'code': 'unsupported', 'message': 'unsupported test call'},
  };

  final Map<String, dynamic> playlistListResponse;
  final Map<String, dynamic> playlistCreateResponse;
  final Map<String, dynamic> playlistUpdateResponse;
  final Map<String, dynamic> playlistDeleteResponse;
  final Map<String, dynamic> favoritesListResponse;
  final Map<String, dynamic> favoritesAddResponse;
  final Map<String, dynamic> favoritesRemoveResponse;
  final Map<String, dynamic> historyListResponse;
  final Map<String, dynamic> historyAddResponse;
  final Map<String, dynamic> historyClearResponse;

  final playlistListInputs = <Map<String, dynamic>>[];
  final playlistCreateInputs = <Map<String, dynamic>>[];
  final playlistUpdateInputs = <Map<String, dynamic>>[];
  final playlistDeleteInputs = <Map<String, dynamic>>[];
  final favoritesListDatabasePaths = <String?>[];
  final favoritesAddDatabasePaths = <String?>[];
  final favoritesAddItems = <Map<String, dynamic>>[];
  final favoritesRemoveDatabasePaths = <String?>[];
  final favoritesRemoveIds = <String>[];
  final historyListInputs = <Map<String, dynamic>>[];
  final historyAddInputs = <Map<String, dynamic>>[];
  final historyClearInputs = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async {
    return {
      'ok': true,
      'data': {'echo': input},
    };
  }

  @override
  Future<Map<String, dynamic>> playlistsListJson(
    Map<String, dynamic> input,
  ) async {
    playlistListInputs.add(input);
    return playlistListResponse;
  }

  @override
  Future<Map<String, dynamic>> playlistsCreateJson(
    Map<String, dynamic> input,
  ) async {
    playlistCreateInputs.add(input);
    return playlistCreateResponse;
  }

  @override
  Future<Map<String, dynamic>> playlistsUpdateJson(
    Map<String, dynamic> input,
  ) async {
    playlistUpdateInputs.add(input);
    return playlistUpdateResponse;
  }

  @override
  Future<Map<String, dynamic>> playlistsDeleteJson(
    Map<String, dynamic> input,
  ) async {
    playlistDeleteInputs.add(input);
    return playlistDeleteResponse;
  }

  @override
  Future<Map<String, dynamic>> favoritesListJson(String? databasePath) async {
    favoritesListDatabasePaths.add(databasePath);
    return favoritesListResponse;
  }

  @override
  Future<Map<String, dynamic>> favoritesAddJson(
    String? databasePath,
    Map<String, dynamic> item,
  ) async {
    favoritesAddDatabasePaths.add(databasePath);
    favoritesAddItems.add(item);
    return favoritesAddResponse;
  }

  @override
  Future<Map<String, dynamic>> favoritesRemoveJson(
    String? databasePath,
    String favoriteId,
  ) async {
    favoritesRemoveDatabasePaths.add(databasePath);
    favoritesRemoveIds.add(favoriteId);
    return favoritesRemoveResponse;
  }

  @override
  Future<Map<String, dynamic>> historyListJson(
    Map<String, dynamic> input,
  ) async {
    historyListInputs.add(input);
    return historyListResponse;
  }

  @override
  Future<Map<String, dynamic>> historyAddJson(
    Map<String, dynamic> input,
  ) async {
    historyAddInputs.add(input);
    return historyAddResponse;
  }

  @override
  Future<Map<String, dynamic>> historyClearJson(
    Map<String, dynamic> input,
  ) async {
    historyClearInputs.add(input);
    return historyClearResponse;
  }

  @override
  Future<NativeCoreHealth> health() async {
    return const NativeCoreHealth(
      available: true,
      version: 'streambox-core 0.1.0',
      platform: 'test-platform',
    );
  }
}
