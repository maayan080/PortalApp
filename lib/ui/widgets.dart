import 'package:flutter/material.dart';

import '../theme/brand.dart';

// the catalogue cover when there is one, otherwise the app's first letter
class AppThumb extends StatelessWidget {
  const AppThumb({super.key, required this.name, this.cover, this.size = 48, this.aspect = 1});

  final String name;
  final Uri? cover;

  // the height, the width is height times aspect. store covers are wide banners
  final double size;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final radius = BorderRadius.circular(size * 0.2);
    final fallback = Center(
      child: Text(letter, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: size * 0.4, color: Brand.muted)),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          width: size * aspect,
          height: size,
          decoration: BoxDecoration(color: Brand.raised2, borderRadius: radius, border: Border.all(color: Brand.line)),
          child: cover == null
              ? fallback
              : Image.network(
                  cover.toString(),
                  fit: BoxFit.cover,
                  // decode at thumbnail size, some covers are over a megabyte
                  cacheWidth: (size * aspect * MediaQuery.devicePixelRatioOf(context)).round(),
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : fallback,
                ),
        ),
      ),
    );
  }
}

enum PillKind { update, running, quiet }

// a short status word. the accent is saved for updates, the one thing that wants a tap
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.kind = PillKind.quiet});

  final String label;
  final PillKind kind;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!;
    final (color, border) = switch (kind) {
      PillKind.update => (Brand.accent, Brand.accent),
      PillKind.running => (Brand.success, Brand.line),
      PillKind.quiet => (Brand.muted, Brand.line),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (kind == PillKind.running) ...[
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.success, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label, style: style.copyWith(color: color)),
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Brand.s4, Brand.s5, Brand.s4, Brand.s2),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Brand.muted, letterSpacing: 1))),
        ?trailing,
      ]),
    );
  }
}

// a list row with a hairline under it, no card. 64 high so a thumb can hit it
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? Brand.raised : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: Brand.s4, vertical: Brand.s3),
            decoration: BoxDecoration(border: divider ? const Border(bottom: BorderSide(color: Brand.line)) : null),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: Brand.s3)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(fontSize: 13)),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: Brand.s3), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

// teaches what to do next rather than only saying nothing is here
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Brand.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: Brand.s2),
            Text(body, style: text.bodyMedium?.copyWith(color: Brand.muted)),
            if (action != null) ...[const SizedBox(height: Brand.s4), action!],
          ]),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Brand.s4, Brand.s5, Brand.s2, Brand.s2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.headlineMedium),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: text.bodySmall?.copyWith(fontSize: 13))),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Brand.s4, Brand.s3, Brand.s4, Brand.s2),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20, color: Brand.faint),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close, size: 18), onPressed: controller.clear),
          ),
        ),
      ),
    );
  }
}

class FactRow extends StatelessWidget {
  const FactRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Brand.s2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 112, child: Text(label, style: text.bodySmall?.copyWith(fontSize: 13))),
        Expanded(child: SelectableText(value, style: text.bodyMedium?.copyWith(fontSize: 14))),
      ]),
    );
  }
}

class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: Brand.raised2, borderRadius: BorderRadius.circular(4)));
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: Brand.s4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Brand.raised2, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: Brand.s3),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 14), const SizedBox(height: 8), bar(220, 11)]),
      ]),
    );
  }
}
