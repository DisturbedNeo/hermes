import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/ui/chat/message/bubble_markdown_view.dart';
import 'package:hermes/ui/chat/message/think_section.dart';
import 'package:hermes/ui/chat/message/think_stream_parser.dart';

class StreamedMessageView extends StatefulWidget {
  final Stream<String> tokenStream; 
  final Color fg;
  final Color bg;
  final bool editable;

  const StreamedMessageView({
    super.key,
    required this.tokenStream,
    required this.fg,
    required this.bg,
    this.editable = false,
  });

  @override
  State<StreamedMessageView> createState() => _StreamedMessageViewState();
}

class _StreamedMessageViewState extends State<StreamedMessageView> {
  late final ThinkStreamParser parser = ThinkStreamParser();
  late final StreamSubscription<String> sub;

  @override
  void initState() {
    super.initState();
    sub = widget.tokenStream.listen(
      parser.addChunk,
      onDone: parser.close,
      onError: (_) => parser.close(),
    );
  }

  @override
  void dispose() {
    sub.cancel();
    parser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: parser,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in parser.parts)
              p.isThink
                  ? ThinkSection(
                      key: ValueKey(p.id),
                      text: p.text,
                      fg: widget.fg,
                      bg: widget.bg,
                      streaming: !p.closed,
                    )
                  : BubbleMarkdownView(
                      key: ValueKey(p.id),
                      text: p.text,
                      foreground: widget.fg,
                      background: widget.bg,
                    ),
          ],
        );
      },
    );
  }
}
