import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

/// Manages the unread count badge on the app icon.
/// Updated whenever a notification arrives and cleared when app is opened.
class BadgeService {
  BadgeService._();

  static const _kBadgeCount = 'cx_badge_count';
  static int _count = 0;

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _count = p.getInt(_kBadgeCount) ?? 0;
  }

  static Future<void> increment() async {
    _count++;
    await _save();
    await _apply();
  }

  static Future<void> clear() async {
    _count = 0;
    await _save();
    try { await FlutterAppBadger.removeBadge(); } catch (_) {}
  }

  static Future<void> _save() async {
    (await SharedPreferences.getInstance()).setInt(_kBadgeCount, _count);
  }

  static Future<void> _apply() async {
    try {
      if (_count > 0) {
        await FlutterAppBadger.updateBadgeCount(_count);
      } else {
        await FlutterAppBadger.removeBadge();
      }
    } catch (_) {}
  }

  static int get count => _count;
}
