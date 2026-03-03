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

// A를 수신했을때 화면을 넘어가도록 - 시작버튼 , 종료 버튼

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum AppState { idle, ready, play, end }

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
      home: const ExhibitionPage(),
    );
  }
}

class ExhibitionPage extends StatefulWidget {
  const ExhibitionPage({super.key});

  @override
  State<ExhibitionPage> createState() => _ExhibitionPageState();
}

class _ExhibitionPageState extends State<ExhibitionPage> {
  final PageController _pageController = PageController();
  AppState _state = AppState.idle;
  Timer? _timer;
  int _remaining = 0;

  // 타이머 기본값 (SharedPreferences에서 로드)
  int _readySeconds = 10;
  int _playSeconds = 10;
  int _endSeconds = 10;

  // UDP 전송용
  String _targetIp = '192.168.240.255';
  int _targetPort = 4210;

  // 모든 에셋 이미지 (시작 시 미리 로드)
  static const _allImages = [
    AssetImage('assets/images/h1_idle.png'),
    AssetImage('assets/images/h2_ready.png'),
    AssetImage('assets/images/h3_ready.png'),
    AssetImage('assets/images/h4_ready.png'),
    AssetImage('assets/images/h5_ready.png'),
    AssetImage('assets/images/h6_ready.png'),
    AssetImage('assets/images/h7_play.png'),
    AssetImage('assets/images/h8_end.png'),
    AssetImage('assets/images/h9_end.png'),
    AssetImage('assets/images/h10_end.png'),
  ];

  // 이미지 로딩 완료 여부
  bool _imagesLoaded = false;

  // 슬라이드 컨트롤러
  final PageController _readyPageController = PageController();
  final PageController _endPageController = PageController();

  // 버튼 탭 피드백
  bool _idlePressed = false;
  bool _readyExitPressed = false;
  bool _readyStartPressed = false;
  bool _readyPrevPressed = false;
  bool _readyNextPressed = false;
  bool _playExitPressed = false;
  bool _playNextPressed = false;
  bool _endExitPressed = false;
  bool _endPrevPressed = false;
  bool _endNextPressed = false;
  bool _endHomePressed = false;

  // 숨겨진 관리자 진입용
  int _tapCount = 0;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _loadTimerSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesLoaded) {
      _precacheAllImages();
    }
  }

  Future<void> _precacheAllImages() async {
    await Future.wait(_allImages.map((img) => precacheImage(img, context)));
    if (mounted) setState(() => _imagesLoaded = true);
  }

  Future<void> _loadTimerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _readySeconds = prefs.getInt('timer_ready') ?? 10;
      _playSeconds = prefs.getInt('timer_play') ?? 10;
      _endSeconds = prefs.getInt('timer_end') ?? 10;
      _targetIp = prefs.getString('target_ip') ?? '192.168.240.255';
      _targetPort = prefs.getInt('target_port') ?? 4210;
    });
  }

  Future<void> _sendUdp(String command) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        utf8.encode(command),
        InternetAddress(_targetIp),
        _targetPort,
      );
      socket.close();
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
    }
  }

  void _goTo(AppState newState) {
    _timer?.cancel();
    setState(() {
      _state = newState;
    });
    _pageController.animateToPage(
      newState.index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    // IDLE이 아니면 타이머 시작
    if (newState != AppState.idle) {
      final seconds = switch (newState) {
        AppState.ready => _readySeconds,
        AppState.play => _playSeconds,
        AppState.end => _endSeconds,
        _ => 10,
      };

      _remaining = seconds;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _remaining--);
        if (_remaining <= 0) {
          t.cancel();
          if (_state == AppState.play) {
            // PLAY 타이머 만료 → UDP 'F' 전송만 (페이지 이동 없음)
            _sendUdp('F');
          } else if (_state == AppState.ready) {
            // Ready 타이머 만료 → UDP 'J' 전송만 (페이지 이동 없음)
            _sendUdp('J');
          } else {
            // End 타이머 만료 → UDP 'J' 전송 후 IDLE로
            _sendUdp('J').then((_) => _goTo(AppState.idle));
          }
        }
      });
    }
  }

  void _resetTimer() {
    if (_state == AppState.idle) return;
    _timer?.cancel();
    final seconds = switch (_state) {
      AppState.ready => _readySeconds,
      AppState.play => _playSeconds,
      AppState.end => _endSeconds,
      _ => 10,
    };
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        if (_state == AppState.play) {
          _sendUdp('F').then((_) => _goTo(AppState.end));
        } else if (_state == AppState.ready) {
          // Ready 타이머 만료 → UDP 'J' 전송만 (페이지 이동 없음)
          _sendUdp('J');
        } else {
          // End 타이머 만료 → UDP 'J' 전송 후 IDLE로
          _sendUdp('J').then((_) => _goTo(AppState.idle));
        }
      }
    });
  }

  void _onAdminTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 2) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= 8) {
      _tapCount = 0;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TestPage()))
          .then((_) => _loadTimerSettings()); // 테스트 페이지에서 돌아오면 타이머 설정 새로고침
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    _readyPageController.dispose();
    _endPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_imagesLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildIdlePage(),
                    _buildReadyPage(),
                    _buildPlayPage(),
                    _buildEndPage(),
                  ],
                ),
                // 좌측 상단 숨겨진 영역 — 8번 탭하면 테스트 페이지
                Positioned(
                  left: 0,
                  top: 0,
                  width: 60,
                  height: 60,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _onAdminTap,
                  ),
                ),
              ],
            ),
    );
  }

  // === IDLE 화면 ===
  Widget _buildIdlePage() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: _allImages[0], // 1_idle.jpg
          fit: BoxFit.cover,
        ),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 132),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _idlePressed = true),
            onTapUp: (_) async {
              setState(() => _idlePressed = false);
              await _sendUdp('O');
              _goTo(AppState.ready);
            },
            onTapCancel: () => setState(() => _idlePressed = false),
            child: Container(
              width: 370,
              height: 85,
              decoration: BoxDecoration(
                color: _idlePressed
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
            ),
          ),
        ),
      ),
    );
  }

  // === READY 화면 (2_ready ~ 6_ready 슬라이드, 6_ready에만 시작 버튼) ===
  Widget _buildReadyPage() {
    final readyImages = _allImages.sublist(1, 6); // 2_ready ~ 6_ready
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          PageView(
            controller: _readyPageController,
            children: [
              for (int i = 0; i < readyImages.length; i++)
                Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: readyImages[i],
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: i == readyImages.length - 1
                      ? Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 114,
                              bottom: 98,
                            ),
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _readyStartPressed = true),
                              onTapUp: (_) async {
                                setState(() => _readyStartPressed = false);
                                await _sendUdp('N');
                                _goTo(AppState.play);
                              },
                              onTapCancel: () =>
                                  setState(() => _readyStartPressed = false),
                              child: Container(
                                width: 370,
                                height: 85,
                                decoration: BoxDecoration(
                                  color: _readyStartPressed
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
          // 좌측 중앙 이전 버튼
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _readyPrevPressed = true),
                onTapUp: (_) {
                  setState(() => _readyPrevPressed = false);
                  _readyPageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                onTapCancel: () => setState(() => _readyPrevPressed = false),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _readyPrevPressed
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // 우측 중앙 다음 버튼
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _readyNextPressed = true),
                onTapUp: (_) {
                  setState(() => _readyNextPressed = false);
                  _readyPageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                onTapCancel: () => setState(() => _readyNextPressed = false),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _readyNextPressed
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // 우측 상단 IDLE 복귀 버튼
          Positioned(
            top: 32,
            right: 32,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _readyExitPressed = true),
              onTapUp: (_) async {
                setState(() => _readyExitPressed = false);
                await _sendUdp('I');
                _goTo(AppState.idle);
              },
              onTapCancel: () => setState(() => _readyExitPressed = false),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _readyExitPressed
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === PLAY 화면 (터치해도 타이머 리셋 없음 — 무조건 END로 전환) ===
  Widget _buildPlayPage() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: _allImages[6], // 7_play.jpg
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          // 우측 상단 IDLE 복귀 버튼
          Positioned(
            top: 32,
            right: 32,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _playExitPressed = true),
              onTapUp: (_) async {
                setState(() => _playExitPressed = false);
                await _sendUdp('F');
                _goTo(AppState.idle);
              },
              onTapCancel: () => setState(() => _playExitPressed = false),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _playExitPressed
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          // 우측 중앙 다음(END) 버튼
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _playNextPressed = true),
                onTapUp: (_) {
                  setState(() => _playNextPressed = false);
                  _goTo(AppState.end);
                },
                onTapCancel: () => setState(() => _playNextPressed = false),
                child: Container(
                  width: 160,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _playNextPressed
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === END 화면 (8_end ~ 10_end 슬라이드, 10_end에 첫화면 버튼) ===
  Widget _buildEndPage() {
    final endImages = _allImages.sublist(7, 10); // 8_end ~ 10_end
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          PageView(
            controller: _endPageController,
            children: [
              for (int i = 0; i < endImages.length; i++)
                Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: endImages[i],
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: i == endImages.length - 1
                      ? Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 70),
                            child: GestureDetector(
                              onTapDown: (_) {
                                setState(() => _endHomePressed = true);
                                HapticFeedback.lightImpact();
                              },
                              onTapUp: (_) async {
                                setState(() => _endHomePressed = false);
                                await _sendUdp('I');
                                _goTo(AppState.idle);
                              },
                              onTapCancel: () =>
                                  setState(() => _endHomePressed = false),
                              child: Container(
                                width: 570,
                                height: 95,
                                decoration: BoxDecoration(
                                  color: _endHomePressed
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
          // 우측 상단 IDLE 복귀 버튼 (h8_end에서만 표시)
          Positioned(
            top: 32,
            right: 32,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _endExitPressed = true),
              onTapUp: (_) async {
                setState(() => _endExitPressed = false);
                await _sendUdp('I');
                _goTo(AppState.idle);
              },
              onTapCancel: () => setState(() => _endExitPressed = false),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _endExitPressed
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          // 좌측 중앙 이전 버튼
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _endPrevPressed = true),
                onTapUp: (_) {
                  setState(() => _endPrevPressed = false);
                  _endPageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                onTapCancel: () => setState(() => _endPrevPressed = false),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _endPrevPressed
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          // 우측 중앙 다음 버튼
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _endNextPressed = true),
                onTapUp: (_) {
                  setState(() => _endNextPressed = false);
                  _endPageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                onTapCancel: () => setState(() => _endNextPressed = false),
                child: Container(
                  width: 160,
                  height: 100,
                  decoration: BoxDecoration(
                    color: _endNextPressed
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
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
  int _targetPort = 10025;
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

  Future<void> _clearDeviceOwner() async {
    try {
      await _platform.invokeMethod('clearDeviceOwner');
      setState(() => _isDeviceOwner = false);
    } on PlatformException catch (e) {
      debugPrint('Device Owner 해제 오류: $e');
    }
  }

  Future<void> sendUdp(String command) async {
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
                  onPressed: () => sendUdp('N'),
                  child: const Text('온'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => sendUdp('F'),
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
                if (_isDeviceOwner)
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Device Owner 해제'),
                    subtitle: const Text('해제 후 앱 삭제/재설치 가능'),
                    trailing: const Icon(Icons.warning, color: Colors.red),
                    onTap: _clearDeviceOwner,
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
