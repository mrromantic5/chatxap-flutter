import 'package:shared_preferences/shared_preferences.dart';

/// Badge count managed through the notification system directly.
/// No external package required — Android shows unread count natively
/// through notification cards (same pattern as WhatsApp/Telegram).
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
  }

  static Future<void> clear() async {
    _count = 0;
    await _save();
  }

  static Future<void> _save() async {
    (await SharedPreferences.getInstance())
        .setInt(_kBadgeCount, _count);
  }

  static int get count => _count;
}
