import 'package:flutter/services.dart';

/// Picture-in-Picture service.
/// When user gets a call and presses home, the call shrinks
/// to a floating window exactly like WhatsApp video calls.
class PiPService {
  PiPService._();

  static const _channel = MethodChannel('com.tlyfe.chatxap/pip');

  static bool _isPiPMode = false;
  static bool get isInPiPMode => _isPiPMode;

  /// Enter PiP mode — call this when a voice/video call is active
  /// and user presses the home button or back button.
  static Future<void> enterPiP({int width = 9, int height = 16}) async {
    try {
      await _channel.invokeMethod('enterPiP', {
        'width':  width,
        'height': height,
      });
      _isPiPMode = true;
    } on PlatformException {
      // PiP not supported on this device — silent fail
    }
  }

  static Future<void> exitPiP() async {
    try {
      await _channel.invokeMethod('exitPiP');
      _isPiPMode = false;
    } on PlatformException {
      _isPiPMode = false;
    }
  }

  /// Check if PiP is supported on this device
  static Future<bool> isPiPSupported() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isPiPSupported') ?? false;
      return result;
    } on PlatformException {
      return false;
    }
  }
}
