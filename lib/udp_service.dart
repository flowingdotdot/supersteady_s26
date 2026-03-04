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

  static Future<void> send(String command, String ip, int port) async {
    final name = _commandNames[command] ?? command;
    final hex = '0x${command.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    debugPrint('UDP 전송: \'$command\' ($hex) $name → $ip:$port x5');
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final data = utf8.encode(command);
      final addr = InternetAddress(ip);
      for (int i = 0; i < 5; i++) {
        socket.send(data, addr, port);
      }
      socket.close();
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
    }
  }
}
