import 'dart:async';

Future<String> startWebSpeech(
  Function(String) onResult,
  Function(String) onError,
) async {
  throw UnsupportedError('Web speech not supported on this platform');
}

void stopWebSpeech() {
  throw UnsupportedError('Web speech not supported on this platform');
}
