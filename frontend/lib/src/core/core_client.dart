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
  Future<Playlist> updatePlaylist(
    String id, {
    String? name,
    String? description,
    List<PlaybackItem>? tracks,
  });
  Future<void> deletePlaylist(String id);
  Future<List<Favorite>> favorites();
  Future<void> favorite(PlaybackItem item);
  Future<void> unfavorite(String favoriteId);
  Future<void> addHistory(PlaybackItem item);
  Future<List<PlaybackItem>> history();
  Future<NativeCoreHealth> nativeHealth();
}

class CoreClientRoutingConfig {
  const CoreClientRoutingConfig({
    this.useRustLocalLibrary = false,
  });

  final bool useRustLocalLibrary;
}

class HybridCoreClient implements CoreClient {
  HybridCoreClient({
    required this.apiClient,
    required this.nativeCore,
    this.rustCoreClient,
    this.routingConfig = const CoreClientRoutingConfig(),
  });

  final ApiClient apiClient;
  final NativeCore nativeCore;
  final CoreClient? rustCoreClient;
  final CoreClientRoutingConfig routingConfig;

  Future<T> _rustLocalOrApi<T>(
    Future<T> Function(CoreClient client) rustRequest,
    Future<T> Function(ApiClient client) apiRequest,
  ) async {
    final rustClient = rustCoreClient;
    if (!routingConfig.useRustLocalLibrary || rustClient == null) {
      return apiRequest(apiClient);
    }

    try {
      return await rustRequest(rustClient);
    } catch (_) {
      return apiRequest(apiClient);
    }
  }

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
    return _rustLocalOrApi(
      (client) => client.playlists(),
      (client) => client.playlists(),
    );
  }

  @override
  Future<Playlist> createPlaylist(String name, List<PlaybackItem> tracks) {
    return _rustLocalOrApi(
      (client) => client.createPlaylist(name, tracks),
      (client) => client.createPlaylist(name, tracks),
    );
  }

  @override
  Future<Playlist> updatePlaylist(
    String id, {
    String? name,
    String? description,
    List<PlaybackItem>? tracks,
  }) {
    return _rustLocalOrApi(
      (client) => client.updatePlaylist(
        id,
        name: name,
        description: description,
        tracks: tracks,
      ),
      (client) => client.updatePlaylist(
        id,
        name: name,
        description: description,
        tracks: tracks,
      ),
    );
  }

  @override
  Future<void> deletePlaylist(String id) {
    return _rustLocalOrApi(
      (client) => client.deletePlaylist(id),
      (client) => client.deletePlaylist(id),
    );
  }

  @override
  Future<List<Favorite>> favorites() {
    return _rustLocalOrApi(
      (client) => client.favorites(),
      (client) => client.favorites(),
    );
  }

  @override
  Future<void> favorite(PlaybackItem item) {
    return _rustLocalOrApi(
      (client) => client.favorite(item),
      (client) => client.favorite(item),
    );
  }

  @override
  Future<void> unfavorite(String favoriteId) {
    return _rustLocalOrApi(
      (client) => client.unfavorite(favoriteId),
      (client) => client.unfavorite(favoriteId),
    );
  }

  @override
  Future<void> addHistory(PlaybackItem item) {
    return _rustLocalOrApi(
      (client) => client.addHistory(item),
      (client) => client.addHistory(item),
    );
  }

  @override
  Future<List<PlaybackItem>> history() {
    return _rustLocalOrApi(
      (client) => client.history(),
      (client) => client.history(),
    );
  }

  @override
  Future<NativeCoreHealth> nativeHealth() {
    return rustCoreClient?.nativeHealth() ?? nativeCore.health();
  }

}
