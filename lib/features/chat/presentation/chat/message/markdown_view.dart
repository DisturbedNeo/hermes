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
  static const Duration _renderThrottle = Duration(milliseconds: 50);
  static final MarkdownGenerator _markdownGenerator = MarkdownGenerator(
    generators: [
      SpanNodeGeneratorWithTag(
        tag: MarkdownTag.pre.name,
        generator: (element, config, visitor) =>
            _SafeCodeBlockNode(element, config.pre, visitor),
      ),
    ],
  );

  bool _linkTapped = false;
  bool _down = false;
  Timer? _renderTimer;
  late String _renderedData;

  @override
  void initState() {
    super.initState();
    _renderedData = widget.data;
  }

  @override
  void didUpdateWidget(covariant MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.data == _renderedData) {
      _renderTimer?.cancel();
      _renderTimer = null;
      return;
    }

    if (widget.data.length < _renderedData.length) {
      _renderTimer?.cancel();
      _renderTimer = null;
      _renderedData = widget.data;
      return;
    }

    _renderTimer ??= Timer(_renderThrottle, () {
      _renderTimer = null;
      if (!mounted || widget.data == _renderedData) return;
      setState(() => _renderedData = widget.data);
    });
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    super.dispose();
  }

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

    final content = MarkdownBlock(
      data: _renderedData,
      config: config,
      generator: _markdownGenerator,
    );

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

class _SafeCodeBlockNode extends ElementNode {
  static final RegExp _classSplit = RegExp(r'\s+');

  final dynamic element;
  final PreConfig preConfig;
  final WidgetVisitor visitor;

  _SafeCodeBlockNode(this.element, this.preConfig, this.visitor);

  String get _content => element.textContent as String? ?? '';

  @override
  InlineSpan build() {
    final language = _languageFrom(element);
    final splitContents = _content.trim().split(
      visitor.splitRegExp ?? WidgetVisitor.defaultSplitRegExp,
    );
    if (splitContents.lastOrNull?.isEmpty ?? false) {
      splitContents.removeLast();
    }

    final codeBuilder = preConfig.builder;
    if (codeBuilder != null) {
      return WidgetSpan(child: codeBuilder.call(_content, language ?? ''));
    }

    final widget = Container(
      decoration: preConfig.decoration,
      margin: preConfig.margin,
      padding: preConfig.padding,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(splitContents.length, (index) {
            final currentContent = splitContents[index];
            return ProxyRichText(
              TextSpan(
                children: highLightSpans(
                  currentContent,
                  language: language ?? 'plaintext',
                  theme: preConfig.theme,
                  textStyle: style,
                  styleNotMatched: preConfig.styleNotMatched,
                ),
              ),
              richTextBuilder: visitor.richTextBuilder,
            );
          }),
        ),
      ),
    );

    return WidgetSpan(
      child:
          preConfig.wrapper?.call(widget, _content, language ?? '') ?? widget,
    );
  }

  @override
  TextStyle get style => preConfig.textStyle.merge(parentStyle);

  static String? _languageFrom(dynamic element) {
    final children = element.children;
    if (children is! List || children.isEmpty) return null;

    final attributes = children.first.attributes;
    if (attributes is! Map) return null;

    final className = attributes['class'];
    if (className is! String || className.trim().isEmpty) return null;

    for (final token in className.trim().split(_classSplit)) {
      if (!token.startsWith('language-')) continue;

      final language = token.substring('language-'.length).trim();
      if (language.isNotEmpty) return language;
    }

    return null;
  }
}
