import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_settings.dart';
import 'biometric_service.dart';

class NativeSettingsPage extends StatefulWidget {
  const NativeSettingsPage({super.key});

  @override
  State<NativeSettingsPage> createState() => _NativeSettingsPageState();
}

class _NativeSettingsPageState extends State<NativeSettingsPage> {
  BiometricCapability? _capability;

  @override
  void initState() {
    super.initState();
    _loadCapability();
  }

  Future<void> _loadCapability() async {
    final cap = await BiometricService.getCapability();
    if (mounted) setState(() => _capability = cap);
  }

  void _haptic() {
    if (AppSettings.hapticFeedback) HapticFeedback.selectionClick();
  }

  // ── Biometric toggle ─────────────────────────────────────────────────────

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      // Open the multi-step setup flow.
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BiometricSetupFlow(capability: _capability),
      );
      if (ok == true && mounted) {
        await AppSettings.setBiometricLock(true);
        // Persist the detected biometric type for icon display.
        final type = (_capability?.hasFace ?? false) ? 'face' : 'fingerprint';
        await AppSettings.setBiometricType(type);
        setState(() {});
        _haptic();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                Icon(
                  type == 'face'
                      ? Icons.face_retouching_natural_rounded
                      : Icons.fingerprint,
                  color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('${type == 'face' ? 'Face ID' : 'Fingerprint'} lock enabled'),
              ]),
              backgroundColor: const Color(0xFF4DA3FF),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } else {
      // Require PIN to disable.
      if (AppSettings.pinHash.isEmpty) {
        await AppSettings.setBiometricLock(false);
        await AppSettings.setAutoLock(false);
        await AppSettings.clearPin();
        setState(() {});
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const _PinConfirmDialog(
          title: 'Disable Lock',
          subtitle: 'Enter your PIN to disable biometric lock',
        ),
      );
      if (ok == true && mounted) {
        await AppSettings.setBiometricLock(false);
        await AppSettings.setAutoLock(false);
        await AppSettings.clearPin();
        setState(() {});
        _haptic();
      }
    }
  }

  // ── Change PIN ────────────────────────────────────────────────────────────

  Future<void> _changePin() async {
    // First verify the existing PIN.
    final verified = await showDialog<bool>(
      context: context,
      builder: (_) => const _PinConfirmDialog(
        title: 'Verify Current PIN',
        subtitle: 'Enter your current PIN to continue',
      ),
    );
    if (verified != true || !mounted) return;

    // Then set a new one.
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PinSetupDialog(),
    );
    if (ok == true && mounted) {
      setState(() {});
      _haptic();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN updated successfully'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Screenshot toggle ─────────────────────────────────────────────────────

  static const _pipChannel = MethodChannel('com.tlyfe.chatxap/pip');

  Future<void> _toggleScreenshot(bool v) async {
    await AppSettings.setScreenshotBlock(v);
    try {
      await _pipChannel.invokeMethod('setSecureFlag', {'secure': v});
    } catch (_) {}
    setState(() {});
    _haptic();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cap = _capability;
    final isLoading = cap == null;
    final canBio = !isLoading && cap.isAvailable;
    final bioTypeName = AppSettings.biometricType == 'face'
        ? 'Face ID'
        : 'Fingerprint';
    final bioIcon = AppSettings.biometricType == 'face'
        ? Icons.face_retouching_natural_rounded
        : Icons.fingerprint;

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

          // ── SECURITY & PRIVACY ─────────────────────────────────────────
          _sectionHeader('🔒 Security & Privacy'),
          const SizedBox(height: 12),

          // Main biometric toggle
          _settingTile(
            icon: bioIcon,
            iconColor: const Color(0xFF4DA3FF),
            title: '$bioTypeName Lock',
            subtitle: AppSettings.biometricLock
                ? 'Locks when you leave. Tap to disable.'
                : 'Require $bioTypeName + PIN to open ChatXAP',
            value: AppSettings.biometricLock,
            enabled: isLoading ? false : canBio,
            onChanged: _toggleBiometric,
            disabledHint: isLoading
                ? 'Checking biometric hardware…'
                : 'No biometric enrolled on this device',
          ),

          // Info box when lock is OFF
          if (!AppSettings.biometricLock) ...[
            const SizedBox(height: 8),
            _infoBox(
              icon: Icons.info_outline_rounded,
              text: 'When enabled, ChatXAP locks when you leave.\n'
                  'You\'ll set a 4-digit PIN as backup.\n'
                  'Unlock with ${canBio ? bioTypeName : 'PIN'} anytime.',
            ),
          ],

          // Sub-options when lock is ON
          if (AppSettings.biometricLock) ...[
            const SizedBox(height: 8),
            _settingTile(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF7C5CFC),
              title: 'Auto-Lock',
              subtitle: 'Lock after ${AppSettings.autoLockMins} min in background',
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
            const SizedBox(height: 8),
            // Change PIN row
            _actionTile(
              icon: Icons.pin_rounded,
              iconColor: const Color(0xFF22C55E),
              title: 'Change PIN',
              subtitle: 'Update your 4-digit backup PIN',
              onTap: _changePin,
            ),
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

          // ── NOTIFICATIONS ──────────────────────────────────────────────
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

          // ── PERFORMANCE ────────────────────────────────────────────────
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

  // ── Shared tile builders ─────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(title,
        style: const TextStyle(
            color: Color(0xFF4DA3FF), fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  );

  Widget _infoBox({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF4DA3FF).withOpacity(0.06),
        border: Border.all(color: const Color(0xFF4DA3FF).withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4DA3FF), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: const Color(0xFF9CA3AF).withOpacity(0.9),
                    fontSize: 12, height: 1.6)),
          ),
        ],
      ),
    );
  }

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0F1626),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
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
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(subtitle,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF4DA3FF), size: 20),
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
    const options = {'auto': 'Auto', 'high': 'High', 'low': 'Data Saver'};
    const icons  = {
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Media Quality',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  SizedBox(height: 2),
                  Text('Controls image/video quality sent',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                    margin: EdgeInsets.only(right: e.key != 'low' ? 8 : 0),
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

// ─────────────────────────────────────────────────────────────────────────────
/// Multi-step biometric setup flow:
///   Step 0 — Set PIN
///   Step 1 — Confirm PIN
///   Step 2 — Test biometric (optional, auto-triggered)
///   Step 3 — Success
// ─────────────────────────────────────────────────────────────────────────────
class _BiometricSetupFlow extends StatefulWidget {
  final BiometricCapability? capability;
  const _BiometricSetupFlow({this.capability});

  @override
  State<_BiometricSetupFlow> createState() => _BiometricSetupFlowState();
}

class _BiometricSetupFlowState extends State<_BiometricSetupFlow>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0=set, 1=confirm, 2=test, 3=success
  final List<String> _pin     = [];
  final List<String> _confirm = [];
  bool _pinError    = false;
  bool _testPassed  = false;
  bool _testRunning = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double>   _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0),   weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() { _shakeCtrl.dispose(); super.dispose(); }

  // ── PIN entry ──────────────────────────────────────────────────────────
  void _onDigit(String d) {
    final current = _step == 0 ? _pin : _confirm;
    if (current.length >= 4) return;
    setState(() { current.add(d); _pinError = false; });
    HapticFeedback.selectionClick();
    if (current.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _advance);
    }
  }

  void _onDelete() {
    final current = _step == 0 ? _pin : _confirm;
    if (current.isEmpty) return;
    setState(() => current.removeLast());
    HapticFeedback.lightImpact();
  }

  Future<void> _advance() async {
    if (_step == 0) {
      // Move to confirm step.
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Validate confirmation.
      if (_pin.join() == _confirm.join()) {
        await AppSettings.setPinHash(_pin.join());
        HapticFeedback.mediumImpact();
        // If biometric is available, show test step; otherwise jump to success.
        if (widget.capability?.isAvailable ?? false) {
          setState(() => _step = 2);
          _runBiometricTest();
        } else {
          setState(() => _step = 3);
        }
      } else {
        HapticFeedback.heavyImpact();
        setState(() { _pinError = true; _confirm.clear(); });
        _shakeCtrl.forward(from: 0);
        Future.delayed(const Duration(milliseconds: 900),
            () { if (mounted) setState(() => _pinError = false); });
      }
    }
  }

  Future<void> _runBiometricTest() async {
    if (!mounted) return;
    setState(() => _testRunning = true);
    await Future.delayed(const Duration(milliseconds: 500));
    final ok = await BiometricService.authenticate(
      localizedReason: 'Confirm biometric to complete setup',
    );
    if (!mounted) return;
    setState(() { _testRunning = false; _testPassed = ok; _step = 3; });
  }

  void _finish() => Navigator.pop(context, true);
  void _cancel() => Navigator.pop(context, false);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildPinStep(key: const ValueKey('set'));
      case 1: return _buildPinStep(key: const ValueKey('confirm'));
      case 2: return _buildTestStep();
      case 3: return _buildSuccessStep();
      default: return const SizedBox.shrink();
    }
  }

  // Step 0 & 1 share the same PIN pad layout; only title/subtitle change.
  Widget _buildPinStep({required Key key}) {
    final isConfirm = _step == 1;
    final current = isConfirm ? _confirm : _pin;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress indicator
        _StepDots(total: 3, current: _step),
        const SizedBox(height: 20),
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4DA3FF).withOpacity(0.12),
          ),
          child: const Icon(Icons.lock_rounded,
              color: Color(0xFF4DA3FF), size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          isConfirm ? 'Confirm PIN' : 'Set Your PIN',
          style: const TextStyle(color: Colors.white,
              fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          isConfirm
              ? 'Re-enter your PIN to confirm'
              : 'Create a 4-digit backup PIN.\nUsed if biometric fails.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        // PIN dots with shake
        AnimatedBuilder(
          animation: _shakeCtrl,
          builder: (_, __) => Transform.translate(
            offset: Offset(_shake.value, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < current.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 15, height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pinError
                        ? const Color(0xFFFF4B4B)
                        : filled
                            ? const Color(0xFF4DA3FF)
                            : Colors.transparent,
                    border: Border.all(
                      color: _pinError
                          ? const Color(0xFFFF4B4B)
                          : const Color(0xFF4DA3FF).withOpacity(0.45),
                      width: 2,
                    ),
                    boxShadow: filled && !_pinError
                        ? [BoxShadow(
                            color: const Color(0xFF4DA3FF).withOpacity(0.4),
                            blurRadius: 6)]
                        : null,
                  ),
                );
              }),
            ),
          ),
        ),
        if (_pinError) ...[
          const SizedBox(height: 8),
          const Text('PINs do not match — try again',
              style: TextStyle(color: Color(0xFFFF4B4B), fontSize: 12)),
        ] else const SizedBox(height: 8),
        const SizedBox(height: 22),
        // Numpad
        _DialogNumpad(onDigit: _onDigit, onDelete: _onDelete),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _cancel,
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildTestStep() {
    final cap = widget.capability;
    return Column(
      key: const ValueKey('test'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepDots(total: 3, current: 2),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _testRunning
              ? Container(
                  key: const ValueKey('running'),
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF4DA3FF).withOpacity(0.4),
                        width: 2),
                  ),
                  child: const CircularProgressIndicator(
                    color: Color(0xFF4DA3FF), strokeWidth: 2),
                )
              : Container(
                  key: const ValueKey('icon'),
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4DA3FF).withOpacity(0.12),
                  ),
                  child: Icon(cap?.icon ?? Icons.fingerprint,
                      color: const Color(0xFF4DA3FF), size: 32),
                ),
        ),
        const SizedBox(height: 16),
        const Text('Test Biometric',
            style: TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _testRunning
              ? 'Scanning…'
              : cap?.actionText ?? 'Touch the sensor',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccessStep() {
    final bioTypeName = (widget.capability?.hasFace ?? false)
        ? 'Face ID'
        : 'Fingerprint';
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF22C55E).withOpacity(0.12),
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF22C55E), size: 34),
        ),
        const SizedBox(height: 16),
        const Text('You\'re Protected',
            style: TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          '${_testPassed ? "$bioTypeName + " : ""}'
          'PIN lock is now active.\n'
          'ChatXAP will lock when you leave the app.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF9CA3AF), fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 8),
        // Summary badges
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (_testPassed)
              _Badge(
                icon: widget.capability?.icon ?? Icons.fingerprint,
                label: bioTypeName,
                color: const Color(0xFF4DA3FF),
              ),
            const _Badge(
              icon: Icons.pin_rounded,
              label: '4-digit PIN',
              color: Color(0xFF7C5CFC),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _finish,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4DA3FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Done',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Standalone PIN setup dialog used by "Change PIN".
// ─────────────────────────────────────────────────────────────────────────────
class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog>
    with SingleTickerProviderStateMixin {
  bool _confirm = false;
  final List<String> _pin  = [];
  final List<String> _conf = [];
  bool _error = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0),  weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() { _shakeCtrl.dispose(); super.dispose(); }

  void _onDigit(String d) {
    final cur = _confirm ? _conf : _pin;
    if (cur.length >= 4) return;
    setState(() { cur.add(d); _error = false; });
    HapticFeedback.selectionClick();
    if (cur.length == 4) Future.delayed(const Duration(milliseconds: 150), _next);
  }

  void _onDelete() {
    final cur = _confirm ? _conf : _pin;
    if (cur.isEmpty) return;
    setState(() => cur.removeLast());
    HapticFeedback.lightImpact();
  }

  Future<void> _next() async {
    if (!_confirm) {
      setState(() => _confirm = true);
    } else {
      if (_pin.join() == _conf.join()) {
        await AppSettings.setPinHash(_pin.join());
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.pop(context, true);
      } else {
        HapticFeedback.heavyImpact();
        setState(() { _error = true; _conf.clear(); });
        _shakeCtrl.forward(from: 0);
        Future.delayed(const Duration(milliseconds: 900),
            () { if (mounted) setState(() => _error = false); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _confirm ? _conf : _pin;
    return Dialog(
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pin_rounded, color: Color(0xFF22C55E), size: 40),
            const SizedBox(height: 14),
            Text(_confirm ? 'Confirm New PIN' : 'Set New PIN',
                style: const TextStyle(color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_confirm
                ? 'Re-enter your PIN to confirm.'
                : 'Choose a 4-digit PIN.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13)),
            const SizedBox(height: 22),
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (_, __) => Transform.translate(
                offset: Offset(_shake.value, 0),
                child: _PinDots(filled: cur.length, isError: _error),
              ),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('PINs do not match',
                  style: TextStyle(
                      color: Color(0xFFFF4B4B), fontSize: 12)),
            ] else const SizedBox(height: 8),
            const SizedBox(height: 22),
            _DialogNumpad(onDigit: _onDigit, onDelete: _onDelete),
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

// ─────────────────────────────────────────────────────────────────────────────
/// PIN verification dialog used when disabling lock.
// ─────────────────────────────────────────────────────────────────────────────
class _PinConfirmDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  const _PinConfirmDialog({required this.title, required this.subtitle});

  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog>
    with SingleTickerProviderStateMixin {
  final List<String> _pin = [];
  bool _error = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0),  weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() { _shakeCtrl.dispose(); super.dispose(); }

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() { _pin.add(d); _error = false; });
    HapticFeedback.selectionClick();
    if (_pin.length == 4) Future.delayed(const Duration(milliseconds: 150), _verify);
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
    HapticFeedback.lightImpact();
  }

  Future<void> _verify() async {
    final ok = await AppSettings.verifyPin(_pin.join());
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() { _pin.clear(); _error = true; });
      _shakeCtrl.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 900),
          () { if (mounted) setState(() => _error = false); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_rounded,
                color: Color(0xFFFF4B4B), size: 38),
            const SizedBox(height: 14),
            Text(widget.title,
                style: const TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 13)),
            const SizedBox(height: 22),
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (_, __) => Transform.translate(
                offset: Offset(_shake.value, 0),
                child: _PinDots(
                    filled: _pin.length,
                    isError: _error,
                    activeColor: const Color(0xFFFF4B4B)),
              ),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              const Text('Incorrect PIN',
                  style: TextStyle(color: Color(0xFFFF4B4B), fontSize: 12)),
            ] else const SizedBox(height: 8),
            const SizedBox(height: 22),
            _DialogNumpad(onDigit: _onDigit, onDelete: _onDelete),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets for dialogs
// ─────────────────────────────────────────────────────────────────────────────

/// 4 animated PIN dots.
class _PinDots extends StatelessWidget {
  final int filled;
  final bool isError;
  final Color activeColor;
  const _PinDots({
    required this.filled,
    this.isError = false,
    this.activeColor = const Color(0xFF4DA3FF),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final isFilled = i < filled;
        final color = isError ? const Color(0xFFFF4B4B) : activeColor;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 15, height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? color : Colors.transparent,
            border: Border.all(
              color: isError
                  ? const Color(0xFFFF4B4B)
                  : activeColor.withOpacity(0.45),
              width: 2,
            ),
            boxShadow: isFilled && !isError
                ? [BoxShadow(
                    color: color.withOpacity(0.4), blurRadius: 6)]
                : null,
          ),
        );
      }),
    );
  }
}

/// Compact numpad for dialogs.
class _DialogNumpad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDelete;
  const _DialogNumpad({required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows.map((row) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((k) => _DialogKey(
            label: k,
            onTap: k.isEmpty
                ? null
                : k == '⌫'
                    ? onDelete
                    : () => onDigit(k),
          )).toList(),
        ),
      )).toList(),
    );
  }
}

class _DialogKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _DialogKey({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox(width: 68, height: 50);
    final isDelete = label == '⌫';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68, height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.04),
        ),
        child: Text(label,
            style: TextStyle(
              color: isDelete ? const Color(0xFF9CA3AF) : Colors.white,
              fontSize: isDelete ? 20 : 22,
              fontWeight: FontWeight.w500,
            )),
      ),
    );
  }
}

/// Progress dots for the setup flow steps.
class _StepDots extends StatelessWidget {
  final int total;
  final int current;
  const _StepDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i <= current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active
                ? const Color(0xFF4DA3FF)
                : Colors.white.withOpacity(0.15),
          ),
        );
      }),
    );
  }
}

/// Small label badge used on the success step.
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
