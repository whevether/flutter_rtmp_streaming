import 'package:flutter/material.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

// Run separately: flutter run -t lib/playback.dart (iOS).
void main() => runApp(const MaterialApp(home: PlaybackExample()));

class PlaybackExample extends StatefulWidget {
  const PlaybackExample({super.key});
  @override
  State<PlaybackExample> createState() => _PlaybackExampleState();
}

class _PlaybackExampleState extends State<PlaybackExample> {
  final player = PlayerController();
  final url = TextEditingController(text: 'rtmp://localhost/live/stream');
  StreamingProtocol protocol = StreamingProtocol.rtmp;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _run(player.initialize);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    player.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RTMP / WHEP playback')),
    body: ValueListenableBuilder<PlayerValue>(
      valueListenable: player,
      builder: (context, value, child) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: PlayerPreview(player)),
          TextField(
            controller: url,
            decoration: const InputDecoration(labelText: 'Playback URL'),
          ),
          DropdownButton<StreamingProtocol>(
            value: protocol,
            items: [StreamingProtocol.rtmp, StreamingProtocol.whep]
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(p.name.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: busy || value.isPlaying
                ? null
                : (p) => setState(() => protocol = p!),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy || !value.isInitialized
                    ? null
                    : () => _run(
                        value.isPlaying
                            ? player.stop
                            : () => player.play(
                                url.text.trim(),
                                protocol: protocol,
                              ),
                      ),
                child: Text(value.isPlaying ? 'Stop' : 'Play'),
              ),
              if (protocol == StreamingProtocol.rtmp)
                OutlinedButton(
                  onPressed: busy || !value.isPlaying
                      ? null
                      : () => _run(() => player.setPaused(!value.isPaused)),
                  child: Text(value.isPaused ? 'Resume' : 'Pause'),
                ),
              OutlinedButton(
                onPressed: busy || !value.isPlaying
                    ? null
                    : () => _run(() => player.setMuted(true)),
                child: const Text('Mute'),
              ),
              OutlinedButton(
                onPressed: busy || !value.isPlaying
                    ? null
                    : () => _run(() => player.setMuted(false)),
                child: const Text('Unmute'),
              ),
            ],
          ),
          if (error ?? value.error case final message?) Text(message),
        ],
      ),
    ),
  );
}
