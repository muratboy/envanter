import 'package:flutter/material.dart';

import '../state/inventory_store.dart';
import 'shell.dart';

/// Bir klasörün ici. Karta dokununca kart buyuyup bu ekrana donusur.
class ContainerScreen extends StatelessWidget {
  const ContainerScreen({super.key, required this.containerId, this.highlightId});

  final String containerId;
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final node = store.byId(containerId);

    // Klasör ya da üstündeki bir klasör bu arada silindiyse (ör. başka telefondan çöpe) geri dön.
    if (node == null || !store.isLive(node)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final count = store.childCount(containerId);

    return InventoryShell(
      parentId: containerId,
      highlightId: highlightId,
      title: store.nameOf(node),
      subtitle: '${store.pathLabel(containerId)} · '
          '${count == 0 ? s.empty : s.recordCount(count)}',
      // Basılı tutunca doğrudan ana ekran.
      leading: LevelBackButton(onPressed: () => Navigator.of(context).maybePop()),
      actions: [ContainerMenu(node: node)],
    );
  }
}
