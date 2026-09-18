import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_span.dart';
import '../data/node.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'search_page.dart';
import 'shell.dart';
import 'widgets/date_fields.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/ink_art.dart';
import 'widgets/paper.dart';

/// Son kullanma tarihi geçen ve yaklaşan eşyalar, bakımı gelenler, altında garantiler ve bakım
/// takvimi. Sol menüden açılır; menüdeki sayı geçen + yaklaşanlar + bakımı gelenler.
class DatesPage extends StatelessWidget {
  const DatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final today = DateTime.now();
    final alerts = store.expiryAlerts;
    final expired = [for (final n in alerts) if (store.expiryOf(n, today) == ExpiryState.expired) n];
    final soon = [for (final n in alerts) if (store.expiryOf(n, today) == ExpiryState.soon) n];
    final warranties = store.warranties;
    final serviceDue = store.serviceDue;
    final dueIds = {for (final n in serviceDue) n.id};
    final serviceLater = [
      for (final n in store.serviceItems)
        if (!dueIds.contains(n.id)) n,
    ];
    final host = LibraryScope.maybeOf(context);
    final otherAlerts = [
      if (host != null)
        for (final e in host.library.entries)
          if (e.id != host.library.activeId && e.alerts.isNotEmpty) e,
    ];

    Widget tile(Node n, String subtitle, {bool service = false}) => RecordTile(
          node: n,
          title: store.nameOf(n),
          subtitle: subtitle,
          detail: store.pathLabel(n.id),
          detailIcon: Icons.place_outlined,
          onTap: () => showNodeFocus(context, n),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bakımı olanda tek dokunuşla "yapıldı" (bildirimde geri alınabilir).
              if (service)
                IconButton(
                  icon: const Icon(Icons.build_circle_outlined),
                  tooltip: s.maintenanceDone,
                  onPressed: () => NodeActions.markMaintained(context, n),
                ),
              IconButton(
                icon: const Icon(Icons.my_location_rounded),
                tooltip: s.goToPlace,
                onPressed: () => revealNode(context, n),
              ),
            ],
          ),
        );

    List<Widget> section(String title, List<Node> nodes, String Function(Node) subtitle, {bool service = false}) => [
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 18, bottom: 8),
            child: Text(
              s.upper(title),
              style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ),
          for (final (i, n) in nodes.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            tile(n, subtitle(n), service: service),
          ],
        ];

    String expiryLine(Node n) {
      final end = n.effectiveExpiry!;
      return '${s.expiryOn(s.formatDate(end))} · ${dueText(s, end, today)}';
    }

    // Satır tek satır ve dar: en önemlisi (ne kadar gecikti, kaç gün kaldı) önce.
    String serviceDueLine(Node n) => [serviceDueText(s, n.nextService!, today), ?n.serviceTask].join(' · ');

    String serviceLaterLine(Node n) {
      final next = n.nextService!;
      return [
        s.formatDate(next),
        serviceDueText(s, next, today),
        s.serviceEveryText(TimeSpan.parse(n.serviceEvery)!),
      ].join(' · ');
    }

    String warrantyLine(Node n) {
      final end = n.effectiveWarrantyEnd!;
      return daysBetween(today, end) < 0
          ? '${s.warrantyEnded} · ${s.formatDate(end)}'
          : '${s.warrantyUntil(s.formatDate(end))} · ${dueText(s, end, today)}';
    }

    return Scaffold(
      appBar: ShellHeader(
        title: s.datesPage,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: alerts.isEmpty && warranties.isEmpty && otherAlerts.isEmpty && store.serviceItems.isEmpty
          ? EmptyState(art: InkArtKind.done, title: s.noDatesSoon, body: s.noDatesSoonHint)
          : ListView(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
              children: [
                if (alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
                    child: Text(s.noDatesSoon, style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (expired.isNotEmpty) ...section(s.expiredSection, expired, expiryLine),
                if (soon.isNotEmpty) ...section(s.expiringSection, soon, expiryLine),
                if (serviceDue.isNotEmpty) ...section(s.serviceDueSection, serviceDue, serviceDueLine, service: true),
                if (warranties.isNotEmpty) ...section(s.warrantySection, warranties, warrantyLine),
                if (serviceLater.isNotEmpty)
                  ...section(s.serviceScheduleSection, serviceLater, serviceLaterLine, service: true),
                if (otherAlerts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 18, bottom: 8),
                    child: Text(
                      s.upper(s.otherDatesSection),
                      style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                  ),
                  for (final e in otherAlerts) ...[
                    Material(
                      color: tones.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => host.openAt(e.id, Arrival(e.id, dates: true)),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: tones.line),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(host!.nameOf(e, s), style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    for (final a in e.alerts.take(5))
                                      Text('• ${a.name} (${a.line})', style: Theme.of(context).textTheme.bodyMedium),
                                    if (e.alerts.length > 5)
                                      Text('• ... (+${e.alerts.length - 5})', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Icon(Icons.swap_horiz_rounded, color: tones.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}
