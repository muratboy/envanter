import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/database.dart';
import 'wire.dart';

/// Bu cihazın ortak kullanım ayarları.
///
/// Her cihaz başlangıçta kendi envanterinin sahibidir (kendi kimliği ve
/// anahtarı). Başka birinin envanterine katılınca o envanterin kimliğini ve
/// anahtarını alır, sahiplik karşıda kalır.
class SharingConfig {
  const SharingConfig({
    required this.enabled,
    required this.deviceId,
    required this.inventoryId,
    required this.inventoryName,
    required this.ownerDeviceId,
    required this.key,
    required this.members,
    this.removed = const {},
    this.ownerAt = 0,
    this.heirDeviceId,
    this.heirAt = 0,
    this.lastSyncAt,
    this.autoAccept = false,
    this.trusted = const {},
    this.quickSmall = true,
    this.syncedWith = const {},
    this.notices = const [],
    this.seenNotices = const {},
  });

  /// Varsayılan kapalı; açılınca cihaz ağda görünür ve eşitler.
  final bool enabled;
  final String deviceId;
  final String inventoryId;

  /// Ağda görünen ad. Boşsa kullanıcı adı kullanılır.
  final String inventoryName;
  /// Yönetici: envanteri kuran ya da yöneticiliği devralan. [ownerAt] devrin
  /// anı (kurucuda 0); cihazlar arasında en yeni devir geçerli.
  final String ownerDeviceId;
  final int ownerAt;

  /// Varis: yönetici ayrılır ya da envanteri silerse yönetici olur; o zamana
  /// dek ana kullanıcı yetkileri var ama kendisi varis seçemez. Yöneticiliği
  /// devreden kişi otomatik olarak yeni yöneticinin varisi olur.
  final String? heirDeviceId;
  final int heirAt;
  final List<int> key;
  final List<Member> members;

  /// Çıkarılan ya da kendi isteğiyle ayrılan cihazların izi (kimlik → an, ms).
  /// Üyeler gibi cihazlar arasında birleşir; iz olmasa, üyeyi henüz silmemiş
  /// bir cihaz onu listeye geri getirirdi. İzden sonra yeniden kabul edilen
  /// cihaz ([Member.joinedAt] daha yeni) yine üyedir.
  final Map<String, int> removed;
  final DateTime? lastSyncAt;

  /// Karşıdan gelen değişiklikler sormadan hemen uygulansın. Varsayılan
  /// kapalı: değişiklikler bildirim olarak bekler, kullanıcı onaylar.
  final bool autoAccept;

  /// Değişiklikleri sormadan gelen üyeler (bu cihazın kararı, eşitlenmez):
  /// "Ayşe'ninkiler sormadan gelsin". Kalıcı ve toplu silmeler yine sorulur.
  final Set<String> trusted;

  /// Adet ve alışveriş listesi değişiklikleri sormadan gelsin (onaylı modda);
  /// her birini onaylamak yoruyor, sonunda "hepsini kabul et"e basılıyordu.
  final bool quickSmall;

  /// Her üyeyle en son eşitlenme anı (ms): "Ayşe'yle 3 gün önce eşitlendi".
  final Map<String, int> syncedWith;

  /// Geri çevrilen değişikliklerin haberleri: herkese yayılır, damgaya girer.
  final List<Notice> notices;

  /// Bu cihaza gelip gösterilmiş haberler (yeniden gösterilmesin; cihaza özel).
  final Set<String> seenNotices;

  bool get isOwner => ownerDeviceId == deviceId;

  /// Geçerli varis (ayrılmış ya da çıkarılmışsa yok).
  String? get heir => heirDeviceId != null && isMember(heirDeviceId) ? heirDeviceId : null;

  bool get isHeir => heir == deviceId;

  Governance get governance =>
      Governance(owner: ownerDeviceId, ownerAt: ownerAt, heir: heirDeviceId, heirAt: heirAt);

  SharingConfig withGovernance(Governance g) => SharingConfig(
        enabled: enabled,
        deviceId: deviceId,
        inventoryId: inventoryId,
        inventoryName: inventoryName,
        ownerDeviceId: g.owner,
        ownerAt: g.ownerAt,
        heirDeviceId: g.heir,
        heirAt: g.heirAt,
        key: key,
        members: members,
        removed: removed,
        lastSyncAt: lastSyncAt,
        autoAccept: autoAccept,
        trusted: trusted,
        quickSmall: quickSmall,
        syncedWith: syncedWith,
        notices: notices,
        seenNotices: seenNotices,
      );

  /// Yönetici, varis ya da yetki verilmiş ana kullanıcı. Yönetici de ancak
  /// üyeyken: ortak kullanımdan ayrılan yöneticinin yetkisi kalmaz.
  bool isAdminDevice(String? id) =>
      id != null &&
      members.any((m) => m.deviceId == id && (m.admin || id == ownerDeviceId || id == heirDeviceId));

  bool get isAdmin => isAdminDevice(deviceId);

  /// Bu cihaz ortak envanterin bilinen bir üyesi mi. Duyurular imzasız
  /// olduğu için ağdaki herkes envanter kimliğini görebilir; durumumuzu
  /// yalnızca kabul edilmiş üyelere veririz.
  bool isMember(String? id) => id != null && members.any((m) => m.deviceId == id);

  /// Çıkarılmış ya da ayrılmış (ve yeniden kabul edilmemiş) cihaz: isteklerine
  /// yanıt verilmez, kendisi de bunu öğrenince ortak kullanımdan düşer.
  bool isRemovedDevice(String? id) => id != null && removed.containsKey(id) && !isMember(id);

  /// Kendisi dışında en az bir üye var.
  bool get isShared => members.any((m) => m.deviceId != deviceId);

  static const _uuid = Uuid();

  /// Kendi envanterinin sahibi olan, kimseyle paylaşmayan cihaz.
  static SharingConfig fresh({
    String? deviceId,
    String inventoryName = '',
    bool enabled = false,
    bool autoAccept = false,
  }) {
    final id = deviceId ?? _uuid.v4();
    return SharingConfig(
      enabled: enabled,
      deviceId: id,
      inventoryId: _uuid.v4(),
      inventoryName: inventoryName,
      ownerDeviceId: id,
      key: RequestSigner.newKey(),
      members: [Member(deviceId: id, name: '')],
      autoAccept: autoAccept,
    );
  }

  SharingConfig copyWith({
    bool? enabled,
    String? inventoryId,
    String? inventoryName,
    String? ownerDeviceId,
    List<int>? key,
    List<Member>? members,
    Map<String, int>? removed,
    DateTime? lastSyncAt,
    bool? autoAccept,
    Set<String>? trusted,
    bool? quickSmall,
    Map<String, int>? syncedWith,
    List<Notice>? notices,
    Set<String>? seenNotices,
  }) =>
      SharingConfig(
        enabled: enabled ?? this.enabled,
        deviceId: deviceId,
        inventoryId: inventoryId ?? this.inventoryId,
        inventoryName: inventoryName ?? this.inventoryName,
        ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
        ownerAt: ownerAt,
        heirDeviceId: heirDeviceId,
        heirAt: heirAt,
        key: key ?? this.key,
        members: members ?? this.members,
        removed: removed ?? this.removed,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        autoAccept: autoAccept ?? this.autoAccept,
        trusted: trusted ?? this.trusted,
        quickSmall: quickSmall ?? this.quickSmall,
        syncedWith: syncedWith ?? this.syncedWith,
        notices: notices ?? this.notices,
        seenNotices: seenNotices ?? this.seenNotices,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'deviceId': deviceId,
        'inventoryId': inventoryId,
        'inventoryName': inventoryName,
        'ownerDeviceId': ownerDeviceId,
        'ownerAt': ownerAt,
        if (heirDeviceId != null) 'heirDeviceId': heirDeviceId,
        'heirAt': heirAt,
        'key': base64Encode(key),
        'members': [for (final m in members) m.toJson()],
        'removed': removed,
        'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
        'autoAccept': autoAccept,
        if (trusted.isNotEmpty) 'trusted': [...trusted],
        if (!quickSmall) 'quickSmall': false,
        if (syncedWith.isNotEmpty) 'syncedWith': syncedWith,
        if (notices.isNotEmpty) 'notices': [for (final n in notices) n.toJson()],
        if (seenNotices.isNotEmpty) 'seenNotices': [...seenNotices],
      };

  static SharingConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final deviceId = json['deviceId'];
    final inventoryId = json['inventoryId'];
    final owner = json['ownerDeviceId'];
    final key = json['key'];
    if (deviceId is! String || inventoryId is! String || owner is! String || key is! String) {
      return null;
    }
    final rawMembers = json['members'];
    final last = json['lastSyncAt'];
    try {
      return SharingConfig(
        enabled: json['enabled'] == true,
        deviceId: deviceId,
        inventoryId: inventoryId,
        inventoryName: json['inventoryName'] is String ? json['inventoryName'] as String : '',
        ownerDeviceId: owner,
        ownerAt: json['ownerAt'] is int ? json['ownerAt'] as int : 0,
        heirDeviceId: json['heirDeviceId'] is String ? json['heirDeviceId'] as String : null,
        heirAt: json['heirAt'] is int ? json['heirAt'] as int : 0,
        key: base64Decode(key),
        members: [
          if (rawMembers is List)
            for (final m in rawMembers) ?Member.fromJson(m),
        ],
        removed: removedFromJson(json['removed']),
        lastSyncAt: last is int ? DateTime.fromMillisecondsSinceEpoch(last) : null,
        autoAccept: json['autoAccept'] == true,
        trusted: {
          if (json['trusted'] is List)
            for (final id in json['trusted'] as List)
              if (id is String) id,
        },
        quickSmall: json['quickSmall'] != false,
        syncedWith: removedFromJson(json['syncedWith']),
        notices: noticesFromJson(json['notices']),
        seenNotices: {
          if (json['seenNotices'] is List)
            for (final id in json['seenNotices'] as List)
              if (id is String) id,
        },
      );
    } on FormatException {
      return null;
    }
  }
}

abstract interface class SharingConfigStore {
  Future<SharingConfig?> load();
  Future<void> save(SharingConfig config);
}

/// Uygulamada: veritabanının meta tablosu.
class MetaSharingConfigStore implements SharingConfigStore {
  static const _key = 'sharing';

  @override
  Future<SharingConfig?> load() async {
    final text = await AppDatabase.instance.readMeta(_key);
    if (text == null) return null;
    try {
      return SharingConfig.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(SharingConfig config) =>
      AppDatabase.instance.writeMeta(_key, jsonEncode(config.toJson()));
}

/// Testler için.
class MemorySharingConfigStore implements SharingConfigStore {
  SharingConfig? value;

  @override
  Future<SharingConfig?> load() async => value;

  @override
  Future<void> save(SharingConfig config) async => value = config;
}
