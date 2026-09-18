import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dokunulan kartin büyüyerek ekrani kaplamasi. Route içeriğini yeniden
/// yerleşime sokmamak için olcekleme Transform ile yapiliyor.
class ExpandRoute<T> extends PageRouteBuilder<T> {
  ExpandRoute({
    required this.sourceRect,
    required WidgetBuilder builder,
    this.barrier = false,
    Duration duration = const Duration(milliseconds: 340),
  }) : super(
          opaque: !barrier,
          barrierColor: barrier ? Colors.black54 : null,
          barrierDismissible: barrier,
          transitionDuration: duration,
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, _, _) => builder(context),
        );

  /// Kartin ekrandaki global dikdortgeni.
  final Rect sourceRect;
  final bool barrier;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.sizeOf(context);
    if (size.isEmpty) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;
        final scale = ui.lerpDouble(
          math.max(sourceRect.width / size.width, 0.2),
          1,
          t,
        )!;
        final dx = ui.lerpDouble(sourceRect.center.dx - size.width / 2, 0, t)!;
        final dy = ui.lerpDouble(sourceRect.center.dy - size.height / 2, 0, t)!;
        return Opacity(
          opacity: Curves.easeOut.transform(math.min(1, t * 2.2)),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(dx, dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Bir widget'in ekrandaki yerini olcer; ExpandRoute'un cikis noktasi.
Rect rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

/// Alttan açılan yuvarlatilmis sayfa.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: builder,
  );
}
