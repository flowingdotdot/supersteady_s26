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

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => _sendUdp('I'),
                  child: const Text('리셋'),
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
                SwitchListTile(
                  title: const Text('키오스크 모드'),
                  subtitle: const Text('전체화면 + 시스템바 숨김'),
                  value: _kioskMode,
                  onChanged: _toggleKiosk,
                ),
                SwitchListTile(
                  title: const Text('가로 모드 고정'),
                  subtitle: const Text('화면 가로 방향 고정'),
                  value: _landscapeMode,
                  onChanged: _toggleLandscape,
                ),
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
