import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/search_screen.dart';
import '../services/profile_service.dart';
import '../utils/profile_navigation.dart';

/// Matches `@username` and `#hashtag` tokens (letters, digits, underscore).
final RegExp _mentionOrHashtagPattern = RegExp(r'[@#][A-Za-z0-9_]+');

/// Renders [text] as plain content, except `@mentions` and `#hashtags` are
/// styled with [accentColor] and become tappable:
/// - `@username` opens that user's profile if the username exists.
/// - `#hashtag` opens the search screen filtered to that tag.
///
/// Unknown mentions/hashtags stay tappable but show a "not found" message
/// rather than failing silently.
class LinkifiedText extends StatelessWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.accentColor,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Color? accentColor;

  Future<void> _onMentionTap(BuildContext context, String username) async {
    final id = await ProfileService().getUserIdByUsername(username);
    if (!context.mounted) return;
    if (id == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('@$username not found')));
      return;
    }
    openProfile(context, id);
  }

  void _onHashtagTap(BuildContext context, String tag) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            SearchScreen(initialQuery: tag, initialTabIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final linkStyle = baseStyle.copyWith(
      color: accentColor ?? cs.primary,
      fontWeight: FontWeight.w600,
    );

    final matches = _mentionOrHashtagPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      final isMention = token.startsWith('@');
      final name = token.substring(1);
      spans.add(
        TextSpan(
          text: token,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => isMention
                ? _onMentionTap(context, name)
                : _onHashtagTap(context, name),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
