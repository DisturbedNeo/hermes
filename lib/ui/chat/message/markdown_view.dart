import 'dart:async';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MarkdownView extends StatefulWidget {
  final String data;
  final VoidCallback? onTapNonLink;
  final List<WidgetConfig> configs;
  final EdgeInsetsGeometry? padding;
  final void Function(String url)? onLinkTap;

  const MarkdownView({
    super.key,
    required this.data,
    this.onTapNonLink,
    this.configs = const [],
    this.padding,
    this.onLinkTap,
  });

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  bool _linkTapped = false;
  bool _down = false;

  void _markLinkTapped() {
    _linkTapped = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _linkTapped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = MarkdownConfig(
      configs: [
        ...widget.configs,
        LinkConfig(
          onTap: (url) {
            _markLinkTapped();
            (widget.onLinkTap ?? launchUrlString).call(url);
          },
        ),
      ],
    );

    final content = MarkdownBlock(data: widget.data, config: config);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _down = true,
      onPointerCancel: (_) => _down = false,
      onPointerUp: (_) {
        scheduleMicrotask(() {
          if (_down && !_linkTapped) {
            widget.onTapNonLink?.call();
          }
          _down = false;
        });
      },
      child: widget.padding == null
          ? content
          : Padding(padding: widget.padding!, child: content),
    );
  }
}
