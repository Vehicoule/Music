# Streambox Flutter Client

Flutter app source for Android, macOS, Linux, and Windows.

## Run

Flutter is installed locally at `..\.toolchains\flutter`.

```powershell
..\.toolchains\flutter\bin\flutter.bat pub get
..\.toolchains\flutter\bin\flutter.bat test
..\.toolchains\flutter\bin\flutter.bat run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The Android, macOS, Linux, and Windows platform folders have been generated. Windows desktop plugin builds require Windows Developer Mode because Flutter needs symlink support.

## Features

- MusicBrainz-backed search screen
- Source adapter health chips
- Direct stream URL entry
- `media_kit` playback
- Queue, previous/next, seek, repeat, shuffle
- Favorite current track
- Save current queue as a playlist
