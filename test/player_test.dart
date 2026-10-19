import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.rtmp_streaming');
  const events = EventChannel('com.rtmp_streaming.eventchannel/91');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late PlayerController player;
  bool failPause = false;
  setUp(() async {
    failPause = false;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCapabilities') {
        return {
          'features': {'playback': true},
        };
      }
      if (call.method == 'initializePlayback') {
        return {'textureId': 1, 'eventId': 91};
      }
      if (call.method == 'pauseStream' && failPause) {
        throw PlatformException(code: 'pause_failed');
      }
      return null;
    });
    player = PlayerController();
    await player.initialize();
  });
  tearDown(() async {
    await player.dispose();
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('concurrent initialize shares one native session', () async {
    await player.dispose();
    player = PlayerController();
    var initialized = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCapabilities') {
        return {
          'features': {'playback': true},
        };
      }
      if (call.method == 'initializePlayback') {
        initialized++;
        return {'textureId': 1, 'eventId': 91};
      }
      return null;
    });
    await Future.wait([player.initialize(), player.initialize()]);
    expect(initialized, 1);
  });

  test('failed playback pause preserves the playing state', () async {
    await player.play('rtmp://host/live/key');
    failPause = true;
    await expectLater(
      player.setPaused(true),
      throwsA(isA<PlatformException>()),
    );
    expect(player.value.isPlaying, isTrue);
    expect(player.value.isPaused, isFalse);
  });
  test('WHEP pause is rejected while mute and stop remain available', () async {
    await player.play('https://host/whep', protocol: StreamingProtocol.whep);
    await expectLater(player.setPaused(true), throwsStateError);
    await player.setMuted(true);
    await player.stop();
    expect(player.value.isPlaying, isFalse);
  });
  test('disposed player cannot initialize again', () async {
    await player.dispose();
    await expectLater(player.initialize(), throwsStateError);
  });
}
