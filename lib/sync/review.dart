import 'package:flutter/foundation.dart';

import '../data/node.dart';
import 'fields.dart';

/// Ortak kullanımda karşıdan gelen değişikliklerin incelenmesi.
///
/// İnceleme açıkken karşıdan gelen yeni sürümler hemen uygulanmaz; "bekleyen
/// değişiklik" olarak durur. Kullanıcı tek tek ya da topluca kabul eder,
/// isterse reddeder. Bu dosya saf hesaptır: neyin bekleyeceğini ve her
/// değişikliğin ne olduğunu bulur; uygulamayı mağaza yapar.

enum ChangeKind { added, edited, moved, reordered, trashed, restored, deleted, lost, found }

/// Karşıdan gelmiş, henüz kabul edilmemiş tek bir kayıt sürümü. Kayıt
/// karşıdan geldiği gibi durur; kabul edilince bizdekiyle alan alan
/// birleşir ([candidateOf]), yani arada bizim başka bir alanda yaptığımız
/// değişiklik kaybolmaz.
class PendingChange {
  const PendingChange({
    required this.nodeId,
    required this.incoming,
    required this.purgedAt,
    required this.receivedAt,
    this.via,
    this.by,
  });

  /// Kayıt sürümü. Kalıcı silmelerde null; o zaman [purgedAt] dolu.
  final Node? incoming;
  final String nodeId;
  final int? purgedAt;
  final DateTime receivedAt;

  /// Değişikliği bize getiren cihaz.
  final String? via;

  /// Değişikliği yapan, kayıttaki yazardan farklıysa ([attributedTo]).
  final String? by;

  bool get isDeletion => incoming == null;

  /// Değişikliğin karşıda yapıldığı an.
  DateTime get changedAt =>
      incoming?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(purgedAt ?? 0);

  /// Değişikliği yapan cihaz; bilinmiyorsa getiren cihaz.
  String? get author => by ?? incoming?.updatedBy ?? via;

  PendingChange withVia(String? device) => PendingChange(
        nodeId: nodeId,
        incoming: incoming,
        purgedAt: purgedAt,
        receivedAt: receivedAt,
        via: device,
        by: by,
      );

  /// Kaydın son yazarı biziz (karşı taraf bizim daha yeni bir alan
  /// değişikliğimizi kendi değişikliğiyle birleştirmiş): bekleyen kısım bizim
  /// değil, getiren cihazın. Yoksa listede "Sen düzenledin" yazar, yetkili
  /// birinin değişikliği de onaya düşerdi.
  PendingChange attributedTo(String? me) {
    if (me == null || via == null || incoming?.updatedBy != me) return this;
    return PendingChange(
      nodeId: nodeId,
      incoming: incoming,
      purgedAt: purgedAt,
      receivedAt: receivedAt,
      via: via,
      by: via,
    );
  }

  Map<String, Object?> toJson() => {
        'nodeId': nodeId,
        'incoming': incoming?.toMap(),
        'purgedAt': purgedAt,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'via': via,
        if (by != null) 'by': by,
      };

  static PendingChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['nodeId'];
    if (id is! String || id.isEmpty) return null;
    final raw = json['incoming'];
    final Node? incoming;
    try {
      incoming = raw is Map ? Node.fromMap(Map<String, Object?>.from(raw)) : null;
    } on Object {
      return null;
    }
    final purged = json['purgedAt'];
    if (incoming == null && purged is! int) return null;
    final received = json['receivedAt'];
    return PendingChange(
      nodeId: id,
      incoming: incoming,
      purgedAt: purged is int ? purged : null,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(received is int ? received : 0),
      via: json['via'] is String ? json['via'] as String : null,
      by: json['by'] is String ? json['by'] as String : null,
    );
  }
}

/// Kullanıcının göreceği bir fark var mı? Yalnızca zamanı (ya da türetilmiş
/// parmak izi) değişmiş kayıtlar incelemeye düşmez, sessizce alınır.
bool sameContent(Node a, Node b) =>
    a.parentId == b.parentId &&
    a.inDrawer == b.inDrawer &&
    a.kind == b.kind &&
    a.name == b.name &&
    a.color == b.color &&
    a.imagePath == b.imagePath &&
    a.lat == b.lat &&
    a.lng == b.lng &&
    (a.locationLabel ?? '') == (b.locationLabel ?? '') &&
    (a.note ?? '') == (b.note ?? '') &&
    a.sortIndex == b.sortIndex &&
    a.isDeleted == b.isDeleted &&
    a.isLost == b.isLost &&
    a.lostFrom == b.lostFrom &&
    a.icon == b.icon &&
    a.quantity == b.quantity &&
    listEquals(a.lots, b.lots) &&
    a.minQuantity == b.minQuantity &&
    a.wantedAt == b.wantedAt &&
    a.buyingBy == b.buyingBy &&
    a.buyingAt == b.buyingAt &&
    a.boughtAt == b.boughtAt &&
    a.autoShop == b.autoShop &&
    a.isFull == b.isFull &&
    a.heldBy == b.heldBy &&
    sameDates(a, b) &&
    listEquals(a.attachments, b.attachments) &&
    a.barcode == b.barcode &&
    a.unit == b.unit &&
    a.borrowedTo == b.borrowedTo &&
    a.borrowedAt == b.borrowedAt &&
    a.returnDueAt == b.returnDueAt &&
    a.price == b.price &&
    a.serial == b.serial &&
    sameService(a, b) &&
    listEquals(a.managers, b.managers);

/// Bakımın planı ve kaydı aynı mı (aralık, ne yapılacağı, son bakım, geçmiş).
bool sameService(Node a, Node b) =>
    a.serviceEvery == b.serviceEvery &&
    a.serviceTask == b.serviceTask &&
    a.servicedAt == b.servicedAt &&
    listEquals(a.serviceLog, b.serviceLog);

/// Değişiklik kabul edilirse kaydın alacağı hal: bizdekiyle alan alan
/// birleşmiş sürüm. Arayüz "ne değişecek"i bununla gösterir.
Node? candidateOf(PendingChange change, Node? local) {
  final inc = change.incoming;
  return inc == null || local == null ? inc : mergeNode(local, inc);
}

/// Kayıp bildirimi ya da bulunma: onay beklemez. Eşyanın nerede olduğunu
/// bilen yok; kayıt yalnızca "arayın" diye işaretlenir, bulan da yerini
/// hemen herkese bildirir.
///
/// Bulunan eşya bizde henüz olmayan (onay bekleyen yeni) bir klasöre
/// konduysa bu sayılmaz: klasörle birlikte onaya düşer, yoksa eşya yersiz
/// kalırdı.
///
/// [merged]: gelen sürümün bizdekiyle birleşmiş hali (karşıdaki yer bilgisi
/// bizimkinden eskiyse zaten kaybolmuş/bulunmuş sayılmaz).
bool isLostFlow(Map<String, Node> local, Node merged) {
  final loc = local[merged.id];
  if (loc == null || loc.isLost == merged.isLost) return false;
  final parent = merged.parentId;
  return parent == null || local.containsKey(parent);
}

/// Satın alma, son kullanma, garanti ve uyarı süresi aynı mı.
bool sameDates(Node a, Node b) =>
    a.purchasedAt == b.purchasedAt &&
    a.expiresAt == b.expiresAt &&
    a.shelfLife == b.shelfLife &&
    a.warrantyEndsAt == b.warrantyEndsAt &&
    a.warranty == b.warranty &&
    a.expiryWarn == b.expiryWarn;

/// Biri ortak kaydı kendi özel alanına aldı: kayıp bildirimi gibi onay
/// beklemez. Sahibi artık kaydı göndermiyor; bu son haberi reddetmenin bir
/// anlamı yok, kayıt yalnızca "Ayşe'de" diye çekmecede işaretlenir. Başkasının
/// onu oradan bir yere koyması ise sıradan taşımadır, onaya düşer.
bool isHeldFlow(Map<String, Node> local, Node merged) {
  final loc = local[merged.id];
  if (loc == null || merged.heldBy == null || loc.heldBy == merged.heldBy) return false;
  final parent = merged.parentId;
  return parent == null || local.containsKey(parent);
}

/// Kayıp/bulunma ve "Ayşe'de" haberi yalnızca kaydın yerini ilgilendirir;
/// aynı sürümdeki başka değişiklikler (ad, adet) yine onaya düşer. Bu,
/// kaydımıza yalnızca gelen yer bilgisinin konmuş hali.
Node _placementOnly(Node loc, Node inc) {
  final times = loc.allFieldTimes..[NodeField.placement.name] = inc.timeOf(NodeField.placement);
  return takeField(loc, inc, NodeField.placement).copyWith(
    fieldTimes: times,
    updatedAt: inc.updatedAt,
    updatedBy: inc.updatedBy,
  );
}

/// Onay beklemeden alınacak kısım; yoksa null.
Node? _quietPart(Map<String, Node> local, Node loc, Node inc) {
  final merged = mergeNode(loc, inc);
  if (sameVersion(merged, loc)) return null;
  if (sameContent(loc, merged)) return inc;
  if (isLostFlow(local, merged) || isHeldFlow(local, merged)) return _placementOnly(loc, inc);
  return null;
}

/// Gelen durumdan, bizdekine görünür bir şey katan (ve bizim kalıcı
/// sildiğimiz bir kaydı sessizce geri getirmeyen) sürümleri çıkarır. Yalnızca
/// zamanı değişenler ve kayıp/"Ayşe'de" haberleri listeye girmez; onları
/// [quietIncoming] verir.
List<PendingChange> stageIncoming({
  required Map<String, Node> local,
  required Map<String, int> localTombstones,
  required Map<String, Node> incoming,
  required Map<String, int> incomingTombstones,
  required DateTime now,
}) {
  final staged = <PendingChange>[];
  for (final inc in incoming.values) {
    final purgedAt = localTombstones[inc.id];
    if (purgedAt != null && purgedAt >= inc.updatedAt.millisecondsSinceEpoch) continue;
    final loc = local[inc.id];
    if (loc != null) {
      final quiet = _quietPart(local, loc, inc);
      final base = quiet == null ? loc : mergeNode(loc, quiet);
      if (sameContent(base, mergeNode(base, inc))) continue;
    }
    staged.add(PendingChange(nodeId: inc.id, incoming: inc, purgedAt: null, receivedAt: now));
  }
  incomingTombstones.forEach((id, at) {
    final loc = local[id];
    if (loc == null || loc.updatedAt.millisecondsSinceEpoch > at) return;
    if (incoming.containsKey(id)) return; // aynı anda hem sürüm hem iz: sürüm kazanır
    staged.add(PendingChange(nodeId: id, incoming: null, purgedAt: at, receivedAt: now));
  });
  return staged;
}

/// İncelemeden doğrudan alınanlar (bizdekiyle birleştirilecek sürümler):
/// görünür farkı olmayanlar, kayıp bildirimi / bulunma ([isLostFlow]) ve
/// "Ayşe'de" haberi ([isHeldFlow]); son ikisinde yalnızca yer bilgisi.
Map<String, Node> quietIncoming({
  required Map<String, Node> local,
  required Map<String, Node> incoming,
}) =>
    {
      for (final inc in incoming.values)
        if (local[inc.id] case final loc?) inc.id: ?_quietPart(local, loc, inc),
    };

/// Bir değişikliğin ne olduğu; metni arayüz kurar.
class ChangeSummary {
  const ChangeSummary({
    required this.kind,
    this.oldName,
    this.newName,
    this.renamed = false,
    this.moved = false,
    this.imageChanged = false,
    this.colorChanged = false,
    this.noteChanged = false,
    this.kindChanged = false,
    this.locationChanged = false,
    this.iconChanged = false,
    this.managersChanged = false,
    this.quantityChanged = false,
    this.minQuantityChanged = false,
    this.wantedChanged = false,
    this.fullChanged = false,
    this.datesChanged = false,
    this.attachmentsChanged = false,
    this.barcodeChanged = false,
    this.borrowChanged = false,
    this.priceChanged = false,
    this.serialChanged = false,
    this.serviceChanged = false,
  });

  final ChangeKind kind;
  final String? oldName;
  final String? newName;
  final bool renamed;
  final bool moved;
  final bool imageChanged;
  final bool colorChanged;
  final bool noteChanged;
  final bool kindChanged;
  final bool locationChanged;
  final bool iconChanged;
  final bool managersChanged;
  final bool quantityChanged;
  final bool minQuantityChanged;

  /// Alışveriş listesine eklendi ya da listeden çıktı.
  final bool wantedChanged;
  final bool fullChanged;
  final bool datesChanged;
  final bool attachmentsChanged;
  final bool barcodeChanged;
  final bool borrowChanged;
  final bool priceChanged;
  final bool serialChanged;

  /// Bakım döngüsü ya da kaydı ("bakım yapıldı") değişti.
  final bool serviceChanged;
}

ChangeSummary describeChange(PendingChange change, Node? local) {
  final inc = candidateOf(change, local);
  if (inc == null) {
    return ChangeSummary(kind: ChangeKind.deleted, oldName: local?.trimmedName);
  }
  if (local == null) {
    return ChangeSummary(
      kind: inc.isDeleted ? ChangeKind.trashed : ChangeKind.added,
      newName: inc.trimmedName,
    );
  }
  final moved = local.parentId != inc.parentId || local.inDrawer != inc.inDrawer;
  final renamed = local.trimmedName != inc.trimmedName;
  final contentChanged = renamed ||
      local.icon != inc.icon ||
      local.quantity != inc.quantity ||
      local.unit != inc.unit ||
      !listEquals(local.lots, inc.lots) ||
      local.minQuantity != inc.minQuantity ||
      local.wantedAt != inc.wantedAt ||
      local.buyingBy != inc.buyingBy ||
      local.boughtAt != inc.boughtAt ||
      local.autoShop != inc.autoShop ||
      local.isFull != inc.isFull ||
      !sameDates(local, inc) ||
      !listEquals(local.managers, inc.managers) ||
      !listEquals(local.attachments, inc.attachments) ||
      local.barcode != inc.barcode ||
      local.borrowedTo != inc.borrowedTo ||
      local.returnDueAt != inc.returnDueAt ||
      local.price != inc.price ||
      local.serial != inc.serial ||
      !sameService(local, inc) ||
      local.imagePath != inc.imagePath ||
      local.color != inc.color ||
      (local.note ?? '') != (inc.note ?? '') ||
      local.kind != inc.kind ||
      local.lat != inc.lat ||
      local.lng != inc.lng ||
      (local.locationLabel ?? '') != (inc.locationLabel ?? '');
  final kind = !local.isLost && inc.isLost
      ? ChangeKind.lost
      : local.isLost && !inc.isLost
      ? ChangeKind.found
      : !local.isDeleted && inc.isDeleted
      ? ChangeKind.trashed
      : local.isDeleted && !inc.isDeleted
          ? ChangeKind.restored
          : moved
              ? ChangeKind.moved
              : !contentChanged && local.sortIndex != inc.sortIndex
                  ? ChangeKind.reordered
                  : ChangeKind.edited;
  return ChangeSummary(
    kind: kind,
    oldName: local.trimmedName,
    newName: inc.trimmedName,
    renamed: renamed,
    moved: moved,
    imageChanged: local.imagePath != inc.imagePath,
    colorChanged: local.color != inc.color,
    noteChanged: (local.note ?? '') != (inc.note ?? ''),
    kindChanged: local.kind != inc.kind,
    iconChanged: local.icon != inc.icon,
    managersChanged: !listEquals(local.managers, inc.managers),
    quantityChanged: local.quantity != inc.quantity || local.unit != inc.unit || !listEquals(local.lots, inc.lots),
    minQuantityChanged: local.minQuantity != inc.minQuantity,
    wantedChanged: local.wantedAt != inc.wantedAt ||
        local.autoShop != inc.autoShop ||
        local.buyingBy != inc.buyingBy ||
        local.boughtAt != inc.boughtAt,
    fullChanged: local.isFull != inc.isFull,
    datesChanged: !sameDates(local, inc),
    attachmentsChanged: !listEquals(local.attachments, inc.attachments),
    barcodeChanged: local.barcode != inc.barcode,
    borrowChanged: local.borrowedTo != inc.borrowedTo || local.returnDueAt != inc.returnDueAt,
    priceChanged: local.price != inc.price,
    serialChanged: local.serial != inc.serial,
    serviceChanged: !sameService(local, inc),
    locationChanged: local.lat != inc.lat ||
        local.lng != inc.lng ||
        (local.locationLabel ?? '') != (inc.locationLabel ?? ''),
  );
}

/// Kabul edilecek kayıtların, bizde olmayan (ama beklemede olan) üst
/// klasörleri. Onlar kabul edilmeden alt kayıt yersiz kalırdı.
Set<String> pendingAncestors({
  required Set<String> accepting,
  required Map<String, Node> local,
  required Map<String, PendingChange> pending,
}) {
  final extra = <String>{};
  final queue = [...accepting];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    final change = pending[id];
    final parentId = change == null ? null : candidateOf(change, local[id])?.parentId;
    if (parentId == null || local.containsKey(parentId)) continue;
    if (!pending.containsKey(parentId)) continue;
    if (accepting.contains(parentId) || !extra.add(parentId)) continue;
    queue.add(parentId);
  }
  return extra;
}

/// Reddedilen bir kaydın, beklemedeki alt kayıtları (reddedilen yeni bir
/// klasörün içine eklenmiş eşyalar gibi). Onlar da reddedilir.
Set<String> pendingDescendants({
  required Set<String> rejecting,
  required Map<String, PendingChange> pending,
}) {
  final extra = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in pending.values) {
      final parentId = p.incoming?.parentId;
      if (parentId == null || rejecting.contains(p.nodeId) || extra.contains(p.nodeId)) continue;
      if (rejecting.contains(parentId) || extra.contains(parentId)) {
        extra.add(p.nodeId);
        changed = true;
      }
    }
  }
  return extra;
}

/// Listede tek satır olarak gösterilen değişiklikler. Birlikte eklenen ya da
/// silinen bir klasör ve içindekiler, ve aynı yerdeki sıralama
/// değişiklikleri tek grupta toplanır; kabul ve ret grubun hepsine uygulanır.
class ChangeGroup {
  ChangeGroup(this.lead, this.changes, this.summary);

  /// Gruba adını veren değişiklik (en üstteki klasör ya da en yenisi).
  final PendingChange lead;
  final List<PendingChange> changes;
  final ChangeSummary summary;

  String get id => lead.nodeId;
  int get extra => changes.length - 1;
  Iterable<String> get nodeIds => changes.map((c) => c.nodeId);

  DateTime get changedAt =>
      changes.map((c) => c.changedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

List<ChangeGroup> groupChanges(Map<String, PendingChange> pending, Map<String, Node> local) {
  final summaries = {
    for (final c in pending.values) c.nodeId: describeChange(c, local[c.nodeId]),
  };
  String? parentOf(PendingChange c) =>
      candidateOf(c, local[c.nodeId])?.parentId ?? local[c.nodeId]?.parentId;

  String keyOf(String id) {
    final kind = summaries[id]!.kind;
    if (kind == ChangeKind.reordered) {
      final c = pending[id]!;
      final n = candidateOf(c, local[id]) ?? local[id];
      return 'order:${n?.parentId ?? (n?.inDrawer == true ? '~drawer' : '~home')}';
    }
    if (kind != ChangeKind.added && kind != ChangeKind.deleted) return id;
    var cur = id;
    final seen = {id};
    while (true) {
      final parent = parentOf(pending[cur]!);
      if (parent == null || !seen.add(parent)) return cur;
      if (summaries[parent]?.kind != kind) return cur;
      cur = parent;
    }
  }

  final buckets = <String, List<PendingChange>>{};
  for (final c in pending.values) {
    (buckets[keyOf(c.nodeId)] ??= []).add(c);
  }
  final groups = [
    for (final e in buckets.entries)
      () {
        final lead = pending[e.key] ??
            e.value.reduce((a, b) => a.changedAt.isAfter(b.changedAt) ? a : b);
        final ordered = [lead, ...e.value.where((c) => c.nodeId != lead.nodeId)];
        return ChangeGroup(lead, ordered, summaries[lead.nodeId]!);
      }(),
  ]..sort((a, b) => b.changedAt.compareTo(a.changedAt));
  return groups;
}
