import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/inventory_store.dart';
import 'shell.dart';
import 'widgets/attachments.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/paper.dart';

/// Fotoğrafların ve eklerin bu cihazda kapladığı yer; en büyük ekler hangi
/// kayıtta. Video biriktikçe uygulamanın ve yedeğin neden büyüdüğü buradan
/// görülür, büyük ek buradan bulunup kaydından kaldırılır.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  Future<StorageUsage>? _usage;
  (int, int, int)? _measuredAt;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    // Kayıtlar değişince (bir ek kaldırıldı) yeniden ölçülür.
    final revision = (store.localRevision.value, store.visibleRecordCount, store.trash.length);
    if (_usage == null || _measuredAt != revision) {
      _measuredAt = revision;
      _usage = store.measureStorage();
    }

    return Scaffold(
      appBar: ShellHeader(
        title: s.storageTitle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: const [],
      ),
      body: FutureBuilder<StorageUsage>(
        future: _usage,
        builder: (context, snap) {
          final usage = snap.data;
          // Dönen simge yok: ölçüm kısa sürer, yazı yeter.
          if (usage == null) {
            return Center(child: Text(s.storageMeasuring, style: TextStyle(color: tones.muted)));
          }
          return ListView(
            padding: readableInsets(context, const EdgeInsets.fromLTRB(0, 0, 0, 32)),
            children: [
              PaperSection(
                children: [
                  PaperRow(
                    icon: Icons.photo_outlined,
                    title: s.storagePhotos,
                    subtitle: s.storageCount(usage.photoCount),
                    trailing: _Size(s.fileSize(usage.photoBytes)),
                  ),
                  const PaperDivider(),
                  PaperRow(
                    icon: Icons.attach_file_rounded,
                    title: s.storageFiles,
                    subtitle: s.storageCount(usage.fileCount),
                    trailing: _Size(s.fileSize(usage.fileBytes)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 0),
                child: Text(s.storageNote, style: TextStyle(fontSize: 12.5, color: tones.muted, height: 1.4)),
              ),
              if (usage.largest.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
                  child: Text(s.storageNoFiles, style: TextStyle(fontSize: 13.5, color: tones.ink, height: 1.4)),
                )
              else
                PaperSection(
                  title: s.storageLargest,
                  children: [
                    for (final (i, e) in usage.largest.indexed) ...[
                      if (i > 0) const PaperDivider(),
                      _LargeRow(entry: e),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Satırın sağındaki boyut.
class _Size extends StatelessWidget {
  const _Size(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          text,
          style: TextStyle(fontFamily: kDisplayFont, fontSize: 17, fontWeight: FontWeight.w600, color: Tones.of(context).ink),
        ),
      );
}

/// Büyük bir ek: küçük görüntüsü, adı, hangi kayıtta olduğu ve boyutu.
/// Dokununca kaydı açılır (ek oradan açılır ya da düzenleyiciden kaldırılır).
class _LargeRow extends StatelessWidget {
  const _LargeRow({required this.entry});

  final StoredAttachment entry;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    // Kayıt bu arada değişmiş olabilir; güncel halini göster.
    final node = store.byId(entry.node.id) ?? entry.node;
    final live = store.byId(node.id) != null && store.isLive(node);
    return InkWell(
      onTap: live ? () => showNodeFocus(context, node) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        child: Row(
          children: [
            AttachmentThumb(attachment: entry.attachment),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tones.ink),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      live ? '${store.nameOf(node)} · ${store.pathLabel(node.id)}' : '${store.nameOf(node)} · ${s.storageInTrash}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: tones.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Size(s.fileSize(entry.bytes)),
          ],
        ),
      ),
    );
  }
}
