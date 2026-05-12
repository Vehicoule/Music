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
}

class StaticNativeCore implements NativeCore {
  const StaticNativeCore(this.value);

  final NativeCoreHealth value;

  @override
  Future<NativeCoreHealth> health() async => value;

  @override
  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) async => {
        'ok': value.available,
        'api_version': value.version,
        'echo': input,
      };
}

class FfiNativeCore implements NativeCore {
  FfiNativeCore({String? libraryName}) : _libraryName = libraryName;

  final String? _libraryName;

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
    final library = _openLibrary();
    final response = _callJson(library, 'streambox_echo_json', input);
    return response;
  }

  DynamicLibrary _openLibrary() {
    return DynamicLibrary.open(_libraryName ?? _defaultLibraryName());
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
typedef _NativeJsonString = Pointer<Char> Function(Pointer<Utf8>);
typedef _DartJsonString = Pointer<Char> Function(Pointer<Utf8>);
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
  final call = library.lookupFunction<_NativeJsonString, _DartJsonString>(
    symbol,
  );
  final inputPointer = jsonEncode(input).toNativeUtf8();
  try {
    final responsePointer = call(inputPointer);
    final response = _readAndFreeOwnedString(library, responsePointer);
    if (response.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(response) as Map<String, dynamic>;
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
