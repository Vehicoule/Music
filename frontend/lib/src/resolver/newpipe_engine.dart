import 'dart:io';
import '../models.dart';
import 'track_resolver.dart';

class NewPipeEngine implements TrackResolver {
  static bool get isAvailable => Platform.isAndroid;

  @override
  Future<List<DiscoverItem>> search(String query, {int limit = 15}) async {
    // On Android, flutter_new_pipe_extractor handles YouTube Music search.
    // Since Flutter SDK isn't available, we can't actually import the package.
    // This is a skeleton that will be completed when the dependency is added.
    //
    // When implemented:
    // final results = await NewPipeExtractor.search(
    //   query,
    //   serviceId: ServiceId.youtubeMusic,
    //   contentFilters: [SearchContentFilters.musicSongs],
    // );
    // return results.items.take(limit).map(_toDiscoverItem).toList();

    throw UnimplementedError(
      'NewPipeEngine.search() requires flutter_new_pipe_extractor dependency. '
      'Add to pubspec.yaml and run flutter pub get.',
    );
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    // When implemented:
    // final info = await NewPipeExtractor.getVideoInfo(url);
    // final stream = info.audioStreams.first;
    // return SourceCandidate(
    //   adapter: 'newpipe',
    //   url: stream.content,
    //   title: info.name,
    //   sourceProvider: 'youtube',
    //   sourceId: info.id,
    //   sourceUrl: info.url,
    //   sourceKind: 'song',
    //   durationSeconds: info.duration.toDouble(),
    // );

    throw UnimplementedError(
      'NewPipeEngine.resolve() requires flutter_new_pipe_extractor dependency. '
      'Add to pubspec.yaml and run flutter pub get.',
    );
  }

  DiscoverItem _toDiscoverItem(/* VideoSearchResultItem */ result) {
    // When implemented, converts NewPipe search result → DiscoverItem
    throw UnimplementedError('Not yet implemented');
  }
}
