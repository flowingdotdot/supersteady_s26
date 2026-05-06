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
  static const setup = 'P';

  static const _names = {
    'N': '모터ON',
    'F': '모터OFF',
    'I': '리셋',
    'C': '캘리브',
    'R': '오른쪽',
    'L': '왼쪽',
    'S': '멈춤',
    'O': '원점저장',
    'P': '전시시작',
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
  int commandPort = 10025;
  int ackPort = 10026;

  RawDatagramSocket? _socket;
  RawDatagramSocket? _ackSocket;
  final _receiveController = StreamController<String>.broadcast();
  final _sendController = StreamController<String>.broadcast();
  final _ackController = StreamController<String>.broadcast();

  /// 수신된 UDP 메시지 스트림
  Stream<String> get onReceive => _receiveController.stream;

  /// 송신된 UDP 메시지 스트림
  Stream<String> get onSend => _sendController.stream;

  /// ACK 수신 스트림 (10026 포트)
  Stream<String> get onAck => _ackController.stream;

  static final instance = UdpController._();

  UdpController._();

  Future<void> init() async {
    _socket?.close();
    _socket = null;
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

    _ackSocket?.close();
    _ackSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, ackPort);
    _ackSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _ackSocket!.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          debugPrint(
            'UDP ACK 수신: $message ← ${datagram.address.address}:${datagram.port}',
          );
          _ackController.add(message);
        }
      }
    });
  }

  Future<RawDatagramSocket> _getSocket() async {
    if (_socket != null) return _socket!;
    await init();
    return _socket!;
  }

  /// 특정 포트로 전송
  Future<void> sendToPort(String command, int port) async {
    final name = _commandNames[command] ?? command;
    final hex = '0x${command.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    debugPrint('UDP 전송: \'$command\' ($hex) $name → $targetIp:$port');
    _sendController.add(command);
    try {
      final socket = await _getSocket();
      final data = utf8.encode(command);
      socket.send(data, InternetAddress(targetIp), port);
    } on SocketException catch (e) {
      debugPrint('UDP 전송 실패 (네트워크 없음): $e');
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
      _socket?.close();
      _socket = null;
      _ackSocket?.close();
      _ackSocket = null;
    }
  }

  /// 일반 전송
  Future<void> send(String command) async {
    final name = _commandNames[command] ?? command;
    final hex = '0x${command.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    debugPrint('UDP 전송: \'$command\' ($hex) $name → $targetIp:$targetPort');
    _sendController.add(command);
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
      _ackSocket?.close();
      _ackSocket = null;
    }
  }

  /// 즉시 단일 패킷 전송 — 반응속도가 최우선인 곳용
  void sendFast(String command) {
    _sendController.add(command);
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
            _ackSocket?.close();
            _ackSocket = null;
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
      _ackSocket?.close();
      _ackSocket = null;
    }
  }

  /// 바이너리 프레임 전송 — 모터드라이버 직접 통신용
  Future<void> sendBytes(Uint8List data) async {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('UDP sendBytes → $targetIp:$targetPort [${data.length}B] $hex');
    try {
      final socket = await _getSocket();
      socket.send(data, InternetAddress(targetIp), targetPort);
    } on SocketException catch (e) {
      debugPrint('UDP sendBytes 실패 (네트워크 없음): $e');
    } catch (e) {
      debugPrint('UDP sendBytes 실패: $e');
      _socket?.close();
      _socket = null;
      _ackSocket?.close();
      _ackSocket = null;
    }
  }

  void dispose() {
    _socket?.close();
    _socket = null;
    _ackSocket?.close();
    _ackSocket = null;
    _receiveController.close();
    _sendController.close();
    _ackController.close();
  }
}
