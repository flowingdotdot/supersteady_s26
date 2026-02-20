import 'dart:io';
import 'dart:convert';

void main() async {
  // 수신 소켓
  final receiver = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4210);
  print('[수신] 4210 포트 대기중...');

  int count = 0;
  receiver.listen((event) {
    if (event == RawSocketEvent.read) {
      final packet = receiver.receive();
      if (packet != null) {
        final msg = utf8.decode(packet.data);
        print('[수신] 받음: "$msg" from ${packet.address.address}:${packet.port}');
        count++;
        if (count >= 2) {
          receiver.close();
          print('[완료] UDP 테스트 성공!');
        }
      }
    }
  });

  // 잠시 대기 후 발신
  await Future.delayed(Duration(milliseconds: 500));

  final sender = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  print('[발신] N 전송...');
  sender.send(utf8.encode('N'), InternetAddress('192.168.240.2'), 4210);

  await Future.delayed(Duration(milliseconds: 500));
  print('[발신] F 전송...');
  sender.send(utf8.encode('F'), InternetAddress('192.168.240.2'), 4210);
  sender.close();

  // 타임아웃
  await Future.delayed(Duration(seconds: 3));
  if (count < 2) {
    print('[실패] 수신 타임아웃');
    receiver.close();
  }
}
