import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../qrcode_plugin.dart';
import 'camera.dart';

/// 控制一个设备相机
///
/// 使用[availableCameras]方法可获取设备上的可用相机列表
///
class CameraController extends ValueNotifier<CameraValue> {
  final CameraDescription description;
  final ResolutionPreset resolutionPreset;
  final Function onScanSuccess;
  List<CodeFormat> codeFormats; //设置扫码识别格式

  /// 设置在录像时是否允许录音
  final bool enableAudio;

  bool _isDisposed = false; //页面是否被销毁
  Completer<void> _initializedCompleter; //相机初始化异步任务
  int _textureId; //相机图像纹理绘制标识，通过[Texture]类来实现

  StreamSubscription<dynamic> _eventSubscription;

  CameraController(this.description, this.resolutionPreset,
      {this.enableAudio = true, this.onScanSuccess, this.codeFormats})
      : super(const CameraValue.uninitialized());

  int get textureId => _textureId;

  /// 初始化构造函数中传入一个设备相机[description]
  /// 如果初始化失败，会抛出一个[CameraException]
  Future<void> initialize() async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    if (codeFormats == null || codeFormats.length == 0) {
      //如果没有设置条码格式，默认支持二维码
      codeFormats = [CodeFormat.qr];
    }

    try {
      _initializedCompleter = Completer<void>();
      final Map<String, dynamic> reply = await QrcodePlugin.initialize(
          description.name,
          serializeResolutionPreset(resolutionPreset),
          enableAudio,
          serializeCodeFormatsList(codeFormats));
      _textureId = reply['textureId'];
      value = value.copyWith(
        isInitialized: true,
        previewSize: Size(reply['previewWidth'].toDouble(),
            reply['previewHeight'].toDouble()),
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }

    // 注册扫码结果回调
    QrcodePlugin.channel.setMethodCallHandler(_handleMethodCall);

    // 注册相机状态变更事件通道
    _eventSubscription = QrcodePlugin.createCameraEventChannel(_textureId)
        .receiveBroadcastStream()
        .listen(_listener);

    _initializedCompleter.complete();

    return _initializedCompleter.future;
  }

  /// 开始预览
  void startPreview() async {
    if (_isDisposed) {
      return Future<void>.value();
    }

    try {
      await QrcodePlugin.startPreview();
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 停止预览
  void stopPreview() async {
    if (_isDisposed) {
      return Future<void>.value();
    }

    try {
      await QrcodePlugin.stopPreview();
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// 释放相机资源
  @override
  void dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    super.dispose();

    if (_initializedCompleter != null) {
      await _initializedCompleter.future;
      await QrcodePlugin.dispose(_textureId);
      await _eventSubscription?.cancel();
    }
  }

  /// 对原生插件返回的相机状态变更的监听
  /// 例如当应用返回到后台时，会自动关闭相机，并发送[cameraClosing]事件
  void _listener(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    if (_isDisposed) {
      return;
    }
    print('event from plugin is ${map['eventType']}');
    switch (map['eventType']) {
      case 'error':
        value = value.copyWith(errorDescription: event['errorDescription']);
        break;
      case 'cameraClosing':
        value = value.copyWith(isRecordingVideo: false);
        break;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case QrcodePlugin.METHOD_SCAN_SUCCESS:
        if (onScanSuccess != null) {
          onScanSuccess(call.arguments);
        }
        break;
    }
  }
}
