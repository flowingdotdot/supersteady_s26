import 'dart:convert';
import 'dart:io';
// [19:20:54] 수신: "F" ← 192.168.240.2:44355
// [19:20:56] 수신: "F" ← 192.168.240.2:47033 출발지포트

void main() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 10025);
  print('=== UDP 수신 대기중 (10025 포트) ===');
  print('태블릿에서 온/오프 버튼을 눌러보세요...');
  print('종료: Ctrl+C\n');

  socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final packet = socket.receive();
      if (packet != null && packet.address.address.startsWith('192.168.240.')) {
        final msg = utf8.decode(packet.data, allowMalformed: true);
        final now = DateTime.now();
        final time =
            '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}';
        print('[$time] 수신: "$msg" ← ${packet.address.address}:${packet.port}');
      }
    }
  });
}
