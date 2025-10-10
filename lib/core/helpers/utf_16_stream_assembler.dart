class Utf16StreamAssembler {
  final void Function(String chunk) onChunk;

  final StringBuffer _buf = StringBuffer();
  int? _pendingHigh;

  Utf16StreamAssembler({ required this.onChunk });

  void add(String token) {
    if (token.isEmpty) return;
    _buf.write(token);
  }

  void flush() {
    if(_buf.isEmpty) return;

    final units = _buf.toString().codeUnits;
    _buf.clear();

    final out = StringBuffer();
    var i = 0;

    if (_pendingHigh != null) {
      if (i < units.length && _isLow(units[i])) {
        out.writeCharCode(_pendingHigh!);
        out.writeCharCode(units[i]);
        i++;
      } else {
        // Replace stranded high surrogate
        out.writeCharCode(0xFFFD);
      }

      _pendingHigh = null;
    }

    while (i < units.length) {
      final u = units[i];

      if (_isHigh(u)) {
        if (i + 1 < units.length) {
          final v = units[i + 1];

          if (_isLow(v)) {
            out.writeCharCode(u);
            out.writeCharCode(v);
            i += 2;
          } else {
            // Bad pair
            out.writeCharCode(0xFFFD);
            i += 1;
          }
        } else {
          // Hold for next tick
          _pendingHigh = u;
          i += 1;
        }
      } else if (_isLow(u)) {
        // Replace stranded low surrogate
        out.writeCharCode(0xFFFD);
        i += 1;
      } else {
        out.writeCharCode(u);
        i += 1;
      }
    }

    if (out.isNotEmpty) onChunk(out.toString());
  }

  void clear() {
    _buf.clear();
    _pendingHigh = null;
  }

  bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
  bool _isLow (int u) => u >= 0xDC00 && u <= 0xDFFF;
}
