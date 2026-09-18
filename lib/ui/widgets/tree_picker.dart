import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/node.dart';
import '../../state/inventory_store.dart';

/// Yeni yer seçtirir. Donen değer [Roots.home], [Roots.drawer] ya da bir
/// klasör kimligidir.
Future<String?> pickTreeTarget(BuildContext context, {required Node moving}) =>
    pickTreeTargetForMany(context, [moving]);

/// Toplu seçimde: aynı seviyeden birden çok kayıt birlikte taşınır. Seçilen
/// klasörlerin hiçbiri kendi içine gidemez.
Future<String?> pickTreeTargetForMany(BuildContext context, List<Node> moving) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _FolderBrowser(moving: moving),
  );
}

/// Taşımadan yalnızca bir yer seçtirir (ör. sayımın kapsamı): [title] başlıkta, [confirm] düğmede
/// yazar, her yer seçilebilir. Taşıma seçicisine boş liste vermek çöküyordu (taşınan ilk kayıt
/// okunuyordu); sayımda klasör seçilince ekran boş kalıyordu. Dönen değer [pickTreeTarget] gibi.
/// [from] verilirse (başka klasöre gitmek) ağaç orada açılır; orası "buradasın" diye seçilemez.
Future<String?> pickFolder(BuildContext context, {required String title, required String confirm, String? from}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _FolderBrowser(moving: const [], title: title, confirm: confirm, from: from),
  );
}

/// Dosya yöneticilerindeki "taşı" gibi: bir klasörün içinde durulur, üstte
/// yol ve ↑ ile yukarı çıkılır, klasöre dokununca içine girilir, "Buraya
/// taşı" o an bakılan yere taşır. Eskiden bütün ağaç tek listedeydi: açık
/// dal yukarıdaki klasörleri ekranın dışına itiyor, alt klasörler küçük
/// oklarla açılıyor, satıra dokunmak hemen taşıyordu; üst klasörlere
/// gidilebildiği anlaşılmıyordu.
class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser({required this.moving, this.title, this.confirm, this.from});

  /// Taşınanlar; seçim kipinde ([pickFolder]) boş.
  final List<Node> moving;
  final String? title;
  final String? confirm;

  /// Seçim kipinde bulunulan klasör: ağaç orada açılır, oraya gidilmez.
  final String? from;

  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  /// O an içine bakılan yer: sanal kök ya da klasör.
  String? _at;

  /// Kayıtların şu an durduğu yer; oraya taşımak anlamsız.
  late String _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_at != null) return;
    final store = InventoryScope.read(context);
    final first = widget.moving.firstOrNull;
    if (first == null) {
      // Seçim kipi: hiçbir kayıt bir yerde durmuyor; ana ekrandan ya da bulunulan klasörden başlanır.
      _current = widget.from ?? '';
      _at = _browsable(store, widget.from) ? widget.from : Roots.home;
      return;
    }
    _current = store.bucketKey(first);
    // Kaldığı klasörde açılır; kayıp eşya son görüldüğü yerde.
    final start = _current == Roots.lost ? first.lostFrom : _current;
    _at = _browsable(store, start) ? start : Roots.home;
  }

  bool _browsable(InventoryStore store, String? level) {
    if (level == null) return false;
    if (level == Roots.home || level == Roots.drawer) return true;
    final n = store.byId(level);
    return n != null && n.isContainer && store.isLive(n) && !_blocked(store).contains(level);
  }

  /// Taşınan klasörlerin kendi alt ağaçları hedef olamaz.
  Set<String> _blocked(InventoryStore store) => {for (final m in widget.moving) ...store.subtreeIds(m.id)};

  /// Bakılan yerin bir üstü; köklerde yok.
  String? _parentOf(InventoryStore store, String level) {
    if (Roots.isVirtual(level)) return null;
    final n = store.byId(level);
    return n == null ? Roots.home : store.bucketKey(n);
  }

  void _go(String level) => setState(() => _at = level);

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final first = widget.moving.firstOrNull;
    // Bakılan klasör bu arada silindiyse (ör. eşitlemeyle) ana ekrana dönülür.
    final at = _browsable(store, _at) ? _at! : Roots.home;
    final blocked = _blocked(store);
    final folders = [
      for (final n in store.childrenOf(at))
        if (n.isContainer && !blocked.contains(n.id)) n,
    ];
    final parent = _parentOf(store, at);
    // Yol: kök, sonra baştan sona klasörler; her parçaya dokununca oraya çıkılır.
    final chain = Roots.isVirtual(at) ? const <Node>[] : [...store.ancestorsOf(at), store.byId(at)!];
    final root = chain.isEmpty ? at : store.bucketKey(chain.first);
    final here = at == _current;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    widget.title ??
                        (first != null && widget.moving.length == 1
                            ? s.whereShouldGo(store.nameOf(first))
                            : s.whereShouldGoMany(widget.moving.length)),
                    style: theme.textTheme.headlineSmall?.copyWith(fontSize: 21)),
                if (first != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.currentlyAt(_current == Roots.lost
                        ? s.lostDrawer
                        : store.pathLabelForParent(first.parentId, inDrawer: first.inDrawer)),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                // İki kök her zaman bir dokunuş uzakta.
                Row(
                  children: [
                    for (final (id, icon, label) in [
                      (Roots.home, Icons.home_rounded, s.home),
                      (Roots.drawer, Icons.inbox_rounded, s.drawer),
                    ]) ...[
                      ChoiceChip(
                        avatar: Icon(icon, size: 18),
                        label: Text(label),
                        selected: root == id,
                        showCheckmark: false,
                        onSelected: (_) => _go(id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Yol ve yukarı çık.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: s.upOneLevel,
                  onPressed: parent == null ? null : () => _go(parent),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                // Uzun yolda son parça (bakılan yer) görünsün diye sondan
                // kaydırılır; kısa yol yine sola, ↑'nin yanına dayanır.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: box.maxWidth),
                        child: Row(
                          children: [
                            _Crumb(
                              label: switch (root) {
                                Roots.drawer => s.drawer,
                                Roots.lost => s.lostDrawer,
                                _ => s.home,
                              },
                              current: chain.isEmpty,
                              // Kayıp çekmecesi hedef değil; oradan ana ekrana çıkılır.
                              onTap: () => _go(root == Roots.drawer ? Roots.drawer : Roots.home),
                            ),
                            for (final (i, n) in chain.indexed) ...[
                              Icon(Icons.chevron_right_rounded, size: 18, color: tones.faint),
                              _Crumb(
                                label: store.nameOf(n),
                                current: i == chain.length - 1,
                                onTap: () => _go(n.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: folders.isEmpty
                ? ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(32),
                    children: [
                      Text(
                        // Bulunulan klasöre gidilmez: "burayı seçebilirsin" demesin.
                        widget.confirm == null
                            ? s.noFoldersHere
                            : (here ? s.noFoldersWhereYouAre : s.noFoldersInside),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final f in folders) _row(store, f, blocked),
                    ],
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // Kayıtlar zaten buradaysa taşınacak bir şey yok; bulunulan klasöre de gidilmez.
                  onPressed: here ? null : () => Navigator.of(context).pop(at),
                  icon: Icon(widget.confirm == null ? Icons.drive_file_move_rounded : Icons.check_rounded),
                  label: Text(here
                      ? (widget.confirm == null ? s.alreadyHere : s.youAreHere)
                      : widget.confirm ?? s.moveHere),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Klasör satırı: dokununca içine girilir. Alt klasörü varsa sayısı yazar.
  Widget _row(InventoryStore store, Node folder, Set<String> blocked) {
    final s = store.strings;
    final tones = Tones.of(context);
    final inside = store.childrenOf(folder.id).where((n) => n.isContainer && !blocked.contains(n.id)).length;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(Icons.inventory_2_rounded, color: Color(folder.color)),
      title: Text(store.nameOf(folder), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: folder.id == _current
          ? Text(widget.moving.isEmpty ? s.youAreHere : s.currentPlace)
          : (inside > 0 ? Text(s.folderCount(inside)) : null),
      trailing: Icon(Icons.chevron_right_rounded, color: tones.faint),
      onTap: () => _go(folder.id),
    );
  }
}

/// Yoldaki tek parça; sonuncusu (bakılan yer) kalın.
class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.current, required this.onTap});

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: current ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
            color: current ? tones.ink : tones.muted,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }
}
