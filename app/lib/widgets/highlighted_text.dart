import 'package:flutter/material.dart';

import '../data/local_store.dart';

class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final int maxLines;
  final TextStyle? style;
  const HighlightedText(
    this.text, {
    super.key,
    this.query = '',
    this.maxLines = 2,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final terms = searchTerms(query);
    if (terms.isEmpty)
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    final pattern = RegExp(
      terms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    var end = 0;
    for (final match in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
