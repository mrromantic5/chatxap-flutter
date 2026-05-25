import 'package:shared_preferences/shared_preferences.dart';

/// Central settings store for all user-configurable native features.
/// Settings are saved locally and also synced with the WebView page
/// so the web app can read them via window.CHATXAP_SETTINGS.
class AppSettings {
  AppSettings._();

  // ── Keys ────────────────────────────────────────────────────────
  static const _kBiometric       = 'cx_biometric_lock';
  static const _kAutoLock        = 'cx_auto_lock';
  static const _kAutoLockMins    = 'cx_auto_lock_mins';
  static const _kScreenshot      = 'cx_screenshot_block';
  static const _kHaptic          = 'cx_haptic';
  static const _kMsgPreview      = 'cx_msg_preview';
  static const _kNotifSuppress   = 'cx_notif_suppress';
  static const _kMediaQuality    = 'cx_media_quality'; // 'auto','high','low'
  static const _kLastLocked      = 'cx_last_locked_ts';
  static const _kPinHash         = 'cx_pin_hash';

  // ── Defaults ────────────────────────────────────────────────────
  static bool   biometricLock     = false;
  static bool   autoLock          = false;
  static int    autoLockMins      = 5;    // minutes
  static bool   screenshotBlock   = false;
  static bool   hapticFeedback    = true;
  static bool   messagePreview    = true; // show msg content in notifications
  static bool   notifSuppress     = true; // hide notif if chat is open
  static String mediaQuality      = 'auto';
  static int    lastLockedTs      = 0;
  static String pinHash          = '';

  /// Load all settings from disk. Call once at app startup.
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    biometricLock   = p.getBool(_kBiometric)     ?? false;
    autoLock        = p.getBool(_kAutoLock)       ?? false;
    autoLockMins    = p.getInt(_kAutoLockMins)    ?? 5;
    screenshotBlock = p.getBool(_kScreenshot)     ?? false;
    hapticFeedback  = p.getBool(_kHaptic)         ?? true;
    messagePreview  = p.getBool(_kMsgPreview)     ?? true;
    notifSuppress   = p.getBool(_kNotifSuppress)  ?? true;
    mediaQuality    = p.getString(_kMediaQuality) ?? 'auto';
    lastLockedTs    = p.getInt(_kLastLocked)      ?? 0;
    pinHash         = p.getString(_kPinHash)       ?? '';
  }

  static Future<void> setBiometricLock(bool v) async {
    biometricLock = v;
    (await SharedPreferences.getInstance()).setBool(_kBiometric, v);
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

  static Future<void> setPinHash(String hash) async {
    pinHash = hash;
    (await SharedPreferences.getInstance()).setString(_kPinHash, hash);
  }

  static bool verifyPin(String enteredPin) {
    // Simple hash: sum of char codes (good enough for local PIN)
    final hash = enteredPin.codeUnits.fold(0, (a, b) => a + b).toString();
    return pinHash == hash && pinHash.isNotEmpty;
  }

  static String hashPin(String pin) {
    return pin.codeUnits.fold(0, (a, b) => a + b).toString();
  }

  /// Returns true if auto-lock timer has expired
  static bool isAutoLockExpired() {
    if (!autoLock) return false;
    if (lastLockedTs == 0) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastLockedTs;
    return elapsed > (autoLockMins * 60 * 1000);
  }

  /// JS object to inject into every web page so web code can read settings
  static String get jsSettingsObject => '''
window.CHATXAP_SETTINGS = {
  haptic: ${hapticFeedback ? 'true' : 'false'},
  messagePreview: ${messagePreview ? 'true' : 'false'},
  screenshotBlock: ${screenshotBlock ? 'true' : 'false'},
  mediaQuality: "${mediaQuality}",
  biometricLock: ${biometricLock ? 'true' : 'false'},
  autoLock: ${autoLock ? 'true' : 'false'},
  autoLockMins: $autoLockMins,
  isNative: true,
  platform: 'android'
};
''';
}
