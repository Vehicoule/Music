import '../models.dart';
import '../native/native_core.dart';

/// Interface for resolving tracks to playable sources.
abstract class TrackResolver {
  /// Search for playable tracks matching [query].
  /// Returns raw track data maps (same format as yt-dlp JSON output).
  Future<List<Map<String, dynamic>>> search(String query);

  /// Resolve a URL to a playable [SourceCandidate].
  Future<SourceCandidate> resolve(String url);
}

/// Implementation of [TrackResolver] using NativeCore's yt-dlp methods.
class YtDlpEngine implements TrackResolver {
  YtDlpEngine({required this.nativeCore});

  final NativeCore nativeCore;

  @override
  Future<List<Map<String, dynamic>>> search(String query) async {
    final response = await nativeCore.ytdlpSearchJson({
      'query': query,
      'limit': 15,
    });
    final data = _unwrap(response);
    return (data as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    final response = await nativeCore.ytdlpResolveJson({
      'url': url,
    });
    final data = _unwrap(response) as Map<String, dynamic>;
    return SourceCandidate(
      adapter: 'ytdlp',
      url: data['url'] as String? ?? url,
      title: data['title'] as String? ?? '',
      sourceProvider: 'youtube',
      sourceId: data['id'] as String?,
      sourceUrl: data['webpage_url'] as String? ?? url,
      sourceKind: 'song',
      durationSeconds: (data['duration_seconds'] as num?)?.toDouble(),
    );
  }

  dynamic _unwrap(Map<String, dynamic> response) {
    if (response['ok'] == true) {
      return response['data'];
    }
    final error = response['error'];
    if (error is Map<String, dynamic>) {
      throw StateError(
        '${error['code'] ?? 'native_error'}: ${error['message'] ?? ''}',
      );
    }
    throw StateError('native_error: invalid native response');
  }
}
