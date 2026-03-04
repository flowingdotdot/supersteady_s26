import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_page.dart';
import 'udp_service.dart';

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
      _readySeconds = prefs.getInt('timer_ready') ?? 10;
      _playSeconds = prefs.getInt('timer_play') ?? 10;
      _endSeconds = prefs.getInt('timer_end') ?? 10;
      _targetIp = prefs.getString('target_ip') ?? '192.168.240.255';
      _targetPort = prefs.getInt('target_port') ?? 4210;
    });
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
        image: DecorationImage(
          image: _allImages[0],
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
          image: _allImages[6],
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
          // 우측 중앙 다음(END) 버튼 — 타이머 만료 후에만 활성화
          if (_playTimerExpired)
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
