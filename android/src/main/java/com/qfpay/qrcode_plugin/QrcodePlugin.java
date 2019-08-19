package com.qfpay.qrcode_plugin;

import android.hardware.camera2.CameraAccessException;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.ArrayList;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * QrcodePlugin
 */
public class QrcodePlugin implements MethodCallHandler {
    private Registrar mRegistrar;

    // 与插件通信方法定义
    // 获取可用相机列表
    private final static String METHOD_AVAILABLE_CAMERAS = "availableCameras";
    // 初始化相机
    private final static String METHOD_INITIALIZE = "initialize";
    // 开始预览
    private final static String METHOD_START_PREVIEW = "startPreview";
    // 停止预览
    private final static String METHOD_STOP_PREVIEW = "stopPreview";
    /// 释放相机
    private final static String METHOD_DISPOSE = "dispose";
    /// 扫码成功
    private final static  String METHOD_SCAN_SUCCESS = "scanSuccess";

    private Camera mCamera;
    private CameraPermissions mCameraPer = new CameraPermissions();
    private static MethodChannel mChannel;

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            // SDK版本低于21(Camera2 API支持的最低版本)不支持
            return;
        }

        mChannel = new MethodChannel(registrar.messenger(), "com.qfpay.flutter.plugin/qrcode_plugin");
        mChannel.setMethodCallHandler(new QrcodePlugin(registrar));
    }

    private QrcodePlugin(Registrar registrar) {
        this.mRegistrar = registrar;
    }

    @Override
    public void onMethodCall(@NonNull final MethodCall call, @NonNull final Result result) {
        String method = call.method;
        switch (method) {
            case "getPlatformVersion":
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                break;
            case METHOD_AVAILABLE_CAMERAS:
                availableCameras(call, result);
                break;
            case METHOD_INITIALIZE:
                if (mCamera != null) {
                    mCamera.close();
                }
                boolean enableAudio = false;
                Object arg = call.argument("enableAudio");
                if (arg != null) {
                    enableAudio = (boolean) arg;
                }
                mCameraPer.requestPermissions(mRegistrar, enableAudio, new CameraPermissions.ResultCallback() {
                    @Override
                    public void onResult(String errorCode, String errorDescription) {
                        if (errorCode == null) {
                            try {
                                initializeCamera(call, result);
                            } catch (CameraAccessException e) {
                                handleException(e, result);
                            }
                        } else {
                            result.error(errorCode, errorDescription, null);
                        }
                    }
                });

                break;
            case METHOD_START_PREVIEW:
                startPreview(result);
                break;

            case METHOD_STOP_PREVIEW:
                stopPreview(result);
                break;
            case METHOD_DISPOSE:
                dispose(call, result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    // 开始预览
    private void startPreview(Result result) {
        if (mCamera != null) {
            mCamera.startPreview(result);
        }
    }

    //停止预览
    private void stopPreview(Result result) {
        if (mCamera != null) {
            mCamera.stopPreview(result);
        }
    }

    private void handleException(Exception e, Result result) {
        if (e instanceof CameraAccessException) {
            result.error("CameraAccess", e.getMessage(), null);
        }
    }

    // 获取可用相机列表
    private void availableCameras(MethodCall call, final Result result) {
        try {
            result.success(CameraUtil.getAvailableCameras(mRegistrar.activity()));
        } catch (CameraAccessException e) {
            handleException(e, result);
        }
    }

    // 初始化相机
    private void initializeCamera(MethodCall call, final Result result) throws CameraAccessException {
        String cameraName = call.argument("cameraName");
        String resolutionPreset = call.argument("resolutionPreset");
        ArrayList<String> codeFormats = call.argument("codeFormats");

//        Boolean enableAudio = call.argument("enableAudio");
//        if (enableAudio == null) {
//            enableAudio = Boolean.FALSE;
//        }
        mCamera = new Camera(mRegistrar.activity(), mRegistrar.view(), cameraName, resolutionPreset, codeFormats, new BarcodeScanListener() {
            @Override
            public void onResult(String content) {
                mChannel.invokeMethod(METHOD_SCAN_SUCCESS, content);
            }
        });
        EventChannel cameraEventChannel = new EventChannel(mRegistrar.messenger(), "com.qfpay.flutter.plugin/camera_event_" + mCamera.getFlutterTexture().id());
        mCamera.setupCameraEventChannel(cameraEventChannel);
        mCamera.open(result);
    }

    // 释放相机
    private void dispose(MethodCall call, final Result result) {
        if (mCamera != null) {
            mCamera.dispose();
        }
        result.success(null);
    }

    /**
     * 伪造Result对象，用于插件内部调用API
     * @return Result
     */
    static Result createMockResult() {
        return new Result() {
            @Override
            public void success(Object o) {

            }

            @Override
            public void error(String s, String s1, Object o) {

            }

            @Override
            public void notImplemented() {

            }
        };
    }
}
