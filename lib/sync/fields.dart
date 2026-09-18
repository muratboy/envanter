import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/node.dart';

/// Eşitlemede ayrı ayrı birleşen alan grupları. Aynı kayıtta iki kişi farklı
/// gruplarda değişiklik yaparsa ikisi de kalır (Ayşe adedi, Ali son kullanma
/// tarihini değiştirdi); aynı grupta ise son yazan kazanır. Eskiden kaydın
/// tamamı karşılaştırılıyordu ve değişikliklerden biri kayboluyordu.
///
/// Birlikte anlam taşıyan alanlar tek gruptadır: kaydın yeri (üst klasör,
/// çekmece, sıra, kayıp, "Ayşe'de") yarım birleşirse eşya iki yerde birden
/// olurdu. `Node`'a eşitlenen bir alan eklenince buraya da girmeli.
enum NodeField {
  placement,
  kind,
  name,
  note,
  look,
  image,
  geo,
  quantity,
  minQuantity,
  wanted,
  autoShop,
  full,
  managers,
  trash,
  purchase,
  expiry,
  warranty,
  attachments,
  barcode,
  borrow,
  price,
  serial,
  // Bakımın planı (aralık, ne yapılacağı) ve kaydı (son bakım, geçmiş) ayrı: biri döngüyü
  // değiştirirken öteki "bakım yapıldı" derse ikisi de kalsın.
  service,
  serviced,
}

extension NodeFieldTimes on Node {
  /// Grubun son değişme anı (ms). Grup zamanı olmayan (eski) kayıtta kaydın
  /// kendi zamanı.
  int timeOf(NodeField f) => fieldTimes[f.name] ?? updatedAt.millisecondsSinceEpoch;

  /// Bütün grupların zamanları, eksikleri kaydın zamanıyla doldurulmuş.
  Map<String, int> get allFieldTimes => {for (final f in NodeField.values) f.name: timeOf(f)};
}

/// Grubun değerleri; karşılaştırma ve eşitlikte karar için.
List<Object?> fieldValues(Node n, NodeField f) => switch (f) {
      NodeField.placement => [n.parentId, n.inDrawer, n.sortIndex, n.lostAt, n.lostFrom, n.heldBy],
      NodeField.kind => [n.kind.name],
      NodeField.name => [n.name],
      NodeField.note => [n.note ?? ''],
      NodeField.look => [n.color, n.icon],
      NodeField.image => [n.imagePath],
      NodeField.geo => [n.lat, n.lng, n.locationLabel ?? ''],
      // Adet, birim ve paketler birlikte: yarım birleşse toplam paketlerle tutmazdı.
      NodeField.quantity => [n.quantity, n.unit, Lot.encode(n.lots)],
      NodeField.minQuantity => [n.minQuantity],
      // Alışveriş durumu tek grup: listede mi, kim alıyor, alındı mı.
      NodeField.wanted => [n.wantedAt, n.buyingBy, n.buyingAt, n.boughtAt],
      NodeField.autoShop => [n.autoShop],
      NodeField.full => [n.isFull],
      NodeField.managers => [n.managers.join(',')],
      NodeField.trash => [n.deletedAt],
      NodeField.purchase => [n.purchasedAt],
      NodeField.expiry => [n.expiresAt, n.shelfLife, n.expiryWarn],
      NodeField.warranty => [n.warrantyEndsAt, n.warranty],
      // Ekler tek tek birleşir ([mergeAttachments]); grubun "değeri" eklerin ve
      // çıkarılanların izlerinin tamamı (zamanlarıyla).
      NodeField.attachments => [Attachment.encode(n.attachments, n.attachmentTombs)],
      NodeField.barcode => [n.barcode],
      NodeField.borrow => [n.borrowedTo, n.borrowedAt?.millisecondsSinceEpoch, n.returnDueAt?.millisecondsSinceEpoch],
      NodeField.price => [n.price],
      NodeField.serial => [n.serial],
      NodeField.service => [n.serviceEvery, n.serviceTask],
      NodeField.serviced => [n.servicedAt?.millisecondsSinceEpoch, ServiceEntry.encode(n.serviceLog)],
    };

bool sameField(Node a, Node b, NodeField f) => listEquals(fieldValues(a, f), fieldValues(b, f));

/// [into] kaydına [from]'un grup değerlerini koyar (zamanı çağıran ayarlar).
Node takeField(Node into, Node from, NodeField f) => switch (f) {
      // Önce temizlenir, sonra konur: gruptaki alanlar ayrı ayrı boş olabilir
      // (kayıp anı var, son yeri yok gibi); tek adımda eskisi kalırdı.
      NodeField.placement => into
          .copyWith(clearParent: true, clearLost: true, clearHeld: true, updatedAt: into.updatedAt)
          .copyWith(
            parentId: from.parentId,
            inDrawer: from.inDrawer,
            sortIndex: from.sortIndex,
            lostAt: from.lostAt,
            lostFrom: from.lostFrom,
            heldBy: from.heldBy,
            updatedAt: into.updatedAt,
          ),
      NodeField.kind => into.copyWith(kind: from.kind, updatedAt: into.updatedAt),
      NodeField.name => into.copyWith(name: from.name, updatedAt: into.updatedAt),
      NodeField.note => into.copyWith(note: from.note ?? '', updatedAt: into.updatedAt),
      NodeField.look => into.copyWith(
          color: from.color,
          icon: from.icon,
          clearIcon: from.icon == null,
          updatedAt: into.updatedAt,
        ),
      // Parmak izi resimden türer: resimle birlikte gider.
      NodeField.image => into.copyWith(
          imagePath: from.imagePath,
          clearImage: from.imagePath == null,
          imageSig: from.imageSig,
          clearSignature: from.imageSig == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.geo => into.copyWith(clearGeo: true, updatedAt: into.updatedAt).copyWith(
            lat: from.lat,
            lng: from.lng,
            locationLabel: from.locationLabel,
            updatedAt: into.updatedAt,
          ),
      NodeField.quantity => into.copyWith(
          quantity: from.quantity,
          clearQuantity: from.quantity == null,
          unit: from.unit,
          clearUnit: from.unit == null,
          lots: from.lots,
          updatedAt: into.updatedAt,
        ),
      NodeField.minQuantity => into.copyWith(
          minQuantity: from.minQuantity,
          clearMinQuantity: from.minQuantity == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.wanted => into.copyWith(
          wantedAt: from.wantedAt,
          clearWanted: from.wantedAt == null,
          buyingBy: from.buyingBy,
          buyingAt: from.buyingAt,
          clearBuying: from.buyingBy == null || from.buyingAt == null,
          boughtAt: from.boughtAt,
          clearBought: from.boughtAt == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.autoShop => into.copyWith(autoShop: from.autoShop, updatedAt: into.updatedAt),
      NodeField.full => into.copyWith(isFull: from.isFull, updatedAt: into.updatedAt),
      NodeField.managers => into.copyWith(managers: from.managers, updatedAt: into.updatedAt),
      NodeField.trash => into.copyWith(
          deletedAt: from.deletedAt,
          clearDeletedAt: from.deletedAt == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.purchase => into.copyWith(
          purchasedAt: from.purchasedAt,
          clearPurchased: from.purchasedAt == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.expiry => into.copyWith(
          expiresAt: from.expiresAt,
          clearExpires: from.expiresAt == null,
          shelfLife: from.shelfLife,
          clearShelfLife: from.shelfLife == null,
          expiryWarn: from.expiryWarn,
          clearExpiryWarn: from.expiryWarn == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.warranty => into.copyWith(
          warrantyEndsAt: from.warrantyEndsAt,
          clearWarrantyEnd: from.warrantyEndsAt == null,
          warranty: from.warranty,
          clearWarranty: from.warranty == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.attachments => into.copyWith(
          attachments: from.attachments,
          attachmentTombs: from.attachmentTombs,
          updatedAt: into.updatedAt,
        ),
      NodeField.barcode => into.copyWith(
          barcode: from.barcode,
          clearBarcode: from.barcode == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.borrow => into.copyWith(
          clearBorrow: from.borrowedTo == null,
          borrowedTo: from.borrowedTo,
          borrowedAt: from.borrowedAt,
          returnDueAt: from.returnDueAt,
          clearReturnDue: from.returnDueAt == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.price => into.copyWith(price: from.price, clearPrice: from.price == null, updatedAt: into.updatedAt),
      NodeField.serial => into.copyWith(serial: from.serial, clearSerial: from.serial == null, updatedAt: into.updatedAt),
      NodeField.service => into.copyWith(
          serviceEvery: from.serviceEvery,
          clearServiceEvery: from.serviceEvery == null,
          serviceTask: from.serviceTask,
          clearServiceTask: from.serviceTask == null,
          updatedAt: into.updatedAt,
        ),
      NodeField.serviced => into.copyWith(
          servicedAt: from.servicedAt,
          clearServiced: from.servicedAt == null,
          serviceLog: from.serviceLog,
          updatedAt: into.updatedAt,
        ),
    };

/// İki sürümün eklerini **tek tek** birleştirir: her ek (kimliğiyle) için en
/// yeni karar geçerli. İki cihazda ayrı ayrı eklenenler birlikte kalır; adı
/// değişen ekte son ad; çıkarılan ek, çıkarıldıktan sonra değişmediyse çıkmış
/// kalır (iz), sonra değiştiyse geri gelir. Eşit anda iz kazanır, iki canlı
/// sürümde metni büyük olan: keyfi ama her yerde aynı. Saf, değişmeli ve
/// tekrarlanabilir: sıra ne olursa olsun iki cihaz aynı listeye varır.
(List<Attachment>, Map<String, int>) mergeAttachments(Node a, Node b) {
  final live = <String, Attachment>{for (final x in a.attachments) x.id: x};
  for (final x in b.attachments) {
    final mine = live[x.id];
    if (mine == null ||
        x.stamp > mine.stamp ||
        (x.stamp == mine.stamp && jsonEncode(x.toJson()).compareTo(jsonEncode(mine.toJson())) > 0)) {
      live[x.id] = x;
    }
  }
  final tombs = Map<String, int>.of(a.attachmentTombs);
  b.attachmentTombs.forEach((id, at) {
    if (at > (tombs[id] ?? -1)) tombs[id] = at;
  });
  // Her kimlikte ya ek ya iz kalır.
  for (final id in tombs.keys.toList()) {
    final x = live[id];
    if (x == null) continue;
    if (tombs[id]! >= x.stamp) {
      live.remove(id);
    } else {
      tombs.remove(id);
    }
  }
  return (Attachment.sorted(live.values), Attachment.trimTombs(tombs));
}

/// Yerel bir yazımda eklerin damgası: yeni eklenen ve adı değişen ek [at]
/// anına geçer, çıkarılan ek için iz kalır, liste değişmez sırasına girer.
/// Arayüz yalnızca listeyi değiştirir; zamanlar ve izler burada konur.
Node _stampAttachments(Node? before, Node after, DateTime at) {
  if (after.attachments.isEmpty && after.attachmentTombs.isEmpty && (before == null || before.attachments.isEmpty)) {
    return after;
  }
  final old = <String, Attachment>{for (final x in before?.attachments ?? const <Attachment>[]) x.id: x};
  final live = <Attachment>[
    for (final x in after.attachments)
      switch (old[x.id]) {
        // Görünen hali aynıysa eski zamanıyla kalır (== zamana bakmaz).
        final was? when was == x => was,
        _ => before == null && x.changedAt != null ? x : x.touched(at),
      },
  ];
  final ids = {for (final x in live) x.id};
  final tombs = {...?before?.attachmentTombs, ...after.attachmentTombs}..removeWhere((id, _) => ids.contains(id));
  for (final id in old.keys) {
    if (!ids.contains(id)) tombs[id] = at.millisecondsSinceEpoch;
  }
  return after.copyWith(
    attachments: Attachment.sorted(live),
    attachmentTombs: Attachment.trimTombs(tombs),
    updatedAt: after.updatedAt,
  );
}

/// Karşıdan gelen ek değişikliği reddedildi: bizdeki ekler geçerli kalsın.
/// Grup zamanını ilerletmek yetmez (ekler zamana göre değil tek tek birleşir):
/// bizdeki her ek [at] anına geçer (karşıdaki çıkarma ve ad değişimi yenilir),
/// karşıda olup bizde olmayan her ek için iz konur (ekleme yenilir).
Node rejectAttachments(Node local, Node incoming, DateTime at) {
  final ids = {for (final x in local.attachments) x.id};
  final tombs = Map<String, int>.of(local.attachmentTombs);
  for (final x in incoming.attachments) {
    if (!ids.contains(x.id)) tombs[x.id] = at.millisecondsSinceEpoch;
  }
  return local.copyWith(
    attachments: [for (final x in local.attachments) x.touched(at)],
    attachmentTombs: Attachment.trimTombs(tombs),
    updatedAt: local.updatedAt,
  );
}

/// Bu cihazdaki bir değişikliğin damgası: [before]'dan farklı gruplar [at]
/// anına geçer, ötekiler eski zamanlarında kalır. Zamanlar her zaman tam
/// yazılır: eksik grup kaydın zamanına düşeceği için, bir alan değişince
/// öteki grupların da "şimdi değişti" sayılmasını önler.
Node stampChanges(Node? before, Node after, DateTime at) {
  after = _stampAttachments(before, after, at);
  final ms = at.millisecondsSinceEpoch;
  final times = before?.allFieldTimes ?? {for (final f in NodeField.values) f.name: ms};
  if (before != null) {
    for (final f in NodeField.values) {
      if (!sameField(before, after, f)) times[f.name] = ms;
    }
  }
  return after.copyWith(fieldTimes: times, updatedAt: at);
}

/// Verilen grupları [at] anına taşır; değerler aynı kalır (ör. reddedilen
/// değişiklikte bizim sürümümüz kazansın diye).
Node bumpFields(Node node, Iterable<NodeField> fields, DateTime at, {String? by}) {
  final times = node.allFieldTimes;
  for (final f in fields) {
    times[f.name] = at.millisecondsSinceEpoch;
  }
  return node.copyWith(fieldTimes: times, updatedAt: at, updatedBy: by);
}

/// İki sürümde farklı olan gruplar.
Iterable<NodeField> differingFields(Node a, Node b) => NodeField.values.where((f) => !sameField(a, b, f));

/// Düzenleyiciden gelen kayıt: [opened] düzenleyicinin açıldığı andaki hali, [draft]
/// kullanıcının bıraktığı taslak, [current] kaydın şimdiki hali. Yalnızca bu oturumda
/// değişen gruplar [current]'a uygulanır. Taslağın tamamını yazmak, düzenleyici açıkken
/// gelen değişikliği (karşıda adet 3'ten 2'ye indi, eşya taşındı, çöpe atıldı) geri alıyor,
/// üstelik "şimdi değişti" diye damgalandığı için eski değer her cihazda kazanıyordu.
///
/// Ekler tek tek birleştiği için ayrıca ele alınır: taslakta olmayan yeni ek "çıkarıldı"
/// diye iz bırakmasın (herkeste silinirdi), karşıda çıkarılmış ek geri gelmesin. Bu oturumda
/// eklenen eklenir, çıkarılan çıkar, dokunulmayan şimdiki haliyle kalır (karşıda adı
/// değişmiş olabilir); izler [current]'tan gelir.
Node applyEdits({required Node opened, required Node draft, required Node current}) {
  var out = current;
  for (final f in differingFields(opened, draft)) {
    if (f != NodeField.attachments) out = takeField(out, draft, f);
  }
  final was = {for (final a in opened.attachments) a.id: a};
  final now = {for (final a in current.attachments) a.id: a};
  final mine = {for (final a in draft.attachments) a.id};
  return out.copyWith(
    attachments: [
      for (final a in draft.attachments)
        if (!was.containsKey(a.id))
          a
        else if (!current.attachmentTombs.containsKey(a.id))
          a == was[a.id] ? (now[a.id] ?? a) : a,
      for (final a in current.attachments)
        if (!was.containsKey(a.id) && !mine.contains(a.id)) a,
    ],
    updatedAt: current.updatedAt,
  );
}

/// Aynı kaydın iki sürümünü grup grup birleştirir: her grupta zamanı yeni
/// olan kazanır. Değişmeli ve tekrarlanabilir: sıra ne olursa olsun iki cihaz
/// aynı sonuca varır (yoksa eşitleme durulmaz). Aynı anda değişmiş iki farklı
/// değerde karar, değerlerin metnine göre verilir: keyfi ama her yerde aynı.
Node mergeNode(Node local, Node incoming) {
  // Çoğu eşitlemede kayıtların neredeyse hepsi iki tarafta aynı sürüm; grup
  // grup bakmak binlerce kayıtta telefonu gözle görülür bekletiyordu.
  if (_sameStamps(local, incoming)) return local;
  var result = local;
  final times = <String, int>{};
  for (final f in NodeField.values) {
    final mine = local.timeOf(f);
    final theirs = incoming.timeOf(f);
    if (f == NodeField.attachments) {
      // Ekler "son yazan kazanır" değil: tek tek birleşir, grubun zamanına bakılmaz.
      if (!sameField(local, incoming, f)) {
        final (live, tombs) = mergeAttachments(local, incoming);
        result = result.copyWith(attachments: live, attachmentTombs: tombs, updatedAt: result.updatedAt);
      }
      times[f.name] = theirs > mine ? theirs : mine;
      continue;
    }
    final takeTheirs = theirs > mine ||
        (theirs == mine &&
            !sameField(local, incoming, f) &&
            fieldValues(incoming, f).toString().compareTo(fieldValues(local, f).toString()) > 0);
    if (takeTheirs) result = takeField(result, incoming, f);
    times[f.name] = theirs > mine ? theirs : mine;
  }
  // Kaydın zamanı ve yazarı: en son değişen tarafınki (eşitlikte yine sabit bir
  // kural). Milisaniyeyle: ağdan ve diskten gelen zaman mikrosaniyesiz, bellekteki
  // değil; yoksa aynı milisaniyede yazan iki cihaz da kendini yeni sanırdı.
  final mine = local.updatedAt.millisecondsSinceEpoch;
  final theirs = incoming.updatedAt.millisecondsSinceEpoch;
  final newer = theirs > mine || (theirs == mine && (incoming.updatedBy ?? '').compareTo(local.updatedBy ?? '') > 0);
  final at = newer ? incoming.updatedAt : local.updatedAt;
  return result.copyWith(
    fieldTimes: times,
    updatedAt: at,
    updatedBy: newer ? incoming.updatedBy : local.updatedBy,
  );
}

/// Aynı yazarın aynı andaki sürümü: değerleri de aynıdır (bir cihaz aynı
/// milisaniyede aynı kaydı iki farklı biçimde yazamaz).
///
/// Ekler bunun istisnası: tek tek birleştikleri için zamanları aynı kalıp
/// içerikleri değişebilir (iki tarafın eklediği birleşince); onlara ayrıca bakılır.
bool _sameStamps(Node a, Node b) =>
    a.updatedAt.millisecondsSinceEpoch == b.updatedAt.millisecondsSinceEpoch &&
    a.updatedBy == b.updatedBy &&
    mapEquals(a.fieldTimes, b.fieldTimes) &&
    ((a.attachments.isEmpty && b.attachments.isEmpty && a.attachmentTombs.isEmpty && b.attachmentTombs.isEmpty) ||
        sameField(a, b, NodeField.attachments));

/// Değerler ve zamanlar birebir aynı mı (Node'un == işleci yalnızca kimlik
/// ve kayıt zamanına bakar).
bool sameVersion(Node a, Node b) =>
    identical(a, b) ||
    a.updatedAt.millisecondsSinceEpoch == b.updatedAt.millisecondsSinceEpoch &&
    a.updatedBy == b.updatedBy &&
    mapEquals(a.allFieldTimes, b.allFieldTimes) &&
    differingFields(a, b).isEmpty &&
    a.imageSig == b.imageSig;
