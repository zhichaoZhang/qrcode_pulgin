import 'package:flutter/material.dart';
import 'package:qrcode_plugin/qrcode_plugin.dart';

class CameraPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return CameraPageState();
  }
}

class CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CameraController cameraController;
  String cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    availableCameras().then((cameras) {
      if (cameras.length > 0) {
        initCamera(cameras[0]);
      } else {
        setState(() {
          cameraError = "No available camera";
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    /// 通过添加WidgetsBindingObserver，实现应用生命周期的监听
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initCamera(cameraController.description);
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (cameraController != null) {
      cameraController.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
  }

  void initCamera(CameraDescription description) {
    cameraController?.dispose();
    cameraController = CameraController(description, ResolutionPreset.max,
        codeFormats: [CodeFormat.code128, CodeFormat.qr],
        onScanSuccess: (content) {
      showInSnackBar(content);
    });

    cameraController.addListener(() {
      if (mounted) {
        setState(() {
          if (cameraController.value.hasError) {
            showInSnackBar(
                'Camera error ${cameraController.value.errorDescription}');
          }
        });
      }
    });

    cameraController.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text("Camera Demo"),
      ),
      body: Center(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (cameraError != null) {
      return Text(cameraError);
    }

    if (cameraController == null || !cameraController.value.isInitialized) {
      return CircularProgressIndicator();
    }

    return Stack(
      children: <Widget>[
        AspectRatio(
          aspectRatio: cameraController.value.aspectRatio,
          child: CameraPreview(cameraController),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Row(
            children: <Widget>[
              RaisedButton(
                onPressed: () {
                  cameraController.startPreview();
                },
                child: Text("开始预览"),
              ),
              RaisedButton(
                onPressed: () {
                  cameraController.stopPreview();
                },
                child: Text("停止预览"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }
}
