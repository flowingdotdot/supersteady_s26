import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'udp_controller.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  // --- 컬러 팔레트 ---
  static const _green = Color(0xFF6A7E3F);
  static const _greenLight = Color(0xFF8BA55A);
  static const _greenDark = Color(0xFF4E5E2D);
  static const _bgDark = Color(0xFF2A2A2A);
  static const _cardDark = Color(0xFF363636);
  static const _textWhite = Color(0xFFF0F0F0);
  static const _textGray = Color(0xFF9E9E9E);

  // --- 네이티브 채널 (키오스크 모드용) ---
  static const _platform = MethodChannel('com.example.controller_tablet/kiosk');

  final _udp = UdpController.instance;
  String _status = '대기 중';
  String _lastReceived = '';
  StreamSubscription<String>? _udpSubscription;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _readyTimerController;
  late TextEditingController _playTimerController;
  late TextEditingController _endTimerController;

  // --- 세팅 토글 상태 ---
  bool _kioskMode = false;
  bool _landscapeMode = false;
  bool _wakeLock = false;
  bool _debugMode = false;

  // --- 이동 버튼 반복 전송용 ---
  Timer? _moveTimer;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: _udp.targetIp);
    _portController = TextEditingController(text: _udp.targetPort.toString());
    _readyTimerController = TextEditingController();
    _playTimerController = TextEditingController();
    _endTimerController = TextEditingController();
    _udpSubscription = _udp.onReceive.listen((msg) {
      setState(() => _lastReceived = msg);
    });
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
    final debug = prefs.getBool('debug_mode') ?? false;

    setState(() {
      if (savedIp != null) {
        _udp.targetIp = savedIp;
        _ipController.text = savedIp;
      }
      if (savedPort != null) {
        _udp.targetPort = savedPort;
        _portController.text = savedPort.toString();
      }
      _readyTimerController.text = (readyTimer ?? 120).toString();
      _playTimerController.text = (playTimer ?? 14).toString();
      _endTimerController.text = (endTimer ?? 120).toString();
      _kioskMode = kiosk;
      _landscapeMode = landscape;
      _wakeLock = wake;
      _debugMode = debug;
    });

    // 저장된 상태 복원 적용
    if (_kioskMode) _setKioskMode(true);
    if (_landscapeMode) _setLandscapeMode(true);
    if (_wakeLock) _setWakeLock(true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 10025;
    final readyTimer = int.tryParse(_readyTimerController.text.trim()) ?? 120;
    final playTimer = int.tryParse(_playTimerController.text.trim()) ?? 14;
    final endTimer = int.tryParse(_endTimerController.text.trim()) ?? 120;
    await prefs.setString('target_ip', ip);
    await prefs.setInt('target_port', port);
    await prefs.setInt('timer_ready', readyTimer);
    await prefs.setInt('timer_play', playTimer);
    await prefs.setInt('timer_end', endTimer);
    _udp.targetIp = ip;
    _udp.targetPort = port;
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _setKioskMode(bool enable) async {
    try {
      await _platform.invokeMethod(enable ? 'startKiosk' : 'stopKiosk');
    } on PlatformException catch (e) {
      debugPrint('키오스크 모드 오류: $e');
    }
  }

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

  Future<void> _toggleDebugMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_mode', value);
    setState(() => _debugMode = value);
  }

  Future<void> _openAppSettings() async {
    try {
      await _platform.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      debugPrint('설정 열기 오류: $e');
    }
  }

  void _showCalibrationDialog() {
    _sendUdp(UdpCommand.calibrate);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String lastSignal = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void sendAndShow(String command) {
              _sendUdpFast(command);
              setDialogState(() => lastSignal = command);
            }

            return Dialog(
              backgroundColor: _cardDark,
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '영점 셋팅',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _textWhite,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '왼쪽/오른쪽을 누르면 모터가 해당 방향으로 회전합니다.\n멈추고 싶을 때 멈춤을 눌러주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: _textGray),
                      ),
                      const SizedBox(height: 12),
                      // 신호 표시
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          lastSignal.isEmpty
                              ? '대기 중'
                              : '전송: $lastSignal (${UdpCommand.nameOf(lastSignal)})',
                          style: TextStyle(
                            fontSize: 14,
                            color: lastSignal == 'S'
                                ? Colors.orange
                                : _greenLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _calibBtn(
                            ' 왼쪽',
                            () => sendAndShow('L'),
                            icon: Icons.arrow_back,
                          ),
                          _calibBtn(
                            '멈춤',
                            () => sendAndShow('S'),
                            icon: Icons.stop,
                            isStop: true,
                          ),
                          _calibBtn(
                            '오른쪽 ',
                            () => sendAndShow('R'),
                            icon: Icons.arrow_forward,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _sendUdp(UdpCommand.saveOrigin);
                            setDialogState(() => lastSignal = 'O');
                            Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: _textWhite,
                          ),
                          child: const Text(
                            '현재값 원점 저장',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                          },
                          child: const Text(
                            '닫기',
                            style: TextStyle(fontSize: 16, color: _textGray),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _startMoving(String command) {
    _sendUdpFast(command);
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendUdpFast(command);
    });
  }

  void _stopMoving() {
    _moveTimer?.cancel();
    _moveTimer = null;
    // 멈춤 명령 3회 연속 전송 — 확실하게 정지시키기 위해
    _sendUdpFast(UdpCommand.stop);
    _sendUdpFast(UdpCommand.stop);
    _sendUdpFast(UdpCommand.stop);
  }

  // Widget _moveButton(String label, String command) {
  //   return Listener(
  //     behavior: HitTestBehavior.opaque,
  //     onPointerDown: (_) => _startMoving(command),
  //     // onPointerUp: (_) => _stopMoving(),
  //     // onPointerCancel: (_) => _stopMoving(),
  //     child: Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  //       decoration: BoxDecoration(
  //         color: _greenDark,
  //         borderRadius: BorderRadius.circular(8),
  //       ),
  //       child: Text(
  //         label,
  //         style: const TextStyle(fontSize: 18, color: _textWhite),
  //       ),
  //     ),
  //   );
  // }

  /// 즉시 전송 (await 없이 fire-and-forget) — 왼쪽/오른쪽/멈춤 등 반응속도 중요한 곳용
  void _sendUdpFast(String command) {
    _udp.sendFast(command);
  }

  Future<void> _sendUdp(String command) async {
    try {
      await _udp.send(command);
      setState(() {
        _status = command == 'N'
            ? '모터 ON 전송됨'
            : command == 'F'
            ? '모터 OFF 전송됨'
            : '리셋 전송됨';
      });
    } catch (e) {
      setState(() {
        _status = '전송 실패: $e';
      });
    }
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _udpSubscription?.cancel();
    _ipController.dispose();
    _portController.dispose();
    _readyTimerController.dispose();
    _playTimerController.dispose();
    _endTimerController.dispose();
    super.dispose();
  }

  InputDecoration _inputDeco(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _greenLight),
      hintStyle: const TextStyle(color: _textGray),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _textGray),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _green, width: 2),
      ),
      filled: true,
      fillColor: _cardDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bgDark,
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _green : _textGray,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? _greenLight.withValues(alpha: 0.4)
                : _cardDark,
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _cardDark,
          foregroundColor: _textWhite,
          title: const Text('관리자'),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // UDP 수신 표시
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _lastReceived.isEmpty
                          ? _cardDark
                          : Colors.blue.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _lastReceived.isEmpty
                          ? '수신 대기 중'
                          : '수신: $_lastReceived (${UdpCommand.nameOf(_lastReceived)})',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _lastReceived.isEmpty
                            ? _textGray
                            : Colors.lightBlueAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 전송 상태 표시
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _cardDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _greenLight,
                      ),
                    ),
                  ),

                  // --- 네트워크 설정 ---
                  const SizedBox(height: 24),
                  _sectionLabel('네트워크'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          decoration: _inputDeco('IP', '192.168.240.255'),
                          style: const TextStyle(color: _textWhite),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portController,
                          decoration: _inputDeco('포트', '10025'),
                          style: const TextStyle(color: _textWhite),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.save, color: _green),
                        onPressed: _saveSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '현재: ${_udp.targetIp}:${_udp.targetPort}',
                    style: const TextStyle(color: _textGray, fontSize: 12),
                  ),

                  // --- 타이머 설정 ---
                  const SizedBox(height: 24),
                  _sectionLabel('타이머 (초)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _readyTimerController,
                          decoration: _inputDeco('READY', '120'),
                          style: const TextStyle(color: _textWhite),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _playTimerController,
                          decoration: _inputDeco('PLAY', '14'),
                          style: const TextStyle(color: _textWhite),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _endTimerController,
                          decoration: _inputDeco('END', '120'),
                          style: const TextStyle(color: _textWhite),
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                    ],
                  ),

                  // --- 모터 제어 ---
                  const SizedBox(height: 32),
                  _sectionLabel('모터 제어'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: GestureDetector(
                            onTapDown: (_) => _sendUdp('N'),
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: _textWhite,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'ON',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: GestureDetector(
                            onTapDown: (_) => _sendUdp('F'),
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _cardDark,
                                foregroundColor: _textWhite,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: _textGray),
                                ),
                              ),
                              child: const Text(
                                'OFF',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _showCalibrationDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _greenDark,
                              foregroundColor: _textWhite,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              '영점세팅',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // --- 세팅 ---
                  const SizedBox(height: 32),
                  const Divider(color: _textGray, height: 1),
                  const SizedBox(height: 16),
                  _sectionLabel('세팅'),
                  const SizedBox(height: 8),
                  _settingTile(
                    '키오스크 모드',
                    '전체화면 + 시스템바 숨김',
                    _kioskMode,
                    _toggleKiosk,
                  ),
                  _settingTile(
                    '가로 모드 고정',
                    '화면 가로 방향 고정',
                    _landscapeMode,
                    _toggleLandscape,
                  ),
                  _settingTile(
                    '화면 꺼짐 방지',
                    '화면이 절대 꺼지지 않음',
                    _wakeLock,
                    _toggleWakeLock,
                  ),
                  _settingTile(
                    '디버그 모드',
                    '전시화면에 상태/타이머/UDP 정보 표시',
                    _debugMode,
                    _toggleDebugMode,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.settings, color: _textGray),
                    title: const Text(
                      '앱 권한 설정',
                      style: TextStyle(color: _textWhite),
                    ),
                    subtitle: const Text(
                      '시스템 권한 설정 화면으로 이동',
                      style: TextStyle(color: _textGray),
                    ),
                    trailing: const Icon(Icons.open_in_new, color: _textGray),
                    onTap: _openAppSettings,
                  ),

                  // --- 전시화면 버튼 ---
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.tv),
                      label: const Text(
                        '전시화면으로',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: _textWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _calibBtn(
    String label,
    VoidCallback onTap, {
    IconData? icon,
    bool isStop = false,
  }) {
    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isStop ? Colors.red.shade800 : _greenDark,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: _textWhite, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 18, color: _textWhite),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _greenLight,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _settingTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: _textWhite)),
      subtitle: Text(subtitle, style: const TextStyle(color: _textGray)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: _green,
    );
  }
}
