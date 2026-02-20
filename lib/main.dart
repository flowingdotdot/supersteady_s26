// =============================================================
// [키오스크 모드 설정 방법] — 기기 4대 각각 한 번씩 해야 함
// =============================================================
//
// 1. 태블릿에서 사전 준비
//    - 설정 → 계정 → 모든 계정 삭제 (구글 계정 포함)
//      ※ 계정이 남아있으면 Device Owner 등록이 거부됨
//    - 설정 → 개발자 옵션 → USB 디버깅 ON
//      (개발자 옵션이 안 보이면: 설정 → 태블릿 정보 → 빌드번호 7번 터치)
//
// 2. PC에 ADB 설치 (이미 있으면 건너뛰기)
//    - Android Studio 설치하면 ADB 자동 포함
//    - 또는 https://developer.android.com/tools/releases/platform-tools 에서
//      "SDK Platform-Tools" 다운 → 압축풀기 → 폴더를 PATH에 추가
//    - cmd에서 adb version 쳐서 나오면 OK
//
// 3. 태블릿을 USB로 PC에 연결
//    - 태블릿에 "USB 디버깅 허용?" 팝업 뜨면 허용
//    - cmd에서 확인:
//      adb devices
//      → 기기 시리얼 번호가 나오면 연결 성공
//
// 4. Device Owner 등록 (기기 1대당 한 번만)
//    - 앱이 이미 설치되어 있어야 함 (flutter run 또는 apk 설치)
//    - cmd에서 실행:
//      adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
//    - "Success" 나오면 완료
//
//    ※ 기기 여러 대 동시 연결 시 시리얼 지정:
//      adb -s [시리얼번호] shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
//      (시리얼번호는 adb devices 에서 확인)
//
// 5. 확인
//    - 앱 실행 → 테스트 페이지 → 세팅 → 키오스크 모드 토글
//    - "Device Owner 미등록" 대신 "홈/뒤로/최근앱 차단 + 전원버튼 복귀" 표시되면 성공
//
// [해제 방법]
//    adb shell dpm remove-active-admin com.example.controller_tablet/.AdminReceiver
//
// =============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const IdlePage(),
    );
  }
}

class IdlePage extends StatefulWidget {
  const IdlePage({super.key});

  @override
  State<IdlePage> createState() => _IdlePageState();
}

class _IdlePageState extends State<IdlePage> {
  int _tapCount = 0;
  DateTime? _lastTap;

  void _onLeftTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 2) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= 8) {
      _tapCount = 0;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TestPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ElevatedButton(onPressed: () {}, child: const Text('체험 시작')),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onLeftTap,
            ),
          ),
        ],
      ),
    );
  }
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  // --- 네이티브 채널 (키오스크 모드용) ---
  static const _platform = MethodChannel('com.example.controller_tablet/kiosk');

  String _targetIp = '192.168.240.255';
  int _targetPort = 4210;
  String _status = '대기 중';
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _readyTimerController;
  late TextEditingController _playTimerController;
  late TextEditingController _endTimerController;

  // --- 세팅 토글 상태 ---
  bool _kioskMode = false; // 키오스크 모드 (홈/뒤로가기 차단)
  bool _landscapeMode = false; // 가로 고정 모드
  bool _wakeLock = false; // 화면 꺼짐 방지
  bool _isDeviceOwner = false; // Device Owner 등록 여부

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: _targetIp);
    _portController = TextEditingController(text: _targetPort.toString());
    _readyTimerController = TextEditingController();
    _playTimerController = TextEditingController();
    _endTimerController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('target_ip');
    final savedPort = prefs.getInt('target_port');
    final readyTimer = prefs.getInt('timer_ready');
    final playTimer = prefs.getInt('timer_play');
    final endTimer = prefs.getInt('timer_end');
    final kiosk = prefs.getBool('kiosk_mode') ?? false;
    final landscape = prefs.getBool('landscape_mode') ?? false;
    final wake = prefs.getBool('wake_lock') ?? false;

    setState(() {
      if (savedIp != null) {
        _targetIp = savedIp;
        _ipController.text = savedIp;
      }
      if (savedPort != null) {
        _targetPort = savedPort;
        _portController.text = savedPort.toString();
      }
      _readyTimerController.text = (readyTimer ?? 10).toString();
      _playTimerController.text = (playTimer ?? 10).toString();
      _endTimerController.text = (endTimer ?? 10).toString();
      _kioskMode = kiosk;
      _landscapeMode = landscape;
      _wakeLock = wake;
    });

    // Device Owner 상태 확인
    try {
      _isDeviceOwner = await _platform.invokeMethod('isDeviceOwner') ?? false;
    } on PlatformException {
      _isDeviceOwner = false;
    }
    if (mounted) setState(() {});

    // 저장된 상태 복원 적용
    if (_kioskMode) _setKioskMode(true);
    if (_landscapeMode) _setLandscapeMode(true);
    if (_wakeLock) _setWakeLock(true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4210;
    final readyTimer = int.tryParse(_readyTimerController.text.trim()) ?? 10;
    final playTimer = int.tryParse(_playTimerController.text.trim()) ?? 10;
    final endTimer = int.tryParse(_endTimerController.text.trim()) ?? 10;
    await prefs.setString('target_ip', ip);
    await prefs.setInt('target_port', port);
    await prefs.setInt('timer_ready', readyTimer);
    await prefs.setInt('timer_play', playTimer);
    await prefs.setInt('timer_end', endTimer);
    setState(() {
      _targetIp = ip;
      _targetPort = port;
    });
    if (mounted) FocusScope.of(context).unfocus();
  }

  // =====================================================
  // 키오스크 모드 — startLockTask (완전 잠금)
  // ON → 홈/뒤로/최근앱 차단 + 시스템바 숨김 + 전원버튼 화면복귀
  // OFF → 모두 해제
  // ※ Device Owner 필요 (USB로 한 번만 실행):
  //   adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
  // =====================================================
  Future<void> _setKioskMode(bool enable) async {
    try {
      await _platform.invokeMethod(enable ? 'startKiosk' : 'stopKiosk');
    } on PlatformException catch (e) {
      debugPrint('키오스크 모드 오류: $e');
    }
  }

  // =====================================================
  // 가로 모드 고정
  // ON → 가로(landscape) 고정
  // OFF → 시스템 기본 (자동 회전)
  // =====================================================
  Future<void> _setLandscapeMode(bool enable) async {
    if (enable) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  // =====================================================
  // 화면 꺼짐 방지 (WakeLock)
  // ON → 화면이 절대 꺼지지 않음
  // OFF → 시스템 기본 타임아웃 따름
  // =====================================================
  Future<void> _setWakeLock(bool enable) async {
    if (enable) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  Future<void> _toggleKiosk(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kiosk_mode', value);
    setState(() => _kioskMode = value);
    await _setKioskMode(value);
  }

  Future<void> _toggleLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('landscape_mode', value);
    setState(() => _landscapeMode = value);
    await _setLandscapeMode(value);
  }

  Future<void> _toggleWakeLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_lock', value);
    setState(() => _wakeLock = value);
    await _setWakeLock(value);
  }

  Future<void> _openAppSettings() async {
    try {
      await _platform.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      debugPrint('설정 열기 오류: $e');
    }
  }

  Future<void> _sendUdp(String command) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final data = utf8.encode(command);
      socket.send(data, InternetAddress(_targetIp), _targetPort);
      socket.close();
      setState(() {
        _status = command == 'N' ? '모터 ON 전송됨' : '모터 OFF 전송됨';
      });
    } catch (e) {
      setState(() {
        _status = '전송 실패: $e';
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _readyTimerController.dispose();
    _playTimerController.dispose();
    _endTimerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 키오스크 모드 ON이면 뒤로가기(백버튼) 차단
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('테스트'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Text(
                  _status,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP',
                          hintText: '192.168.240.255',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveSettings(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: '포트',
                          hintText: '4210',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveSettings(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: _saveSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '현재: $_targetIp:$_targetPort',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _readyTimerController,
                        decoration: const InputDecoration(
                          labelText: 'READY (초)',
                          hintText: '10',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveSettings(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _playTimerController,
                        decoration: const InputDecoration(
                          labelText: 'PLAY (초)',
                          hintText: '10',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveSettings(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endTimerController,
                        decoration: const InputDecoration(
                          labelText: 'END (초)',
                          hintText: '10',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveSettings(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => _sendUdp('N'),
                  child: const Text('온'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => _sendUdp('F'),
                  child: const Text('오프'),
                ),

                // === 세팅 토글 영역 ===
                const SizedBox(height: 40),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '세팅',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),

                // 키오스크 모드 토글
                SwitchListTile(
                  title: const Text('키오스크 모드'),
                  subtitle: Text(
                    _isDeviceOwner
                        ? '홈/뒤로/최근앱 차단 + 전원버튼 복귀'
                        : 'Device Owner 미등록 (adb 설정 필요)',
                  ),
                  value: _kioskMode,
                  onChanged: _toggleKiosk,
                ),

                // 가로 모드 토글
                SwitchListTile(
                  title: const Text('가로 모드 고정'),
                  subtitle: const Text('화면 가로 방향 고정'),
                  value: _landscapeMode,
                  onChanged: _toggleLandscape,
                ),

                // 화면 꺼짐 방지 토글
                SwitchListTile(
                  title: const Text('화면 꺼짐 방지'),
                  subtitle: const Text('화면이 절대 꺼지지 않음'),
                  value: _wakeLock,
                  onChanged: _toggleWakeLock,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('앱 권한 설정'),
                  subtitle: const Text('시스템 권한 설정 화면으로 이동'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _openAppSettings,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.tv),
                    label: const Text('전시화면으로', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
