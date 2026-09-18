import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/money.dart';
import '../core/time_span.dart';
import '../data/node.dart';
import 'fields.dart';

/// Ortak kullanımda cihazlar arasında gidip gelen veri ve imzası.
///
/// Karşıdan gelen her şey doğrulanır: ağdaki bir cihaz bozuk ya da kötü
/// niyetli veri gönderebilir. Özellikle resim yolları: "../databases/…"
/// gibi bir yol kabul edilseydi, kayıt silinince uygulamanın başka
/// dosyaları silinebilirdi.

/// Uygulamanın resim yolları hep bu biçimde.
final _safeImagePath = RegExp(r'^images/[A-Za-z0-9._-]+$');

bool isSafeImagePath(String? path) =>
    path != null && _safeImagePath.hasMatch(path) && !path.contains('..');

/// Ek dosyalarının yolu (`files/…`); resim yoluyla aynı kural.
bool isSafeFilePath(String? path) => Attachment.isSafeFile(path);

/// Eşitlenecek durumun küçük özeti: kayıt sayısı, kayıtların
/// kimlik+düzenleme zamanı+grup zamanları karmalarının XOR'u ve silme izleri.
/// Herhangi biri değişince damga değişir; sıradan bağımsız olduğu için aynı
/// içeriğe sahip iki cihaz aynı damgayı üretir. Grup zamanları şart: iki
/// değişikliği birleştiren cihazın kaydı, karşıdakiyle aynı düzenleme
/// zamanını taşır ama içeriği farklıdır (onun bilmediği bir alanı da içerir).
///
/// Cihazlar bunu duyurularında taşır: damga son eşitlemedekiyle aynıysa
/// konuşacak bir şey yoktur, envanter boşuna gidip gelmez.
/// Kaydın damgadaki payı, kaydın o haline bağlı ([Node] değişmez; değişen
/// kayıt yeni bir nesnedir). Tek kayıt değişince bütün envanterin metni yeniden
/// kurulup karılıyordu: binlerce kayıtta her değişiklikte hissediliyordu.
final Expando<int> _nodeStamp = Expando();

String stateStampOf(Iterable<Node> nodes, Map<String, int> tombstones) {
  var count = 0;
  var acc = 0;
  for (final n in nodes) {
    count++;
    // Ekler tek tek birleştiği için kaydın zamanları eklerini tanımlamaz (iki
    // tarafın eklediği birleşince zaman ilerlemez, içerik değişir): damgaya
    // eklerin kendisi de girer.
    acc ^= _nodeStamp[n] ??= _fnv1a(
      '${n.id}:${n.updatedAt.millisecondsSinceEpoch}:${n.updatedBy ?? ''}:${NodeField.values.map(n.timeOf).join(',')}'
      '${n.attachments.isEmpty && n.attachmentTombs.isEmpty ? '' : ':${Attachment.encode(n.attachments, n.attachmentTombs)}'}',
    );
  }
  var tombAcc = 0;
  tombstones.forEach((id, at) => tombAcc ^= _fnv1a('$id:$at'));
  return '$count.${acc.toRadixString(16)}.${tombstones.length}.${tombAcc.toRadixString(16)}';
}

/// Envanterin yönetimi: yönetici (kuran ya da devralan) ve yönetici ayrılırsa
/// yerine geçecek varis. Her ikisi zamanıyla taşınır, cihazlar arasında en yeni
/// karar geçerli (devir, varis seçme ya da kaldırma).
class Governance {
  const Governance({required this.owner, this.ownerAt = 0, this.heir, this.heirAt = 0});

  final String owner;
  final int ownerAt;

  /// Varis: ana kullanıcı yetkileri var, yönetici ayrılınca (ya da envanteri
  /// silince) yönetici olur. Varis seçmeyi yalnızca yönetici yapabilir.
  final String? heir;
  final int heirAt;

  Map<String, Object?> toJson() => {
        'owner': owner,
        'ownerAt': ownerAt,
        if (heir != null) 'heir': heir,
        'heirAt': heirAt,
      };

  static Governance? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final owner = raw['owner'];
    if (owner is! String || owner.isEmpty) return null;
    final ownerAt = raw['ownerAt'];
    final heir = raw['heir'];
    final heirAt = raw['heirAt'];
    return Governance(
      owner: owner,
      ownerAt: ownerAt is int ? ownerAt : 0,
      heir: heir is String && heir.isNotEmpty ? heir : null,
      heirAt: heirAt is int ? heirAt : 0,
    );
  }

  /// Her kararda zamanı yeni olan; aynı anda iki farklı karar (neredeyse
  /// imkânsız) kimliğe göre sabit bir kuralla: iki cihaz aynı sonuca varsın.
  Governance merge(Governance other) {
    final takeOwner = other.ownerAt > ownerAt || (other.ownerAt == ownerAt && other.owner.compareTo(owner) > 0);
    final takeHeir = other.heirAt > heirAt ||
        (other.heirAt == heirAt && (other.heir ?? '').compareTo(heir ?? '') > 0);
    return Governance(
      owner: takeOwner ? other.owner : owner,
      ownerAt: takeOwner ? other.ownerAt : ownerAt,
      heir: takeHeir ? other.heir : heir,
      heirAt: takeHeir ? other.heirAt : heirAt,
    );
  }

  String get stamp => '$owner:$ownerAt:${heir ?? ''}:$heirAt';

  @override
  bool operator ==(Object other) => other is Governance && other.stamp == stamp;

  @override
  int get hashCode => stamp.hashCode;
}

/// Üye listesinin özeti: adlar, roller, çıkarılan/ayrılan üyelerin izleri ve
/// yönetim (yönetici, varis) de eşitlenen bilgi, onlar değişince de konuşulmalı.
String memberStampOf(Iterable<Member> members, [Map<String, int> removed = const {}, Governance? governance]) {
  var count = 0;
  var acc = 0;
  for (final m in members) {
    count++;
    acc ^= _fnv1a('${m.deviceId}:${m.name}:${m.admin}:${m.roleAt}:${m.joinedAt}');
  }
  var gone = 0;
  removed.forEach((id, at) => gone ^= _fnv1a('-$id:$at'));
  final g = governance == null ? '' : _fnv1a(governance.stamp).toRadixString(16);
  return '$count.${acc.toRadixString(16)}.${removed.length}.${gone.toRadixString(16)}.$g';
}

/// Geri çevrilen bir değişikliğin, onu yapana haberi ("Ali, “Kalem” kaydındaki
/// değişikliğini geri çevirdi"); yoksa ret sessizce geri döner, kişi aynı
/// değişikliği yeniden yapardı. Üye listesi gibi herkese yayılır (yapan o an
/// ağda olmayabilir), yalnızca [to] cihazında gösterilir; [keep] sonra düşer.
class Notice {
  const Notice({
    required this.id,
    required this.to,
    required this.by,
    required this.name,
    required this.kind,
    required this.at,
  });

  final String id;

  /// Değişikliği yapan, haberi görecek cihaz.
  final String to;

  /// Geri çeviren cihaz.
  final String by;

  /// Kaydın geri çevrildiği andaki adı.
  final String name;

  /// Değişikliğin türü (`ChangeKind` adı: added, edited, moved, trashed...).
  final String kind;
  final int at;

  static const keep = Duration(days: 14);

  /// Bir cihazın taşıdığı en çok haber (en yeniler).
  static const limit = 200;

  Map<String, Object?> toJson() => {'id': id, 'to': to, 'by': by, 'name': name, 'kind': kind, 'at': at};

  static final _kind = RegExp(r'^[a-z]{1,16}$');

  static Notice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final to = raw['to'];
    final by = raw['by'];
    final name = raw['name'];
    final kind = raw['kind'];
    final at = raw['at'];
    if (id is! String || to is! String || by is! String || name is! String || kind is! String || at is! int) {
      return null;
    }
    if (id.isEmpty || id.length > 64 || to.isEmpty || to.length > 64 || by.length > 64) return null;
    if (name.length > 200 || !_kind.hasMatch(kind) || at <= 0) return null;
    return Notice(id: id, to: to, by: by, name: name, kind: kind, at: at);
  }
}

List<Notice> noticesFromJson(Object? raw) => [
      if (raw is List)
        for (final n in raw) ?Notice.fromJson(n),
    ];

/// Haberlerin birleşimi: kimliğe göre tek, süresi dolan düşer, en yeni [Notice.limit].
List<Notice> mergeNotices(Iterable<Notice> a, Iterable<Notice> b, DateTime now) {
  final limit = now.millisecondsSinceEpoch - Notice.keep.inMilliseconds;
  final byId = <String, Notice>{
    for (final n in [...a, ...b])
      if (n.at >= limit) n.id: n,
  };
  final list = byId.values.toList()..sort((x, y) => y.at != x.at ? y.at.compareTo(x.at) : x.id.compareTo(y.id));
  return list.take(Notice.limit).toList();
}

String noticeStampOf(Iterable<Notice> notices) {
  var count = 0;
  var acc = 0;
  for (final n in notices) {
    count++;
    acc ^= _fnv1a(n.id);
  }
  return '$count.${acc.toRadixString(16)}';
}

/// FNV-1a: küçük, hızlı ve çalıştırmalar arasında aynı sonucu veren karma
/// (Dart'ın kendi hashCode'u her açılışta değişebiliyor).
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h = ((h ^ s.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Ortak envanterin bir üyesi (cihaz).
class Member {
  const Member({
    required this.deviceId,
    required this.name,
    this.admin = false,
    this.roleAt = 0,
    this.joinedAt = 0,
  });

  final String deviceId;
  final String name;

  /// Genel ana kullanıcı: değişiklikleri herkese onaysız uygulanır, katılma
  /// isteklerini onaylar, rol ve sorumlu atar. Sahip her zaman öyledir.
  final bool admin;

  /// Rolün son değiştiği an (ms); cihazlar arasında en yenisi geçerli.
  final int roleAt;

  /// Katılmanın onaylandığı an (ms; kurucu ve eski üyelerde 0). Çıkarılan ya
  /// da ayrılan bir cihaz yeniden kabul edilirse bu, çıkarılma izinden yeni
  /// olur; yoksa diğer cihazlar eski izi görüp onu yine listeden atardı.
  final int joinedAt;

  Member copyWith({String? name, bool? admin, int? roleAt, int? joinedAt}) => Member(
        deviceId: deviceId,
        name: name ?? this.name,
        admin: admin ?? this.admin,
        roleAt: roleAt ?? this.roleAt,
        joinedAt: joinedAt ?? this.joinedAt,
      );

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'admin': admin,
        'roleAt': roleAt,
        if (joinedAt > 0) 'joinedAt': joinedAt,
      };

  static Member? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['deviceId'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    final roleAt = raw['roleAt'];
    final joinedAt = raw['joinedAt'];
    return Member(
      deviceId: id,
      name: name is String ? name : '',
      admin: raw['admin'] == true,
      roleAt: roleAt is int ? roleAt : 0,
      joinedAt: joinedAt is int && joinedAt > 0 ? joinedAt : 0,
    );
  }
}

/// Bir cihazın envanter durumu: kayıtlar (çöptekiler dahil), kalıcı silme
/// izleri ve bildiği üyeler. Resimler ayrıca, gerekirse tek tek istenir.
/// Eşitlenen verinin biçimi. `Node`'a eşitlenen bir alan eklenince (veritabanı
/// sürümüyle birlikte) artar. Farklı sürümdeki iki cihaz durum alışverişi
/// yapmaz: eski olan tanımadığı alanları sessizce atar, o kaydı sonra
/// değiştirirse kaydın bütünü yeni cihazlara geri gider ve oradaki alanlar
/// (tarihler, "Ayşe'de") silinirdi. Bu sürümü göndermeyen eski uygulama 0 sayılır.
/// 13: "en az adet" ve alan bazında birleştirme (kayıtlar grup zamanlarını taşır).
/// 14: ortak alışveriş listesi (`wanted_at`).
/// 15: eşyanın "listeye kendiliğinden ekle" ayarı (`auto_shop`).
/// 16: farklı son kullanma tarihli paketler (`lots`).
/// 17: yönetim (yönetici devri, varis) ve ayrılırken veda (`governance`, `farewell`).
/// 18: geri çevrilen değişikliklerin haberi (`notices`, damgada da) ve gönderenin
///     saati (`clock`, `auto`): yanlış saatli telefon fark edilsin, düzeltilsin;
///     alışverişte "alıyorum" ve "alındı, yerleştirilecek" (`buying_by`, `buying_at`, `bought_at`).
/// 19: ekler (`attachments`); dosyaları `/file/…` ile ayrıca çekilir.
/// 20: ekler tek tek birleşir (ekin kendi zamanı `t`, çıkarılanın izi `x`); eski
///     sürüm izleri atıp listeyi bütün olarak ezerdi.
/// 21: ürün barkodu (`barcode`).
/// 22: miktar ölçü birimi (`unit`).
/// 23: emanet & ödünç takibi (`borrowedTo`, `borrowedAt`, `returnDueAt`).
/// 24: değer ve seri numarası (`price`, `serial`).
/// 25: periyodik bakım (`service_every`, `service_task`, `serviced_at`, `service_log`).
const kDataVersion = 25;

/// İsteklerde veri sürümünü ve gönderen cihazı taşıyan başlıklar (imzanın
/// dışında: yalnızca "konuşabilir miyiz" sorusu içindir, imzalı gövdeye girmez).
const kDataHeader = 'x-envanter-data';
const kFromHeader = 'x-envanter-from';

class SyncState {
  const SyncState({
    required this.nodes,
    required this.tombstones,
    required this.members,
    this.removed = const {},
    this.governance,
    this.farewell,
    this.notices = const [],
    this.clock,
    this.clockTrusted = false,
    this.from,
    this.dataVersion = kDataVersion,
  });

  final Map<String, Node> nodes;
  final Map<String, int> tombstones;
  final List<Member> members;

  /// Ortak kullanımdan çıkarılan ya da ayrılan cihazlar (kimlik → an, ms).
  final Map<String, int> removed;

  /// Yönetici ve varis (gönderenin bildiği en yeni hali).
  final Governance? governance;

  /// Gönderen ayrılırken son haberi: 'left' (ayrıldı) ya da 'deleted'
  /// (envanteri kendi cihazından sildi). Öteki durumlarda null.
  final String? farewell;

  /// Geri çevrilen değişikliklerin haberleri ([Notice]).
  final List<Notice> notices;

  /// Gönderenin durumu yazdığı an (düzeltilmiş saatiyle, ms) ve saati
  /// otomatik mi (bkz. `SyncClock`).
  final int? clock;
  final bool clockTrusted;

  /// Durumu gönderen cihaz.
  final String? from;

  /// Gönderenin veri sürümü ([kDataVersion]); eski uygulamada 0.
  final int dataVersion;

  Map<String, Object?> toJson() => {
        'data': dataVersion,
        'nodes': [for (final n in nodes.values) n.toMap()],
        'tombstones': tombstones,
        'members': [for (final m in members) m.toJson()],
        if (removed.isNotEmpty) 'removed': removed,
        if (governance != null) 'governance': governance!.toJson(),
        if (farewell != null) 'farewell': farewell,
        if (notices.isNotEmpty) 'notices': [for (final n in notices) n.toJson()],
        if (clock != null) 'clock': clock,
        if (clockTrusted) 'auto': true,
        'from': from,
      };

  /// Karşıdan gelen durum. Geçersiz kayıtlar atlanır, güvensiz resim
  /// yolları düşürülür; biçim tamamen bozuksa [FormatException].
  static SyncState fromJson(Object? json) {
    if (json is! Map) throw const FormatException('durum bir nesne değil');
    final rawNodes = json['nodes'];
    if (rawNodes is! List) throw const FormatException('kayıt listesi yok');
    final nodes = <String, Node>{};
    for (final raw in rawNodes) {
      final node = sanitizeNode(raw);
      if (node != null) nodes[node.id] = node;
    }
    final rawTomb = json['tombstones'];
    final tombstones = <String, int>{
      if (rawTomb is Map)
        for (final e in rawTomb.entries)
          if (e.key is String && (e.key as String).isNotEmpty && e.value is num)
            e.key as String: (e.value as num).toInt(),
    };
    final rawMembers = json['members'];
    final members = <Member>[
      if (rawMembers is List)
        for (final m in rawMembers) ?Member.fromJson(m),
    ];
    final from = json['from'];
    final data = json['data'];
    return SyncState(
      nodes: nodes,
      tombstones: tombstones,
      members: members,
      removed: removedFromJson(json['removed']),
      governance: Governance.fromJson(json['governance']),
      farewell: switch (json['farewell']) {
        'left' => 'left',
        'deleted' => 'deleted',
        _ => null,
      },
      notices: noticesFromJson(json['notices']),
      clock: switch (json['clock']) {
        final int ms when ms > 0 => ms,
        _ => null,
      },
      clockTrusted: json['auto'] == true,
      from: from is String && from.isNotEmpty ? from : null,
      dataVersion: data is int ? data : 0,
    );
  }
}

/// Çıkarılma izleri; bozuk girdiler atlanır.
Map<String, int> removedFromJson(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && (e.key as String).isNotEmpty && e.value is int && (e.value as int) > 0)
            e.key as String: e.value as int,
    };

bool _validTimes(Object raw) {
  if (raw is! String || raw.length > 1000) return false;
  try {
    final map = jsonDecode(raw);
    if (map is! Map || map.isEmpty) return false;
    final known = {for (final f in NodeField.values) f.name};
    return map.entries.every((e) => known.contains(e.key) && e.value is int && (e.value as int) >= 0);
  } on FormatException {
    return false;
  }
}

/// Dışarıdan gelen bir kaydı doğrular. Kimliği olmayanlar atlanır, güvenli
/// olmayan resim yolları düşürülür, türü bozuk alanlar kaydı geçersiz kılar.
Node? sanitizeNode(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, Object?>.from(raw);
  final id = map['id'];
  if (id is! String || id.isEmpty) return null;
  final parent = map['parent_id'];
  if (parent != null && (parent is! String || parent.isEmpty || parent == id)) {
    map['parent_id'] = null;
  }
  final quantity = map['quantity'];
  if (quantity != null && (quantity is! int || quantity < 0 || quantity > 1000000)) map['quantity'] = null;
  final minQuantity = map['min_quantity'];
  if (minQuantity != null && (minQuantity is! int || minQuantity < 0 || minQuantity > 1000000)) {
    map['min_quantity'] = null;
  }
  // Grup zamanları: bozuksa ya da tanımadığımız grup varsa atılır; eksik
  // gruplar kaydın zamanını alır ([NodeFieldTimes.timeOf]).
  final rawTimes = map['field_times'];
  if (rawTimes != null) map['field_times'] = _validTimes(rawTimes) ? rawTimes : null;
  if (map['auto_shop'] is! int) map['auto_shop'] = 0;
  // Paketler: bozuksa atılır; varsa adet onların toplamıdır.
  final rawLots = map['lots'];
  if (rawLots != null) {
    final lots = rawLots is String && rawLots.length <= 20000 ? Lot.decode(rawLots) : const <Lot>[];
    map['lots'] = Lot.encode(lots);
    if (lots.isNotEmpty) map['quantity'] = lots.fold<int>(0, (a, l) => a + l.count);
  }
  final wanted = map['wanted_at'];
  if (wanted != null && (wanted is! int || wanted <= 0)) map['wanted_at'] = null;
  map['barcode'] = Node.cleanBarcode(map['barcode']);
  map['unit'] = Node.cleanUnit(map['unit']);
  map['borrowed_to'] = Node.cleanBorrower(map['borrowed_to']);
  map['price'] = Money.clean(map['price']);
  map['serial'] = Node.cleanSerial(map['serial']);
  map['service_task'] = Node.cleanServiceTask(map['service_task']);
  // Bakım geçmişi: bozuk satırlar atılır, sıra ve sınır her cihazda aynı.
  final rawLog = map['service_log'];
  if (rawLog != null) {
    map['service_log'] = rawLog is String && rawLog.length <= 40000
        ? ServiceEntry.encode(ServiceEntry.decode(rawLog))
        : null;
  }
  final borrowedAt = map['borrowed_at'];
  if (borrowedAt != null && (borrowedAt is! int || borrowedAt <= 0)) map['borrowed_at'] = null;
  final returnDueAt = map['return_due_at'];
  if (returnDueAt != null && (returnDueAt is! int || returnDueAt <= 0)) map['return_due_at'] = null;
  for (final key in ['buying_at', 'bought_at']) {
    final v = map[key];
    if (v != null && (v is! int || v <= 0)) map[key] = null;
  }
  final buyer = map['buying_by'];
  if (buyer != null && (buyer is! String || buyer.isEmpty || buyer.length > 64)) map['buying_by'] = null;
  final isFull = map['is_full'];
  if (isFull != null && isFull is! int) map['is_full'] = null;
  final managers = map['managers'];
  if (managers != null && (managers is! String || managers.length > 2000)) map['managers'] = null;
  final icon = map['icon'];
  if (icon != null && (icon is! String || icon.isEmpty || icon.length > 40)) map['icon'] = null;
  // Tarihler: sayı olmayan tarih, bozuk süre metni düşer (kayıt kalır).
  for (final key in ['purchased_at', 'expires_at', 'warranty_ends_at', 'serviced_at']) {
    if (map[key] != null && map[key] is! int) map[key] = null;
  }
  for (final key in ['shelf_life', 'warranty', 'expiry_warn', 'service_every']) {
    final v = map[key];
    if (v != null && (v is! String || !TimeSpan.isValid(v))) map[key] = null;
  }
  final heldBy = map['held_by'];
  if (heldBy != null && (heldBy is! String || heldBy.isEmpty || heldBy.length > 200)) map['held_by'] = null;
  final lostFrom = map['lost_from'];
  if (lostFrom != null && (lostFrom is! String || lostFrom == id)) map['lost_from'] = null;
  // Ekler: çözülüp yeniden yazılır; güvensiz yol ya da adres taşıyan ek düşer.
  final rawAttachments = map['attachments'];
  if (rawAttachments != null) {
    map['attachments'] = rawAttachments is String && rawAttachments.length <= 240000
        ? Attachment.encode(Attachment.decode(rawAttachments), Attachment.decodeTombs(rawAttachments))
        : null;
  }
  final image = map['image_path'];
  if (image is! String || !isSafeImagePath(image)) {
    map['image_path'] = null;
    map['image_sig'] = null;
  }
  try {
    return Node.fromMap(map);
  } on Object {
    return null; // alan türleri beklenmedik: bu kaydı almayalım
  }
}

/// Ağ gövdesi olarak durum ve imza için özeti.
class EncodedState {
  const EncodedState(this.body, this.digest);

  final Uint8List body;

  /// Gövdenin SHA-256 özeti ([RequestSigner.headers]'a verilir).
  final String digest;
}

/// Bu kadar kayıttan / bayttan büyük durum ayrı yalıtımda işlenir. Durumu metne
/// çevirmek, özetini almak, çözmek ve her kaydı doğrulamak ana iş parçacığını
/// kesintisiz meşgul ediyordu (5.000 kayıtta her biri ~100 ms: arayüz her
/// eşitlemede takılıyordu). Küçük durumda yalıtım açmanın kendisi daha pahalı:
/// yerinde yapılır. Testler eşiği düşürüp yalıtım yolunu sınar.
int stateOffloadNodes = 400;
int stateOffloadBytes = 200 * 1024;

/// Kaç iş gerçekten ayrı yalıtımda yapıldı (testler yolun kullanıldığını bununla
/// görür: yalıtım açılamazsa iş sessizce yerinde yapılır, sonuç aynı olur).
int stateOffloadCount = 0;

EncodedState _encodeNow(SyncState state) {
  final body = utf8.encode(jsonEncode(state.toJson()));
  return EncodedState(body, sha256.convert(body).toString());
}

SyncState? _decodeNow(List<int> body) {
  try {
    return SyncState.fromJson(jsonDecode(utf8.decode(body)));
  } on FormatException {
    return null;
  }
}

// Yalıtıma giden kapanışlar ayrı işlevlerde kurulur: kapanış, kurulduğu
// kapsamdaki her şeyi taşır; orada gönderilemeyen bir şey (bekleyen bir Future)
// varsa yalıtım hiç başlamaz.
Future<EncodedState> _encodeOff(SyncState state) => Isolate.run(() => _encodeNow(state));

Future<SyncState?> _decodeOff(List<int> body) => Isolate.run(() => _decodeNow(body));

Future<(bool, SyncState?)> _verifyOff(
  List<int> key,
  String method,
  String path,
  List<int> body,
  String? time,
  String? signature,
  DateTime now,
  bool decode,
) =>
    Isolate.run(() => _verifyNow(key, method, path, body, time, signature, now, decode));

(bool, SyncState?) _verifyNow(
  List<int> key,
  String method,
  String path,
  List<int> body,
  String? time,
  String? signature,
  DateTime now,
  bool decode,
) {
  final ok = RequestSigner(key).verify(method: method, path: path, body: body, time: time, signature: signature, now: now);
  // İmzası tutmayan gövde hiç çözülmez.
  return (ok, ok && decode ? _decodeNow(body) : null);
}

/// Durumu ağ gövdesine çevirir ve özetini çıkarır; büyükse ayrı yalıtımda.
Future<EncodedState> encodeState(SyncState state) async {
  if (state.nodes.length < stateOffloadNodes) return _encodeNow(state);
  try {
    final encoded = await _encodeOff(state);
    stateOffloadCount++;
    return encoded;
  } on Object {
    // Yalıtım açılamadıysa iş yine yapılır, yalnızca yerinde.
    return _encodeNow(state);
  }
}

/// Gövdeden durumu çözer (her kayıt [sanitizeNode]'dan geçer); biçim bozuksa
/// null. Büyükse ayrı yalıtımda.
Future<SyncState?> decodeState(List<int> body) async {
  if (body.length < stateOffloadBytes) return _decodeNow(body);
  try {
    final state = await _decodeOff(body);
    stateOffloadCount++;
    return state;
  } on Object {
    return _decodeNow(body);
  }
}

/// Gelen durum isteğinin imzasını doğrular ve (imza tutuyorsa, [decode] de
/// isteniyorsa) gövdeyi çözer. İkisi de gövdenin tamamını okur; büyük gövdede
/// tek yalıtımda, art arda yapılır. İmzasız gövde çözülmez.
Future<(bool ok, SyncState? state)> verifyAndDecodeState({
  required List<int> key,
  required String method,
  required String path,
  required List<int> body,
  required String? time,
  required String? signature,
  required DateTime now,
  bool decode = true,
}) async {
  if (body.length < stateOffloadBytes) return _verifyNow(key, method, path, body, time, signature, now, decode);
  try {
    final result = await _verifyOff(key, method, path, body, time, signature, now, decode);
    stateOffloadCount++;
    return result;
  } on Object {
    return _verifyNow(key, method, path, body, time, signature, now, decode);
  }
}

/// Üyeler arası isteklerin imzası: ortak anahtarla HMAC-SHA256.
///
/// İmza; yöntemi, yolu, zamanı ve gövdenin özetini kapsar. Anahtar yalnızca
/// katılma onayında bir kez gönderilir; sonraki isteklerde ağda dolaşmaz.
/// Zaman penceresi ±5 dakika: eski bir isteğin tekrar oynatılması en fazla
/// aynı veriyi yeniden birleştirir, ki bu zararsızdır.
class RequestSigner {
  RequestSigner(this.key);

  final List<int> key;

  static const timeHeader = 'x-envanter-time';
  static const signatureHeader = 'x-envanter-sig';
  static const tolerance = Duration(minutes: 5);

  /// 401 yanıtında sunucunun saati. Saati elle ayarlı bir telefon pencerenin dışında kalınca imzalı
  /// her isteği reddediliyordu (katılma imzasız olduğu için yine oluyor, envanter hiç gitmiyordu);
  /// istemci farkı buradan öğrenip isteği karşının saatine göre yeniden imzalar.
  static const nowHeader = 'x-envanter-now';

  static Uint8List newKey() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  }

  /// [digest]: gövdenin SHA-256 özeti zaten hesaplandıysa (büyük durumda ayrı
  /// yalıtımda, bkz. [encodeState]) yeniden hesaplanmaz.
  String _sign(String method, String path, int time, List<int> body, {String? digest}) {
    digest ??= sha256.convert(body).toString();
    final message = utf8.encode('$method\n$path\n$time\n$digest');
    return Hmac(sha256, key).convert(message).toString();
  }

  Map<String, String> headers(String method, String path, List<int> body, DateTime now, {String? digest}) {
    final time = now.millisecondsSinceEpoch;
    return {
      timeHeader: '$time',
      signatureHeader: _sign(method, path, time, body, digest: digest),
    };
  }

  bool verify({
    required String method,
    required String path,
    required List<int> body,
    required String? time,
    required String? signature,
    required DateTime now,
  }) {
    final t = int.tryParse(time ?? '');
    if (t == null || signature == null) return false;
    final skew = (now.millisecondsSinceEpoch - t).abs();
    if (skew > tolerance.inMilliseconds) return false;
    return _constantTimeEquals(_sign(method, path, t, body), signature);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
