# Windows storage integration

Vendored from flutter_secure_storage_windows 4.2.2 (MIT; see LICENSE).
Original source: https://github.com/mogol/flutter_secure_storage/tree/develop/flutter_secure_storage_windows

This new application uses the package's Dart FFI DPAPI implementation exclusively.
The manifest omits `pluginClass: FlutterSecureStorageWindowsPlugin` and the
legacy C++ backend, which otherwise requires the optional Visual Studio ATL component.
The `dartPluginClass` registration and Dart implementation are unchanged.
`Api` explicitly configures `WindowsOptions(useBackwardCompatibility: false)`.
There are no legacy application credentials to migrate. The same Windows DPAPI
protection is used; plaintext preferences are never used for session tokens.

When upgrading, refresh these vendored Dart files and keep the Dart-only plugin
manifest and explicit no-legacy-storage option. Verify native write/read/delete
on Windows before distributing a new package.
