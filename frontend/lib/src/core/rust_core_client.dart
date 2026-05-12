import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';
import 'core_client.dart';

class RustCoreClient implements CoreClient {
  const RustCoreClient({
    required this.nativeCore,
    required this.fallbackApiClient,
  });

  final NativeCore nativeCore;
  final ApiClient fallbackApiClient;

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
  Future<void> addHistory(PlaybackItem item) {
    return fallbackApiClient.addHistory(item);
  }

  @override
  Future<List<PlaybackItem>> history() => fallbackApiClient.history();

  @override
  Future<NativeCoreHealth> nativeHealth() => nativeCore.health();
}
