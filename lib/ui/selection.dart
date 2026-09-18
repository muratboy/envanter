import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/node.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import 'label_flows.dart';
import 'widgets/transfer_dialog.dart';
import 'widgets/tree_picker.dart';

/// Destede toplu seçim. Kabuk tutar: seçim açıkken açık seviyedeki kartlara
/// dokunmak onları seçer, alttaki çubuktaki eylem hepsine birden uygulanır.
/// Yirmi eşyayı tek tek sürüklemek yerine.
class DeckSelection extends ChangeNotifier {
  final Set<String> _ids = {};
  bool _active = false;

  bool get active => _active;
  int get count => _ids.length;
  Set<String> get ids => Set.unmodifiable(_ids);
  bool contains(String id) => _ids.contains(id);

  void start([String? id]) {
    _active = true;
    if (id != null) _ids.add(id);
    notifyListeners();
  }

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Hepsi seçiliyse seçimi boşaltır, değilse hepsini seçer.
  void toggleAll(Iterable<String> ids) {
    final all = ids.toSet();
    if (all.isNotEmpty && _ids.containsAll(all)) {
      _ids.clear();
    } else {
      _ids.addAll(all);
    }
    notifyListeners();
  }

  void end() {
    if (!_active && _ids.isEmpty) return;
    _active = false;
    _ids.clear();
    notifyListeners();
  }

  /// Seviyede artık durmayanlar (taşındı, çöpe gitti, karşıdan değişti) düşer.
  /// Çizim sırasında çağrılır; haber vermez.
  void retain(Set<String> present) => _ids.removeWhere((id) => !present.contains(id));
}

/// Seçim açıkken alt çubuğun yerini alan eylemler: taşı, çekmeceye, QR etiketi,
/// çöpe. Kayıt seçilmemişken sönük durur.
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key, required this.selection, required this.levelId});

  final DeckSelection selection;

  /// Seçimin yapıldığı seviye (sanal kök ya da klasör).
  final String levelId;

  /// Seçilenler destedeki sırasıyla.
  List<Node> _chosen(InventoryStore store) =>
      [for (final n in store.childrenOf(levelId)) if (selection.contains(n.id)) n];

  String _placeLabel(InventoryStore store, String target) => switch (target) {
        Roots.home => store.strings.home,
        Roots.drawer => store.strings.drawer,
        _ => store.pathLabelForParent(target),
      };

  Future<void> _moveTo(BuildContext context, String target) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final moved = await store.moveMany(selection.ids, target);
    selection.end();
    if (moved.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.moveNotPossible)));
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.movedMany(moved.length, _placeLabel(store, target))),
      // Her kayıt eski yerine ve sırasına; kayıpsa yeniden kayıp olur.
      action: SnackBarAction(label: s.undo, onPressed: () => store.restorePlacements(moved)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _move(BuildContext context) async {
    final store = InventoryScope.read(context);
    final roots = store.selectionRoots(selection.ids);
    if (roots.isEmpty) return;
    final target = await pickTreeTargetForMany(context, roots);
    if (target == null || !context.mounted) return;
    await _moveTo(context, target);
  }

  Future<void> _trash(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final trashed = await store.trashMany(selection.ids);
    selection.end();
    if (trashed.isEmpty) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.trashedMany(trashed.length)),
      action: SnackBarAction(label: s.undo, onPressed: () => store.restoreMany(trashed)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final none = selection.count == 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: tones.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: tones.line),
                boxShadow: [
                  BoxShadow(color: tones.shadow.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 10)),
                ],
              ),
              child: Row(
                children: [
                  _BarAction(
                    icon: Icons.drive_file_move_rounded,
                    label: s.moveShort,
                    onTap: none ? null : () => _move(context),
                  ),
                  // Zaten çekmecedeyken "çekmeceye" anlamsız.
                  if (levelId != Roots.drawer)
                    _BarAction(
                      icon: Icons.inbox_rounded,
                      label: s.toDrawerShort,
                      onTap: none ? null : () => _moveTo(context, Roots.drawer),
                    ),
                  _BarAction(
                    icon: Icons.qr_code_2_rounded,
                    label: s.labelsShort,
                    onTap: none ? null : () => LabelFlows.forNodes(context, _chosen(store)),
                  ),
                  if (LibraryScope.maybeOf(context)?.library.entries.length case final len? when len > 1)
                    _BarAction(
                      icon: Icons.swap_horiz_rounded,
                      label: s.transferAction,
                      onTap: none
                          ? null
                          : () async {
                              final nodes = _chosen(store);
                              selection.end();
                              await showTransferDialog(context, nodes);
                            },
                    ),
                  _BarAction(
                    icon: Icons.delete_outline_rounded,
                    label: s.trashShort,
                    color: tones.danger,
                    onTap: none ? null : () => _trash(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final ink = onTap == null ? tones.faint : (color ?? tones.ink);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Tooltip(
          message: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: ink),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
