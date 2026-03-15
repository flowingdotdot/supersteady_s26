import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'test_page.dart';
import 'udp_service.dart';
import 'widgets/exit_button.dart';
import 'widgets/page_nav_button.dart';

enum AppState { idle, ready, play, end }

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
  int _targetPort = 10025;

  // 네이티브 채널 (키오스크 모드용)
  static const _platform = MethodChannel('com.example.controller_tablet/kiosk');

  // 모든 에셋 이미지 (시작 시 미리 로드)
  static const _allImages = [
    // AssetImage('assets/images/h1_idle.png'),
    // AssetImage('assets/images/h2_ready.png'),
    // AssetImage('assets/images/h3_ready.png'),
    // AssetImage('assets/images/h4_ready.png'),
    // AssetImage('assets/images/h5_ready.png'),
    // AssetImage('assets/images/h6_ready.png'),
    // AssetImage('assets/images/h7_play.png'),
    // AssetImage('assets/images/h8_end.png'),
    // AssetImage('assets/images/h9_end.png'),
    // AssetImage('assets/images/h10_end.png'),
    AssetImage('assets/images/p2_1_idle.png'),
    AssetImage('assets/images/p2_2_ready.png'),
    AssetImage('assets/images/p2_3_ready.png'),
    AssetImage('assets/images/p2_4_ready.png'),
    AssetImage('assets/images/p2_5_ready.png'),
    AssetImage('assets/images/p2_6_ready.png'),
    AssetImage('assets/images/p2_7_play.png'),
    AssetImage('assets/images/p2_8_end.png'),
    AssetImage('assets/images/p2_9_end.png'),
    AssetImage('assets/images/p2_10_end.png'),
  ];

  // 이미지 로딩 완료 여부
  bool _imagesLoaded = false;

  // 슬라이드 컨트롤러
  final PageController _readyPageController = PageController();
  final PageController _endPageController = PageController();

  // 버튼 탭 피드백
  bool _idlePressed = false;
  bool _readyStartPressed = false;
  bool _endHomePressed = false;

  // Play 타이머 만료 여부 (만료 전까지 다음 버튼 비활성화)
  bool _playTimerExpired = false;

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
      _readySeconds = prefs.getInt('timer_ready') ?? 120;
      _playSeconds = prefs.getInt('timer_play') ?? 14;
      _endSeconds = prefs.getInt('timer_end') ?? 120;
      _targetIp = prefs.getString('target_ip') ?? '192.168.240.255';
      _targetPort = prefs.getInt('target_port') ?? 10025;
    });

    // 저장된 세팅 복원 적용
    if (prefs.getBool('kiosk_mode') ?? false) {
      try {
        await _platform.invokeMethod('startKiosk');
      } on PlatformException catch (_) {}
    }
    if (prefs.getBool('landscape_mode') ?? false) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (prefs.getBool('wake_lock') ?? false) {
      await WakelockPlus.enable();
    }
  }

  Future<void> _sendUdp(String command) async {
    await UdpService.send(command, _targetIp, _targetPort);
  }

  void _goTo(AppState newState) {
    _timer?.cancel();
    setState(() {
      _state = newState;
      if (newState == AppState.play) _playTimerExpired = false;
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
            _sendUdp('F');
            setState(() => _playTimerExpired = true);
          } else {
            _sendUdp('I').then((_) => _goTo(AppState.idle));
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
          _sendUdp('F');
          setState(() => _playTimerExpired = true);
        } else {
          _sendUdp('I').then((_) => _goTo(AppState.idle));
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
          .then((_) => _loadTimerSettings());
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
        image: DecorationImage(image: _allImages[0], fit: BoxFit.cover),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 132),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _idlePressed = true),
            onTapUp: (_) {
              setState(() => _idlePressed = false);
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
    final readyImages = _allImages.sublist(1, 6);
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
                            child: Listener(
                              onPointerDown: (_) async {
                                setState(() => _readyStartPressed = true);
                                await _sendUdp('N');
                                _goTo(AppState.play);
                              },
                              onPointerUp: (_) =>
                                  setState(() => _readyStartPressed = false),
                              onPointerCancel: (_) =>
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
          PageNavButton(
            isLeft: true,
            onTap: () => _readyPageController.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
          ),
          // 우측 중앙 다음 버튼
          PageNavButton(
            isLeft: false,
            onTap: () => _readyPageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
          ),
          // 우측 상단 IDLE 복귀 버튼
          ExitButton(
            onTap: () async {
              await _sendUdp('I');
              _goTo(AppState.idle);
            },
          ),
        ],
      ),
    );
  }

  // === PLAY 화면 (터치해도 타이머 리셋 없음 — 무조건 END로 전환) ===
  Widget _buildPlayPage() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(image: _allImages[6], fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          // 우측 상단 IDLE 복귀 버튼
          ExitButton(
            onTap: () async {
              await _sendUdp('F');
              _goTo(AppState.idle);
            },
          ),
          // 우측 중앙 다음(END) 버튼 — 타이머 만료 후에만 활성화
          if (_playTimerExpired)
            PageNavButton(isLeft: false, onTap: () => _goTo(AppState.end)),
        ],
      ),
    );
  }

  // === END 화면 (8_end ~ 10_end 슬라이드, 10_end에 첫화면 버튼) ===
  Widget _buildEndPage() {
    final endImages = _allImages.sublist(7, 10);
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
          // 우측 상단 IDLE 복귀 버튼
          ExitButton(
            onTap: () async {
              await _sendUdp('I');
              _goTo(AppState.idle);
            },
          ),
          // 좌측 중앙 이전 버튼
          PageNavButton(
            isLeft: true,
            onTap: () => _endPageController.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
          ),
          // 우측 중앙 다음 버튼
          PageNavButton(
            isLeft: false,
            onTap: () => _endPageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    );
  }
}
