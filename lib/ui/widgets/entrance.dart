import 'package:flutter/material.dart';

/// İçeriği değişen bir yüzeyin kısa "belirme" hareketi: [trigger] değişince
/// çocuk hafifçe kayarak (ve/veya büyüyerek, istenirse biraz solarak) yerine
/// oturur. Eski içerik beklemez, yenisi hemen yerindedir; hareket yalnızca
/// gözü yeni içeriğe taşır.
///
/// Varsayılan yalnızca kaymadır: solma, çocuğun tamamını ayrı bir katmana
/// çizdirir. Deste gibi ağır bir yüzeyde ilk kare uzun sürünce (emülatörde
/// ölçüldü) saydam başlayan içerik boş bir kare olarak görünüyordu: anlık
/// değişimden kötü. Solma yalnızca hafif yüzeylerde (başlık yazısı, ayar
/// sayfası) ve hiçbir zaman sıfırdan başlamadan kullanılır ([fadeFrom]).
///
/// `AnimatedSwitcher` yerine bu: o, geçiş boyunca eski ve yeni çocuğu birlikte
/// ağaçta tutar (iki deste, iki takım bırakma hedefi). Burada ağacın biçimi
/// **hiç değişmez** (solma + dönüşüm sarmalayıcıları hep durur, dururken
/// etkisizdir), yani sürüklemenin bırakma hedefleri düşmez.
///
/// [enabled] kapalıyken (ör. sürükleme sürerken) ve telefonda "animasyonları
/// kaldır" açıkken içerik hareketsiz değişir.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.trigger,
    required this.child,
    this.enabled = true,
    this.offset = Offset.zero,
    this.scale = 1,
    this.fadeFrom = 1,
    this.duration = const Duration(milliseconds: 220),
  }) : assert(fadeFrom > 0 && fadeFrom <= 1);

  /// Değişince hareket başlar (seviye, görünüm, sekme, sayı...).
  final Object? trigger;
  final Widget child;
  final bool enabled;

  /// İçeriğin başladığı yer (dp); buradan yerine kayar.
  final Offset offset;

  /// İçeriğin başladığı ölçek; buradan 1'e gelir.
  final double scale;

  /// İçeriğin başladığı saydamlık (1: solma yok). Sıfır olamaz: ilk kare boş kalmasın.
  final double fadeFrom;
  final Duration duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  // İlk çizimde hareket yok: değer 1'de başlar.
  late final AnimationController _run = AnimationController(vsync: this, duration: widget.duration, value: 1);
  late final Animation<double> _eased = CurvedAnimation(parent: _run, curve: Curves.easeOutCubic);
  static const Animation<double> _opaque = AlwaysStoppedAnimation(1);

  @override
  void didUpdateWidget(Entrance old) {
    super.didUpdateWidget(old);
    _run.duration = widget.duration;
    if (old.trigger == widget.trigger) return;
    final still = !widget.enabled || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _run.value = 1;
    } else {
      _run.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moved = AnimatedBuilder(
      animation: _eased,
      builder: (context, child) {
        final t = _eased.value;
        final scale = widget.scale + (1 - widget.scale) * t;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(widget.offset.dx * (1 - t), widget.offset.dy * (1 - t), 0, 1)
            ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        );
      },
      child: widget.child,
    );
    // Solma kapalıyken de sarmalayıcı yerinde: ağacın biçimi ayara göre değişmesin.
    return FadeTransition(
      opacity: widget.fadeFrom < 1 ? _eased.drive(Tween(begin: widget.fadeFrom, end: 1)) : _opaque,
      child: moved,
    );
  }
}
