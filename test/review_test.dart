import 'package:envanter/data/node.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/review.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = DateTime.utc(2026, 9, 19, 10);
DateTime t(int m) => _base.add(Duration(minutes: m));

Node n(String id, {String? parent, String? name, int at = 0, bool trashed = false,
    NodeKind kind = NodeKind.item, String? image, String? by}) =>
    Node(
      id: id,
      parentId: parent,
      kind: kind,
      name: name ?? id,
      color: 1,
      sortIndex: 0,
      createdAt: t(0),
      updatedAt: t(at),
      deletedAt: trashed ? t(at) : null,
      imagePath: image,
      updatedBy: by,
    );

List<PendingChange> stage(List<Node> local, List<Node> incoming,
        {Map<String, int> localTomb = const {}, Map<String, int> incomingTomb = const {}}) =>
    stageIncoming(
      local: {for (final x in local) x.id: x},
      localTombstones: localTomb,
      incoming: {for (final x in incoming) x.id: x},
      incomingTombstones: incomingTomb,
      now: t(100),
    );

void main() {
  group('neyin bekleyeceği', () {
    test('yalnızca bizdekinden yeni sürümler bekler', () {
      final staged = stage(
        [n('a', at: 5), n('b', at: 5)],
        [n('a', at: 6, name: 'yeni'), n('b', at: 5), n('c', at: 1)],
      );
      expect(staged.map((c) => c.nodeId), unorderedEquals(['a', 'c']));
    });

    test('bizdeki daha yeni sürüm beklemeye alınmaz', () {
      expect(stage([n('a', at: 9)], [n('a', at: 2)]), isEmpty);
    });

    test('bizim kalıcı sildiğimiz eski kayıt beklemeye bile girmez', () {
      expect(stage([], [n('a', at: 1)], localTomb: {'a': t(5).millisecondsSinceEpoch}), isEmpty);
    });

    test('karşının kalıcı silmesi bekleyen silme olur', () {
      final staged = stage([n('a', at: 1)], [], incomingTomb: {'a': t(5).millisecondsSinceEpoch});
      expect(staged.single.isDeletion, isTrue);
    });

    test('silmeden sonra bizde düzenlenmiş kaydın silinmesi beklemez', () {
      expect(stage([n('a', at: 9)], [], incomingTomb: {'a': t(5).millisecondsSinceEpoch}), isEmpty);
    });

    test('bekleyen değişiklik kaydedilip geri okunabilir', () {
      final c = stage([], [n('a', at: 3, by: 'ayse')]).single;
      final back = PendingChange.fromJson(c.toJson())!;
      expect(back.nodeId, 'a');
      expect(back.author, 'ayse');
      expect(back.changedAt.isAtSameMomentAs(t(3)), isTrue);
    });
  });

  group('alan bazında', () {
    // Ortak başlangıç: iki tarafta da Mutfak'taki Pil.
    final pil = stampChanges(null, n('pil', parent: 'mutfak', at: 0), t(0));
    final mutfak = n('mutfak', kind: NodeKind.container);
    Node edit(Node x, Node Function(Node) change, int at, String by) =>
        stampChanges(x, change(x).copyWith(updatedAt: t(at), updatedBy: by), t(at));

    test('bizim sonradan başka alanda yaptığımız değişiklik gelenin önünü kesmez', () {
      final ours = edit(pil, (x) => x.copyWith(name: 'Kalem pil'), 9, 'ali');
      final theirs = edit(pil, (x) => x.copyWith(quantity: 4), 5, 'ayse');
      final staged = stage([mutfak, ours], [theirs]);
      final sum = describeChange(staged.single, ours);
      expect(sum.quantityChanged, isTrue);
      expect(sum.renamed, isFalse);
      expect(candidateOf(staged.single, ours)!.name, 'Kalem pil');
    });

    test('kayıp haberi sessizce, aynı sürümdeki ad değişikliği onayla gelir', () {
      final theirs = edit(
        pil,
        (x) => x.copyWith(clearParent: true, lostAt: t(5), lostFrom: 'mutfak', name: 'Pil (AA)'),
        5,
        'ayse',
      );
      final local = {'mutfak': mutfak, 'pil': pil};
      final quiet = quietIncoming(local: local, incoming: {'pil': theirs});
      expect(quiet['pil']!.isLost, isTrue);
      expect(quiet['pil']!.name, 'pil', reason: 'ad onay bekler');

      final afterQuiet = mergeNode(pil, quiet['pil']!);
      final staged = stage([mutfak, afterQuiet], [theirs]);
      final sum = describeChange(staged.single, afterQuiet);
      expect(sum.renamed, isTrue);
      expect(sum.kind, ChangeKind.edited, reason: 'kayıp kısmı zaten alındı');
      // Beklemeden önce hesaplansa da aynı sonuç: kayıp kısmı sessiz sayılır.
      expect(describeChange(stage([mutfak, pil], [theirs]).single, afterQuiet).renamed, isTrue);
    });

    test('yalnızca zamanları ilerleyen sürüm beklemez, sessizce alınır', () {
      final same = bumpFields(pil, [NodeField.note], t(7), by: 'ayse');
      expect(stage([mutfak, pil], [same]), isEmpty);
      expect(quietIncoming(local: {'pil': pil}, incoming: {'pil': same}).keys, ['pil']);
      // Aynısı yeniden gelirse artık alınacak bir şey yok.
      final taken = mergeNode(pil, same);
      expect(quietIncoming(local: {'pil': taken}, incoming: {'pil': same}), isEmpty);
    });
  });

  group('değişikliğin tarifi', () {
    ChangeSummary d(Node? local, Node? incoming, {int? purgedAt}) => describeChange(
          PendingChange(nodeId: 'a', incoming: incoming, purgedAt: purgedAt, receivedAt: t(0)),
          local,
        );

    test('eklendi', () => expect(d(null, n('a')).kind, ChangeKind.added));
    test('taşındı', () {
      final s = d(n('a', parent: 'x'), n('a', parent: 'y', at: 2));
      expect(s.kind, ChangeKind.moved);
      expect(s.moved, isTrue);
    });
    test('adı değişti', () {
      final s = d(n('a', name: 'Tencere'), n('a', name: 'Düdüklü', at: 2));
      expect(s.kind, ChangeKind.edited);
      expect(s.renamed, isTrue);
      expect(s.oldName, 'Tencere');
      expect(s.newName, 'Düdüklü');
    });
    test('çöpe atıldı', () => expect(d(n('a'), n('a', trashed: true, at: 2)).kind, ChangeKind.trashed));
    test('geri getirildi', () => expect(d(n('a', trashed: true), n('a', at: 2)).kind, ChangeKind.restored));
    test('kalıcı silindi', () => expect(d(n('a'), null, purgedAt: 5).kind, ChangeKind.deleted));
    test('hem taşınıp hem adı değişince ikisi de görünür', () {
      final s = d(n('a', parent: 'x', name: 'Eski'), n('a', parent: 'y', name: 'Yeni', at: 2));
      expect(s.kind, ChangeKind.moved);
      expect(s.renamed, isTrue);
    });
  });

  group('bağımlılıklar', () {
    Map<String, PendingChange> pend(List<Node> nodes) => {
          for (final x in nodes)
            x.id: PendingChange(nodeId: x.id, incoming: x, purgedAt: null, receivedAt: t(0)),
        };

    test('yeni bir klasörün içindeki eşyayı kabul edince klasör de gelir', () {
      final pending = pend([
        n('kutu', kind: NodeKind.container),
        n('ic', parent: 'raf', kind: NodeKind.container),
        n('esya', parent: 'ic'),
      ]);
      // 'raf' bizde yok ve beklemede de değil: zinciri orada durur.
      pending['ic'] = PendingChange(nodeId: 'ic', incoming: n('ic', parent: 'kutu', kind: NodeKind.container), purgedAt: null, receivedAt: t(0));
      final extra = pendingAncestors(accepting: {'esya'}, local: const {}, pending: pending);
      expect(extra, {'ic', 'kutu'});
    });

    test('bizde olan üst klasör için ek kabul gerekmez', () {
      final pending = pend([n('esya', parent: 'mutfak')]);
      final extra = pendingAncestors(
        accepting: {'esya'},
        local: {'mutfak': n('mutfak', kind: NodeKind.container)},
        pending: pending,
      );
      expect(extra, isEmpty);
    });

    test('reddedilen yeni klasörün içine eklenenler de reddedilir', () {
      final pending = pend([
        n('kutu', kind: NodeKind.container),
        n('ic', parent: 'kutu', kind: NodeKind.container),
        n('esya', parent: 'ic'),
        n('baska'),
      ]);
      expect(pendingDescendants(rejecting: {'kutu'}, pending: pending), {'ic', 'esya'});
    });
  });
}
