import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/theme.dart';
import '../../core/time_span.dart';
import '../../state/inventory_store.dart';
import '../dates_page.dart';
import '../lending_page.dart';
import '../shell.dart';
import '../shopping_page.dart';

/// Ana ekranın üstündeki "bugün" şeridi: ilgi isteyen şeyler damga gibi küçük
/// etiketlerde (tarihi geçen, yaklaşan, alınacak, yerleştirilecek, kayıp,
/// çekmecede bekleyen). Yalnızca sayısı sıfırdan büyük olanlar görünür;
/// dokununca ilgili yer açılır. Hiçbiri yoksa şerit de yoktur.
///
/// Bu bilgiler sol menüde ve sağ kenardaki kulplarda zaten var, ama dağınık:
/// uygulamayı açan kişi "bugün neye bakmalıyım"ı tek satırda görsün.
class TodayStrip extends StatelessWidget {
  const TodayStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final size = MediaQuery.sizeOf(context);
    // Yatay telefonda yer dar: aynı sayılar başlıktaki düğmelerde duruyor.
    if (landscapeLayout(context) && size.height < 520) return const SizedBox.shrink();

    final expired = store.expiredItems.length;
    final soon = store.expiryAlerts.where((n) => store.expiryOf(n) == ExpiryState.soon).length;
    final service = store.serviceDue;
    final serviceLate = service.any((n) => n.serviceStateOn(DateTime.now()) == ExpiryState.expired);
    final toBuy = store.shoppingCount;
    final toPutAway = store.toPutAway.length;
    final lost = store.childrenOf(Roots.lost).length;
    final drawer = store.childrenOf(Roots.drawer).length;
    final overdueBorrow = store.overdueBorrowedItems.length;
    final borrowed = store.borrowedItems.length;

    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    final chips = [
      if (expired > 0)
        _Chip(Icons.event_busy_rounded, s.todayExpired(expired), tones.danger, () => push(const DatesPage())),
      if (soon > 0) _Chip(Icons.event_rounded, s.todaySoon(soon), tones.lost, () => push(const DatesPage())),
      // Bakımı gelenler; biri gecikmişse kırmızı.
      if (service.isNotEmpty)
        _Chip(Icons.build_circle_outlined, s.todayService(service.length), serviceLate ? tones.danger : tones.lost,
            () => push(const DatesPage())),
      if (overdueBorrow > 0)
        _Chip(Icons.front_hand_rounded, s.todayOverdueBorrow(overdueBorrow), tones.danger, () => push(const LendingPage()))
      else if (borrowed > 0)
        // Renksiz (çekmece gibi): `tones.raised` koyu temada yazıyı zeminle aynı renge boyuyordu.
        _Chip(Icons.front_hand_rounded, s.todayBorrowed(borrowed), null, () => push(const LendingPage())),
      if (toBuy > 0)
        _Chip(Icons.shopping_cart_outlined, s.todayToBuy(toBuy), tones.accent, () => push(const ShoppingPage())),
      if (toPutAway > 0)
        _Chip(Icons.move_to_inbox_rounded, s.todayToPutAway(toPutAway), tones.success, () => push(const ShoppingPage())),
      if (lost > 0)
        _Chip(Icons.travel_explore_rounded, s.todayLost(lost), tones.lost, () => InventoryShell.openLostPanel(context)),
      if (drawer > 0)
        _Chip(Icons.inbox_rounded, s.todayInDrawer(drawer), null, () => InventoryShell.openDrawerPanel(context)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    // Şerit sabit boyda: yazı büyütmesi sınırlı, boyu onunla birlikte uzar.
    final scale = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, kFixedTextScale);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kFixedTextScale,
      child: SizedBox(
        height: 30 * scale + 12,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final chip = chips[i];
            // Renksiz olan (çekmece) mürekkep tonunda.
            final color = chip.color ?? tones.ink;
            final dark = Theme.of(context).brightness == Brightness.dark;
            // Açık temada koyu bir ton, koyu temada rengin kendisi okunur.
            final text = chip.color == null
                ? tones.ink
                : dark
                    ? Color.lerp(color, Colors.white, 0.18)!
                    : Color.lerp(color, kInk, 0.35)!;
            return Material(
              color: color.withValues(alpha: chip.color == null ? 0.08 : 0.17),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: chip.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chip.icon, size: 15, color: text),
                      const SizedBox(width: 6),
                      Text(
                        chip.label,
                        style: TextStyle(color: text, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Chip {
  const _Chip(this.icon, this.label, this.color, this.onTap);

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
}
