import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.rtmp_streaming');
  const events = EventChannel('com.rtmp_streaming.eventchannel/91');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController controller;
  late MockStreamHandlerEventSink sink;
  late Future<Object?> Function(MethodCall) handler;
  late List<String> calls;
  const capabilities = {
    'backend': 'test',
    'protocols': ['rtmp'],
    'features': <String, bool>{},
    'videoCodecs': ['h264'],
    'audioCodecs': ['aac'],
  };

  setUp(() async {
    calls = [];
    handler = (_) async => null;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, eventSink) {
          sink = eventSink;
        },
      ),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initialize') {
        return {
          'textureId': 1,
          'eventId': 91,
          'previewWidth': 720.0,
          'previewHeight': 1280.0,
          'previewQuarterTurns': 0,
        };
      }
      if (call.method == 'getCapabilities') return capabilities;
      return handler(call);
    });
    controller = CameraController(ResolutionPreset.high);
    await controller.initialize(CameraDescription(name: '0'));
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    await controller.dispose();
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'display dimensions produce matching portrait and landscape aspect ratios',
    () async {
      expect(controller.value.aspectRatio, 9 / 16);
      sink.success({
        'eventType': 'preview_geometry_changed',
        'previewWidth': 1280,
        'previewHeight': 720,
        'previewQuarterTurns': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.previewSize, const Size(1280, 720));
      expect(controller.value.aspectRatio, 16 / 9);
      sink.success({
        'eventType': 'preview_geometry_changed',
        'previewWidth': 0,
        'previewHeight': double.nan,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.previewSize, const Size(1280, 720));
    },
  );

  test(
    'late recording completion cannot notify or resurrect a disposed controller',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoRecording') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final start = controller.startVideoRecording('/tmp/test.mp4');
      await entered.future;
      final disposing = controller.dispose();
      expect(calls.where((m) => m == 'dispose'), isEmpty);
      reply.complete(null);
      await Future.wait([start, disposing]);
      expect(controller.value.isRecordingVideo, false);
      expect(calls.where((m) => m == 'dispose').length, 1);
      await controller.dispose();
      expect(calls.where((m) => m == 'dispose').length, 1);
    },
  );

  test(
    'duplicate starts are rejected before a second native request',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoStreaming') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final first = controller.startVideoStreaming(
        'rtmp://example.invalid/live/a',
      );
      await entered.future;
      await expectLater(
        controller.startVideoStreaming('rtmp://example.invalid/live/b'),
        throwsA(
          isA<CameraException>().having(
            (e) => e.code,
            'code',
            'operationInProgress',
          ),
        ),
      );
      reply.complete(null);
      await first;
      expect(calls.where((m) => m == 'startVideoStreaming').length, 1);
    },
  );

  test(
    'stop during connecting cleans up native output and suppresses stale success',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoStreaming') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final start = controller.startVideoStreaming(
        'rtmp://example.invalid/live/key',
      );
      await entered.future;
      final stopping = controller.stopVideoStreaming();
      sink.success({'eventType': 'success'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isStreaming, false);
      reply.complete(null);
      await Future.wait([start, stopping]);
      expect(calls, contains('stopStreaming'));
      expect(controller.value.isStreaming, false);
      expect(controller.value.streamingProtocol, isNull);
    },
  );

  for (final stopRecording in [false, true]) {
    test(
      'combined start keeps the other output when stopping recording=$stopRecording',
      () async {
        final reply = Completer<Object?>();
        final entered = Completer<void>();
        handler = (call) async {
          if (call.method == 'startVideoRecordingAndStreaming') {
            entered.complete();
            return reply.future;
          }
          return null;
        };
        final start = controller.startVideoRecordingAndStreaming(
          '/tmp/test.mp4',
          'rtmp://example.invalid/live/key',
        );
        await entered.future;
        final stopping = stopRecording
            ? controller.stopVideoRecording()
            : controller.stopVideoStreaming();
        reply.complete(null);
        await Future.wait([start, stopping]);
        expect(controller.value.isRecordingVideo, !stopRecording);
        expect(controller.value.isStreaming, stopRecording);
      },
    );
  }

  test(
    'stop-all cancels pending combined output without resurrecting either state',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoRecordingAndStreaming') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final start = controller.startVideoRecordingAndStreaming(
        '/tmp/test.mp4',
        'rtmp://example.invalid/live/key',
      );
      await entered.future;
      final stopping = controller.stopRecordingOrStreaming();
      reply.complete(null);
      await Future.wait([start, stopping]);
      expect(calls, contains('stopRecordingOrStreaming'));
      expect(controller.value.isRecordingVideo, false);
      expect(controller.value.isStreaming, false);
    },
  );

  test(
    'failed stop preserves state and does not poison the transition queue',
    () async {
      await controller.startVideoStreaming('rtmp://example.invalid/live/key');
      var fail = true;
      handler = (call) async {
        if (call.method == 'stopStreaming' && fail) {
          throw PlatformException(code: 'test');
        }
        return null;
      };
      await expectLater(
        controller.stopVideoStreaming(),
        throwsA(isA<CameraException>()),
      );
      expect(controller.value.isStreaming, true);
      fail = false;
      await controller.stopVideoStreaming();
      expect(controller.value.isStreaming, false);
    },
  );
  test('stop before native startup prevents the request entirely', () async {
    final start = controller.startVideoStreaming(
      'rtmp://example.invalid/live/key',
    );
    final stop = controller.stopVideoStreaming();
    await Future.wait([start, stop]);
    expect(calls.where((m) => m == 'startVideoStreaming'), isEmpty);
    expect(controller.value.isStreaming, false);
  });

  test(
    'dispose before native startup prevents a late native request',
    () async {
      final start = controller.startVideoRecording('/tmp/test.mp4');
      await controller.dispose();
      await start;
      expect(calls.where((m) => m == 'startVideoRecording'), isEmpty);
      expect(controller.value.isRecordingVideo, false);
    },
  );

  test(
    'stopping the network leaves an independent pending recording intact',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoRecording') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final start = controller.startVideoRecording('/tmp/test.mp4');
      await entered.future;
      final stop = controller.stopVideoStreaming();
      reply.complete(null);
      await Future.wait([start, stop]);
      expect(controller.value.isRecordingVideo, true);
      expect(controller.value.isStreaming, false);
    },
  );
  test(
    'native disconnect before start reply cannot resurrect streaming',
    () async {
      final reply = Completer<Object?>();
      final entered = Completer<void>();
      handler = (call) async {
        if (call.method == 'startVideoStreaming') {
          entered.complete();
          return reply.future;
        }
        return null;
      };
      final start = controller.startVideoStreaming(
        'rtmp://example.invalid/live/key',
      );
      await entered.future;
      sink.success({'eventType': 'rtmp_stopped'});
      await Future<void>.delayed(Duration.zero);
      reply.complete(null);
      await start;
      expect(controller.value.isStreaming, false);
    },
  );
}
