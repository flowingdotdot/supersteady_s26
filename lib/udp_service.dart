import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class UdpService {
  static Future<void> send(String command, String ip, int port) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(utf8.encode(command), InternetAddress(ip), port);
      socket.close();
    } catch (e) {
      debugPrint('UDP 전송 실패: $e');
    }
  }
}
