# qrcode_plugin

A new Flutter plugin for Qrcode. Supports iOS and Android

On Android, the code recognition is based on Zxing library.
On iOS, the code recognition is realized by AVFoundation.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/developing-packages/),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter, view our 
[online documentation](https://flutter.dev/docs), which offers tutorials, 
samples, guidance on mobile development, and a full API reference.

## Usage

To use this plugin, and qrcode_plugin as dependency in your pubspec.yaml file

### Add permission

#### iOS
Add the following keys to your Info.plist file, located in <project root>/ios/Runner/Info.plist:

* NSCameraUsageDescription - describe why your app needs access to the camera. This is called Privacy - Camera Usage Description in the visual editor.

#### Android

Add the following code to you AndroidManifest.xml file.

```
<uses-permission android:name="android.permission.CAMERA"/>
```

### Supported Code Formats

```
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
```


## Example

```
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    availableCameras().then((cameras) {
      initCamera(cameras[0]);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    cameraController.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  void initCamera(CameraDescription description) {
    cameraController?.dispose();
    cameraController = CameraController(description, ResolutionPreset.high,
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
                child: Text("start preview"),
              ),
              RaisedButton(
                onPressed: () {
                  cameraController.stopPreview();
                },
                child: Text("stop preview"),
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
```
