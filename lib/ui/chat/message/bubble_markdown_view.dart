import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hermes/core/models/themes/bubble_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class BubbleMarkdownView extends StatelessWidget {
  final String text;
  final Color foreground;
  final Color background;

  const BubbleMarkdownView({
    super.key,
    required this.text,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: false,
      softLineBreak: true,
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank');
        }
      },
      styleSheet: bubbleMarkdownStyles(context, textColor: foreground, background: background),
      sizedImageBuilder: (config) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          config.uri.toString(),
          width: config.width,
          height: config.height,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Text(config.alt ?? 'Image failed to load'),
        ),
      ),
    );
  }
}
