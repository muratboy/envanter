import 'dart:async';
import 'dart:convert';

import '../core/time_span.dart';
import '../data/library.dart';
import '../data/node.dart';
import '../state/inventory_store.dart';
import 'platform_bridge.dart';

/// Ana ekrandaki alışveriş listesi widget'ı. Widget'ı Android çizer (uygulama
/// kapalıyken de durur, `ShoppingWidget.kt`); veriyi uygulama verir: mağaza her
/// değiştiğinde liste yeniden hesaplanır, değiştiyse yerel tarafa yazılır.
class ShoppingWidgetSync {
  ShoppingWidgetSync._();

  static final instance = ShoppingWidgetSync._();

  InventoryStore? _store;
  String? _last;
  bool _scheduled = false;

  /// Açılışta bir kez. Yerel taraf yoksa (testler) dinlemeyi bırakır.
  Future<void> attach(InventoryStore store) async {
    if (identical(store, _store)) return;
    _store?.removeListener(_changed);
    _store = store;
    _last = null;
    store.addListener(_changed);
    if (await push() == null) {
      store.removeListener(_changed);
      _store = null;
    }
  }

  /// Aynı anda gelen değişiklikler (eşitlemede yüzlerce kayıt) tek hesapta
  /// toplanır. Zamanlayıcı değil mikro görev: bekleyen zamanlayıcı widget
  /// testlerini düşürürdü, bir sonraki kareyi beklemeye de gerek yok.
  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(push());
    });
  }

  /// Listeyi yazar; değişmediyse dokunmaz. Yerel taraf yoksa null.
  Future<bool?> push() async {
    final store = _store;
    if (store == null) return false;
    if (store.loading) return true;
    final payload = shoppingWidgetPayload(store, today: DateTime.now());
    if (payload == _last) return true;
    final ok = await PlatformBridge.updateShoppingWidget(payload);
    if (ok == true) _last = payload;
    return ok;
  }
}

/// Tarihi geçecekler için ne kadar ileri bakılır: uygulama bu kadar gün
/// açılmasa da widget listeyi gün gün kendisi tazeleyebilir.
const widgetLookAhead = 90;

/// Widget'a giden veri (JSON): uygulamadaki alışveriş listesinin aynısı
/// ([InventoryStore.shoppingItems]). "Listeye kendiliğinden ekle" ayarı açık
/// eşyalardan tarihi ileride geçecekler de "şu günden itibaren" (`from`, son
/// günün ertesi) diye gelir; widget o gün gelince gösterir, yani sütün tarihi
/// gece geçince uygulama açılmadan da listeye girer.
/// Metinler burada, uygulamanın dilinde hazırlanır; yerel taraf yalnızca
/// süzer ve çizer. Aynı eşya iki kez gelirse widget ilk görünen satırı alır.
String shoppingWidgetPayload(InventoryStore store, {required DateTime today}) {
  final s = store.strings;
  final day = dateOnly(today);
  Map<String, Object?> row(Node n) => {
        'id': n.id,
        'name': store.nameOf(n),
        'note': store.shoppingNote(n, day),
        'kind': store.shoppingReason(n, day)?.name ?? 'wanted',
      };

  final listed = store.shoppingItems;
  final ids = {for (final n in listed) n.id};
  final items = [
    for (final n in listed) row(n),
    for (final n in store.expiringBy(DateTime(day.year, day.month, day.day + widgetLookAhead)))
      if (n.autoShop && !ids.contains(n.id))
        {
          'id': n.id,
          'name': store.nameOf(n),
          'note': s.pastDateNote,
          'kind': 'expired',
          'from': _isoDay(n.lastExpiry!, plusDays: 1),
        },
  ];
  // Öteki envanterlerin listesi de (kapanırken saklanan): Ev ile Yazlık'ı
  // birlikte kullanan tek listede görsün. Hangi envanterden olduğu notta.
  final library = InventoryLibrary.current;
  final others = [
    if (library != null)
      for (final e in library.entries)
        if (e.id != library.activeId)
          for (final x in e.shopping)
            {
              'id': '${e.id}/${x.id}',
              'name': x.name,
              'note': [library.nameOf(e, s.appTitle), if (x.note.isNotEmpty) x.note].join(' · '),
              'kind': x.kind,
            },
  ];
  // Birden çok envanter varken başlıkta açık olanın adı; öteki listeler de
  // katıldıysa yalnızca "Alışveriş listesi".
  final label = others.isEmpty ? library?.labelFor(s.appTitle) : null;
  return jsonEncode({
    'title': label == null ? s.shoppingList : '${s.shoppingList} · $label',
    'empty': s.shoppingEmpty,
    'items': [...items, ...others],
  });
}

/// "2026-09-28": yerel tarafta metin olarak karşılaştırılır.
String _isoDay(DateTime d, {int plusDays = 0}) {
  final x = DateTime(d.year, d.month, d.day + plusDays);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${x.year.toString().padLeft(4, '0')}-${two(x.month)}-${two(x.day)}';
}
