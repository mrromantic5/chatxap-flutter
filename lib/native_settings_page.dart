import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'app_settings.dart';

/// Native settings page — accessible from profile page via
/// window.flutter_inappwebview.callHandler('Bridge', 'openNativeSettings')
/// All settings are immediately applied and persisted.
class NativeSettingsPage extends StatefulWidget {
  const NativeSettingsPage({super.key});

  @override
  State<NativeSettingsPage> createState() => _NativeSettingsPageState();
}

class _NativeSettingsPageState extends State<NativeSettingsPage> {
  final _auth = LocalAuthentication();
  bool _canBiometric = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    try {
      final can = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
      if (mounted) setState(() => _canBiometric = can);
    } catch (_) {}
  }

  // ── Toggle helpers ─────────────────────────────────────────────
  Future<void> _toggleBiometric(bool v) async {
    if (v && _canBiometric) {
      // Verify once before enabling
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'Confirm to enable biometric lock',
          options: const AuthenticationOptions(stickyAuth: true),
        );
        if (!ok) return;
      } catch (_) { return; }
    }
    await AppSettings.setBiometricLock(v);
    if (!v) await AppSettings.setAutoLock(false);
    if (mounted) setState(() {});
    _haptic();
  }

  Future<void> _toggleAutoLock(bool v) async {
    await AppSettings.setAutoLock(v);
    if (mounted) setState(() {});
    _haptic();
  }

  Future<void> _toggleScreenshot(bool v) async {
    await AppSettings.setScreenshotBlock(v);
    // Apply immediately
    if (v) {
      await SystemChannels.platform.invokeMethod('SystemChrome.setApplicationSwitcherDescription',
        {'label': 'ChatXAP', 'primaryColor': 0xFF0A0F1F});
    }
    if (mounted) setState(() {});
    _haptic();
  }

  void _haptic() {
    if (AppSettings.hapticFeedback) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1F),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'App Settings',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.3),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4DA3FF), Color(0xFF7C5CFC)],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [

          // ── SECURITY & PRIVACY ─────────────────────────────────
          _sectionHeader('🔒 Security & Privacy'),
          const SizedBox(height: 12),

          _settingTile(
            icon: Icons.fingerprint,
            iconColor: const Color(0xFF4DA3FF),
            title: 'Biometric Lock',
            subtitle: 'Require fingerprint or face to open ChatXAP',
            value: AppSettings.biometricLock,
            enabled: _canBiometric,
            onChanged: _toggleBiometric,
            disabledHint: 'No biometric enrolled on this device',
          ),

          if (AppSettings.biometricLock) ...[
            const SizedBox(height: 8),
            _settingTile(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF7C5CFC),
              title: 'Auto-Lock',
              subtitle: 'Lock automatically after ${AppSettings.autoLockMins} min in background',
              value: AppSettings.autoLock,
              onChanged: _toggleAutoLock,
            ),
            if (AppSettings.autoLock) ...[
              const SizedBox(height: 8),
              _autoLockDurationTile(),
            ],
          ],

          const SizedBox(height: 8),

          _settingTile(
            icon: Icons.screenshot_monitor_rounded,
            iconColor: const Color(0xFFFF4B4B),
            title: 'Block Screenshots',
            subtitle: 'Prevent screenshots inside ChatXAP (like Signal)',
            value: AppSettings.screenshotBlock,
            onChanged: _toggleScreenshot,
          ),

          const SizedBox(height: 24),

          // ── NOTIFICATIONS ──────────────────────────────────────
          _sectionHeader('🔔 Notifications'),
          const SizedBox(height: 12),

          _settingTile(
            icon: Icons.message_rounded,
            iconColor: const Color(0xFF22C55E),
            title: 'Message Preview',
            subtitle: 'Show message content in notifications',
            value: AppSettings.messagePreview,
            onChanged: (v) async {
              await AppSettings.setMessagePreview(v);
              setState(() {});
              _haptic();
            },
          ),

          const SizedBox(height: 8),

          _settingTile(
            icon: Icons.notifications_off_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'Smart Suppress',
            subtitle: 'Hide notification if that chat is currently open',
            value: AppSettings.notifSuppress,
            onChanged: (v) async {
              await AppSettings.setNotifSuppress(v);
              setState(() {});
              _haptic();
            },
          ),

          const SizedBox(height: 24),

          // ── PERFORMANCE ────────────────────────────────────────
          _sectionHeader('⚡ Performance'),
          const SizedBox(height: 12),

          _settingTile(
            icon: Icons.vibration_rounded,
            iconColor: const Color(0xFF4DA3FF),
            title: 'Haptic Feedback',
            subtitle: 'Subtle vibration on actions and notifications',
            value: AppSettings.hapticFeedback,
            onChanged: (v) async {
              await AppSettings.setHapticFeedback(v);
              setState(() {});
              HapticFeedback.mediumImpact();
            },
          ),

          const SizedBox(height: 8),

          _mediaQualityTile(),

          const SizedBox(height: 32),

          // ── Version info ───────────────────────────────────────
          Center(
            child: Text(
              'ChatXAP Native v1.0 · Phase 1',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 12),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(title,
        style: const TextStyle(
            color: Color(0xFF4DA3FF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8)),
  );

  Widget _settingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    bool enabled = true,
    String? disabledHint,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1626),
        border: Border.all(
            color: value && enabled
                ? iconColor.withOpacity(0.3)
                : Colors.white.withOpacity(0.06),
            width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withOpacity(0.12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        subtitle: Text(
          enabled ? subtitle : (disabledHint ?? subtitle),
          style: TextStyle(
              color: enabled
                  ? const Color(0xFF9CA3AF)
                  : Colors.white24,
              fontSize: 12),
        ),
        trailing: Switch.adaptive(
          value: value && enabled,
          onChanged: enabled ? (v) => onChanged(v) : null,
          activeColor: iconColor,
          inactiveThumbColor: Colors.white38,
          inactiveTrackColor: Colors.white12,
        ),
      ),
    );
  }

  Widget _autoLockDurationTile() {
    final options = [1, 2, 5, 10, 15, 30];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1626),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lock after',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((mins) {
              final selected = AppSettings.autoLockMins == mins;
              return GestureDetector(
                onTap: () async {
                  await AppSettings.setAutoLockMins(mins);
                  setState(() {});
                  _haptic();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: selected
                        ? const Color(0xFF7C5CFC)
                        : Colors.white.withOpacity(0.07),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF7C5CFC)
                          : Colors.white12,
                    ),
                  ),
                  child: Text(
                    mins == 1 ? '1 min' : '$mins mins',
                    style: TextStyle(
                        color:
                            selected ? Colors.white : Colors.white60,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _mediaQualityTile() {
    final options = {'auto': 'Auto', 'high': 'High', 'low': 'Data Saver'};
    final icons = {
      'auto': Icons.auto_awesome_rounded,
      'high': Icons.hd_rounded,
      'low': Icons.data_saver_on_rounded,
    };
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1626),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22C55E).withOpacity(0.12),
              ),
              child: const Icon(Icons.high_quality_rounded,
                  color: Color(0xFF22C55E), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Media Quality',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('Controls image/video quality sent',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            children: options.entries.map((e) {
              final selected = AppSettings.mediaQuality == e.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await AppSettings.setMediaQuality(e.key);
                    setState(() {});
                    _haptic();
                  },
                  child: Container(
                    margin:
                        EdgeInsets.only(right: e.key != 'low' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected
                          ? const Color(0xFF22C55E).withOpacity(0.15)
                          : Colors.white.withOpacity(0.05),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF22C55E)
                            : Colors.white12,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icons[e.key]!,
                            color: selected
                                ? const Color(0xFF22C55E)
                                : Colors.white38,
                            size: 18),
                        const SizedBox(height: 4),
                        Text(e.value,
                            style: TextStyle(
                                color: selected
                                    ? const Color(0xFF22C55E)
                                    : Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
