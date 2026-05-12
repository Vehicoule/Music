# Native core CI runner performance

The `rust` job is intentionally much smaller than the platform runner jobs. It only installs the Rust toolchain, checks formatting, and runs the Rust unit tests for `native/streambox_core`.

The `flutter` job does all of the Rust work needed for a Windows app shell plus Flutter work:

- installs both Rust and Flutter;
- resolves Dart packages with `flutter pub get`;
- runs static analysis and Flutter tests;
- builds the Windows Rust DLL; and
- builds the Windows Flutter debug shell.

The `android-bridge` job has the most setup and build work:

- installs Java, Android command-line tooling, Rust, and Flutter;
- installs or restores Android NDK `28.2.13676358`;
- resolves Dart packages;
- adds and compiles two Android Rust targets (`aarch64-linux-android` and `x86_64-linux-android`); and
- runs a Gradle-backed `flutter build apk --debug`.

This means the platform jobs spend time downloading SDKs and building generated/native artifacts before they reach the app checks, while the Rust job only compiles and tests one crate. To reduce repeated setup cost, the workflow now caches Cargo outputs, the Flutter SDK/pub cache, Gradle dependencies, and the Android NDK install.
