import 'package:flutter/widgets.dart';

/// Deste kayarken gelen −/+ dokunuşu çoğu zaman kazadır: adet sessizce
/// değişiyordu. Kaydırma sürerken bu dokunuşlar yok sayılır. (Hızla kayan
/// listeyi durdurmak için dokunmayı Flutter zaten kartlara iletmez.)
class ScrollGuard {
  static bool _scrolling = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Bitiş haberi kaçarsa (liste kaydırma ortasında kapandıysa) kilit kalmasın.
  static const _stale = Duration(seconds: 1);

  static bool get busy => _scrolling && DateTime.now().difference(_last) < _stale;

  /// Uygulamanın kökünde bütün kaydırma haberlerini dinler.
  static bool observe(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    _last = DateTime.now();
    if (n is ScrollStartNotification || n is ScrollUpdateNotification && n.dragDetails != null) _scrolling = true;
    if (n is ScrollEndNotification) _scrolling = false;
    return false;
  }
}
