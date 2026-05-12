import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';
import 'core_client.dart';

class RustCoreClient implements CoreClient {
  const RustCoreClient({
    required this.nativeCore,
    required this.fallbackApiClient,
    this.databasePath = 'data/streambox.sqlite3',
  });

  final NativeCore nativeCore;
  final ApiClient fallbackApiClient;
  final String databasePath;

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
  Future<List<Favorite>> favorites() async {
    final response = await nativeCore.favoritesListJson(databasePath);
    final data = _unwrapJsonProtocol(response) as List<dynamic>;
    return data
        .map((item) => Favorite.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> favorite(PlaybackItem item) async {
    final response = await nativeCore.favoritesAddJson(
      databasePath,
      item.toJson(),
    );
    _unwrapJsonProtocol(response);
  }

  @override
  Future<void> unfavorite(String favoriteId) async {
    final response = await nativeCore.favoritesRemoveJson(
      databasePath,
      favoriteId,
    );
    _unwrapJsonProtocol(response);
  }

  @override
  Future<void> addHistory(PlaybackItem item) {
    return fallbackApiClient.addHistory(item);
  }

  @override
  Future<List<PlaybackItem>> history() => fallbackApiClient.history();

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
