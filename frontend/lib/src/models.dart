class ArtistMetadata {
  const ArtistMetadata({this.id, required this.name});

  final String? id;
  final String name;

  factory ArtistMetadata.fromJson(Map<String, dynamic> json) {
    return ArtistMetadata(
        id: json['id'] as String?, name: json['name'] as String? ?? '');
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class AlbumMetadata {
  const AlbumMetadata({
    this.id,
    this.title,
    this.releaseGroupId,
    this.artworkUrl,
  });

  final String? id;
  final String? title;
  final String? releaseGroupId;
  final String? artworkUrl;

  factory AlbumMetadata.fromJson(Map<String, dynamic> json) {
    return AlbumMetadata(
      id: json['id'] as String?,
      title: json['title'] as String?,
      releaseGroupId: json['release_group_id'] as String?,
      artworkUrl: json['artwork_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'release_group_id': releaseGroupId,
        'artwork_url': artworkUrl,
      };
}

class TrackMetadata {
  const TrackMetadata({
    required this.id,
    required this.title,
    required this.artists,
    this.album,
    this.lengthMs,
    this.score,
    this.releaseCount,
    this.listenCount,
    this.listenerCount,
    this.popularityScore,
    this.confidenceScore,
    this.rankReason,
    this.artworkUrl,
    this.sourceProvider,
    this.sourceId,
    this.sourceUrl,
    this.sourceKind,
    this.rawTitle,
    this.canonicalTitle,
    this.canonicalArtist,
    this.parseSource,
    this.matchReasons = const [],
    this.source = 'musicbrainz',
  });

  final String id;
  final String title;
  final List<ArtistMetadata> artists;
  final AlbumMetadata? album;
  final int? lengthMs;
  final int? score;
  final int? releaseCount;
  final int? listenCount;
  final int? listenerCount;
  final double? popularityScore;
  final double? confidenceScore;
  final String? rankReason;
  final String? artworkUrl;
  final String? sourceProvider;
  final String? sourceId;
  final String? sourceUrl;
  final String? sourceKind;
  final String? rawTitle;
  final String? canonicalTitle;
  final String? canonicalArtist;
  final String? parseSource;
  final List<String> matchReasons;
  final String source;

  String get artistLabel {
    final names =
        artists.map((artist) => artist.name).where((name) => name.isNotEmpty);
    return names.isEmpty ? 'Unknown artist' : names.join(', ');
  }

  factory TrackMetadata.fromJson(Map<String, dynamic> json) {
    return TrackMetadata(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artists: (json['artists'] as List<dynamic>? ?? [])
          .map((item) => ArtistMetadata.fromJson(item as Map<String, dynamic>))
          .toList(),
      album: json['album'] == null
          ? null
          : AlbumMetadata.fromJson(json['album'] as Map<String, dynamic>),
      lengthMs: json['length_ms'] as int?,
      score: json['score'] as int?,
      releaseCount: json['release_count'] as int?,
      listenCount: json['listen_count'] as int?,
      listenerCount: json['listener_count'] as int?,
      popularityScore: (json['popularity_score'] as num?)?.toDouble(),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      rankReason: json['rank_reason'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      sourceProvider: json['source_provider'] as String?,
      sourceId: json['source_id'] as String?,
      sourceUrl: json['source_url'] as String?,
      sourceKind: json['source_kind'] as String?,
      rawTitle: json['raw_title'] as String?,
      canonicalTitle: json['canonical_title'] as String?,
      canonicalArtist: json['canonical_artist'] as String?,
      parseSource: json['parse_source'] as String?,
      matchReasons: (json['match_reasons'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      source: json['source'] as String? ?? 'musicbrainz',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artists': artists.map((artist) => artist.toJson()).toList(),
        'album': album?.toJson(),
        'length_ms': lengthMs,
        'score': score,
        'release_count': releaseCount,
        'listen_count': listenCount,
        'listener_count': listenerCount,
        'popularity_score': popularityScore,
        'confidence_score': confidenceScore,
        'rank_reason': rankReason,
        'artwork_url': artworkUrl,
        'source_provider': sourceProvider,
        'source_id': sourceId,
        'source_url': sourceUrl,
        'source_kind': sourceKind,
        'raw_title': rawTitle,
        'canonical_title': canonicalTitle,
        'canonical_artist': canonicalArtist,
        'parse_source': parseSource,
        'match_reasons': matchReasons,
        'source': source,
      };
}

class RuntimeDebug {
  const RuntimeDebug({
    required this.apiVersion,
    required this.ytdlpAvailable,
    this.ytdlpPath = '',
  });

  final String apiVersion;
  final bool ytdlpAvailable;
  final String ytdlpPath;

  factory RuntimeDebug.fromJson(Map<String, dynamic> json) {
    return RuntimeDebug(
      apiVersion: json['api_version'] as String? ?? '',
      ytdlpAvailable: json['ytdlp_available'] as bool? ?? false,
      ytdlpPath: json['ytdlp_path'] as String? ?? '',
    );
  }
}

class SourceCandidate {
  const SourceCandidate({
    required this.adapter,
    required this.url,
    required this.title,
    this.mimeType,
    this.durationSeconds,
    this.sourceProvider,
    this.sourceId,
    this.sourceUrl,
    this.sourceKind,
    this.rawTitle,
    this.canonicalTitle,
    this.canonicalArtist,
    this.albumTitle,
    this.artworkUrl,
    this.parseSource,
    this.confidenceScore,
    this.rankReason,
    this.isLive = false,
    this.headers = const {},
  });

  final String adapter;
  final String url;
  final String title;
  final String? mimeType;
  final double? durationSeconds;
  final String? sourceProvider;
  final String? sourceId;
  final String? sourceUrl;
  final String? sourceKind;
  final String? rawTitle;
  final String? canonicalTitle;
  final String? canonicalArtist;
  final String? albumTitle;
  final String? artworkUrl;
  final String? parseSource;
  final double? confidenceScore;
  final String? rankReason;
  final bool isLive;
  final Map<String, String> headers;

  factory SourceCandidate.fromJson(Map<String, dynamic> json) {
    return SourceCandidate(
      adapter: json['adapter'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      mimeType: json['mime_type'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      sourceProvider: json['source_provider'] as String?,
      sourceId: json['source_id'] as String?,
      sourceUrl: json['source_url'] as String?,
      sourceKind: json['source_kind'] as String?,
      rawTitle: json['raw_title'] as String?,
      canonicalTitle: json['canonical_title'] as String?,
      canonicalArtist: json['canonical_artist'] as String?,
      albumTitle: json['album_title'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      parseSource: json['parse_source'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      rankReason: json['rank_reason'] as String?,
      isLive: json['is_live'] as bool? ?? false,
      headers: (json['headers'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value.toString())),
    );
  }

  Map<String, dynamic> toJson() => {
        'adapter': adapter,
        'url': url,
        'title': title,
        'mime_type': mimeType,
        'duration_seconds': durationSeconds,
        'source_provider': sourceProvider,
        'source_id': sourceId,
        'source_url': sourceUrl,
        'source_kind': sourceKind,
        'raw_title': rawTitle,
        'canonical_title': canonicalTitle,
        'canonical_artist': canonicalArtist,
        'album_title': albumTitle,
        'artwork_url': artworkUrl,
        'parse_source': parseSource,
        'confidence_score': confidenceScore,
        'rank_reason': rankReason,
        'is_live': isLive,
        'headers': headers,
      };
}

class DiscoverWarning {
  const DiscoverWarning({required this.code, required this.message});

  final String code;
  final String message;

  factory DiscoverWarning.fromJson(Map<String, dynamic> json) {
    return DiscoverWarning(
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

class AlbumSearchResult {
  const AlbumSearchResult({
    required this.title,
    this.artists = const [],
    this.browseId,
    this.playlistId,
    this.year,
    this.artworkUrl,
  });

  final String title;
  final List<ArtistMetadata> artists;
  final String? browseId;
  final String? playlistId;
  final String? year;
  final String? artworkUrl;

  String get artistLabel {
    final names =
        artists.map((artist) => artist.name).where((name) => name.isNotEmpty);
    return names.isEmpty ? 'Unknown artist' : names.join(', ');
  }

  factory AlbumSearchResult.fromJson(Map<String, dynamic> json) {
    return AlbumSearchResult(
      title: json['title'] as String? ?? '',
      artists: (json['artists'] as List<dynamic>? ?? [])
          .map((item) => ArtistMetadata.fromJson(item as Map<String, dynamic>))
          .toList(),
      browseId: json['browse_id'] as String?,
      playlistId: json['playlist_id'] as String?,
      year: json['year'] as String?,
      artworkUrl: json['artwork_url'] as String?,
    );
  }
}

class ArtistSearchResult {
  const ArtistSearchResult({
    required this.name,
    this.browseId,
    this.channelId,
    this.artworkUrl,
  });

  final String name;
  final String? browseId;
  final String? channelId;
  final String? artworkUrl;

  factory ArtistSearchResult.fromJson(Map<String, dynamic> json) {
    return ArtistSearchResult(
      name: json['name'] as String? ?? '',
      browseId: json['browse_id'] as String?,
      channelId: json['channel_id'] as String?,
      artworkUrl: json['artwork_url'] as String?,
    );
  }
}

class DiscoverItem {
  const DiscoverItem({
    required this.id,
    required this.mode,
    this.kind = 'metadata',
    this.track,
    this.albumResult,
    this.artistResult,
    this.source,
    this.label,
  });

  final String id;
  final String mode;
  final String kind;
  final TrackMetadata? track;
  final AlbumSearchResult? albumResult;
  final ArtistSearchResult? artistResult;
  final SourceCandidate? source;
  final String? label;

  bool get isPlayable =>
      (kind == 'song' || kind == 'video' || kind == 'metadata') &&
      (source != null || track?.sourceUrl != null || track != null);

  String get displayTitle {
    if (track != null) {
      return track!.title;
    }
    if (albumResult != null) {
      return albumResult!.title;
    }
    if (artistResult != null) {
      return artistResult!.name;
    }
    return '';
  }

  String get displaySubtitle {
    if (track != null) {
      final parts = [
        track!.artistLabel,
        if (track!.album?.title != null && track!.album!.title!.isNotEmpty)
          track!.album!.title!,
        if (track!.lengthMs != null) _duration(track!.lengthMs!),
      ];
      return parts.join(' · ');
    }
    if (albumResult != null) {
      return [
        albumResult!.artistLabel,
        if (albumResult!.year != null && albumResult!.year!.isNotEmpty)
          albumResult!.year!,
      ].join(' · ');
    }
    if (artistResult != null) {
      return 'Artist';
    }
    return '';
  }

  String? get artworkUrl =>
      track?.artworkUrl ??
      track?.album?.artworkUrl ??
      albumResult?.artworkUrl ??
      artistResult?.artworkUrl;

  factory DiscoverItem.fromJson(Map<String, dynamic> json) {
    return DiscoverItem(
      id: json['id'] as String? ?? '',
      mode: json['mode'] as String? ?? 'metadata',
      kind: json['kind'] as String? ?? 'metadata',
      track: json['track'] == null
          ? null
          : TrackMetadata.fromJson(json['track'] as Map<String, dynamic>),
      albumResult: json['album_result'] == null
          ? null
          : AlbumSearchResult.fromJson(
              json['album_result'] as Map<String, dynamic>),
      artistResult: json['artist_result'] == null
          ? null
          : ArtistSearchResult.fromJson(
              json['artist_result'] as Map<String, dynamic>),
      source: json['source'] == null
          ? null
          : SourceCandidate.fromJson(json['source'] as Map<String, dynamic>),
      label: json['label'] as String?,
    );
  }
}

String _duration(int lengthMs) {
  final duration = Duration(milliseconds: lengthMs);
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class DiscoverResponse {
  const DiscoverResponse({
    required this.query,
    required this.mode,
    this.scope = 'all',
    required this.items,
    required this.warnings,
  });

  final String query;
  final String mode;
  final String scope;
  final List<DiscoverItem> items;
  final List<DiscoverWarning> warnings;

  factory DiscoverResponse.fromJson(Map<String, dynamic> json) {
    return DiscoverResponse(
      query: json['query'] as String? ?? '',
      mode: json['mode'] as String? ?? 'metadata',
      scope: json['scope'] as String? ?? 'all',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => DiscoverItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((item) => DiscoverWarning.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DetailSection {
  const DetailSection({required this.label, required this.items});

  final String label;
  final List<DiscoverItem> items;

  factory DetailSection.fromJson(Map<String, dynamic> json) {
    return DetailSection(
      label: json['label'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => DiscoverItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AlbumDetail {
  const AlbumDetail({
    required this.title,
    this.artists = const [],
    this.browseId,
    this.playlistId,
    this.year,
    this.artworkUrl,
    this.tracks = const [],
  });

  final String title;
  final List<ArtistMetadata> artists;
  final String? browseId;
  final String? playlistId;
  final String? year;
  final String? artworkUrl;
  final List<DiscoverItem> tracks;

  String get artistLabel {
    final names =
        artists.map((artist) => artist.name).where((name) => name.isNotEmpty);
    return names.isEmpty ? 'Unknown artist' : names.join(', ');
  }

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    return AlbumDetail(
      title: json['title'] as String? ?? '',
      artists: (json['artists'] as List<dynamic>? ?? [])
          .map((item) => ArtistMetadata.fromJson(item as Map<String, dynamic>))
          .toList(),
      browseId: json['browse_id'] as String?,
      playlistId: json['playlist_id'] as String?,
      year: json['year'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      tracks: (json['tracks'] as List<dynamic>? ?? [])
          .map((item) => DiscoverItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ArtistDetail {
  const ArtistDetail({
    required this.name,
    this.browseId,
    this.channelId,
    this.artworkUrl,
    this.sections = const [],
  });

  final String name;
  final String? browseId;
  final String? channelId;
  final String? artworkUrl;
  final List<DetailSection> sections;

  factory ArtistDetail.fromJson(Map<String, dynamic> json) {
    return ArtistDetail(
      name: json['name'] as String? ?? '',
      browseId: json['browse_id'] as String?,
      channelId: json['channel_id'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((item) => DetailSection.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ResolveResult {
  const ResolveResult({required this.candidates, required this.warnings});

  final List<SourceCandidate> candidates;
  final List<DiscoverWarning> warnings;

  factory ResolveResult.fromJson(Map<String, dynamic> json) {
    return ResolveResult(
      candidates: (json['candidates'] as List<dynamic>? ?? [])
          .map((item) => SourceCandidate.fromJson(item as Map<String, dynamic>))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((item) => DiscoverWarning.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  String get warningMessage {
    return warnings.map((warning) => warning.message).where((message) {
      return message.trim().isNotEmpty;
    }).join('\n');
  }
}

class PlaybackItem {
  const PlaybackItem({
    required this.id,
    required this.track,
    this.source,
    this.addedAt,
  });

  final String id;
  final TrackMetadata track;
  final SourceCandidate? source;
  final DateTime? addedAt;

  factory PlaybackItem.fromTrack(TrackMetadata track, SourceCandidate source) {
    return PlaybackItem(
      id: '${track.id}-${DateTime.now().microsecondsSinceEpoch}',
      track: track,
      source: source,
      addedAt: DateTime.now().toUtc(),
    );
  }

  factory PlaybackItem.fromJson(Map<String, dynamic> json) {
    return PlaybackItem(
      id: json['id'] as String? ?? '',
      track: TrackMetadata.fromJson(json['track'] as Map<String, dynamic>),
      source: json['source'] == null
          ? null
          : SourceCandidate.fromJson(json['source'] as Map<String, dynamic>),
      addedAt: DateTime.tryParse(json['added_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': track.toJson(),
        'source': source?.toJson(),
        'added_at': addedAt?.toIso8601String(),
      };
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.tracks,
  });

  final String id;
  final String name;
  final String description;
  final List<PlaybackItem> tracks;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tracks: (json['tracks'] as List<dynamic>? ?? [])
          .map((item) => PlaybackItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'tracks': tracks.map((item) => item.toJson()).toList(),
      };
}

class Favorite {
  const Favorite({required this.id, required this.item});

  final String id;
  final PlaybackItem item;

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      id: json['id'] as String? ?? '',
      item: PlaybackItem.fromJson(json['item'] as Map<String, dynamic>),
    );
  }
}

class AdapterCapability {
  const AdapterCapability({
    required this.name,
    required this.enabled,
    required this.healthy,
    required this.label,
    this.notes,
  });

  final String name;
  final bool enabled;
  final bool healthy;
  final String label;
  final String? notes;

  factory AdapterCapability.fromJson(Map<String, dynamic> json) {
    return AdapterCapability(
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      healthy: json['healthy'] as bool? ?? false,
      label: json['label'] as String? ?? '',
      notes: json['notes'] as String?,
    );
  }
}
