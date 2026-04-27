import 'package:flutter/services.dart';

class ScreenSecurity {
  static const MethodChannel _channel = MethodChannel('com.padipay/screen_secure');

  static Future<void> secureOn() async {
    try {
      await _channel.invokeMethod('secureOn');
    } catch (_) {
      // ignore on unsupported platforms
    }
  }

  static Future<void> secureOff() async {
    try {
      await _channel.invokeMethod('secureOff');
    } catch (_) {
      // ignore
    }
  }
}
