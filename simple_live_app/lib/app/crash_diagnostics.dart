import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Small local reports remain available even when verbose logging is disabled.
class CrashDiagnostics {
  static const _channel = MethodChannel('com.xycz.simple_live/diagnostics');
  static const maxFileBytes = 256 * 1024;
  static Directory? _directory;
  static bool _sampling = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      final support = await getApplicationSupportDirectory();
      _directory =
          await Directory('${support.path}/log').create(recursive: true);
      final previousFlutterHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        recordError(details.exception, details.stack ?? StackTrace.current);
        previousFlutterHandler?.call(details);
      };
      final previousPlatformHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        recordError(error, stack);
        return previousPlatformHandler?.call(error, stack) ?? false;
      };
      final exits = await _channel.invokeListMethod<dynamic>('previousExits');
      if (exits?.isNotEmpty ?? false) {
        _write('crash', 'Previous Android exits: ${jsonEncode(exits)}');
      }
    } catch (error) {
      debugPrint('Crash diagnostics unavailable: $error');
    }
  }

  static void recordError(Object error, StackTrace stack) {
    _write('crash', '$error\n$stack');
  }

  static Future<void> samplePlayback(String context) async {
    if (_directory == null || _sampling) return;
    _sampling = true;
    try {
      var descriptors = 0;
      await for (final _
          in Directory('/proc/self/fd').list(followLinks: false)) {
        descriptors++;
      }
      _write('playback-health',
          '$context rssMiB=${(ProcessInfo.currentRss / 1048576).round()} fd=$descriptors');
    } catch (error) {
      debugPrint('Playback diagnostics unavailable: $error');
    } finally {
      _sampling = false;
    }
  }

  static void _write(String name, String message) {
    final directory = _directory;
    if (directory == null) return;
    try {
      // Keep crash-time allocations and total retained disk space bounded.
      final text =
          message.length > 16000 ? message.substring(0, 16000) : message;
      final bytes = utf8.encode('${DateTime.now().toIso8601String()} $text\n');
      final file = File('${directory.path}/$name.log');
      if (file.existsSync() &&
          file.lengthSync() + bytes.length > maxFileBytes) {
        final previous = File('${directory.path}/$name.previous.log');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
      file.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);
    } catch (_) {
      // Reporting must never become a second failure (e.g. a full disk).
    }
  }
}
