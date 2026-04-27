import 'package:flutter/services.dart';

class JailbreakDetector {
  static const MethodChannel _channel = MethodChannel('com.padipay/jailbreak');

  /// Returns true if the device appears rooted or jailbroken.
  static Future<bool> isDeviceRootedOrJailbroken() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDeviceRootedOrJailbroken');
      if (res is bool) return res;
      return false;
    } catch (_) {
      return false;
    }
  }
}
