package com.qfpay.qrcode_plugin;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import android.media.CamcorderProfile;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Process;
import android.text.TextUtils;
import android.util.Size;
import android.view.Surface;

import androidx.annotation.NonNull;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.ReaderException;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterView;
import io.flutter.view.TextureRegistry;

import static com.qfpay.qrcode_plugin.CameraUtil.computeBestPreviewSize;

/**
 * @Description: 相机抽象类
 * @Author: joye
 * @CreateDate: 2019-08-13 19:50
 * @ProjectName: android
 * @Package: com.qfpay.qrcode_plugin
 * @ClassName: Camera
 */
class Camera {
    private final TextureRegistry.SurfaceTextureEntry flutterTexture;
    private final CameraManager cameraManager;
    private final String cameraName;
    private final Size captureSize;
    private final Size previewSize;

    private CameraDevice cameraDevice;
    private CameraCaptureSession cameraCaptureSession;
    private ImageReader pictureImageReader;
    private EventChannel.EventSink eventSink;
    private CaptureRequest.Builder captureRequestBuilder;

    private final MultiFormatReader multiFormatReader;
    private final Handler mCameraHandler;
    private final Handler mUIHandler;
    private volatile boolean isPreviewing = false;
    private BarcodeScanListener mScanListener;
    private static Map<String, BarcodeFormat> SUPPORT_CODE_FORMATS = new HashMap<>();

    // Mirrors camera.dart
    public enum ResolutionPreset {
        low,
        medium,
        high,
        veryHigh,
        ultraHigh,
        max,
    }

    static {
        SUPPORT_CODE_FORMATS.put("codabar", BarcodeFormat.CODABAR);
        SUPPORT_CODE_FORMATS.put("code39", BarcodeFormat.CODE_39);
        SUPPORT_CODE_FORMATS.put("code93", BarcodeFormat.CODE_93);
        SUPPORT_CODE_FORMATS.put("code128", BarcodeFormat.CODE_128);
        SUPPORT_CODE_FORMATS.put("ean8", BarcodeFormat.EAN_8);
        SUPPORT_CODE_FORMATS.put("ean13", BarcodeFormat.EAN_13);
        SUPPORT_CODE_FORMATS.put("itf", BarcodeFormat.ITF);
        SUPPORT_CODE_FORMATS.put("upca", BarcodeFormat.UPC_A);
        SUPPORT_CODE_FORMATS.put("aztec", BarcodeFormat.AZTEC);
        SUPPORT_CODE_FORMATS.put("datamatrix", BarcodeFormat.DATA_MATRIX);
        SUPPORT_CODE_FORMATS.put("pdf417", BarcodeFormat.PDF_417);
        SUPPORT_CODE_FORMATS.put("qr", BarcodeFormat.QR_CODE);
    }

    Camera(
            final Activity activity,
            final FlutterView flutterView,
            final String cameraName,
            final String resolutionPreset,
            final List<String> codeFormats,
            final BarcodeScanListener barcodeScanListener) {
        if (activity == null) {
            throw new IllegalStateException("No activity available!");
        }

        this.cameraName = cameraName;
        this.flutterTexture = flutterView.createSurfaceTexture();
        this.cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);
        ResolutionPreset preset = ResolutionPreset.valueOf(resolutionPreset);
        CamcorderProfile recordingProfile = CameraUtil.getBestAvailableCamcorderProfileForResolutionPreset(cameraName, preset);
        captureSize = new Size(recordingProfile.videoFrameWidth, recordingProfile.videoFrameHeight);
        previewSize = computeBestPreviewSize(cameraName, preset);

        // 初始化二维码解析器
        multiFormatReader = new MultiFormatReader();
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        Collection<BarcodeFormat> decodeFormats = EnumSet.of(BarcodeFormat.QR_CODE);

        if (codeFormats != null && codeFormats.size() > 0) {
            decodeFormats.clear();
            for(String name : codeFormats) {
                decodeFormats.add(SUPPORT_CODE_FORMATS.get(name));
            }
        }

        hints.put(DecodeHintType.POSSIBLE_FORMATS, decodeFormats);
        multiFormatReader.setHints(hints);

        // 初始化相机操作线程
        HandlerThread handlerThread = new HandlerThread("BarCodeDecode", Process.THREAD_PRIORITY_BACKGROUND);
        handlerThread.start();
        mCameraHandler = new Handler(handlerThread.getLooper());

        mUIHandler = new Handler();

        this.mScanListener = barcodeScanListener;
    }

    TextureRegistry.SurfaceTextureEntry getFlutterTexture() {
        return flutterTexture;
    }

    void setupCameraEventChannel(EventChannel cameraEventChannel) {
        cameraEventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink sink) {
                        eventSink = sink;
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        eventSink = null;
                    }
                });
    }

    /**
     * 打开相机
     *
     * @param result 通道返回
     * @throws CameraAccessException 相机访问异常
     */
    @SuppressLint("MissingPermission")
    void open(@NonNull final MethodChannel.Result result) throws CameraAccessException {
        pictureImageReader =
                ImageReader.newInstance(
                        captureSize.getWidth(), captureSize.getHeight(), ImageFormat.YUV_420_888, 2);

        cameraManager.openCamera(
                cameraName,
                new CameraDevice.StateCallback() {
                    @Override
                    public void onOpened(@NonNull CameraDevice device) {
                        cameraDevice = device;
                        openCamera(result);
                    }

                    @Override
                    public void onClosed(@NonNull CameraDevice camera) {
                        sendEvent(EventType.CAMERA_CLOSING);
                        super.onClosed(camera);
                    }

                    @Override
                    public void onDisconnected(@NonNull CameraDevice cameraDevice) {
                        close();
                        sendEvent(EventType.ERROR, "The camera was disconnected.");
                    }

                    @Override
                    public void onError(@NonNull CameraDevice cameraDevice, int errorCode) {
                        close();
                        String errorDescription;
                        switch (errorCode) {
                            case ERROR_CAMERA_IN_USE:
                                errorDescription = "The camera device is in use already.";
                                break;
                            case ERROR_MAX_CAMERAS_IN_USE:
                                errorDescription = "Max cameras in use";
                                break;
                            case ERROR_CAMERA_DISABLED:
                                errorDescription = "The camera device could not be opened due to a device policy.";
                                break;
                            case ERROR_CAMERA_DEVICE:
                                errorDescription = "The camera device has encountered a fatal error";
                                break;
                            case ERROR_CAMERA_SERVICE:
                                errorDescription = "The camera service has encountered a fatal error.";
                                break;
                            default:
                                errorDescription = "Unknown camera error";
                        }
                        sendEvent(EventType.ERROR, errorDescription);
                    }
                },
                null);
    }

    private String scanBarcode(Image image) {
        if (image == null) {
            return "";
        }
        Image.Plane[] planes = image.getPlanes();
        if (planes == null || planes.length == 0) {
            return "";
        }
        ByteBuffer byteBuffer = planes[0].getBuffer();
        byte[] data = new byte[byteBuffer.remaining()];
        byteBuffer.get(data);
        PlanarYUVLuminanceSource source = buildLuminanceSource(data, previewSize.getWidth(), previewSize.getHeight());
        BinaryBitmap bitmap = new BinaryBitmap(new HybridBinarizer(source));
        try {
            Result rawResult = multiFormatReader.decodeWithState(bitmap);
            return rawResult.getText();
        } catch (ReaderException re) {
            // continue
        } finally {
            multiFormatReader.reset();
        }
        return "";
    }

    /**
     * A factory method to build the appropriate LuminanceSource object based on the format
     * of the preview buffers, as described by Camera.Parameters.
     *
     * @param data   A preview frame.
     * @param width  The width of the image.
     * @param height The height of the image.
     * @return A PlanarYUVLuminanceSource instance.
     */
    private PlanarYUVLuminanceSource buildLuminanceSource(byte[] data, int width, int height) {
        Rect rect = new Rect(0, 0, width, height);
//        if (rect == null) {
//            return null;
//        }
        // Go ahead and assume it's YUV rather than die.
        return new PlanarYUVLuminanceSource(data, width, height, rect.left, rect.top,
                rect.width(), rect.height(), false);
    }

    private void openCamera(final MethodChannel.Result result) {
        if (cameraDevice == null) {
            result.error("CameraAccess", "The camera has been closed, please initialize first.", null);
            return;
        }
        try {
            createCaptureSession(CameraDevice.TEMPLATE_PREVIEW, pictureImageReader.getSurface());
            Map<String, Object> reply = new HashMap<>();
            reply.put("textureId", flutterTexture.id());
            reply.put("previewWidth", previewSize.getWidth());
            reply.put("previewHeight", previewSize.getHeight());
            result.success(reply);
        } catch (CameraAccessException e) {
            e.printStackTrace();
            result.error("CameraAccess", e.getMessage(), null);
            close();
        }
    }

    private CameraCaptureSession.CaptureCallback mCaptureCallback = new CameraCaptureSession.CaptureCallback() {
        @Override
        public void onCaptureCompleted(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
            super.onCaptureCompleted(session, request, result);
            if (!isPreviewing) {
                //如果停止了预览，则不再识别图片
                return;
            }

            if (pictureImageReader == null) {
                return;
            }
            Image image = pictureImageReader.acquireLatestImage();
            final String scanResult = scanBarcode(image);
            if (image != null) {
                image.close();
            }
            if (!TextUtils.isEmpty(scanResult)) {
                // 扫码成功后，自动停止预览
                stopPreview(QrcodePlugin.createMockResult());
                if (mScanListener != null) {
                    // 与Dart通信只能在主线程
                    mUIHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            mScanListener.onResult(scanResult);
                        }
                    });
                }
            }
        }
    };

    /**
     * 开始预览
     */
    void startPreview(final MethodChannel.Result result) {
        if (cameraCaptureSession == null) {
            result.error("CameraAccess", "The camera has been closed, please initialize first.", null);
            return;
        }
        try {
            cameraCaptureSession.setRepeatingRequest(captureRequestBuilder.build(), mCaptureCallback, mCameraHandler);
            isPreviewing = true;
        } catch (CameraAccessException e) {
            e.printStackTrace();
            result.error("CameraAccess", e.getMessage(), null);
            close();
        }
    }

    private void createCaptureSession(int templateType, Surface... surfaces)
            throws CameraAccessException {
        createCaptureSession(templateType, null, surfaces);
    }

    private void createCaptureSession(
            int templateType, final Runnable onSuccessCallback, Surface... surfaces)
            throws CameraAccessException {
        // Close any existing capture session.
        closeCaptureSession();

        // Create a new capture builder.
        captureRequestBuilder = cameraDevice.createCaptureRequest(templateType);

        // Build Flutter surface to render to
        SurfaceTexture surfaceTexture = flutterTexture.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
        Surface flutterSurface = new Surface(surfaceTexture);
        captureRequestBuilder.addTarget(flutterSurface);

        List<Surface> remainingSurfaces = Arrays.asList(surfaces);
//        if (templateType != CameraDevice.TEMPLATE_PREVIEW) {
        // If it is not preview mode, add all surfaces as targets.
        for (Surface surface : remainingSurfaces) {
            captureRequestBuilder.addTarget(surface);
        }
//        }

        // Prepare the callback
        CameraCaptureSession.StateCallback callback =
                new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(@NonNull CameraCaptureSession session) {
                        try {
                            if (cameraDevice == null) {
                                sendEvent(EventType.ERROR, "The camera was closed during configuration.");
                                return;
                            }
                            cameraCaptureSession = session;
                            captureRequestBuilder.set(
                                    CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO);
                            cameraCaptureSession.setRepeatingRequest(captureRequestBuilder.build(), mCaptureCallback, mCameraHandler);
                            isPreviewing = true;
                            if (onSuccessCallback != null) {
                                onSuccessCallback.run();
                            }
                        } catch (CameraAccessException | IllegalStateException | IllegalArgumentException e) {
                            sendEvent(EventType.ERROR, e.getMessage());
                        }
                    }

                    @Override
                    public void onConfigureFailed(@NonNull CameraCaptureSession cameraCaptureSession) {
                        sendEvent(EventType.ERROR, "Failed to configure camera session.");
                    }
                };

        // Collect all surfaces we want to render to.
        List<Surface> surfaceList = new ArrayList<>();
        surfaceList.add(flutterSurface);
        surfaceList.addAll(remainingSurfaces);
        // Start the session
        cameraDevice.createCaptureSession(surfaceList, callback, null);
    }

    /**
     * 停止预览
     */
    void stopPreview(@NonNull final MethodChannel.Result result) {
        if (cameraCaptureSession == null) {
            result.error("CameraAccess", "The camera has been closed, please initialize first.", null);
            return;
        }

        try {
            cameraCaptureSession.stopRepeating();
            isPreviewing = false;
            Map<String, Object> reply = new HashMap<>();
            reply.put("textureId", flutterTexture.id());
            result.success(reply);
        } catch (CameraAccessException | IllegalStateException e) {
            e.printStackTrace();
            result.error("CameraAccess", e.getMessage(), null);
            close();
        }
    }

    private void sendEvent(EventType eventType) {
        sendEvent(eventType, null);
    }

    private void sendEvent(EventType eventType, String description) {
        if (eventSink != null) {
            Map<String, String> event = new HashMap<>();
            event.put("eventType", eventType.toString().toLowerCase());
            // Only errors have description
            if (eventType != EventType.ERROR) {
                event.put("errorDescription", description);
            }
            eventSink.success(event);
        }
    }

    private enum EventType {
        ERROR,
        CAMERA_CLOSING,
    }

    void dispose() {
        close();
        flutterTexture.release();
    }


    void close() {
        closeCaptureSession();

        if (cameraDevice != null) {
            cameraDevice.close();
            cameraDevice = null;
        }
        if (pictureImageReader != null) {
            pictureImageReader.setOnImageAvailableListener(null, null);
            pictureImageReader.close();
            pictureImageReader = null;
        }
        if (mCameraHandler != null) {
            mCameraHandler.getLooper().quit();
        }
    }

    private void closeCaptureSession() {
        if (cameraCaptureSession != null) {
            cameraCaptureSession.close();
            cameraCaptureSession = null;
        }
    }

}
