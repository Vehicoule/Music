import '../models.dart';
import 'track_resolver.dart';

class YouTubeExplodeEngine implements TrackResolver {
  static bool get isAvailable => true;

  @override
  Future<List<DiscoverItem>> search(String query, {int limit = 15}) async {
    // Uses youtube_explode_dart (pure Dart, no native deps).
    // Works everywhere as a fallback if yt-dlp/NewPipe are unavailable.
    // 
    // When implemented:
    // final yt = YoutubeExplode();
    // final results = await yt.search.search(query);
    // return results.take(limit).map(_toDiscoverItem).toList();
    
    throw UnimplementedError(
      'YouTubeExplodeEngine requires youtube_explode_dart dependency.'
    );
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    // When implemented:
    // final yt = YoutubeExplode();
    // final manifest = await yt.videos.streamsClient.getManifest(url);
    // final audio = manifest.audioOnly.first;
    // return SourceCandidate(
    //   adapter: 'youtube_explore',
    //   url: audio.url.toString(),
    //   title: '',
    //   sourceProvider: 'youtube',
    //   sourceId: url,
    //   sourceUrl: url,
    //   sourceKind: 'song',
    //   durationSeconds: null,
    // );
    
    throw UnimplementedError(
      'YouTubeExplodeEngine requires youtube_explode_dart dependency.'
    );
  }
}
