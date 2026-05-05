import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:light/light.dart';
import 'package:screen_brightness/screen_brightness.dart';

class AutoIlluminationService {
  Light? _lightSensor;
  StreamSubscription<int>? _subscription;

  bool _isBoosted = false;
  double? _originalBrightness;

  static const int darkThreshold = 15;
  static const int brightThreshold = 30;

  Future<void> startAutoIllumination() async {
    try {
      _originalBrightness = await ScreenBrightness.instance.application;

      _lightSensor = Light();
      _subscription = _lightSensor?.lightSensorStream.listen(_onLightDataReceived);
      debugPrint("SYSTEM: Auto-Illumination Sensor Online.");
    } catch(e) {
      debugPrint("SYSTEM ERROR: Light sensor not available on this device: $e");
    }
  }

  Future<void> _onLightDataReceived(int luxValue) async {
    try {
      if (luxValue < darkThreshold && !_isBoosted) {
        _isBoosted = true;

        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
        debugPrint("SYSTEM: Low light detected ($luxValue lux). Brightness maximmized.");
      }
      else if (luxValue > brightThreshold && _isBoosted) {
        _isBoosted = false;

        if (_originalBrightness != null) {
          await ScreenBrightness.instance.setApplicationScreenBrightness(_originalBrightness!);
        } else {
          await ScreenBrightness.instance.resetApplicationScreenBrightness();
        }
        debugPrint("SYSTEM: Light restored ($luxValue lux). Brightness normalized.");
      }
    } catch(e) {
      debugPrint("SYSTEM ERROR: Failed to adjust brightness: $e");
    }
  }

  Future<void> stopAutoIllumination() async {
    try {
      _subscription?.cancel();
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
      _isBoosted = false;
      debugPrint("SYSTEM: Auto-Illumination Sensor Offline.");
    } catch (e) {
      debugPrint("SYSTEM ERROR: Failed to reset brightness: $e");
    }
  }
}