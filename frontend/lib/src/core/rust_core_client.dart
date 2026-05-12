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
  Future<List<Playlist>> playlists() async {
    final response = await nativeCore.playlistsListJson({});
    final payload = _requireNativeData(response);
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
      _requireNativeData(response) as Map<String, dynamic>,
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
      _requireNativeData(response) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deletePlaylist(String id) async {
    final response = await nativeCore.playlistsDeleteJson({'id': id});
    _requireNativeData(response);
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

dynamic _requireNativeData(Map<String, dynamic> response) {
  if (response['ok'] == true) {
    return response['data'];
  }
  final error = response['error'];
  if (error is Map<String, dynamic>) {
    throw NativeCoreProtocolException(
      error['code'] as String? ?? 'native_error',
      error['message'] as String? ?? 'native core call failed',
    );
  }
  throw const NativeCoreProtocolException(
    'native_error',
    'native core call failed',
  );
}
