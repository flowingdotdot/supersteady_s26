import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:video_player/video_player.dart';

import 'motor_controller.dart';
import 'test_page.dart';
import 'udp_controller.dart';
import 'widgets/exit_button.dart';
import 'widgets/idle_button.dart';
import 'widgets/page_nav_button.dart';
import 'widgets/start_button.dart';

enum AppState { idle, ready1, ready2, play, end, survey }

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
  int _surveySeconds = 10;

  // UDP 컨트롤러
  final _udp = UdpController.instance;
  final _motor = MotorController.instance;

  // 네이티브 채널 (키오스크 모드용)
  static const _platform = MethodChannel('com.example.controller_tablet/kiosk');

  // 모든 에셋 이미지 (시작 시 미리 로드)
  static const _allImages = [
    AssetImage('assets/images/survey/hongdae/1_1.png'),
  ];
  // 이미지 로딩 완료 여부
  bool _imagesLoaded = false;

  // 슬라이드 컨트롤러
  final PageController _surveyPageController = PageController();

  // Play 타이머 만료 여부 (만료 전까지 다음 버튼 비활성화)
  bool _playTimerExpired = false;

  // Ready 영상 1회 재생 완료 여부 (완료 후 시작 버튼 표시)
  bool _readyButtonVisible = false;

  // _goTo 중복 호출 방지
  bool _navigating = false;

  // ready 영상 13초 타이머
  Timer? _readyVideoTimer;
  bool _readyTimerActive = false;
  bool _ready2Resetting = false;

  // end 영상 6초 타이머
  Timer? _endUdpTimer;

  // keepalive 타이머
  Timer? _keepaliveTimer;

  // A신호 반복 타이머 + ACK 구독
  Timer? _aSignalTimer;
  StreamSubscription<String>? _ackSubscription;

  // 숨겨진 관리자 진입용
  int _tapCount = 0;
  DateTime? _lastTap;

  // 영상 컨트롤러
  late VideoPlayerController _idleVideoController;
  late VideoPlayerController _ready1VideoController;
  late VideoPlayerController _ready2VideoController;
  late VideoPlayerController _playVideoController;
  late VideoPlayerController _endVideoController;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _loadTimerSettings();
    _initVideos();
    _motor.setup();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _udp.sendToPort('K', _udp.commandPort);
    });
  }

  Future<void> _initVideos() async {
    final controllers = [
      _idleVideoController = VideoPlayerController.asset(
        'assets/videos/hongdae/idle_p1.mp4',
      ),
      _ready1VideoController = VideoPlayerController.asset(
        'assets/videos/hongdae/ready_p1.mp4',
      ),
      _ready2VideoController = VideoPlayerController.asset(
        'assets/videos/hongdae/ready_p2.mp4',
      ),

      _playVideoController = VideoPlayerController.asset(
        'assets/videos/hongdae/play_p1.mp4',
      ),
      _endVideoController = VideoPlayerController.asset(
        'assets/videos/hongdae/end_p1.mp4',
      ),
    ];
    await Future.wait(controllers.map((c) => c.initialize()));
    _idleVideoController.setLooping(true);
    _ready1VideoController.setLooping(false);
    _ready2VideoController.setLooping(false);
    _playVideoController.setLooping(false);
    _endVideoController.setLooping(false);

    _ready2VideoController.addListener(_onReady2VideoEnd);
    _playVideoController.addListener(_onPlayVideoEnd);
    _endVideoController.addListener(_onEndVideoEnd);
    _idleVideoController.play();
    if (mounted) setState(() {});
  }

  void _onReady2VideoEnd() {
    if (_ready2Resetting) return;
    if (_readyButtonVisible) return;
    final v = _ready2VideoController.value;
    if (!v.isInitialized || v.isPlaying) return;
    final remaining = v.duration - v.position;
    if (remaining < const Duration(milliseconds: 300) &&
        _state == AppState.ready2) {
      if (mounted) setState(() => _readyButtonVisible = true);
    }
  }

  void _onEndVideoEnd() {
    if (_navigating) return;
    final v = _endVideoController.value;
    if (!v.isInitialized || v.isPlaying) return;
    final remaining = v.duration - v.position;
    if (remaining < const Duration(milliseconds: 300) &&
        _state == AppState.end) {
      if (mounted) _goTo(AppState.survey);
    }
  }

  void _onPlayVideoEnd() {
    if (_navigating) return;
    final v = _playVideoController.value;
    if (!v.isInitialized || v.isPlaying) return;
    final remaining = v.duration - v.position;
    if (remaining < const Duration(milliseconds: 300) &&
        _state == AppState.play) {
      _sendUdp('F').then((_) {
        if (mounted) _goTo(AppState.end);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesLoaded) {
      _precacheAllImages();
    }
  }

  Future<void> _precacheAllImages() async {
    await Future.wait(
      _allImages.map((img) => precacheImage(img, context).catchError((_) {})),
    );
    if (mounted) setState(() => _imagesLoaded = true);
  }

  Future<void> _loadTimerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _readySeconds = prefs.getInt('timer_ready') ?? 180;
      _playSeconds = prefs.getInt('timer_play') ?? 15;
      _endSeconds = prefs.getInt('timer_end') ?? 180;
      _surveySeconds = prefs.getInt('timer_survey') ?? 180;
      _udp.targetIp = prefs.getString('target_ip') ?? '192.168.240.255';
      _udp.targetPort = prefs.getInt('target_port') ?? 10025;
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
    for (int i = 0; i < 5; i++) {
      await _udp.sendToPort(command, _udp.commandPort);
      if (i < 4) await Future.delayed(const Duration(milliseconds: 50));
    }
    // 바이너리 프레임도 함께 전송 (모터드라이버 직접 통신용)
    switch (command) {
      case 'N':
        await _motor.motorOn();
        break;
      case 'F':
        break;
      case 'I':
        await _motor.reset();
        break;
      case 'R':
        await _motor.moveRight();
        break;
      case 'L':
        await _motor.moveLeft();
        break;
      case 'S':
        await _motor.stop();
        break;
      case 'O':
        await _motor.saveOrigin();
        break;
      case 'A':
        break;
      case 'B':
        break;
    }
  }

  void _startEndUdpTimer() {
    _endUdpTimer?.cancel();
    _endUdpTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _state != AppState.end) return;
      _sendUdp('B');
    });
  }

  Future<void> _goTo(AppState newState) async {
    if (_navigating) return;
    _navigating = true;
    try {
      _timer?.cancel();
      _timer = null;
      setState(() {
        _state = newState;
        if (newState == AppState.play) _playTimerExpired = false;
      });

      // 영상 재생 제어
      if (newState == AppState.ready1 || newState == AppState.ready2) {
        setState(() => _readyButtonVisible = false);
        _readyVideoTimer?.cancel();
        _readyTimerActive = true;
        _readyVideoTimer = Timer(const Duration(seconds: 13), () {
          if (!mounted || !_readyTimerActive) return;
          setState(() => _readyButtonVisible = true);
        });
        // ready2 진입 시에도 포함해 항상 기존 A신호 타이머 취소
        _aSignalTimer?.cancel();
        _aSignalTimer = null;
        _ackSubscription?.cancel();
        _ackSubscription = null;
        // ready1: A신호 반복 시작 (ACK 오면 정지)
        if (newState == AppState.ready1) {
          _aSignalTimer = Timer.periodic(const Duration(milliseconds: 500), (
            _,
          ) {
            if (!mounted) return;
            _udp.sendToPort('A', _udp.commandPort);
          });
          _ackSubscription = _udp.onAck.listen((ack) {
            if (ack.trim() == 'A') {
              _aSignalTimer?.cancel();
              _aSignalTimer = null;
              _ackSubscription?.cancel();
              _ackSubscription = null;
            }
          });
        }
      } else {
        _readyTimerActive = false;
        _readyVideoTimer?.cancel();
        _readyVideoTimer = null;
        // ready 아닌 상태로 이동 시 A신호 반복 정지
        _aSignalTimer?.cancel();
        _aSignalTimer = null;
        _ackSubscription?.cancel();
        _ackSubscription = null;
      }
      switch (newState) {
        case AppState.idle:
          await _idleVideoController.seekTo(Duration.zero);
          _idleVideoController.play();
          break;
        case AppState.ready1:
          await _ready1VideoController.seekTo(Duration.zero);
          _ready1VideoController.play();
          break;
        case AppState.ready2:
          await _ready2VideoController.seekTo(Duration.zero);
          _ready2VideoController.play();
          break;

        case AppState.play:
          _playVideoController.setLooping(false);
          await _playVideoController.seekTo(Duration.zero);
          await _playVideoController.play();
          break;
        case AppState.end:
          await _endVideoController.seekTo(Duration.zero);
          _endVideoController.play();
          _startEndUdpTimer();
          break;
        case AppState.survey: // 설문 페이지 진입 시 END 영상 정지
          _endVideoController.pause();
          break;
      }

      _pageController.animateToPage(
        newState.index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      // IDLE이 아니면 타이머 시작
      if (newState != AppState.idle) {
        final seconds = switch (newState) {
          AppState.ready1 => _readySeconds,
          AppState.ready2 => _readySeconds,
          AppState.play => _playSeconds,
          AppState.end => _endSeconds,
          AppState.survey => _surveySeconds,
          _ => 10,
        };

        _remaining = seconds;
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _remaining--);
          if (_state == AppState.play && _remaining == 1) {
            // 14초: 모터 먼저 정지
            _motor.motorOff();
          }
          if (_remaining <= 0) {
            t.cancel();
            _timer = null;
            if (_state == AppState.play) {
              // 15초: UDP F 신호
              _udp.send('F');
              setState(() => _playTimerExpired = true);
            } else {
              _aSignalTimer?.cancel();
              _aSignalTimer = null;
              _ackSubscription?.cancel();
              _ackSubscription = null;
              _sendUdp('I').then((_) => _goTo(AppState.idle));
            }
          }
        });
      }
    } finally {
      _navigating = false;
    }
  }

  void _resetTimer() {
    if (_state == AppState.idle || _state == AppState.play) return;
    _timer?.cancel();
    final seconds = switch (_state) {
      AppState.ready1 => _readySeconds,
      AppState.ready2 => _readySeconds,
      AppState.play => _playSeconds,
      AppState.end => _endSeconds,
      AppState.survey => _surveySeconds,
      _ => 10,
    };
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _aSignalTimer?.cancel();
        _aSignalTimer = null;
        _ackSubscription?.cancel();
        _ackSubscription = null;
        _sendUdp('I').then((_) => _goTo(AppState.idle));
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
    _readyVideoTimer?.cancel();
    _endUdpTimer?.cancel();
    _keepaliveTimer?.cancel();
    _aSignalTimer?.cancel();
    _ackSubscription?.cancel();
    _udp.dispose();
    _pageController.dispose();
    _surveyPageController.dispose();
    _idleVideoController.dispose();
    _ready1VideoController.dispose();
    _ready2VideoController.dispose();
    _playVideoController.dispose();
    _endVideoController.dispose();
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
                    _buildReady1Page(),
                    _buildReady2Page(),
                    _buildPlayPage(),
                    _buildEndPage(),
                    _buildSurveyPage(),
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
    return Stack(
      children: [
        if (_idleVideoController.value.isInitialized)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _idleVideoController.value.size.width,
                height: _idleVideoController.value.size.height,
                child: VideoPlayer(_idleVideoController),
              ),
            ),
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: Center(
            child: IdleButton(
              onTap: () async {
                await _sendUdp('A');
                _goTo(AppState.ready1);
              },
            ),
          ),
        ),
      ],
    );
  }

  // === READY 화면 ===
  Widget _buildReady1Page() {
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          if (_ready1VideoController.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _ready1VideoController.value.size.width,
                  height: _ready1VideoController.value.size.height,
                  child: VideoPlayer(_ready1VideoController),
                ),
              ),
            ),
          PageNavButton(
            isLeft: true,
            isVisible: false,
            onTap: () async {
              await _ready1VideoController.seekTo(Duration.zero);
              _ready1VideoController.play();
            },
          ),
          PageNavButton(
            isLeft: false,
            isVisible: false,
            onTap: () async {
              await _goTo(AppState.ready2);
            },
          ),
          ExitButton(
            onTap: () async {
              _aSignalTimer?.cancel();
              _aSignalTimer = null;
              _ackSubscription?.cancel();
              _ackSubscription = null;
              await _sendUdp('I');
              _goTo(AppState.idle);
            },
          ),
        ],

        // 우측 상단 IDLE 복귀 버튼 (항상 표시)
      ),
    );
  }

  // === READY2 화면 ===
  Widget _buildReady2Page() {
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          if (_ready2VideoController.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _ready2VideoController.value.size.width,
                  height: _ready2VideoController.value.size.height,
                  child: VideoPlayer(_ready2VideoController),
                ),
              ),
            ),
          PageNavButton(
            isLeft: true,
            isVisible: false,
            onTap: () async {
              _ready2Resetting = true;
              setState(() => _readyButtonVisible = false);
              await _ready2VideoController.seekTo(Duration.zero);
              _ready2Resetting = false;
              _ready2VideoController.play();
            },
          ),
          PageNavButton(
            isLeft: false,
            isVisible: false,
            onTap: () async {
              setState(() => _readyButtonVisible = true);
              await _ready2VideoController.seekTo(const Duration(seconds: 6));
              _ready2VideoController.play();
            },
          ),
          ExitButton(
            onTap: () async {
              await _sendUdp('I');
              _goTo(AppState.idle);
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: AnimatedOpacity(
              opacity: _readyButtonVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeIn,
              child: IgnorePointer(
                ignoring: !_readyButtonVisible,
                child: Center(
                  child: StartButton(
                    onTap: () async {
                      await _sendUdp('N');
                      await _goTo(AppState.play);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],

        // 우측 상단 IDLE 복귀 버튼 (항상 표시)
      ),
    );
  }

  // === PLAY 화면 (터치해도 타이머 리셋 없음 — 무조건 END로 전환) ===
  Widget _buildPlayPage() {
    return Container(
      child: Stack(
        children: [
          if (_playVideoController.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _playVideoController.value.size.width,
                  height: _playVideoController.value.size.height,
                  child: VideoPlayer(_playVideoController),
                ),
              ),
            ),
          // 우측 중앙 다음(END) 버튼 — 타이머 만료 후에만 활성화
          if (_playTimerExpired)
            PageNavButton(
              isLeft: false,
              isWhite: true,
              onTap: () async {
                await _sendUdp('F');
                _goTo(AppState.end);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEndPage() {
    return Container(
      child: Stack(
        children: [
          if (_endVideoController.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _endVideoController.value.size.width,
                  height: _endVideoController.value.size.height,
                  child: VideoPlayer(_endVideoController),
                ),
              ),
            ),
          PageNavButton(
            isLeft: true,
            isVisible: false,
            onTap: () async {
              await _endVideoController.seekTo(Duration.zero);
              _endVideoController.play();
              _startEndUdpTimer();
            },
          ),

          PageNavButton(
            isLeft: false,
            isWhite: true,
            isVisible: false,
            onTap: () async {
              await _sendUdp('B');
              await _goTo(AppState.survey);
            },
          ),
          ExitButton(
            showImage: false,
            onTap: () async {
              await _sendUdp('I');
              _goTo(AppState.idle);
            },
          ),
        ],
      ),
    );
  }

  // === END 화면 (8_end ~ 10_end 슬라이드, 10_end에 첫화면 버튼) ===
  Widget _buildSurveyPage() {
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(image: _allImages[0], fit: BoxFit.cover),
            ),
          ),
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
}
