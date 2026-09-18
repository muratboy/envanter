import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';

/// Kartın fotoğrafını tam ekran açar. Kartta küçük, eğik bir baskı olarak
/// duruyor; etiketi okumak ya da ayrıntıya bakmak için büyütülebilsin.
Future<void> showPhoto(BuildContext context, File file, {String? title}) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => PhotoViewer(file: file, title: title),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ),
    );

/// Siyah zeminde fotoğraf: iki parmakla büyütülür ve kaydırılır, çift dokunuş
/// dokunulan yere yakınlaşır ya da geri döner, tek dokunuş üst çubuğu gizler.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.file, this.title});

  final File file;
  final String? title;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapAt = Offset.zero;
  bool _chrome = true;

  static const double maxScale = 6;
  static const double doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      if (_zoomTween case final tween?) _transform.value = tween.value;
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    final p = _doubleTapAt;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-p.dx * (doubleTapScale - 1), -p.dy * (doubleTapScale - 1), 0, 1)
          ..scaleByDouble(doubleTapScale, doubleTapScale, 1, 1));
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOut));
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _chrome = !_chrome),
                onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                onDoubleTap: _toggleZoom,
                child: InteractiveViewer(
                  transformationController: _transform,
                  maxScale: maxScale,
                  child: SizedBox.expand(
                    child: Image.file(
                      widget.file,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Üst çubuk: kapat ve kaydın adı. Fotoğrafa bakarken gizlenebilir.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0x66000000)),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: s.close,
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
