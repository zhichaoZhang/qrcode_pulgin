package com.qfpay.qrcode_plugin;

/**
 * @Description: 扫码识别回调
 * @Author: joye
 * @CreateDate: 2019-08-14 20:44
 * @ProjectName: android
 * @Package: com.qfpay.qrcode_plugin
 * @ClassName: BarcodeScanListener
 */
public interface BarcodeScanListener {
    void onResult(String content);
}
