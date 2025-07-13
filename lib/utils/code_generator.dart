import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class CodeGenerator {
  static const String _uppercaseLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercaseLetters = 'abcdefghijklmnopqrstuvwxyz';
  static const String _numbers = '0123456789';
  static const String _alphanumeric =
      _uppercaseLetters + _lowercaseLetters + _numbers;
  static const String _roomCodeChars = _uppercaseLetters + _numbers;

  static final Random _random = Random.secure();
  static const Uuid _uuid = Uuid();

  /// Generates a unique room code (6 characters, uppercase letters and numbers)
  static String generateRoomCode() {
    final code = List.generate(
      6,
      (index) => _roomCodeChars[_random.nextInt(_roomCodeChars.length)],
    ).join();
    return code;
  }

  /// Generates a unique ID using UUID v4
  static String generateId() {
    return _uuid.v4();
  }

  /// Generates a unique session ID
  static String generateSessionId() {
    return _uuid.v4();
  }

  /// Generates a unique peer ID for WebRTC connections
  static String generatePeerId() {
    return _uuid.v4();
  }

  /// Generates a random alphanumeric string of specified length
  static String generateRandomString(int length) {
    return List.generate(
      length,
      (index) => _alphanumeric[_random.nextInt(_alphanumeric.length)],
    ).join();
  }

  /// Generates a secure token for authentication
  static String generateSecureToken() {
    final bytes = List.generate(32, (index) => _random.nextInt(256));
    return sha256.convert(bytes).toString();
  }

  /// Validates if a room code is in the correct format
  static bool isValidRoomCode(String code) {
    if (code.length != 6) return false;
    return RegExp(r'^[A-Z0-9]{6}$').hasMatch(code);
  }

  /// Validates if a string is a valid UUID
  static bool isValidUuid(String id) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(id);
  }

  /// Generates a hash from a string
  static String generateHash(String input) {
    return sha256.convert(input.codeUnits).toString();
  }

  /// Generates a short hash (8 characters) from a string
  static String generateShortHash(String input) {
    final hash = sha256.convert(input.codeUnits).toString();
    return hash.substring(0, 8);
  }

  /// Generates a unique viewer ID based on device information
  static String generateViewerId(String deviceInfo) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final input = '$deviceInfo-$timestamp';
    return generateShortHash(input);
  }

  /// Generates a connection ID for WebRTC peer connections
  static String generateConnectionId(String roomCode, String peerId) {
    final input = '$roomCode-$peerId-${DateTime.now().millisecondsSinceEpoch}';
    return generateShortHash(input);
  }

  /// Generates a random port number within a range
  static int generateRandomPort({int min = 3000, int max = 8000}) {
    return min + _random.nextInt(max - min + 1);
  }

  /// Generates a list of potential ports for the web server
  static List<int> generatePortList({
    int count = 10,
    int min = 3000,
    int max = 8000,
  }) {
    final ports = <int>[];
    for (int i = 0; i < count; i++) {
      int port;
      do {
        port = generateRandomPort(min: min, max: max);
      } while (ports.contains(port));
      ports.add(port);
    }
    return ports;
  }

  /// Generates a unique filename for screen capture
  static String generateScreenCaptureFilename() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomString = generateRandomString(6);
    return 'screen_capture_${timestamp}_$randomString';
  }

  /// Generates a unique log file name
  static String generateLogFilename() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'mirror_mesh_${dateStr}_$timeStr.log';
  }

  /// Generates a display name for a device
  static String generateDisplayName(String? deviceName) {
    if (deviceName != null && deviceName.isNotEmpty) {
      return deviceName;
    }
    final adjectives = [
      'Red',
      'Blue',
      'Green',
      'Yellow',
      'Purple',
      'Orange',
      'Pink',
      'Gray',
      'Black',
      'White',
    ];
    final nouns = [
      'Device',
      'Computer',
      'Phone',
      'Tablet',
      'Laptop',
      'Desktop',
      'Mobile',
      'Client',
      'Viewer',
      'Screen',
    ];

    final adjective = adjectives[_random.nextInt(adjectives.length)];
    final noun = nouns[_random.nextInt(nouns.length)];
    final number = _random.nextInt(999) + 1;

    return '$adjective $noun $number';
  }
}
