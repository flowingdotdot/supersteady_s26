package com.example.controller_tablet

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.controller_tablet/kiosk"
    private var kioskActive = false
    private val handler = Handler(Looper.getMainLooper())

    // =====================================================
    // 전원 버튼으로 화면 꺼지면 즉시 다시 켜는 리시버
    // 키오스크 모드 활성 상태에서만 동작
    // =====================================================
    private fun isCharging(): Boolean {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.isCharging
    }

    // 충전 상태 변경 감지: 충전 시 화면 켜짐 유지, 비충전 시 화면 꺼짐 허용
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!kioskActive) return
            runOnUiThread {
                if (isCharging()) {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComponent = ComponentName(this@MainActivity, AdminReceiver::class.java)
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        dpm.setKeyguardDisabled(adminComponent, true)
                    }
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                    )
                    wakeUpScreen()
                } else {
                    window.clearFlags(
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                    )
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComponent = ComponentName(this@MainActivity, AdminReceiver::class.java)
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        dpm.setKeyguardDisabled(adminComponent, false)
                    }
                    if (dpm.isAdminActive(adminComponent)) {
                        dpm.lockNow()
                    }
                }
            }
        }
    }

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_OFF && kioskActive && isCharging()) {
                // 충전 중일 때만 화면 다시 켜기 (비충전 시 화면 꺼짐 허용)
                handler.postDelayed({ wakeUpScreen() }, 500)
            }
        }
    }

    private fun wakeUpScreen() {
        // WakeLock으로 화면 강제 켜기
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wl = pm.newWakeLock(
            PowerManager.FULL_WAKE_LOCK
                or PowerManager.ACQUIRE_CAUSES_WAKEUP
                or PowerManager.ON_AFTER_RELEASE,
            "controller_tablet:kiosk_wakeup"
        )
        wl.acquire(5000L)

        // Activity를 앞으로 가져오기
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        startActivity(intent)

        // 최신 API — Activity 레벨에서 화면 켜기
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        // FLAG_KEEP_SCREEN_ON 다시 설정
        runOnUiThread {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // 1초 후 WakeLock 해제 (화면이 켜진 뒤)
        handler.postDelayed({ wl.release() }, 1000)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val screenFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        val powerFilter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, screenFilter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(powerReceiver, powerFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenOffReceiver, screenFilter)
            registerReceiver(powerReceiver, powerFilter)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        unregisterReceiver(screenOffReceiver)
        unregisterReceiver(powerReceiver)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // =====================================================
                    // startKiosk: 완전한 키오스크 모드
                    //   - startLockTask()로 홈/뒤로/최근앱 전부 차단
                    //   - 시스템 바(상태바+네비바) 숨김
                    //   - 전원 버튼 눌러도 화면 즉시 복귀
                    //
                    //   ※ Device Owner 필요 (USB로 한 번만):
                    //   adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
                    // =====================================================
                    "startKiosk" -> {
                        try {
                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val adminComponent = ComponentName(this, AdminReceiver::class.java)

                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
                                dpm.setKeyguardDisabled(adminComponent, true)
                            }

                            startLockTask()
                            hideSystemUI()
                            kioskActive = true

                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                            )

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("KIOSK_ERROR", e.message, null)
                        }
                    }

                    // =====================================================
                    // stopKiosk: 키오스크 완전 해제
                    // Device Owner 모드에서는 알림/팝업 없이 해제됨
                    // =====================================================
                    "stopKiosk" -> {
                        try {
                            kioskActive = false

                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val adminComponent = ComponentName(this, AdminReceiver::class.java)

                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.setKeyguardDisabled(adminComponent, false)
                            }

                            stopLockTask()
                            showSystemUI()

                            window.clearFlags(
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                            )

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("KIOSK_ERROR", e.message, null)
                        }
                    }

                    // =====================================================
                    // isDeviceOwner: Device Owner 등록 여부 확인
                    // =====================================================
                    "isDeviceOwner" -> {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        result.success(dpm.isDeviceOwnerApp(packageName))
                    }

                    // =====================================================
                    // clearDeviceOwner: Device Owner 해제
                    // =====================================================
                    "clearDeviceOwner" -> {
                        try {
                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.clearDeviceOwnerApp(packageName)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("CLEAR_OWNER_ERROR", e.message, null)
                        }
                    }

                    // =====================================================
                    // openAppSettings: 앱 권한 설정 화면 열기
                    // =====================================================
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                it.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
        }
    }

    private fun showSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(
                WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
            )
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}
