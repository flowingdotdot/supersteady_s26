import 'dart:convert';
import 'dart:io';

void main() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final target = InternetAddress('192.168.240.120');
  const port = 10025;
  var sendN = true;

  print('=== 192.168.240.120:10025 로 N/F 교대 전송 중 ===');
  print('종료: Ctrl+C\n');

  while (true) {
    final command = sendN ? 'N' : 'F';
    socket.send(utf8.encode(command), target, port);
    print('전송: "$command" → 192.168.240.120:$port');
    sendN = !sendN;
    await Future.delayed(const Duration(seconds: 2));
  }
}
// ON	N	0x4E (78)	[78]
// OFF	F	0x46 (70)	[70]