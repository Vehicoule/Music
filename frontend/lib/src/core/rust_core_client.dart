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
  Future<List<Playlist>> playlists() => fallbackApiClient.playlists();

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) {
    return fallbackApiClient.createPlaylist(name, tracks);
  }

  @override
  Future<List<Favorite>> favorites() => fallbackApiClient.favorites();

  @override
  Future<void> favorite(PlaybackItem item) => fallbackApiClient.favorite(item);

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
