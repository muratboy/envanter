import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/node.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'shell.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/ink_art.dart';
import 'widgets/paper.dart';

/// Başkalarına ödünç / emanet verilmiş eşyaların listesi. Sol menüden
/// ve ana ekrandaki "Bugün" şeridinden açılır.
class LendingPage extends StatelessWidget {
  const LendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final borrowed = store.borrowedItems;
    final overdue = store.overdueBorrowedItems;
    final active = borrowed.where((n) => !n.isBorrowOverdue).toList();

    Widget tile(Node n) {
      final dueDate = n.returnDueAt;
      final dueText = dueDate != null
          ? (n.isBorrowOverdue
              ? '${s.returnDueDate}: ${s.formatDate(dueDate)} (${s.borrowOverdueShort})'
              : '${s.returnDueDate}: ${s.formatDate(dueDate)}')
          : s.noReturnDueDate;

      final subtitle = '${s.borrower}: ${n.borrowedTo!} · $dueText';

      return RecordTile(
        node: n,
        title: store.nameOf(n),
        subtitle: subtitle,
        detail: store.pathLabel(n.id),
        detailIcon: Icons.place_outlined,
        onTap: () => showNodeFocus(context, n),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.assignment_turned_in_rounded),
              tooltip: s.markReturned,
              color: Colors.green.shade700,
              onPressed: () => NodeActions.markReturned(context, n),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: s.borrowDetailsTitle,
              onPressed: () => NodeActions.promptBorrow(context, n),
            ),
          ],
        ),
      );
    }

    List<Widget> section(String title, List<Node> nodes, {Color? color}) => [
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 18, bottom: 8),
            child: Text(
              s.upper(title),
              style: TextStyle(
                color: color ?? tones.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          for (final (i, n) in nodes.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            tile(n),
          ],
        ];

    return Scaffold(
      appBar: ShellHeader(
        title: s.borrowedPageTitle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: borrowed.isEmpty
          ? EmptyState(
              art: InkArtKind.box,
              title: s.noBorrowedItems,
              body: s.noBorrowedHint,
            )
          : ListView(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
              children: [
                if (overdue.isNotEmpty) ...section(s.overdueSection, overdue, color: tones.danger),
                if (active.isNotEmpty) ...section(s.activeBorrowSection, active),
              ],
            ),
    );
  }
}
