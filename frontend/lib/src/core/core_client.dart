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
  Future<void> unfavorite(String favoriteId);
  Future<void> addHistory(PlaybackItem item);
  Future<List<PlaybackItem>> history();
  Future<NativeCoreHealth> nativeHealth();
}

class HybridCoreClient implements CoreClient {
  const HybridCoreClient({
    required this.apiClient,
    required this.nativeCore,
    this.rustCoreClient,
  });

  final ApiClient apiClient;
  final NativeCore nativeCore;
  final CoreClient? rustCoreClient;

  @override
  Future<DiscoverResponse> discover(String query, {String scope = 'all'}) {
    return rustCoreClient?.discover(query, scope: scope) ??
        apiClient.discover(query, scope: scope);
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) {
    return rustCoreClient?.discoverPlayable(query) ??
        apiClient.discoverPlayable(query);
  }

  @override
  Future<RuntimeDebug> runtimeDebug() {
    return rustCoreClient?.runtimeDebug() ?? apiClient.runtimeDebug();
  }

  @override
  Future<AlbumDetail> albumDetail(String browseId) {
    return rustCoreClient?.albumDetail(browseId) ??
        apiClient.albumDetail(browseId);
  }

  @override
  Future<ArtistDetail> artistDetail(String browseId) {
    return rustCoreClient?.artistDetail(browseId) ??
        apiClient.artistDetail(browseId);
  }

  @override
  Future<ResolveResult> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) {
    return rustCoreClient?.resolve(
          track,
          adapters: adapters,
          sourceUrl: sourceUrl,
        ) ??
        apiClient.resolve(track, adapters: adapters, sourceUrl: sourceUrl);
  }

  @override
  Future<List<AdapterCapability>> sources() {
    return rustCoreClient?.sources() ?? apiClient.sources();
  }

  @override
  Future<List<Playlist>> playlists() {
    return rustCoreClient?.playlists() ?? apiClient.playlists();
  }

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) {
    return rustCoreClient?.createPlaylist(name, tracks) ??
        apiClient.createPlaylist(name, tracks);
  }

  @override
  Future<List<Favorite>> favorites() {
    return _tryRust(() => rustCoreClient?.favorites(), apiClient.favorites);
  }

  @override
  Future<void> favorite(PlaybackItem item) {
    return _tryRust(
      () => rustCoreClient?.favorite(item),
      () => apiClient.favorite(item),
    );
  }

  @override
  Future<void> unfavorite(String favoriteId) {
    return _tryRust(
      () => rustCoreClient?.unfavorite(favoriteId),
      () => apiClient.unfavorite(favoriteId),
    );
  }

  @override
  Future<void> addHistory(PlaybackItem item) {
    return rustCoreClient?.addHistory(item) ?? apiClient.addHistory(item);
  }

  @override
  Future<List<PlaybackItem>> history() {
    return rustCoreClient?.history() ?? apiClient.history();
  }

  @override
  Future<NativeCoreHealth> nativeHealth() {
    return rustCoreClient?.nativeHealth() ?? nativeCore.health();
  }

  Future<T> _tryRust<T>(
    Future<T>? Function() rustCall,
    Future<T> Function() apiCall,
  ) async {
    final rustFuture = rustCall();
    if (rustFuture == null) {
      return apiCall();
    }
    try {
      return await rustFuture;
    } catch (_) {
      return apiCall();
    }
  }
}
