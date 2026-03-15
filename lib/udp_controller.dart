import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class UdpCommand {
  // 전시 운영
  static const motorOn = 'N';
  static const motorOff = 'F';
  static const reset = 'I';

  // 원점 셋팅
  static const calibrate = 'C';
  static const moveRight = 'R';
  static const moveLeft = 'L';
  static const stop = 'S';
  static const saveOrigin = 'O';

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

class UdpController {
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

  String targetIp = '192.168.240.255';
  int targetPort = 10025;

  RawDatagramSocket? _socket;
  final _receiveController = StreamController<String>.broadcast();

  /// 수신된 UDP 메시지 스트림
  Stream<String> get onReceive => _receiveController.stream;

  static final instance = UdpController._();

  UdpController._();

  Future<void> init() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          debugPrint(
            'UDP 수신: $message ← ${datagram.address.address}:${datagram.port}',
          );
          _receiveController.add(message);
        }
      }
    });
  }

  Future<RawDatagramSocket> _getSocket() async {
    if (_socket != null) return _socket!;
    await init();
    return _socket!;
  }

  /// 일반 전송
  Future<void> send(String command) async {
    final name = _commandNames[command] ?? command;
    final hex = '0x${command.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    debugPrint('UDP 전송: \'$command\' ($hex) $name → $targetIp:$targetPort');
    try {
      final socket = await _getSocket();
      final data = utf8.encode(command);
      final addr = InternetAddress(targetIp);
      socket.send(data, addr, targetPort);
    } on SocketException catch (e) {
      debugPrint('UDP 전송 실패 (네트워크 없음): $e');
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
      _socket?.close();
      _socket = null;
    }
  }

  /// 즉시 단일 패킷 전송 — 반응속도가 최우선인 곳용
  void sendFast(String command) {
    final socket = _socket;
    if (socket == null) {
      _getSocket()
          .then((s) {
            try {
              s.send(
                utf8.encode(command),
                InternetAddress(targetIp),
                targetPort,
              );
            } on SocketException catch (e) {
              debugPrint('UDP fast 전송 실패 (네트워크 없음): $e');
            }
          })
          .catchError((e) {
            debugPrint('UDP fast 전송 실패: $e');
            _socket?.close();
            _socket = null;
          });
      return;
    }
    try {
      final bytes = socket.send(
        utf8.encode(command),
        InternetAddress(targetIp),
        targetPort,
      );
      debugPrint(
        'UDP fast 전송: $command (${UdpCommand.nameOf(command)}) → $targetIp:$targetPort [$bytes bytes]',
      );
    } on SocketException catch (e) {
      debugPrint('UDP fast 전송 실패 (네트워크 없음): $e');
    } catch (e) {
      debugPrint('UDP fast 전송 실패: $e');
      _socket?.close();
      _socket = null;
    }
  }

  void dispose() {
    _socket?.close();
    _socket = null;
    _receiveController.close();
  }
}
