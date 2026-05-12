import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';
import 'core_client.dart';

class RustCoreClient implements CoreClient {
  const RustCoreClient({
    required this.nativeCore,
    required this.fallbackApiClient,
    String? dbPath,
    String? databasePath,
  }) : dbPath = dbPath ?? databasePath;

  final NativeCore nativeCore;
  final ApiClient fallbackApiClient;
  final String? dbPath;

  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) {
    return nativeCore.echoJson(input);
  }

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) async {
    if (scope == 'songs' || scope == 'videos') {
      final cached = await _discoverFromSourceIndex(query, scope: scope);
      if (cached != null) {
        return cached;
      }
    }
    final response = await fallbackApiClient.discover(query, scope: scope);
    await _cacheSourceIndexItems(response.items);
    return response;
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) {
    return fallbackApiClient.discoverPlayable(query);
  }

  Future<DiscoverResponse?> _discoverFromSourceIndex(
    String query, {
    required String scope,
  }) async {
    late final Map<String, dynamic> response;
    try {
      response = await nativeCore.sourceIndexSearchJson({
        'database_path': dbPath,
        'query': query,
        'scope': scope,
        'limit': 12,
      });
    } catch (_) {
      return null;
    }
    dynamic payload;
    try {
      payload = _unwrapJsonProtocol(response);
    } catch (_) {
      return null;
    }
    final data = payload as List<dynamic>;
    if (data.isEmpty) {
      return null;
    }
    final entries = data
        .map((item) => item as Map<String, dynamic>)
        .toList();
    final bestScore =
        (entries.first['confidence_score'] as num?)?.toDouble() ?? 0;
    if (bestScore < 90) {
      return null;
    }
    return DiscoverResponse.fromJson({
      'query': query,
      'mode': 'stream',
      'scope': scope,
      'items': entries.map(_sourceIndexDiscoverItemJson).toList(),
      'warnings': const [],
    });
  }

  Future<void> _cacheSourceIndexItems(List<DiscoverItem> items) async {
    final entries = items
        .map(_sourceIndexEntryJson)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (entries.isEmpty) {
      return;
    }
    try {
      await nativeCore.sourceIndexUpsertJson({
        'database_path': dbPath,
        'entries': entries,
      });
    } catch (_) {
      // Source-index writes are opportunistic; network discovery remains authoritative.
    }
  }

  @override
  Future<RuntimeDebug> runtimeDebug() => fallbackApiClient.runtimeDebug();

  @override
  Future<AlbumDetail> albumDetail(String browseId) {
    return fallbackApiClient.albumDetail(browseId);
  }

  @override
  Future<ArtistDetail> artistDetail(String browseId) {
    return fallbackApiClient.artistDetail(browseId);
  }

  @override
  Future<ResolveResponse> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) {
    return fallbackApiClient.resolve(
      track,
      adapters: adapters,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Future<List<AdapterCapability>> sources() => fallbackApiClient.sources();

  @override
  Future<List<Playlist>> playlists() async {
    final response = await nativeCore.playlistsListJson({});
    final payload = _unwrapJsonProtocol(response);
    return (payload as List<dynamic>)
        .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) async {
    final response = await nativeCore.playlistsCreateJson({
      'name': name,
      'tracks': tracks.map((item) => item.toJson()).toList(),
    });
    return Playlist.fromJson(
      _unwrapJsonProtocol(response) as Map<String, dynamic>,
    );
  }

  @override
  Future<Playlist> updatePlaylist(
    String id, {
    String? name,
    String? description,
    List<PlaybackItem>? tracks,
  }) async {
    final response = await nativeCore.playlistsUpdateJson({
      'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (tracks != null)
        'tracks': tracks.map((item) => item.toJson()).toList(),
    });
    return Playlist.fromJson(
      _unwrapJsonProtocol(response) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deletePlaylist(String id) async {
    final response = await nativeCore.playlistsDeleteJson({'id': id});
    _unwrapJsonProtocol(response);
  }

  @override
  Future<List<Favorite>> favorites() async {
    final response = await nativeCore.favoritesListJson(dbPath);
    final data = _unwrapJsonProtocol(response) as List<dynamic>;
    return data
        .map((item) => Favorite.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> favorite(PlaybackItem item) async {
    final response = await nativeCore.favoritesAddJson(
      dbPath,
      item.toJson(),
    );
    _unwrapJsonProtocol(response);
  }

  @override
  Future<void> unfavorite(String favoriteId) async {
    final response = await nativeCore.favoritesRemoveJson(
      dbPath,
      favoriteId,
    );
    _unwrapJsonProtocol(response);
  }

  @override
  Future<void> addHistory(PlaybackItem item) async {
    _requireOk(await nativeCore.historyAddJson({
      'db_path': dbPath,
      'item': item.toJson(),
    }));
  }

  @override
  Future<List<PlaybackItem>> history() async {
    final response = _requireOk(await nativeCore.historyListJson({
      'db_path': dbPath,
    }));
    return (response['data'] as List<dynamic>? ?? [])
        .map((item) => PlaybackItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() async {
    _requireOk(await nativeCore.historyClearJson({
      'db_path': dbPath,
    }));
  }

  @override
  Future<NativeCoreHealth> nativeHealth() => nativeCore.health();

  dynamic _unwrapJsonProtocol(Map<String, dynamic> response) {
    if (response['ok'] == true) {
      return response['data'];
    }
    final error = response['error'];
    if (error is Map<String, dynamic>) {
      throw StateError(
        '${error['code'] ?? 'native_error'}: ${error['message'] ?? ''}',
      );
    }
    throw StateError('native_error: invalid native response');
  }
}

Map<String, dynamic> _sourceIndexDiscoverItemJson(Map<String, dynamic> entry) {
  final sourceProvider = entry['source_provider'] as String? ?? '';
  final sourceId = entry['source_id'] as String? ?? '';
  final sourceKind = entry['source_kind'] as String? ?? '';
  final sourceUrl = entry['source_url'] as String? ?? '';
  final durationSeconds = (entry['duration_seconds'] as num?)?.toDouble();
  return {
    'id': '$sourceProvider:$sourceId',
    'mode': 'stream',
    'kind': sourceKind == 'video' ? 'video' : 'song',
    'label': 'Source index',
    'track': {
      'id': '$sourceProvider:$sourceId',
      'title': entry['title'],
      'artists': [
        {
          'name': (entry['artist'] as String?)?.isNotEmpty == true
              ? entry['artist']
              : sourceProvider,
        },
      ],
      if ((entry['album'] as String?)?.isNotEmpty == true)
        'album': {'title': entry['album']},
      if (durationSeconds != null)
        'length_ms': (durationSeconds * 1000).round(),
      'confidence_score': entry['confidence_score'],
      'rank_reason': entry['rank_reason'],
      'artwork_url': entry['artwork_url'],
      'source_provider': sourceProvider,
      'source_id': sourceId,
      'source_url': sourceUrl,
      'source_kind': sourceKind,
      'raw_title': entry['raw_title'],
      'canonical_title': entry['canonical_title'],
      'canonical_artist': entry['canonical_artist'],
      'parse_source': entry['parse_source'],
      'source': sourceProvider,
    },
    'source': {
      'adapter': sourceProvider == 'youtube' ? 'ytdlp' : sourceProvider,
      'url': sourceUrl,
      'title': entry['raw_title'] ?? entry['title'],
      'duration_seconds': durationSeconds,
      'source_provider': sourceProvider,
      'source_id': sourceId,
      'source_url': sourceUrl,
      'source_kind': sourceKind,
      'raw_title': entry['raw_title'],
      'canonical_title': entry['canonical_title'],
      'canonical_artist': entry['canonical_artist'],
      'album_title': entry['album'],
      'artwork_url': entry['artwork_url'],
      'parse_source': entry['parse_source'],
      'confidence_score': entry['confidence_score'],
      'rank_reason': entry['rank_reason'],
    },
  };
}

Map<String, dynamic>? _sourceIndexEntryJson(DiscoverItem item) {
  final source = item.source;
  final track = item.track;
  final sourceProvider = source?.sourceProvider ?? track?.sourceProvider;
  final sourceId = source?.sourceId ?? track?.sourceId;
  final sourceUrl = source?.sourceUrl ?? track?.sourceUrl;
  if (sourceProvider == null || sourceId == null || sourceUrl == null) {
    return null;
  }
  return {
    'source_provider': sourceProvider,
    'source_id': sourceId,
    'source_url': sourceUrl,
    'title': source?.canonicalTitle ??
        track?.canonicalTitle ??
        track?.title ??
        source?.title ??
        '',
    'artist': source?.canonicalArtist ??
        track?.canonicalArtist ??
        track?.artistLabel ??
        '',
    'album': source?.albumTitle ?? track?.album?.title ?? '',
    'duration_seconds': source?.durationSeconds ??
        (track?.lengthMs == null ? null : track!.lengthMs! / 1000),
    'confidence_score': source?.confidenceScore ?? track?.confidenceScore ?? 0,
    'rank_reason': source?.rankReason ?? track?.rankReason ?? '',
    'artwork_url': source?.artworkUrl ?? track?.artworkUrl ?? '',
    'source_kind': source?.sourceKind ?? track?.sourceKind ?? item.kind,
    'raw_title': source?.rawTitle ??
        track?.rawTitle ??
        source?.title ??
        track?.title ??
        '',
    'canonical_title': source?.canonicalTitle ??
        track?.canonicalTitle ??
        track?.title ??
        source?.title ??
        '',
    'canonical_artist': source?.canonicalArtist ??
        track?.canonicalArtist ??
        track?.artistLabel ??
        '',
    'parse_source': source?.parseSource ?? track?.parseSource ?? 'structured',
  };
}

class RustCoreException implements Exception {
  const RustCoreException(this.message);

  final String message;

  @override
  String toString() => 'RustCoreException: $message';
}

Map<String, dynamic> _requireOk(Map<String, dynamic> response) {
  if (response['ok'] == true) {
    return response;
  }
  final error = response['error'];
  if (error is Map<String, dynamic>) {
    throw RustCoreException(
      '${error['code'] ?? 'unknown'}: ${error['message'] ?? 'Rust core request failed'}',
    );
  }
  throw const RustCoreException('Rust core request failed');
}
