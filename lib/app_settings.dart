import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central settings store for all user-configurable native features.
/// Settings are persisted locally and synced with the WebView page
/// so the web app can read them via window.CHATXAP_SETTINGS.
///
/// PIN security:
///   • Raw PIN is NEVER stored. A random 16-byte salt + SHA-256 hash is
///     written to Android Keystore / iOS Keychain via flutter_secure_storage.
///   • The legacy sum-of-chars hash (v1) is automatically migrated on first
///     correct use.
class AppSettings {
  AppSettings._();

  // ── Shared Preferences keys ──────────────────────────────────────────────
  static const _kBiometric     = 'cx_biometric_lock';
  static const _kBiometricType = 'cx_biometric_type'; // 'face' | 'fingerprint'
  static const _kAutoLock      = 'cx_auto_lock';
  static const _kAutoLockMins  = 'cx_auto_lock_mins';
  static const _kScreenshot    = 'cx_screenshot_block';
  static const _kHaptic        = 'cx_haptic';
  static const _kMsgPreview    = 'cx_msg_preview';
  static const _kNotifSuppress = 'cx_notif_suppress';
  static const _kMediaQuality  = 'cx_media_quality';
  static const _kLastLocked    = 'cx_last_locked_ts';
  // Legacy (v1) PIN hash — kept only to allow silent migration.
  static const _kPinHashLegacy = 'cx_pin_hash';

  // ── Secure Storage keys (Android Keystore / iOS Keychain) ────────────────
  static const _kPinHashV2 = 'cx_pin_hash_v2';
  static const _kPinSalt   = 'cx_pin_salt';

  // ── Secure storage instance ──────────────────────────────────────────────
  static const _secure = FlutterSecureStorage(
    // Android: AES-256 keys stored in the Keystore.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // iOS: accessible after first device unlock (background-safe).
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── In-memory state (loaded from disk on startup) ────────────────────────
  static bool   biometricLock   = false;
  static String biometricType   = 'fingerprint'; // 'face' | 'fingerprint'
  static bool   autoLock        = false;
  static int    autoLockMins    = 5;
  static bool   screenshotBlock = false;
  static bool   hapticFeedback  = true;
  static bool   messagePreview  = true;
  static bool   notifSuppress   = true;
  static String mediaQuality    = 'auto';
  static int    lastLockedTs    = 0;

  /// Non-empty string when a PIN has been set; empty otherwise.
  /// Used by webview_screen.dart to decide whether to show the lock screen.
  static String pinHash = '';

  // ── Startup load ─────────────────────────────────────────────────────────

  /// Load all settings from disk. Must be awaited once before [runApp].
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    biometricLock   = p.getBool(_kBiometric)     ?? false;
    biometricType   = p.getString(_kBiometricType) ?? 'fingerprint';
    autoLock        = p.getBool(_kAutoLock)       ?? false;
    autoLockMins    = p.getInt(_kAutoLockMins)    ?? 5;
    screenshotBlock = p.getBool(_kScreenshot)     ?? false;
    hapticFeedback  = p.getBool(_kHaptic)         ?? true;
    messagePreview  = p.getBool(_kMsgPreview)     ?? true;
    notifSuppress   = p.getBool(_kNotifSuppress)  ?? true;
    mediaQuality    = p.getString(_kMediaQuality) ?? 'auto';
    lastLockedTs    = p.getInt(_kLastLocked)      ?? 0;

    // Load PIN hash from secure storage.
    try {
      final stored = await _secure.read(key: _kPinHashV2);
      pinHash = stored ?? '';

      // If no v2 hash exists but a legacy v1 hash is in prefs,
      // keep a sentinel so the lock screen knows a PIN was set
      // and the migration flow can run on next unlock attempt.
      if (pinHash.isEmpty) {
        final legacy = p.getString(_kPinHashLegacy) ?? '';
        if (legacy.isNotEmpty) pinHash = '_legacy_$legacy';
      }
    } catch (_) {
      // Secure storage read failure — treat as no PIN set.
      pinHash = '';
    }
  }

  // ── Setters ──────────────────────────────────────────────────────────────

  static Future<void> setBiometricLock(bool v) async {
    biometricLock = v;
    (await SharedPreferences.getInstance()).setBool(_kBiometric, v);
  }

  static Future<void> setBiometricType(String type) async {
    biometricType = type;
    (await SharedPreferences.getInstance()).setString(_kBiometricType, type);
  }

  static Future<void> setAutoLock(bool v) async {
    autoLock = v;
    (await SharedPreferences.getInstance()).setBool(_kAutoLock, v);
  }

  static Future<void> setAutoLockMins(int v) async {
    autoLockMins = v;
    (await SharedPreferences.getInstance()).setInt(_kAutoLockMins, v);
  }

  static Future<void> setScreenshotBlock(bool v) async {
    screenshotBlock = v;
    (await SharedPreferences.getInstance()).setBool(_kScreenshot, v);
  }

  static Future<void> setHapticFeedback(bool v) async {
    hapticFeedback = v;
    (await SharedPreferences.getInstance()).setBool(_kHaptic, v);
  }

  static Future<void> setMessagePreview(bool v) async {
    messagePreview = v;
    (await SharedPreferences.getInstance()).setBool(_kMsgPreview, v);
  }

  static Future<void> setNotifSuppress(bool v) async {
    notifSuppress = v;
    (await SharedPreferences.getInstance()).setBool(_kNotifSuppress, v);
  }

  static Future<void> setMediaQuality(String v) async {
    mediaQuality = v;
    (await SharedPreferences.getInstance()).setString(_kMediaQuality, v);
  }

  static Future<void> setLastLocked(int ts) async {
    lastLockedTs = ts;
    (await SharedPreferences.getInstance()).setInt(_kLastLocked, ts);
  }

  // ── PIN management ───────────────────────────────────────────────────────

  /// Persist a new PIN.  The raw [pin] string is salted and SHA-256 hashed
  /// before being written to the OS secure enclave.  The plaintext PIN is
  /// never stored.
  static Future<void> setPinHash(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _secure.write(key: _kPinSalt,   value: salt);
    await _secure.write(key: _kPinHashV2, value: hash);
    pinHash = hash; // update in-memory cache
    // Remove any legacy v1 hash from SharedPreferences.
    (await SharedPreferences.getInstance()).remove(_kPinHashLegacy);
  }

  /// Verify [enteredPin] against the stored hash.
  ///
  /// Handles two scenarios:
  ///   1. **v2 (secure)** — compares SHA-256(pin + salt) against stored hash.
  ///   2. **v1 (legacy)** — compares sum-of-char-codes; silently migrates to
  ///      v2 on success so the user is seamlessly upgraded.
  ///
  /// Returns `true` if the PIN matches.
  static Future<bool> verifyPin(String enteredPin) async {
    try {
      final storedHash = await _secure.read(key: _kPinHashV2);
      final storedSalt = await _secure.read(key: _kPinSalt);

      if (storedHash != null && storedSalt != null) {
        return _hashPin(enteredPin, storedSalt) == storedHash;
      }

      // ── Legacy v1 migration path ──────────────────────────────────────
      if (pinHash.startsWith('_legacy_')) {
        final legacyStored = pinHash.substring('_legacy_'.length);
        final legacyEntered =
            enteredPin.codeUnits.fold(0, (a, b) => a + b).toString();
        if (legacyStored == legacyEntered) {
          // Migrate silently to v2.
          await setPinHash(enteredPin);
          return true;
        }
        return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Remove the stored PIN and all associated secure storage keys.
  static Future<void> clearPin() async {
    await _secure.delete(key: _kPinHashV2);
    await _secure.delete(key: _kPinSalt);
    pinHash = '';
    (await SharedPreferences.getInstance()).remove(_kPinHashLegacy);
  }

  // ── Auto-lock ────────────────────────────────────────────────────────────

  /// Returns true if the auto-lock timer has elapsed.
  static bool isAutoLockExpired() {
    if (!autoLock) return false;
    if (lastLockedTs == 0) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastLockedTs;
    return elapsed > (autoLockMins * 60 * 1000);
  }

  // ── JS bridge ────────────────────────────────────────────────────────────

  /// JS object injected into every web page so the web app can read settings.
  static String get jsSettingsObject => '''
window.CHATXAP_SETTINGS = {
  haptic: ${hapticFeedback ? 'true' : 'false'},
  messagePreview: ${messagePreview ? 'true' : 'false'},
  screenshotBlock: ${screenshotBlock ? 'true' : 'false'},
  mediaQuality: "$mediaQuality",
  biometricLock: ${biometricLock ? 'true' : 'false'},
  autoLock: ${autoLock ? 'true' : 'false'},
  autoLockMins: $autoLockMins,
  isNative: true,
  platform: 'android'
};
''';

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Generate a cryptographically random 16-byte salt, hex-encoded.
  static String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// SHA-256 hash of [pin] + [salt], returned as lowercase hex.
  static String _hashPin(String pin, String salt) {
    final data = utf8.encode(pin + salt);
    return sha256.convert(data).toString();
  }
}
