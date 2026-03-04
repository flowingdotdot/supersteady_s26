import 'dart:convert';
import 'dart:io';

void main() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final target = InternetAddress('192.168.240.255');
  const port = 10025;
  final commands = ['I', 'N', 'F'];
  var index = 0;

  print('=== UDP Sender ===');
  print('송신: ${socket.address.address}:${socket.port}');
  print('수신: 192.168.240.255:$port');
  print('패턴: I → N → F (4초 간격)');
  print('종료: Ctrl+C\n');

  while (true) {
    final command = commands[index % commands.length];
    for (var i = 0; i < 5; i++) {
      socket.send(utf8.encode(command), target, port);
    }
    print('[${DateTime.now().toString().substring(11, 19)}] 전송: "$command" x5 → 192.168.240.255:$port');
    index++;
    await Future.delayed(const Duration(seconds: 4));
  }
}
// ON	N	0x4E (78)	[78]
// OFF	F	0x46 (70)	[70]
