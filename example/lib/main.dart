// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtmp_streaming/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class CameraExampleHome extends StatefulWidget {
  const CameraExampleHome({super.key});
  @override
  CameraExampleHomeState createState() {
    return CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection? direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
    default:
      return Icons.camera;
  }
}

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

class CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver {
  final CameraController controller = CameraController(
    ResolutionPreset.medium,
    enableAudio: true,
    androidUseOpenGL: true,
  );
  String? imagePath;
  String? videoPath;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true; // 是否启用音频
  bool isFlashLight = false; // false表示关闭闪光灯，true表示打开闪光灯
  CameraDescription? _cameraDesc;
  final TextEditingController _textFieldController =
      TextEditingController(text: "rtmp://grafana.imchat.love/live/live");

  /// RootEncoder 2.7.0+：BT.709 与 RTMP ping/RTT 示例
  bool _forceBt709 = false;
  bool _rtmpShouldSendPings = false;
  Timer? _streamStatsTimer;
  String _androidStreamStatsLine = '';

  /// HaishinKit 2.2.5+：分屏/多任务时保持相机（iOS 17+）
  bool _iosMultitaskingCamera = false;

  bool get isStreaming => controller.value.isStreamingVideoRtmp ?? false;

  bool get isControllerInitialized => controller.value.isInitialized ?? false;
  bool get isRecordingVideo => controller.value.isRecordingVideo ?? false;
  bool get isRecordingPaused => controller.value.isRecordingPaused;
  bool get isStreamingPaused => controller.value.isStreamingPaused;
  bool get isTakingPicture => controller.value.isTakingPicture ?? false;

  @override
  void initState() {
    onInit();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    onDispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  //
  void onDispose() async {
    _streamStatsTimer?.cancel();
    await WakelockPlus.disable();
    await controller.dispose();
  }
  // @override
  // Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
  //   // App state changed before we got the chance to initialize.
  //   if (!isControllerInitialized) {
  //     return;
  //   }
  //   if (state == AppLifecycleState.paused) {

  //     await pauseVideoRecording();
  //   } else if (state == AppLifecycleState.resumed) {
  //     await resumeVideoRecording();
  //   }
  // }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;

    if (isRecordingVideo) {
      color = Colors.redAccent;
    } else if (isStreaming) {
      color = Colors.blueAccent;
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Camera example'),
        actions: Platform.isAndroid ? [
          ElevatedButton(onPressed: isControllerInitialized ? ()async{
            await controller.setFilter(0);
          } : null, child: Text("set filter")),
          ElevatedButton(onPressed: isControllerInitialized ? ()async{
            await controller.removeFilter(0);
          } : null, child: Text("remove filter")),
          ElevatedButton(
            onPressed: isControllerInitialized
                ? () async {
                    await controller.setFilter(43);
                  }
                : null,
            child: const Text('edge HQ'),
          ),
        ] : null,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: color,
                  width: 3.0,
                ),
              ),
              child: Center(
                child: _cameraPreviewWidget(),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: _captureControlRowWidget(),
          )
        ],
      ),
       floatingActionButton: FloatingActionButton(
          onPressed: isControllerInitialized  ? () async{
            await controller.dispose();
          } : null,
          child: Icon(Icons.close),
        ),
    );
  }

  /// Display camera preview (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (!isControllerInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: CameraPreview(controller),
    );
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          imagePath == null
              ? Container()
              : SizedBox(
                  width: 64.0,
                  height: 64.0,
                  child: Image.file(File(imagePath!)),
                ),
        ],
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    if (!isControllerInitialized) return Container();

    return ListView(
      children: <Widget>[
        // Only Android has implemented it
        if (Platform.isAndroid)
          ElevatedButton.icon(
            icon: const Icon(
              Icons.camera_alt,
              color: Colors.white,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            label: Text(
              "Take Picture",
              style: TextStyle(color: Colors.white),
            ),
            onPressed:
                (isControllerInitialized && (isRecordingVideo || isStreaming)) ? onTakePictureButtonPressed : null,
          ),
        SizedBox(
          width: 5,
        ),
        // Record Localhost video
        ElevatedButton.icon(
          icon: Icon(
            !isRecordingVideo ? Icons.videocam : Icons.stop,
            color: Colors.white,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: !isRecordingVideo ? Colors.blue : Colors.red,
          ),
          label: Text(
            !isRecordingVideo ? "Start Record" : "Stop Record",
            style: TextStyle(color: Colors.white),
          ),
          onPressed: isControllerInitialized
              ? () {
                  if (!isRecordingVideo) {
                    onVideoRecordButtonPressed();
                  } else {
                    stopVideoRecording();
                  }
                }
              : null,
        ),
        SizedBox(
          width: 5,
        ),
        ElevatedButton.icon(
          icon: Icon(
            !isStreaming ? Icons.play_arrow : Icons.stop,
            color: Colors.white,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: !isStreaming ? Colors.blue : Colors.red,
          ),
          label: Text(
            !isStreaming ? "Start Streaming" : "Stop Streaming",
            style: TextStyle(color: Colors.white),
          ),
          onPressed: isControllerInitialized
              ? () {
                  if (!isStreaming) {
                    startVideoStreaming();
                  } else {
                    stopVideoStreaming();
                  }
                }
              : null,
        ),
        // Only Android has implemented it
        if (Platform.isAndroid)
          ElevatedButton.icon(
              icon: Icon(
                isRecordingPaused ? Icons.play_arrow : Icons.pause,
                color: Colors.white,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: !isStreamingPaused ? Colors.blue : Colors.red,
              ),
              label: Text(
                !isRecordingPaused ? "pause Recording" : "resume Recording",
                style: TextStyle(color: Colors.white),
              ),
              onPressed: isControllerInitialized && isRecordingVideo
                  ? () async {
                      if (isRecordingPaused) {
                        await resumeVideoRecording();
                      } else {
                        await pauseVideoRecording();
                      }
                    }
                  : null),
        // stop all Streaming and Recording
        ElevatedButton.icon(
          icon: Icon(
            !(isRecordingVideo && isStreaming) ? Icons.play_arrow : Icons.stop,
            color: Colors.white,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                !(isRecordingVideo && isStreaming) ? Colors.blue : Colors.red,
          ),
          label: Text(
            !(isRecordingVideo && isStreaming)
                ? "Start Streaming And Recording"
                : "Stop Streaming And Recording",
            style: TextStyle(color: Colors.white),
          ),
          onPressed: isControllerInitialized
              ? () {
                  if (isRecordingVideo && isStreaming) {
                    stopRecordingOrStreaming();
                  } else {
                    onRecordingAndVideoStreamingButtonPressed();
                  }
                }
              : null,
        ),
        _cameraTogglesRowWidget(),
        const SizedBox(
          width: 5,
        ),
        Text('${enableAudio ? 'Enable' : 'Disable'} Audio'),
        Switch(
          value: enableAudio,
          onChanged: (bool value) async {
            if (isControllerInitialized) {
              await controller.switchAudio(value);
              setState(() {
                enableAudio = value;
              });
            } else {
              showInSnackBar('Please select a camera first.');
            }
          },
        ),
        const SizedBox(
          width: 5,
        ),
        Text('${isFlashLight ? 'Enable' : 'Disable'} FlashLight'),
        Switch(
          value: isFlashLight,
          onChanged: (bool value) async {
            if (isControllerInitialized &&
                _cameraDesc?.lensDirection == CameraLensDirection.back) {
                   setState(() {
                isFlashLight = value;
              });
              await controller.switchFlashLight(value);
             
            } else {
              showInSnackBar('Please select a camera first.');
            }
          },
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 8),
          Text('BT.709 色彩 (RootEncoder 2.7+)'),
          Switch(
            value: _forceBt709,
            onChanged: (v) {
              setState(() => _forceBt709 = v);
            },
          ),
          Text('RTMP Ping / RTT (需推流前开启)'),
          Switch(
            value: _rtmpShouldSendPings,
            onChanged: (v) {
              setState(() => _rtmpShouldSendPings = v);
            },
          ),
          if (_androidStreamStatsLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _androidStreamStatsLine,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        if (Platform.isIOS) ...[
          const SizedBox(height: 8),
          const Text('多任务相机 (HaishinKit 2.2.5+, iOS 17+)'),
          Switch(
            value: _iosMultitaskingCamera,
            onChanged: (bool v) async {
              setState(() => _iosMultitaskingCamera = v);
              if (!isControllerInitialized) {
                return;
              }
              try {
                await controller.setMultitaskingCameraAccessEnabled(v);
              } on CameraException catch (e) {
                _showCameraException(e);
              }
            },
          ),
          ElevatedButton(
            onPressed: isControllerInitialized
                ? () async {
                    try {
                      await controller.setVideoSettings(
                        expectedFrameRate: 30,
                        bitRateMode: 'average',
                      );
                      showInSnackBar(
                          '已设置 expectedFrameRate=30、bitRateMode=average（2.2.2 onMetaData / 2.2.1 VBR 基础）');
                    } on CameraException catch (e) {
                      _showCameraException(e);
                    }
                  }
                : null,
            child: const Text('HaishinKit 视频编码示例'),
          ),
        ],
        
        _thumbnailWidget(),
      ],
    );
  }

  // switch cameras
  void onSwitchCameras(CameraDescription? cld) async {
    if (cld == null) {
      showInSnackBar("camersa not Empty");
      return;
    }
    try {
       setState(() {
        _cameraDesc = cld;
      });
      await controller.switchCamera(cld.name!);
      await WakelockPlus.enable();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  /// Display a row of toggles to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    if (cameras.isEmpty) {
      return Text('No camera found');
    } else {
      return RadioGroup<CameraDescription>(
        groupValue: _cameraDesc,
        onChanged: (CameraDescription? cld) {
          if (isControllerInitialized) {
            onSwitchCameras(cld);
          }
        },
        child: Column(
          children: cameras.map((cameraDescription) {
            return SizedBox(
              width: 90.0,
              child: RadioListTile<CameraDescription>(
                title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
                value: cameraDescription,
              ),
            );
          }).toList(),
        ),
      );
    }
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  //init
  void onInit() {
    if (cameras.isEmpty) {
      showInSnackBar("No available cameras");
      return;
    }
    var cameraItem = cameras[0];
    setState(() {
      _cameraDesc = cameraItem;
    });
    // init cameras index 0
    onNewCameraSelected(cameraItem);
  }

  //init camera
  void onNewCameraSelected(CameraDescription? cameraDescription) async {
    if (cameraDescription == null) return;
    if (Platform.isMacOS == false) {
      await Permission.camera.request();
      await Permission.microphone.request();
    }
    try {
      await controller.initialize(cameraDescription);
      if (Platform.isIOS && _iosMultitaskingCamera) {
        try {
          await controller.setMultitaskingCameraAccessEnabled(true);
        } on CameraException catch (e) {
          _showCameraException(e);
        }
      }
    } on CameraException catch (e) {
      _showCameraException(e);
    }
    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});

      if (controller.value.event != null) {
        final Map<dynamic, dynamic> event =
            controller.value.event as Map<dynamic, dynamic>;
        final String eventType = event['eventType'] as String;
        //只有发生错误的时候才
        if ((eventType == "error" || eventType == 'rtmp_stopped') &&
            isStreaming) {
          showInSnackBar('Camera error ${controller.value.errorDescription}');
          stopVideoStreaming();
        } else {
          print('Event $event');
          showInSnackBar('Camera message ${controller.value.errorDescription}');
        }
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error:  not init');
      return;
    }
    final Directory? extDir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getTemporaryDirectory();
    if (extDir == null) {
      return;
    }
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (isTakingPicture) {
      showInSnackBar('Error:  current is TakingPicture');
      // A capture is already pending, do nothing.
      return;
    }

    try {
      await controller.takePicture(filePath);
      if (mounted) {
        setState(() {
          imagePath = filePath;
        });
        showInSnackBar('Picture saved to $filePath');
      }
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  void onVideoRecordButtonPressed() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: not init');
      return;
    }

    final Directory? extDir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getTemporaryDirectory();
    if (extDir == null) return;

    final String dirPath = '${extDir.path}/Movies/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.mp4';

    if (isRecordingVideo) {
      // A recording is already started, do nothing.
      showInSnackBar('Error: Recording Video');
      return;
    }

    try {
      videoPath = filePath;
      await controller.startVideoRecording(filePath);
      showInSnackBar('Saving video to $filePath');
      await WakelockPlus.enable();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void startVideoStreaming() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (isStreaming) {
      showInSnackBar('Error: is Streaming');
      return;
    }

    // Open up a dialog for the url
    String myUrl = await _getUrl();
    if (myUrl.isEmpty) {
      showInSnackBar('url is empty');
      return;
    }
    try {
      if (Platform.isAndroid) {
        await controller.setForceBt709Color(_forceBt709);
        await controller.setRtmpShouldSendPings(_rtmpShouldSendPings);
      }
      await controller.startVideoStreaming(myUrl);
      showInSnackBar('Streaming video to $myUrl');
      await WakelockPlus.enable();
      _startAndroidStreamStatsTimer();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  void onRecordingAndVideoStreamingButtonPressed() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: not init');
      return;
    }

    if (isStreaming) {
      showInSnackBar('Error: is Streaming');
      return;
    }

    String myUrl = await _getUrl();
    if (myUrl.isEmpty) {
      showInSnackBar('url is empty');
      return;
    }
    final Directory? extDir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getTemporaryDirectory();
    if (extDir == null) {
      return;
    }
    final String dirPath = '${extDir.path}/Movies/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.mp4';

    try {
      if (Platform.isAndroid) {
        await controller.setForceBt709Color(_forceBt709);
        await controller.setRtmpShouldSendPings(_rtmpShouldSendPings);
      }
      videoPath = filePath;
      await controller.startVideoRecordingAndStreaming(videoPath!, myUrl);
      showInSnackBar('Recording streaming video to $myUrl');
      await WakelockPlus.enable();
      _startAndroidStreamStatsTimer();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  // stop video
  void _startAndroidStreamStatsTimer() {
    if (!Platform.isAndroid) return;
    _streamStatsTimer?.cancel();
    _streamStatsTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || !isStreaming) return;
      try {
        final s = await controller.getStreamStatistics();
        if (!mounted) return;
        setState(() {
          _androidStreamStatsLine =
              'fps=${s.fps}  RTT=${s.rttMicros}µs  已发送字节=${s.bytesSend}';
        });
      } catch (_) {}
    });
  }

  void _stopAndroidStreamStatsTimer() {
    _streamStatsTimer?.cancel();
    _streamStatsTimer = null;
    if (mounted) {
      setState(() => _androidStreamStatsLine = '');
    }
  }

  void stopRecordingOrStreaming() async {
    if (!isStreaming && !isRecordingVideo) {
      showInSnackBar('Video stop streamed or recording');
      return;
    }
    try {
      await controller.stopRecordingOrStreaming();
      _stopAndroidStreamStatsTimer();
      await WakelockPlus.disable();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  // stop Video Recording
  void stopVideoRecording() async {
    if (!isRecordingVideo) {
      showInSnackBar('not Start Recording Video');
      return;
    }
    try {
      await controller.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  /// pause Video Recording
  /// Only Android has implemented it
  Future<void> pauseVideoRecording() async {
    try {
      if (!isRecordingVideo) {
        showInSnackBar('not Start Video recording');
        return;
      }
      await controller.pauseVideoRecording();
      showInSnackBar('Video recording paused');
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    } catch (e) {
      showInSnackBar(e.toString());
    }
  }

  /// resume Video Recording
  /// Only Android has implemented it
  Future<void> resumeVideoRecording() async {
    try {
      if (!isRecordingVideo) {
        showInSnackBar('not Start Video recording');
        return;
      }
      await controller.resumeVideoRecording();
      showInSnackBar('Video recording resume');
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    } catch (e) {
      showInSnackBar(e.toString());
    }
  }


  

  Future<String> _getUrl() async {
    // Open up a dialog for the url
    String result = _textFieldController.text;

    return await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Url to Stream to'),
            content: TextField(
              controller: _textFieldController,
              decoration: InputDecoration(hintText: "Url to Stream to"),
              onChanged: (String str) => result = str,
            ),
            actions: <Widget>[
              TextButton(
                child:
                    Text(MaterialLocalizations.of(context).cancelButtonLabel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
                onPressed: () {
                  Navigator.pop(context, result);
                },
              )
            ],
          );
        });
  }

  void stopVideoStreaming() async {
    if (!isControllerInitialized) {
      showInSnackBar('Error: not init');
      return;
    }
    if (!isStreaming) {
      showInSnackBar('Error: not is Streaming');
      return;
    }

    try {
      await controller.stopVideoStreaming();
      _stopAndroidStreamStatsTimer();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  //
  void _showCameraException(CameraException e) {
    logError(e.code, e.description ?? "No description found");
    showInSnackBar(
        'Error: ${e.code}\n${e.description ?? "No description found"}');
  }
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> cameras = [];

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
    print("$cameras");
  } on CameraException catch (e) {
    logError(e.code, e.description ?? "No description found");
  }
  runApp(CameraApp());
}
