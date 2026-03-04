import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'udp_service.dart';

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

  String _targetIp = '192.168.240.255';
  int _targetPort = 10025;
  String _status = '대기 중';
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _readyTimerController;
  late TextEditingController _playTimerController;
  late TextEditingController _endTimerController;

  // --- 세팅 토글 상태 ---
  bool _kioskMode = false;
  bool _landscapeMode = false;
  bool _wakeLock = false;

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
      _readyTimerController.text = (readyTimer ?? 120).toString();
      _playTimerController.text = (playTimer ?? 14).toString();
      _endTimerController.text = (endTimer ?? 120).toString();
      _kioskMode = kiosk;
      _landscapeMode = landscape;
      _wakeLock = wake;
    });

    // 저장된 상태 복원 적용
    if (_kioskMode) _setKioskMode(true);
    if (_landscapeMode) _setLandscapeMode(true);
    if (_wakeLock) _setWakeLock(true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4210;
    final readyTimer = int.tryParse(_readyTimerController.text.trim()) ?? 120;
    final playTimer = int.tryParse(_playTimerController.text.trim()) ?? 14;
    final endTimer = int.tryParse(_endTimerController.text.trim()) ?? 120;
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
      builder: (ctx) => Dialog(
        backgroundColor: _cardDark,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTapDown: (_) => _sendUdp(UdpCommand.moveLeft),
                      onTapUp: (_) => _sendUdp(UdpCommand.stop),
                      onTapCancel: () => _sendUdp(UdpCommand.stop),
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _greenDark,
                          foregroundColor: _textWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        child: const Text(
                          '< 왼쪽',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),

                    GestureDetector(
                      onTapDown: (_) => _sendUdp(UdpCommand.moveRight),
                      onTapUp: (_) => _sendUdp(UdpCommand.stop),
                      onTapCancel: () => _sendUdp(UdpCommand.stop),
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _greenDark,
                          foregroundColor: _textWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        child: const Text(
                          '오른쪽 >',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _sendUdp(UdpCommand.saveOrigin),
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
                      _sendUdp(UdpCommand.stop);
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
      ),
    );
  }

  Future<void> _sendUdp(String command) async {
    try {
      await UdpService.send(command, _targetIp, _targetPort);
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
                  // 상태 표시
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
                          decoration: _inputDeco('포트', '4210'),
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
                    '현재: $_targetIp:$_targetPort',
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
                          child: ElevatedButton(
                            onPressed: () => _sendUdp('N'),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => _sendUdp('F'),
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
