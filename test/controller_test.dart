import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.rtmp_streaming');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
  test(
    'snapshot rejects overlap and clears its pending state after failure',
    () async {
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (_) => pending.future);
      final first = controller.takePicture('/tmp/first.jpg');
      await expectLater(
        controller.takePicture('/tmp/second.jpg'),
        throwsA(isA<CameraException>()),
      );
      final failed = expectLater(first, throwsA(isA<CameraException>()));
      pending.completeError(PlatformException(code: 'capture_failed'));
      await failed;
      expect(controller.value.isTakingPicture, isFalse);
    },
  );
  test('uninitialized controller never sends a capture request', () async {
    controller.value = const CameraValue.uninitialized();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    await expectLater(
      controller.takePicture('/tmp/photo.jpg'),
      throwsA(isA<CameraException>()),
    );
    expect(calls, 0);
  });
  test('combined stop works for recording without a network stream', () async {
    controller.value = controller.value.copyWith(isStreaming: false);
    await controller.stopRecordingOrStreaming();
    expect(controller.value.isRecordingVideo, isFalse);
    expect(controller.value.isStreaming, isFalse);
  });

  test(
    'failed initialization does not leave dispose waiting forever',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          throw PlatformException(code: 'camera_denied');
        }
        return null;
      });
      await expectLater(
        controller.initialize(CameraDescription(name: '0')),
        throwsA(isA<CameraException>()),
      );
      await controller.dispose().timeout(const Duration(seconds: 2));
    },
  );

  test(
    'invalid camera controls and metadata fail before native dispatch',
    () async {
      await expectLater(controller.setZoom(double.nan), throwsArgumentError);
      await expectLater(controller.tapToFocus(x: 1.5), throwsArgumentError);
      await expectLater(
        controller.setPitchShift(double.infinity),
        throwsArgumentError,
      );
      await expectLater(controller.setFrameRate(0), throwsArgumentError);
      await expectLater(
        controller.setManualExposure(iso: 100),
        throwsArgumentError,
      );
      await expectLater(
        controller.setCaptureTelemetry(true, intervalMs: 10),
        throwsArgumentError,
      );
      await expectLater(
        controller.setRtmpMetadata({'bad': double.nan}),
        throwsArgumentError,
      );
      await expectLater(
        controller.setRtmpMetadata({'nested': <String, String>{}}),
        throwsArgumentError,
      );
    },
  );

  test('camera controls accept integer and floating-point native numbers', () {
    final controls = CameraControls.fromMap({
      'zoom': 2,
      'minZoom': 1.0,
      'maxZoom': 8,
      'autoFocus': true,
      'exposure': -1,
      'torch': false,
    });
    expect(controls.zoom, 2.0);
    expect(controls.maxZoom, 8.0);
    expect(controls.exposure, -1);
  });

  test(
    'native disconnect retains recording and destination events retain their id',
    () async {
      const events = EventChannel('com.rtmp_streaming.eventchannel/42');
      late MockStreamHandlerEventSink sink;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, events) {
            sink = events;
          },
        ),
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          return {
            'textureId': 0,
            'eventId': 42,
            'previewWidth': 640,
            'previewHeight': 480,
            'previewQuarterTurns': 0,
          };
        }
        return null;
      });
      await controller.initialize(CameraDescription(name: '0'));
      await Future<void>.delayed(Duration.zero);
      controller.value = controller.value.copyWith(
        isRecordingVideo: true,
        isStreaming: true,
      );
      sink.success({
        'eventType': 'destination_stopped',
        'destinationId': 'backup',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isStreaming, isTrue);
      expect(controller.value.event['destinationId'], 'backup');
      sink.success({'eventType': 'rtmp_stopped'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isStreaming, isFalse);
      expect(controller.value.isRecordingVideo, isTrue);
      await controller.dispose();
      messenger.setMockStreamHandler(events, null);
    },
  );
  test('dispose can finish while initialization is still pending', () async {
    final reply = Completer<Map<String, dynamic>>();
    var nativeDisposals = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return reply.future;
      if (call.method == 'dispose') nativeDisposals++;
      return null;
    });
    final initializing = controller.initialize(CameraDescription(name: '0'));
    final disposing = controller.dispose();
    reply.complete({
      'textureId': 0,
      'eventId': 1,
      'previewWidth': 640,
      'previewHeight': 480,
      'previewQuarterTurns': 0,
    });
    await Future.wait([
      initializing,
      disposing,
    ]).timeout(const Duration(seconds: 2));
    expect(nativeDisposals, 1);
  });
}
