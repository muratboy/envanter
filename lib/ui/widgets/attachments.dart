import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_paths.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/transitions.dart';
import '../../data/node.dart';
import '../../services/attachment_service.dart';
import '../../services/platform_bridge.dart';
import '../sharing/sharing_scope.dart';
import 'photo_viewer.dart';
import 'text_prompt.dart';

/// Ekin türüne göre simge.
IconData attachmentIcon(Attachment a) => switch (a.kind) {
      AttachmentKind.link => Icons.link_rounded,
      AttachmentKind.photo => Icons.image_outlined,
      AttachmentKind.video => Icons.play_circle_outline_rounded,
      AttachmentKind.document =>
        a.mime == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined,
    };

/// Ekin adının altındaki satır: "PDF · 3,2 MB", "Video · 48 MB", "youtube.com".
/// Dosya bu cihaza henüz inmediyse onu söyler; iniyorsa ([downloading]) yüzdesini.
String attachmentDetail(AppStrings s, Attachment a, {int? downloading}) {
  if (a.isLink) return a.host;
  final kind = switch (a.kind) {
    AttachmentKind.photo => s.attachmentPhoto,
    AttachmentKind.video => s.attachmentVideo,
    _ => a.extension.isEmpty ? s.attachmentDocument : a.extension,
  };
  return [
    kind,
    if (a.size > 0) s.fileSize(a.size),
    if (AppPaths.imageFile(a.file) == null)
      downloading == null ? s.attachmentNotHereShort : s.attachmentDownloading(downloading),
  ].join(' · ');
}

/// Ek karşı cihazdan iniyorsa yüzdesini verir (inmiyorsa ya da zaten buradaysa
/// null). Yalnızca eki gösteren yer dinler: ilerleme her yüzdede değişir,
/// bütün ekranın yeniden kurulmasına değmez.
class AttachmentProgress extends StatelessWidget {
  const AttachmentProgress({super.key, required this.attachment, required this.builder});

  final Attachment attachment;
  final Widget Function(BuildContext context, int? percent) builder;

  @override
  Widget build(BuildContext context) {
    final rel = attachment.file;
    final service = context.getInheritedWidgetOfExactType<SharingScope>()?.notifier;
    if (rel == null || service == null || AppPaths.imageFile(rel) != null) return builder(context, null);
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: service.fileProgress,
      builder: (context, progress, _) => builder(context, progress[rel]),
    );
  }
}

/// Eki açar: fotoğraf uygulamanın içinde büyür; belge ve video telefonda o
/// türü açan uygulamada, bağlantı tarayıcıda açılır.
Future<void> openAttachment(BuildContext context, Attachment a) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  if (a.url case final url?) {
    if (!await PlatformBridge.openUrl(url)) say(s.cannotOpenLink);
    return;
  }
  final file = AppPaths.imageFile(a.file);
  if (file == null) return say(s.attachmentNotHere);
  if (a.kind == AttachmentKind.photo) {
    await showPhoto(context, file, title: a.name);
    return;
  }
  // Açan uygulamanın başlığında ekin adı görünsün (uzantısıyla: türü oradan anlayan var).
  final shown = a.extension.isEmpty ? a.name : '${a.name}.${a.extension.toLowerCase()}';
  if (!await PlatformBridge.openFile(file.path, a.mime, name: shown)) say(s.noAppToOpen);
}

/// Eki başka bir uygulamaya gönderir (dosyayı ya da bağlantının adresini).
Future<void> shareAttachment(BuildContext context, Attachment a) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (a.url case final url?) {
    await SharePlus.instance.share(ShareParams(text: url, subject: a.name));
    return;
  }
  final file = AppPaths.imageFile(a.file);
  if (file == null) {
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentNotHere)));
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: a.mime, name: a.name)]));
}

/// "Ek ekle": nereden ekleneceği sorulur, seçilen dosyalar envanterin klasörüne
/// alınır. Eklenenleri döner (dosyaları diskte, henüz hiçbir kayda yazılmadı);
/// vazgeçilirse boş liste. [existing]: kayıttaki ekler (sınır ve ad çakışması için).
Future<List<Attachment>> pickAttachments(BuildContext context, {required List<Attachment> existing}) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (existing.length >= Attachment.maxCount) {
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentLimit)));
    return const [];
  }
  final choice = await showAppSheet<String>(context, (context) {
    Widget option(String value, IconData icon, String title, [String? subtitle]) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () => Navigator.of(context).pop(value),
        );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            option('document', Icons.description_outlined, s.attachDocument, s.attachDocumentHint),
            option('photo', Icons.photo_camera_rounded, s.takePhoto),
            option('video', Icons.videocam_rounded, s.attachRecordVideo),
            option('gallery', Icons.photo_library_rounded, s.attachFromGallery),
            option('link', Icons.link_rounded, s.attachLink, s.attachLinkHint),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  });
  if (choice == null || !context.mounted) return const [];

  if (choice == 'link') {
    final link = await _askLink(context);
    return [?link];
  }

  final AttachmentPick pick;
  try {
    pick = switch (choice) {
      'document' => await AttachmentService.documents(),
      'photo' => await AttachmentService.takePhoto(s.attachmentPhoto),
      'video' => await AttachmentService.recordVideo(s.attachmentVideo),
      _ => await AttachmentService.fromGallery(photo: s.attachmentPhoto, video: s.attachmentVideo),
    };
  } on Exception {
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentFailed)));
    return const [];
  }
  if (pick.tooLarge.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentTooLarge(pick.tooLarge.map((n) => '"$n"').join(', ')))));
  } else if (pick.failed > 0) {
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentFailed)));
  }

  // Sınırı aşanlar alınmaz; dosyaları da diskte kalmasın.
  final room = Attachment.maxCount - existing.length;
  if (pick.added.length > room) {
    for (final a in pick.added.skip(room)) {
      try {
        AppPaths.imageFile(a.file)?.deleteSync();
      } on FileSystemException {
        // Zaten yoksa sorun değil.
      }
      AppPaths.forget(a.file);
    }
    messenger.showSnackBar(SnackBar(content: Text(s.attachmentLimit)));
  }
  // "Fotoğraf", "Fotoğraf 2", "Fotoğraf 3": aynı adlı ekler ayırt edilsin.
  final taken = {for (final a in existing) a.name};
  return [
    for (final a in pick.added.take(room)) a.renamed(_unique(a.name, taken)),
  ];
}

String _unique(String name, Set<String> taken) {
  var candidate = name;
  for (var i = 2; taken.contains(candidate); i++) {
    candidate = '$name $i';
  }
  taken.add(candidate);
  return candidate;
}

Future<Attachment?> _askLink(BuildContext context) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final values = await showTextPrompt(
    context,
    title: s.attachLink,
    fields: [
      PromptField(
        label: s.linkAddress,
        hint: 'youtube.com/…',
        keyboardType: TextInputType.url,
        capitalization: TextCapitalization.none,
      ),
      PromptField(label: s.linkTitleOptional),
    ],
    cancelLabel: s.cancel,
    confirmLabel: s.save,
  );
  if (values == null) return null;
  final link = AttachmentService.link(values[0], values[1]);
  if (link == null) messenger.showSnackBar(SnackBar(content: Text(s.linkInvalid)));
  return link;
}

/// Ekin adını sorar; vazgeçilirse ya da boş bırakılırsa null.
Future<String?> askAttachmentName(BuildContext context, Attachment a) async {
  final s = AppStrings.of(context);
  final values = await showTextPrompt(
    context,
    title: s.renameAttachment,
    fields: [PromptField(label: s.attachmentName, initial: a.name, selectAll: true)],
    cancelLabel: s.cancel,
    confirmLabel: s.save,
  );
  final name = values?.single.trim() ?? '';
  return name.isEmpty ? null : (name.length > 120 ? name.substring(0, 120) : name);
}

/// Ekin küçük görüntüsü: fotoğrafın kendisi, videonun bir karesi, PDF'in ilk
/// sayfası; yoksa türün simgesi.
class AttachmentThumb extends StatefulWidget {
  const AttachmentThumb({super.key, required this.attachment, this.size = 44});

  final Attachment attachment;
  final double size;

  @override
  State<AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<AttachmentThumb> {
  Future<File?>? _thumb;
  String? _loadedFor;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final a = widget.attachment;
    final here = a.isLink || AppPaths.imageFile(a.file) != null;
    // Dosya sonradan inebilir (ortak kullanım): gelince küçük resim de yüklensin.
    final key = here ? a.file : null;
    if (key != _loadedFor) {
      _loadedFor = key;
      _thumb = key == null ? null : AttachmentService.thumbnailOf(a);
    }
    final size = widget.size;
    final icon = Icon(
      here ? attachmentIcon(a) : Icons.cloud_download_outlined,
      size: size * 0.48,
      color: here ? tones.ink : tones.faint,
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tones.raised,
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: tones.line),
      ),
      child: _thumb == null
          // Henüz burada değil: iniyorsa bulutun çevresinde ilerleme halkası.
          ? AttachmentProgress(
              attachment: a,
              builder: (context, percent) => percent == null
                  ? icon
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: size * 0.74,
                          height: size * 0.74,
                          child: CircularProgressIndicator(
                            value: percent / 100,
                            strokeWidth: 2.5,
                            color: tones.accent,
                            backgroundColor: tones.line,
                          ),
                        ),
                        Icon(Icons.arrow_downward_rounded, size: size * 0.36, color: tones.ink),
                      ],
                    ),
            )
          : FutureBuilder<File?>(
              future: _thumb,
              builder: (context, snap) {
                final file = snap.data;
                if (file == null) return icon;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      file,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, _, _) => icon,
                    ),
                    // Videoyu fotoğraftan ayıran işaret.
                    if (a.kind == AttachmentKind.video)
                      Center(
                        child: Container(
                          width: size * 0.5,
                          height: size * 0.5,
                          decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                          child: Icon(Icons.play_arrow_rounded, size: size * 0.38, color: Colors.white),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

enum _RowAction { rename, share, copy, remove }

/// Düzenleyicideki ek satırı: küçük görüntü, ad, tür ve boyut; sağda menü.
class AttachmentRow extends StatelessWidget {
  const AttachmentRow({
    super.key,
    required this.attachment,
    required this.onRename,
    required this.onRemove,
  });

  final Attachment attachment;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final s = AppStrings.of(context);
    final a = attachment;
    return InkWell(
      onTap: () => openAttachment(context, a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
        child: Row(
          children: [
            AttachmentThumb(attachment: a),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tones.ink),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AttachmentProgress(
                      attachment: a,
                      builder: (context, percent) => Text(
                        attachmentDetail(s, a, downloading: percent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: tones.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_RowAction>(
              tooltip: s.options,
              icon: Icon(Icons.more_vert_rounded, color: tones.muted),
              onSelected: (action) async {
                switch (action) {
                  case _RowAction.rename:
                    final name = await askAttachmentName(context, a);
                    if (name != null) onRename(name);
                  case _RowAction.share:
                    await shareAttachment(context, a);
                  case _RowAction.copy:
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: a.url ?? ''));
                    messenger.showSnackBar(SnackBar(content: Text(s.linkCopied)));
                  case _RowAction.remove:
                    onRemove();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: _RowAction.rename, child: Text(s.renameAttachment)),
                PopupMenuItem(value: _RowAction.share, child: Text(s.shareAttachment)),
                if (a.isLink) PopupMenuItem(value: _RowAction.copy, child: Text(s.copyLink)),
                PopupMenuItem(value: _RowAction.remove, child: Text(s.removeAttachment)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartın odak görünümündeki ek şeridi: yan yana küçük kutular, dokununca açılır;
/// sonda "ekle". Kılavuza ya da garanti belgesine düzenleyiciye girmeden ulaşılır.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.attachments, required this.onAdd});

  final List<Attachment> attachments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final s = AppStrings.of(context);
    // İki satır yazı sığsın: telefonun yazı boyutu büyütülmüşse şerit de uzar
    // (60dp'de 1,3 kattan itibaren alttan taşıyordu).
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return SizedBox(
      height: 60 + 34 * (scale - 1).clamp(0.0, 2.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == attachments.length) {
            return Tooltip(
              message: s.addAttachment,
              child: Material(
                color: tones.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onAdd,
                  child: SizedBox(width: 56, child: Icon(Icons.add_rounded, color: tones.ink)),
                ),
              ),
            );
          }
          final a = attachments[i];
          return Material(
            color: tones.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openAttachment(context, a),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AttachmentThumb(attachment: a),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: tones.ink),
                          ),
                          AttachmentProgress(
                            attachment: a,
                            builder: (context, percent) => Text(
                              attachmentDetail(s, a, downloading: percent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: tones.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
