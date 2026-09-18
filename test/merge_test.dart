import 'package:envanter/data/node.dart';
import 'package:envanter/sync/merge.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 18, 12);
DateTime t(int minutes) => _now.subtract(Duration(minutes: 1000 - minutes));
int ms(int minutes) => t(minutes).millisecondsSinceEpoch;

Node n(
  String id, {
  String? parent,
  NodeKind kind = NodeKind.item,
  String name = '',
  int at = 0,
  bool trashed = false,
  bool drawer = false,
  String? image,
}) =>
    Node(
      id: id,
      parentId: parent,
      kind: kind,
      name: name.isEmpty ? id : name,
      color: 0xFF000000,
      sortIndex: 0,
      createdAt: t(0),
      updatedAt: t(at),
      deletedAt: trashed ? t(at) : null,
      inDrawer: drawer,
      imagePath: image,
    );

Node box(String id, {String? parent, int at = 0}) =>
    n(id, parent: parent, kind: NodeKind.container, at: at);

MergeResult merge(
  List<Node> local,
  List<Node> incoming, {
  Map<String, int> localTomb = const {},
  Map<String, int> incomingTomb = const {},
}) =>
    mergeInventories(
      local: {for (final x in local) x.id: x},
      localTombstones: localTomb,
      incoming: {for (final x in incoming) x.id: x},
      incomingTombstones: incomingTomb,
      now: _now,
    );

Map<String, Node> apply(List<Node> local, MergeResult r) {
  final out = {for (final x in local) x.id: x};
  for (final id in r.removals) {
    out.remove(id);
  }
  for (final u in r.upserts) {
    out[u.id] = u;
  }
  return out;
}

void main() {
  group('son yazan kazanır', () {
    test('sadece karşıda olan kayıt eklenir', () {
      final r = merge([box('a')], [box('a'), n('b', parent: 'a')]);
      expect(r.upserts.map((x) => x.id), ['b']);
      expect(r.stats.added, 1);
    });

    test('karşıdaki daha yeni düzenleme yereli ezer', () {
      final r = merge([n('a', name: 'Eski', at: 1)], [n('a', name: 'Yeni', at: 2)]);
      expect(r.upserts.single.name, 'Yeni');
      expect(r.stats.updated, 1);
    });

    test('bizdeki daha yeni düzenleme korunur', () {
      final r = merge([n('a', name: 'Yeni', at: 2)], [n('a', name: 'Eski', at: 1)]);
      expect(r.upserts, isEmpty);
      expect(r.stats.keptLocal, 1);
    });

    test('aynı dosyayı iki kez almak ikincisinde hiçbir şey değiştirmez', () {
      final local = [box('a', at: 1)];
      final incoming = [box('a', at: 1), n('b', parent: 'a', at: 3)];
      final first = merge(local, incoming);
      final afterFirst = apply(local, first).values.toList();
      final second = merge(afterFirst, incoming);
      expect(second.changesAnything, isFalse);
      expect(second.stats.isEmpty, isTrue);
    });

    test('karşıda çöpe atılan kayıt bizde de çöpe gider', () {
      final r = merge([n('a', at: 1)], [n('a', at: 2, trashed: true)]);
      expect(r.upserts.single.isDeleted, isTrue);
      expect(r.stats.trashed, 1);
    });

    test('çöpten geri alma da yayılır', () {
      final r = merge([n('a', at: 1, trashed: true)], [n('a', at: 2)]);
      expect(r.upserts.single.isDeleted, isFalse);
    });

    test('taşıma yayılır', () {
      final r = merge(
        [box('x'), box('y'), n('a', parent: 'x', at: 1)],
        [box('x'), box('y'), n('a', parent: 'y', at: 2)],
      );
      expect(r.upserts.single.parentId, 'y');
    });
  });

  group('kalıcı silme izleri', () {
    test('karşının kalıcı sildiği, bizde sonradan dokunulmamış kayıt silinir', () {
      final r = merge([n('a', at: 1)], [], incomingTomb: {'a': ms(5)});
      expect(r.removals, {'a'});
      expect(r.stats.removed, 1);
    });

    test('karşı silmeden sonra bizde düzenlenmiş kayıt korunur', () {
      final r = merge([n('a', at: 9)], [], incomingTomb: {'a': ms(5)});
      expect(r.removals, isEmpty);
    });

    test('bizim kalıcı sildiğimiz eski kayıt geri gelmez', () {
      final r = merge([], [n('a', at: 1)], localTomb: {'a': ms(5)});
      expect(r.upserts, isEmpty);
      expect(r.tombstones, {'a': ms(5)});
    });

    test('silinmeden sonra karşıda düzenlenmiş kayıt geri gelir, iz temizlenir', () {
      final r = merge([], [n('a', at: 9)], localTomb: {'a': ms(5)});
      expect(r.upserts.single.id, 'a');
      expect(r.clearedTombstones, {'a'});
      expect(r.tombstones.containsKey('a'), isFalse);
    });

    test('izler birleşir, aynı kayıtta daha geç olan kalır', () {
      final r = merge([], [], localTomb: {'a': ms(3), 'b': ms(1)}, incomingTomb: {'a': ms(1), 'c': ms(2)});
      expect(r.tombstones, {'a': ms(3), 'b': ms(1), 'c': ms(2)});
    });
  });

  group('ağaç bütünlüğü', () {
    test('biz klasörü kalıcı silerken karşı içine eşya koyduysa eşya çekmeceye düşer', () {
      final r = merge(
        [],
        [box('k', at: 1), n('yeni', parent: 'k', at: 8)],
        localTomb: {'k': ms(5)},
      );
      final yeni = r.upserts.singleWhere((x) => x.id == 'yeni');
      expect(yeni.parentId, isNull);
      expect(yeni.inDrawer, isTrue);
      expect(r.stats.relocated, 1);
    });

    test('üstü eşyaya dönüşmüş kayıt çekmeceye düşer', () {
      final r = merge(
        [n('k', kind: NodeKind.item, at: 5)],
        [box('k', at: 1), n('c', parent: 'k', at: 2)],
      );
      final c = r.upserts.singleWhere((x) => x.id == 'c');
      expect(c.inDrawer, isTrue);
    });

    test('çapraz taşıma döngüsünde eski taşıma geri alınır', () {
      // Biz A'yı B'ye koyduk (dakika 3), karşı B'yi A'ya koydu (dakika 4).
      final r = merge(
        [box('a', parent: 'b', at: 3), box('b', at: 1)],
        [box('a', at: 1), box('b', parent: 'a', at: 4)],
      );
      final result = apply([box('a', parent: 'b', at: 3), box('b', at: 1)], r);
      expect(result['a']!.parentId, isNull, reason: 'eski niyet: A çekmeceye');
      expect(result['a']!.inDrawer, isTrue);
      expect(result['b']!.parentId, 'a', reason: 'yeni niyet korunur');
      expect(r.stats.relocated, 1);
    });

    test('birleşme sonucu hiçbir kayıt kendi atası olmaz', () {
      final r = merge(
        [box('a', parent: 'c', at: 5), box('b', at: 1), box('c', at: 1)],
        [box('a', at: 1), box('b', parent: 'a', at: 6), box('c', parent: 'b', at: 7)],
      );
      final result = apply([box('a', parent: 'c', at: 5), box('b', at: 1), box('c', at: 1)], r);
      for (final start in result.keys) {
        final seen = <String>{};
        String? cur = start;
        while (cur != null) {
          expect(seen.add(cur), isTrue, reason: 'döngü: $start');
          cur = result[cur]?.parentId;
        }
      }
    });
  });

  group('resimler', () {
    test('yalnızca yeni gelen ya da değişen resimler kopyalanır', () {
      final r = merge(
        [n('a', at: 1, image: 'images/a1.jpg'), n('b', at: 5, image: 'images/b.jpg')],
        [
          n('a', at: 2, image: 'images/a2.jpg'), // değişti
          n('b', at: 1, image: 'images/b-eski.jpg'), // bizdeki yeni
          n('c', at: 1, image: 'images/c.jpg'), // yeni
          n('d', at: 1), // resimsiz
        ],
      );
      expect(r.imagesToCopy, {'images/a2.jpg', 'images/c.jpg'});
    });
  });
}
