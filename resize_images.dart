import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final dir = Directory('assets/images');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  const maxWidth = 2560;

  for (final file in files) {
    print('처리중: ${file.path}');
    final bytes = file.readAsBytesSync();
    final original = img.decodeJpg(bytes);
    if (original == null) {
      print('  디코딩 실패');
      continue;
    }
    print('  원본: ${original.width}x${original.height}');

    if (original.width <= maxWidth) {
      print('  리사이즈 불필요');
      continue;
    }

    // 비율 유지하며 width=2560 기준으로 축소
    final ratio = maxWidth / original.width;
    final newHeight = (original.height * ratio).round();

    final resized = img.copyResize(
      original,
      width: maxWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    final encoded = img.encodeJpg(resized, quality: 90);
    file.writeAsBytesSync(encoded);
    final newSize = (encoded.length / 1024 / 1024).toStringAsFixed(1);
    print('  리사이즈: ${resized.width}x${resized.height} (${newSize}MB)');
  }
  print('완료!');
}
