import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the AutoOrientationPlugin using package:web.
class AutoOrientationWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'auto_orientation',
      const StandardMethodCodec(),
      registrar,
    );
    final pluginInstance = AutoOrientationWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    try {
      final orientation = web.window.screen.orientation;

      switch (call.method) {
        case 'setLandscapeRight':
        case 'setLandscapeAuto':
          await orientation.lock('landscape-primary').toDart;
          break;
        case 'setLandscapeLeft':
          await orientation.lock('landscape-secondary').toDart;
          break;
        case 'setPortraitUp':
        case 'setPortraitAuto':
          await orientation.lock('portrait-primary').toDart;
          break;
        case 'setPortraitDown':
          await orientation.lock('portrait-secondary').toDart;
          break;
        case 'setAuto':
        case 'setScreenOrientationUser':
          orientation.unlock();
          break;
        default:
          throw PlatformException(
            code: 'Unimplemented',
            details:
                'auto_orientation_v2 for Web does not implement ${call.method}',
          );
      }
    } catch (_) {
      // Fallback gracefully on browsers without ScreenOrientation API
    }
    return null;
  }
}
