import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/money.dart';
import '../core/time_span.dart';

/// Envanterdeki her kayıt bir [Node]. Klasör ve eşya aynı ağaçta yasar;
/// aradaki tek fark [kind] ve klasörlerin cocuk alabilmesi.
enum NodeKind { container, item }

@immutable
class Node {
  const Node({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    required this.color,
    required this.sortIndex,
    required this.createdAt,
    required this.updatedAt,
    this.imagePath,
    this.lat,
    this.lng,
    this.locationLabel,
    this.note,
    this.inDrawer = false,
    this.deletedAt,
    this.imageSig,
    this.updatedBy,
    this.lostAt,
    this.lostFrom,
    this.icon,
    this.managers = const [],
    this.quantity,
    this.isFull = false,
    this.heldBy,
    this.purchasedAt,
    this.expiresAt,
    this.shelfLife,
    this.warrantyEndsAt,
    this.warranty,
    this.expiryWarn,
    this.minQuantity,
    this.wantedAt,
    this.buyingBy,
    this.buyingAt,
    this.boughtAt,
    this.autoShop = false,
    this.lots = const [],
    this.attachments = const [],
    this.attachmentTombs = const {},
    this.barcode,
    this.unit,
    this.borrowedTo,
    this.borrowedAt,
    this.returnDueAt,
    this.price,
    this.serial,
    this.serviceEvery,
    this.serviceTask,
    this.servicedAt,
    this.serviceLog = const [],
    this.fieldTimes = const {},
  });

  final String id;

  /// null ise kök seviyededir (ana ekran veya çekmece).
  final String? parentId;
  final NodeKind kind;
  final String name;

  /// Uygulama belgeler klasorune göre goreli yol, orn. `images/ab12.jpg`.
  final String? imagePath;

  /// Resim yoksa kart rengi, resim varsa çerçeve rengi.
  final int color;

  final double? lat;
  final double? lng;
  final String? locationLabel;
  final String? note;

  /// Görüntüyle aramanın kullandığı parmak izi (bkz. ImageSignature).
  /// Resim değişince yeniden hesaplanır.
  final String? imageSig;

  /// Son değiştiren cihazın kimliği (ortak kullanımda "kim yaptı").
  final String? updatedBy;

  /// Doluysa eşya yerinde bulunamamış, kayıp çekmecesinde bekliyor.
  final DateTime? lostAt;

  /// Kaybolmadan önce durduğu klasör (null: ana ekran ya da çekmece).
  final String? lostFrom;

  /// Kullanıcının seçtiği simgenin anahtarı (bkz. NodeIcons); null ise türün
  /// varsayılan simgesi.
  final String? icon;

  /// Klasörün sorumluları (cihaz kimlikleri). Sorumlunun bu klasörde
  /// ve içindekilerde yaptığı değişiklikler diğerlerine onaysız uygulanır.
  final List<String> managers;

  /// Eşyanın adedi. null: adet tutulmuyor (tek bir nesne). 0 olabilir:
  /// tükenen sarf malzemesinin kaydı ve yeri durur, stok gelince sayı artar.
  final int? quantity;

  bool get tracksQuantity => quantity != null;

  /// Ortak bir kaydı biri kendi "yalnızca bende" alanına aldı: bu cihazın
  /// kimliği. O cihaz kaydı artık göndermez; son bildirdiği sürümde kayıt
  /// herkesin çekmecesinde bu işaretle durur ("Ayşe'de"). Başkası onu bir yere
  /// koyunca işaret kalkar.
  final String? heldBy;

  // Tarihler (eşyada). Hepsi gün olarak tutulur (yerel gece yarısı).

  /// Satın alma tarihi. Raf ömrü ve garanti süresi buna eklenir.
  final DateTime? purchasedAt;

  /// Paketin üstünde yazan son kullanma tarihi.
  final DateTime? expiresAt;

  /// Son kullanma tarihi yazmayanlar (muz, elma) için: satın almadan bu kadar
  /// sonra biter. Kısa metin ([TimeSpan.encode]); tarih verildiyse kullanılmaz.
  final String? shelfLife;

  /// Garanti belgesindeki bitiş tarihi.
  final DateTime? warrantyEndsAt;

  /// Garanti süresi; bitiş tarihi verilmediyse satın alma tarihine eklenir.
  final String? warranty;

  /// Bu eşyaya özel "son kullanmaya kala uyar" süresi (ör. bisküvi 1 ay). null
  /// ise ayarlardaki genel süre.
  final String? expiryWarn;

  /// Adet bu sayıya (ya da altına) inince alışveriş listesine "azalan" olarak
  /// girer. null: izlenmiyor.
  final int? minQuantity;

  bool get isLow =>
      minQuantity != null && quantity != null && quantity! > 0 && quantity! <= minQuantity!;

  /// Alışveriş listesine eklendiği an; null: listede değil. Kaydın bir alanı:
  /// ortak kullanımda liste de ortak (Ayşe'nin eklediği sütü herkes görür).
  /// Tükenen, azalan ya da tarihi geçen eşya ayrıca otomatik girebilir, ama
  /// yalnızca envanterde "otomatik ekle" açıksa (varsayılan kapalı).
  final DateTime? wantedAt;

  bool get isWanted => wantedAt != null;

  /// "Alıyorum" diyen cihaz ve an: evden çıkmadan söylenir, ötekiler listede
  /// "Ayşe alıyor" görür, iki kişi aynı şeyi almaz. Bir günden eskisi sayılmaz.
  final String? buyingBy;
  final DateTime? buyingAt;

  /// Markette işaretlendi ("Aldım"): adet ve tarih evde, "Yerleştir" adımında
  /// girilir. O zamana dek listeden düşer, "Yerleştirilecek"te durur.
  final DateTime? boughtAt;

  bool get isBought => boughtAt != null;

  /// Geçerli "alıyorum" işareti (bir günden eski değil).
  String? buyingNow(DateTime now) =>
      buyingBy != null && buyingAt != null && now.difference(buyingAt!) < const Duration(days: 1) ? buyingBy : null;

  /// Bitince, azalınca ya da son kullanma tarihi geçince alışveriş listesine
  /// kendiliğinden girsin. Eşyanın kendi ayarı (düzenleyicide), varsayılan
  /// kapalı: kapalıyken böyle bir eşya listeye yalnızca önerilir.
  final bool autoShop;

  /// Aynı eşyanın farklı son kullanma tarihli paketleri (6 yoğurt: 2 tanesi
  /// 5 Eki, 4 tanesi 12 Eki), tarihe göre sıralı. Boşsa tek tarih
  /// ([expiresAt] ya da raf ömrü) bütün eşyaya geçer; birden fazla tarih
  /// olunca adet paketlerin toplamıdır. Paket işlemleri `lots.dart`'ta.
  final List<Lot> lots;

  bool get hasLots => lots.isNotEmpty;

  /// Kayda iliştirilenler: kullanım kılavuzu, garanti belgesinin fotoğrafı,
  /// bir video, bir bağlantı. Dosyalar envanterin `files/` klasöründe durur.
  final List<Attachment> attachments;

  /// Çıkarılan eklerin izleri (ek kimliği → çıkarıldığı an, ms). Ekler
  /// eşitlemede tek tek birleşir: iz olmasaydı, eki hâlâ tutan bir cihazla
  /// birleşince çıkarılan ek geri gelirdi. Arayüzde görünmez; eklerle aynı
  /// sütunda ve aynı ağ alanında taşınır (bkz. [Attachment.encode]).
  final Map<String, int> attachmentTombs;

  /// Ürünün üstündeki barkod (EAN, UPC, Code 128...): okutulunca bu kayıt bulunur.
  /// Uygulamanın kendi QR etiketinden ayrı; aynı barkod birden çok kayıtta olabilir
  /// (aynı üründen iki yerde).
  final String? barcode;

  /// Adet veya miktarın ölçü birimi (ör. "adet", "paket", "kg", "m", "lt").
  /// null ise varsayılan adet ("tane").
  final String? unit;

  /// Eşyanın ödünç verildiği kişinin adı. null ya da boş ise ödünçte değil.
  final String? borrowedTo;

  /// Ödünç verilme anı/tarihi.
  final DateTime? borrowedAt;

  /// Beklenen iade tarihi (opsiyonel).
  final DateTime? returnDueAt;

  /// Eşya birine ödünç verilmiş mi?
  bool get isBorrowed => borrowedTo != null && borrowedTo!.trim().isNotEmpty;

  /// Beklenen iade tarihi geçmiş mi?
  bool get isBorrowOverdue =>
      isBorrowed && returnDueAt != null && dateOnly(DateTime.now()).isAfter(dateOnly(returnDueAt!));

  bool get hasAttachments => attachments.isNotEmpty;

  /// Bir tanesinin fiyatı (alış bedeli ya da biçilen değer), [Money.encode] metni
  /// ("1250.50 TRY"). Adet tutulan eşyada birim fiyattır; toplam değer adetle
  /// çarpılır ([value]). Klasörün kendi fiyatı olmaz, değeri içindekilerin toplamıdır.
  final String? price;

  Money? get priceMoney => Money.decode(price);

  /// Eşyanın toplam değeri: fiyat × adet (adet tutulmuyorsa tek tane). Fiyat yoksa null.
  Money? get value {
    final p = priceMoney;
    if (p == null) return null;
    return quantity == null ? p : p.times(quantity!);
  }

  /// Seri ya da model numarası (cihazın etiketinden, faturadan). Sigorta ve garanti
  /// başvurusunda istenir; aramada da bulunur.
  final String? serial;

  /// Seri numarası metni: denetim karakteri yok, en çok 80 karakter. Boşsa null.
  static String? cleanSerial(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty || text.length > 80 || text.contains(RegExp(r'[\x00-\x1F\x7F]')) ? null : text;
  }

  /// Tek satırlık kısa metin: kırpılır, denetim karakteri (satır sonu dahil) yok, en çok [max]
  /// karakter. Boşsa ya da uymuyorsa null.
  static String? _cleanLine(Object? raw, int max) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty || text.length > max || text.contains(RegExp(r'[\x00-\x1F\x7F]')) ? null : text;
  }

  // Periyodik bakım (alet, cihaz, araç): "3 ayda bir yağla". Satın alma ve son kullanma
  // tarihlerinden ayrı tutulur: bakım onları değiştirmez (garanti satın almadan sayılır).

  /// Bakımın aralığı, [TimeSpan.encode] metni ("3m"). null: periyodik bakım yok (geçmiş yine
  /// tutulabilir: arıza ve onarım kaydı gibi).
  final String? serviceEvery;

  /// Bakımda ne yapılacağı ("Filtreyi değiştir"); isteğe bağlı, kısa.
  final String? serviceTask;

  /// Son bakımın günü: sonraki bakım buna [serviceEvery] eklenerek bulunur. "Bakım yapıldı"
  /// bugüne çeker; döngü ilk kurulurken düzenleyici verir (kullanıcı değiştirebilir).
  final DateTime? servicedAt;

  /// Bakım geçmişi, en yeni önce ([ServiceEntry.order]). "Bakım yapıldı" bir satır ekler.
  final List<ServiceEntry> serviceLog;

  /// Bakımda ne yapılacağı metni (en çok 80 karakter).
  static String? cleanServiceTask(Object? raw) => _cleanLine(raw, 80);

  /// Sonraki bakım günü; döngü ya da son bakım günü yoksa null.
  DateTime? get nextService {
    final every = TimeSpan.parse(serviceEvery);
    return every == null || servicedAt == null ? null : every.addTo(servicedAt!);
  }

  /// Bakımla ilgili bir bilgisi var mı (döngü, son bakım ya da geçmiş).
  bool get hasService => serviceEvery != null || servicedAt != null || serviceLog.isNotEmpty;

  /// Bakımın [today] günündeki durumu; döngüsü yoksa null. Gün geçtiyse gecikmiş
  /// ([ExpiryState.expired]); bakım günü ve öncesindeki pay içinde "yaklaştı"
  /// ([ExpiryState.soon]). Pay döngünün dörtte biri, en çok bir hafta: haftalık bakım bir gün,
  /// yıllık bakım bir hafta önceden görünür (usta çağrılacaksa vakit kalsın).
  ExpiryState? serviceStateOn(DateTime today) {
    final next = nextService;
    if (next == null) return null;
    final left = daysBetween(today, next);
    if (left < 0) return ExpiryState.expired;
    final lead = (daysBetween(servicedAt!, next) ~/ 4).clamp(0, 7);
    return left <= lead ? ExpiryState.soon : ExpiryState.fine;
  }

  /// Barkod olarak saklanabilecek metin: yazdırılabilir ASCII, en çok 80 karakter
  /// (Code 128 harf ve işaret de taşır). Boşsa ya da uymuyorsa null.
  static String? cleanBarcode(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty || text.length > 80 || !_barcodeText.hasMatch(text) ? null : text;
  }

  /// Ölçü birimi metni: en fazla 16 karakter, boşluklar kırpılır.
  static String? cleanUnit(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty || text.length > 16 ? null : text;
  }

  /// Ödünç alan kişi adı: en fazla 100 karakter, boşluklar kırpılır.
  static String? cleanBorrower(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty || text.length > 100 ? null : text;
  }

  static final _barcodeText = RegExp(r'^[\x20-\x7E]+$');

  /// Alan gruplarının son değişme anı (ms; bkz. sync/fields.dart). Eşitlemede
  /// her grup ayrı birleşir: iki kişi aynı eşyanın farklı alanlarını
  /// değiştirirse ikisi de kalır. Boşsa (eski kayıt) hepsi [updatedAt] sayılır.
  final Map<String, int> fieldTimes;

  /// Hesaplanan son kullanma günü: yazan tarih, yoksa satın alma + raf ömrü.
  /// En yakın son kullanma: paket varsa en eskisininki. Uyarı ve kartın
  /// damgası buna bakar.
  DateTime? get effectiveExpiry {
    if (lots.isNotEmpty) return lots.first.expires;
    if (expiresAt != null) return expiresAt;
    final life = TimeSpan.parse(shelfLife);
    return purchasedAt == null || life == null ? null : life.addTo(purchasedAt!);
  }

  /// En uzak son kullanma: paket varsa en yenisininki. "Hepsinin tarihi
  /// geçti" (yenisini almak gerekir) buna bakar.
  DateTime? get lastExpiry => lots.isNotEmpty ? lots.last.expires : effectiveExpiry;

  /// Bütün farklı son kullanma tarihleri (bildirim her biri için).
  List<DateTime> get expiryDates => lots.isNotEmpty ? [for (final b in lots) b.expires] : [?effectiveExpiry];

  /// Hesaplanan garanti bitişi: yazan tarih, yoksa satın alma + garanti süresi.
  DateTime? get effectiveWarrantyEnd {
    if (warrantyEndsAt != null) return warrantyEndsAt;
    final span = TimeSpan.parse(warranty);
    return purchasedAt == null || span == null ? null : span.addTo(purchasedAt!);
  }

  bool get hasDates =>
      purchasedAt != null || effectiveExpiry != null || effectiveWarrantyEnd != null;

  /// Klasörün yeri doldu: içine yeni bir şey sığmıyor. Kullanıcı elle
  /// işaretler; kayıt sayısından bağımsızdır (kaydı olmayan eşyalarla da
  /// dolabilir). Yer ararken kartın üstünde görünür.
  final bool isFull;

  final double sortIndex;

  /// Yeri henuz belli olmayanların durduğu sag çekmece. Sadece
  /// [parentId] null iken anlamlidir.
  final bool inDrawer;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Dolu ise çöp kutusunda demektir. Alt ağaç birlikte gizlenir.
  final DateTime? deletedAt;

  bool get isContainer => kind == NodeKind.container;
  bool get isDeleted => deletedAt != null;
  bool get isLost => lostAt != null;
  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasGeo => lat != null && lng != null;

  /// Eşyaların adı boş bırakılabilir; "adsız" etiketini dile duyarlı
  /// olabilmesi için arayüz katmanı koyar ([InventoryStore.nameOf]).
  String get trimmedName => name.trim();
  bool get hasName => trimmedName.isNotEmpty;

  Node copyWith({
    String? parentId,
    bool clearParent = false,
    NodeKind? kind,
    String? name,
    String? imagePath,
    bool clearImage = false,
    int? color,
    double? lat,
    double? lng,
    String? locationLabel,
    bool clearGeo = false,
    String? note,
    String? imageSig,
    bool clearSignature = false,
    String? updatedBy,
    double? sortIndex,
    bool? inDrawer,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? lostAt,
    String? lostFrom,
    bool clearLost = false,
    String? icon,
    bool clearIcon = false,
    List<String>? managers,
    int? quantity,
    bool clearQuantity = false,
    bool? isFull,
    String? heldBy,
    bool clearHeld = false,
    DateTime? purchasedAt,
    bool clearPurchased = false,
    DateTime? expiresAt,
    bool clearExpires = false,
    String? shelfLife,
    bool clearShelfLife = false,
    DateTime? warrantyEndsAt,
    bool clearWarrantyEnd = false,
    String? warranty,
    bool clearWarranty = false,
    String? expiryWarn,
    bool clearExpiryWarn = false,
    int? minQuantity,
    bool clearMinQuantity = false,
    DateTime? wantedAt,
    bool clearWanted = false,
    String? buyingBy,
    DateTime? buyingAt,
    bool clearBuying = false,
    DateTime? boughtAt,
    bool clearBought = false,
    bool? autoShop,
    List<Lot>? lots,
    List<Attachment>? attachments,
    Map<String, int>? attachmentTombs,
    String? barcode,
    bool clearBarcode = false,
    String? unit,
    bool clearUnit = false,
    String? borrowedTo,
    bool clearBorrow = false,
    DateTime? borrowedAt,
    DateTime? returnDueAt,
    bool clearReturnDue = false,
    String? price,
    bool clearPrice = false,
    String? serial,
    bool clearSerial = false,
    String? serviceEvery,
    bool clearServiceEvery = false,
    String? serviceTask,
    bool clearServiceTask = false,
    DateTime? servicedAt,
    bool clearServiced = false,
    List<ServiceEntry>? serviceLog,
    Map<String, int>? fieldTimes,
  }) {
    return Node(
      id: id,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      kind: kind ?? this.kind,
      name: name ?? this.name,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      color: color ?? this.color,
      lat: clearGeo ? null : (lat ?? this.lat),
      lng: clearGeo ? null : (lng ?? this.lng),
      locationLabel: clearGeo ? null : (locationLabel ?? this.locationLabel),
      note: note ?? this.note,
      imageSig: clearSignature ? null : (imageSig ?? this.imageSig),
      updatedBy: updatedBy ?? this.updatedBy,
      sortIndex: sortIndex ?? this.sortIndex,
      inDrawer: inDrawer ?? this.inDrawer,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      lostAt: clearLost ? null : (lostAt ?? this.lostAt),
      lostFrom: clearLost ? null : (lostFrom ?? this.lostFrom),
      icon: clearIcon ? null : (icon ?? this.icon),
      managers: managers ?? this.managers,
      quantity: clearQuantity ? null : (quantity ?? this.quantity),
      isFull: isFull ?? this.isFull,
      heldBy: clearHeld ? null : (heldBy ?? this.heldBy),
      purchasedAt: clearPurchased ? null : (purchasedAt ?? this.purchasedAt),
      expiresAt: clearExpires ? null : (expiresAt ?? this.expiresAt),
      shelfLife: clearShelfLife ? null : (shelfLife ?? this.shelfLife),
      warrantyEndsAt: clearWarrantyEnd ? null : (warrantyEndsAt ?? this.warrantyEndsAt),
      warranty: clearWarranty ? null : (warranty ?? this.warranty),
      expiryWarn: clearExpiryWarn ? null : (expiryWarn ?? this.expiryWarn),
      minQuantity: clearMinQuantity ? null : (minQuantity ?? this.minQuantity),
      wantedAt: clearWanted ? null : (wantedAt ?? this.wantedAt),
      buyingBy: clearBuying ? null : (buyingBy ?? this.buyingBy),
      buyingAt: clearBuying ? null : (buyingAt ?? this.buyingAt),
      boughtAt: clearBought ? null : (boughtAt ?? this.boughtAt),
      autoShop: autoShop ?? this.autoShop,
      lots: lots ?? this.lots,
      attachments: attachments ?? this.attachments,
      attachmentTombs: attachmentTombs ?? this.attachmentTombs,
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      unit: clearUnit ? null : (unit ?? this.unit),
      borrowedTo: clearBorrow ? null : (borrowedTo ?? this.borrowedTo),
      borrowedAt: clearBorrow ? null : (borrowedAt ?? this.borrowedAt),
      returnDueAt: (clearBorrow || clearReturnDue) ? null : (returnDueAt ?? this.returnDueAt),
      price: clearPrice ? null : (price ?? this.price),
      serial: clearSerial ? null : (serial ?? this.serial),
      serviceEvery: clearServiceEvery ? null : (serviceEvery ?? this.serviceEvery),
      serviceTask: clearServiceTask ? null : (serviceTask ?? this.serviceTask),
      servicedAt: clearServiced ? null : (servicedAt ?? this.servicedAt),
      serviceLog: serviceLog ?? this.serviceLog,
      fieldTimes: fieldTimes ?? this.fieldTimes,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'parent_id': parentId,
        'kind': kind.name,
        'name': name,
        'image_path': imagePath,
        'color': color,
        'lat': lat,
        'lng': lng,
        'location_label': locationLabel,
        'note': note,
        'image_sig': imageSig,
        'updated_by': updatedBy,
        'sort_index': sortIndex,
        'in_drawer': inDrawer ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'lost_at': lostAt?.millisecondsSinceEpoch,
        'lost_from': lostFrom,
        'icon': icon,
        'managers': managers.isEmpty ? null : managers.join(','),
        'quantity': quantity,
        'is_full': isFull ? 1 : 0,
        'held_by': heldBy,
        'purchased_at': purchasedAt?.millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'shelf_life': shelfLife,
        'warranty_ends_at': warrantyEndsAt?.millisecondsSinceEpoch,
        'warranty': warranty,
        'expiry_warn': expiryWarn,
        'min_quantity': minQuantity,
        'wanted_at': wantedAt?.millisecondsSinceEpoch,
        'buying_by': buyingBy,
        'buying_at': buyingAt?.millisecondsSinceEpoch,
        'bought_at': boughtAt?.millisecondsSinceEpoch,
        'auto_shop': autoShop ? 1 : 0,
        'lots': Lot.encode(lots),
        'attachments': Attachment.encode(attachments, attachmentTombs),
        'barcode': barcode,
        'unit': unit,
        'borrowed_to': borrowedTo,
        'borrowed_at': borrowedAt?.millisecondsSinceEpoch,
        'return_due_at': returnDueAt?.millisecondsSinceEpoch,
        'price': price,
        'serial': serial,
        'service_every': serviceEvery,
        'service_task': serviceTask,
        'serviced_at': servicedAt?.millisecondsSinceEpoch,
        'service_log': ServiceEntry.encode(serviceLog),
        // Sıralı: aynı zamanlar her cihazda aynı metni versin.
        'field_times': fieldTimes.isEmpty
            ? null
            : jsonEncode({for (final k in (fieldTimes.keys.toList()..sort())) k: fieldTimes[k]}),
      };

  static Map<String, int> _times(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return const {};
      return {
        for (final e in map.entries)
          if (e.key is String && e.value is int && (e.value as int) >= 0) e.key as String: e.value as int,
      };
    } on FormatException {
      return const {};
    }
  }

  static DateTime? _day(Object? ms) =>
      ms is int ? dateOnly(DateTime.fromMillisecondsSinceEpoch(ms)) : null;

  static String? _span(Object? raw) => raw is String && TimeSpan.isValid(raw) ? raw : null;

  static Node fromMap(Map<String, Object?> m) => Node(
        id: m['id']! as String,
        parentId: m['parent_id'] as String?,
        kind: (m['kind'] as String?) == 'item' ? NodeKind.item : NodeKind.container,
        name: (m['name'] as String?) ?? '',
        imagePath: m['image_path'] as String?,
        color: (m['color'] as int?) ?? 0xFF6E7B8B,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        locationLabel: m['location_label'] as String?,
        note: m['note'] as String?,
        imageSig: m['image_sig'] as String?,
        updatedBy: m['updated_by'] as String?,
        sortIndex: (m['sort_index'] as num?)?.toDouble() ?? 0,
        inDrawer: ((m['in_drawer'] as int?) ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['deleted_at']! as int),
        lostAt: m['lost_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['lost_at']! as int),
        lostFrom: m['lost_from'] as String?,
        icon: m['icon'] as String?,
        managers: [
          for (final id in ((m['managers'] as String?) ?? '').split(','))
            if (id.trim().isNotEmpty) id.trim(),
        ],
        quantity: (m['quantity'] as num?)?.toInt(),
        isFull: ((m['is_full'] as int?) ?? 0) == 1,
        heldBy: switch (m['held_by']) {
          final String by when by.isNotEmpty => by,
          _ => null,
        },
        purchasedAt: _day(m['purchased_at']),
        expiresAt: _day(m['expires_at']),
        shelfLife: _span(m['shelf_life']),
        warrantyEndsAt: _day(m['warranty_ends_at']),
        warranty: _span(m['warranty']),
        expiryWarn: _span(m['expiry_warn']),
        minQuantity: switch (m['min_quantity']) {
          final int v when v >= 0 => v,
          _ => null,
        },
        wantedAt: switch (m['wanted_at']) {
          final int v when v > 0 => DateTime.fromMillisecondsSinceEpoch(v),
          _ => null,
        },
        buyingBy: switch (m['buying_by']) {
          final String v when v.isNotEmpty => v,
          _ => null,
        },
        buyingAt: switch (m['buying_at']) {
          final int v when v > 0 => DateTime.fromMillisecondsSinceEpoch(v),
          _ => null,
        },
        boughtAt: switch (m['bought_at']) {
          final int v when v > 0 => DateTime.fromMillisecondsSinceEpoch(v),
          _ => null,
        },
        autoShop: m['auto_shop'] == 1,
        lots: Lot.decode(m['lots']),
        attachments: Attachment.decode(m['attachments']),
        attachmentTombs: Attachment.decodeTombs(m['attachments']),
        barcode: cleanBarcode(m['barcode']),
        unit: cleanUnit(m['unit']),
        borrowedTo: cleanBorrower(m['borrowed_to']),
        borrowedAt: switch (m['borrowed_at']) {
          final int v when v > 0 => DateTime.fromMillisecondsSinceEpoch(v),
          _ => null,
        },
        returnDueAt: _day(m['return_due_at']),
        price: Money.clean(m['price']),
        serial: cleanSerial(m['serial']),
        serviceEvery: _span(m['service_every']),
        serviceTask: cleanServiceTask(m['service_task']),
        servicedAt: _day(m['serviced_at']),
        serviceLog: ServiceEntry.decode(m['service_log']),
        fieldTimes: _times(m['field_times']),
      );

  @override
  bool operator ==(Object other) => other is Node && other.id == id && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, updatedAt);
}

/// Bir paket: kaç tane ve son kullanma günü.
@immutable
class Lot {
  const Lot(this.count, this.expires);

  final int count;

  /// Gün başı (yerel).
  final DateTime expires;

  Lot withCount(int c) => Lot(c, expires);

  @override
  bool operator ==(Object other) => other is Lot && other.count == count && other.expires == expires;

  @override
  int get hashCode => Object.hash(count, expires);

  @override
  String toString() => '$count×${expires.toIso8601String().substring(0, 10)}';

  /// Veritabanında ve ağda JSON metin; boşsa null.
  static String? encode(List<Lot> lots) => lots.isEmpty
      ? null
      : jsonEncode([for (final b in lots) {'c': b.count, 'e': b.expires.millisecondsSinceEpoch}]);

  /// Bozuk ya da boşsa boş liste.
  static List<Lot> decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map && e['c'] is int && (e['c'] as int) > 0 && e['e'] is int)
            Lot(e['c'] as int, dateOnly(DateTime.fromMillisecondsSinceEpoch(e['e'] as int))),
      ]..sort((a, b) => a.expires.compareTo(b.expires));
    } on FormatException {
      return const [];
    }
  }
}

/// Bakım geçmişinin bir satırı: hangi gün yapıldı, isteğe bağlı kısa not ("Filtre değişti,
/// 450 ₺", "Servis: Ahmet usta").
@immutable
class ServiceEntry {
  const ServiceEntry(this.day, [this.note]);

  /// Gün başı (yerel).
  final DateTime day;
  final String? note;

  /// Saklanan satır sayısı (en yenileri): yılda birkaç bakımla on yıllarca yeter.
  static const maxCount = 100;

  /// Notun uzunluk sınırı.
  static const maxNote = 200;

  static String? cleanNote(Object? raw) => Node._cleanLine(raw, maxNote);

  /// Değişmez sıra: en yeni gün önce, aynı günde nota göre. Her cihazda aynı olmalı (grup
  /// değeri ve eşitlikte karar metne bakar).
  static int order(ServiceEntry a, ServiceEntry b) {
    final c = b.day.compareTo(a.day);
    return c != 0 ? c : (a.note ?? '').compareTo(b.note ?? '');
  }

  /// [log]'a [entry] eklenmiş, sıralı ve sınırlı hali.
  static List<ServiceEntry> add(List<ServiceEntry> log, ServiceEntry entry) => _trim([...log, entry]..sort(order));

  static List<ServiceEntry> _trim(List<ServiceEntry> log) => log.length > maxCount ? log.sublist(0, maxCount) : log;

  @override
  bool operator ==(Object other) => other is ServiceEntry && other.day == day && other.note == note;

  @override
  int get hashCode => Object.hash(day, note);

  @override
  String toString() => '${day.toIso8601String().substring(0, 10)}${note == null ? '' : ' $note'}';

  /// Veritabanında ve ağda JSON metin, [order] sırasıyla; boşsa null.
  static String? encode(List<ServiceEntry> log) => log.isEmpty
      ? null
      : jsonEncode([
          for (final e in _trim(log.toList()..sort(order)))
            {'d': e.day.millisecondsSinceEpoch, if (e.note != null) 'n': e.note},
        ]);

  /// Bozuk satırlar atlanır (ağdan ve yedekten gelen de buradan geçer); sonuç sıralı ve sınırlı.
  static List<ServiceEntry> decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return _trim([
        for (final e in list)
          if (e is Map && e['d'] is int && (e['d'] as int) > 0 && (e['n'] == null || cleanNote(e['n']) != null))
            ServiceEntry(dateOnly(DateTime.fromMillisecondsSinceEpoch(e['d'] as int)), cleanNote(e['n'])),
      ]..sort(order));
    } on FormatException {
      return const [];
    }
  }
}

/// Ekin türü; dosyalarda MIME türünden, bağlantıda adresten anlaşılır.
enum AttachmentKind { photo, video, document, link }

/// Kayda iliştirilen bir dosya ya da bağlantı.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.addedAt,
    this.file,
    this.url,
    this.mime,
    this.size = 0,
    this.changedAt,
  });

  final String id;

  /// Görünen ad: dosyanın adı ya da kullanıcının verdiği başlık.
  final String name;

  /// Dosyaysa envanter klasörüne göre yol (`files/ab12.pdf`).
  final String? file;

  /// Bağlantıysa adres (http/https).
  final String? url;

  final String? mime;

  /// Dosyanın boyutu (bayt): karşı cihaz indirirken bunu bekler.
  final int size;

  final DateTime addedAt;

  /// Bu ekin son değiştiği an (eklenme, ad değişimi, reddedilen bir değişiklikte
  /// "bizimki geçerli"). Eşitlemede ek ek karar bununla verilir; yoksa eklendiği an.
  /// Kullanıcının gördüğü bir şey değil: [==] buna bakmaz.
  final DateTime? changedAt;

  /// Karşılaştırılan zaman (ms).
  int get stamp => (changedAt ?? addedAt).millisecondsSinceEpoch;

  bool get isLink => url != null;

  AttachmentKind get kind {
    if (isLink) return AttachmentKind.link;
    final m = mime ?? '';
    if (m.startsWith('image/')) return AttachmentKind.photo;
    if (m.startsWith('video/')) return AttachmentKind.video;
    return AttachmentKind.document;
  }

  /// Dosya adının uzantısı, büyük harfle ("PDF"); yoksa boş.
  String get extension {
    final source = file ?? '';
    final dot = source.lastIndexOf('.');
    return dot < 0 || dot == source.length - 1 ? '' : source.substring(dot + 1).toUpperCase();
  }

  /// Bağlantının sitesi ("youtube.com"); adres bozuksa adresin kendisi.
  String get host {
    final h = Uri.tryParse(url ?? '')?.host ?? '';
    return h.isEmpty ? (url ?? '') : (h.startsWith('www.') ? h.substring(4) : h);
  }

  Attachment renamed(String name) => Attachment(
        id: id,
        name: name,
        addedAt: addedAt,
        file: file,
        url: url,
        mime: mime,
        size: size,
        changedAt: changedAt,
      );

  /// Aynı ek, [at] anında değişmiş sayılarak.
  Attachment touched(DateTime at) =>
      Attachment(id: id, name: name, addedAt: addedAt, file: file, url: url, mime: mime, size: size, changedAt: at);

  Map<String, Object?> toJson() => {
        'i': id,
        'n': name,
        'a': addedAt.millisecondsSinceEpoch,
        if (file != null) 'f': file,
        if (url != null) 'u': url,
        if (mime != null) 'm': mime,
        if (size > 0) 's': size,
        if (changedAt != null && changedAt != addedAt) 't': changedAt!.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.id == id &&
      other.name == name &&
      other.file == file &&
      other.url == url &&
      other.mime == mime &&
      other.size == size &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, name, file, url, mime, size, addedAt);

  @override
  String toString() => 'Attachment($name, ${file ?? url})';

  /// Bir kayıtta en fazla bu kadar ek (eklerken).
  static const maxCount = 40;

  /// Saklanan ve ağdan kabul edilen üst sınır. Ekleme sınırından büyük: iki
  /// cihazda ayrı ayrı eklenenler birleşince [maxCount] aşılabilir; orada
  /// kesmek hangi cihazın eklerinin atılacağını sıraya bırakırdı.
  static const maxStored = 160;

  /// Saklanan iz sayısı (en yenileri).
  static const maxTombs = 200;

  /// Eklerin değişmez sırası: eklenme anı, eşitse kimlik. Her cihazda aynı
  /// olmalı (birleşen liste iki tarafta da aynı metne dönmeli).
  static int order(Attachment a, Attachment b) {
    final c = a.addedAt.millisecondsSinceEpoch.compareTo(b.addedAt.millisecondsSinceEpoch);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  static List<Attachment> sorted(Iterable<Attachment> list) => list.toList()..sort(order);

  /// Tek dosyanın üst sınırı: daha büyüğü eklenmez, karşıdan da alınmaz.
  static const maxBytes = 500 * 1024 * 1024;

  static final _safeFile = RegExp(r'^files/[A-Za-z0-9._-]+$');
  static final _safeMime = RegExp(r'^[a-z0-9.+-]+/[A-Za-z0-9.+-]+$');

  /// Uygulamanın ek yolları hep bu biçimde (bkz. wire.dart'taki resim yolu).
  static bool isSafeFile(String? path) => path != null && _safeFile.hasMatch(path) && !path.contains('..');

  /// Yalnızca tarayıcının açacağı adresler; "file:", "content:" gibileri
  /// karşıdan gelen bir kayıtla cihazdaki dosyaları açtırabilirdi.
  static bool isSafeUrl(String? url) {
    if (url == null || url.length > 2000) return false;
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  /// Veritabanında ve ağda JSON metin; ek de iz de yoksa null. Ekler [order]
  /// sırasıyla, izler (`{"i": kimlik, "x": an}`) kimlik sırasıyla yazılır: aynı
  /// içerik her cihazda aynı metindir (sürüm karşılaştırması ve damga buna güvenir).
  static String? encode(List<Attachment> list, [Map<String, int> tombs = const {}]) {
    if (list.isEmpty && tombs.isEmpty) return null;
    final ids = tombs.keys.toList()..sort();
    return jsonEncode([
      for (final a in sorted(list)) a.toJson(),
      for (final id in ids) {'i': id, 'x': tombs[id]},
    ]);
  }

  /// Çıkarılan eklerin izleri (bkz. [Node.attachmentTombs]). Hâlâ duran bir ekin
  /// izi sayılmaz; en yeni [maxTombs] tanesi tutulur.
  static Map<String, int> decodeTombs(Object? raw) {
    if (raw is! String || raw.isEmpty || !raw.contains('"x"')) return const {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const {};
      final out = <String, int>{};
      final live = <String>{};
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['i'];
        final at = e['x'];
        if (id is! String || id.isEmpty || id.length > 64) continue;
        if (at is int && at >= 0) {
          if (at > (out[id] ?? -1)) out[id] = at;
        } else {
          live.add(id);
        }
      }
      out.removeWhere((id, _) => live.contains(id));
      return trimTombs(out);
    } on FormatException {
      return const {};
    }
  }

  /// En yeni [maxTombs] iz (eşitlikte kimlik sırası): her cihaz aynısını tutar.
  static Map<String, int> trimTombs(Map<String, int> tombs) {
    if (tombs.length <= maxTombs) return tombs;
    final ids = tombs.keys.toList()
      ..sort((a, b) {
        final c = tombs[b]!.compareTo(tombs[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return {for (final id in ids.take(maxTombs)) id: tombs[id]!};
  }

  /// Bozuk ya da güvensiz olanlar atlanır: ağdan ve yedekten gelen de buradan geçer.
  /// Sonuç [order] sırasındadır; izler ([decodeTombs]) buraya girmez.
  static List<Attachment> decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final seen = <String>{};
      final out = <Attachment>[];
      for (final e in list) {
        if (e is! Map || e.containsKey('x')) continue;
        final id = e['i'];
        final name = e['n'];
        final at = e['a'];
        final file = e['f'];
        final url = e['u'];
        final mime = e['m'];
        final size = e['s'];
        final changed = e['t'];
        if (id is! String || id.isEmpty || id.length > 64 || !seen.add(id)) continue;
        if (name is! String || name.length > 200 || at is! int || at < 0) continue;
        final okFile = file is String && isSafeFile(file);
        final okUrl = url is String && isSafeUrl(url);
        // Ya dosya ya bağlantı: ikisi birden ya da hiçbiri değil.
        if (okFile == okUrl || (file != null && !okFile) || (url != null && !okUrl)) continue;
        out.add(Attachment(
          id: id,
          name: name,
          addedAt: DateTime.fromMillisecondsSinceEpoch(at),
          file: okFile ? file : null,
          url: okUrl ? url : null,
          mime: mime is String && mime.length <= 100 && _safeMime.hasMatch(mime) ? mime : null,
          size: okFile && size is int && size > 0 && size <= maxBytes ? size : 0,
          changedAt: changed is int && changed >= 0 ? DateTime.fromMillisecondsSinceEpoch(changed) : null,
        ));
      }
      out.sort(order);
      // Sıralandıktan sonra kesilir: hangi eklerin kalacağı sıraya değil içeriğe bağlı.
      return out.length > maxStored ? out.sublist(0, maxStored) : out;
    } on FormatException {
      return const [];
    }
  }
}
