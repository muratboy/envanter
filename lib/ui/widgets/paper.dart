import 'package:flutter/material.dart';

import '../../core/app_paths.dart';
import '../../core/palette.dart';
import '../../core/strings.dart';
import '../../core/text_match.dart';
import '../../core/theme.dart';
import '../../data/node.dart';
import 'node_card.dart';

/// Sayfalardaki başlıklı panel: küçük harf aralıklı başlık, altında kağıt
/// zeminli, ince çizgili bir kutu.
class PaperSection extends StatelessWidget {
  const PaperSection({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 22, 16, 0),
  });

  final String? title;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final s = AppStrings.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.upper(title!),
                      style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: tones.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: tones.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel içinde tek satır: simge kutusu, başlık, açıklama, sağda ok ya da
/// verilen bileşen.
class PaperRow extends StatelessWidget {
  const PaperRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.tint,
    this.danger = false,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? tint;
  final bool danger;

  /// Açıklamanın altında kalın tek satır (ör. "Son yedek: 12 gün önce").
  /// Açıklamaya eklenseydi uzun açıklamada satır sınırına takılıp kayboluyordu.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final iconColor = tint ?? (danger ? tones.danger : tones.ink);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint == null && !danger ? tones.raised : iconColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: danger ? tones.danger : tones.ink,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: tones.muted, height: 1.3),
                      ),
                    ),
                  if (footnote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        footnote!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: tint ?? tones.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Padding(padding: const EdgeInsets.only(left: 8), child: trailing!)
            else if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right_rounded, color: tones.faint),
              ),
          ],
        ),
      ),
    );
  }
}

/// Panel içindeki satırlar arası ince çizgi.
class PaperDivider extends StatelessWidget {
  const PaperDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 66, endIndent: 16, color: Tones.of(context).line);
}

/// Kaydın küçük hali: fotoğrafı ya da kart rengi üstünde simgesi.
class RecordThumb extends StatelessWidget {
  const RecordThumb({super.key, required this.node, this.size = 48, this.badge});

  final Node node;
  final double size;

  /// Sağ altta küçük bir işaret (ör. değişikliğin türü).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final color = nodeTone(context, node);
    final image = AppPaths.imageFile(node.imagePath);
    final thumb = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: onColorOf(color).withValues(alpha: 0.08)),
        image: image == null
            ? null
            : DecorationImage(image: ResizeImage(FileImage(image), width: (size * 3).round()), fit: BoxFit.cover),
      ),
      child: image != null ? null : Icon(nodeGlyph(node), size: size * 0.44, color: onColorOf(color)),
    );
    if (badge == null) return thumb;
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(clipBehavior: Clip.none, children: [thumb, Positioned(right: 0, bottom: 0, child: badge!)]),
    );
  }
}

/// [text] içinde [tokens]'ın geçtiği yerler fosforlu kalemle çizilmiş gibi.
/// Kelimeler katlanmış olmalı ([searchTokens]).
TextSpan highlightedText(String text, List<String> tokens, {required TextStyle style, required Color marker}) {
  final ranges = matchRanges(text, tokens);
  if (ranges.isEmpty) return TextSpan(text: text, style: style);
  final hit = style.copyWith(backgroundColor: marker, fontWeight: FontWeight.w800);
  final parts = <TextSpan>[];
  var at = 0;
  for (final (start, end) in ranges) {
    if (start > at) parts.add(TextSpan(text: text.substring(at, start)));
    parts.add(TextSpan(text: text.substring(start, end), style: hit));
    at = end;
  }
  if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: parts);
}

/// Listelerdeki kayıt satırı (arama, çöp, görüntüyle arama).
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.node,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.highlight = const [],
    this.detail,
    this.detailIcon,
  });

  final Node node;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Aramada eşleşen kelimeler (katlanmış): başlıkta ve ayrıntıda vurgulanır.
  final List<String> highlight;

  /// Alt yazının altında ikinci satır: aranan kelimenin geçtiği not parçası
  /// ya da konum adı. Kayıt adında geçmeyen bir kelimeyle bulunduysa neden
  /// bulunduğu buradan anlaşılır.
  final String? detail;
  final IconData? detailIcon;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final marker = tones.accent.withValues(alpha: 0.22);
    return Material(
      color: tones.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: tones.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            children: [
              RecordThumb(node: node),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      highlightedText(
                        title,
                        highlight,
                        marker: marker,
                        style: TextStyle(
                          fontFamily: kDisplayFont,
                          fontSize: 17.5,
                          fontWeight: FontWeight.w600,
                          color: tones.ink,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: tones.muted, fontWeight: FontWeight.w600),
                      ),
                    if (detail != null && detail!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (detailIcon != null) ...[
                              Icon(detailIcon, size: 13, color: tones.muted),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text.rich(
                                highlightedText(
                                  detail!,
                                  highlight,
                                  marker: marker,
                                  style: TextStyle(fontSize: 12.5, color: tones.ink, height: 1.3),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Sağdaki düğmeler dar ekranda ya da büyük yazıda satırın yarısından
              // fazlasını isterse küçülür (alışveriş listesinde ✋ ✕ "Aldım").
              if (trailing != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: trailing),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
