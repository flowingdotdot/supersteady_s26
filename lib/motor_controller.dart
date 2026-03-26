import 'motor_frames.dart';
import 'udp_controller.dart';

/// 모터드라이버 고수준 제어 클래스.
/// MotorFrames로 바이너리 프레임을 만들어 UdpController.sendBytes()로 직접 전송합니다.
class MotorController {
  final UdpController _udp;

  // 전시 설정값 (60각: 속도 300, 포지션 -1200~1200, 대기 200ms)
  static const int _pos = 1200;
  static const int _vel = 200;
  static const int _wait = 200;

  MotorController(this._udp);

  static final instance = MotorController(UdpController.instance);

  // ── 전시 시작 (서보 ON → 반복 이송 시작) ────────────────────
  Future<void> motorOn() async {
    await _udp.sendBytes(MotorFrames.servoCommand(true));
    await Future.delayed(const Duration(milliseconds: 50));
    await _udp.sendBytes(MotorFrames.controlRepeatMove(true, 0));
  }

  // ── 전시 종료 (반복 중단 → 정지 → 0점 복귀) ────────────────
  Future<void> motorOff() async {
    await _udp.sendBytes(MotorFrames.controlRepeatMove(false, 0));
    await Future.delayed(const Duration(milliseconds: 100));
    await _udp.sendBytes(MotorFrames.moveStop());
    await Future.delayed(const Duration(milliseconds: 200));
    await _udp.sendBytes(MotorFrames.moveAbsolute(0, _vel));
  }

  // ── 리셋/초기화 (motorOff와 동일) ───────────────────────────
  Future<void> reset() => motorOff();

  // ── 영점 설정 대화상자용 명령들 ──────────────────────────────
  Future<void> moveRight() => _udp.sendBytes(MotorFrames.moveJog(true));
  Future<void> moveLeft() => _udp.sendBytes(MotorFrames.moveJog(false));
  Future<void> stop() => _udp.sendBytes(MotorFrames.moveStop());
  Future<void> saveOrigin() => _udp.sendBytes(MotorFrames.setOrigin());

  // ── 초기 세션 셋업 (최초 1회, 앱 시작 시 호출) ──────────────
  Future<void> setup() async {
    await _udp.sendBytes(MotorFrames.init());
    await Future.delayed(const Duration(milliseconds: 500));
    await _udp.sendBytes(MotorFrames.servoCommand(true));
    await Future.delayed(const Duration(milliseconds: 500));
    await _udp.sendBytes(MotorFrames.setOrigin());
    await Future.delayed(const Duration(milliseconds: 500));
    await _udp.sendBytes(MotorFrames.setRepeatPosition(0, _pos, _vel, _wait));
    await Future.delayed(const Duration(milliseconds: 100));
    await _udp.sendBytes(MotorFrames.setRepeatPosition(1, -_pos, _vel, _wait));
  }
}
