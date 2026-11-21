
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'education_app.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);

        if (kDebugMode) {
          debugPrint(
            'Simorgh Flutter error: ${details.exceptionAsString()}',
          );
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) {
          debugPrint('Simorgh uncaught error: $error');
          debugPrintStack(stackTrace: stack);
        }

        return true;
      };

      runApp(const EducationApp());
    },
    (error, stack) {
      if (kDebugMode) {
        debugPrint('Simorgh zone error: $error');
        debugPrintStack(stackTrace: stack);
      }
    },
  );
}
