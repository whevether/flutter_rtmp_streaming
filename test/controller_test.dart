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

  test(
    'statistics accept CGFloat values and keep unknown values null',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStreamStatistics') {
          return {
            'width': 1280.0,
            'height': 720.0,
            'fps': 29.97,
            'bitrate': 1200000,
            'bytesSend': 4200.0,
          };
        }
        return null;
      });
      final stats = await controller.getStreamStatistics();
      expect(stats.width, 1280);
      expect(stats.height, 720);
      expect(stats.bytesSend, 4200);
      expect(stats.cacheSize, isNull);
      expect(stats.sentAudioFrames, isNull);
      expect(stats.rttMicros, isNull);
    },
  );

  test(
    'capabilities come from native backend and unknown features are false',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCapabilities') {
          return {
            'backend': 'test/SPM',
            'protocols': ['rtmp', 'whep'],
            'videoCodecs': ['h264'],
            'audioCodecs': ['aac'],
            'features': {'recordingPause': false, 'zoom': true},
          };
        }
        return null;
      });
      final caps = await controller.getCapabilities();
      expect(caps.supports('zoom'), isTrue);
      expect(caps.supports('recordingPause'), isFalse);
      expect(caps.supports('notImplemented'), isFalse);
      expect(caps.supportsProtocol(StreamingProtocol.whep), isTrue);
      expect(caps.supportsProtocol(StreamingProtocol.rtsp), isFalse);
    },
  );

  test('torch and mute work during preview without streaming', () async {
    controller.value = controller.value.copyWith(isStreaming: false);
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'setHasAudio') {
        expect((call.arguments as Map)['isEnable'], isFalse);
      }
      return null;
    });
    await controller.switchFlashLight(true);
    await controller.setAudioMuted(true);
    expect(methods, ['switchFlashLight', 'setHasAudio']);
  });

  test('common camera controls dispatch on the native backend', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCameraControls') {
        return {
          'zoom': 1.0,
          'minZoom': 1,
          'maxZoom': 5,
          'autoFocus': true,
          'exposure': 0,
          'torch': false,
        };
      }
      if (call.method == 'tapToFocus') return true;
      return null;
    });
    expect((await controller.getCameraControls()).maxZoom, 5);
    await controller.setZoom(2);
    await controller.setAutoFocus(true);
    expect(await controller.tapToFocus(), isTrue);
  });

  test('invalid encoder settings never reach native code', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    await expectLater(
      controller.setVideoSettings(width: 721, height: 1280),
      throwsArgumentError,
    );
    await expectLater(
      controller.setVideoSettings(expectedFrameRate: double.nan),
      throwsArgumentError,
    );
    await expectLater(
      controller.setVideoSettings(bitRateMode: 'ignored'),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('stop-all is idempotent after all outputs stopped', () async {
    controller.value = controller.value.copyWith(
      isRecordingVideo: false,
      isStreaming: false,
    );
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method.startsWith('stop')) stops++;
      return null;
    });
    await controller.stopRecordingOrStreaming();
    await controller.stopVideoStreaming();
    expect(stops, 0);
  });

  test(
    'multi IDs are normalized and final target stop preserves recording',
    () async {
      controller.value = controller.value.copyWith(
        isStreaming: false,
        isRecordingVideo: false,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCapabilities') {
          return {
            'backend': 'test',
            'protocols': ['rtmp', 'srt'],
            'videoCodecs': ['h264'],
            'audioCodecs': ['aac'],
            'features': <String, bool>{},
          };
        }
        if (call.method == 'startMultiStreaming') {
          final targets = (call.arguments as Map)['destinations'] as List;
          expect((targets[0] as Map)['id'], 'dest_0');
          expect((targets[1] as Map)['id'], 'backup');
        }
        return null;
      });
      await controller.startMultiStreaming([
        StreamDestination(url: 'rtmp://host/live/key'),
        StreamDestination(
          url: 'srt://host:9000',
          protocol: StreamingProtocol.srt,
          id: 'backup',
        ),
      ]);
      controller.value = controller.value.copyWith(isRecordingVideo: true);
      expect(controller.streamingDestinationIds, ['dest_0', 'backup']);
      await controller.stopStreamingDestination('dest_0');
      expect(controller.value.isStreaming, isTrue);
      await controller.stopStreamingDestination('backup');
      expect(controller.value.isStreaming, isFalse);
      expect(controller.value.isRecordingVideo, isTrue);
    },
  );

  test('multi start failure rolls back partial success state', () async {
    controller.value = controller.value.copyWith(
      isStreaming: false,
      isRecordingVideo: false,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCapabilities') {
        return {
          'backend': 'test',
          'protocols': ['rtmp'],
          'videoCodecs': ['h264'],
          'audioCodecs': ['aac'],
          'features': <String, bool>{},
        };
      }
      if (call.method == 'startMultiStreaming') {
        controller.value = controller.value.copyWith(isStreaming: true);
        throw PlatformException(code: 'second_destination_failed');
      }
      return null;
    });
    await expectLater(
      controller.startMultiStreaming([
        StreamDestination(url: 'rtmp://host/live/key'),
      ]),
      throwsA(isA<CameraException>()),
    );
    expect(controller.value.isStreaming, isFalse);
    expect(controller.streamingDestinationIds, isEmpty);
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
      await expectLater(
        controller.setOverlayText(text: 'x', fontSize: double.nan),
        throwsArgumentError,
      );
      await expectLater(
        controller.setOverlayImage(
          filePath: '/tmp/test.png',
          scale: double.infinity,
        ),
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
      controller.value = const CameraValue.uninitialized();
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
    controller.value = const CameraValue.uninitialized();
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
