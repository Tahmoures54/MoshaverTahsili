import 'dart:convert';
import 'package:moshaver_tahsili/education/education_store.dart';

/// Deterministic test double with key-bound envelopes; never used in production.
class MemorySecureLocalCipher implements SecureLocalCipher {
  @override
  Future<String> encrypt(String plaintext, {required String key}) async =>
      'enc:v2:${base64Encode(utf8.encode('$key:$plaintext'))}';

  @override
  Future<String> decrypt(String ciphertext, {required String key}) async {
    if (!ciphertext.startsWith('enc:v2:'))
      throw const FormatException('bad envelope');
    final decoded = utf8.decode(
      base64Decode(ciphertext.substring('enc:v2:'.length)),
    );
    if (!decoded.startsWith('$key:'))
      throw const FormatException('wrong key context');
    return decoded.substring(key.length + 1);
  }
}
