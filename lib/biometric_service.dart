import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Describes what biometric hardware is available on the current device.
// ─────────────────────────────────────────────────────────────────────────────
class BiometricCapability {
  final bool isAvailable;
  final bool hasFace;
  final bool hasFingerprint;
  final List<BiometricType> types;

  const BiometricCapability({
    required this.isAvailable,
    required this.hasFace,
    required this.hasFingerprint,
    required this.types,
  });

  /// Human-readable name of the primary biometric method.
  String get displayName {
    if (hasFace) return 'Face ID';
    if (hasFingerprint) return 'Fingerprint';
    return 'Biometric';
  }

  /// Icon for the primary biometric method.
  IconData get icon {
    if (hasFace) return Icons.face_retouching_natural_rounded;
    return Icons.fingerprint;
  }

  /// Short verb used in prompts ("Scan your face" vs "Touch the sensor").
  String get actionText {
    if (hasFace) return 'Scan your face to unlock';
    return 'Touch the sensor to unlock';
  }

  /// Fallback sentence on the lock screen.
  String get fallbackText {
    if (hasFace) return 'Use PIN instead of Face ID';
    return 'Use PIN instead of Fingerprint';
  }

  /// Sentence used when switching back from PIN to biometric.
  String get switchToBiometricText {
    if (hasFace) return 'Use Face ID';
    return 'Use Fingerprint';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Lightweight service wrapper around [LocalAuthentication].
/// All methods are static — call from anywhere without instantiation.
// ─────────────────────────────────────────────────────────────────────────────
class BiometricService {
  BiometricService._();

  static final _auth = LocalAuthentication();

  // ── Capability check ────────────────────────────────────────────────────

  /// Queries what biometric hardware is enrolled and ready.
  static Future<BiometricCapability> getCapability() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();

      if (!canCheck && !isSupported) {
        return const BiometricCapability(
          isAvailable: false,
          hasFace: false,
          hasFingerprint: false,
          types: [],
        );
      }

      final types = await _auth.getAvailableBiometrics();

      // Face: explicit face type.
      // Fingerprint: explicit fingerprint type OR "strong" class (Android 11+
      // hardware-backed biometric, almost always a fingerprint sensor).
      final hasFace = types.contains(BiometricType.face);
      final hasFingerprint = types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong);

      return BiometricCapability(
        isAvailable: true,
        hasFace: hasFace,
        hasFingerprint: hasFingerprint || (!hasFace && types.isNotEmpty),
        types: types,
      );
    } catch (_) {
      return const BiometricCapability(
        isAvailable: false,
        hasFace: false,
        hasFingerprint: false,
        types: [],
      );
    }
  }

  // ── Authentication ──────────────────────────────────────────────────────

  /// Triggers the platform biometric prompt.
  ///
  /// [localizedReason] is shown in the OS dialog (iOS / Android).
  /// Returns `true` on success, `false` on failure or cancellation.
  static Future<bool> authenticate({
    String localizedReason = 'Authenticate to access ChatXAP',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // Allow PIN/pattern OS fallback — user can also use PIN in our UI.
          biometricOnly: false,
          // Keep dialog open if user switches apps mid-auth.
          stickyAuth: true,
          // Let the OS show its own error dialogs (locked out, etc.).
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Cancels an in-flight biometric prompt (e.g. when user taps "Use PIN").
  static Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
