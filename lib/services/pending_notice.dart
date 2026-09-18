import 'dart:convert';

import '../core/strings.dart';
import '../data/library.dart';
import '../state/inventory_store.dart';
import 'date_notifier.dart';

/// Kullanıcı bakmıyorken onay bekleyen yeni bir değişiklik gelirse telefon bildirimi.
///
/// Evde değişiklikler çoğu zaman uygulama kapalıyken, arka plan eşitlemesiyle gelir; onay
/// bekleyen değişiklik ise onaylanana kadar hiçbir cihazda geçerli olmaz. Envanter
/// listesindeki işareti görmek için uygulamayı açmak gerekiyordu.
///
/// "Yeni" = kullanıcının uygulamadan son çıktığı andaki sayıdan fazlası. O sayı kütüphanede
/// durur ([seenKey]): arka plan motoru her seferinde baştan kurulduğu için bellekte tutulsa
/// aynı değişiklik yarım saatte bir yeniden bildirilirdi.
abstract final class PendingNotice {
  /// Kütüphanedeki (`global`) anahtar: envanter kimliği → görülen sayı (JSON). Ayar değil,
  /// `AppSettings.globalKeys`'e girmez.
  static const seenKey = 'pending_seen';

  /// Onay bekleyenler: envanter kimliği → sayı (yalnızca sıfırdan büyükler). Açık envanterde
  /// mağazanın o anki sayısı, kapalılarda son kapanışta ya da ziyarette yazılan özet.
  static Map<String, int> counts(InventoryLibrary library, InventoryStore open) => {
        for (final e in library.entries)
          if ((e.id == library.activeId ? open.pendingCount : e.pending) > 0)
            e.id: e.id == library.activeId ? open.pendingCount : e.pending,
      };

  static Map<String, int> seen(InventoryLibrary library) {
    try {
      final json = jsonDecode(library.global[seenKey] ?? '{}');
      return {
        if (json is Map)
          for (final e in json.entries)
            if (e.key is String && e.value is int) e.key as String: e.value as int,
      };
    } on FormatException {
      return {};
    }
  }

  /// Kullanıcı uygulamadan çıkıyor: o anda bekleyenleri arayüzde görmüş sayılır.
  static Future<void> markSeen(InventoryLibrary library, InventoryStore open) =>
      library.writeGlobals({seenKey: jsonEncode(counts(library, open))});

  /// Arka plan eşitlemesinden sonra: bir envanterde bekleyenler arttıysa bildirir. Sayılar
  /// her durumda yazılır (azalan da): üç değişiklik onaylanıp sonra bir yenisi gelirse o da
  /// "yeni"dir. Bildirim gösterildiyse true.
  static Future<bool> check(
    InventoryLibrary library,
    InventoryStore open, {
    Future<void> Function(PendingText text)? show,
  }) async {
    final now = counts(library, open);
    final before = seen(library);
    await library.writeGlobals({seenKey: jsonEncode(now)});
    final grew = now.entries.any((e) => e.value > (before[e.key] ?? 0));
    if (!grew || !open.settings.notifyPending) return false;
    final s = open.strings;
    final text = compose(s, library, now);
    await (show ?? (t) => DateNotifier.instance.pendingChanges(s, title: t.title, body: t.body, inventoryId: t.inventoryId))(
      text,
    );
    return true;
  }

  /// Bildirimin metni. Tek envanterde başlık envanterin adı ve dokununca o envanter açılır;
  /// birkaç envanterde hepsi alt alta, dokununca envanter listesi.
  static PendingText compose(AppStrings s, InventoryLibrary library, Map<String, int> now) {
    final rows = [
      for (final e in library.entries)
        if (now[e.id] case final count?) (id: e.id, name: library.nameOf(e, s.appTitle), count: count),
    ];
    if (rows.length == 1) {
      final only = rows.single;
      return PendingText(title: only.name, body: s.pendingInInventory(only.count), inventoryId: only.id);
    }
    return PendingText(
      title: s.pendingNoticeTitle,
      body: [for (final r in rows) '${r.name}: ${s.pendingInInventory(r.count)}'].join('\n'),
    );
  }
}

class PendingText {
  const PendingText({required this.title, required this.body, this.inventoryId});

  final String title;
  final String body;

  /// Tek envanterse kimliği: bildirime dokununca o envanterin değişiklikleri açılır.
  final String? inventoryId;
}
