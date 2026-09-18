import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/app_paths.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../services/image_service.dart';
import '../services/image_tone.dart';
import '../services/visual_index.dart';
import '../state/inventory_store.dart';
import 'shell.dart';
import 'widgets/paper.dart';
import 'widgets/tree_picker.dart';

/// Seri ekleme: koli boşaltırken, oda dizerken eşyaları tek tek "+ → fotoğraf → ad → kaydet"
/// diye girmek yoruyordu. Kamera açık kalır, art arda çekilir (çekilenler altta küçük pullar
/// olarak birikir); "Bitti"de her pula yalnızca ad yazılır, boş kalan "Adsız N" olur, hepsi tek
/// dokunuşla hedef klasöre girer. Fotoğrafın tonu (kart rengi) ve görüntüyle arama izi çekim
/// sürerken arka planda hazırlanır.
///
/// Galeriden de olur ([BurstSource.gallery]): birden çok fotoğraf seçilir, her biri ad yazma adımına
/// fotoğrafın adıyla gelir (değiştirilebilir). Satırlar hemen görünür, fotoğraflar geldikçe dolar; alma ve
/// kaydetme ilerleme çubuğuyla (200 fotoğrafta dakikalarca "hiçbir şey olmuyor" gibi duruyordu).
///
/// Fotoğraflar çekilir ya da seçilir seçilmez envanterin `images/` klasörüne yazılır (geçici dosya
/// uygulama kapanınca kaybolabilirdi); vazgeçilen ya da çıkarılan çekim oradan silinir.
class BurstAddPage extends StatefulWidget {
  const BurstAddPage({
    super.key,
    required this.parentId,
    this.source = BurstSource.camera,
    this.picked,
    @visibleForTesting this.initialShots,
  });

  /// Eklenecek yer: sanal kök ([Roots.home], [Roots.drawer]) ya da klasör.
  final String parentId;

  final BurstSource source;

  /// Galeriden seçilenler (adres, galerideki adı); sayfa doğrudan ad yazma adımında açılır, fotoğraflar
  /// orada alınır.
  final List<(String, String)>? picked;

  /// Kamerasız başlangıç (testler): `images/` altındaki göreli yollar; sayfa doğrudan ad yazma
  /// adımında açılır.
  final List<String>? initialShots;

  /// "+" → "Seri ekle": kamerayla mı, galeriden mi.
  static Future<void> start(BuildContext context, String parentId) async {
    final s = InventoryScope.read(context).strings;
    final source = await showAppSheet<BurstSource>(
      context,
      (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(s.burstAdd, style: Theme.of(context).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(s.takePhoto),
              subtitle: Text(s.burstCameraHint),
              onTap: () => Navigator.of(context).pop(BurstSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(s.pickFromGallery),
              subtitle: Text(s.burstGalleryHint),
              onTap: () => Navigator.of(context).pop(BurstSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    await open(context, parentId, source: source);
  }

  /// Açar; eklenen eşya sayısını bildirir. Galeriden açılırken önce sistemin seçicisi gelir, hiçbir şey
  /// seçilmezse sayfa açılmaz.
  static Future<void> open(BuildContext context, String parentId, {BurstSource source = BurstSource.camera}) async {
    final store = InventoryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    List<(String, String)>? picked;
    if (source == BurstSource.gallery) {
      try {
        picked = await ImageService.pickGallery();
      } on Object {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(store.strings.photoFailed)));
        return;
      }
      if (picked.isEmpty || !context.mounted) return;
    }
    final added = await Navigator.of(context).push<(int, String)>(
      MaterialPageRoute(builder: (_) => BurstAddPage(parentId: parentId, source: source, picked: picked)),
    );
    if (added == null || added.$1 == 0) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(store.strings.burstAdded(added.$1, added.$2))));
  }

  @override
  State<BurstAddPage> createState() => _BurstAddPageState();
}

/// Seri eklemenin fotoğraf kaynağı.
enum BurstSource { camera, gallery }

class _Shot {
  _Shot(this.path, [String name = '']) : name = TextEditingController(text: name);

  /// `images/...` göreli yolu; galeriden seçilende fotoğraf gelene dek null.
  String? path;
  final TextEditingController name;

  /// Satır çıkarıldı (fotoğrafı gelmeden de olabilir): sonradan gelen fotoğraf silinir.
  bool removed = false;

  /// Kart rengi ve görüntüyle arama izi; fotoğraf gelince sıraya girer ([_BurstAddPageState._enqueue]).
  late final Future<(int?, String?)> prepared = _prepare();

  Future<(int?, String?)> _prepare() async {
    final file = AppPaths.imageFile(path);
    if (file == null) return (null, null);
    try {
      final (tone, signature) = await _prepareOff(await file.readAsBytes());
      return (tone == null ? null : nearestPaletteColor(Color(tone)).toARGB32(), signature);
    } on Object {
      return (null, null);
    }
  }
}

/// Kart rengi ve görüntüyle arama izi tek çözümle, ayrı yalıtımda ([ImageTone], [VisualIndex] ile aynı
/// hesap): fotoğrafı ikisi için ayrı ayrı çözmek hazırlığın yarısıydı. Kapanış üst düzeyde kurulur, yalıtıma
/// yalnızca baytlar gider (kapanış kurulduğu kapsamı da taşır, orada gönderilemeyen bir şey olmasın).
Future<(int?, String?)> _prepareOff(Uint8List bytes) => Isolate.run(() => _prepareBytes(bytes));

(int?, String?) _prepareBytes(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return (null, null);
  }
  if (decoded == null) return (null, null);
  return (toneOfImage(decoded), VisualIndex.signatureOfImage(decoded).encode());
}

class _BurstAddPageState extends State<BurstAddPage> with WidgetsBindingObserver {
  static const _uuid = Uuid();

  final List<_Shot> _shots = [];
  late String _target = widget.parentId;
  late bool _reviewing = widget.initialShots != null || widget.source == BurstSource.gallery;
  CameraController? _camera;
  Object? _cameraError;
  bool _capturing = false;
  bool _saving = false;
  bool _flash = false;

  /// Kaydederken hazırlığı biten fotoğraf sayısı (ilerleme).
  int _ready = 0;

  /// Galeriden alma: bu turda seçilen ve işi biten (alınan ya da alınamayan) fotoğraf sayısı.
  int _importTotal = 0;
  int _importDone = 0;
  bool get _importing => _importDone < _importTotal;

  /// Sayfadan çıkıldı: süren alma durur, sonradan gelen fotoğraf silinir.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final path in widget.initialShots ?? const <String>[]) {
      _shots.add(_Shot(path));
    }
    if (widget.picked case final picked?) _addPicks(picked);
    if (!_reviewing) unawaited(_openCamera());
  }

  /// Kamerayla başlayan sayfa: ad yazma adımından geri, çekime döner.
  bool get _fromCamera => widget.source == BurstSource.camera && widget.initialShots == null;

  /// Hazırlık (ton, iz) en çok bu kadar fotoğrafta aynı anda: her biri ayrı yalıtımda bir fotoğraf çözer.
  /// Tek tek sırayla 200 fotoğrafta dakikalar sürüyordu; hepsi birden başlasa bellek dolardı.
  static final _prepareWorkers = math.max(1, math.min(3, Platform.numberOfProcessors - 1));

  /// Galeriden aynı anda alınan fotoğraf (yerelde ayrı iş parçacıklarında küçültülür).
  static const _importWorkers = 3;

  final _waiting = Queue<_Shot>();
  int _running = 0;

  /// Hazırlık sırasına koyar; sıra gelince başlar.
  _Shot _enqueue(_Shot shot) {
    _waiting.add(shot);
    _pump();
    return shot;
  }

  void _pump() {
    while (_running < _prepareWorkers && _waiting.isNotEmpty) {
      final shot = _waiting.removeFirst();
      if (shot.removed) continue;
      _running++;
      unawaited(shot.prepared.whenComplete(() {
        _running--;
        _pump();
      }));
    }
  }

  /// Galeriden seçilenler satır olarak hemen (adlarıyla) eklenir, fotoğraflar arkadan alınır.
  void _addPicks(List<(String, String)> picks) {
    final rows = [for (final (_, name) in picks) _Shot(null, ImageService.nameOfImage(name))];
    _shots.addAll(rows);
    _importTotal = picks.length;
    _importDone = 0;
    unawaited(_import([for (final (i, (uri, _)) in picks.indexed) (rows[i], uri)]));
  }

  /// Fotoğrafları birkaç tane birden alır; gelen satırın fotoğrafı dolar, hazırlığa girer. Alınamayan satır
  /// düşer, sonunda sayısı söylenir.
  Future<void> _import(List<(_Shot, String)> jobs) async {
    var next = 0;
    var failed = 0;
    Future<void> worker() async {
      while (next < jobs.length && !_closing) {
        final (shot, uri) = jobs[next++];
        String? path;
        if (!shot.removed) {
          try {
            path = await ImageService.importPicked(uri);
          } on Object {
            path = null;
          }
        }
        if (_closing || !mounted) {
          ImageService.discard(path);
          return;
        }
        setState(() {
          _importDone++;
          if (shot.removed) {
            ImageService.discard(path);
          } else if (path == null) {
            failed++;
            _shots.remove(shot);
            shot.name.dispose();
          } else {
            shot.path = path;
            _enqueue(shot);
          }
        });
      }
    }

    await Future.wait([for (var i = 0; i < _importWorkers; i++) worker()]);
    if (failed == 0 || !mounted || _closing) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(InventoryScope.read(context).strings.burstImportFailed(failed))));
  }

  Future<void> _addFromGallery() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = InventoryScope.read(context).strings;
    final List<(String, String)> picks;
    try {
      picks = await ImageService.pickGallery();
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.photoFailed)));
      return;
    }
    if (picks.isEmpty || !mounted || _closing) return;
    setState(() => _addPicks(picks));
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera?.dispose());
    for (final shot in _shots) {
      shot.name.dispose();
    }
    super.dispose();
  }

  /// Arka plana geçince kamera bırakılır (başka uygulama kullanabilsin), dönünce yeniden açılır.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_reviewing) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final camera = _camera;
      _camera = null;
      unawaited(camera?.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      unawaited(_openCamera());
    }
  }

  Future<void> _openCamera() async {
    setState(() => _cameraError = null);
    try {
      if (!await ImageService.ensureCamera()) throw CameraException('denied', 'no permission');
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'no camera');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      // 1080p: kartlar ve görüntüyle arama için yeter; tam çözünürlük her fotoğrafta birkaç MB
      // olur, eşitlemede de gidip gelirdi (galeriden seçilenler de 1800 pikselle sınırlı).
      final camera = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await camera.initialize();
      if (!mounted || _reviewing) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
    } on Object catch (e) {
      if (mounted) setState(() => _cameraError = e);
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturing) return;
    setState(() {
      _capturing = true;
      _flash = true;
    });
    unawaited(HapticFeedback.lightImpact());
    try {
      final shot = await camera.takePicture();
      final relative = p.join('images', '${_uuid.v4()}.jpg');
      Directory(p.join(AppPaths.docsDir, 'images')).createSync(recursive: true);
      await File(shot.path).copy(p.join(AppPaths.docsDir, relative));
      unawaited(File(shot.path).delete().then((_) {}, onError: (_) {}));
      AppPaths.forget(relative);
      final added = _enqueue(_Shot(relative));
      if (mounted) setState(() => _shots.add(added));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(InventoryScope.read(context).strings.photoFailed)));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  void _remove(_Shot shot) {
    shot.removed = true;
    ImageService.discard(shot.path);
    shot.name.dispose();
    setState(() => _shots.remove(shot));
    if (_shots.isEmpty && _reviewing && _fromCamera) _backToCamera();
  }

  void _toReview() {
    if (_shots.isEmpty) return;
    final camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    setState(() => _reviewing = true);
  }

  void _backToCamera() {
    setState(() => _reviewing = false);
    unawaited(_openCamera());
  }

  /// Çekilenler varken çıkmak hepsini siler: önce sorulur.
  Future<void> _leave() async {
    if (_shots.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final s = InventoryScope.read(context).strings;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.burstDiscardQuestion(_shots.length)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.burstKeep)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.burstDiscard)),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _closing = true;
    for (final shot in [..._shots]) {
      ImageService.discard(shot.path);
    }
    _shots.clear();
    Navigator.of(context).pop();
  }

  String _placeLabel(InventoryStore store) => switch (_target) {
        Roots.home => store.strings.home,
        Roots.drawer => store.strings.drawer,
        final id => store.byId(id) == null ? store.strings.home : store.nameOf(store.byId(id)!),
      };

  Future<void> _changeTarget() async {
    final store = InventoryScope.read(context);
    final probe = store.draft(parentId: _target, kind: NodeKind.item);
    final picked = await pickTreeTarget(context, moving: probe);
    if (picked != null && mounted) setState(() => _target = picked);
  }

  /// Her fotoğraf bir eşya, çekim ya da seçim sırasıyla. Hazırlıklar (ton, iz) bittikçe ilerleme ilerler;
  /// sonra hepsi tek yazımla girer ([InventoryStore.addAll]: 200 ayrı yazım ve yeniden çizim yerine).
  /// Ad boşsa sıradaki "Adsız N".
  Future<void> _save() async {
    final store = InventoryScope.read(context);
    final navigator = Navigator.of(context);
    final shots = [..._shots];
    setState(() {
      _saving = true;
      _ready = 0;
    });
    // Taslaklar yazımdan önce kurulduğu için sıra numarası elle ardışık verilir (store.draft hepsine
    // aynısını verirdi).
    final first = store.draft(parentId: _target, kind: NodeKind.item);
    final drafts = <Node>[];
    for (final (i, shot) in shots.indexed) {
      final (color, signature) = await shot.prepared;
      var draft = (i == 0 ? first : store.draft(parentId: _target, kind: NodeKind.item)).copyWith(
            name: shot.name.text.trim(),
            imagePath: shot.path,
            imageSig: signature,
            sortIndex: first.sortIndex + i,
          );
      if (color != null) draft = draft.copyWith(color: color);
      drafts.add(draft);
      if (mounted) setState(() => _ready = i + 1);
    }
    await store.addAll(drafts);
    final place = _placeLabel(store);
    _shots.clear();
    if (mounted) navigator.pop((drafts.length, place));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        if (_reviewing && _fromCamera) {
          _backToCamera();
        } else {
          _leave();
        }
      },
      child: _reviewing ? _review(context) : _capturePage(context),
    );
  }

  Widget _capturePage(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: camera != null && camera.value.isInitialized
                ? Center(child: CameraPreview(camera))
                : Center(
                    child: _cameraError == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.burstCameraFailed,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonal(onPressed: _openCamera, child: Text(s.retry)),
                              ],
                            ),
                          ),
                  ),
          ),
          // Deklanşör geri bildirimi: kısa bir beyaz parlama.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flash ? 0.35 : 0,
              duration: const Duration(milliseconds: 90),
              child: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: s.back,
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: _leave,
                      ),
                      Expanded(
                        child: Text(
                          s.burstTarget(_placeLabel(store)),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_shots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    child: Text(
                      s.burstEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _shots.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _Thumb(shot: _shots[_shots.length - 1 - i], size: 64),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _shots.isEmpty ? '' : s.burstShots(_shots.length),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: s.takePhoto,
                        child: Tooltip(
                          message: s.takePhoto,
                          child: GestureDetector(
                            onTap: _capture,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                              ),
                              padding: const EdgeInsets.all(5),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _capturing ? Colors.white54 : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: _shots.isEmpty ? null : _toReview,
                            child: Text(s.burstDone),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _review(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    return Scaffold(
      appBar: ShellHeader(
        title: s.burstShots(_shots.length),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 24)),
        children: [
          PaperSection(
            padding: EdgeInsets.zero,
            children: [
              PaperRow(
                icon: Icons.folder_open_rounded,
                title: s.burstTarget(_placeLabel(store)),
                onTap: _saving ? null : _changeTarget,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Galeriden alma sürüyor: satırlar adlarıyla hazır, fotoğraflar geldikçe dolar.
          if (_importing) ...[
            Text(
              s.burstImporting(_importDone, _importTotal),
              style: TextStyle(color: tones.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _ProgressLine(value: _importDone / _importTotal),
            const SizedBox(height: 14),
          ],
          for (final (i, shot) in _shots.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: tones.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tones.line),
              ),
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  _Thumb(shot: shot, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: shot.name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: i == _shots.length - 1 ? TextInputAction.done : TextInputAction.next,
                      onTapOutside: dismissKeyboard,
                      decoration: InputDecoration(hintText: s.burstNameHint, border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    tooltip: s.burstRemoveShot,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _saving ? null : () => _remove(shot),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kaydederken: hazırlığı (ton, iz) biten fotoğraflar; sonra hepsi tek yazımla girer.
              if (_saving) ...[
                _ProgressLine(value: _shots.isEmpty ? 1 : _ready / _shots.length),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (_fromCamera) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(s.burstTakeMore),
                      onPressed: _saving ? null : _backToCamera,
                    ),
                    const SizedBox(width: 12),
                  ] else if (widget.source == BurstSource.gallery) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(s.burstMoreFromGallery),
                      onPressed: _saving || _importing ? null : _addFromGallery,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving || _importing || _shots.isEmpty ? null : _save,
                      child: Text(switch (_saving) {
                        false => s.burstAddItems(_shots.length),
                        true when _ready < _shots.length => s.burstPreparing(_ready, _shots.length),
                        true => s.burstSaving,
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.shot, required this.size});

  final _Shot shot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = AppPaths.imageFile(shot.path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: file == null
            // Galeriden henüz gelmedi.
            ? const ColoredBox(color: Colors.black26, child: Icon(Icons.photo_outlined, color: Colors.white70))
            : Image.file(file, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
      ),
    );
  }
}

/// Belirli ilerleme çubuğu. Dönen (belirsiz) gösterge değil: ne kadar kaldığı görünsün, testlerde de
/// `pumpAndSettle` askıda kalmaz.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 6),
      );
}
