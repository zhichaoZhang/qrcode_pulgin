package com.qfpay.qrcode_plugin;

import android.app.Activity;
import android.content.Context;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.media.CamcorderProfile;
import android.util.Size;
import com.qfpay.qrcode_plugin.Camera.ResolutionPreset;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @Description: 相机操作工具类
 * @Author: joye
 * @CreateDate: 2019-08-13 18:59
 * @ProjectName: android
 * @Package: com.qfpay.qrcode_plugin
 * @ClassName: CameraUtil
 */
public class CameraUtil {

    /**
     * 获取可用相机列表
     *
     * @param activity 上下文
     * @return 相机基本信息列表
     */
    protected static List<Map<String, Object>> getAvailableCameras(Activity activity) throws CameraAccessException {
        CameraManager cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);
        String[] cameraNames = cameraManager.getCameraIdList();
        List<Map<String, Object>> cameras = new ArrayList<>();
        for (String cameraName : cameraNames) {
            HashMap<String, Object> details = new HashMap<>();
            CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraName);
            details.put("name", cameraName);

            Integer sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            details.put("sensorOrientation", sensorOrientation);

            Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
            if (lensFacing == null) {
                return cameras;
            }
            switch (lensFacing) {
                case CameraMetadata.LENS_FACING_FRONT:
                    details.put("lensFacing", "front");
                    break;
                case CameraMetadata.LENS_FACING_BACK:
                    details.put("lensFacing", "back");
                    break;
                case CameraMetadata.LENS_FACING_EXTERNAL:
                    details.put("lensFacing", "external");
                    break;
            }
            cameras.add(details);
        }
        return cameras;
    }

    static Size computeBestPreviewSize(String cameraName, ResolutionPreset preset) {
        if (preset.ordinal() > ResolutionPreset.high.ordinal()) {
            preset = ResolutionPreset.high;
        }

        CamcorderProfile profile =
                getBestAvailableCamcorderProfileForResolutionPreset(cameraName, preset);
        return new Size(profile.videoFrameWidth, profile.videoFrameHeight);
    }

    static CamcorderProfile getBestAvailableCamcorderProfileForResolutionPreset(
            String cameraName, ResolutionPreset preset) {
        int cameraId = Integer.parseInt(cameraName);
        switch (preset) {
            // All of these cases deliberately fall through to get the best available profile.
            case max:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_HIGH)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_HIGH);
                }
            case ultraHigh:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_2160P)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_2160P);
                }
            case veryHigh:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_1080P)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_1080P);
                }
            case high:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_720P)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_720P);
                }
            case medium:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_480P)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_480P);
                }
            case low:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_QVGA)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_QVGA);
                }
            default:
                if (CamcorderProfile.hasProfile(
                        Integer.parseInt(cameraName), CamcorderProfile.QUALITY_LOW)) {
                    return CamcorderProfile.get(CamcorderProfile.QUALITY_LOW);
                } else {
                    throw new IllegalArgumentException(
                            "No capture session available for current capture session.");
                }
        }
    }
}
