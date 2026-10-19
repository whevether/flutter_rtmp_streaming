// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final MethodChannel _channel = const MethodChannel('com.rtmp_streaming');

enum CameraLensDirection { front, back, external }

/// Streaming protocol for [CameraController.startVideoStreaming].
///
/// Platform support:
/// - Android: [rtmp], [rtsp], [srt], [udp], [whip]
/// - iOS: [rtmp], [srt], [whip], [whep] ([whip]/[whep] via RTCHaishinKit, alpha)
///
/// SRT URL example:
/// `srt://host:10080?streamid=#!::r=live/livestream,m=publish`
enum StreamingProtocol { rtmp, rtsp, srt, udp, whip, whep }

String serializeStreamingProtocol(StreamingProtocol protocol) {
  switch (protocol) {
    case StreamingProtocol.rtmp:
      return 'rtmp';
    case StreamingProtocol.rtsp:
      return 'rtsp';
    case StreamingProtocol.srt:
      return 'srt';
    case StreamingProtocol.udp:
      return 'udp';
    case StreamingProtocol.whip:
      return 'whip';
    case StreamingProtocol.whep:
      return 'whep';
  }
}

bool isStreamingProtocolSupported(StreamingProtocol protocol) {
  if (Platform.isAndroid) {
    return protocol != StreamingProtocol.whep;
  }
  if (Platform.isIOS) {
    return protocol == StreamingProtocol.rtmp ||
        protocol == StreamingProtocol.srt ||
        protocol == StreamingProtocol.whip ||
        protocol == StreamingProtocol.whep;
  }
  return false;
}

/// Protocols allowed in [CameraController.startMultiStreaming] (excludes WHIP/WHEP).
bool isMultiStreamingProtocolSupported(StreamingProtocol protocol) {
  if (protocol == StreamingProtocol.whip ||
      protocol == StreamingProtocol.whep) {
    return false;
  }
  return isStreamingProtocolSupported(protocol);
}

/// Overlay corner / center for [CameraController.setOverlayText] /
/// [CameraController.setOverlayImage].
enum OverlayPosition { topLeft, topRight, bottomLeft, bottomRight, center }

String serializeOverlayPosition(OverlayPosition position) {
  switch (position) {
    case OverlayPosition.topLeft:
      return 'topLeft';
    case OverlayPosition.topRight:
      return 'topRight';
    case OverlayPosition.bottomLeft:
      return 'bottomLeft';
    case OverlayPosition.bottomRight:
      return 'bottomRight';
    case OverlayPosition.center:
      return 'center';
  }
}

/// Video codec for [CameraController.setVideoCodec] (Android / RootEncoder).
enum VideoCodecType { h264, h265, av1, vp8, vp9 }

String serializeVideoCodecType(VideoCodecType codec) {
  switch (codec) {
    case VideoCodecType.h264:
      return 'h264';
    case VideoCodecType.h265:
      return 'h265';
    case VideoCodecType.av1:
      return 'av1';
    case VideoCodecType.vp8:
      return 'vp8';
    case VideoCodecType.vp9:
      return 'vp9';
  }
}

/// Audio codec for [CameraController.setAudioCodec] (Android / RootEncoder).
enum AudioCodecType { aac, heAac, opus, g711 }

String serializeAudioCodecType(AudioCodecType codec) {
  switch (codec) {
    case AudioCodecType.aac:
      return 'aac';
    case AudioCodecType.heAac:
      return 'heAac';
    case AudioCodecType.opus:
      return 'opus';
    case AudioCodecType.g711:
      return 'g711';
  }
}

/// Video capture source for [CameraController.setVideoSource] (Android).
enum VideoSourceType { camera2, cameraX, uvc, screen }

String serializeVideoSourceType(VideoSourceType source) {
  switch (source) {
    case VideoSourceType.camera2:
      return 'camera2';
    case VideoSourceType.cameraX:
      return 'cameraX';
    case VideoSourceType.uvc:
      return 'uvc';
    case VideoSourceType.screen:
      return 'screen';
  }
}

/// Current controls reported by an active Android Camera2/CameraX source.
class CameraControls {
  const CameraControls({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.autoFocus,
    required this.exposure,
    required this.torch,
  });
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final bool autoFocus;
  final int exposure;
  final bool torch;

  factory CameraControls.fromMap(Map<String, dynamic> data) => CameraControls(
    zoom: (data['zoom'] as num).toDouble(),
    minZoom: (data['minZoom'] as num).toDouble(),
    maxZoom: (data['maxZoom'] as num).toDouble(),
    autoFocus: data['autoFocus'] as bool,
    exposure: (data['exposure'] as num).toInt(),
    torch: data['torch'] as bool,
  );
}

/// Android GPU effects. Use the overlay methods for text and still images.
enum VideoEffect {
  deformation,
  beauty,
  black,
  blur,
  brightness,
  cartoon,
  chroma,
  chromaticAberration,
  circle,
  color,
  contrast,
  crop,
  distortedTv,
  duotone,
  earlyBird,
  edgeDetection,
  exposure,
  fire,
  gamma,
  glitch,
  gif,
  greyScale,
  halftoneLines,
  image70s,
  lamoish,
  money,
  negative,
  noise,
  pixelated,
  polygonization,
  rainbow,
  rgbSaturation,
  ripple,
  rotation,
  saturation,
  sepia,
  sharpness,
  snow,
  video,
  temperature,
  zebra,
  sobel,
}

/// Capabilities reported by the loaded native backend. Hardware features can
/// change when the camera/source changes; query again after switching sources.
class StreamingCapabilities {
  StreamingCapabilities.fromMap(Map<dynamic, dynamic> map)
    : backend = map['backend'] as String,
      protocols = List<String>.unmodifiable(
        (map['protocols'] as List).cast<String>(),
      ),
      features = Map<String, bool>.unmodifiable(
        (map['features'] as Map).cast<String, bool>(),
      ),
      videoCodecs = List<String>.unmodifiable(
        (map['videoCodecs'] as List).cast<String>(),
      ),
      audioCodecs = List<String>.unmodifiable(
        (map['audioCodecs'] as List).cast<String>(),
      );
  final String backend;
  final List<String> protocols;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final Map<String, bool> features;
  bool supports(String feature) => features[feature] == true;
  bool supportsProtocol(StreamingProtocol protocol) =>
      protocols.contains(protocol.name);
}

/// One destination for [CameraController.startMultiStreaming].
class StreamDestination {
  const StreamDestination({
    required this.url,
    this.protocol = StreamingProtocol.rtmp,
    this.id,
  });

  final String url;
  final StreamingProtocol protocol;
  final String? id;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'url': url,
    'protocol': serializeStreamingProtocol(protocol),
    if (id != null) 'id': id,
  };
}

/// Affect the quality of video recording and image capture.
///
/// Android 与 iOS 行为对齐：同一 preset 在两端得到相同或最接近的目标分辨率。
/// 若设备不支持目标分辨率，会自动选用最接近的可用分辨率。
enum ResolutionPreset {
  /// 352x288 (CIF)
  low,

  /// 640x480 (VGA)
  medium,

  /// 1280x720 (720p)
  high,

  /// 1920x1080 (1080p)
  veryHigh,

  /// 3840x2160 (4K)
  ultraHigh,

  /// 设备支持的最高分辨率
  max,
}

/// Returns the resolution preset as a String.
String serializeResolutionPreset(ResolutionPreset resolutionPreset) {
  switch (resolutionPreset) {
    case ResolutionPreset.max:
      return 'max';
    case ResolutionPreset.ultraHigh:
      return 'ultraHigh';
    case ResolutionPreset.veryHigh:
      return 'veryHigh';
    case ResolutionPreset.high:
      return 'high';
    case ResolutionPreset.medium:
      return 'medium';
    case ResolutionPreset.low:
      return 'low';
  }
}

CameraLensDirection _parseCameraLensDirection(String? string) {
  switch (string) {
    case 'front':
      return CameraLensDirection.front;
    case 'back':
      return CameraLensDirection.back;
    case 'external':
      return CameraLensDirection.external;
    case 'unspecified':
      return CameraLensDirection.external;
  }
  throw ArgumentError('Unknown CameraLensDirection value');
}

/// Completes with a list of available cameras.
///
/// May throw a [CameraException].
Future<List<CameraDescription>> availableCameras() async {
  try {
    final List<Map<dynamic, dynamic>> cameras = (await _channel
        .invokeListMethod<Map<dynamic, dynamic>>('availableCameras'))!;
    return cameras.map((Map<dynamic, dynamic> camera) {
      return CameraDescription(
        name: camera['name'],
        lensDirection: _parseCameraLensDirection(camera['lensFacing']),
        sensorOrientation: camera['sensorOrientation'],
      );
    }).toList();
  } on PlatformException catch (e) {
    throw CameraException(e.code, e.message);
  }
}

class CameraDescription {
  CameraDescription({this.name, this.lensDirection, this.sensorOrientation});

  final String? name;
  final CameraLensDirection? lensDirection;

  /// Clockwise angle through which the output image needs to be rotated to be upright on the device screen in its native orientation.
  ///
  /// **Range of valid values:**
  /// 0, 90, 180, 270
  ///
  /// On Android, also defines the direction of rolling shutter readout, which
  /// is from top to bottom in the sensor's coordinate system.
  final int? sensorOrientation;

  @override
  bool operator ==(Object other) {
    return other is CameraDescription &&
        other.name == name &&
        other.lensDirection == lensDirection;
  }

  @override
  int get hashCode {
    return [name, lensDirection].hashCode;
  }

  @override
  String toString() {
    return '$runtimeType($name, $lensDirection, $sensorOrientation)';
  }
}

/// Statistics about the streaming, bitrate, errors, drops etc.
///
/// [rttMicros] 与 [bytesSend] 依赖 RootEncoder 2.7.0+ RTMP 客户端（需开启 [setRtmpShouldSendPings] 后 RTT 才有效）。
/// [queueBytesOut] / [bytesOutPerSecond] / [queueCongestionPercent] / [totalBytesOut]
/// 依赖 RootEncoder 2.8.1+（Android）。
class StreamStatistics {
  /// Sender queue capacity in packets; null when unavailable.
  final int? cacheSize;
  final int? sentAudioFrames;
  final int? sentVideoFrames;
  final int? droppedAudioFrames;
  final int? droppedVideoFrames;
  final bool? isAudioMuted;

  /// 推流时视频是否被静音（发送黑帧），双端对齐。
  final bool? isVideoMuted;
  final int? bitrate;
  final int? width;
  final int? height;
  final int? fps;

  /// RTMP 往返时延（微秒），需 `setRtmpShouldSendPings(true)` 且推流建立后由服务端响应 ping。
  final int? rttMicros;
  final int? bytesSend;
  final int? queueBytesOut;
  final int? bytesOutPerSecond;
  final double? queueCongestionPercent;
  final int? totalBytesOut;

  StreamStatistics({
    required this.cacheSize,
    required this.sentAudioFrames,
    required this.sentVideoFrames,
    required this.droppedAudioFrames,
    required this.droppedVideoFrames,
    required this.bitrate,
    required this.width,
    required this.height,
    required this.isAudioMuted,
    this.isVideoMuted,
    this.fps,
    this.rttMicros,
    this.bytesSend,
    this.queueBytesOut,
    this.bytesOutPerSecond,
    this.queueCongestionPercent,
    this.totalBytesOut,
  });

  @override
  String toString() {
    return 'StreamStatistics{cacheSize: $cacheSize, sentAudioFrames: $sentAudioFrames, sentVideoFrames: $sentVideoFrames, droppedAudioFrames: $droppedAudioFrames, droppedVideoFrames: $droppedVideoFrames, isAudioMuted: $isAudioMuted, isVideoMuted: $isVideoMuted, bitrate: $bitrate, width: $width, height: $height, fps: $fps, rttMicros: $rttMicros, bytesSend: $bytesSend, queueBytesOut: $queueBytesOut, bytesOutPerSecond: $bytesOutPerSecond, queueCongestionPercent: $queueCongestionPercent, totalBytesOut: $totalBytesOut}';
  }
}

/// This is thrown when the plugin reports an error.
class CameraException implements Exception {
  CameraException(this.code, this.description);

  String code;
  String? description;

  @override
  String toString() => '$runtimeType($code, $description)';
}

// Build the UI texture view of the video data with textureId.
class CameraPreview extends StatelessWidget {
  const CameraPreview(this.controller, {super.key});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.value.isInitialized!) {
      Widget childView;
      if (Platform.isAndroid) {
        childView = AndroidView(
          viewType: 'hybrid-view-type',
          creationParamsCodec: const StandardMessageCodec(),
        );
      } else {
        childView = Texture(textureId: controller._textureId!);
      }

      if (controller.value.previewSize!.width <
          controller.value.previewSize!.height) {
        return RotatedBox(
          quarterTurns: controller.value.previewQuarterTurns!,
          child: childView,
        );
      } else {
        return childView;
      }
    } else {
      return Container();
    }
  }
}

/// The state of a [CameraController].
class CameraValue {
  const CameraValue({
    this.isInitialized,
    this.errorDescription,
    this.previewSize,
    this.previewQuarterTurns,
    this.isRecordingVideo,
    this.isTakingPicture,
    this.isStreaming,
    this.streamingProtocol,
    this.event,
    bool? isRecordingPaused,
    bool? isStreamingPaused,
    // Preserve the public parameter names and the private raw flags.
    // ignore: prefer_initializing_formals
  }) : _isRecordingPaused = isRecordingPaused,
       // ignore: prefer_initializing_formals
       _isStreamingPaused = isStreamingPaused;

  const CameraValue.uninitialized()
    : this(
        isInitialized: false,
        isRecordingVideo: false,
        isTakingPicture: false,
        isStreaming: false,
        streamingProtocol: null,
        isRecordingPaused: false,
        isStreamingPaused: false,
        previewQuarterTurns: 0,
        event: null,
      );

  /// True after [CameraController.initialize] has completed successfully.
  final bool? isInitialized;

  /// True when a picture capture request has been sent but as not yet returned.
  final bool? isTakingPicture;

  /// True when the camera is recording (not the same as previewing).
  final bool? isRecordingVideo;

  /// True when the camera is streaming (any [StreamingProtocol]).
  final bool? isStreaming;

  /// Current streaming protocol while [isStreaming] is true.
  final StreamingProtocol? streamingProtocol;
  final bool? _isRecordingPaused;
  final bool? _isStreamingPaused;

  /// True when camera [isRecordingVideo] and recording is paused.
  bool get isRecordingPaused => isRecordingVideo! && _isRecordingPaused!;

  /// True when camera [isRecordingVideo] and streaming is paused.
  bool get isStreamingPaused => isStreaming! && _isStreamingPaused!;

  final String? errorDescription;

  /// The size of the preview in pixels.
  ///
  /// Is `null` until  [isInitialized] is `true`.
  final Size? previewSize;

  /// The amount to rotate the preview by in quarter turns.
  ///
  /// Is `null` until  [isInitialized] is `true`.
  final int? previewQuarterTurns;

  /// Raw event info
  final dynamic event;

  /// Convenience getter for `previewSize.height / previewSize.width`.
  ///
  /// Can only be called when [initialize] is done.
  double get aspectRatio => previewSize!.height / previewSize!.width;

  CameraValue copyWith({
    bool? isInitialized,
    bool? isRecordingVideo,
    bool? isStreaming,
    StreamingProtocol? streamingProtocol,
    bool clearStreamingProtocol = false,
    bool? isTakingPicture,
    String? errorDescription,
    Size? previewSize,
    int? previewQuarterTurns,
    bool? isRecordingPaused,
    bool? isStreamingPaused,
    dynamic event,
  }) {
    return CameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      errorDescription: errorDescription,
      previewSize: previewSize ?? this.previewSize,
      previewQuarterTurns: previewQuarterTurns ?? this.previewQuarterTurns,
      isRecordingVideo: isRecordingVideo ?? this.isRecordingVideo,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingProtocol: clearStreamingProtocol
          ? null
          : (streamingProtocol ?? this.streamingProtocol),
      isTakingPicture: isTakingPicture ?? this.isTakingPicture,
      isRecordingPaused: isRecordingPaused ?? _isRecordingPaused,
      isStreamingPaused: isStreamingPaused ?? _isStreamingPaused,
      event: event,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'isRecordingVideo: $isRecordingVideo, '
        'isRecordingPaused: $isRecordingPaused, '
        'isStreamingPaused: $isStreamingPaused, '
        'isTakingPicture: $isTakingPicture, '
        'isInitialized: $isInitialized, '
        'errorDescription: $errorDescription, '
        'previewSize: $previewSize, '
        'previewQuarterTurns: $previewQuarterTurns, '
        'isStreaming: $isStreaming, '
        'streamingProtocol: $streamingProtocol)';
  }
}

/// Controls a device camera.
///
/// Use [availableCameras] to get a list of available cameras.
///
/// Before using a [CameraController] a call to [initialize] must complete.
///
/// To show the camera preview on the screen use a [CameraPreview] widget.
class CameraController extends ValueNotifier<CameraValue> {
  CameraController(
    this.resolutionPreset, {
    this.enableAudio = true,
    @Deprecated('OpenGL is always enabled.') this.androidUseOpenGL = false,
  }) : super(const CameraValue.uninitialized());

  final ResolutionPreset resolutionPreset;

  /// Whether to include audio when recording a video.
  final bool enableAudio;

  int? _textureId;
  int? _eventId;
  bool _isDisposed = false;
  StreamSubscription<dynamic>? _eventSubscription;
  Completer<void>? _creatingCompleter;
  @Deprecated('All Android pipelines use OpenGL; this flag has no effect.')
  final bool androidUseOpenGL;
  final Set<String> _destinationIds = <String>{};
  List<String> get streamingDestinationIds =>
      List.unmodifiable(_destinationIds);

  /// Query the actual native build and current camera capabilities.
  Future<StreamingCapabilities> getCapabilities() async {
    final data = await _invokeNative<Map<dynamic, dynamic>>('getCapabilities');
    return StreamingCapabilities.fromMap(data!);
  }

  Future<T?> _invokeNative<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'uninitialized',
        '$method requires initialization.',
      );
    }
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Mute encoded audio without detaching the microphone or changing tracks.
  Future<void> setAudioMuted(bool muted) => setHasAudio(!muted);

  /// Typed capture preset; applies before starting streaming/recording.
  Future<void> setCapturePreset(ResolutionPreset preset) async {
    const names = {
      'low': 'cif352x288',
      'medium': 'vga640x480',
      'high': 'hd1280x720',
      'veryHigh': 'hd1920x1080',
      'ultraHigh': 'hd4K3840x2160',
      'max': 'high',
    };
    if (value.isStreaming! || value.isRecordingVideo!) {
      throw CameraException(
        'invalidState',
        'Stop recording and streaming before changing capture presets.',
      );
    }
    await _invokeNative<void>('setCapturePreset', {
      'preset': preset.name,
      'sessionPreset': names[preset.name]!,
    });
  }

  /// Initializes the camera on the device.
  ///
  /// Throws a [CameraException] if the initialization fails.
  Future<void> initialize(CameraDescription cameraDesc) async {
    if (_creatingCompleter != null && !_creatingCompleter!.isCompleted) {
      throw CameraException(
        'Initialization in progress',
        'Wait for initialize to complete.',
      );
    }
    if (_isDisposed) {
      return Future<void>.value();
    }
    try {
      _creatingCompleter = Completer<void>();
      final Map<String, dynamic> reply = (await _channel
          .invokeMapMethod<String, dynamic>('initialize', <String, dynamic>{
            'cameraName': cameraDesc.name,
            'resolutionPreset': serializeResolutionPreset(resolutionPreset),
            'enableAudio': enableAudio,
          }))!;
      if (_isDisposed) {
        _creatingCompleter!.complete();
        return;
      }
      _textureId = reply['textureId'];
      _eventId = reply['eventId'];
      value = value.copyWith(
        isInitialized: true,
        previewSize: Size(
          reply['previewWidth'].toDouble(),
          reply['previewHeight'].toDouble(),
        ),
        previewQuarterTurns: reply['previewQuarterTurns'],
      );
    } on PlatformException catch (e) {
      _creatingCompleter!.complete();
      _creatingCompleter = null;
      throw CameraException(e.code, e.message);
    } catch (_) {
      _creatingCompleter!.complete();
      _creatingCompleter = null;
      rethrow;
    }
    await _eventSubscription?.cancel();
    _eventSubscription = EventChannel(
      'com.rtmp_streaming.eventchannel/$_eventId',
    ).receiveBroadcastStream().listen(_listener);
    _creatingCompleter!.complete();
    return _creatingCompleter!.future;
  }

  /// Prepare the capture session for video streaming.
  ///
  /// Use of this method is optional, but it may be called for performance
  /// reasons on iOS.
  ///
  /// Preparing audio can cause a minor delay in the CameraPreview view on iOS.
  /// If video streaming is intended, calling this early eliminates this delay
  /// that would otherwise be experienced when video streaming is started.
  /// This operation is a no-op on Android.
  ///
  /// Throws a [CameraException] if the prepare fails.
  @Deprecated('initialize already prepares capture; no warmup call is needed.')
  Future<void> prepareForVideoStreaming() async {
    await _channel.invokeMethod<void>('prepareForVideoStreaming');
  }

  /// Listen to events from the native plugins.
  ///
  /// A "cameraClosing" event is sent when the camera is closed automatically by the system (for example when the app go to background). The plugin will try to reopen the camera automatically but any ongoing recording will end.
  void _listener(dynamic event) {
    final Map<dynamic, dynamic>? map = event;
    if (_isDisposed || event == null) {
      return;
    }

    // Android: Event {eventType: rtmp_retry, errorDescription: BadName received}
    // iOS: Event {event: rtmp_retry, errorDescription: connection failed rtmpStatus}
    final String? eventType =
        map?['eventType'] as String? ?? map?['event'] as String?;
    final String? errorDescription = map?['errorDescription'];
    final Map<String, dynamic> uniEvent = <String, dynamic>{
      'eventType': eventType,
      'errorDescription': errorDescription,
      if (map?['destinationId'] != null || map?['streamId'] != null)
        'destinationId': map?['destinationId'] ?? map?['streamId'],
      if (map?['captureStatistics'] != null)
        'captureStatistics': map!['captureStatistics'],
    };
    switch (eventType) {
      case 'error':
        value = value.copyWith(
          errorDescription: errorDescription,
          event: uniEvent,
        );
        break;
      case 'recording_stopped':
        value = value.copyWith(
          isRecordingVideo: false,
          isRecordingPaused: false,
          errorDescription: errorDescription,
          event: uniEvent,
        );
        break;
      case 'camera_closing':
        value = value.copyWith(
          errorDescription: errorDescription,
          isRecordingVideo: false,
          isStreaming: false,
          clearStreamingProtocol: true,
          event: uniEvent,
        );
        break;
      case 'rtmp_retry':
        value = value.copyWith(
          errorDescription: errorDescription,
          event: uniEvent,
        );
        break;
      case 'destination_stopped':
        final id = uniEvent['destinationId'];
        _destinationIds.remove(id);
        value = value.copyWith(event: uniEvent);
        break;
      case 'rtmp_stopped':
        final destinationId = uniEvent['destinationId'];
        if (destinationId != null) {
          _destinationIds.remove(destinationId);
          if (_destinationIds.isNotEmpty) {
            value = value.copyWith(event: uniEvent);
            break;
          }
        } else {
          _destinationIds.clear();
        }
        value = value.copyWith(
          errorDescription: errorDescription,
          isStreaming: false,
          clearStreamingProtocol: true,
          event: uniEvent,
        );
        break;
      case 'success':
        value = value.copyWith(
          errorDescription: errorDescription,
          isStreaming: true,
          isStreamingPaused: false,
          event: uniEvent,
        );
        break;
      case 'wait':
        value = value.copyWith(
          errorDescription: errorDescription,
          event: uniEvent,
        );
        break;
      default:
        value = value.copyWith(
          errorDescription: errorDescription,
          event: uniEvent,
        );
        break;
    }
  }

  /// Captures an image and saves it to [path].
  ///
  /// A path can for example be obtained using
  /// [path_provider](https://pub.dartlang.org/packages/path_provider).
  ///
  /// If a file already exists at the provided path an error will be thrown.
  /// The file can be read as this function returns.
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> takePicture(String path) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'takePicture was called on uninitialized CameraController',
      );
    }
    if (value.isTakingPicture!) {
      throw CameraException(
        'Previous capture has not returned yet.',
        'takePicture was called before the previous capture returned.',
      );
    }
    try {
      value = value.copyWith(isTakingPicture: true);
      await _channel.invokeMethod<void>('takePicture', <String, dynamic>{
        'path': path,
      });
      value = value.copyWith(isTakingPicture: false);
    } on PlatformException catch (e) {
      value = value.copyWith(isTakingPicture: false);
      throw CameraException(e.code, e.message);
    }
  }

  /// Apply a named Android GPU effect. Media effects require a local file.
  Future<void> setVideoEffect(VideoEffect effect, {String? filePath}) {
    const ids = <VideoEffect, int>{
      VideoEffect.deformation: 0,
      VideoEffect.beauty: 1,
      VideoEffect.black: 2,
      VideoEffect.blur: 3,
      VideoEffect.brightness: 4,
      VideoEffect.cartoon: 5,
      VideoEffect.chroma: 6,
      VideoEffect.chromaticAberration: 7,
      VideoEffect.circle: 8,
      VideoEffect.color: 9,
      VideoEffect.contrast: 10,
      VideoEffect.crop: 11,
      VideoEffect.distortedTv: 12,
      VideoEffect.duotone: 13,
      VideoEffect.earlyBird: 14,
      VideoEffect.edgeDetection: 15,
      VideoEffect.exposure: 16,
      VideoEffect.fire: 17,
      VideoEffect.gamma: 18,
      VideoEffect.glitch: 19,
      VideoEffect.gif: 20,
      VideoEffect.greyScale: 21,
      VideoEffect.halftoneLines: 22,
      VideoEffect.image70s: 24,
      VideoEffect.lamoish: 25,
      VideoEffect.money: 26,
      VideoEffect.negative: 27,
      VideoEffect.noise: 28,
      VideoEffect.pixelated: 29,
      VideoEffect.polygonization: 30,
      VideoEffect.rainbow: 31,
      VideoEffect.rgbSaturation: 32,
      VideoEffect.ripple: 33,
      VideoEffect.rotation: 34,
      VideoEffect.saturation: 35,
      VideoEffect.sepia: 36,
      VideoEffect.sharpness: 37,
      VideoEffect.snow: 38,
      VideoEffect.video: 39,
      VideoEffect.temperature: 40,
      VideoEffect.zebra: 42,
      VideoEffect.sobel: 43,
    };
    if (!Platform.isAndroid) {
      throw CameraException(
        'unsupportedOperation',
        'GPU effects require Android.',
      );
    }
    return _invokeNative<void>('setFilter', {
      'type': ids[effect]!,
      'filePath': filePath,
    });
  }

  /// The set filter
  ///
  /// Android 滤镜类型包含：`15` 边缘检测（性能模式）、`43` 边缘检测 Sobel 高质量（RootEncoder 2.7.0+）等，详见原生 [CameraNativeView]。
  ///
  /// Throws a [CameraException] if the capture fails.
  @Deprecated('Use setVideoEffect or parameterized overlay methods.')
  Future<void> setFilter(int type, {String? filePath}) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setFilter was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setFilter supported android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setFilter', <String, dynamic>{
        'type': type,
        'filePath': filePath,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 使用 BT.709 色彩矩阵编码视频（RootEncoder 2.7.0+，仅 Android）。
  ///
  /// 可在空闲预览时调用，配置于下次推流或录制的编码器准备前应用。
  /// 推流或录制中不能修改；重复设置相同值安全返回。
  Future<void> setForceBt709Color(bool enabled) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setForceBt709Color was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setForceBt709Color is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setForceBt709Color', <String, dynamic>{
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 启用 RTMP 周期 ping，用于测量往返时延（RootEncoder 2.7.0+，仅 Android）。
  ///
  /// 须在 [startVideoStreaming] 之前调用；[getStreamStatistics] 中的 [StreamStatistics.rttMicros] 依赖此项。
  Future<void> setRtmpShouldSendPings(bool enabled) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setRtmpShouldSendPings was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setRtmpShouldSendPings is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setRtmpShouldSendPings',
        <String, dynamic>{'enabled': enabled},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  Future<T?> _invokeAndroid<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        '$method requires an initialized controller.',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        '$method requires Android.',
      );
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set extra RTMP metadata before streaming. Values are strings, booleans,
  /// or finite numbers. An empty map clears previously configured metadata.
  /// Applies to single and multiple RTMP destinations on Android.
  Future<void> setRtmpMetadata(Map<String, Object> metadata) async {
    if (metadata.entries.any(
      (entry) =>
          entry.key.trim().isEmpty ||
          !(entry.value is String ||
              entry.value is bool ||
              (entry.value is num && (entry.value as num).isFinite)),
    )) {
      throw ArgumentError(
        'Metadata requires nonempty keys and finite scalar values.',
      );
    }
    await _invokeAndroid<void>('setRtmpMetadata', {'metadata': metadata});
  }

  /// Request an encoder keyframe while streaming or recording on Android.
  Future<void> requestKeyFrame() async =>
      _invokeAndroid<void>('requestKeyFrame');

  /// Set manual ISO and exposure duration in nanoseconds. Android requires
  /// Camera2; iOS requires a device with custom exposure support. Values must
  /// fit the sensor ranges. Omit both to restore automatic exposure.
  Future<void> setManualExposure({int? iso, int? exposureTimeNanos}) async {
    if ((iso == null) != (exposureTimeNanos == null) ||
        (iso != null && iso <= 0) ||
        (exposureTimeNanos != null && exposureTimeNanos <= 0)) {
      throw ArgumentError(
        'Provide positive ISO and exposure time together, or omit both.',
      );
    }
    await _invokeNative<void>('setManualExposure', {
      'iso': iso,
      'exposureTimeNanos': exposureTimeNanos,
    });
  }

  /// Opt into capture telemetry through [CameraValue.event].
  /// Events have `eventType: capture_statistics` and a `captureStatistics` map
  /// containing available ISO, exposure time, sensor timestamp, focus distance,
  /// and AF/AE/AWB states. [intervalMs] must be >= 100; disabled by default.
  Future<void> setCaptureTelemetry(
    bool enabled, {
    int intervalMs = 1000,
  }) async {
    if (intervalMs < 100) throw ArgumentError.value(intervalMs, 'intervalMs');
    await _invokeNative<void>('setCaptureTelemetry', {
      'enabled': enabled,
      'intervalMs': intervalMs,
    });
  }

  /// Read controls from the active Camera2/CameraX or iOS capture device.
  /// Screen, UVC and Android multi streaming do not expose these controls.
  Future<CameraControls> getCameraControls() async {
    final data = await _invokeNative<Map<dynamic, dynamic>>(
      'getCameraControls',
    );
    if (data == null) {
      throw CameraException('CameraError', 'No camera controls returned.');
    }
    return CameraControls.fromMap(Map<String, dynamic>.from(data));
  }

  /// Set zoom within the range returned by [getCameraControls] (Android).
  Future<void> setZoom(double zoom) async {
    if (!zoom.isFinite || zoom <= 0) throw ArgumentError.value(zoom, 'zoom');
    await _invokeNative<void>('setZoom', {'zoom': zoom});
  }

  /// Enable or disable autofocus on the active Camera2/CameraX source (Android).
  Future<void> setAutoFocus(bool enabled) async =>
      _invokeNative<void>('setAutoFocus', {'enabled': enabled});

  /// Focus at normalized preview coordinates on Android; returns false when unavailable.
  Future<bool> tapToFocus({double x = 0.5, double y = 0.5}) async {
    if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
      throw ArgumentError('Focus coordinates must be between 0 and 1.');
    }
    return await _invokeNative<bool>('tapToFocus', {'x': x, 'y': y}) ?? false;
  }

  /// The remove filter
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> clearVideoEffect() => _invokeAndroid<void>('removeFilter');

  Future<void> removeFilter(int type) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'removeFilter was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'removeFilter supported android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('removeFilter', <String, dynamic>{
        'type': type,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Apply RootEncoder PitchShiftEffect to microphone PCM (Android only).
  ///
  /// [pitch] must be finite and between `0.5…3.0`. Pass `1.0` to disable
  /// (identity / NoAudioEffect). Prefer calling while preview or streaming is active.
  Future<void> setPitchShift(double pitch) async {
    if (!pitch.isFinite || pitch < 0.5 || pitch > 3.0) {
      throw ArgumentError.value(pitch, 'pitch');
    }
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setPitchShift was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setPitchShift is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setPitchShift', <String, dynamic>{
        'pitch': pitch,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Draw text overlay on the stream (Android GL object filter / iOS ScreenObject).
  ///
  /// [fontSize] is the text size in output pixels (1–1024).
  /// [scale] is a percentage of natural size (`100` = 1:1 pixels, default).
  Future<void> setOverlayText({
    required String text,
    double fontSize = 22,
    int colorArgb = 0xFFFF0000,
    OverlayPosition position = OverlayPosition.center,
    double scale = 100,
  }) async {
    if (!scale.isFinite) throw ArgumentError.value(scale, 'scale');
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setOverlayText was called on uninitialized CameraController',
      );
    }
    if (text.isEmpty ||
        !fontSize.isFinite ||
        fontSize <= 0 ||
        fontSize > 1024) {
      throw ArgumentError(
        'Text must be nonempty and font size must be within 1–1024 pixels.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setOverlayText', <String, dynamic>{
        'text': text,
        'fontSize': fontSize,
        'colorArgb': colorArgb,
        'position': serializeOverlayPosition(position),
        'scale': scale,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Draw an image overlay from [filePath] on the stream.
  ///
  /// [scale] is a percentage of natural image size (`100` = 1:1 pixels).
  Future<void> setOverlayImage({
    required String filePath,
    OverlayPosition position = OverlayPosition.bottomRight,
    double scale = 100,
  }) async {
    if (!scale.isFinite) throw ArgumentError.value(scale, 'scale');
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setOverlayImage was called on uninitialized CameraController',
      );
    }
    if (filePath.isEmpty) throw ArgumentError.value(filePath, 'filePath');
    try {
      await _channel.invokeMethod<void>('setOverlayImage', <String, dynamic>{
        'filePath': filePath,
        'position': serializeOverlayPosition(position),
        'scale': scale,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Remove text/image overlay previously set via [setOverlayText]/[setOverlayImage].
  Future<void> clearOverlay() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'clearOverlay was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('clearOverlay');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Lock Camera2 auto-exposure at the current value (Android only).
  ///
  /// Must be called after preview or streaming has started. Returns whether
  /// the lock succeeded (device may not support AE lock).
  Future<bool> lockExposure() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'lockExposure was called on uninitialized CameraController',
      );
    }
    try {
      final locked = await _channel.invokeMethod<bool>('lockExposure');
      return locked ?? false;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Unlock Camera2 auto-exposure (Android only).
  Future<void> unlockExposure() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'unlockExposure was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('unlockExposure');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Whether Camera2 exposure lock is currently enabled (Android only).
  Future<bool> isExposureLocked() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'isExposureLocked was called on uninitialized CameraController',
      );
    }
    try {
      final locked = await _channel.invokeMethod<bool>('isExposureLocked');
      return locked ?? false;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set video codec (Android / RootEncoder 2.8.1+). Call before streaming.
  Future<void> setVideoCodec(VideoCodecType codec) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setVideoCodec was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setVideoCodec', <String, dynamic>{
        'name': serializeVideoCodecType(codec),
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set audio codec (Android / RootEncoder 2.8.1+). Call before streaming.
  Future<void> setAudioCodec(AudioCodecType codec) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setAudioCodec was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setAudioCodec', <String, dynamic>{
        'name': serializeAudioCodecType(codec),
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Configure acoustic echo cancel / noise suppress for mic prepare (Android).
  Future<void> setAudioProcessing({
    bool? echoCanceler,
    bool? noiseSuppressor,
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setAudioProcessing was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setAudioProcessing is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setAudioProcessing', <String, dynamic>{
        'echoCanceler': ?echoCanceler,
        'noiseSuppressor': ?noiseSuppressor,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Lock Camera2 white balance at the current value (Android only).
  Future<bool> lockWhiteBalance() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'lockWhiteBalance was called on uninitialized CameraController',
      );
    }
    try {
      final locked = await _channel.invokeMethod<bool>('lockWhiteBalance');
      return locked ?? false;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Unlock Camera2 white balance (Android only).
  Future<void> unlockWhiteBalance() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'unlockWhiteBalance was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('unlockWhiteBalance');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Whether Camera2 white balance lock is currently enabled (Android only).
  Future<bool> isWhiteBalanceLocked() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'isWhiteBalanceLocked was called on uninitialized CameraController',
      );
    }
    try {
      final locked = await _channel.invokeMethod<bool>('isWhiteBalanceLocked');
      return locked ?? false;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Tap-to-meter at normalized preview coords (Android only).
  ///
  /// [mode] is `exposure` (default) or `whitebalance` / `wb`.
  Future<bool> tapToMeter({
    double x = 0.5,
    double y = 0.5,
    String mode = 'exposure',
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'tapToMeter was called on uninitialized CameraController',
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>(
        'tapToMeter',
        <String, dynamic>{'x': x, 'y': y, 'mode': mode},
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Switch video source mode (Android / RootEncoder 2.8.1+).
  ///
  /// Applied on the next stream start, or immediately when a StreamBase preview
  /// or streaming session (Camera2 / CameraX / UVC / screen / WHIP) is active.
  ///
  /// On stream start, [VideoSourceType.camera2] and [VideoSourceType.cameraX] re-apply the
  /// current camera facing (front/back). UVC and screen have no lens facing.
  /// Android idle preview uses CameraX by default and returns to the selected
  /// camera source after stop (UVC/screen return to a camera preview). The preview session is recreated when streaming
  /// starts or stops. Not combined with [startMultiStreaming] (MultiCamera2
  /// is camera2-only). For [VideoSourceType.screen], call [requestScreenCapture]
  /// first ([CameraPreview] must be mounted).
  Future<void> setVideoSource(VideoSourceType source) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'setVideoSource was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'setVideoSource is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setVideoSource', <String, dynamic>{
        'mode': serializeVideoSourceType(source),
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Use BufferAudioSource instead of mic (Android). Then feed PCM via [feedPcmAudio].
  ///
  /// If a GenericCamera2 stream is already live, enabling buffer audio migrates
  /// that session onto the StreamBase path (same URL) so PCM input can attach.
  Future<void> enableBufferAudio(bool enable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'enableBufferAudio was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'enableBufferAudio is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('enableBufferAudio', <String, dynamic>{
        'enable': enable,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Push PCM samples into BufferAudioSource (Android). Requires [enableBufferAudio].
  /// Push PCM samples into [BufferAudioSource] (Android).
  ///
  /// Expects 16-bit little-endian PCM matching the prepare audio config
  /// (default 32 kHz stereo). Call [enableBufferAudio] first.
  Future<void> feedPcmAudio(Uint8List bytes) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'feedPcmAudio was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'feedPcmAudio is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('feedPcmAudio', <String, dynamic>{
        'bytes': bytes,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Request MediaProjection permission for screen capture (Android only).
  ///
  /// Request MediaProjection permission (Android). Mount [CameraPreview] first.
  /// On success, call [setVideoSource] with [VideoSourceType.screen].
  Future<void> requestScreenCapture() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController.',
        'requestScreenCapture was called on uninitialized CameraController',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'requestScreenCapture is only supported on Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>('requestScreenCapture');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Get statistics about the rtmp stream.
  ///
  /// Throws a [CameraException] if image streaming was not started.
  Future<StreamStatistics> getStreamStatistics() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopImageStream was called on uninitialized CameraController.',
      );
    }
    if (!value.isStreaming!) {
      throw CameraException(
        'No camera is streaming images',
        'stopImageStream was called when no camera is streaming images.',
      );
    }

    try {
      var data = (await _channel.invokeMapMethod<String, dynamic>(
        'getStreamStatistics',
      ))!;
      return StreamStatistics(
        sentAudioFrames: (data["sentAudioFrames"] as num?)?.toInt(),
        sentVideoFrames: (data["sentVideoFrames"] as num?)?.toInt(),
        height: (data["height"] as num?)?.toInt(),
        width: (data["width"] as num?)?.toInt(),
        bitrate: (data["bitrate"] as num?)?.toInt(),
        isAudioMuted: data["isAudioMuted"] as bool?,
        isVideoMuted: data["isVideoMuted"] as bool?,
        cacheSize: (data["cacheSize"] as num?)?.toInt(),
        droppedAudioFrames: (data["droppedAudioFrames"] as num?)?.toInt(),
        droppedVideoFrames: (data["droppedVideoFrames"] as num?)?.toInt(),
        fps: (data["fps"] as num?)?.toInt(),
        rttMicros: (data["rttMicros"] as num?)?.toInt(),
        bytesSend: (data["bytesSend"] as num?)?.toInt(),
        queueBytesOut: (data["queueBytesOut"] as num?)?.toInt(),
        bytesOutPerSecond: (data["bytesOutPerSecond"] as num?)?.toInt(),
        queueCongestionPercent: (data["queueCongestionPercent"] as num?)
            ?.toDouble(),
        totalBytesOut: (data["totalBytesOut"] as num?)?.toInt(),
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start a video recording and save the file to [path].
  ///
  /// A path can for example be obtained using
  /// [path_provider](https://pub.dartlang.org/packages/path_provider).
  ///
  /// The file is written on the flight as the video is being recorded.
  /// If a file already exists at the provided path an error will be thrown.
  /// The file can be read as soon as [stopVideoRecording] returns.
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> startVideoRecording(String filePath) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startVideoRecording was called on uninitialized CameraController',
      );
    }
    if (value.isRecordingVideo!) {
      throw CameraException(
        'A video recording is already started.',
        'startVideoRecording was called when a recording is already started.',
      );
    }

    try {
      await _channel.invokeMethod<void>(
        'startVideoRecording',
        <String, dynamic>{'filePath': filePath},
      );
      value = value.copyWith(isRecordingVideo: true, isRecordingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop recording while leaving any active stream running.
  Future<void> stopVideoRecording() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopRecording was called on uninitialized CameraController',
      );
    }
    if (!value.isRecordingVideo!) {
      throw CameraException(
        'No video is recording',
        'stopRecording was called when no video is recording.',
      );
    }
    try {
      await _channel.invokeMethod<void>('stopRecording', <String, dynamic>{});
      value = value.copyWith(isRecordingVideo: false, isRecordingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Pause video recording.
  /// Only supports Android
  /// Check `recordingPause` in getCapabilities before using this method.
  Future<void> pauseVideoRecording() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'pauseVideoRecording was called on uninitialized CameraController',
      );
    }
    if (!value.isRecordingVideo!) {
      throw CameraException(
        'No video is recording',
        'pauseVideoRecording was called when no video is recording.',
      );
    }
    if (value.isRecordingPaused) {
      throw CameraException(
        'No video is pause',
        'pauseVideoRecording was called when no video is recording.',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'pauseVideoRecording Only supports Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'pauseVideoRecording',
        <String, dynamic>{},
      );
      value = value.copyWith(isRecordingPaused: true);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Resume video recording after pausing.
  /// Only supports Android
  /// Check `recordingPause` in getCapabilities before using this method.
  Future<void> resumeVideoRecording() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'resumeVideoRecording was called on uninitialized CameraController',
      );
    }
    if (!value.isRecordingVideo!) {
      throw CameraException(
        'No video is recording',
        'resumeVideoRecording was called when no video is recording.',
      );
    }
    if (!value.isRecordingPaused) {
      throw CameraException(
        'No video is resume',
        'resumeVideoRecording was called when no video is recording.',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Unsupported platforms.',
        'resumeVideoRecording Only supports Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'resumeVideoRecording',
        <String, dynamic>{},
      );
      value = value.copyWith(isRecordingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start recording to [filePath] and streaming to [url] with [protocol].
  ///
  /// Throws a [CameraException] if the capture fails or the protocol is
  /// unsupported on this platform.
  Future<void> startVideoRecordingAndStreaming(
    String filePath,
    String url, {
    StreamingProtocol protocol = StreamingProtocol.rtmp,
    int bitrate = 1200 * 1024,
    @Deprecated('OpenGL is always enabled.') bool? androidUseOpenGL,
    String? whipToken,
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startVideoStreaming was called on uninitialized CameraController',
      );
    }

    if (value.isRecordingVideo!) {
      throw CameraException(
        'A video recording is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }
    if (value.isStreaming!) {
      throw CameraException(
        'A video streaming is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }
    await _ensurePublishingProtocolSupported(protocol);

    try {
      await _channel.invokeMethod<void>(
        'startVideoRecordingAndStreaming',
        <String, dynamic>{
          'url': url,
          'filePath': filePath,
          'bitrate': bitrate,
          'protocol': serializeStreamingProtocol(protocol),
          'whipToken': ?whipToken,
        },
      );
      value = value.copyWith(
        isStreaming: true,
        streamingProtocol: protocol,
        isStreamingPaused: false,
        isRecordingVideo: true,
        isRecordingPaused: false,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start streaming to [url] using [protocol].
  ///
  /// Defaults to [StreamingProtocol.rtmp].
  ///
  /// iOS supports [StreamingProtocol.rtmp], [StreamingProtocol.srt],
  /// and [StreamingProtocol.whip]. WHEP playback uses [PlayerController].
  /// Android supports [StreamingProtocol.rtmp], [StreamingProtocol.rtsp],
  /// [StreamingProtocol.srt], [StreamingProtocol.udp], and [StreamingProtocol.whip].
  ///
  /// Throws a [CameraException] if the capture fails or the protocol is
  /// unsupported on this platform.
  Future<void> startVideoStreaming(
    String url, {
    StreamingProtocol protocol = StreamingProtocol.rtmp,
    int bitrate = 1200 * 1024,
    @Deprecated('OpenGL is always enabled.') bool? androidUseOpenGL,
    String? whipToken,
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startVideoStreaming was called on uninitialized CameraController',
      );
    }
    if (value.isRecordingVideo!) {
      throw CameraException(
        'A video recording is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }
    if (value.isStreaming!) {
      throw CameraException(
        'A video streaming is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }
    if (protocol == StreamingProtocol.whep) {
      throw CameraException(
        'unsupportedOperation',
        'Use PlayerController for WHEP playback.',
      );
    }
    await _ensurePublishingProtocolSupported(protocol);

    try {
      await _channel
          .invokeMethod<void>('startVideoStreaming', <String, dynamic>{
            'url': url,
            'bitrate': bitrate,
            'protocol': serializeStreamingProtocol(protocol),
            'whipToken': ?whipToken,
          });
      value = value.copyWith(
        isStreaming: true,
        streamingProtocol: protocol,
        isStreamingPaused: false,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  Future<void> _ensurePublishingProtocolSupported(
    StreamingProtocol protocol,
  ) async {
    if (protocol == StreamingProtocol.whep) {
      throw CameraException(
        'unsupportedOperation',
        'Use PlayerController for WHEP playback.',
      );
    }
    final capabilities = await getCapabilities();
    if (!capabilities.supportsProtocol(protocol)) {
      throw CameraException(
        'unsupportedProtocol',
        '${protocol.name} is unavailable in this native build.',
      );
    }
  }

  /// Start streaming to multiple destinations at once (iOS / Android; excludes WHIP/WHEP).
  Future<void> startMultiStreaming(
    List<StreamDestination> destinations, {
    int bitrate = 1200 * 1024,
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startMultiStreaming was called on uninitialized CameraController',
      );
    }
    if (destinations.isEmpty) {
      throw CameraException(
        'invalidArgument',
        'startMultiStreaming requires at least one destination.',
      );
    }
    if (value.isStreaming! || value.isRecordingVideo!) {
      throw CameraException(
        'A video streaming is already started.',
        'stop existing streaming before startMultiStreaming.',
      );
    }
    final capabilities = await getCapabilities();
    for (final d in destinations) {
      if (!capabilities.supportsProtocol(d.protocol) ||
          d.protocol == StreamingProtocol.whip ||
          d.protocol == StreamingProtocol.whep) {
        throw CameraException(
          'unsupportedProtocol',
          '${d.protocol.name} is not available for multi streaming.',
        );
      }
    }
    final normalized = <StreamDestination>[];
    final ids = <String>{};
    for (var i = 0; i < destinations.length; i++) {
      final d = destinations[i];
      final id = d.id ?? 'dest_$i';
      if (id.isEmpty || !ids.add(id)) {
        throw ArgumentError('Destination IDs must be nonempty and unique.');
      }
      normalized.add(
        StreamDestination(url: d.url, protocol: d.protocol, id: id),
      );
    }
    _destinationIds
      ..clear()
      ..addAll(ids);
    try {
      await _channel
          .invokeMethod<void>('startMultiStreaming', <String, dynamic>{
            'bitrate': bitrate,
            'destinations': normalized.map((d) => d.toMap()).toList(),
          });
      value = value.copyWith(
        isStreaming: true,
        streamingProtocol: destinations.first.protocol,
        isStreamingPaused: false,
      );
    } on PlatformException catch (e) {
      _destinationIds.clear();
      value = value.copyWith(isStreaming: false, clearStreamingProtocol: true);
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop one destination previously started via [startMultiStreaming].
  Future<void> stopStreamingDestination(String id) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopStreamingDestination was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'stopStreamingDestination',
        <String, dynamic>{'id': id},
      );
      _destinationIds.remove(id);
      if (_destinationIds.isEmpty) {
        value = value.copyWith(
          isStreaming: false,
          isStreamingPaused: false,
          clearStreamingProtocol: true,
        );
      }
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop all destinations started via [startMultiStreaming].
  Future<void> stopMultiStreaming() => stopVideoStreaming();

  /// Stop streaming.
  Future<void> stopVideoStreaming() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopVideoStreaming was called on uninitialized CameraController',
      );
    }
    if (!value.isStreaming!) return;
    try {
      await _channel.invokeMethod<void>('stopStreaming', <String, dynamic>{});
      _destinationIds.clear();
      value = value.copyWith(
        isStreaming: false,
        isStreamingPaused: false,
        clearStreamingProtocol: true,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop streaming and Recording.
  Future<void> stopRecordingOrStreaming() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopRecordingOrStreaming was called on uninitialized CameraController',
      );
    }
    if (!value.isStreaming! && !value.isRecordingVideo!) return;
    try {
      await _channel.invokeMethod<void>(
        'stopRecordingOrStreaming',
        <String, dynamic>{},
      );
      value = value.copyWith(
        isStreaming: false,
        isRecordingVideo: false,
        isRecordingPaused: false,
        isStreamingPaused: false,
        clearStreamingProtocol: true,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// switch Camera[cameraId`].
  ///
  /// This switch Camera to the camera with the given [cameraId].
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> switchCamera(String cameraId) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'switchCamera was called on uninitialized CameraController',
      );
    }

    try {
      await _channel.invokeMethod<void>('switchCamera', <String, dynamic>{
        'cameraName': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Legacy audio enable alias. Both platforms mute without detaching capture.
  @Deprecated('Use setAudioMuted; this does not detach the microphone.')
  Future<void> switchAudio(bool isEnable) => setAudioMuted(!isEnable);

  /// switch Flash Light
  ///
  /// This switch Flash Light
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> switchFlashLight(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startVideoStreaming was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('switchFlashLight', <String, dynamic>{
        'isEnable': isEnable,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Pause video stream play.
  /// Only supports ios
  Future<void> pauseVideoStreamPlay() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'pauseVideoStream was called on uninitialized CameraController',
      );
    }
    if (!value.isStreaming!) {
      throw CameraException(
        'No video is Streaming',
        'pauseVideoStream was called when no video is Streaming.',
      );
    }
    if (value.isStreamingPaused) {
      throw CameraException(
        'No video is Paused',
        'pauseVideoStream was called when no video is Streaming.',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'pauseVideoStream Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>('pauseStream', <String, dynamic>{});
      value = value.copyWith(isStreamingPaused: true);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// resume video stream play.
  /// Only supports ios
  Future<void> resumeVideoStreamPlay() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'resumeVideoStream was called on uninitialized CameraController',
      );
    }
    if (!value.isStreaming!) {
      throw CameraException(
        'No video is Streaming',
        'resumeVideoStream was called when no video is Streaming.',
      );
    }
    if (!value.isStreamingPaused) {
      throw CameraException(
        'No video is resume',
        'resumeVideoStream was called when no video is Streaming.',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'resumeVideoStream Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>('resumeStream', <String, dynamic>{});
      value = value.copyWith(isStreamingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 设置音频编码码率（bps）。须在开始推流/录制前调用；推流中修改需两端原生库支持热更新。
  Future<void> setAudioSettings(int bitrate) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setAudioSettings was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setAudioSettings', <String, dynamic>{
        "bitrate": bitrate,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 设置视频编码参数。
  ///
  /// [expectedFrameRate]：HaishinKit 2.2.2+，写入编码期望帧率并进入 RTMP onMetaData 的 `framerate`（仅 iOS）。
  ///
  /// [bitRateMode]：`average`（默认）、`constant`（iOS 16+）、`variable`（iOS 26+）。
  ///
  /// Android：推流中可通过 [bitrate] 调用 `setVideoBitrateOnFly` 热更新码率。
  /// Android applies width/height and keyframe interval (seconds) on the next
  /// stream or recording session. Bitrate can also change during streaming.
  Future<void> setVideoSettings({
    int? bitrate,
    int? width,
    int? height,
    int? frameInterval,
    String? profileLevel,
    double? expectedFrameRate,
    String? bitRateMode,
  }) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setVideoSettings was called on uninitialized CameraController',
      );
    }
    if ((width == null) != (height == null) ||
        (width != null &&
            (width <= 0 || height! <= 0 || width.isOdd || height.isOdd)) ||
        (bitrate != null && bitrate <= 0) ||
        (frameInterval != null && frameInterval <= 0) ||
        (expectedFrameRate != null &&
            (!expectedFrameRate.isFinite || expectedFrameRate <= 0))) {
      throw ArgumentError(
        'Invalid encoder dimensions, bitrate, interval or frame rate.',
      );
    }
    if (bitRateMode != null &&
        !{'average', 'constant', 'variable'}.contains(bitRateMode)) {
      throw ArgumentError.value(bitRateMode, 'bitRateMode');
    }
    if (Platform.isAndroid && (profileLevel != null || bitRateMode != null)) {
      throw CameraException(
        'unsupportedOperation',
        'Android does not expose profileLevel or this bitRateMode.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setVideoSettings', <String, dynamic>{
        "bitrate": bitrate,
        "width": width,
        "height": height,
        "frameInterval": frameInterval,
        if (!Platform.isAndroid) "profileLevel": profileLevel,
        "expectedFrameRate": ?expectedFrameRate,
        "bitRateMode": ?bitRateMode,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 多任务/分屏时保持相机采集（HaishinKit 2.2.5+，底层 `AVCaptureSession.isMultitaskingCameraAccessEnabled`）。
  ///
  /// 需要 iOS 17+ 且设备支持；宜在 [initialize] 之后、[startVideoStreaming] 之前调用。
  Future<void> setMultitaskingCameraAccessEnabled(bool enabled) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setMultitaskingCameraAccessEnabled was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setMultitaskingCameraAccessEnabled is only supported on iOS.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setMultitaskingCameraAccessEnabled',
        <String, dynamic>{'enabled': enabled},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 推流时是否正在发送音频（false 表示已静音）。
  Future<bool?> getHasAudio() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'getHasAudio was called on uninitialized CameraController',
      );
    }
    try {
      return await _channel.invokeMethod<bool>(
        'getHasAudio',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Control encoded audio mute without detaching the microphone.
  Future<void> setHasAudio(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setHasAudio was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setHasAudio', <String, dynamic>{
        "isEnable": isEnable,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 推流时是否正在发送视频（false 表示已静音/黑帧）。
  Future<bool?> getHasVideo() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'getHasVideo was called on uninitialized CameraController',
      );
    }
    try {
      return await _channel.invokeMethod<bool>(
        'getHasVideo',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 推流时临时停止/恢复发送视频（Android 发送黑帧，iOS 混音静音）。
  Future<void> setHasVideo(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setHasVideo was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setHasVideo', <String, dynamic>{
        "isEnable": isEnable,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 设置采集/编码目标帧率。宜在 [initialize] 之后、开始推流前调用。
  Future<void> setFrameRate(int frameRate) async {
    if (frameRate <= 0) throw ArgumentError.value(frameRate, 'frameRate');
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setFrameRate was called on uninitialized CameraController',
      );
    }
    try {
      await _channel.invokeMethod<void>('setFrameRate', <String, dynamic>{
        "frameRate": frameRate,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Session Preset
  /// Only supports ios
  @Deprecated('Use setCapturePreset with ResolutionPreset.')
  Future<void> setSessionPreset(String sessionPreset) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setSessionPreset was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setSessionPreset Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setSessionPreset', <String, dynamic>{
        "sessionPreset": sessionPreset,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Screen Settings
  /// Only supports ios
  Future<void> setOverlayCanvas(int width, int height) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Canvas dimensions must be positive.');
    }
    await _invokeNative<void>('setScreenSettings', {
      'width': width,
      'height': height,
    });
  }

  @Deprecated('Use setOverlayCanvas; this does not capture the screen.')
  Future<void> setScreenSettings(int width, int height) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setScreenSettings was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setScreenSettings Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>('setScreenSettings', <String, dynamic>{
        "width": width,
        "height": height,
      });
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Releases the resources of this camera.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    // Update state so UI reflects streaming/recording stopped before native dispose
    value = value.copyWith(isStreaming: false, isRecordingVideo: false);
    notifyListeners();
    super.dispose();
    if (_creatingCompleter != null) {
      await _creatingCompleter!.future;
      await _channel.invokeMethod<void>('dispose', <String, dynamic>{});
      await _eventSubscription?.cancel();
    }
  }
}

/// Playback has its own state, separate from capture and recording. The native
/// plugin has one session: dispose the camera before initializing a player.
class PlayerValue {
  const PlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isPaused = false,
    this.error,
  });
  final bool isInitialized;
  final bool isPlaying;
  final bool isPaused;
  final String? error;
}

class PlayerController extends ValueNotifier<PlayerValue> {
  PlayerController() : super(const PlayerValue());
  int? _textureId;
  StreamSubscription<dynamic>? _events;
  bool _disposed = false;
  StreamingProtocol? _protocol;
  Future<void>? _initializing;
  bool _ownsNativeSession = false;

  Future<void> initialize() {
    if (_disposed) return Future.error(StateError('Player has been disposed.'));
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final caps = await _channel.invokeMapMethod<String, dynamic>(
        'getCapabilities',
      );
      if ((caps?['features'] as Map?)?['playback'] != true) {
        throw CameraException(
          'unsupportedOperation',
          'This native backend does not support playback.',
        );
      }
      if (_disposed) return;
      final reply = await _channel.invokeMapMethod<String, dynamic>(
        'initializePlayback',
      );
      _ownsNativeSession = true;
      if (_disposed) return;
      _textureId = (reply!['textureId'] as num).toInt();
      _events =
          EventChannel(
            'com.rtmp_streaming.eventchannel/${reply['eventId']}',
          ).receiveBroadcastStream().listen(
            (dynamic event) {
              if (_disposed) return;
              final map = event as Map;
              if (map['eventType'] == 'rtmp_stopped') {
                value = PlayerValue(
                  isInitialized: true,
                  error: map['errorDescription'] as String?,
                );
              } else if (map['eventType'] == 'error') {
                _reportError(map['errorDescription'].toString());
              }
            },
            onError: (Object error) {
              if (!_disposed) _reportError(error.toString());
            },
          );
      value = const PlayerValue(isInitialized: true);
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  void _reportError(String error) {
    value = PlayerValue(
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isPaused: value.isPaused,
      error: error,
    );
  }

  Future<void> play(
    String url, {
    StreamingProtocol protocol = StreamingProtocol.rtmp,
    String? bearerToken,
  }) async {
    if (!value.isInitialized || _disposed) {
      throw StateError('Initialize player first.');
    }
    if (value.isPlaying) throw StateError('Stop existing playback first.');
    if (protocol != StreamingProtocol.rtmp &&
        protocol != StreamingProtocol.whep) {
      throw ArgumentError('Playback supports RTMP and WHEP on iOS.');
    }
    await _channel.invokeMethod<void>('startPlayback', {
      'url': url,
      'protocol': protocol.name,
      'whipToken': ?bearerToken,
    });
    _protocol = protocol;
    if (!_disposed) {
      value = const PlayerValue(isInitialized: true, isPlaying: true);
    }
  }

  /// RTMP supports remote pause. WHEP only supports stop/reconnect.
  Future<void> setPaused(bool paused) async {
    if (_disposed || !value.isPlaying || _protocol != StreamingProtocol.rtmp) {
      throw StateError('Pause requires active RTMP playback.');
    }
    await _channel.invokeMethod<void>(paused ? 'pauseStream' : 'resumeStream');
    if (!_disposed) {
      value = PlayerValue(
        isInitialized: true,
        isPlaying: true,
        isPaused: paused,
      );
    }
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed || !value.isPlaying) {
      throw StateError('Start playback first.');
    }
    await _channel.invokeMethod<void>('setPlaybackMuted', {'muted': muted});
  }

  Future<void> stop() async {
    if (_disposed || !value.isPlaying) return;
    await _channel.invokeMethod<void>('stopStreaming');
    if (!_disposed) value = const PlayerValue(isInitialized: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _initializing;
    } catch (_) {
      /* Initialization did not acquire a session. */
    }
    await _events?.cancel();
    try {
      if (_ownsNativeSession) await _channel.invokeMethod<void>('dispose');
    } finally {
      super.dispose();
    }
  }
}

class PlayerPreview extends StatelessWidget {
  const PlayerPreview(this.controller, {super.key});
  final PlayerController controller;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlayerValue>(
    valueListenable: controller,
    builder: (context, value, child) => value.isInitialized
        ? Texture(textureId: controller._textureId!)
        : const SizedBox.shrink(),
  );
}
