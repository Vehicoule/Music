import '../api_client.dart';
import '../models.dart';
import '../native/native_core.dart';

abstract class CoreClient {
  Future<DiscoverResponse> discover(String query, {String scope = 'all'});
  Future<DiscoverResponse> discoverPlayable(String query);
  Future<RuntimeDebug> runtimeDebug();
  Future<AlbumDetail> albumDetail(String browseId);
  Future<ArtistDetail> artistDetail(String browseId);
  Future<ResolveResponse> resolve(
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
  Future<NativeDbHealth> nativeDbHealth();
}

class CoreClientRoutingConfig {
  const CoreClientRoutingConfig({
    this.useRustLocalLibrary = true,
  });

  final bool useRustLocalLibrary;
}

const defaultRustDatabasePath = './data/streambox.sqlite3';

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
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.discover(query, scope: scope);
  }

  @override
  Future<DiscoverResponse> discoverPlayable(String query) {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.discoverPlayable(query);
  }

  @override
  Future<RuntimeDebug> runtimeDebug() {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.runtimeDebug();
  }

  @override
  Future<AlbumDetail> albumDetail(String browseId) {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.albumDetail(browseId);
  }

  @override
  Future<ArtistDetail> artistDetail(String browseId) {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.artistDetail(browseId);
  }

  @override
  Future<ResolveResponse> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.resolve(track, adapters: adapters, sourceUrl: sourceUrl);
  }

  @override
  Future<List<AdapterCapability>> sources() {
    final rustClient = rustCoreClient;
    if (rustClient == null) {
      throw StateError('Rust core client not available — FastAPI backend has been removed');
    }
    return rustClient.sources();
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

  @override
  Future<NativeDbHealth> nativeDbHealth() async {
    final rustClient = rustCoreClient;
    if (rustClient != null) {
      return rustClient.nativeDbHealth();
    }
    try {
      return NativeDbHealth.fromProtocol(
        await nativeCore.dbHealthJson(defaultRustDatabasePath),
      );
    } catch (error) {
      return NativeDbHealth.unavailable(error);
    }
  }
}
