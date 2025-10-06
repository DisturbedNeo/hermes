import 'package:flutter/material.dart';
import 'package:hermes/core/models/message_part.dart';

class ThinkStreamParser extends ChangeNotifier {
  static const startTag = '<think>';
  static const endTag = '</think>';
  static const startKeep = startTag.length - 1;
  static const endKeep = endTag.length - 1;

  final List<MessagePart> parts = [];
  bool inThink = false;
  MessagePart? current;
  String pending = '';

  void startPart(bool isThink) {
    current = MessagePart(
      '${parts.length}-${isThink ? 'think' : 'text'}',
      isThink: isThink,
      closed: !isThink,
    );

    parts.add(current!);
  }

  void addChunk(String chunk) {
    pending += chunk;

    while (true) {
      if (!inThink) {
        final i = pending.indexOf(startTag);
        if (i == -1) {
          final keep = pending.length < startKeep ? pending.length : startKeep;
          final emitLen = pending.length - keep;
          if (emitLen > 0) {
            if (current == null || current!.isThink) startPart(false);
            current!.append(pending.substring(0, emitLen));
          }
          pending = pending.substring(pending.length - keep);
          break;
        } else {
          if (i > 0) {
            if (current == null || current!.isThink) startPart(false);
            current!.append(pending.substring(0, i));
          }
          pending = pending.substring(i + startTag.length);
          inThink = true;
          startPart(true);
        }
      } else {
        final j = pending.indexOf(endTag);
        if (j == -1) {
          final keep = pending.length < endKeep ? pending.length : endKeep;
          final emitLen = pending.length - keep;
          if (emitLen > 0) {
            current!.append(pending.substring(0, emitLen));
          }
          pending = pending.substring(pending.length - keep);
          break;
        } else {
          if (j > 0) current!.append(pending.substring(0, j));
          current!.closed = true;
          pending = pending.substring(j + endTag.length);
          inThink = false;
          current = null;
        }
      }
    }

    notifyListeners();
  }

  void flushTail() {
    if (pending.isEmpty) {
      return;
    }

    if (!inThink) {
      if (current == null || current!.isThink) startPart(false);
      current!.append(pending);
    } else {
      current!.append(pending);
    }

    pending = '';
    notifyListeners();
  }

  void close() {
    if (pending.isNotEmpty) {
      if (!inThink) {
        if (current == null || current!.isThink) startPart(false);
        current!.append(pending);
      } else {
        current!.append(pending);
      }
      pending = '';
    }
    notifyListeners();
  }

  void reset() {
    parts.clear();
    inThink = false;
    current = null;
    pending = '';
    notifyListeners();
  }
}
