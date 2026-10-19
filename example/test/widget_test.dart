import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:rtmp_streaming_example/main.dart';

void main() {
  test('camera selector supports front, rear and external cameras', () {
    expect(getCameraLensIcon(CameraLensDirection.front), Icons.camera_front);
    expect(getCameraLensIcon(CameraLensDirection.back), Icons.camera_rear);
    expect(getCameraLensIcon(CameraLensDirection.external), Icons.camera);
  });
}
