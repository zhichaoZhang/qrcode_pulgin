import 'dart:ui';

import 'package:flutter/services.dart';

import '../qrcode_plugin.dart';

/// 相机摄像头方向，例如后置、前置、额外的
enum CameraLensDirection { front, back, external }

/// 支持识别的条形码格式枚举类型
enum CodeFormat {
  codabar,
  code39,
  code93,
  code128,
  ean8,
  ean13,
  itf,
  upca,
  upce,
  aztec,
  datamatrix,
  pdf417,
  qr
}

/// 相机描述类
class CameraDescription {
  /// 相机名称
  final String name;

  /// 摄像头朝向
  final CameraLensDirection lensDirection;

  /// 相机传感器方向
  /// 也是需要将输出的图片通过顺时针旋转后，来达到在屏幕上向上显示需要旋转的角度
  final int sensorOrientation;

  CameraDescription(this.name, this.lensDirection, this.sensorOrientation);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDescription &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          lensDirection == other.lensDirection &&
          sensorOrientation == other.sensorOrientation;

  @override
  int get hashCode =>
      name.hashCode ^ lensDirection.hashCode ^ sensorOrientation.hashCode;

  @override
  String toString() {
    return 'CameraDescription{name: $name, lensDirection: $lensDirection, sensorOrientation: $sensorOrientation}';
  }
}

/// 相机操作异常类型
class CameraException implements Exception {
  String code;
  String description;

  CameraException(this.code, this.description);

  @override
  String toString() {
    return 'CameraException{code: $code, description: $description}';
  }
}

/// 获取可用相机列表
Future<List<CameraDescription>> availableCameras() async {
  try {
    List<Map<dynamic, dynamic>> cameras = await QrcodePlugin.availableCameras();
    return cameras.map((Map<dynamic, dynamic> camera) {
      return CameraDescription(
          camera['name'],
          _parseCameraLensDirection(camera['lensFacing']),
          camera['sensorOrientation']);
    }).toList();
  } on PlatformException catch (e) {
    throw CameraException(e.code, e.message);
  }
}

CameraLensDirection _parseCameraLensDirection(String string) {
  switch (string) {
    case 'front':
      return CameraLensDirection.front;
    case 'back':
      return CameraLensDirection.back;
    case 'external':
      return CameraLensDirection.external;
  }
  throw ArgumentError('Unknown CameraLensDirection value');
}

/// 相机控制器[CameraController]的状态描述
class CameraValue {
  /// 是否完成初始化，当[CameraController.initialiaze]完成后，此字段变为true
  final bool isInitialized;

  /// 当向原生系统发送了拍照请求，但还没有返回时此字段为true
  final bool isTakingPicture;

  /// 正在录像时此字段为true
  final bool isRecordingVideo;

  /// 当从相机获取到图像流时此字段为true
  final bool isStreamImages;

  /// 相机操作错误描述
  final String errorDescription;

  /// 相机预览尺寸，当没有初始化完成之前，此字段为null
  final Size previewSize;

  /// 相机预览尺寸高宽比
  double get aspectRatio => previewSize.height / previewSize.width;

  /// 是否发生错误
  bool get hasError => errorDescription != null;

  const CameraValue(
      {this.isInitialized,
      this.isTakingPicture,
      this.isRecordingVideo,
      this.isStreamImages,
      this.errorDescription,
      this.previewSize});

  /// 将当前状态置为未初始化
  const CameraValue.uninitialized()
      : this(
            isInitialized: false,
            isRecordingVideo: false,
            isTakingPicture: false,
            isStreamImages: false);

  /// 复制当前状态
  CameraValue copyWith({
    bool isInitialized,
    bool isRecordingVideo,
    bool isTakingPicture,
    bool isStreamImages,
    String errorDescription,
    Size previewSize,
  }) {
    return CameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      errorDescription: errorDescription,
      previewSize: previewSize ?? this.previewSize,
      isRecordingVideo: isRecordingVideo ?? this.isRecordingVideo,
      isTakingPicture: isTakingPicture ?? this.isTakingPicture,
      isStreamImages: isStreamImages ?? this.isStreamImages,
    );
  }

  @override
  String toString() {
    return 'CameraValue{isInitialized: $isInitialized, isTakingPicture: $isTakingPicture, isRecordingVideo: $isRecordingVideo, isStreamImages: $isStreamImages, errorDescription: $errorDescription, previewSize: $previewSize}';
  }
}

/// 支持的屏幕分辨率类型，不同的类型影响了拍照和录像的质量
/// 如果设备不支持设置的分辨率，则会自动向下选择一个较低分辨率类型。
enum ResolutionPreset {
  /// iOS设备上代表352x288，Android设备上代表240p(320x240)
  low,

  /// 480p (iOS上的640x480, Android上的720x480)
  medium,

  /// 720p (1280x720)
  high,

  /// 1080p (1920x1080)
  veryHigh,

  /// 2160p (3840x2160)
  ultraHigh,

  /// 设备支持的最大分辨率
  max,
}

/// 将[ResolutionPreset]转换成字符串方式表示
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
  throw ArgumentError('Unknown ResolutionPreset value');
}

/// 条码枚举类型与字符描述对应
var _availableFormats = {
  CodeFormat.codabar: 'codabar', // Android only
  CodeFormat.code39: 'code39',
  CodeFormat.code93: 'code93',
  CodeFormat.code128: 'code128',
  CodeFormat.ean8: 'ean8',
  CodeFormat.ean13: 'ean13',
  CodeFormat.itf: 'itf', // itf-14 on iOS, should be changed to Interleaved2of5?
  CodeFormat.upca: 'upca', // Android only
  CodeFormat.upce: 'upce',
  CodeFormat.aztec: 'aztec',
  CodeFormat.datamatrix: 'datamatrix',
  CodeFormat.pdf417: 'pdf417',
  CodeFormat.qr: 'qr',
};

List<String> serializeCodeFormatsList(List<CodeFormat> formats) {
  List<String> list = [];

  for (var i = 0; i < formats.length; i++) {
    if (_availableFormats[formats[i]] != null) {
      //  this format exists in my list of available formats
      list.add(_availableFormats[formats[i]]);
    }
  }

  return list;
}
