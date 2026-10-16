import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/brand.dart';

sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);

  final int level;
  final String text;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);

  final String text;
}

class MdBullets extends MdBlock {
  const MdBullets(this.items);

  final List<String> items;
}

// the same small subset the raccoon dev store site renders: headings, bullet lists,
// paragraphs, inline code, bold, italics and links
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  final paragraph = <String>[];
  var list = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MdParagraph(paragraph.join(' ')));
    paragraph.clear();
  }

  void flushList() {
    if (list.isEmpty) return;
    blocks.add(MdBullets(list));
    list = [];
  }

  for (final raw in source.replaceAll('\r', '').split('\n')) {
    final line = raw.trim();
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    final item = RegExp(r'^[-*]\s+(.+)$').firstMatch(line);
    if (line.isEmpty) {
      flushParagraph();
      flushList();
    } else if (heading != null) {
      flushParagraph();
      flushList();
      blocks.add(MdHeading(heading.group(1)!.length, heading.group(2)!));
    } else if (item != null) {
      flushParagraph();
      list.add(item.group(1)!);
    } else {
      flushList();
      paragraph.add(line);
    }
  }
  flushParagraph();
  flushList();
  return blocks;
}

class InlinePart {
  const InlinePart(this.text, {this.bold = false, this.italic = false, this.code = false, this.href});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? href;
}

final _inline = RegExp(r'\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*');

// only web links are followed, anything else is shown as plain text
bool isWebUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null && (u.scheme == 'http' || u.scheme == 'https');
}

List<InlinePart> parseInline(String text) {
  final out = <InlinePart>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) out.add(InlinePart(text.substring(at, m.start)));
    if (m.group(1) != null) {
      final href = m.group(2)!.trim();
      out.add(isWebUrl(href) ? InlinePart(m.group(1)!, href: href) : InlinePart(m.group(1)!));
    } else if (m.group(3) != null) {
      out.add(InlinePart(m.group(3)!, code: true));
    } else if (m.group(4) != null) {
      out.add(InlinePart(m.group(4)!, bold: true));
    } else {
      out.add(InlinePart(m.group(5)!, italic: true));
    }
    at = m.end;
  }
  if (at < text.length) out.add(InlinePart(text.substring(at)));
  return out;
}

class MarkdownView extends StatefulWidget {
  const MarkdownView(this.source, {super.key, required this.onLink});

  final String source;
  final void Function(String url) onLink;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TextSpan _spans(String text, TextStyle base) {
    final children = <TextSpan>[];
    for (final p in parseInline(text)) {
      TapGestureRecognizer? tap;
      if (p.href != null) {
        final href = p.href!;
        tap = TapGestureRecognizer()..onTap = () => widget.onLink(href);
        _recognizers.add(tap);
      }
      children.add(TextSpan(
        text: p.text,
        style: TextStyle(
          fontWeight: p.bold ? FontWeight.w700 : null,
          fontStyle: p.italic ? FontStyle.italic : null,
          fontFamily: p.code ? 'Consolas' : null,
          backgroundColor: p.code ? Brand.raised2 : null,
          color: p.href != null ? Brand.accent : null,
          decoration: p.href != null ? TextDecoration.underline : null,
          decorationColor: Brand.accent,
        ),
        recognizer: tap,
      ));
    }
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final text = Theme.of(context).textTheme;
    final blocks = parseMarkdown(widget.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          Padding(
            padding: EdgeInsets.only(top: b is MdHeading ? Brand.s5 : Brand.s3),
            child: switch (b) {
              MdHeading() => Text.rich(_spans(b.text, text.titleMedium!.copyWith(fontSize: b.level == 1 ? 19 : 15))),
              MdParagraph() => Text.rich(_spans(b.text, text.bodyMedium!)),
              MdBullets() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in b.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Brand.s1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 9, right: Brand.s3, left: Brand.s1),
                              child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Brand.muted, shape: BoxShape.circle)),
                            ),
                            Expanded(child: Text.rich(_spans(item, text.bodyMedium!))),
                          ],
                        ),
                      ),
                  ],
                ),
            },
          ),
      ],
    );
  }
}

