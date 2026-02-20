package com.example.controller_tablet

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

// =====================================================
// Device Admin Receiver
// Device Owner 모드에서 완전한 키오스크를 사용할 때 필요
// 설정 방법 (USB 디버깅으로 한 번만):
//   adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
// 해제 방법:
//   adb shell dpm remove-active-admin com.example.controller_tablet/.AdminReceiver
// =====================================================
class AdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}
