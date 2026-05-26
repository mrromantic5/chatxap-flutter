import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_settings.dart';
import 'biometric_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// In-process brute-force tracker.
// Resets when the app is killed — intentional. A determined attacker who can
// restart the app has physical device access; the OS biometric lockout handles
// that case.
// ─────────────────────────────────────────────────────────────────────────────
class _BruteForce {
  static int _failures = 0;
  static DateTime? _lockedUntil;

  static bool get isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  static Duration get remaining =>
      isLocked ? _lockedUntil!.difference(DateTime.now()) : Duration.zero;

  static void recordFailure() {
    _failures++;
    if (_failures >= 10) {
      _lockedUntil = DateTime.now().add(const Duration(minutes: 10));
    } else if (_failures >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  static void reset() {
    _failures = 0;
    _lockedUntil = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Full-screen lock overlay shown when the app resumes from background.
/// Dismissed only after biometric auth or correct PIN.
// ─────────────────────────────────────────────────────────────────────────────
class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const BiometricLockScreen({super.key, required this.onUnlocked});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  bool _showPin       = false;
  bool _authenticating = false;
  bool _biometricFailed = false;
  final List<String> _pin = [];

  // ── Biometric capability (loaded once) ───────────────────────────────
  BiometricCapability? _capability;

  // ── Animation controllers ─────────────────────────────────────────────
  late final AnimationController _pulseCtrl;   // biometric icon glow
  late final AnimationController _shakeCtrl;   // PIN dots shake on wrong
  late final AnimationController _successCtrl; // PIN dots success flash
  late final AnimationController _fadeInCtrl;  // initial fade-in

  late final Animation<double> _pulse;
  late final Animation<double> _shake;
  late final Animation<double> _successScale;
  late final Animation<Color?> _successColor;
  late final Animation<double> _fadeIn;

  // ── Brute-force countdown timer ───────────────────────────────────────
  Timer? _countdownTimer;
  Duration _lockRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadCapabilityAndAuth();
    _startCountdownIfNeeded();
  }

  void _setupAnimations() {
    // Biometric icon pulse (continuous)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // PIN dots shake (single shot)
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -8.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0),    weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    // PIN dots success (single shot)
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _successScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _successCtrl, curve: Curves.easeOut),
    );
    _successColor = ColorTween(
      begin: const Color(0xFF4DA3FF),
      end: const Color(0xFF22C55E),
    ).animate(_successCtrl);

    // Screen fade-in
    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _fadeInCtrl, curve: Curves.easeOut);
  }

  Future<void> _loadCapabilityAndAuth() async {
    final cap = await BiometricService.getCapability();
    if (!mounted) return;
    setState(() => _capability = cap);

    // If device has no biometric hardware, show PIN immediately.
    if (!cap.isAvailable) {
      setState(() => _showPin = true);
      return;
    }

    // Auto-trigger biometric after short delay.
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted && !_showPin) _triggerBiometric();
  }

  Future<void> _triggerBiometric() async {
    if (_authenticating || _showPin || !mounted) return;
    setState(() { _authenticating = true; _biometricFailed = false; });

    final ok = await BiometricService.authenticate(
      localizedReason: 'Unlock ChatXAP',
    );

    if (!mounted) return;

    if (ok) {
      _handleSuccess();
    } else {
      setState(() { _authenticating = false; _biometricFailed = true; });
      // Auto-clear the failed indicator after 2 s.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _biometricFailed = false);
      });
    }
  }

  // ── PIN entry ────────────────────────────────────────────────────────

  void _onPinDigit(String d) {
    if (_BruteForce.isLocked || _pin.length >= 4) return;
    setState(() => _pin.add(d));
    if (AppSettings.hapticFeedback) HapticFeedback.selectionClick();
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 100), _verifyPin);
    }
  }

  void _onPinDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin.removeLast());
    if (AppSettings.hapticFeedback) HapticFeedback.lightImpact();
  }

  Future<void> _verifyPin() async {
    final entered = _pin.join();
    final ok = await AppSettings.verifyPin(entered);

    if (!mounted) return;

    if (ok) {
      _BruteForce.reset();
      if (AppSettings.hapticFeedback) HapticFeedback.mediumImpact();
      // Play success animation then dismiss.
      await _successCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 180));
      if (mounted) _handleSuccess();
    } else {
      _BruteForce.recordFailure();
      if (AppSettings.hapticFeedback) HapticFeedback.heavyImpact();
      setState(() => _pin.clear());
      _shakeCtrl.forward(from: 0);
      _startCountdownIfNeeded();
    }
  }

  void _handleSuccess() async {
    await AppSettings.setLastLocked(0);
    if (mounted) widget.onUnlocked();
  }

  // ── Brute-force countdown ────────────────────────────────────────────

  void _startCountdownIfNeeded() {
    if (!_BruteForce.isLocked) return;
    _countdownTimer?.cancel();
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _countdownTimer?.cancel(); return; }
      _updateCountdown();
      if (!_BruteForce.isLocked) _countdownTimer?.cancel();
    });
  }

  void _updateCountdown() {
    if (mounted) setState(() => _lockRemaining = _BruteForce.remaining);
  }

  // ── Mode toggle ──────────────────────────────────────────────────────

  void _switchToPin() {
    BiometricService.cancel();
    setState(() {
      _showPin          = true;
      _authenticating   = false;
      _biometricFailed  = false;
      _pin.clear();
    });
  }

  void _switchToBiometric() {
    setState(() {
      _showPin = false;
      _pin.clear();
    });
    Future.delayed(const Duration(milliseconds: 200), _triggerBiometric);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    _fadeInCtrl.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Scaffold(
        backgroundColor: const Color(0xFF080D1A),
        body: Stack(
          children: [
            // Subtle radial glow background
            Positioned.fill(
              child: CustomPaint(painter: _BackgroundGlowPainter()),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _buildHeader(),
                  const Spacer(flex: 3),
                  if (!_showPin) _buildBiometricSection()
                  else           _buildPinSection(),
                  const Spacer(flex: 3),
                  _buildBottomBadge(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header (logo + app name) ─────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        // App icon with blue glow
        Container(
          width: 82, height: 82,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4DA3FF).withOpacity(0.35),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset('assets/icon.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'ChatXAP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _showPin ? 'Enter your PIN' : 'Verify to continue',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  // ── Biometric section ─────────────────────────────────────────────────

  Widget _buildBiometricSection() {
    final cap = _capability;
    final icon  = cap?.icon  ?? Icons.fingerprint;
    final label = cap?.actionText ?? 'Touch the sensor to unlock';

    final btnColor = _biometricFailed
        ? const Color(0xFFFF4B4B)
        : const Color(0xFF4DA3FF);

    return Column(
      children: [
        // Pulsing biometric button
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => GestureDetector(
            onTap: _authenticating ? null : _triggerBiometric,
            child: Transform.scale(
              scale: _authenticating ? _pulse.value : 1.0,
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      btnColor.withOpacity(0.18),
                      btnColor.withOpacity(0.06),
                    ],
                  ),
                  border: Border.all(
                    color: btnColor.withOpacity(0.5),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: btnColor.withOpacity(
                          _authenticating ? 0.45 : 0.18),
                      blurRadius: _authenticating ? 32 : 14,
                      spreadRadius: _authenticating ? 6 : 0,
                    ),
                  ],
                ),
                child: Icon(icon, size: 46, color: btnColor),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Status text
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            key: ValueKey(_biometricFailed ? 'fail' : _authenticating ? 'auth' : 'idle'),
            _biometricFailed
                ? 'Authentication failed — try again'
                : _authenticating
                    ? 'Verifying…'
                    : label,
            style: TextStyle(
              color: _biometricFailed
                  ? const Color(0xFFFF4B4B)
                  : const Color(0xFF9CA3AF),
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // "Use PIN" link
        _LinkButton(
          label: cap?.fallbackText ?? 'Use PIN instead',
          onTap: _switchToPin,
        ),
      ],
    );
  }

  // ── PIN section ───────────────────────────────────────────────────────

  Widget _buildPinSection() {
    final locked = _BruteForce.isLocked;

    return Column(
      children: [
        // PIN dots with shake + success animations
        AnimatedBuilder(
          animation: Listenable.merge([_shakeCtrl, _successCtrl]),
          builder: (_, __) {
            return Transform.translate(
              offset: Offset(_shake.value, 0),
              child: Transform.scale(
                scale: _successScale.value,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < _pin.length;
                    final dotColor = _successCtrl.isAnimating
                        ? _successColor.value!
                        : const Color(0xFF4DA3FF);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? dotColor : Colors.transparent,
                        border: Border.all(
                          color: filled
                              ? dotColor
                              : const Color(0xFF4DA3FF).withOpacity(0.4),
                          width: 2,
                        ),
                        boxShadow: filled
                            ? [BoxShadow(
                                color: dotColor.withOpacity(0.45),
                                blurRadius: 8, spreadRadius: 1)]
                            : null,
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),

        // Error / lockout message
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: locked
              ? Text(
                  key: const ValueKey('locked'),
                  'Too many attempts — wait ${_lockRemaining.inSeconds}s',
                  style: const TextStyle(
                      color: Color(0xFFFF4B4B), fontSize: 12),
                )
              : const SizedBox(height: 16, key: ValueKey('spacer')),
        ),

        const SizedBox(height: 28),

        // Number pad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: _buildNumpad(locked),
        ),

        const SizedBox(height: 16),

        // Switch to biometric (only if hardware is available)
        if ((_capability?.isAvailable ?? false))
          _LinkButton(
            label: _capability?.switchToBiometricText ?? 'Use Fingerprint',
            icon: _capability?.icon ?? Icons.fingerprint,
            onTap: _switchToBiometric,
          ),
      ],
    );
  }

  Widget _buildNumpad(bool locked) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['biometric', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: row.map((k) {
              if (k == 'biometric') {
                // Bottom-left: biometric shortcut icon, or empty placeholder
                if (_capability?.isAvailable ?? false) {
                  return _NumpadBioKey(
                    icon: _capability!.icon,
                    onTap: _switchToBiometric,
                  );
                }
                return const SizedBox(width: 80, height: 64);
              }
              return _NumpadKey(
                label: k,
                onTap: locked
                    ? null
                    : k == '⌫'
                        ? _onPinDelete
                        : () => _onPinDigit(k),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  // ── Bottom badge ─────────────────────────────────────────────────────

  Widget _buildBottomBadge() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded,
            color: Colors.white.withOpacity(0.15), size: 12),
        const SizedBox(width: 5),
        Text(
          'End-to-end secured',
          style: TextStyle(
            color: Colors.white.withOpacity(0.15),
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Numeric key button on the PIN pad.
class _NumpadKey extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _NumpadKey({required this.label, this.onTap});

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _press, curve: Curves.easeIn));
  }

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDelete = widget.label == '⌫';

    return GestureDetector(
      onTapDown: (_) { if (widget.onTap != null) _press.forward(); },
      onTapUp: (_) { _press.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 80, height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: widget.onTap == null
                ? Colors.white.withOpacity(0.03)
                : Colors.white.withOpacity(0.06),
            border: Border.all(
              color: Colors.white.withOpacity(
                  widget.onTap == null ? 0.04 : 0.08),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: isDelete
                  ? const Color(0xFF9CA3AF)
                  : widget.onTap == null
                      ? Colors.white24
                      : Colors.white,
              fontSize: isDelete ? 22 : 24,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left biometric shortcut on the PIN pad.
class _NumpadBioKey extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NumpadBioKey({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80, height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF4DA3FF).withOpacity(0.08),
          border: Border.all(
            color: const Color(0xFF4DA3FF).withOpacity(0.18),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 26, color: const Color(0xFF4DA3FF)),
      ),
    );
  }
}

/// Underlined text link button used for "Use PIN" / "Use Fingerprint" etc.
class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  const _LinkButton({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: const Color(0xFF4DA3FF)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4DA3FF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFF4DA3FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background radial glow painter
// ─────────────────────────────────────────────────────────────────────────────
class _BackgroundGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.3),
        radius: 0.9,
        colors: [
          const Color(0xFF4DA3FF).withOpacity(0.07),
          const Color(0xFF080D1A).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
