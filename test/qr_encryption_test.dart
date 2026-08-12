import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

enc.Key _derivedKey() {
  const secret = String.fromEnvironment('QR_SIGNING_SECRET', defaultValue: 'ISTE_QR_SECRET_DEV_FALLBACK_32ch');
  final bytes = utf8.encode(secret);
  final hash = sha256.convert(bytes).bytes;
  return enc.Key(Uint8List.fromList(hash));
}

String _encryptPayload(String plaintext) {
  final key = _derivedKey();
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
  final encrypted = encrypter.encrypt(plaintext, iv: iv);
  return '${base64Url.encode(iv.bytes)}.${encrypted.base64}';
}

String _decryptPayload(String encryptedStr) {
  final parts = encryptedStr.split('.');
  if (parts.length != 2) throw const FormatException('Invalid QR payload format');
  final ivBytes = base64Url.decode(parts[0]);
  final iv = enc.IV(ivBytes);
  final encrypted = enc.Encrypted.fromBase64(parts[1]);
  final key = _derivedKey();
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
  return encrypter.decrypt(encrypted, iv: iv);
}

void main() {
  test('AES-256-GCM QR Payload Encryption and Decryption', () {
    final originalJson = jsonEncode({
      'uid': '00000000-0000-0000-0000-000000000001',
      'token': 'a1b2c3d4e5f678901234567890abcdef',
      'ts': 1723440000000,
    });

    final encryptedPayload = _encryptPayload(originalJson);
    expect(encryptedPayload.contains('.'), isTrue);

    final decryptedJson = _decryptPayload(encryptedPayload);
    expect(decryptedJson, equals(originalJson));

    final parsedPayload = jsonDecode(decryptedJson) as Map<String, dynamic>;
    expect(parsedPayload['uid'], equals('00000000-0000-0000-0000-000000000001'));
    expect(parsedPayload['token'], equals('a1b2c3d4e5f678901234567890abcdef'));
    expect(parsedPayload['ts'], equals(1723440000000));
  });
}
