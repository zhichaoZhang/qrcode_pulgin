import 'package:flutter/widgets.dart';

import 'camera_controller.dart';

/// 通过textureId创建一个显示视频数据的视图控件
class CameraPreview extends StatelessWidget {
  final CameraController controller;

  const CameraPreview(this.controller);

  @override
  Widget build(BuildContext context) {
    return controller.value.isInitialized
        ? Texture(textureId: controller.textureId)
        : Container();
  }
}
