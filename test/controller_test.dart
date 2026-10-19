import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.rtmp_streaming');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController controller;
  setUp(() {
    controller = CameraController(ResolutionPreset.medium);
    controller.value = controller.value.copyWith(
      isInitialized: true,
      isRecordingVideo: true,
      isStreaming: true,
      streamingProtocol: StreamingProtocol.rtmp,
    );
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() async {
    await controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('stopping the network preserves a concurrent recording', () async {
    await controller.stopVideoStreaming();
    expect(controller.value.isStreaming, isFalse);
    expect(controller.value.streamingProtocol, isNull);
    expect(controller.value.isRecordingVideo, isTrue);
  });
  test('stopping a recording preserves the stream and protocol', () async {
    await controller.stopVideoRecording();
    expect(controller.value.isRecordingVideo, isFalse);
    expect(controller.value.isStreaming, isTrue);
    expect(controller.value.streamingProtocol, StreamingProtocol.rtmp);
  });
  for (final stopRecording in [true, false]) {
    test('failed stop preserves state (recording=$stopRecording)', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'native_failure');
      });
      final operation = stopRecording
          ? controller.stopVideoRecording()
          : controller.stopVideoStreaming();
      await expectLater(operation, throwsA(isA<CameraException>()));
      expect(controller.value.isStreaming, isTrue);
      expect(controller.value.isRecordingVideo, isTrue);
      expect(controller.value.streamingProtocol, StreamingProtocol.rtmp);
    });
  }
  test('snapshot rejects overlap and clears its pending state after failure', () async {
    final pending = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final first = controller.takePicture('/tmp/first.jpg');
    await expectLater(controller.takePicture('/tmp/second.jpg'),
        throwsA(isA<CameraException>()));
    final failed = expectLater(first, throwsA(isA<CameraException>()));
    pending.completeError(PlatformException(code: 'capture_failed'));
    await failed;
    expect(controller.value.isTakingPicture, isFalse);
  });
  test('uninitialized controller never sends a capture request', () async {
    controller.value = const CameraValue.uninitialized();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async { calls++; return null; });
    await expectLater(controller.takePicture('/tmp/photo.jpg'),
        throwsA(isA<CameraException>()));
    expect(calls, 0);
  });
}
