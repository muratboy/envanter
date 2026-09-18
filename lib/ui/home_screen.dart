import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/theme.dart';

import '../state/inventory_store.dart';
import 'audit_page.dart';
import 'shell.dart';
import '../state/inventory_host.dart';
import 'widgets/inventory_emblem.dart';
import 'widgets/today_strip.dart';

/// Ana ekran: kök seviyedeki kartlarin destesi.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final count = store.childrenOf(Roots.home).length;
    final host = LibraryScope.maybeOf(context);

    return InventoryShell(
      parentId: Roots.home,
      showLeftDrawer: true,
      // Renk ya da amblem seçildiyse adın önünde: hangi envanter, bir bakışta.
      titleBadge: host != null && host.library.active.hasLook
          ? InventoryEmblem(entry: host.library.active, size: 26, active: true)
          : null,
      // Envanterin adı (verilmediyse uygulamanın adı).
      title: host == null ? s.appTitle : host.nameOf(host.library.active, s),
      subtitle: count == 0 ? s.nothingYet : s.itemsAtRoot(count),
      // Üstte: ilk kartlar oluşunca bir kez ipuçları (sürükleme ve çekmece kolay
      // fark edilmiyor) ve "bugün" şeridi (boşsa yer kaplamaz).
      banner: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (count > 0 && !store.settings.tipsSeen) const _TipsCard(),
          // Şerit belirirken/kaybolurken deste bir anda zıplamasın. Sürüklerken
          // hareketsiz (parmağın altındaki hedefler kaymasın).
          AnimatedSize(
            duration: store.draggingId == null ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: const TodayStrip(),
          ),
        ],
      ),
      leading: Builder(
        builder: (context) => IconButton(
          // Yedek hatırlatması ve son kullanma uyarısı menünün içinde; burada
          // yalnızca küçük bir nokta.
          icon: Badge(
            isLabelVisible: store.backupDue || store.expiryAlerts.isNotEmpty || store.serviceDue.isNotEmpty,
            smallSize: 8,
            backgroundColor: Tones.of(context).accent,
            child: const Icon(Icons.menu_rounded),
          ),
          tooltip: s.menu,
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      actions: [
        if (count > 0)
          PopupMenuButton<void>(
            tooltip: s.moreActions,
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                onTap: () => InventoryShell.startSelection(ctx),
                child: ListTile(
                  leading: const Icon(Icons.checklist_rounded),
                  title: Text(s.select),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                onTap: () => AuditPage.start(ctx),
                child: ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(s.auditInventory),
                  dense: true,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// İlk açılış ipuçları: masaya bantlanmış bir not kağıdı.
class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final note = cardTone(kCardPalette[6].toARGB32(), Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Transform.rotate(
          angle: -0.012,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 10, 6),
                decoration: BoxDecoration(
                  color: note,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: tones.shadow.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tipTitle,
                      style: const TextStyle(fontFamily: kDisplayFont, fontSize: 19, fontWeight: FontWeight.w600, color: kInk),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.tipBody,
                      style: TextStyle(fontSize: 13, height: 1.45, color: kInk.withValues(alpha: 0.78)),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(foregroundColor: kInk),
                        onPressed: () => store.updateSettings(store.settings.copyWith(tipsSeen: true)),
                        child: Text(s.gotIt),
                      ),
                    ),
                  ],
                ),
              ),
              // Üstte yarı saydam bant.
              Positioned(
                top: -10,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.rotate(
                    angle: 0.04,
                    child: Container(width: 84, height: 22, color: const Color(0x99EFE6CC)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
