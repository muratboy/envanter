import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_paths.dart';
import '../core/strings.dart';
import '../services/image_service.dart';
import '../services/visual_index.dart';
import '../state/inventory_store.dart';
import 'container_screen.dart';
import 'widgets/focus_overlay.dart';
import '../core/theme.dart';
import 'widgets/paper.dart';
import 'widgets/ink_art.dart';
import 'shell.dart';

/// Elindeki eşyanın fotoğrafını çekip envanterdeki resimlerle karşılaştırır.
/// Model kullanmıyor; resimlerin parmak izlerini eşleştiriyor, bu yüzden
/// benzer açıdan çekilmiş fotoğraflarda iyi, çok farklı açılarda zayıf.
class VisualSearchPage extends StatefulWidget {
  const VisualSearchPage({super.key});

  @override
  State<VisualSearchPage> createState() => _VisualSearchPageState();
}

enum _Stage { idle, picking, comparing, done }

class _VisualSearchPageState extends State<VisualSearchPage> {
  _Stage _stage = _Stage.idle;

  /// Sonuçta gösterilen fotoğrafın bellekteki kopyası; dosyanın kendisi
  /// karşılaştırma biter bitmez siliniyor.
  Uint8List? _shot;
  List<VisualMatch> _matches = const [];
  String? _error;

  /// Henüz silinmemiş geçici dosya (karşılaştırma sürerken).
  String? _pending;

  /// Kaçıncı arama: vazgeçilen bir aramadan geç gelen sonuç kullanılmaz.
  int _run = 0;

  Future<void> _pick(ImageSource source) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final run = ++_run;

    setState(() {
      _stage = _Stage.picking;
      _error = null;
      _matches = const [];
    });

    String? path;
    try {
      path = await ImageService.pick(source);
    } on Exception {
      path = null;
    }
    // Vazgeçilmiş ya da sayfadan çıkılmışsa fotoğraf da durmasın.
    if (!mounted || run != _run) {
      ImageService.discard(path);
      return;
    }
    if (path == null) {
      // Kullanıcı kameradan vazgeçti: sayfadan atılmaz, yeniden deneyebilir.
      setState(() => _stage = _shot == null ? _Stage.idle : _Stage.done);
      return;
    }

    _pending = path;
    setState(() => _stage = _Stage.comparing);

    final file = AppPaths.imageFile(path);
    if (file == null) {
      _pending = null;
      ImageService.discard(path);
      setState(() {
        _stage = _Stage.done;
        _error = s.photoFailed;
      });
      return;
    }

    final bytes = await file.readAsBytes();
    final matches = await store.findByImage(file);
    // Arama fotoğrafı envanterin parçası değil: işi bitince diskten silinir,
    // önizleme bellekteki kopyadan çizilir.
    ImageService.discard(path);
    _pending = null;
    if (!mounted || run != _run) return;
    setState(() {
      _stage = _Stage.done;
      _shot = bytes;
      _matches = matches;
    });
  }

  /// Kamera/galeri beklerken vazgeçme: geç gelen sonuç yok sayılır.
  void _cancelPick() {
    _run++;
    setState(() => _stage = _shot == null ? _Stage.idle : _Stage.done);
  }

  @override
  void dispose() {
    // Yarıda kalan arama fotoğrafı iz bırakmasın.
    ImageService.discard(_pending);
    super.dispose();
  }

  void _open(VisualMatch match) {
    final node = match.node;
    if (node.isContainer) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ContainerScreen(containerId: node.id)),
      );
    } else {
      showNodeFocus(context, node);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: ShellHeader(
        title: s.visualSearch,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: switch (_stage) {
        _Stage.idle => _Start(
            noImages: store.imagedCount == 0,
            onCamera: () => _pick(ImageSource.camera),
            onGallery: () => _pick(ImageSource.gallery),
          ),
        _Stage.picking => _Busy(label: s.visualSearchOpening, onCancel: _cancelPick),
        _Stage.comparing => _Busy(label: s.visualSearchRunning),
        _Stage.done => ListView(
            padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
            children: [
              if (_shot case final bytes?) _Shot(bytes: bytes),
              const SizedBox(height: 16),
              if (_error != null)
                _Message(text: _error!, theme: theme)
              else if (_matches.isEmpty)
                _Message(text: s.visualSearchNoMatch, theme: theme)
              else ...[
                Text(
                  s.visualSearchResult(_matches.length),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                for (final match in _matches)
                  _MatchTile(
                    match: match,
                    store: store,
                    onTap: () => _open(match),
                  ),
              ],
              const SizedBox(height: 20),
              Center(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: Text(s.searchAgain),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text(s.visualSearchFromGallery),
                    ),
                  ],
                ),
              ),
            ],
          ),
      },
    );
  }
}

/// Arama başlamadan önceki ekran: kullanıcı kamerayı kendi açar, istemezse
/// geri döner. (Sayfa açılır açılmaz kamera açılsaydı, kameradan çıkmak
/// dışında seçenek kalmazdı.)
class _Start extends StatelessWidget {
  const _Start({required this.noImages, required this.onCamera, required this.onGallery});

  final bool noImages;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: readableInsets(context, const EdgeInsets.fromLTRB(24, 24, 24, 32)),
      children: [
        const Center(child: InkArt(InkArtKind.search, size: 124)),
        const SizedBox(height: 18),
        Text(
          noImages ? s.visualSearchNoImages : s.visualSearchHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (!noImages) ...[
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.photo_camera_rounded),
            label: Text(s.visualSearchTake),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_rounded),
            label: Text(s.visualSearchFromGallery),
          ),
        ],
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label, this.onCancel});

  final String label;

  /// Kamera/galeri beklenirken vazgeçme.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 22),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onCancel != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onCancel,
                  child: Text(AppStrings.of(context).cancel),
                ),
              ],
            ],
          ),
        ),
      );
}

class _Shot extends StatelessWidget {
  const _Shot({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const InkArt(InkArtKind.search, size: 104),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontSize: 19)),
          ],
        ),
      );
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.store, required this.onTap});

  final VisualMatch match;
  final InventoryStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final node = match.node;
    final s = store.strings;
    final percent = (match.score * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RecordTile(
        node: node,
        title: store.nameOf(node),
        subtitle: '${s.similarity(percent)} · ${store.pathLabel(node.id)}',
        onTap: onTap,
        trailing: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(Icons.chevron_right_rounded, color: Tones.of(context).faint),
        ),
      ),
    );
  }
}
