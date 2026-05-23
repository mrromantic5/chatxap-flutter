import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'badge_service.dart';

/// Background sync using WorkManager.
/// Fetches unread count from server every 15 minutes
/// so badge is accurate even without push notifications.
const _syncTaskName = 'cx_background_sync';

// ── Top-level callback required by WorkManager ───────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _syncTaskName) {
      await _doSync();
    }
    return Future.value(true);
  });
}

Future<void> _doSync() async {
  try {
    final prefs  = await SharedPreferences.getInstance();
    final cookie = prefs.getString('session_cookie') ?? '';
    if (cookie.isEmpty) return;

    final client  = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final request = await client.getUrl(
        Uri.parse('https://c.x.t-lyfe.com.ng/backend/sync_data.php'));
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    request.headers.set('X-ChatXAP-App', '1');
    request.headers.set('Cookie', cookie);
    final response = await request.close();
    final body     = await response.transform(
        const SystemEncoding().decoder).join();
    client.close();

    // Parse unread count from response
    // sync_data.php returns: {"unread": 5}
    final match = RegExp(r'"unread"\s*:\s*(\d+)').firstMatch(body);
    if (match != null) {
      final count = int.tryParse(match.group(1) ?? '0') ?? 0;
      if (count > 0) {
        await BadgeService.clear();
        for (int i = 0; i < count; i++) {
          await BadgeService.increment();
        }
      }
    }
  } catch (_) {}
}

/// Main service class to start/stop background sync
class SyncService {
  SyncService._();

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> startPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  static Future<void> stopSync() async {
    await Workmanager().cancelByUniqueName(_syncTaskName);
  }
}
