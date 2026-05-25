import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'app_settings.dart';

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

  void _haptic() {
    if (AppSettings.hapticFeedback) HapticFeedback.selectionClick();
  }

  // ── Biometric toggle — shows PIN setup dialog ──────────────────
  Future<void> _toggleBiometric(bool v) async {
    if (v) {
      // ENABLE: show setup dialog (biometric + PIN)
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _BiometricSetupDialog(),
      );
      if (ok == true) {
        await AppSettings.setBiometricLock(true);
        setState(() {});
        _haptic();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔒 Biometric lock enabled'),
              backgroundColor: Color(0xFF4DA3FF),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      // DISABLE: require PIN to turn off
      if (AppSettings.pinHash.isEmpty) {
        await AppSettings.setBiometricLock(false);
        await AppSettings.setAutoLock(false);
        setState(() {});
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const _PinConfirmDialog(
          title: 'Disable Biometric Lock',
          subtitle: 'Enter your 4-digit PIN to disable',
        ),
      );
      if (ok == true) {
        await AppSettings.setBiometricLock(false);
        await AppSettings.setAutoLock(false);
        setState(() {});
        _haptic();
      }
    }
  }

  // ── Screenshot toggle — immediately applies FLAG_SECURE ────────
  static const _pipChannel = MethodChannel('com.tlyfe.chatxap/pip');

  Future<void> _toggleScreenshot(bool v) async {
    await AppSettings.setScreenshotBlock(v);
    // Apply FLAG_SECURE immediately
    try {
      await _pipChannel.invokeMethod('setSecureFlag', {'secure': v});
    } catch (_) {}
    setState(() {});
    _haptic();
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
        title: const Text('App Settings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
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
            subtitle: AppSettings.biometricLock
                ? 'App locks when you leave. Tap to disable.'
                : 'Require fingerprint + PIN to open ChatXAP',
            value: AppSettings.biometricLock,
            enabled: _canBiometric,
            onChanged: _toggleBiometric,
            disabledHint: 'No biometric enrolled on this device',
          ),

          // Info box when biometric is off
          if (!AppSettings.biometricLock) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF4DA3FF).withOpacity(0.06),
                border: Border.all(
                    color: const Color(0xFF4DA3FF).withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Color(0xFF4DA3FF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'When enabled, ChatXAP will lock after you leave the app. '
                      'You\'ll set a 4-digit PIN as backup. '
                      'Unlock with fingerprint or PIN anytime.',
                      style: TextStyle(
                          color: const Color(0xFF9CA3AF).withOpacity(0.9),
                          fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (AppSettings.biometricLock) ...[
            const SizedBox(height: 8),
            _settingTile(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF7C5CFC),
              title: 'Auto-Lock',
              subtitle:
                  'Lock after ${AppSettings.autoLockMins} min in background',
              value: AppSettings.autoLock,
              onChanged: (v) async {
                await AppSettings.setAutoLock(v);
                setState(() {});
                _haptic();
              },
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
            subtitle: AppSettings.screenshotBlock
                ? 'Screenshots are blocked inside ChatXAP'
                : 'Prevent screenshots inside ChatXAP (like Signal)',
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
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(title,
        style: const TextStyle(
            color: Color(0xFF4DA3FF), fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
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
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withOpacity(0.12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          enabled ? subtitle : (disabledHint ?? subtitle),
          style: TextStyle(
              color: enabled ? const Color(0xFF9CA3AF) : Colors.white24,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lock after',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
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
                        color: selected ? Colors.white : Colors.white60,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700 : FontWeight.w500),
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
    final options = {
      'auto': 'Auto',
      'high': 'High',
      'low': 'Data Saver',
    };
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
              width: 40, height: 40,
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
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Controls image/video quality sent',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
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
                    margin: EdgeInsets.only(
                        right: e.key != 'low' ? 8 : 0),
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
                    child: Column(children: [
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
                    ]),
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

// ── Biometric + PIN setup dialog ────────────────────────────────
class _BiometricSetupDialog extends StatefulWidget {
  const _BiometricSetupDialog();

  @override
  State<_BiometricSetupDialog> createState() => _BiometricSetupDialogState();
}

class _BiometricSetupDialogState extends State<_BiometricSetupDialog> {
  final List<String> _pin = [];
  final List<String> _confirm = [];
  bool _settingPin = true; // true = entering first PIN, false = confirming
  bool _error = false;
  final _auth = LocalAuthentication();

  void _onDigit(String d) {
    final current = _settingPin ? _pin : _confirm;
    if (current.length >= 4) return;
    setState(() { current.add(d); _error = false; });
    HapticFeedback.selectionClick();

    if (current.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _next);
    }
  }

  void _onDelete() {
    final current = _settingPin ? _pin : _confirm;
    if (current.isEmpty) return;
    setState(() => current.removeLast());
    HapticFeedback.lightImpact();
  }

  Future<void> _next() async {
    if (_settingPin) {
      setState(() { _settingPin = false; });
    } else {
      // Confirm PIN
      if (_pin.join() == _confirm.join()) {
        // Save PIN hash
        await AppSettings.setPinHash(
            AppSettings.hashPin(_pin.join()));
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.pop(context, true);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = true;
          _confirm.clear();
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _error = false);
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _settingPin ? _pin : _confirm;
    return Dialog(
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded,
                color: Color(0xFF4DA3FF), size: 40),
            const SizedBox(height: 16),
            Text(
              _settingPin ? 'Set Your PIN' : 'Confirm PIN',
              style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _settingPin
                  ? 'Create a 4-digit backup PIN.\nUsed if fingerprint fails.'
                  : 'Re-enter your PIN to confirm.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < current.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _error
                        ? const Color(0xFFFF4B4B)
                        : filled
                            ? const Color(0xFF4DA3FF)
                            : Colors.transparent,
                    border: Border.all(
                      color: _error
                          ? const Color(0xFFFF4B4B)
                          : const Color(0xFF4DA3FF).withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('PINs do not match. Try again.',
                  style: TextStyle(
                      color: Color(0xFFFF4B4B), fontSize: 12)),
            ],
            const SizedBox(height: 24),
            // Numpad
            for (final row in [
              ['1','2','3'],
              ['4','5','6'],
              ['7','8','9'],
              ['','0','⌫'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((k) => _PinDialogKey(
                  label: k,
                  onTap: k.isEmpty ? null : k == '⌫'
                      ? _onDelete : () => _onDigit(k),
                )).toList(),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PIN confirm dialog (for disabling) ──────────────────────────
class _PinConfirmDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  const _PinConfirmDialog({required this.title, required this.subtitle});

  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog> {
  final List<String> _pin = [];
  bool _error = false;

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() { _pin.add(d); _error = false; });
    HapticFeedback.selectionClick();
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _verify);
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
  }

  void _verify() {
    if (AppSettings.verifyPin(_pin.join())) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() { _pin.clear(); _error = true; });
      Future.delayed(const Duration(milliseconds: 800),
          () { if (mounted) setState(() => _error = false); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_rounded,
                color: Color(0xFFFF4B4B), size: 36),
            const SizedBox(height: 16),
            Text(widget.title,
                style: const TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _error
                        ? const Color(0xFFFF4B4B)
                        : filled
                            ? const Color(0xFFFF4B4B)
                            : Colors.transparent,
                    border: Border.all(
                      color: _error
                          ? const Color(0xFFFF4B4B)
                          : const Color(0xFFFF4B4B).withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('Wrong PIN',
                  style: TextStyle(
                      color: Color(0xFFFF4B4B), fontSize: 12)),
            ],
            const SizedBox(height: 24),
            for (final row in [
              ['1','2','3'],
              ['4','5','6'],
              ['7','8','9'],
              ['','0','⌫'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row.map((k) => _PinDialogKey(
                  label: k,
                  onTap: k.isEmpty ? null : k == '⌫'
                      ? _onDelete : () => _onDigit(k),
                )).toList(),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDialogKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PinDialogKey({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox(width: 64, height: 52);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64, height: 52,
        alignment: Alignment.center,
        child: Text(label,
          style: TextStyle(
            color: label == '⌫' ? const Color(0xFF9CA3AF) : Colors.white,
            fontSize: label == '⌫' ? 18 : 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
