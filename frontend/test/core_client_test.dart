import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/src/api_client.dart';
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

  test('rust core client exposes native echo json protocol', () async {
    final rustClient = RustCoreClient(
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

  test('rust source-index cache hits require backend resolution', () async {
    final nativeCore = _SourceIndexNativeCore({
      'ok': true,
      'data': [
        {
          'mode': 'stream',
          'kind': 'song',
          'label': 'Source index',
          'track': {
            'id': 'youtube:abc123',
            'title': 'Cached Song',
            'artists': [{'name': 'Cached Artist'}],
            'length_ms': 180000,
            'artwork_url': null,
            'source_provider': 'youtube',
            'source_id': 'abc123',
            'source_url': 'https://music.youtube.com/watch?v=abc123',
            'source_kind': 'song',
            'source': 'youtube',
          },
        },
      ],
    });
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
    );

    final response = await rustClient.discover('cached song', scope: 'songs');
    final item = response.items.single;

    expect(item.track?.title, 'Cached Song');
    expect(item.track?.sourceUrl, 'https://music.youtube.com/watch?v=abc123');
    expect(item.source, isNull);
    expect(nativeCore.searchCalls, 0);
  });

  test('rust source-index is skipped for uncacheable discover scopes', () async {
    final nativeCore = _SourceIndexNativeCore({
      'ok': true,
      'data': [
        {
          'mode': 'stream',
          'kind': 'song',
          'label': 'Source index',
          'track': {
            'id': 'youtube:abc123',
            'title': 'Cached Song',
            'artists': [{'name': 'Cached Artist'}],
            'length_ms': 180000,
            'artwork_url': null,
            'source_provider': 'youtube',
            'source_id': 'abc123',
            'source_url': 'https://music.youtube.com/watch?v=abc123',
            'source_kind': 'song',
            'source': 'youtube',
          },
        },
      ],
    });
    final requestedScopes = <String>[];
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
    );

    for (final scope in ['all', 'albums', 'artists']) {
      final response = await rustClient.discover('cached song', scope: scope);
      expect(response.scope, scope);
    }

    expect(nativeCore.searchCalls, 0);
    expect(requestedScopes, []);
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
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    final playlists = await rustClient.playlists();
    expect(playlists.single, isA<Playlist>());
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
    expect(created, isA<Playlist>());
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
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    final favorites = await rustClient.favorites();
    expect(favorites.single, isA<Favorite>());
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
      databasePath: '/tmp/streambox-contract.sqlite3',
    );

    await rustClient.addHistory(historyItem);
    expect(nativeCore.historyAddInputs.single['db_path'],
        '/tmp/streambox-contract.sqlite3');
    expect(nativeCore.historyAddInputs.single['item']['track']['source_provider'],
        'ytmusic');

    final history = await rustClient.history();
    expect(history.single, isA<PlaybackItem>());
    expect(history.single.id, 'playback-001');
    expect(history.single.track.canonicalArtist, 'Fixture Artist');
    expect(nativeCore.historyListInputs.single['db_path'],
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

  test('rust core client exposes successful Rust DB health diagnostics', () async {
    final nativeCore = _DbHealthNativeCore({
      'ok': true,
      'data': {
        'path': '/tmp/streambox-health.sqlite3',
        'schema_version': 3,
        'user_version': 3,
        'foreign_keys_enabled': true,
      },
    });
    final rustClient = RustCoreClient(
      nativeCore: nativeCore,
      databasePath: '/tmp/streambox-health.sqlite3',
    );

    final health = await rustClient.nativeDbHealth();

    expect(nativeCore.dbHealthPaths.single, '/tmp/streambox-health.sqlite3');
    expect(health.available, isTrue);
    expect(health.path, '/tmp/streambox-health.sqlite3');
    expect(health.schemaVersion, 3);
    expect(health.userVersion, 3);
    expect(health.foreignKeysEnabled, isTrue);
    expect(
      health.diagnosticLabels,
      containsAllInOrder([
        'DB path: /tmp/streambox-health.sqlite3',
        'Schema version: 3',
        'User version: 3',
        'Foreign keys enabled: yes',
      ]),
    );
  });

  test('rust core client falls back when Rust DB health is unavailable', () async {
    final rustClient = RustCoreClient(
      nativeCore: const StaticNativeCore(
        NativeCoreHealth(available: false, error: 'missing native library'),
      ),
    );

    final health = await rustClient.nativeDbHealth();

    expect(health.available, isFalse);
    expect(health.error, 'unsupported');
    expect(
      health.diagnosticLabels.single,
      'Rust DB health unavailable: unsupported',
    );
  });
}

class _DbHealthNativeCore extends StaticNativeCore {
  _DbHealthNativeCore(this.response)
      : super(const NativeCoreHealth(available: true, platform: 'test'));

  final Map<String, dynamic> response;
  final dbHealthPaths = <String>[];

  @override
  Future<Map<String, dynamic>> dbHealthJson(String databasePath) async {
    dbHealthPaths.add(databasePath);
    return response;
  }
}

class _SourceIndexNativeCore extends StaticNativeCore {
  _SourceIndexNativeCore(this.searchResponse)
      : super(const NativeCoreHealth(available: true, platform: 'test'));

  final Map<String, dynamic> searchResponse;
  var searchCalls = 0;

  @override
  Future<Map<String, dynamic>> sourceIndexSearchJson(
    Map<String, dynamic> input,
  ) async {
    searchCalls += 1;
    return searchResponse;
  }

  @override
  Future<Map<String, dynamic>> discoverJson(
    Map<String, dynamic> input,
  ) async {
    final data = searchResponse['data'];
    return {
      'ok': true,
      'data': {
        'items': data is List ? data : [],
        'warnings': <dynamic>[],
      },
    };
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
  Future<Map<String, dynamic>> dbHealthJson(String databasePath) async {
    return _unsupportedResponse;
  }

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

  @override
  Future<Map<String, dynamic>> sourceIndexClearJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> sourceIndexRebuildJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> sourceIndexSearchJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> sourceIndexUpsertJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> discoverJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> runtimeDebugJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> sourcesJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> ytdlpSearchJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> ytdlpResolveJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }

  @override
  Future<Map<String, dynamic>> ytdlpAvailableJson(Map<String, dynamic> input) async {
    return _unsupportedResponse;
  }
}
