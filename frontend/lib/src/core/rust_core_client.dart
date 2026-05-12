import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';
import 'core_client.dart';

class RustCoreClient implements CoreClient {
  const RustCoreClient({
    required this.nativeCore,
    required this.fallbackApiClient,
    this.dbPath,
  });

  final NativeCore nativeCore;
  final ApiClient fallbackApiClient;
  final String? dbPath;

  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) {
    return nativeCore.echoJson(input);
  }

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) {
    return fallbackApiClient.discover(query, scope: scope);
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) {
    return fallbackApiClient.discoverPlayable(query);
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
  Future<ResolveResult> resolve(
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
    await _requireOk(await nativeCore.historyAddJson({
      'db_path': dbPath,
      'item': item.toJson(),
    }));
  }

  @override
  Future<List<PlaybackItem>> history() async {
    final response = await _requireOk(await nativeCore.historyListJson({
      'db_path': dbPath,
    }));
    return (response['data'] as List<dynamic>? ?? [])
        .map((item) => PlaybackItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() async {
    await _requireOk(await nativeCore.historyClearJson({
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
