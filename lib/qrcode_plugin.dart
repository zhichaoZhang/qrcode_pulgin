import 'dart:async';

import 'package:flutter/services.dart';

export 'src/camera_controller.dart';
export 'src/camera.dart';
export 'src/camera_preview.dart';

/// 与原生平台系统通信通道定义
class QrcodePlugin {
  /// 与插件通信方法定义
  /// 获取可用相机列表
  static const String METHOD_AVAILABLE_CAMERAS = "availableCameras";

  /// 初始化相机
  static const String METHOD_INITIALIZE = "initialize";

  /// 开始预览
  static const String METHOD_START_PREVIEW = "startPreview";

  /// 停止预览
  static const String METHOD_STOP_PREVIEW = "stopPreview";

  /// 释放相机
  static const String METHOD_DISPOSE = "dispose";

  /// 扫码成功
  static const String METHOD_SCAN_SUCCESS = "scanSuccess";

  /// 相机操作方法调用通道
  static const MethodChannel _channel =
      const MethodChannel('com.qfpay.flutter.plugin/qrcode_plugin');

  static MethodChannel get channel => _channel;

  /// 相机事件通道
  static EventChannel createCameraEventChannel(int textureId) {
    return EventChannel('com.qfpay.flutter.plugin/camera_event_$textureId');
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// 调用availableCameras接口
  static Future<List<Map<dynamic, dynamic>>> availableCameras() async {
    return await _channel
        .invokeListMethod<Map<dynamic, dynamic>>("availableCameras");
  }

  /// 初始化[cameraName]指定的相机
  static Future<Map<String, dynamic>> initialize(
      String cameraName,
      String resolutionPreset,
      bool enableAudio,
      List<String> codeFormats) async {
    return await _channel
        .invokeMapMethod<String, dynamic>(METHOD_INITIALIZE, <String, dynamic>{
      'cameraName': cameraName,
      'resolutionPreset': resolutionPreset,
      'enableAudio': enableAudio,
      'codeFormats': codeFormats,
    });
  }

  /// 开始预览
  static Future<void> startPreview() async {
    print("start preview");
    return await _channel.invokeMethod(METHOD_START_PREVIEW);
  }

  /// 停止预览
  static Future<void> stopPreview() async {
    print("stop preview");
    return await _channel.invokeMethod(METHOD_STOP_PREVIEW);
  }

  /// 释放相机
  static Future<void> dispose(int textureId) async {
    return await _channel.invokeMethod<void>(
        METHOD_DISPOSE, <String, dynamic>{'textureId': textureId});
  }
}
