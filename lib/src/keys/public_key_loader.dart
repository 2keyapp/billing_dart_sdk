// Conditional import: use file-based loader on IO platforms, stub on web.
import 'public_key_loader_stub.dart'
    if (dart.library.io) 'public_key_loader_io.dart'
    as loader;

/// Loads and validates public key PEM from a file path.
///
/// Validates that the file content contains the standard PEM boundaries
/// `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`.
///
/// On web this throws [UnsupportedError]. On mobile/desktop (dart:io) reads
/// the file and returns the PEM string.
///
/// Throws [FormatException] if the file is missing or content is not valid PEM.
String loadPublicKeyFromPath(String path) => loader.loadPublicKeyFromPath(path);
