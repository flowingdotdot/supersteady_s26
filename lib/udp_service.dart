import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class UdpCommand {
  // 전시 운영
  static const motorOn = 'N'; // 모터 ON
  static const motorOff = 'F'; // 모터 OFF
  static const reset = 'I'; // 리셋

  // 원점 셋팅
  static const calibrate = 'C'; // 원점 셋팅모드
  static const moveRight = 'R'; // 오른쪽 이동
  static const moveLeft = 'L'; // 왼쪽 이동
  static const stop = 'S'; // 멈춤
  static const saveOrigin = 'O'; // 현재값 원점 저장

  static const _names = {
    'N': '모터ON',
    'F': '모터OFF',
    'I': '리셋',
    'C': '캘리브',
    'R': '오른쪽',
    'L': '왼쪽',
    'S': '멈춤',
    'O': '원점저장',
  };
  static String nameOf(String cmd) => _names[cmd] ?? cmd;
}

class UdpService {
  static const _commandNames = {
    'N': 'motorOn',
    'F': 'motorOff',
    'I': 'reset',
    'C': 'calibrate',
    'R': 'moveRight',
    'L': 'moveLeft',
    'S': 'stop',
    'O': 'saveOrigin',
  };

  static RawDatagramSocket? _cachedSocket;

  static Future<RawDatagramSocket> _getSocket() async {
    if (_cachedSocket != null) return _cachedSocket!;
    _cachedSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _cachedSocket!.broadcastEnabled = true;
    return _cachedSocket!;
  }

  /// 일반 전송 — 5회 중복 전송 (모터 ON/OFF 등 확실히 전달해야 하는 명령용)
  static Future<void> send(String command, String ip, int port) async {
    final name = _commandNames[command] ?? command;
    final hex = '0x${command.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    debugPrint('UDP 전송: \'$command\' ($hex) $name → $ip:$port x5');
    try {
      final socket = await _getSocket();
      final data = utf8.encode(command);
      final addr = InternetAddress(ip);
      socket.send(data, addr, port);
      // for (int i = 0; i < 5; i++) {
      //   socket.send(data, addr, port);
      // }
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
      _cachedSocket?.close();
      _cachedSocket = null;
    }
  }

  /// 소켓 미리 준비 — 앱 시작 시 호출해두면 sendFast가 완전 동기로 동작
  static Future<void> warmUp() async {
    await _getSocket();
  }

  /// 즉시 단일 패킷 전송 — 영점세팅 이동/멈춤 등 반응속도가 최우선인 곳용
  /// 소켓이 이미 캐시돼 있으면 완전 동기로 전송 (await 없음)
  static void sendFast(String command, String ip, int port) {
    final socket = _cachedSocket;
    if (socket == null) {
      // 소켓 아직 없으면 비동기로 한 번 초기화 후 전송
      _getSocket()
          .then((s) {
            s.send(utf8.encode(command), InternetAddress(ip), port);
          })
          .catchError((e) {
            debugPrint('UDP fast 전송 실패: $e');
            _cachedSocket?.close();
            _cachedSocket = null;
          });
      return;
    }
    try {
      final bytes = socket.send(
        utf8.encode(command),
        InternetAddress(ip),
        port,
      );
      debugPrint(
        'UDP fast 전송: $command (${UdpCommand.nameOf(command)}) → $ip:$port [$bytes bytes]',
      );
    } catch (e) {
      debugPrint('UDP fast 전송 실패: $e');
      _cachedSocket?.close();
      _cachedSocket = null;
    }
  }

  static void dispose() {
    _cachedSocket?.close();
    _cachedSocket = null;
  }
}
