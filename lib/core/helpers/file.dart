import 'dart:io';

Future<bool> isExecutable(File f) async {
  final stat = await f.stat();
  final mode = stat.mode;
  // 0x49 = 0b1001001 -- execute bits
  final isX = (mode & 0x49) != 0;
  return isX;
}