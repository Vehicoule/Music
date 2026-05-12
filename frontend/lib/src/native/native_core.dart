import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

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
}

class StaticNativeCore implements NativeCore {
  const StaticNativeCore(this.value);

  final NativeCoreHealth value;

  @override
  Future<NativeCoreHealth> health() async => value;
}

class FfiNativeCore implements NativeCore {
  FfiNativeCore({String? libraryName}) : _libraryName = libraryName;

  final String? _libraryName;

  @override
  Future<NativeCoreHealth> health() async {
    DynamicLibrary library;
    try {
      library = DynamicLibrary.open(_libraryName ?? _defaultLibraryName());
    } catch (exception) {
      return NativeCoreHealth(
        available: false,
        error: exception.toString(),
      );
    }

    try {
      final version = _readOwnedString(library, 'streambox_version');
      final platformInfo =
          jsonDecode(_readOwnedString(library, 'streambox_platform_info_json'))
              as Map<String, dynamic>;
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
typedef _NativeFree = Void Function(Pointer<Char>);
typedef _DartFree = void Function(Pointer<Char>);

String _readOwnedString(DynamicLibrary library, String symbol) {
  final getString = library.lookupFunction<_NativeString, _DartString>(symbol);
  final freeString =
      library.lookupFunction<_NativeFree, _DartFree>('streambox_string_free');
  final pointer = getString();
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
