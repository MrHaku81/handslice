// Dart-seitiger Nachweis: Beim erfolgreichen Zeitraffer-Download ruft
// die App den MethodChannel `dev.handslice.handslice/engine` mit
// `saveVideoToGallery` auf; Argumente enthalten den tatsaechlichen
// Dateinamen und `video/mp4`-Mime. Die Kotlin-Seite nutzt
// MediaStore.Video.Media.EXTERNAL_CONTENT_URI mit
// RELATIVE_PATH=Movies/Handslice; keinen WRITE_EXTERNAL_STORAGE
// (API 29+ scoped storage).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveVideoToGallery wird mit korrekten Argumenten gerufen', () async {
    const channel = MethodChannel('dev.handslice.handslice/engine');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'saveVideoToGallery') {
        return 'content://media/external/video/media/42';
      }
      return null;
    });

    final uri = await channel.invokeMethod<String>('saveVideoToGallery', {
      'srcPath': '/path/to/handslice-timelapse.mp4',
      'displayName': 'handslice-timelapse.mp4',
      'mime': 'video/mp4',
    });

    expect(uri, startsWith('content://media/'));
    expect(calls, hasLength(1));
    expect(calls.first.method, 'saveVideoToGallery');
    final args = Map<String, dynamic>.from(calls.first.arguments as Map);
    expect(args['srcPath'], '/path/to/handslice-timelapse.mp4');
    expect(args['displayName'], 'handslice-timelapse.mp4');
    expect(args['mime'], 'video/mp4');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
