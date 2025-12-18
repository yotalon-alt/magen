// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'dart:async';

Future<String> startWebSpeech(
  Function(String) onResult,
  Function(String) onError,
) async {
  final completer = Completer<String>();

  js.context.callMethod('startWebSpeechRecognition', [
    (String text) {
      if (!completer.isCompleted) {
        completer.complete(text);
      }
      onResult(text);
    },
    (String error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      onError(error);
    },
  ]);

  return completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      throw TimeoutException('Speech recognition timeout');
    },
  );
}

void stopWebSpeech() {
  try {
    js.context.callMethod('stopWebSpeechRecognition');
  } catch (e) {
    // Ignore errors on stop
  }
}
