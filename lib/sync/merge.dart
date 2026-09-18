import '../data/node.dart';
import 'fields.dart';

/// İki envanterin birleştirilmesi. Arayüzden ve veritabanından bağımsız,
/// saf bir hesap: ne eklenecek, ne değişecek, ne silinecek.
///
/// Kural her alan grubu için "son yazan kazanır" ([mergeNode]): aynı eşyada
/// biri adedi, öbürü adı değiştirdiyse ikisi de kalır. Çöpe atma da bir
/// düzenleme olduğu için aynı kuralla yayılır. Kalıcı silmeler ise kayıt
/// ortadan kalktığı için ayrıca "iz" (tombstone) olarak taşınır; yoksa
/// karşı taraf eski kaydı her içe aktarmada geri getirirdi.
///
/// Birleşme ağaç bütünlüğünü bozabilir: biri bir klasörü kalıcı
/// silerken öbürü içine eşya koymuş olabilir, ya da iki kişi A'yı B'ye,
/// B'yi A'ya taşımış olabilir. Böyle kayıtlar kaybolmasın diye
/// çekmeceye alınır.
class MergeResult {
  MergeResult({
    required this.upserts,
    required this.removals,
    required this.tombstones,
    required this.clearedTombstones,
    required this.imagesToCopy,
    required this.stats,
  });

  /// Yerelde yazılacak (yeni ya da değişen) kayıtlar.
  final List<Node> upserts;

  /// Yerelden kalıcı silinecek kayıt kimlikleri.
  final Set<String> removals;

  /// Birleşme sonrası geçerli kalıcı silme izleri (kimlik → zaman, ms).
  final Map<String, int> tombstones;

  /// Silindikten sonra düzenlendiği için geri dönen kayıtların izleri.
  final Set<String> clearedTombstones;

  /// Gelen dosyadan kopyalanması gereken resimler (göreli yol).
  final Set<String> imagesToCopy;

  final MergeStats stats;

  bool get changesAnything =>
      upserts.isNotEmpty || removals.isNotEmpty || clearedTombstones.isNotEmpty;
}

class MergeStats {
  int added = 0;
  int updated = 0;

  /// [updated] içinden, karşı tarafta çöpe atılmış olanlar.
  int trashed = 0;
  int removed = 0;

  /// İki tarafta da vardı, karşıdakinde bizim bilmediğimiz bir şey yoktu.
  int keptLocal = 0;

  /// Yeri kaybolduğu ya da döngüye girdiği için çekmeceye alınanlar.
  int relocated = 0;

  /// İncelemeye alınan (henüz uygulanmamış) değişiklikler.
  int pending = 0;

  bool get isEmpty =>
      added + updated + removed + keptLocal + relocated == 0;
}

MergeResult mergeInventories({
  required Map<String, Node> local,
  required Map<String, int> localTombstones,
  required Map<String, Node> incoming,
  required Map<String, int> incomingTombstones,
  required DateTime now,
  String? author,
}) {
  final stats = MergeStats();

  // İzlerin birleşimi; aynı kayıt için daha geç olan silme zamanı.
  final tombstones = Map<String, int>.of(localTombstones);
  incomingTombstones.forEach((id, at) {
    final mine = tombstones[id];
    if (mine == null || at > mine) tombstones[id] = at;
  });

  final result = Map<String, Node>.of(local);
  final changed = <String>{};
  final clearedTombstones = <String>{};
  final fromIncoming = <String>{};

  for (final inc in incoming.values) {
    final loc = local[inc.id];
    final purgedAt = tombstones[inc.id];
    final editedAt = inc.updatedAt.millisecondsSinceEpoch;

    if (purgedAt != null) {
      if (purgedAt >= editedAt) continue; // silindikten sonra dokunulmamış
      // Silindikten sonra biri düzenlemiş: veri kaybetmemek için geri gelir.
      tombstones.remove(inc.id);
      clearedTombstones.add(inc.id);
    }

    if (loc == null) {
      result[inc.id] = inc;
      changed.add(inc.id);
      fromIncoming.add(inc.id);
      stats.added++;
    } else {
      final merged = mergeNode(loc, inc);
      if (sameVersion(merged, loc)) {
        if (!sameVersion(inc, loc)) stats.keptLocal++;
        continue;
      }
      result[inc.id] = merged;
      changed.add(inc.id);
      // Yalnızca zamanları ilerleyen kayıt (değerler aynı) sayılmaz.
      if (differingFields(loc, merged).isEmpty) continue;
      fromIncoming.add(inc.id);
      stats.updated++;
      if (merged.isDeleted && !loc.isDeleted) stats.trashed++;
    }
  }

  // Karşı tarafın kalıcı sildiği, bizde o zamandan beri dokunulmamış kayıtlar.
  final removals = <String>{};
  for (final loc in local.values) {
    final purgedAt = tombstones[loc.id];
    if (purgedAt == null || clearedTombstones.contains(loc.id)) continue;
    if (loc.updatedAt.millisecondsSinceEpoch <= purgedAt) {
      removals.add(loc.id);
      result.remove(loc.id);
      changed.remove(loc.id);
      stats.removed++;
    }
  }

  // Ağaç bütünlüğü.
  Node toDrawer(Node n) {
    stats.relocated++;
    changed.add(n.id);
    return stampChanges(n, n.copyWith(clearParent: true, inDrawer: true, updatedAt: now, updatedBy: author), now);
  }

  // 1) Üstü yok olmuş ya da üstü artık klasör olmayan kayıtlar.
  for (final n in result.values.toList()) {
    final parentId = n.parentId;
    if (parentId == null) continue;
    final parent = result[parentId];
    if (parent == null || !parent.isContainer) result[n.id] = toDrawer(n);
  }

  // 2) Döngüler: A'nın atası B, B'nin atası A. Döngüdeki en eski
  //    taşıma geri alınır; daha yeni niyet (son taşıma) korunur.
  final settled = <String>{};
  for (final start in result.keys.toList()) {
    if (settled.contains(start)) continue;
    final chain = <String>[];
    final onChain = <String>{};
    String? cur = start;
    while (cur != null && !settled.contains(cur)) {
      if (onChain.contains(cur)) {
        final cycle = chain.sublist(chain.indexOf(cur));
        int movedAt(String id) => result[id]!.timeOf(NodeField.placement);
        final oldest = cycle.reduce(
          (a, b) => movedAt(a) < movedAt(b) || (movedAt(a) == movedAt(b) && a.compareTo(b) < 0) ? a : b,
        );
        result[oldest] = toDrawer(result[oldest]!);
        break;
      }
      onChain.add(cur);
      chain.add(cur);
      cur = result[cur]?.parentId;
    }
    settled.addAll(chain);
  }

  final upserts = [for (final id in changed) result[id]!];

  final imagesToCopy = <String>{
    for (final id in fromIncoming)
      if (result[id]?.imagePath case final path? when path.isNotEmpty)
        if (local[id]?.imagePath != path) path,
  };

  return MergeResult(
    upserts: upserts,
    removals: removals,
    tombstones: tombstones,
    clearedTombstones: clearedTombstones,
    imagesToCopy: imagesToCopy,
    stats: stats,
  );
}
