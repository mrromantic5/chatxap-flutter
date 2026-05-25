import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'app_settings.dart';

/// Full biometric + PIN lock screen.
/// Shown when app comes to foreground if biometric lock is enabled.
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
  bool _showPinFallback = false;
  final List<String> _pinDigits = [];
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
    Future.delayed(const Duration(milliseconds: 400), _authenticate);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating || _showPinFallback) return;
    setState(() { _isAuthenticating = true; _failed = false; });

    try {
      final canBio = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();

      if (!canBio) {
        setState(() { _showPinFallback = true; _isAuthenticating = false; });
        return;
      }

      final ok = await _auth.authenticate(
        localizedReason: 'Unlock ChatXAP',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (ok && mounted) {
        HapticFeedback.mediumImpact();
        await AppSettings.setLastLocked(0);
        widget.onUnlocked();
      } else if (mounted) {
        setState(() {
          _failed = true;
          _isAuthenticating = false;
          _showPinFallback = true;
        });
      }
    } on PlatformException {
      if (mounted) {
        setState(() {
          _failed = false;
          _isAuthenticating = false;
          _showPinFallback = true;
        });
      }
    }
  }

  void _onPinDigit(String d) {
    if (_pinDigits.length >= 4) return;
    setState(() => _pinDigits.add(d));
    HapticFeedback.selectionClick();

    if (_pinDigits.length == 4) {
      Future.delayed(const Duration(milliseconds: 120), _verifyPin);
    }
  }

  void _onPinDelete() {
    if (_pinDigits.isEmpty) return;
    setState(() => _pinDigits.removeLast());
    HapticFeedback.lightImpact();
  }

  void _verifyPin() {
    final entered = _pinDigits.join();
    if (AppSettings.verifyPin(entered)) {
      HapticFeedback.mediumImpact();
      AppSettings.setLastLocked(0);
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() { _pinDigits.clear(); _failed = true; });
      Future.delayed(const Duration(seconds: 1),
          () { if (mounted) setState(() => _failed = false); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D1A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF4DA3FF).withOpacity(0.3),
                  blurRadius: 28, spreadRadius: 4)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/icon.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            const Text('ChatXAP',
                style: TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            Text(
              _showPinFallback ? 'Enter your 4-digit PIN' : 'Verify to continue',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
            const Spacer(),

            if (!_showPinFallback) ...[
              // Fingerprint button
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Transform.scale(
                  scale: _isAuthenticating ? _pulse.value : 1.0,
                  child: GestureDetector(
                    onTap: _authenticate,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _failed
                              ? [const Color(0xFFFF4B4B).withOpacity(0.2),
                                 const Color(0xFFFF4B4B).withOpacity(0.1)]
                              : [const Color(0xFF4DA3FF).withOpacity(0.2),
                                 const Color(0xFF1A6FCC).withOpacity(0.1)],
                        ),
                        border: Border.all(
                          color: _failed
                              ? const Color(0xFFFF4B4B).withOpacity(0.6)
                              : const Color(0xFF4DA3FF).withOpacity(0.6),
                          width: 2,
                        ),
                        boxShadow: [BoxShadow(
                          color: (_failed
                              ? const Color(0xFFFF4B4B)
                              : const Color(0xFF4DA3FF))
                              .withOpacity(_isAuthenticating ? 0.4 : 0.15),
                          blurRadius: _isAuthenticating ? 24 : 10,
                          spreadRadius: _isAuthenticating ? 4 : 0,
                        )],
                      ),
                      child: Icon(Icons.fingerprint, size: 44,
                        color: _failed
                            ? const Color(0xFFFF4B4B)
                            : const Color(0xFF4DA3FF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _failed ? 'Authentication failed' : _isAuthenticating
                    ? 'Verifying…' : 'Tap to unlock',
                style: TextStyle(
                  color: _failed
                      ? const Color(0xFFFF4B4B)
                      : const Color(0xFF9CA3AF),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _showPinFallback = true),
                child: const Text('Use PIN instead',
                    style: TextStyle(
                        color: Color(0xFF4DA3FF), fontSize: 13)),
              ),
            ] else ...[
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pinDigits.length;
                  final isError = _failed;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isError
                          ? const Color(0xFFFF4B4B)
                          : filled
                              ? const Color(0xFF4DA3FF)
                              : Colors.transparent,
                      border: Border.all(
                        color: isError
                            ? const Color(0xFFFF4B4B)
                            : const Color(0xFF4DA3FF).withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              if (_failed)
                const Text('Wrong PIN. Try again.',
                    style: TextStyle(
                        color: Color(0xFFFF4B4B), fontSize: 12)),
              const SizedBox(height: 28),
              // Numpad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  children: [
                    for (final row in [
                      ['1','2','3'],
                      ['4','5','6'],
                      ['7','8','9'],
                      ['','0','⌫'],
                    ])
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row.map((k) => _PinKey(
                          label: k,
                          onTap: k.isEmpty ? null : k == '⌫'
                              ? _onPinDelete
                              : () => _onPinDigit(k),
                        )).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() {
                  _showPinFallback = false;
                  _pinDigits.clear();
                  Future.delayed(
                      const Duration(milliseconds: 200), _authenticate);
                }),
                child: const Text('Use Fingerprint',
                    style: TextStyle(
                        color: Color(0xFF4DA3FF), fontSize: 13)),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PinKey({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox(width: 72, height: 60);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72, height: 60,
        alignment: Alignment.center,
        child: Text(label,
          style: TextStyle(
            color: label == '⌫'
                ? const Color(0xFF9CA3AF)
                : Colors.white,
            fontSize: label == '⌫' ? 20 : 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
