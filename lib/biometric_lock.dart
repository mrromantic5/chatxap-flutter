import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'app_settings.dart';

/// Biometric / PIN lock overlay.
/// Shown when app comes to foreground after being backgrounded
/// longer than the auto-lock timer (or always if biometric is on).
class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const BiometricLockScreen({super.key, required this.onUnlocked});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  final _auth = LocalAuthentication();
  bool _isAuthenticating = false;
  bool _failed = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    // Auto-trigger auth after short delay
    Future.delayed(const Duration(milliseconds: 400), _authenticate);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() { _isAuthenticating = true; _failed = false; });

    try {
      final canAuth = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();

      if (!canAuth) {
        // No biometrics available — unlock immediately
        widget.onUnlocked();
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Unlock ChatXAP',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated && mounted) {
        HapticFeedback.mediumImpact();
        await AppSettings.setLastLocked(0); // reset timer
        widget.onUnlocked();
      } else if (mounted) {
        setState(() { _failed = true; _isAuthenticating = false; });
        HapticFeedback.heavyImpact();
      }
    } on PlatformException catch (_) {
      if (mounted) setState(() { _failed = true; _isAuthenticating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D1A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              const Color(0xFF0D1A2E),
              const Color(0xFF080D1A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              // ── App logo ───────────────────────────────────────
              Hero(
                tag: 'app_icon',
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4DA3FF).withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text('ChatXAP',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(
                AppSettings.biometricLock
                    ? 'Verify to continue'
                    : 'App locked',
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 15),
              ),

              const Spacer(),

              // ── Fingerprint button ─────────────────────────────
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Transform.scale(
                  scale: _isAuthenticating ? _pulse.value : 1.0,
                  child: GestureDetector(
                    onTap: _authenticate,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _failed
                              ? [
                                  const Color(0xFFFF4B4B).withOpacity(0.2),
                                  const Color(0xFFFF4B4B).withOpacity(0.1),
                                ]
                              : [
                                  const Color(0xFF4DA3FF).withOpacity(0.2),
                                  const Color(0xFF1A6FCC).withOpacity(0.1),
                                ],
                        ),
                        border: Border.all(
                          color: _failed
                              ? const Color(0xFFFF4B4B).withOpacity(0.5)
                              : const Color(0xFF4DA3FF).withOpacity(0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_failed
                                    ? const Color(0xFFFF4B4B)
                                    : const Color(0xFF4DA3FF))
                                .withOpacity(
                                    _isAuthenticating ? 0.35 : 0.15),
                            blurRadius: _isAuthenticating ? 24 : 12,
                            spreadRadius: _isAuthenticating ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        _failed
                            ? Icons.fingerprint
                            : _isAuthenticating
                                ? Icons.fingerprint
                                : Icons.fingerprint,
                        size: 46,
                        color: _failed
                            ? const Color(0xFFFF4B4B)
                            : const Color(0xFF4DA3FF),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                _failed
                    ? 'Authentication failed. Tap to retry.'
                    : _isAuthenticating
                        ? 'Verifying…'
                        : 'Tap to unlock',
                style: TextStyle(
                  color: _failed
                      ? const Color(0xFFFF4B4B)
                      : const Color(0xFF9CA3AF),
                  fontSize: 14,
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
