import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Firebase Remote Config service.
/// Controls app behaviour without requiring a new release.
/// Force-update logic: if server minimum_version > installed version → block.
class RemoteConfigService {
  RemoteConfigService._();

  static FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  static bool _initialized = false;

  // ── Remote Config keys ──────────────────────────────────────────
  static const _kMinVersion        = 'minimum_version';
  static const _kMaintenanceMode   = 'maintenance_mode';
  static const _kMaintenanceMsg    = 'maintenance_message';
  static const _kFeatureGames      = 'feature_games_enabled';
  static const _kFeatureAI         = 'feature_ai_enabled';
  static const _kBannerMsg         = 'banner_message';
  static const _kBannerEnabled     = 'banner_enabled';

  // ── Defaults ────────────────────────────────────────────────────
  static const _defaults = {
    _kMinVersion:       '1.0.0',
    _kMaintenanceMode:  false,
    _kMaintenanceMsg:   'ChatXAP is under maintenance. Please check back soon.',
    _kFeatureGames:     true,
    _kFeatureAI:        true,
    _kBannerMsg:        '',
    _kBannerEnabled:    false,
  };

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout:          const Duration(seconds: 10),
        minimumFetchInterval:  const Duration(hours: 1),
      ));
      await _rc.setDefaults(_defaults);
      await _rc.fetchAndActivate();
      _initialized = true;
    } catch (_) {
      // Non-critical — app works with defaults if fetch fails
    }
  }

  // ── Accessors ────────────────────────────────────────────────────
  static String  get minimumVersion   => _rc.getString(_kMinVersion);
  static bool    get maintenanceMode  => _rc.getBool(_kMaintenanceMode);
  static String  get maintenanceMsg   => _rc.getString(_kMaintenanceMsg);
  static bool    get gamesEnabled     => _rc.getBool(_kFeatureGames);
  static bool    get aiEnabled        => _rc.getBool(_kFeatureAI);
  static String  get bannerMessage    => _rc.getString(_kBannerMsg);
  static bool    get bannerEnabled    => _rc.getBool(_kBannerEnabled);

  /// Check if this build needs a forced update.
  /// Returns true if app should be blocked.
  static Future<bool> checkForceUpdate(BuildContext context) async {
    try {
      await initialize();
      final info    = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);
      final minimum = _parseVersion(minimumVersion);

      if (_isOlderThan(current, minimum)) {
        if (context.mounted) _showForceUpdateDialog(context);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Check maintenance mode
  static Future<bool> checkMaintenance(BuildContext context) async {
    try {
      await initialize();
      if (maintenanceMode) {
        if (context.mounted) _showMaintenanceDialog(context, maintenanceMsg);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Dialogs ─────────────────────────────────────────────────────
  static void _showForceUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1626),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Required',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'A newer version of ChatXAP is required. '
          'Please update to continue.',
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              const url =
                  'https://play.google.com/store/apps/details?id=com.tlyfe.chatxap';
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DA3FF)),
            child: const Text('Update Now',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  static void _showMaintenanceDialog(
      BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1626),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Under Maintenance',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(message,
            style: const TextStyle(color: Color(0xFF9CA3AF))),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF4DA3FF))),
          ),
        ],
      ),
    );
  }

  // ── Version parsing helpers ──────────────────────────────────────
  static List<int> _parseVersion(String v) {
    try {
      return v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    } catch (_) {
      return [0, 0, 0];
    }
  }

  static bool _isOlderThan(List<int> current, List<int> minimum) {
    for (int i = 0; i < 3; i++) {
      final c = i < current.length ? current[i] : 0;
      final m = i < minimum.length ? minimum[i] : 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }
}
