import 'motor_frames.dart';
import 'udp_controller.dart';

/// 모터드라이버 고수준 제어 클래스.
/// MotorFrames로 바이너리 프레임을 만들어 UdpController.sendBytes()로 직접 전송합니다.
/// 축 동기화: axis 0 = 마스터, axis 1 = 슬레이브
/// - 양축 모두: servoCommand, setOrigin
/// - 마스터만: controlRepeatMove, moveStop, moveAbsolute, moveJog, setRepeatPosition
class MotorController {
  final UdpController _udp;

  // 60각 설정값(속도 : 300, 포지션 -1200~1200, 대기 200ms)
  // 45각 설정값, 웜기어 ( 속도 : 310, 포지션 -40000~40000, 대기 200ms)
  static const int _pos = 40000;
  static const int _vel = 2900;
  static const int _wait = 200;

  static const int _master = 0;
  static const int _slave = 1;

  MotorController(this._udp);

  static final instance = MotorController(UdpController.instance);

  // ── 전시 시작 (서보 ON → 반복 이송 시작) ────────────────────
  Future<void> motorOn() async {
    await _udp.sendBytes(MotorFrames.servoCommand(_master, true));
    await Future.delayed(const Duration(milliseconds: 50));
    await _udp.sendBytes(MotorFrames.servoCommand(_slave, true));
    await Future.delayed(const Duration(milliseconds: 50));
    await _udp.sendBytes(MotorFrames.controlRepeatMove(_master, true, 0));
  }

  // ── 전시 종료 moveAbsolute(반복 중단 → 정지 → 0점 복귀) ────────────────
  Future<void> motorOff() async {
    await _udp.sendBytes(MotorFrames.controlRepeatMove(_master, false, 0));
    await Future.delayed(const Duration(milliseconds: 100));
    await _udp.sendBytes(MotorFrames.moveStop(_master));
    await Future.delayed(const Duration(milliseconds: 200));
    await _udp.sendBytes(MotorFrames.moveAbsolute(_master, 0, _vel));
  }

  // ── 리셋/초기화 (motorOff와 동일) ───────────────────────────
  Future<void> reset() => motorOff();

  // ── 영점 설정 대화상자용 명령들 ──────────────────────────────
  Future<void> moveRight() =>
      _udp.sendBytes(MotorFrames.moveJog(_master, true));
  Future<void> moveLeft() =>
      _udp.sendBytes(MotorFrames.moveJog(_master, false));
  Future<void> stop() => _udp.sendBytes(MotorFrames.moveStop(_master));
  Future<void> saveOrigin() async {
    await _udp.sendBytes(MotorFrames.setOrigin(_master));
    await _udp.sendBytes(MotorFrames.setOrigin(_slave));
  }

  // ── 초기 세션 셋업 (최초 1회, 앱 시작 시 호출) ──────────────
  Future<void> setup() async {
    // 1. 세션 초기화
    await _udp.sendBytes(MotorFrames.init());
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. 서보 ON (양축)
    await _udp.sendBytes(MotorFrames.servoCommand(_master, true));
    await Future.delayed(const Duration(milliseconds: 200));
    await _udp.sendBytes(MotorFrames.servoCommand(_slave, true));
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. 원점 설정 (양축)
    await _udp.sendBytes(MotorFrames.setOrigin(_master));
    await Future.delayed(const Duration(milliseconds: 200));
    await _udp.sendBytes(MotorFrames.setOrigin(_slave));
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. 축 동기화 (axis 0 마스터, axis 1 슬레이브)
    await _udp.sendBytes(MotorFrames.setSyncAxis(_master, _slave, true));
    await Future.delayed(const Duration(milliseconds: 500));

    // 5. 반복 이송 범위 설정 (마스터만 — 슬레이브는 동기화로 자동 동작)
    await _udp.sendBytes(
      MotorFrames.setRepeatPosition(_master, 0, _pos, _vel, _wait),
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await _udp.sendBytes(
      MotorFrames.setRepeatPosition(_master, 1, -_pos, _vel, _wait),
    );
  }
}
