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

const defaultRustDatabasePath = './data/streambox.sqlite3';
