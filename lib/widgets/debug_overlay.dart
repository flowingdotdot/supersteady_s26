import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../udp_controller.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _enabled = false;
  String _lastSent = '';
  String _lastReceived = '';
  StreamSubscription<String>? _recvSub;
  StreamSubscription<String>? _sendSub;

  @override
  void initState() {
    super.initState();
    _load();
    _recvSub = UdpController.instance.onReceive.listen((msg) {
      setState(() => _lastReceived = msg);
    });
    _sendSub = UdpController.instance.onSend.listen((msg) {
      setState(() => _lastSent = msg);
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _enabled = prefs.getBool('debug_mode') ?? false);
  }

  @override
  void dispose() {
    _recvSub?.cancel();
    _sendSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SharedPreferences 변경을 감지하기 위해 매 빌드마다 체크
    // (테스트 페이지에서 토글 후 돌아왔을 때 반영)
    _load();

    if (!_enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 8,
          bottom: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '송신: ${_lastSent.isEmpty ? '-' : '$_lastSent(${UdpCommand.nameOf(_lastSent)})'}'
                ' | 수신: ${_lastReceived.isEmpty ? '-' : '$_lastReceived(${UdpCommand.nameOf(_lastReceived)})'}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
