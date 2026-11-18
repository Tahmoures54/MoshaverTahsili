import 'dart:convert';
import 'package:moshaver_tahsili/education/education_store.dart';

class MemorySecureLocalCipher implements SecureLocalCipher {
  @override
  Future<String> encrypt(String plaintext) async =>
      'enc:v1:${base64Encode(utf8.encode(plaintext))}';
  @override
  Future<String> decrypt(String ciphertext) async {
    if (!ciphertext.startsWith('enc:v1:')) throw const FormatException('bad envelope');
    return utf8.decode(base64Decode(ciphertext.substring('enc:v1:'.length)));
  }
}
