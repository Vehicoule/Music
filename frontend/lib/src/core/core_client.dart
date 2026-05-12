import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';

abstract class CoreClient {
  Future<DiscoverResponse> discover(String query, {String scope = 'all'});
  Future<DiscoverResponse> discoverPlayable(String query);
  Future<RuntimeDebug> runtimeDebug();
  Future<AlbumDetail> albumDetail(String browseId);
  Future<ArtistDetail> artistDetail(String browseId);
  Future<ResolveResult> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  });
  Future<List<AdapterCapability>> sources();
  Future<List<Playlist>> playlists();
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks);
  Future<List<Favorite>> favorites();
  Future<void> favorite(PlaybackItem item);
  Future<void> addHistory(PlaybackItem item);
  Future<List<PlaybackItem>> history();
  Future<NativeCoreHealth> nativeHealth();
}

class HybridCoreClient implements CoreClient {
  const HybridCoreClient({
    required this.apiClient,
    required this.nativeCore,
  });

  final ApiClient apiClient;
  final NativeCore nativeCore;

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) {
    return apiClient.discover(query, scope: scope);
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) {
    return apiClient.discoverPlayable(query);
  }

  @override
  Future<RuntimeDebug> runtimeDebug() => apiClient.runtimeDebug();

  @override
  Future<AlbumDetail> albumDetail(String browseId) {
    return apiClient.albumDetail(browseId);
  }

  @override
  Future<ArtistDetail> artistDetail(String browseId) {
    return apiClient.artistDetail(browseId);
  }

  @override
  Future<ResolveResult> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) {
    return apiClient.resolve(track, adapters: adapters, sourceUrl: sourceUrl);
  }

  @override
  Future<List<AdapterCapability>> sources() => apiClient.sources();

  @override
  Future<List<Playlist>> playlists() => apiClient.playlists();

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) {
    return apiClient.createPlaylist(name, tracks);
  }

  @override
  Future<List<Favorite>> favorites() => apiClient.favorites();

  @override
  Future<void> favorite(PlaybackItem item) => apiClient.favorite(item);

  @override
  Future<void> addHistory(PlaybackItem item) => apiClient.addHistory(item);

  @override
  Future<List<PlaybackItem>> history() => apiClient.history();

  @override
  Future<NativeCoreHealth> nativeHealth() => nativeCore.health();
}
