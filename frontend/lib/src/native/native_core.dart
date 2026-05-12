import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeCoreHealth {
  const NativeCoreHealth({
    required this.available,
    this.version,
    this.platform,
    this.error,
  });

  final bool available;
  final String? version;
  final String? platform;
  final String? error;

  factory NativeCoreHealth.fromJson(Map<String, dynamic> json) {
    return NativeCoreHealth(
      available: json['available'] as bool? ?? false,
      version: json['version'] as String?,
      platform: json['platform'] as String?,
      error: json['error'] as String?,
    );
  }

  String get diagnosticLabel {
    if (available) {
      return 'Rust core: ${version ?? 'available'} (${platform ?? 'unknown platform'})';
    }
    return 'Rust core unavailable: ${error ?? 'native library not loaded'}';
  }
}

abstract class NativeCore {
  Future<NativeCoreHealth> health();
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> historyListJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> historyAddJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> historyClearJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> favoritesListJson(String? databasePath);
  Future<Map<String, dynamic>> favoritesAddJson(
    String? databasePath,
    Map<String, dynamic> item,
  );
  Future<Map<String, dynamic>> favoritesRemoveJson(
    String? databasePath,
    String favoriteId,
  );
  Future<Map<String, dynamic>> playlistsListJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> playlistsCreateJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> playlistsUpdateJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> playlistsDeleteJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> sourceIndexSearchJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> sourceIndexUpsertJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> sourceIndexClearJson(Map<String, dynamic> input);
  Future<Map<String, dynamic>> sourceIndexRebuildJson(Map<String, dynamic> input);
}

class StaticNativeCore implements NativeCore {
  const StaticNativeCore(this.value);

  final NativeCoreHealth value;

  @override
  Future<NativeCoreHealth> health() async => value;

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async {
    return {
      'ok': true,
      'data': {'echo': input},
    };
  }

  @override
  Future<Map<String, dynamic>> historyListJson(
    Map<String, dynamic> input,
  ) async {
    return {'ok': false, 'error': {'code': 'unsupported'}};
  }

  @override
  Future<Map<String, dynamic>> historyAddJson(
    Map<String, dynamic> input,
  ) async {
    return {'ok': false, 'error': {'code': 'unsupported'}};
  }

  @override
  Future<Map<String, dynamic>> historyClearJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> favoritesListJson(String? databasePath) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> favoritesAddJson(
    String? databasePath,
    Map<String, dynamic> item,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> favoritesRemoveJson(
    String? databasePath,
    String favoriteId,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsListJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsCreateJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsUpdateJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> playlistsDeleteJson(
    Map<String, dynamic> input,
  ) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> sourceIndexSearchJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> sourceIndexUpsertJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> sourceIndexClearJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  @override
  Future<Map<String, dynamic>> sourceIndexRebuildJson(Map<String, dynamic> input) async {
    return _unsupported();
  }

  Map<String, dynamic> _unsupported() {
    return {'ok': false, 'error': {'code': 'unsupported'}};
  }
}

class FfiNativeCore implements NativeCore {
  FfiNativeCore({String? libraryName}) : _libraryName = libraryName;

  final String? _libraryName;
  DynamicLibrary? _library;

  @override
  Future<NativeCoreHealth> health() async {
    DynamicLibrary library;
    try {
      library = _openLibrary();
    } catch (exception) {
      return NativeCoreHealth(
        available: false,
        error: exception.toString(),
      );
    }

    try {
      final version = _readOwnedString(library, 'streambox_version');
      final platformInfo = jsonDecode(
        _readOwnedString(library, 'streambox_platform_info_json'),
      ) as Map<String, dynamic>;
      return NativeCoreHealth(
        available: true,
        version: version,
        platform:
            '${platformInfo['target_os'] ?? 'unknown'}-${platformInfo['target_arch'] ?? 'unknown'}',
      );
    } catch (exception) {
      return NativeCoreHealth(
        available: false,
        error: exception.toString(),
      );
    }
  }

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_echo_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> historyListJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_history_list_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> historyAddJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_history_add_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> historyClearJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_history_clear_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> favoritesListJson(String? databasePath) async {
    return _callJson(
      _openLibrary(),
      'streambox_favorites_list_json',
      {'database_path': databasePath},
    );
  }

  @override
  Future<Map<String, dynamic>> favoritesAddJson(
    String? databasePath,
    Map<String, dynamic> item,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_favorites_add_json',
      {'database_path': databasePath, 'item': item},
    );
  }

  @override
  Future<Map<String, dynamic>> favoritesRemoveJson(
    String? databasePath,
    String favoriteId,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_favorites_remove_json',
      {'database_path': databasePath, 'id': favoriteId},
    );
  }

  @override
  Future<Map<String, dynamic>> playlistsListJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_playlists_list_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> playlistsCreateJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_playlists_create_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> playlistsUpdateJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_playlists_update_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> playlistsDeleteJson(
    Map<String, dynamic> input,
  ) async {
    return _callJson(
      _openLibrary(),
      'streambox_playlists_delete_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> sourceIndexSearchJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_source_index_search_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> sourceIndexUpsertJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_source_index_upsert_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> sourceIndexClearJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_source_index_clear_json',
      input,
    );
  }

  @override
  Future<Map<String, dynamic>> sourceIndexRebuildJson(Map<String, dynamic> input) async {
    return _callJson(
      _openLibrary(),
      'streambox_source_index_rebuild_json',
      input,
    );
  }

  DynamicLibrary _openLibrary() {
    return _library ??=
        DynamicLibrary.open(_libraryName ?? _defaultLibraryName());
  }

  String _defaultLibraryName() {
    if (Platform.isWindows) {
      return 'streambox_core.dll';
    }
    if (Platform.isMacOS) {
      return 'libstreambox_core.dylib';
    }
    return 'libstreambox_core.so';
  }
}

typedef _NativeString = Pointer<Char> Function();
typedef _DartString = Pointer<Char> Function();
typedef _NativeJsonCall = Pointer<Char> Function(Pointer<Char>);
typedef _DartJsonCall = Pointer<Char> Function(Pointer<Char>);
typedef _NativeFree = Void Function(Pointer<Char>);
typedef _DartFree = void Function(Pointer<Char>);

String _readOwnedString(DynamicLibrary library, String symbol) {
  final getString = library.lookupFunction<_NativeString, _DartString>(symbol);
  final pointer = getString();
  return _readAndFreeOwnedString(library, pointer);
}

Map<String, dynamic> _callJson(
  DynamicLibrary library,
  String symbol,
  Map<String, dynamic> input,
) {
  final callJson =
      library.lookupFunction<_NativeJsonCall, _DartJsonCall>(symbol);
  final inputPointer =
      jsonEncode(input).toNativeUtf8(allocator: calloc).cast<Char>();
  try {
    final outputPointer = callJson(inputPointer);
    final output = _readAndFreeOwnedString(library, outputPointer);
    return jsonDecode(output) as Map<String, dynamic>;
  } finally {
    calloc.free(inputPointer);
  }
}

String _readAndFreeOwnedString(DynamicLibrary library, Pointer<Char> pointer) {
  final freeString =
      library.lookupFunction<_NativeFree, _DartFree>('streambox_string_free');
  if (pointer == nullptr) {
    return '';
  }
  try {
    return _readNullTerminatedUtf8(pointer);
  } finally {
    freeString(pointer);
  }
}

String _readNullTerminatedUtf8(Pointer<Char> pointer) {
  final bytes = pointer.cast<Uint8>();
  var length = 0;
  while ((bytes + length).value != 0) {
    length++;
  }
  return utf8.decode(bytes.asTypedList(length));
}
