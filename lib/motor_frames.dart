import 'dart:typed_data';

/// 모터드라이버로 보낼 바이너리 프레임을 생성합니다.
/// Arduino esp32s3_uniservo.ino 코드와 동일한 프레임 구조입니다.
class MotorFrames {
  static int _seq = 1;
  static const int _axis = 0x00;

  static int _nextSeq() {
    final s = _seq & 0xFFFF;
    _seq = (_seq + 1) & 0xFFFF;
    if (_seq == 0) _seq = 1;
    return s;
  }

  static void _header(Uint8List f, int seq, int opId) {
    f[2] = 0xF1;
    f[3] = 0xF2;
    f[4] = (seq >> 8) & 0xFF;
    f[5] = seq & 0xFF;
    f[8] = 0x10; // Write Mode
    f[9] = opId;
    f[10] = _axis;
  }

  /// int32 값을 빅엔디안으로 기록 (음수 포함)
  static void _i32(Uint8List f, int base, int val) {
    final v = val & 0xFFFFFFFF;
    f[base] = (v >> 24) & 0xFF;
    f[base + 1] = (v >> 16) & 0xFF;
    f[base + 2] = (v >> 8) & 0xFF;
    f[base + 3] = v & 0xFF;
  }

  // ── ID 8: 세션 초기화 ──────────────────────
  static Uint8List init() {
    return Uint8List.fromList([
      0x00, 0x00, 0xF1, 0xF2,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x08, 0xFF, 0x00,
      0x00, 0x00, 0x00, 0x01,
    ]);
  }

  // ── ID 50: 드라이브 알람 리셋 ───────────────
  static Uint8List resetDrive() {
    final f = Uint8List(20);
    _header(f, _nextSeq(), 50);
    f[15] = 0x01;
    return f;
  }

  // ── ID 51: 감속 정지 (SlowStop) ─────────────
  static Uint8List moveStop() {
    final f = Uint8List(20);
    _header(f, _nextSeq(), 51);
    f[15] = 0x01;
    f[19] = 200;
    return f;
  }

  // ── ID 63: 원점 설정 (Actual Position Clear) ─
  static Uint8List setOrigin() {
    final f = Uint8List(20);
    _header(f, _nextSeq(), 63);
    f[15] = 0x01;
    return f;
  }

  // ── ID 73: 서보 ON/OFF ──────────────────────
  static Uint8List servoCommand(bool on) {
    final f = Uint8List(20);
    _header(f, _nextSeq(), 73);
    f[15] = 0x01;
    f[19] = on ? 1 : 0;
    return f;
  }

  // ── ID 20: 절대 이송 ────────────────────────
  static Uint8List moveAbsolute(int targetPos, int velocity) {
    final f = Uint8List(60);
    _header(f, _nextSeq(), 20);
    f[15] = 11;
    void d(int i, int v) => _i32(f, 16 + i * 4, v);
    d(0, 3);         // S-curve 가감속
    d(1, velocity);
    d(2, 300);       // 가속 시간
    d(3, 300);       // 감속 시간
    d(4, 60);        // Jerk Accel
    d(5, 60);        // Jerk Decel
    d(6, targetPos);
    d(7, 0);
    d(8, 0);
    d(9, 0);
    d(10, 0);        // 0: 절대 이송
    return f;
  }

  // ── ID 20: Jog 이송 ─────────────────────────
  static Uint8List moveJog(bool direction) {
    final f = Uint8List(60);
    _header(f, _nextSeq(), 20);
    f[15] = 11;
    void d(int i, int v) => _i32(f, 16 + i * 4, v);
    d(0, 5);                  // Jog 이송
    d(1, 10);
    d(2, 300);
    d(3, 300);
    d(4, 60);
    d(5, 60);
    d(6, 0);
    d(7, direction ? 1 : 0); // 방향: true=오른쪽
    d(8, 0);
    d(9, 0);
    d(10, 0);
    return f;
  }

  // ── ID 140: 반복 이송 조건 설정 ─────────────
  // addr: 0=지점A, 1=지점B
  static Uint8List setRepeatPosition(
      int addr, int pos, int velocity, int waitTime) {
    final f = Uint8List(60);
    _header(f, _nextSeq(), 140);
    // addr → 11~14번 바이트
    f[11] = (addr >> 24) & 0xFF;
    f[12] = (addr >> 16) & 0xFF;
    f[13] = (addr >> 8) & 0xFF;
    f[14] = addr & 0xFF;
    f[15] = 11;
    void d(int i, int v) => _i32(f, 16 + i * 4, v);
    d(0, 1);         // 위치정보 활성화
    d(1, 1);         // Absolute 이송
    d(2, 0);         // In-position 확인
    d(3, 0);         // 사다리꼴 가감속
    d(4, pos);
    d(5, velocity);
    d(6, 300);
    d(7, 300);
    d(8, 0);
    d(9, 0);
    d(10, waitTime);
    return f;
  }

  // ── ID 141: 반복 이송 실행/정지 ─────────────
  static Uint8List controlRepeatMove(bool start, int repeatCount) {
    final f = Uint8List(24);
    _header(f, _nextSeq(), 141);
    f[15] = 2;
    f[19] = start ? 1 : 0;
    _i32(f, 20, repeatCount);
    return f;
  }
}
