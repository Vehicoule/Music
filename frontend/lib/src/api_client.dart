import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Future<List<TrackMetadata>> search(String query) async {
    final uri =
        Uri.parse('$baseUrl/api/search').replace(queryParameters: {'q': query});
    final payload = await _getJson(uri);
    return (payload['tracks'] as List<dynamic>? ?? [])
        .map((item) => TrackMetadata.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DiscoverResponse> discover(String query,
      {String scope = 'all'}) async {
    final uri = Uri.parse('$baseUrl/api/discover')
        .replace(queryParameters: {'q': query, 'scope': scope});
    final payload = await _getJson(uri);
    return DiscoverResponse.fromJson(payload as Map<String, dynamic>);
  }

  Future<DiscoverResponse> discoverPlayable(String query) async {
    final uri = Uri.parse('$baseUrl/api/discover/playable')
        .replace(queryParameters: {'q': query});
    final payload = await _getJson(uri);
    return DiscoverResponse.fromJson(payload as Map<String, dynamic>);
  }

  Future<RuntimeDebug> runtimeDebug() async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/debug/runtime'));
    return RuntimeDebug.fromJson(payload as Map<String, dynamic>);
  }

  Future<AlbumDetail> albumDetail(String browseId) async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/albums/$browseId'));
    return AlbumDetail.fromJson(payload as Map<String, dynamic>);
  }

  Future<ArtistDetail> artistDetail(String browseId) async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/artists/$browseId'));
    return ArtistDetail.fromJson(payload as Map<String, dynamic>);
  }

  Future<ResolveResult> resolve(
    TrackMetadata track, {
    List<String> adapters = const [],
    String? sourceUrl,
  }) async {
    final payload = await _postJson(
      Uri.parse('$baseUrl/api/resolve'),
      {
        'track': track.toJson(),
        'adapters': adapters,
        'source_url': sourceUrl,
      },
    );
    return ResolveResult.fromJson(payload as Map<String, dynamic>);
  }

  Future<List<AdapterCapability>> sources() async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/sources'));
    return (payload as List<dynamic>)
        .map((item) => AdapterCapability.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Playlist>> playlists() async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/playlists'));
    return (payload as List<dynamic>)
        .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Playlist> createPlaylist(
      String name, List<PlaybackItem> tracks) async {
    final payload = await _postJson(
      Uri.parse('$baseUrl/api/playlists'),
      {
        'name': name,
        'tracks': tracks.map((item) => item.toJson()).toList(),
      },
    );
    return Playlist.fromJson(payload);
  }

  Future<List<Favorite>> favorites() async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/favorites'));
    return (payload as List<dynamic>)
        .map((item) => Favorite.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> favorite(PlaybackItem item) async {
    await _postJson(
        Uri.parse('$baseUrl/api/favorites'), {'item': item.toJson()});
  }

  Future<void> unfavorite(String favoriteId) async {
    await _delete(Uri.parse('$baseUrl/api/favorites/$favoriteId'));
  }

  Future<void> addHistory(PlaybackItem item) async {
    await _postJson(Uri.parse('$baseUrl/api/history'), {'item': item.toJson()});
  }

  Future<List<PlaybackItem>> history() async {
    final payload = await _getJson(Uri.parse('$baseUrl/api/history'));
    return (payload as List<dynamic>)
        .map((item) => PlaybackItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<dynamic> _getJson(Uri uri) async {
    final response = await _httpClient.get(uri);
    return _decode(response);
  }

  Future<dynamic> _postJson(Uri uri, Object payload) async {
    final response = await _httpClient.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decode(response);
  }

  Future<void> _delete(Uri uri) async {
    final response = await _httpClient.delete(uri);
    _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('HTTP ${response.statusCode}: ${response.body}');
    }
    if (response.body.isEmpty) {
      return null;
    }
    return jsonDecode(response.body);
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
