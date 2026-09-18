import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Klasör bir yere bırakıldığında "yalnızca içindekiler" seçilirse: içindekiler
/// gider, klasör boş olarak yerinde kalır.
void main() {
  late InventoryStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.openForTest();
    store = InventoryStore()..authorId = 'ben';
    await store.init();
  });

  tearDown(() => AppDatabase.instance.close());

  Future<Node> add(String name, {required String parent, NodeKind kind = NodeKind.item}) async {
    final n = store.draft(parentId: parent, kind: kind).copyWith(name: name);
    await store.commit(n);
    return n;
  }

  test('içindekiler aktarılır, klasör boş olarak yerinde kalır', () async {
    final depo = await add('Depo', parent: Roots.home, kind: NodeKind.container);
    final kutu = await add('Kutu', parent: Roots.home, kind: NodeKind.container);
    final tuz = await add('Tuz', parent: kutu.id);
    final biber = await add('Biber', parent: kutu.id);

    expect(store.canTransferContents(kutu.id, depo.id), isTrue);
    expect(await store.moveContents(kutu.id, depo.id), 2);

    expect(store.childrenOf(depo.id).map((n) => n.name), ['Tuz', 'Biber'], reason: 'sıra korunur');
    expect(store.byId(tuz.id)!.parentId, depo.id);
    expect(store.byId(biber.id)!.parentId, depo.id);
    expect(store.childrenOf(kutu.id), isEmpty);
    expect(store.byId(kutu.id)!.parentId, isNull, reason: 'klasör ana ekranda kaldı');
  });

  test('içindekiler hedefin sonuna eklenir', () async {
    final depo = await add('Depo', parent: Roots.home, kind: NodeKind.container);
    await add('Bir', parent: depo.id);
    final kutu = await add('Kutu', parent: Roots.home, kind: NodeKind.container);
    await add('İki', parent: kutu.id);

    expect(await store.moveContents(kutu.id, depo.id), 1);
    expect(store.childrenOf(depo.id).map((n) => n.name), ['Bir', 'İki']);
  });

  test('boş klasörde aktaracak bir şey yok', () async {
    final depo = await add('Depo', parent: Roots.home, kind: NodeKind.container);
    final bos = await add('Boş', parent: Roots.home, kind: NodeKind.container);

    expect(store.canTransferContents(bos.id, depo.id), isFalse);
    expect(await store.moveContents(bos.id, depo.id), 0);
  });

  test('kendi içine aktarma olmaz', () async {
    final dis = await add('Dış', parent: Roots.home, kind: NodeKind.container);
    final ic = await add('İç', parent: dis.id, kind: NodeKind.container);
    await add('Eşya', parent: dis.id);

    expect(store.canTransferContents(dis.id, ic.id), isFalse);
    expect(await store.moveContents(dis.id, ic.id), 0);
    expect(store.canTransferContents(dis.id, dis.id), isFalse);
  });

  test('içindekiler çekmeceye de aktarılabilir', () async {
    final kutu = await add('Kutu', parent: Roots.home, kind: NodeKind.container);
    final pil = await add('Pil', parent: kutu.id);

    expect(await store.moveContents(kutu.id, Roots.drawer), 1);
    final moved = store.byId(pil.id)!;
    expect(moved.parentId, isNull);
    expect(moved.inDrawer, isTrue);
    expect(store.childrenOf(Roots.drawer).map((n) => n.id), [pil.id]);
    expect(store.childrenOf(kutu.id), isEmpty);
  });

  test('kayıp çekmecesine toplu aktarma yok', () async {
    final kutu = await add('Kutu', parent: Roots.home, kind: NodeKind.container);
    await add('Pil', parent: kutu.id);

    expect(store.canTransferContents(kutu.id, Roots.lost), isFalse);
    expect(await store.moveContents(kutu.id, Roots.lost), 0);
  });

  test('eşya aktarılacak bir şey değil', () async {
    final depo = await add('Depo', parent: Roots.home, kind: NodeKind.container);
    final esya = await add('Kalem', parent: Roots.home);

    expect(store.canTransferContents(esya.id, depo.id), isFalse);
  });
}
