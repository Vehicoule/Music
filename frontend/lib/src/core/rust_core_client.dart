import '../models.dart';
import '../native/native_core.dart';
import 'core_client.dart';

class RustCoreClient implements CoreClient {
  const RustCoreClient({
    required this.nativeCore,
    String? dbPath,
    String? databasePath,
  }) : dbPath = dbPath ?? databasePath;

  final NativeCore nativeCore;
  final String? dbPath;

  String get databasePath => dbPath ?? defaultRustDatabasePath;

  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) {
    return nativeCore.echoJson(input);
  }

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) async {
    // Use the Rust discovery orchestrator (source index -> yt-dlp -> MusicBrainz)
    final response = await nativeCore.discoverJson({
      if (dbPath != null) 'database_path': dbPath,
      'query': query,
      'limit': 12,
    });
    final payload = _unwrapJsonProtocol(response);
    final data = payload as Map<String, dynamic>;
    final rawItems = (data['items'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();
    final items = rawItems.map(_rustDiscoverResultToItem).toList();
    final warnings = (data['warnings'] as List<dynamic>)
        .map((item) => DiscoverWarning(
              code: 'rust_discovery',
              message: item as String? ?? '',
            ))
        .toList();
    return DiscoverResponse(
      query: query,
      mode: 'stream',
      scope: scope,
      items: items,
      warnings: warnings,
    );
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) async {
    // yt-dlp search returns playable results directly
    final response = await nativeCore.ytdlpSearchJson({
      'query': query,
      'limit': 15,
    });
    final tracks = _unwrapJsonProtocol(response) as List<dynamic>;
    final items = tracks
        .map((track) => _ytdlpTrackToDiscoverItem(track as Map<String, dynamic>))
        .toList();
    return DiscoverResponse(
      query: query,
      mode: 'stream',
      scope: 'all',
      items: items,
      warnings: const [],
    );
  }

  @override
  Future<RuntimeDebug> runtimeDebug() async {
    final response = await nativeCore.runtimeDebugJson({});
    final data = _unwrapJsonProtocol(response) as Map<String, dynamic>;
    return RuntimeDebug(
      apiVersion: data['api_version'] as String? ?? '',
      ytdlpAvailable: data['ytdlp_available'] as bool? ?? false,
      ytdlpPath: '',
    );
  }

  @override
  Future<AlbumDetail> albumDetail(String browseId) async {
    // Resolve the browse URL through yt-dlp to get album track details
    final response = await nativeCore.ytdlpResolveJson({
      'url': browseId,
    });
    final track = _unwrapJsonProtocol(response) as Map<String, dynamic>;
    final discoverItem = _ytdlpTrackToDiscoverItem(track);
    final title = track['title'] as String? ?? '';
    final uploader = track['uploader'] as String? ?? '';
    return AlbumDetail(
      title: title,
      artists: uploader.isNotEmpty
          ? [ArtistMetadata(name: uploader)]
          : const [],
      browseId: browseId,
      artworkUrl: track['thumbnail'] as String?,
      tracks: [discoverItem],
    );
  }

  @override
  Future<ArtistDetail> artistDetail(String browseId) async {
    // Resolve the browse URL through yt-dlp to get artist details
    final response = await nativeCore.ytdlpResolveJson({
      'url': browseId,
    });
    final track = _unwrapJsonProtocol(response) as Map<String, dynamic>;
    final title = track['title'] as String? ?? '';
    final uploader = track['uploader'] as String? ?? '';
    return ArtistDetail(
      name: uploader.isNotEmpty ? uploader : title,
      browseId: browseId,
      artworkUrl: track['thumbnail'] as String?,
      sections: const [],
    );
  }

  @override
  Future<ResolveResponse> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) async {
    final url = sourceUrl ??
        track.sourceUrl ??
        (track.album?.id != null ? 'https://music.youtube.com/browse/${track.album!.id}' : '');
    if (url.isEmpty) {
      throw const RustCoreException('No source URL available for resolution');
    }
    final response = await nativeCore.ytdlpResolveJson({
      'url': url,
    });
    final data = _unwrapJsonProtocol(response) as Map<String, dynamic>;
    final candidate = SourceCandidate(
      adapter: 'ytdlp',
      url: data['url'] as String? ?? url,
      title: data['title'] as String? ?? track.title,
      sourceProvider: 'youtube',
      sourceId: data['id'] as String?,
      sourceUrl: data['webpage_url'] as String? ?? url,
      sourceKind: 'song',
      durationSeconds: (data['duration_seconds'] as num?)?.toDouble(),
    );
    return ResolveResponse(
      candidates: [candidate],
      warnings: const [],
    );
  }

  @override
  Future<List<AdapterCapability>> sources() async {
    final response = await nativeCore.sourcesJson({});
    final data = _unwrapJsonProtocol(response) as List<dynamic>;
    return data
        .map((item) => AdapterCapability.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Playlist>> playlists() async {
    final response = await nativeCore.playlistsListJson({
      if (dbPath != null) 'database_path': dbPath,
    });
    final payload = _unwrapJsonProtocol(response);
    return (payload as List<dynamic>)
        .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) async {
    final response = await nativeCore.playlistsCreateJson({
      if (dbPath != null) 'database_path': dbPath,
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
      if (dbPath != null) 'database_path': dbPath,
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
    final response = await nativeCore.playlistsDeleteJson({
      if (dbPath != null) 'database_path': dbPath,
      'id': id,
    });
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

  @override
  Future<NativeDbHealth> nativeDbHealth() async {
    try {
      return NativeDbHealth.fromProtocol(
        await nativeCore.dbHealthJson(databasePath),
      );
    } catch (error) {
      return NativeDbHealth.unavailable(error);
    }
  }

  DiscoverItem _ytdlpTrackToDiscoverItem(Map<String, dynamic> track) {
    final id = track['id'] as String? ?? '';
    final title = track['title'] as String? ?? '';
    final url = track['url'] as String? ?? '';
    final webpageUrl = track['webpage_url'] as String? ?? url;
    final uploader = track['uploader'] as String? ?? '';
    final duration = (track['duration_seconds'] as num?)?.toDouble();
    final thumbnail = track['thumbnail'] as String?;

    return DiscoverItem(
      id: 'youtube:$id',
      mode: 'stream',
      kind: 'song',
      label: 'YouTube Music',
      track: TrackMetadata(
        id: 'youtube:$id',
        title: title,
        artists: uploader.isNotEmpty
            ? [ArtistMetadata(name: uploader)]
            : [const ArtistMetadata(name: 'YouTube')],
        lengthMs: duration != null ? (duration * 1000).round() : null,
        artworkUrl: thumbnail,
        sourceProvider: 'youtube',
        sourceId: id,
        sourceUrl: webpageUrl,
        sourceKind: 'song',
        source: 'youtube',
      ),
    );
  }

  DiscoverItem _rustDiscoverResultToItem(Map<String, dynamic> result) {
    // Rust DiscoverResult JSON has {mode, kind, label, track { ... }}
    // Map to DiscoverItem format expected by Flutter
    final mode = result['mode'] as String? ?? 'stream';
    final kind = result['kind'] as String? ?? 'song';
    final label = result['label'] as String?;
    final trackJson = result['track'] as Map<String, dynamic>?;
    final track = trackJson != null
        ? TrackMetadata.fromJson(trackJson)
        : null;
    return DiscoverItem(
      id: track?.id ?? '',
      mode: mode,
      kind: kind,
      track: track,
      label: label,
    );
  }

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
