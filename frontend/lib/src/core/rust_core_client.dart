import '../native/native_core.dart';

class RustCoreClient {
  const RustCoreClient({required this.nativeCore});

  final NativeCore nativeCore;

  Future<NativeCoreHealth> nativeHealth() {
    return nativeCore.health();
  }

  Future<Map<String, dynamic>> echoJson(Map<String, dynamic> input) {
    return nativeCore.echoJson(input);
  }
}
