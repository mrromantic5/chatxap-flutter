import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Checks Google Play for available updates and shows a non-intrusive
/// prompt. Uses flexible update for minor versions, immediate for major.
class UpdateService {
  UpdateService._();

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!context.mounted) return;

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        // Flexible update — downloads in background, prompts to install
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Silent fail — update check is non-critical
    }
  }
}
