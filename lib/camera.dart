// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final MethodChannel _channel = const MethodChannel('com.rtmp_streaming');

enum CameraLensDirection { front, back, external }

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
class StreamStatistics {
  final int? cacheSize;
  final int? sentAudioFrames;
  final int? sentVideoFrames;
  final int? droppedAudioFrames;
  final int? droppedVideoFrames;
  final bool? isAudioMuted;
  final int? bitrate;
  final int? width;
  final int? height;
  final int? fps;
  /// RTMP 往返时延（微秒），需 `setRtmpShouldSendPings(true)` 且推流建立后由服务端响应 ping。
  final int? rttMicros;
  final int? bytesSend;

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
    this.fps,
    this.rttMicros,
    this.bytesSend,
  });

  @override
  String toString() {
    return 'StreamStatistics{cacheSize: $cacheSize, sentAudioFrames: $sentAudioFrames, sentVideoFrames: $sentVideoFrames, droppedAudioFrames: $droppedAudioFrames, droppedVideoFrames: $droppedVideoFrames, isAudioMuted: $isAudioMuted, bitrate: $bitrate, width: $width, height: $height, fps: $fps, rttMicros: $rttMicros, bytesSend: $bytesSend}';
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
            child: childView);
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
    this.isStreamingVideoRtmp,
    this.event,
    bool? isRecordingPaused,
    bool? isStreamingPaused,
  })  : _isRecordingPaused = isRecordingPaused,
        _isStreamingPaused = isStreamingPaused;

  const CameraValue.uninitialized()
      : this(
          isInitialized: false,
          isRecordingVideo: false,
          isTakingPicture: false,
          isStreamingVideoRtmp: false,
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

  /// True when the camera is recording (not the same as previewing).
  final bool? isStreamingVideoRtmp;
  final bool? _isRecordingPaused;
  final bool? _isStreamingPaused;

  /// True when camera [isRecordingVideo] and recording is paused.
  bool get isRecordingPaused => isRecordingVideo! && _isRecordingPaused!;

  /// True when camera [isRecordingVideo] and streaming is paused.
  bool get isStreamingPaused => isStreamingVideoRtmp! && _isStreamingPaused!;

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
    bool? isStreamingVideoRtmp,
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
      isStreamingVideoRtmp: isStreamingVideoRtmp ?? this.isStreamingVideoRtmp,
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
        'isStreamingVideoRtmp: $isStreamingVideoRtmp)';
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
    this.androidUseOpenGL = false,
  }) : super(const CameraValue.uninitialized());

  final ResolutionPreset resolutionPreset;

  /// Whether to include audio when recording a video.
  final bool enableAudio;

  int? _textureId;
  int? _eventId;
  bool _isDisposed = false;
  StreamSubscription<dynamic>? _eventSubscription;
  Completer<void>? _creatingCompleter;
  final bool androidUseOpenGL;

  /// Initializes the camera on the device.
  ///
  /// Throws a [CameraException] if the initialization fails.
  Future<void> initialize(CameraDescription cameraDesc) async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    try {
      _creatingCompleter = Completer<void>();
      final Map<String, dynamic> reply =
          (await _channel.invokeMapMethod<String, dynamic>(
        'initialize',
        <String, dynamic>{
          'cameraName': cameraDesc.name,
          'resolutionPreset': serializeResolutionPreset(resolutionPreset),
          'enableAudio': enableAudio,
          'enableAndroidOpenGL': androidUseOpenGL
        },
      ))!;
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
      throw CameraException(e.code, e.message);
    }
    _eventSubscription =
        EventChannel('com.rtmp_streaming.eventchannel/$_eventId')
            .receiveBroadcastStream()
            .listen(_listener);
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
      'errorDescription': errorDescription
    };
    switch (eventType) {
      case 'error':
        value =
            value.copyWith(errorDescription: errorDescription, event: uniEvent);
        break;
      case 'camera_closing':
        value = value.copyWith(
            errorDescription: errorDescription,
            isRecordingVideo: false,
            isStreamingVideoRtmp: false,
            event: uniEvent);
        break;
      case 'rtmp_retry':
        value =
            value.copyWith(errorDescription: errorDescription, event: uniEvent);
        break;
      case 'rtmp_stopped':
        value = value.copyWith(
            errorDescription: errorDescription,
            isStreamingVideoRtmp: false,
            event: uniEvent);
        break;
      case 'success':
        value = value.copyWith(
            errorDescription: errorDescription,
            isStreamingVideoRtmp: true,
            isStreamingPaused: false,
            event: uniEvent);
        break;
      case 'wait':
        value =
            value.copyWith(errorDescription: errorDescription, event: uniEvent);
        break;
      default:
        value =
            value.copyWith(errorDescription: errorDescription, event: uniEvent);
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
      await _channel.invokeMethod<void>(
        'takePicture',
        <String, dynamic>{'path': path},
      );
      value = value.copyWith(isTakingPicture: false);
    } on PlatformException catch (e) {
      value = value.copyWith(isTakingPicture: false);
      throw CameraException(e.code, e.message);
    }
  }

  /// The set filter
  ///
  /// Android 滤镜类型包含：`15` 边缘检测（性能模式）、`43` 边缘检测 Sobel 高质量（RootEncoder 2.7.0+）等，详见原生 [CameraNativeView]。
  ///
  /// Throws a [CameraException] if the capture fails.
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
      await _channel.invokeMethod<void>(
        'setFilter',
        <String, dynamic>{'type': type, 'filePath': filePath},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 使用 BT.709 色彩矩阵编码视频（RootEncoder 2.7.0+，仅 Android）。
  ///
  /// 在 [startVideoStreaming] / 开始录制 之前调用；可与服务端色彩处理对齐。
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
      await _channel.invokeMethod<void>(
        'setForceBt709Color',
        <String, dynamic>{'enabled': enabled},
      );
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

  /// The remove filter
  ///
  /// Throws a [CameraException] if the capture fails.
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
      await _channel.invokeMethod<void>(
        'removeFilter',
        <String, dynamic>{'type': type},
      );
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
    if (!value.isStreamingVideoRtmp!) {
      throw CameraException(
        'No camera is streaming images',
        'stopImageStream was called when no camera is streaming images.',
      );
    }

    try {
      var data = (await _channel
          .invokeMapMethod<String, dynamic>('getStreamStatistics'))!;
      return StreamStatistics(
        sentAudioFrames: data["sentAudioFrames"] as int?,
        sentVideoFrames: data["sentVideoFrames"] as int?,
        height: data["height"] as int?,
        width: data["width"] as int?,
        bitrate: data["bitrate"] as int?,
        isAudioMuted: data["isAudioMuted"] as bool?,
        cacheSize: data["cacheSize"] as int?,
        droppedAudioFrames: data["droppedAudioFrames"] as int?,
        droppedVideoFrames: data["droppedVideoFrames"] as int?,
        fps: data["fps"] as int?,
        rttMicros: data["rttMicros"] as int?,
        bytesSend: (data["bytesSend"] as num?)?.toInt(),
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

  /// Stop recording.
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
      value =
          value.copyWith(isRecordingVideo: false, isStreamingVideoRtmp: false);
      await _channel.invokeMethod<void>(
        'stopRecording',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Pause video recording.
  /// Only supports Android
  /// This feature is only available on iOS and Android sdk 24+.
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
      value = value.copyWith(isRecordingPaused: true);
      await _channel.invokeMethod<void>(
        'pauseVideoRecording',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Resume video recording after pausing.
  /// Only supports Android
  /// This feature is only available on iOS and Android sdk 24+.
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
      value = value.copyWith(isRecordingPaused: false);
      await _channel.invokeMethod<void>(
        'resumeVideoRecording',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start a video streaming to the url in [url`].
  ///
  /// This uses rtmp to do the sending the remote side.
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> startVideoRecordingAndStreaming(String filePath, String url,
      {int bitrate = 1200 * 1024, bool? androidUseOpenGL}) async {
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
    if (value.isStreamingVideoRtmp!) {
      throw CameraException(
        'A video streaming is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }

    try {
      await _channel.invokeMethod<void>(
          'startVideoRecordingAndStreaming', <String, dynamic>{
        'url': url,
        'filePath': filePath,
        'bitrate': bitrate,
      });
      value = value.copyWith(
          isStreamingVideoRtmp: true,
          isStreamingPaused: false,
          isRecordingVideo: true,
          isRecordingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start a video streaming to the url in [url`].
  ///
  /// This uses rtmp to do the sending the remote side.
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> startVideoStreaming(String url,
      {int bitrate = 1200 * 1024, bool? androidUseOpenGL}) async {
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
    if (value.isStreamingVideoRtmp!) {
      throw CameraException(
        'A video streaming is already started.',
        'startVideoStreaming was called when a recording is already started.',
      );
    }

    try {
      await _channel
          .invokeMethod<void>('startVideoStreaming', <String, dynamic>{
        'url': url,
        'bitrate': bitrate,
      });
      value =
          value.copyWith(isStreamingVideoRtmp: true, isStreamingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop streaming.
  Future<void> stopVideoStreaming() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'stopVideoStreaming was called on uninitialized CameraController',
      );
    }
    if (!value.isStreamingVideoRtmp!) {
      throw CameraException(
        'No video is recording',
        'stopVideoStreaming was called when no video is streaming.',
      );
    }
    try {
      value =
          value.copyWith(isStreamingVideoRtmp: false, isRecordingVideo: false);
      await _channel.invokeMethod<void>(
        'stopStreaming',
        <String, dynamic>{},
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
    if (!value.isStreamingVideoRtmp!) {
      throw CameraException(
        'No video is recording',
        'stopRecordingOrStreaming was called when no video is streaming.',
      );
    }
    try {
      value =
          value.copyWith(isStreamingVideoRtmp: false, isRecordingVideo: false);
      await _channel.invokeMethod<void>(
        'stopRecordingOrStreaming',
        <String, dynamic>{},
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
      await _channel.invokeMethod<void>(
          'switchCamera', <String, dynamic>{'cameraName': cameraId});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// switch Audio
  ///
  /// This switch Audio
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<void> switchAudio(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'startVideoStreaming was called on uninitialized CameraController',
      );
    }
    if (!value.isStreamingVideoRtmp!) {
      throw CameraException(
        'No video is recording',
        'resumeVideoStreaming was called when no video is streaming.',
      );
    }
    if (!Platform.isAndroid) {
      throw CameraException(
        'Currently only supports Android platform',
        'Please use on Android platform',
      );
    }
    try {
      await _channel.invokeMethod<void>(
          'switchAudio', <String, dynamic>{'isEnable': isEnable});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

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
    if (!value.isStreamingVideoRtmp!) {
      throw CameraException(
        'No video is recording',
        'resumeVideoStreaming was called when no video is streaming.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
          'switchFlashLight', <String, dynamic>{'isEnable': isEnable});
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
    if (!value.isStreamingVideoRtmp!) {
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
      value = value.copyWith(isStreamingPaused: true);
      await _channel.invokeMethod<void>(
        'pauseStream',
        <String, dynamic>{},
      );
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
    if (!value.isStreamingVideoRtmp!) {
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
      value = value.copyWith(isStreamingPaused: false);
      await _channel.invokeMethod<void>(
        'resumeStream',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Audio Settings
  /// Only supports ios
  Future<void> setAudioSettings(int bitrate) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setAudioSettings was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setAudioSettings Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setAudioSettings',
        <String, dynamic>{"bitrate": bitrate},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set video Settings
  ///
  /// [expectedFrameRate]：HaishinKit 2.2.2+，写入编码期望帧率并进入 RTMP onMetaData 的 `framerate`。
  ///
  /// [bitRateMode]：`average`（默认）、`constant`（iOS 16+）、`variable`（iOS 26+，对应 VideoToolbox VBR）。
  /// Only supports ios
  Future<void> setVideoSettings(
      {int? bitrate,
      int? width,
      int? height,
      int? frameInterval,
      String? profileLevel,
      double? expectedFrameRate,
      String? bitRateMode}) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setVideoSettings was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setVideoSettings Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setVideoSettings',
        <String, dynamic>{
          "bitrate": bitrate,
          "width": width,
          "height": height,
          "frameInterval": frameInterval,
          "profileLevel": profileLevel,
          if (expectedFrameRate != null) "expectedFrameRate": expectedFrameRate,
          if (bitRateMode != null) "bitRateMode": bitRateMode,
        },
      );
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

  /// Obtain whether to temporarily mute
  /// Only supports ios
  Future<bool?> getHasAudio() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'getHasAudio was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'getHasAudio Only supports Ios.',
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

  /// Set temporary mute
  /// Only supports ios
  Future<void> setHasAudio(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setHasAudio was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setHasAudio Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setHasAudio',
        <String, dynamic>{"isEnable": isEnable},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Obtain whether to temporarily video
  /// Only supports ios
  Future<bool?> getHasVideo() async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'getHasVideo was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'getHasVideo Only supports Ios.',
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

  /// Set temporary Video
  /// Only supports ios
  Future<void> setHasVideo(bool isEnable) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setHasVideo was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setHasVideo Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setHasVideo',
        <String, dynamic>{"isEnable": isEnable},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Frame Rate
  /// Only supports ios
  Future<void> setFrameRate(int frameRate) async {
    if (!value.isInitialized! || _isDisposed) {
      throw CameraException(
        'Uninitialized CameraController',
        'setFrameRate was called on uninitialized CameraController',
      );
    }
    if (!Platform.isIOS) {
      throw CameraException(
        'Unsupported platforms.',
        'setFrameRate Only supports Ios.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'setFrameRate',
        <String, dynamic>{"frameRate": frameRate},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Session Preset
  /// Only supports ios
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
      await _channel.invokeMethod<void>(
        'setSessionPreset',
        <String, dynamic>{"sessionPreset": sessionPreset},
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// set Screen Settings
  /// Only supports ios
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
      await _channel.invokeMethod<void>(
        'setScreenSettings',
        <String, dynamic>{"width": width, "height": height},
      );
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
    value = value.copyWith(
      isStreamingVideoRtmp: false,
      isRecordingVideo: false,
    );
    notifyListeners();
    super.dispose();
    if (_creatingCompleter != null) {
      await _creatingCompleter!.future;
      await _channel.invokeMethod<void>(
        'dispose',
        <String, dynamic>{},
      );
      await _eventSubscription?.cancel();
    }
  }
}
