import 'dart:io';

import 'package:envanter/data/node.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/merge.dart';
import 'package:envanter/sync/sync_target.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter/foundation.dart';

/// Gerçek birleştirme motorunu kullanan bellek içi envanter.
class FakeInventory implements SyncTarget {
  final Map<String, Node> nodes = {};
  final Map<String, int> tombstones = {};
  final Map<String, Uint8List> files = {};
  final ValueNotifier<int> _rev = ValueNotifier(0);
  int _seq = 0;

  Node add(String name, {String? parent, NodeKind kind = NodeKind.item, String? image}) {
    final now = DateTime.now();
    final n = Node(
      id: '${name.toLowerCase()}-${_seq++}-${now.microsecondsSinceEpoch}',
      parentId: parent,
      kind: kind,
      name: name,
      color: 0xFF3F6C8C,
      sortIndex: 0,
      createdAt: now,
      updatedAt: now,
      imagePath: image,
    );
    if (image != null) files[image] = Uint8List.fromList('foto:$name'.codeUnits);
    nodes[n.id] = stampChanges(null, n, now);
    _rev.value++;
    return nodes[n.id]!;
  }

  void rename(String id, String name) {
    final now = DateTime.now();
    nodes[id] = stampChanges(nodes[id], nodes[id]!.copyWith(name: name, updatedAt: now), now);
    _rev.value++;
  }

  /// Kaydı değiştirir; zaman damgası ve yazar da güncellenir.
  void update(String id, Node Function(Node n) change, {String? by}) {
    final now = DateTime.now();
    nodes[id] = stampChanges(nodes[id], change(nodes[id]!).copyWith(updatedAt: now, updatedBy: by), now);
    _rev.value++;
  }

  void purge(String id) {
    nodes.remove(id);
    tombstones[id] = DateTime.now().millisecondsSinceEpoch;
    _rev.value++;
  }

  Node? named(String name) => nodes.values.where((n) => n.name == name).firstOrNull;

  /// Kaç kez durum istendi: eşitlemenin gerçekten konuşup konuşmadığını
  /// sınamak için.
  int snapshots = 0;

  @override
  ({Map<String, Node> nodes, Map<String, int> tombstones}) snapshot() {
    snapshots++;
    return (nodes: Map.of(nodes), tombstones: Map.of(tombstones));
  }

  @override
  String get stateStamp => stateStampOf(nodes.values, tombstones);

  /// İnceleme istenen birleştirmelerde gelen değişiklikler burada bekler.
  final List<({Map<String, Node> nodes, Map<String, int> tombstones, String? from})> reviewed = [];

  /// Yavaş cihaz taklidi: birleştirme bu kadar bekler; [merging] o an sürenlerin sayısı.
  /// Alışverişin ortasında kapanışı sınamak için.
  Duration mergeDelay = Duration.zero;
  int merging = 0;

  @override
  Future<MergeStats> mergeRemote({
    required Map<String, Node> nodes,
    required Map<String, int> tombstones,
    bool review = false,
    String? from,
  }) async {
    merging++;
    try {
      if (mergeDelay > Duration.zero) await Future<void>.delayed(mergeDelay);
      if (review) {
        reviewed.add((nodes: nodes, tombstones: tombstones, from: from));
        return MergeStats();
      }
      return await mergeNow(nodes: nodes, tombstones: tombstones);
    } finally {
      merging--;
    }
  }

  Future<MergeStats> mergeNow({
    required Map<String, Node> nodes,
    required Map<String, int> tombstones,
  }) async {
    final r = mergeInventories(
      local: Map.of(this.nodes),
      localTombstones: Map.of(this.tombstones),
      incoming: nodes,
      incomingTombstones: tombstones,
      now: DateTime.now(),
    );
    for (final id in r.removals) {
      this.nodes.remove(id);
    }
    for (final n in r.upserts) {
      this.nodes[n.id] = n;
    }
    this.tombstones
      ..clear()
      ..addAll(r.tombstones);
    return r.stats;
  }

  bool _referenced(String rel) => nodes.values.any((n) => n.imagePath == rel);

  @override
  Set<String> missingImages() => {
        for (final n in nodes.values)
          if (n.imagePath != null && !files.containsKey(n.imagePath)) n.imagePath!,
      };

  @override
  Future<Uint8List?> readImage(String rel) async => _referenced(rel) ? files[rel] : null;

  @override
  Future<bool> saveImage(String rel, Uint8List bytes) async {
    if (!_referenced(rel)) return false;
    files[rel] = bytes;
    return true;
  }

  /// Ek dosyaları gerçek dosya: ağda akışla taşınıyorlar.
  late final Directory dir = Directory.systemTemp.createTempSync('envanter_fake');

  File _file(String rel) => File('${dir.path}/${rel.replaceAll('/', '_')}');

  /// Kayda bir dosya eki koyar (içeriği diske yazılır).
  Attachment attach(String id, String rel, List<int> bytes, {String name = 'ek'}) {
    _file(rel).writeAsBytesSync(bytes);
    final a = Attachment(
      id: 'a${_seq++}',
      name: name,
      addedAt: DateTime.now(),
      file: rel,
      mime: 'application/pdf',
      size: bytes.length,
    );
    update(id, (n) => n.copyWith(attachments: [...n.attachments, a]));
    return a;
  }

  /// Ekin diskteki içeriği; yoksa null.
  List<int>? fileBytes(String rel) => _file(rel).existsSync() ? _file(rel).readAsBytesSync() : null;

  @override
  Map<String, int> missingFiles() => {
        for (final n in nodes.values)
          for (final a in n.attachments)
            if (a.file case final rel? when !_file(rel).existsSync()) rel: a.size,
      };

  @override
  File? outgoingFile(String rel) =>
      nodes.values.any((n) => n.attachments.any((a) => a.file == rel)) && _file(rel).existsSync() ? _file(rel) : null;

  @override
  File incomingFile(String rel) => File('${_file(rel).path}.part');

  @override
  Future<bool> adoptFile(String rel, File temp) async {
    final expected = missingFiles()[rel];
    if (expected == null || (expected > 0 && temp.lengthSync() != expected)) {
      if (temp.existsSync()) temp.deleteSync();
      return false;
    }
    temp.renameSync(_file(rel).path);
    return true;
  }

  @override
  int get liveRecordCount => nodes.values.where((n) => !n.isDeleted).length;

  @override
  ValueListenable<int> get localRevision => _rev;
}
