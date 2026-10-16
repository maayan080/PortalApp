import 'package:flutter/material.dart';

import '../theme/brand.dart';

// below this width a list opens its detail as a new page, above it the detail sits beside the list
const twoPaneWidth = 760.0;

class MasterDetail extends StatelessWidget {
  const MasterDetail({super.key, required this.master, required this.detail, required this.emptyHint});

  final Widget master;

  // null when nothing is selected
  final Widget? detail;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < twoPaneWidth) return master;
      return Row(children: [
        SizedBox(width: 400, child: master),
        const VerticalDivider(width: 1),
        Expanded(
          child: detail == null
              ? Center(child: Text(emptyHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Brand.faint)))
              : Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: detail)),
        ),
      ]);
    });
  }

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= twoPaneWidth;
}
