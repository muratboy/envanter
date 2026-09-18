import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_paths.dart';
import '../../core/node_icons.dart';
import '../../core/palette.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/time_span.dart';
import '../../data/node.dart';
import '../../state/inventory_store.dart';
import '../actions.dart';
import '../sharing/sharing_flows.dart';
import '../sharing/sharing_scope.dart';
import 'card_swipe.dart';
import 'entrance.dart';
import 'stacked_card_list.dart';
import '../../data/lots.dart';
import 'photo_viewer.dart';

/// Kartın simgesi: seçilmişse o, yoksa türün varsayılanı.
IconData nodeGlyph(Node node) => NodeIcons.byKey(node.icon) ?? glyphFor(node.kind);

IconData glyphFor(NodeKind kind) => kind == NodeKind.container
    ? Icons.inventory_2_rounded
    : Icons.label_rounded;

/// Kaydın ekrandaki kart rengi (eski paletteki renkler çevrilir, koyu temada
/// kısılır).
Color nodeTone(BuildContext context, Node node) =>
    cardTone(node.color, Theme.of(context).brightness);

/// Kartın görsel gövdesi. Kağıttan bir kartoteks: klasör bir klasör,
/// eşya çizgili bir fiş kartı. Fotoğraf varsa kartın üstüne tutturulmuş bir
/// baskı gibi durur; kartın düzenini değiştirmez.
class NodeCard extends StatelessWidget {
  const NodeCard({
    super.key,
    required this.node,
    this.focus = 1,
    this.focusOf,
    this.subtitle,
    this.onPlus,
    this.highlight = false,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 12, 12),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.onMore,
    this.onQuantity,
    this.selected,
    this.openPhoto = false,
    this.titleController,
    this.titleHint,
    this.titleAutofocus = false,
    this.onTitleChanged,
    this.onTitleSubmitted,
    this.onGlyph,
  });

  final Node node;

  /// Fotoğrafa dokununca tam ekran açılır (büyütülüp incelenir). Seçerken ya
  /// da yalnızca gösterilen kartta kapalı: dokunuş karta gider.
  final bool openPhoto;

  /// Düzenleyicide: ad kartın başlığında, yerinde yazılır (parmak zaten oraya
  /// gidiyordu; ayrı "Ad" kutusu yok). Verilince başlık bir yazı alanıdır.
  final TextEditingController? titleController;
  final String? titleHint;
  final bool titleAutofocus;
  final ValueChanged<String>? onTitleChanged;
  final VoidCallback? onTitleSubmitted;

  /// Tür simgesine dokununca (düzenleyicide simge seçimi).
  final VoidCallback? onGlyph;

  /// Toplu seçimde: true seçili, false seçilmemiş; null ise seçim kapalı.
  /// Seçim açıkken tür simgesinin yerinde işaret durur.
  final bool? selected;

  /// Adet tutulan eşyada − / + ile yeni adet. null ise adet yalnızca yazılır.
  final ValueChanged<int>? onQuantity;

  /// Kartın sağ üstündeki "⋯": seçenekleri açar.
  final VoidCallback? onMore;

  /// 1.0 odakta, 0.0 destede. Alt satırın belirginliğini ayarlar.
  final double focus;

  /// Destede odak kaydırdıkça değişir: verilirse [focus] yerine bu dinlenir ve
  /// yalnızca odağa bağlı iki parça (gölge, alt satırın saydamlığı) yenilenir.
  /// Kartın tamamı her kaydırma karesinde baştan kurulmasın diye.
  final ValueListenable<double>? focusOf;
  final String? subtitle;

  /// Klasörlerde yeni kayıt başlatan artı.
  final VoidCallback? onPlus;

  /// Üzerine bırakma hedefi olarak işaretli.
  final bool highlight;

  /// Kartın iç boşlukları.
  final EdgeInsets padding;

  /// Destede yerleşimi deste yapıyor; tek başına gösterilen kartta kenar payı.
  final EdgeInsets margin;

  static const double radius = 22;

  /// Fiş kartında başlık çizgisinin yeri (kartın üstünden).
  static const double headerRule = 58;

  /// Kartın dış biçimi: klasör sekmeli klasör, eşya yuvarlak köşeli fiş kartı.
  static ShapeBorder cardShape(NodeKind kind, {BorderSide side = BorderSide.none}) =>
      kind == NodeKind.container
          ? FolderBorder(radius: radius, side: side)
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = nodeTone(context, node);
    final ink = onColorOf(color);
    final soft = ink.withValues(alpha: 0.62);
    final image = AppPaths.imageFile(node.imagePath);
    final store = InventoryScope.of(context);
    final pending = store.hasPendingMark(node.id);
    final inside = node.isContainer ? store.childrenOf(node.id) : const <Node>[];
    // Fotoğrafı olmayan klasör: içindekilerin fotoğrafları kapak olur.
    final cover = image == null && node.isContainer ? FolderCover.filesOf(store, node) : const <File>[];
    // Son kullanma: yaklaştıysa hardal, geçtiyse kırmızı damga.
    final expiry = store.expiryOf(node);
    // Paketli eşyanın bir kısmının tarihi geçtiyse (hepsinin değil): "2 tanesi geçti".
    final partlyExpired = expiry == ExpiryState.expired &&
            node.hasLots &&
            !dateOnly(DateTime.now()).isAfter(node.lastExpiry!)
        ? expiredUnits(node, DateTime.now())
        : 0;
    // Bırakma hedefi ya da seçili: kiremit kenar.
    final marked = highlight || selected == true;
    final focusOf = this.focusOf ?? AlwaysStoppedAnimation(focus);

    // Kart sabit boyda: yazı büyütmesi sınırlı (bkz. kFixedTextScale).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kFixedTextScale,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - margin.horizontal).clamp(0.0, double.infinity);
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 214.0;
        // Fotoğraf düzeni belirlemez: yazı ve düğmeler fotoğrafsız karttaki
        // yerlerindedir, fotoğraf kartın üstüne tutturulmuş bir baskı gibi
        // arkada durur; üst üste gelirlerse yazılar önde kalır.
        final pin = PinnedPhoto.styleFor(node.id);
        // Yatay düzende kart kısa ama geniş: başlık çizgisinin altında fotoğrafa
        // yer kalmıyordu (küçücük). Orada kartın boyunca uzanır, sağdaki ⋯ ve +
        // sütununun solunda durur; ad solda kalır.
        final lengthwise = h < 200 && w > 300 && landscapeLayout(context);
        // Dikeyde başlık satırının altından başlar: ad ve simgeler açık kalır.
        final double photoTop = lengthwise
            ? 12 + (node.isContainer ? FolderBorder.drop : 0)
            : NodeCard.headerRule - 6 + (node.isContainer ? FolderBorder.drop / 2 : 0);
        final double photoRight = 22 + pin.shift + (lengthwise ? 46 : 0);
        final photoHeight = (h - photoTop - (lengthwise ? 12 : 10)).clamp(60.0, 196.0);
        final photoWidth = (photoHeight * 0.88).clamp(64.0, w * (lengthwise ? 0.36 : 0.46));
        // Not yazısı fotoğrafın altına girmesin diye ondan önce satır atlar.
        final photoLeft =
            image == null && cover.isEmpty ? 0.0 : photoRight + photoWidth + 10 - padding.right;

        return FocusBuilder(
          focus: focusOf,
          // Gölge odağa bağlı; gövde ([child]) değil.
          builder: (context, focus, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: margin,
          decoration: ShapeDecoration(
            color: color,
            shape: cardShape(
              node.kind,
              // Kağıt kenarı: çok ince bir çizgi; bırakma hedefiyken kiremit.
              side: marked
                  ? BorderSide(color: tones.accent, width: 2.5)
                  : BorderSide(color: ink.withValues(alpha: dark ? 0.0 : 0.07)),
            ),
            shadows: [
              BoxShadow(
                color: tones.shadow.withValues(alpha: (dark ? 0.42 : 0.10) + 0.08 * focus),
                blurRadius: 16 + 12 * focus,
                offset: Offset(0, 5 + 7 * focus),
              ),
              BoxShadow(
                color: tones.shadow.withValues(alpha: dark ? 0.35 : 0.07),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
              if (marked)
                BoxShadow(color: tones.accent.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!node.isContainer)
                CustomPaint(painter: _IndexCardPainter(ink: ink, accent: tones.accent)),
              if (image != null)
                Positioned(
                  // Sağda, düğme şeridinin biraz içinde, dikeyde ortada.
                  right: photoRight,
                  top: photoTop,
                  width: photoWidth,
                  height: photoHeight,
                  child: IgnorePointer(
                    ignoring: !openPhoto,
                    child: Semantics(
                      button: openPhoto,
                      label: openPhoto ? store.strings.openPhoto : null,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: openPhoto ? () => showPhoto(context, image, title: store.nameOf(node)) : null,
                        child: PinnedPhoto(file: image, style: pin),
                      ),
                    ),
                  ),
                ),
              if (cover.isNotEmpty)
                Positioned(
                  right: photoRight,
                  top: photoTop,
                  width: photoWidth,
                  height: photoHeight,
                  // Dokunuş karta gider: kapak bir fotoğraf değil, klasörün içi.
                  child: IgnorePointer(child: FolderCover(files: cover, seed: node.id)),
                ),
              Padding(
                padding: node.isContainer ? padding.copyWith(top: padding.top + 2) : padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sol üst: tür simgesi ve ad.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        selected == null
                            ? GestureDetector(
                                onTap: onGlyph,
                                child: _GlyphChip(
                                  kind: node.kind,
                                  glyph: nodeGlyph(node),
                                  ink: ink,
                                  cardColor: color,
                                ),
                              )
                            : _SelectChip(selected: selected!, ink: ink),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: titleController == null
                                ? Text(
                                    store.nameOf(node),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: ink,
                                      fontSize: 21,
                                      height: 1.2,
                                    ),
                                  )
                                : _TitleField(
                                    controller: titleController!,
                                    hint: titleHint,
                                    autofocus: titleAutofocus,
                                    onChanged: onTitleChanged,
                                    onSubmitted: onTitleSubmitted,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: ink,
                                      fontSize: 21,
                                      height: 1.2,
                                    ),
                                    ink: ink,
                                  ),
                          ),
                        ),
                        // İşaretler (yıldız, damgalar, kilit, kayıp...) dar kartta ya da
                        // büyük yazıda sığmazsa küçülür; ad her zaman en az kartın
                        // kalanını alır. Sığıyorsa hiçbir şey değişmez.
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: w * 0.56),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Sık kullanılan: destede hep açık duran başlık satırında.
                                if (store.isFavorite(node.id))
                                  _RowSlot(
                                    left: 6,
                                    child: Tooltip(
                                      message: store.strings.favorites,
                                      child: Icon(Icons.star_rounded, size: 18, color: tones.accent),
                                    ),
                                  ),
                                // Dolu klasör: yer ararken tek bakışta görünsün diye
                                // destede hep açık duran başlık satırında damga gibi.
                                if (node.isContainer && node.isFull)
                                  _RowSlot(
                                    left: 8,
                                    child: Tooltip(
                                      message: store.strings.fullHint,
                                      child: _Stamp(label: store.strings.fullShort),
                                    ),
                                  ),
                                // Son kullanma uyarısı: destede hep açık duran başlık satırında.
                                if (expiry == ExpiryState.soon || expiry == ExpiryState.expired)
                                  _RowSlot(
                                    left: 8,
                                    child: _Stamp(
                                      label: expiry == ExpiryState.expired
                                          ? (partlyExpired > 0
                                              ? store.strings.someExpired(partlyExpired)
                                              : store.strings.expiredShort)
                                          : store.strings.expiringShort,
                                      color: expiry == ExpiryState.expired ? _dangerStamp : tones.lost,
                                      ink: expiry == ExpiryState.expired ? Colors.white : kInk,
                                    ),
                                  ),
                                // Başkası kendi özel alanına aldı: kimde olduğu.
                                if (node.heldBy != null)
                                  _RowSlot(
                                    left: 6,
                                    child: Builder(builder: (context) {
                                      final who = SharingScope.maybeOf(context)?.memberName(node.heldBy!) ??
                                          store.strings.someone;
                                      return Tooltip(
                                        message: store.strings.heldHint(who),
                                        child: NameAvatar(name: who, radius: 12),
                                      );
                                    }),
                                  ),
                                // Yalnızca bende: başka cihazlara gitmez.
                                if (store.isPrivate(node.id))
                                  _RowSlot(
                                    left: 6,
                                    child: Tooltip(
                                      message: store.strings.privateHint,
                                      child: Icon(Icons.lock_rounded, size: 16, color: soft),
                                    ),
                                  ),
                                if (node.hasGeo)
                                  _RowSlot(
                                    left: 6,
                                    child: Icon(Icons.place_rounded, size: 17, color: soft),
                                  ),
                                if (node.isLost)
                                  _RowSlot(
                                    left: 8,
                                    child: Tooltip(
                                      message: store.strings.lostDrawer,
                                      child: const LostBadge(),
                                    ),
                                  ),
                                if (pending)
                                  _RowSlot(
                                    left: 8,
                                    child: Tooltip(
                                      message: store.strings.pendingMarkTooltip,
                                      child: const PendingDot(),
                                    ),
                                  ),
                                if (node.managers.isNotEmpty)
                                  _RowSlot(
                                    left: 6,
                                    child: _ManagerAvatars(ids: node.managers, ring: color),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (onMore != null)
                          _RowSlot(
                            left: 6,
                            child: _CardButton(
                              icon: Icons.more_horiz_rounded,
                              ink: ink,
                              background: color,
                              tooltip: store.strings.options,
                              onTap: onMore!,
                            ),
                          ),
                      ],
                    ),
                    // Not: eşyada fiş kartının satırlarına, klasörde başlığın
                    // altına. Sığmazsa "…" ile biter.
                    Expanded(
                      child: _NoteArea(
                        note: node.note,
                        ink: ink,
                        ruled: !node.isContainer,
                        topGap: NodeCard.headerRule - padding.top - 34,
                        right: photoLeft,
                      ),
                    ),
                    FocusBuilder(
                      focus: focusOf,
                      builder: (context, focus, child) =>
                          Opacity(opacity: (0.35 + 0.65 * focus).clamp(0.0, 1.0), child: child),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (inside.isNotEmpty) ...[
                                  _InsidePreview(nodes: inside, ink: ink),
                                  const SizedBox(height: 9),
                                ],
                                if (node.isBorrowed) ...[
                                  _Stamp(
                                    label: node.isBorrowOverdue
                                        ? store.strings.borrowOverdueShort
                                        : store.strings.borrowedToStamp(node.borrowedTo!),
                                    color: node.isBorrowOverdue ? _dangerStamp : _paperStamp,
                                    ink: node.isBorrowOverdue ? Colors.white : kInk,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (node.quantity == 0 && !node.isContainer) ...[
                                  _Stamp(label: store.strings.outOfStock),
                                  const SizedBox(height: 6),
                                ] else if (node.isLow && !node.isContainer) ...[
                                  _Stamp(label: store.strings.lowStockShort, color: tones.lost, ink: kInk),
                                  const SizedBox(height: 6),
                                ],
                                if (node.hasAttachments || (subtitle != null && subtitle!.isNotEmpty))
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Eki olan kayıt: ataş ve sayısı (kılavuzu var mı, bir bakışta).
                                      if (node.hasAttachments) ...[
                                        Icon(Icons.attach_file_rounded, size: 14, color: soft),
                                        Text(
                                          '${node.attachments.length}',
                                          style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(width: 7),
                                      ],
                                      if (subtitle != null && subtitle!.isNotEmpty)
                                        Flexible(
                                          child: Text(
                                            subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: soft,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          if (!node.isContainer && node.tracksQuantity)
                            _QuantityStepper(
                              id: node.id,
                              quantity: node.quantity!,
                              unit: node.unit,
                              ink: ink,
                              background: color,
                              onChanged: onQuantity,
                              onTypeQuantity: onQuantity != null ? () => NodeActions.promptQuantity(context, node) : null,
                            ),
                          if (onPlus != null)
                            _CardButton(
                              icon: Icons.add_rounded,
                              ink: ink,
                              background: color,
                              filled: true,
                              tooltip: AppStrings.of(context).addInside,
                              onTap: onPlus!,
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
      },
      ),
    );
  }
}

/// Fiş kartı: başlığın altında kiremit bir çizgi, altında soluk satır
/// çizgileri. Kütüphane kataloğu kartlarından.
class _IndexCardPainter extends CustomPainter {
  const _IndexCardPainter({required this.ink, required this.accent});

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const top = NodeCard.headerRule;
    if (size.height < top + 20) return;
    canvas.drawLine(
      const Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
    final rule = Paint()
      ..color = ink.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    for (var y = top + 24; y < size.height - 8; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
  }

  @override
  bool shouldRepaint(_IndexCardPainter old) => old.ink != ink || old.accent != accent;
}

/// Kartın tür simgesi. Klasörde dolu mürekkep, eşyada kağıda basılmış
/// gibi soluk; destede yalnızca üst şeridi görünse bile türü söyler.
class _GlyphChip extends StatelessWidget {
  const _GlyphChip({
    required this.kind,
    required this.glyph,
    required this.ink,
    required this.cardColor,
  });

  final NodeKind kind;
  final IconData glyph;
  final Color ink;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final container = kind == NodeKind.container;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: container ? ink : ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(glyph, size: 18, color: container ? cardColor : ink.withValues(alpha: 0.85)),
    );
  }
}

/// Toplu seçimde tür simgesinin yerini alan işaret: seçiliyse kiremit zemin
/// üstünde tik, değilse boş bir çerçeve (dokununca seçileceği anlaşılsın).
class _SelectChip extends StatelessWidget {
  const _SelectChip({required this.selected, required this.ink});

  final bool selected;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: selected ? tones.accent : ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: selected ? tones.accent : ink.withValues(alpha: 0.4), width: 2),
      ),
      child: selected ? Icon(Icons.check_rounded, size: 20, color: tones.onAccent) : null,
    );
  }
}

/// Fotoğrafın karta nasıl tutturulduğu: bant ya da iğne, hafif bir eğim.
/// Kayıt kimliğinden türetilir; her açılışta aynı kart aynı görünür.
class PinStyle {
  const PinStyle({required this.corners, required this.angle, required this.shift, required this.tapeAngle});

  /// true: iki üst köşede çapraz bant; false: üst ortada tek bant.
  final bool corners;

  /// Baskının eğimi (radyan).
  final double angle;

  /// Yatayda küçük kayma, hepsi aynı yerde durmasın.
  final double shift;
  final double tapeAngle;
}

/// Karta yapıştırılmış fotoğraf: beyaz kenarlı bir baskı (alt kenarı biraz
/// kalın), hafif eğik, gölgeli; üstünde yarı saydam kağıt bant.
/// Düzenleyicideki kartın başlığı: adın kendisi, yerinde yazılır. Kartın
/// başlığıyla aynı yazı; altında ince bir çizgi yazılabildiğini söyler.
class _TitleField extends StatelessWidget {
  const _TitleField({
    required this.controller,
    required this.style,
    required this.ink,
    this.hint,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final TextStyle? style;
  final Color ink;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    InputBorder line(double alpha) => UnderlineInputBorder(borderSide: BorderSide(color: ink.withValues(alpha: alpha)));
    // Görünür etiket yok (kartın başlığı); ekran okuyucu "Ad" desin.
    return Semantics(
      label: s.name,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onTapOutside: dismissKeyboard,
        maxLines: 1,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted?.call(),
        style: style,
        cursorColor: ink,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.only(bottom: 4),
          hintText: hint,
          hintStyle: style?.copyWith(color: ink.withValues(alpha: 0.38)),
          border: line(0.22),
          enabledBorder: line(0.22),
          focusedBorder: line(0.6),
        ),
      ),
    );
  }
}

class PinnedPhoto extends StatelessWidget {
  const PinnedPhoto({super.key, required this.file, required this.style});

  final File file;
  final PinStyle style;

  static PinStyle styleFor(String id) {
    final h = id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final degrees = (h % 9) - 4; // -4..+4
    return PinStyle(
      corners: (h >> 4).isEven,
      angle: (degrees == 0 ? 2 : degrees) * math.pi / 180,
      shift: ((h >> 8) % 3) * 6.0,
      tapeAngle: (((h >> 12) % 7) - 3) * math.pi / 180,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final print = Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 5, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F5F0),
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(color: Color(0x4D000000), blurRadius: 10, offset: Offset(2, 6)),
              BoxShadow(color: Color(0x26000000), blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              alignment: const Alignment(0, -0.15),
              cacheWidth: c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : null,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFD9D6CF)),
            ),
          ),
        );
        return Transform.rotate(
          angle: style.angle,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: print),
              if (style.corners) ...[
                Positioned(top: -6, left: -12, child: _Tape(width: 44, angle: -0.72)),
                Positioned(top: -6, right: -12, child: _Tape(width: 44, angle: 0.72)),
              ] else
                Positioned(
                  top: -9,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _Tape(width: math.min(64, c.maxWidth * 0.55), angle: style.tapeAngle),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Fotoğrafı olmayan klasörün kapağı: içindeki kayıtların fotoğrafları, klasöre
/// konmuş birkaç baskı gibi üst üste (en çok [InventoryStore.coverSize]).
/// Klasörün kendi fotoğrafından ayırt edilsin diye bantsız ve daha küçük:
/// "bu klasörün resmi" değil, "içinde bunlar var".
class FolderCover extends StatelessWidget {
  const FolderCover({super.key, required this.files, required this.seed});

  final List<File> files;

  /// Kaydın kimliği: baskıların duruşu klasörden klasöre biraz değişir ama
  /// aynı klasörde hep aynıdır.
  final String seed;

  /// Kapaktaki fotoğrafların cihazda duran dosyaları. Fotoğrafı henüz
  /// gelmemiş (ortak kullanımda çekilmeyi bekleyen) kayıt atlanır.
  static List<File> filesOf(InventoryStore store, Node folder) {
    final nodes = store.coverOf(folder.id);
    if (nodes.isEmpty) return const <File>[];
    return [for (final n in nodes) ?AppPaths.imageFile(n.imagePath)];
  }

  // (yatay yer, dikey yer, açı°): arkadan öne.
  static const _one = [(0.15, 0.0, -4.0)];
  static const _two = [(-1.0, -0.8, -8.0), (1.0, 0.9, 6.0)];
  static const _three = [(-1.0, -0.9, -9.0), (1.0, -0.15, 7.0), (-0.35, 1.0, -2.0)];

  @override
  Widget build(BuildContext context) {
    final n = math.min(files.length, 3);
    if (n == 0) return const SizedBox.shrink();
    final spread = n == 1 ? _one : (n == 2 ? _two : _three);
    final size = n == 1 ? 0.74 : (n == 2 ? 0.66 : 0.6);
    // Yarısı sağa, yarısı sola yaslı: bütün klasörler aynı görünmesin.
    final flip = seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff).isEven ? 1.0 : -1.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < n; i++)
          Align(
            alignment: Alignment(spread[i].$1 * flip, spread[i].$2),
            child: FractionallySizedBox(
              widthFactor: size,
              heightFactor: size,
              child: Transform.rotate(
                angle: spread[i].$3 * flip * math.pi / 180,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F5F0),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(1, 3))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1.5),
                    child: Image(
                      // Sabit genişlik: aynı fotoğraf her kartta aynı önbellek kaydını kullanır.
                      image: ResizeImage(FileImage(files[i]), width: 256),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFD9D6CF)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Liste satırında klasörün kapağı: telefonun ana ekranındaki klasör simgesi
/// gibi küçük bir ızgara. Üç gözde içindekilerin fotoğrafları, dördüncüde
/// klasörün kendi simgesi (kullanıcının seçtiği simge kaybolmasın).
class FolderMosaic extends StatelessWidget {
  const FolderMosaic({
    super.key,
    required this.files,
    required this.glyph,
    required this.ink,
    required this.cardColor,
  });

  final List<File> files;
  final IconData glyph;
  final Color ink;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(4.5);
    Widget cell(int i) => Expanded(
          child: i < files.length
              ? ClipRRect(
                  borderRadius: corner,
                  child: Image(
                    // Karttaki küçük karelerle (bkz. [_Pip]) aynı önbellek kaydı.
                    image: ResizeImage(FileImage(files[i]), width: 96),
                    fit: BoxFit.cover,
                    height: double.infinity,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => ColoredBox(color: ink.withValues(alpha: 0.07)),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(color: ink.withValues(alpha: 0.07), borderRadius: corner),
                  child: const SizedBox.expand(),
                ),
        );
    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: ink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
      child: Column(
        children: [
          Expanded(child: Row(children: [cell(0), const SizedBox(width: 2), cell(1)])),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                cell(2),
                const SizedBox(width: 2),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: ink, borderRadius: corner),
                    child: Center(child: Icon(glyph, size: 11, color: cardColor)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yarı saydam kağıt bant; kenarları hafif açık.
class _Tape extends StatelessWidget {
  const _Tape({required this.width, required this.angle});

  final double width;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: Container(
          width: width,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xB8EFE6CC),
            border: Border.symmetric(vertical: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
        ),
      );
}

/// Kartın notu. Fiş kartında yazı satır çizgilerinin üstüne oturur (satır
/// yüksekliği çizgi aralığıyla aynı); klasörde başlığın altında sade.
/// Kaç satır sığıyorsa o kadar, gerisi "…".
class _NoteArea extends StatelessWidget {
  const _NoteArea({
    required this.note,
    required this.ink,
    required this.ruled,
    required this.topGap,
    required this.right,
  });

  final String? note;
  final Color ink;
  final bool ruled;

  /// Üst satırın altından ilk not satırına kadar boşluk (fiş kartında başlık
  /// çizgisine denk gelsin diye).
  final double topGap;

  /// Sağda fotoğrafa bırakılan pay.
  final double right;

  static const double lineHeight = 24;

  @override
  Widget build(BuildContext context) {
    final text = note?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final gap = ruled ? topGap.clamp(0.0, 40.0) : 8.0;
      final lines = ((c.maxHeight - gap - 6) / lineHeight).floor();
      if (lines < 1) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: gap, right: right.clamp(0.0, c.maxWidth * 0.6)),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            text,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(fontSize: 13.5, height: lineHeight / 13.5, forceStrutHeight: true),
            style: TextStyle(
              fontSize: 13.5,
              height: lineHeight / 13.5,
              color: ink.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    });
  }
}

/// Kartın üstüne basılmış küçük damga: tükenen sarf malzemesinde
/// "Tükendi", azalanda "Azaldı", yeri dolan klasörde "Dolu".
/// Kâğıt rengi damga (emanetteki kişinin adı). Kart koyu temada da açık renkte kalır; temanın `raised`'ı koyu
/// temada `29251F` olup koyu mürekkeple birlikte adı okunmaz yapıyordu. Damga kartın üstünde: rengi temadan değil.
const _paperStamp = Color(0xFFEDE7DC);

/// Kırmızı damga (tarihi geçti, geç kaldı), beyaz yazıyla: açık temanın `danger`'ı. Koyu temanın açık kırmızısı
/// (`F0877A`) beyaz yazıyla 2,5:1 kalıyordu.
const _dangerStamp = Color(0xFFC0392B);

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, this.color, this.ink});

  final String label;

  /// Varsayılan kiremit; son kullanma uyarısında hardal ya da kırmızı.
  final Color? color;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color ?? tones.accent, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(
          color: ink ?? tones.onAccent,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Eşya adedi: − adet +. Dokunuşla bir azalır ya da artar; 0'ın altına inmez,
/// 0'da kayıt silinmez. [onChanged] yoksa (ör. önizleme) yalnızca adet yazar.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.id,
    required this.quantity,
    this.unit,
    required this.ink,
    required this.background,
    required this.onChanged,
    this.onTypeQuantity,
  });

  /// Kaydın kimliği: sayının kıpırdaması yalnızca **aynı** kaydın adedi
  /// değişince olsun (liste yeniden dizilince bu yere başka kayıt gelebilir).
  final String id;
  final int quantity;
  final String? unit;
  final Color ink;
  final Color background;
  final ValueChanged<int>? onChanged;
  final VoidCallback? onTypeQuantity;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final onChanged = this.onChanged;
    Widget step(IconData icon, String tip, int delta, bool enabled) => Tooltip(
          message: tip,
          child: InkWell(
            customBorder: const CircleBorder(),
            // Pasifken de dokunuşu kendisi karşılar; yoksa karta geçip seçenekleri
            // açıyordu.
            onTap: onChanged == null
                ? null
                : !enabled
                    ? () {}
                    : () {
                        HapticFeedback.selectionClick();
                        onChanged(quantity + delta);
                      },
            child: SizedBox(
              width: 38,
              height: 40,
              child: Icon(icon, size: 20, color: enabled ? background : background.withValues(alpha: 0.35)),
            ),
          ),
        );
    return Material(
      color: ink,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onChanged != null) step(Icons.remove_rounded, s.decrease, -1, quantity > 0),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: onChanged == null ? 14 : 2),
            child: SizedBox(
              height: 40,
              child: Center(
                // − / + dokunuşunun karşılığı: sayı kısa bir an büyüyüp yerine oturur;
                // dokunulursa doğrudan sayı girme penceresi açılır.
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTypeQuantity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Entrance(
                      key: ValueKey(id),
                      trigger: quantity,
                      scale: 1.32,
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        unit != null ? '$quantity $unit' : '$quantity',
                        style: TextStyle(
                          fontFamily: kDisplayFont,
                          fontSize: unit != null ? 14.5 : 19,
                          fontWeight: FontWeight.w600,
                          color: background,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onChanged != null) step(Icons.add_rounded, s.increase, 1, true),
        ],
      ),
    );
  }
}

/// Sürüklenen kartın gireceği yeri gösteren kiremit çizgi.
class _InsertLine extends StatelessWidget {
  const _InsertLine();

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    // Kağıt renkli ince kenar: kiremit çizgi, kiremite yakın kart renklerinin
    // üstünde de seçilsin.
    final edge = BorderSide(color: tones.paper, width: 1.4);
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: tones.accent,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(edge),
          ),
        ),
        Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: tones.accent,
              borderRadius: BorderRadius.circular(3),
              border: Border.fromBorderSide(edge),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kartın üst satırındaki bir öğe: tür simgesiyle (34) aynı yükseklikte
/// ortalanır.
class _RowSlot extends StatelessWidget {
  const _RowSlot({required this.child, this.left = 0});

  final Widget child;
  final double left;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: left),
        child: SizedBox(height: 34, child: Center(child: child)),
      );
}

/// Klasör silüeti: sol üstte bir sekme, üst kenarın geri kalanı biraz aşağıda.
class FolderBorder extends OutlinedBorder {
  const FolderBorder({this.radius = 24, super.side, this.notch = drop, this.tab, this.slope = 22});

  final double radius;

  /// Sekmenin dışındaki üst kenarın ne kadar aşağıda olduğu.
  static const double drop = 11;

  /// Bu biçimde üst kenarın inişi (kartta [drop]; liste satırında daha sığ).
  final double notch;

  /// Sekmenin eni. null: genişliğin %42'si (kart); satırda simgenin üstü kadar.
  final double? tab;

  /// Sekmeden gövdeye inişin yatay uzunluğu.
  final double slope;

  Path _path(Rect rect) {
    final r = radius.clamp(0.0, rect.shortestSide / 2);
    final top = rect.top;
    final lowTop = top + notch;
    final tabEnd = rect.left + (tab ?? (rect.width * 0.42).clamp(110.0, 230.0));
    final slope = this.slope;
    return Path()
      ..moveTo(rect.left, top + r)
      ..arcToPoint(Offset(rect.left + r, top), radius: Radius.circular(r))
      ..lineTo(tabEnd - slope, top)
      // Sekmeden gövdeye yumuşak iniş.
      ..cubicTo(
        tabEnd - slope * 0.35,
        top,
        tabEnd - slope * 0.55,
        lowTop,
        tabEnd,
        lowTop,
      )
      ..lineTo(rect.right - r, lowTop)
      ..arcToPoint(Offset(rect.right, lowTop + r), radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r),
      )
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  FolderBorder _with({double? radius, required BorderSide side}) =>
      FolderBorder(radius: radius ?? this.radius, side: side, notch: notch, tab: tab, slope: slope);

  @override
  FolderBorder copyWith({BorderSide? side}) => _with(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _with(radius: radius * t, side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is FolderBorder
      ? _with(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is FolderBorder
      ? _with(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is FolderBorder &&
      other.radius == radius &&
      other.side == side &&
      other.notch == notch &&
      other.tab == tab &&
      other.slope == slope;

  @override
  int get hashCode => Object.hash(radius, side, notch, tab, slope);
}

/// Klasörün içindekilerden ilk birkaçı: renkleri ya da fotoğrafları.
class _InsidePreview extends StatelessWidget {
  const _InsidePreview({required this.nodes, required this.ink});

  final List<Node> nodes;
  final Color ink;

  static const _pip = 30.0; // 24 + aralık
  static const _more = 42.0; // "+N" rozeti

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final room = c.maxWidth.isFinite ? c.maxWidth : 5 * _pip;
      var shown = (room / _pip).floor().clamp(0, 5);
      if (nodes.length > shown) shown = ((room - _more) / _pip).floor().clamp(0, 5);
      final extra = nodes.length - shown;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final n in nodes.take(shown))
            Padding(padding: const EdgeInsets.only(right: 6), child: _Pip(node: n, ink: ink)),
          if (extra > 0)
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$extra',
                style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 11.5),
              ),
            ),
        ],
      );
    });
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.node, required this.ink});

  final Node node;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final image = AppPaths.imageFile(node.imagePath);
    final color = nodeTone(context, node);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ink.withValues(alpha: 0.16)),
        image: image == null
            ? null
            : DecorationImage(image: ResizeImage(FileImage(image), width: 96), fit: BoxFit.cover),
      ),
      child: image != null
          ? null
          : Icon(nodeGlyph(node), size: 12, color: onColorOf(color).withValues(alpha: 0.8)),
    );
  }
}

/// Klasörün sorumlularının baş harfleri; ortak kullanımda kimin
/// ilgilendiği bir bakışta görünsün.
class _ManagerAvatars extends StatelessWidget {
  const _ManagerAvatars({required this.ids, required this.ring});

  final List<String> ids;

  /// Kartın rengi: baş harfler üst üste binince kart rengiyle ayrılır.
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.maybeOf(context);
    final s = InventoryScope.of(context).strings;
    final names = [for (final id in ids) sharing?.memberName(id) ?? s.someone];
    return Tooltip(
      message: s.managersLabel(names.join(', ')),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, name) in names.take(3).indexed)
            Align(
              widthFactor: i == 0 ? 1 : 0.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: NameAvatar(name: name, radius: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kayıp eşyanın işareti: hardal renkli soru rozeti.
class LostBadge extends StatelessWidget {
  const LostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: tones.lost,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      ),
      child: const Icon(Icons.question_mark_rounded, size: 14, color: kInk),
    );
  }
}

/// Onay bekleyen değişiklik işareti (kartta ve listelerde).
class PendingDot extends StatelessWidget {
  const PendingDot({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Tones.of(context).accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
        ),
      );
}

/// Kart üzerindeki yuvarlak düğme. ⋯ kağıda gömülü ve sakin; + mürekkeple
/// dolu, kartın ana eylemi.
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.ink,
    required this.background,
    required this.onTap,
    this.tooltip,
    this.filled = false,
  });

  final IconData icon;
  final Color ink;
  final Color background;
  final VoidCallback onTap;
  final String? tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final size = filled ? 40.0 : 34.0;
    final button = Material(
      color: filled ? ink : ink.withValues(alpha: 0.07),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: filled ? 22 : 20,
            color: filled ? background : ink.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Sürüklerken parmağın ucunda duran küçük kart.
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.node, this.moved});

  final Node node;

  /// Parmak kıpırdadı mı: üstteki ipucu buna göre ne olacağını söyler.
  final ValueListenable<bool>? moved;

  /// Parmağın kartın ortasında durması için sürükleme çapası.
  static const anchor = Offset(DragChip.width / 2, _hintSpace + 48);
  static const double width = 250;
  static const double _hintSpace = 46;

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    final moved = this.moved;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _hintSpace,
            child: moved == null
                ? null
                : Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: moved,
                      builder: (context, m, _) => _HintBubble(
                        icon: m ? Icons.open_with_rounded : Icons.touch_app_rounded,
                        text: m ? s.dragHintMoving : s.dragHintStill,
                      ),
                    ),
                  ),
          ),
          _chip(context),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context) {
    final color = nodeTone(context, node);
    final ink = onColorOf(color);
    final tones = Tones.of(context);
    final image = AppPaths.imageFile(node.imagePath);
    final label = InventoryScope.of(context).nameOf(node);
    return Transform.rotate(
      angle: -0.05,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 176,
          height: 96,
          decoration: ShapeDecoration(
            color: color,
            shape: NodeCard.cardShape(node.kind),
            shadows: [
              BoxShadow(
                color: tones.shadow.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Positioned(
                  right: 10,
                  top: 18,
                  width: 50,
                  height: 58,
                  child: PinnedPhoto(file: image, style: PinnedPhoto.styleFor(node.id)),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, node.isContainer ? 16 : 12, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GlyphChip(kind: node.kind, glyph: nodeGlyph(node), ink: ink, cardColor: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kDisplayFont,
                          color: ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          height: 1.15,
                        ),
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
  }
}

/// Sürüklerken kartın üstünde duran kısa açıklama.
class _HintBubble extends StatelessWidget {
  const _HintBubble({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Material(
      color: tones.ink,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tones.paper),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tones.paper, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste görünümündeki satır: kartın sıkıştırılmış hali. Rengi, simgesi ve
/// damgaları kartla aynı; not ve fotoğraf baskısı yok (fotoğraf küçük resim
/// olur). Kalabalık bir klasörde aranan şey bir bakışta görünsün diye ekrana
/// destedekinin iki katına yakın kayıt sığar.
class NodeRow extends StatelessWidget {
  const NodeRow({
    super.key,
    required this.node,
    this.subtitle,
    this.highlight = false,
    this.onMore,
    this.onQuantity,
    this.selected,
  });

  final Node node;
  final String? subtitle;
  final bool highlight;
  final VoidCallback? onMore;
  final ValueChanged<int>? onQuantity;
  final bool? selected;

  static const double height = 58;
  static const double radius = 16;

  /// Klasör satırında üst kenarın sekmenin dışında kalan kısmı bu kadar aşağıda.
  static const double folderNotch = 6;

  /// Satırın dış biçimi. Klasör satırı küçük bir klasör: simgenin üstünde sekme,
  /// gerisinde üst kenar biraz aşağıda (karttaki silüetin sığ hali). Listede
  /// klasörle eşya yalnızca soldaki simgeyle ayrılıyordu; bir bakışta seçilmiyordu.
  static ShapeBorder rowShape(NodeKind kind, {BorderSide side = BorderSide.none}) => kind == NodeKind.container
      ? FolderBorder(radius: radius, side: side, notch: folderNotch, tab: 66, slope: 16)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = nodeTone(context, node);
    final ink = onColorOf(color);
    final soft = ink.withValues(alpha: 0.62);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final image = AppPaths.imageFile(node.imagePath);
    final marked = highlight || selected == true;

    // Satırda tek damgaya yer var: en önemlisi yazar (kartta hepsi durur).
    final stamp = _mainStamp(store, node, tones);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    // Fotoğrafı olmayan klasör: içindekilerin fotoğrafları (bkz. [FolderMosaic]).
    final cover = image == null && node.isContainer && selected == null
        ? FolderCover.filesOf(store, node)
        : const <File>[];

    final Widget leading = selected != null
        ? _SelectChip(selected: selected!, ink: ink)
        : image == null
            ? cover.isNotEmpty
                ? FolderMosaic(files: cover, glyph: nodeGlyph(node), ink: ink, cardColor: color)
                : _GlyphChip(kind: node.kind, glyph: nodeGlyph(node), ink: ink, cardColor: color)
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image(
                      image: ResizeImage(FileImage(image), width: 126),
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _GlyphChip(kind: node.kind, glyph: nodeGlyph(node), ink: ink, cardColor: color),
                    ),
                  ),
                  // Fotoğraflı klasör eşyayla karışmasın: köşede klasör işareti.
                  if (node.isContainer)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color, width: 1.5),
                        ),
                        child: Icon(nodeGlyph(node), size: 10, color: color),
                      ),
                    ),
                ],
              );

    // Satır sabit boyda: telefonun yazı boyutu çok büyütülmüşse yazı satırdan
    // taşmasın diye büyütme burada 1,3 katla sınırlanır.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kFixedTextScale,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: height,
      decoration: ShapeDecoration(
        color: color,
        shape: rowShape(
          node.kind,
          side: marked
              ? BorderSide(color: tones.accent, width: 2.5)
              : BorderSide(color: ink.withValues(alpha: dark ? 0.0 : 0.07)),
        ),
        shadows: [
          BoxShadow(
            color: tones.shadow.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          if (marked) BoxShadow(color: tones.accent.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.only(left: 8, right: 6),
      // Klasörde gövdenin üstü alçak: içerik gövdede ortalı dursun diye biraz
      // aşağıda çizilir (yerleşim aynı kalır; pay bırakmak büyük yazıda taşırıyordu).
      child: Transform.translate(
        offset: Offset(0, node.isContainer ? folderNotch / 3 : 0),
        child: Row(
        children: [
          SizedBox(width: 42, height: 42, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        store.nameOf(node),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(color: ink, fontSize: 16.5, height: 1.2),
                      ),
                    ),
                    if (store.isFavorite(node.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Icon(Icons.star_rounded, size: 15, color: tones.accent),
                      ),
                    if (store.isPrivate(node.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Icon(Icons.lock_rounded, size: 13, color: soft),
                      ),
                    if (store.hasPendingMark(node.id))
                      const Padding(padding: EdgeInsets.only(left: 6), child: PendingDot(size: 10)),
                  ],
                ),
                if (stamp != null || node.hasAttachments || hasSubtitle)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LayoutBuilder(builder: (context, box) {
                      final clip = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file_rounded, size: 13, color: soft),
                          Text(
                            '${node.attachments.length}',
                            style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      );
                      final small = stamp == null
                          ? null
                          : Transform.scale(scale: 0.86, alignment: Alignment.centerLeft, child: stamp);
                      // Çok dar yerde (dar ekran, adet düğmesinin yanı) hepsi sığmaz:
                      // en önemlisi kalır (damga, yoksa ek sayısı), o da gerekirse küçülür.
                      if (box.maxWidth < 96) {
                        if (small == null && !node.hasAttachments) {
                          return Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                          );
                        }
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: small ?? clip),
                        );
                      }
                      return Row(
                        children: [
                          if (small != null) ...[
                            Flexible(
                              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: small),
                            ),
                            const SizedBox(width: 2),
                          ],
                          if (node.hasAttachments) ...[clip, const SizedBox(width: 6)],
                          if (hasSubtitle)
                            Flexible(
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
              ],
            ),
          ),
          if (node.isLost) const Padding(padding: EdgeInsets.only(left: 6), child: LostBadge()),
          if (!node.isContainer && node.tracksQuantity)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _QuantityStepper(
                id: node.id,
                quantity: node.quantity!,
                unit: node.unit,
                ink: ink,
                background: color,
                onChanged: onQuantity,
                onTypeQuantity: onQuantity != null ? () => NodeActions.promptQuantity(context, node) : null,
              ),
            ),
          if (onMore != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _CardButton(
                icon: Icons.more_horiz_rounded,
                ink: ink,
                background: color,
                tooltip: s.options,
                onTap: onMore!,
              ),
            ),
        ],
        ),
      ),
      ),
    );
  }
}

/// Dar yüzeyde (liste satırı, ızgara karosu) tek damgaya yer var: en önemlisi.
/// Tarihi geçen > yaklaşan > tükenen > azalan > dolu klasör.
Widget? _mainStamp(InventoryStore store, Node node, Tones tones) {
  final s = store.strings;
  final expiry = store.expiryOf(node);
  if (expiry == ExpiryState.expired) {
    final partly = node.hasLots && !dateOnly(DateTime.now()).isAfter(node.lastExpiry!)
        ? expiredUnits(node, DateTime.now())
        : 0;
    return _Stamp(
      label: partly > 0 ? s.someExpired(partly) : s.expiredShort,
      color: _dangerStamp,
      ink: Colors.white,
    );
  }
  if (node.isBorrowOverdue) {
    return _Stamp(label: s.borrowOverdueShort, color: _dangerStamp, ink: Colors.white);
  }
  if (expiry == ExpiryState.soon) return _Stamp(label: s.expiringShort, color: tones.lost, ink: kInk);
  if (node.isBorrowed) {
    return _Stamp(label: s.borrowedToStamp(node.borrowedTo!), color: _paperStamp, ink: kInk);
  }
  if (node.quantity == 0 && !node.isContainer) return _Stamp(label: s.outOfStock);
  if (node.isLow && !node.isContainer) return _Stamp(label: s.lowStockShort, color: tones.lost, ink: kInk);
  if (node.isContainer && node.isFull) return _Stamp(label: s.fullShort);
  return null;
}

/// Izgara görünümünde bir kayıt: üstte fotoğraf (kare), altında adı. Fotoğrafı
/// olan envanterde aranan şey adından önce resminden bulunur; ekrana destenin
/// birkaç katı kayıt sığar. Kartın bütün bilgisi yok: tek damga (en önemlisi),
/// adet ve ⋯. Gerisi dokununca açılan kartta.
///
/// Klasör karosu klasör silüetindedir; fotoğrafı yoksa içindekilerin
/// fotoğraflarını gösterir (bkz. [FolderCover.filesOf]).
class NodeTile extends StatelessWidget {
  const NodeTile({super.key, required this.node, this.highlight = false, this.onMore, this.selected});

  final Node node;
  final bool highlight;
  final VoidCallback? onMore;
  final bool? selected;

  /// Resmin altındaki ad şeridinin boyu (iki satır ad sığar).
  static const double labelHeight = 40;
  static const double radius = 16;
  static const double folderNotch = 7;

  static ShapeBorder tileShape(NodeKind kind, {BorderSide side = BorderSide.none}) => kind == NodeKind.container
      ? FolderBorder(radius: radius, side: side, notch: folderNotch, tab: 54, slope: 14)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = nodeTone(context, node);
    final ink = onColorOf(color);
    final soft = ink.withValues(alpha: 0.62);
    final store = InventoryScope.of(context);
    final image = AppPaths.imageFile(node.imagePath);
    final cover = image == null && node.isContainer ? FolderCover.filesOf(store, node) : const <File>[];
    final marked = highlight || selected == true;
    final stamp = _mainStamp(store, node, tones);
    final glyph = nodeGlyph(node);

    Widget blank() => ColoredBox(
          color: ink.withValues(alpha: 0.06),
          child: Center(child: Icon(glyph, size: 34, color: ink.withValues(alpha: 0.5))),
        );
    Widget photo(File file, int width) => Image(
          image: ResizeImage(FileImage(file), width: width),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => blank(),
        );
    // Klasörün içindekiler: bir, iki (yan yana) ya da üç (biri büyük) fotoğraf.
    final Widget picture = image != null
        ? photo(image, 320)
        : switch (cover.length) {
            0 => blank(),
            1 => photo(cover[0], 256),
            2 => Row(
                children: [
                  Expanded(child: photo(cover[0], 256)),
                  const SizedBox(width: 2),
                  Expanded(child: photo(cover[1], 256)),
                ],
              ),
            _ => Row(
                children: [
                  Expanded(flex: 3, child: photo(cover[0], 256)),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Expanded(child: photo(cover[1], 256)),
                        const SizedBox(height: 2),
                        Expanded(child: photo(cover[2], 256)),
                      ],
                    ),
                  ),
                ],
              ),
          };
    final pictured = image != null || cover.isNotEmpty;

    // Karo sabit boyda: yazı büyütmesi sınırlı (bkz. kFixedTextScale).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kFixedTextScale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: ShapeDecoration(
          color: color,
          shape: tileShape(
            node.kind,
            side: marked
                ? BorderSide(color: tones.accent, width: 2.5)
                : BorderSide(color: ink.withValues(alpha: dark ? 0.0 : 0.07)),
          ),
          shadows: [
            BoxShadow(color: tones.shadow.withValues(alpha: dark ? 0.35 : 0.08), blurRadius: 6, offset: const Offset(0, 2)),
            if (marked) BoxShadow(color: tones.accent.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(5, 5 + (node.isContainer ? folderNotch : 0), 5, 0),
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(11), child: picture),
                      // Sol üst: seçim işareti ya da en önemli damga.
                      if (selected != null)
                        Positioned(left: 5, top: 5, child: _SelectChip(selected: selected!, ink: pictured ? kInk : ink))
                      else if (stamp != null)
                        Positioned(
                          left: 5,
                          top: 5,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: math.max(20, box.maxWidth - 46)),
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: stamp),
                          ),
                        ),
                      // Fotoğraflı klasör eşyayla karışmasın: köşede klasörün simgesi.
                      if (node.isContainer && pictured)
                        Positioned(
                          left: 5,
                          bottom: 5,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: ink,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: color, width: 1.5),
                            ),
                            child: Icon(glyph, size: 13, color: color),
                          ),
                        ),
                      // Adet: yalnızca sayı (− / + dokununca açılan kartta).
                      if (!node.isContainer && node.tracksQuantity)
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ink,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color, width: 1.5),
                            ),
                            child: Text(
                              '${node.quantity}',
                              style: TextStyle(
                                fontFamily: kDisplayFont,
                                fontSize: 13,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      if (onMore != null)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Tooltip(
                            message: store.strings.options,
                            child: Material(
                              // Fotoğrafın üstünde de seçilsin: kart renginde dolu daire.
                              color: color.withValues(alpha: 0.9),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onMore,
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(Icons.more_horiz_rounded, size: 19, color: ink.withValues(alpha: 0.85)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: labelHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        store.nameOf(node),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ink, fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (node.isLost) const Padding(padding: EdgeInsets.only(left: 4), child: LostBadge()),
                    if (store.isFavorite(node.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(Icons.star_rounded, size: 14, color: tones.accent),
                      ),
                    if (store.isPrivate(node.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(Icons.lock_rounded, size: 12, color: soft),
                      ),
                    if (store.hasPendingMark(node.id))
                      const Padding(padding: EdgeInsets.only(left: 4), child: PendingDot(size: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Karti etkilesimli hale getirir: dokunma, uzun basma, sürükleme ve
/// klasörlerde bırakma hedefi olma.
class NodeCardTile extends StatefulWidget {
  const NodeCardTile({
    super.key,
    required this.node,
    required this.focus,
    required this.onTap,
    required this.onMore,
    required this.onDropped,
    this.onHoverOpen,
    this.onPlus,
    this.subtitle,
    this.onQuantity,
    this.index = 0,
    this.orderParent,
    this.onOrder,
    this.peek = 96,
    this.selected,
    this.dense = false,
    this.grid = false,
    this.focusOf,
  });

  final Node node;
  final double focus;

  /// Destede kaydırdıkça değişen odak (bkz. [NodeCard.focusOf]); verilirse
  /// [focus] yerine bu geçerlidir.
  final ValueListenable<double>? focusOf;
  final VoidCallback onTap;

  /// Izgara görünümü: kart yerine [NodeTile]. Sarmalayıcılar yine aynı; ama
  /// kayıtlar yan yana durduğu için sıralama sol/sağ yarıya göre yapılır ve
  /// yana kaydırma eylemsizdir (dar karoda kısa bir fiske çöpe atardı).
  final bool grid;

  /// Liste görünümü: kart yerine [NodeRow]. Dokunma, sürükleme, yana kaydırma,
  /// bırakma hedefi olma aynı; yalnızca görünen şey değişir.
  final bool dense;

  /// Toplu seçim açıksa kartın seçili olup olmadığı; null ise seçim kapalı.
  /// Seçim açıkken dokunmak seçer, sürükleme ve yana kaydırma çalışmaz.
  final bool? selected;

  /// Kartın destedeki sırası; kenarına bırakılan kart bu sıraya girer.
  final int index;

  /// Sıralamanın yapılacağı seviye. null ise bu destede sıralama yok
  /// (sık kullanılanlar, kayıp çekmecesi).
  final String? orderParent;

  /// Kart bu kartın kenarına bırakıldı: verilen sıraya koy.
  final Future<void> Function(String droppedId, int index)? onOrder;

  /// Destede kartın görünen şeridinin yüksekliği: odaktaki kart tümüyle
  /// görünür, ötekilerin altını sonraki kart örter. Sürüklerken hangi kartın
  /// hedef olduğu buna göre belirlenir.
  final double peek;

  /// Adet tutulan eşyada − / +.
  final ValueChanged<int>? onQuantity;

  /// Kartın ⋯ düğmesi: seçenekler. Uzun basmak yalnızca taşıma başlatır.
  final VoidCallback onMore;

  /// Bu klasörün üzerine baska bir kart birakildi.
  final Future<void> Function(String droppedId) onDropped;

  /// Klasör üzerinde bir sure beklenince içine girilir. null ise
  /// (orn. çekmecede) yalnızca dogrudan bırakma çalışır.
  final void Function(Node container)? onHoverOpen;

  final VoidCallback? onPlus;
  final String? subtitle;

  @override
  State<NodeCardTile> createState() => _NodeCardTileState();
}

/// Sürüklenen kart bu kartın önüne mi arkasına mı girecek.
enum _InsertSide { before, after }

class _NodeCardTileState extends State<NodeCardTile> {
  Offset? _dragStart;

  /// Kenarda bekleyen kart nereye girecek; çizgi buna göre çizilir.
  _InsertSide? _side;

  /// Basılı tutarken parmak kıpırdadı mı; kartın üstündeki ipucu değişir.
  final ValueNotifier<bool> _moved = ValueNotifier(false);
  Timer? _hoverTimer;
  bool _hovering = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _moved.dispose();
    super.dispose();
  }

  bool _canAccept(String draggedId) {
    if (!widget.node.isContainer) return false;
    return InventoryScope.read(context).canMove(draggedId, widget.node.id);
  }

  /// Sürüklenen kart bu kartın yanına sıralanabilir mi? Klasör ve eşyalar
  /// ayrı gruplanıyorsa kart yalnızca kendi grubunda sıralanır.
  bool _canOrder(String draggedId) {
    final parent = widget.orderParent;
    if (parent == null || widget.onOrder == null || draggedId == widget.node.id) return false;
    final store = InventoryScope.read(context);
    final dragged = store.byId(draggedId);
    if (dragged == null) return false;
    if (store.settings.groupKinds && dragged.isContainer != widget.node.isContainer) return false;
    return store.bucketKey(dragged) == parent || store.canMove(draggedId, parent);
  }

  /// Parmağın kart üzerindeki yeri: kartın destede görünen şeridine göre
  /// hesaplanır (altını sonraki kart örtüyorsa orası onun işi). Eşyada üst
  /// yarı önü, alt yarı arkası; klasörde ince üst/alt şerit sıralama,
  /// ortası "içine koy".
  ///
  /// Izgarada kayıtlar yan yana: aynı kural yatayda ([at] parmağın soldan
  /// uzaklığı, [extent] karonun eni).
  _InsertSide? _sideFor(double at, double extent) {
    if (!widget.node.isContainer) {
      return at < extent / 2 ? _InsertSide.before : _InsertSide.after;
    }
    final band = math.min(30.0, extent / 3.6);
    if (at <= band) return _InsertSide.before;
    if (at >= extent - band) return _InsertSide.after;
    return null;
  }

  /// Parmak kıpırdadıkça sıralama çizgisi ve "içine koy" vurgusu tazelenir.
  void _updateZone(DragTargetDetails<String> details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final at = box.globalToLocal(details.offset + DragChip.anchor);
    final dy = at.dy;
    // Odaktaki kart tümüyle görünür; ötekilerin yalnızca üst şeridi.
    final focus = widget.focusOf?.value ?? widget.focus;
    final visible = focus >= 0.5 ? box.size.height : math.min(widget.peek, box.size.height);
    final mine = dy >= -6 && dy <= visible;
    final side = mine && _canOrder(details.data)
        ? (widget.grid ? _sideFor(at.dx, box.size.width) : _sideFor(dy, visible))
        : null;
    if (side != _side && mounted) setState(() => _side = side);
    final into = mine && side == null && _canAccept(details.data);
    if (into && !_hovering) {
      setState(() => _hovering = true);
      _startHoverTimer();
    } else if (!into && _hovering) {
      _cancelHover();
    }
  }

  void _clearZone() {
    if (_side != null && mounted) setState(() => _side = null);
    _cancelHover();
  }

  void _startHoverTimer() {
    _hoverTimer?.cancel();
    final open = widget.onHoverOpen;
    if (open == null) return;
    _hoverTimer = Timer(const Duration(milliseconds: 850), () {
      // Kenarda kaydırma sürüyorsa parmak kartı seçmiş sayılmaz.
      if (mounted && _hovering && !InventoryScope.read(context).edgeScrolling) {
        open(widget.node);
      }
    });
  }

  void _cancelHover() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (_hovering && mounted) setState(() => _hovering = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final isDraggingThis = store.draggingId == widget.node.id;
    final selecting = widget.selected != null;

    final swipe = _swipeActions(store);

    final Widget card = widget.grid
        ? NodeTile(
            node: widget.node,
            highlight: _hovering,
            onMore: selecting ? null : widget.onMore,
            selected: widget.selected,
          )
        : widget.dense
        ? NodeRow(
            node: widget.node,
            subtitle: widget.subtitle,
            highlight: _hovering,
            onMore: selecting ? null : widget.onMore,
            onQuantity: selecting ? null : widget.onQuantity,
            selected: widget.selected,
          )
        : NodeCard(
            node: widget.node,
            focus: widget.focus,
            focusOf: widget.focusOf,
            subtitle: widget.subtitle,
            // Seçerken kartın kendi düğmeleri yanlışlıkla basılmasın.
            onPlus: selecting ? null : widget.onPlus,
            highlight: _hovering,
            // Yerleşimi deste yapıyor.
            margin: EdgeInsets.zero,
            onMore: selecting ? null : widget.onMore,
            onQuantity: selecting ? null : widget.onQuantity,
            selected: widget.selected,
            // Seçerken dokunuş seçimi değiştirir, fotoğrafı açmaz.
            openPhoto: !selecting,
          );

    final draggable = LongPressDraggable<String>(
      data: widget.node.id,
      delay: const Duration(milliseconds: 260),
      // Klasör üzerinde bekleyince yeni ekran açılır; surukledigimiz
      // kart Navigator'in katmaninda kalirsa altinda gomulu kalir.
      rootOverlay: true,
      // Uzun basmak taşıma modudur; kartın üstündeki ipucu ne yapılacağını söyler.
      feedback: DragChip(node: widget.node, moved: _moved),
      dragAnchorStrategy: (_, _, _) => DragChip.anchor,
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      onDragStarted: () {
        _moved.value = false;
        HapticFeedback.mediumImpact();
        store.setDragging(widget.node.id);
      },
      onDragUpdate: (d) {
        _dragStart ??= d.globalPosition;
        if (!_moved.value && (d.globalPosition - _dragStart!).distance >= 16) {
          _moved.value = true;
          HapticFeedback.selectionClick();
        }
      },
      // Kıpırdamadan bırakmak taşımayı iptal eder; seçenekler ⋯ düğmesinde.
      onDragEnd: (_) {
        store.setDragging(null);
        _dragStart = null;
      },
      onDraggableCanceled: (_, _) {
        store.setDragging(null);
        _dragStart = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: card,
      ),
    );

    // Yana kaydırma taşımanın üstünde: kısa bir fiske eylemi çalıştırır,
    // basılı tutmak taşımayı başlatır.
    final swipeable = CardSwipe(
      key: ValueKey('swipe_${widget.node.id}'),
      shape: widget.grid
          ? NodeTile.tileShape(widget.node.kind)
          : widget.dense
              ? NodeRow.rowShape(widget.node.kind)
              : NodeCard.cardShape(widget.node.kind),
      // Izgarada yana kaydırma yok (sarmalayıcı ağaçta durur, eylemsiz).
      left: selecting || widget.grid ? null : swipe.$1,
      right: selecting || widget.grid ? null : swipe.$2,
      child: selecting
          ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: card)
          : draggable,
    );

    // Her kart bırakma hedefi: klasörün ortası "içine", kenarları ise
    // sıralama. Eşyada kartın tamamı sıralamadır.
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final ok = _canOrder(details.data) || _canAccept(details.data);
        if (ok) _updateZone(details);
        return ok;
      },
      onMove: _updateZone,
      onLeave: (_) => _clearZone(),
      onAcceptWithDetails: (details) async {
        final side = _side;
        _clearZone();
        if (side != null) {
          await widget.onOrder!(
            details.data,
            side == _InsertSide.before ? widget.index : widget.index + 1,
          );
          return;
        }
        await widget.onDropped(details.data);
      },
      builder: (context, candidate, rejected) => swipeable,
    );

    // Ağacın biçimi hep aynı kalmalı: sıralama çizgisi eklenip çıkarken
    // DragTarget yeniden kurulursa sürüklemenin hedefi düşer, bırakma hiçbir
    // yere ulaşmaz.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.node.isContainer
            ? target
            : Opacity(opacity: isDraggingThis ? 0.4 : 1, child: target),
        if (_side != null && widget.grid)
          // Izgarada kayıt soluna ya da sağına girer: çizgi dikey.
          Positioned(
            top: 4,
            bottom: 4,
            left: _side == _InsertSide.before ? -8.5 : null,
            right: _side == _InsertSide.after ? -8.5 : null,
            child: const IgnorePointer(child: RotatedBox(quarterTurns: 1, child: _InsertLine())),
          )
        else if (_side != null)
          Positioned(
            left: 4,
            right: 4,
            top: _side == _InsertSide.before ? -5 : null,
            bottom: _side == _InsertSide.after ? -5 : null,
            child: const IgnorePointer(child: _InsertLine()),
          ),
      ],
    );
  }

  /// Sola kaydırınca çöp kutusu, sağa kaydırınca çekmece. Zaten çekmecede
  /// duran kart sağa kaydırılmaz (gidecek yeri yok).
  (SwipeAction, SwipeAction?) _swipeActions(InventoryStore store) {
    final s = store.strings;
    final tones = Tones.of(context);
    final node = widget.node;
    final toDrawer = store.canMove(node.id, Roots.drawer);
    return (
      SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: s.moveToTrash,
        background: tones.danger,
        foreground: Colors.white,
        onAct: () => NodeActions.trash(context, node),
      ),
      toDrawer
          ? SwipeAction(
              icon: Icons.inbox_rounded,
              label: s.drawer,
              background: tones.ink,
              foreground: tones.paper,
              onAct: () => NodeActions.toDrawer(context, node),
            )
          : null,
    );
  }
}
