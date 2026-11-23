import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'education_app.dart';

/// Shared entry point for reporting unexpected errors.
///
/// Developer logging is invoked in every build mode.
/// This is not persistent storage or a remote crash-reporting service.
void _reportError(
  Object error,
  StackTrace stackTrace, {
  required String source,
}) {
  developer.log(
    'Unhandled error in $source',
    name: 'moshaver_tahsili',
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );

  if (kDebugMode) {
    debugPrint('moshaver_tahsili [$source]: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

void main() {
  runZonedGuarded<void>(
    () {
      // Initialize the binding and run the app in the same zone.
      WidgetsFlutterBinding.ensureInitialized();

      // Handle errors caught by the Flutter framework.
      FlutterError.onError = (FlutterErrorDetails details) {
        // Preserve Flutter's standard error output.
        FlutterError.presentError(details);

        _reportError(
          details.exception,
          details.stack ?? StackTrace.current,
          source: 'Flutter framework',
        );
      };

      // Handle unhandled errors delivered by the Flutter engine.
      PlatformDispatcher.instance.onError = (
        Object error,
        StackTrace stackTrace,
      ) {
        _reportError(
          error,
          stackTrace,
          source: 'Platform dispatcher',
        );

        // The error has been reported by this handler.
        return true;
      };

      runApp(const EducationApp());
    },
    (Object error, StackTrace stackTrace) {
      // Handle uncaught errors in this zone.
      _reportError(
        error,
        stackTrace,
        source: 'Application zone',
      );
    },
  );
}
