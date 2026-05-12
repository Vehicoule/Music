import '../models.dart';

typedef ResolveTrack = Future<ResolveResponse> Function(
  TrackMetadata track, {
  String? sourceUrl,
});

class ResolvePrefetcher {
  ResolvePrefetcher({required ResolveTrack resolve}) : _resolve = resolve;

  final ResolveTrack _resolve;
  final Map<String, List<SourceCandidate>> _cache = {};
  final Map<String, Future<void>> _inFlight = {};

  Future<void> prefetchTop(List<DiscoverItem> items, {int limit = 3}) async {
    final playable = items
        .where((item) => item.isPlayable && item.track != null)
        .take(limit);
    await Future.wait([for (final item in playable) prefetch(item)]);
  }

  Future<void> prefetch(DiscoverItem item) {
    final key = _key(item);
    if (key == null || _cache.containsKey(key)) {
      return Future.value();
    }
    final running = _inFlight[key];
    if (running != null) {
      return running;
    }
    final track = item.track!;
    final future = _resolve(track, sourceUrl: track.sourceUrl).then((result) {
      if (result.candidates.isNotEmpty) {
        _cache[key] = result.candidates;
      }
    }).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  List<SourceCandidate>? candidatesFor(DiscoverItem item) {
    final key = _key(item);
    return key == null ? null : _cache[key];
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  String? _key(DiscoverItem item) {
    final track = item.track;
    if (track == null || !item.isPlayable) {
      return null;
    }
    return '${track.id}:${track.sourceUrl ?? ''}';
  }
}
