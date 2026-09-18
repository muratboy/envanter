import '../data/library.dart';

/// Kayıtların eşitleme için damgalandığı saat. Birleştirme "son yazan
/// kazanır": saati yanlış bir telefon (elle ayarlanmış, otomatik saat kapalı)
/// değişikliği yanlış sıraya koyar, silineni geri getirebilir. Saati otomatik
/// olmayan cihaz, saati otomatik olan bir üyeyle eşitlerken aradaki farkı
/// öğrenir ve kendi değişikliklerini düzeltilmiş saatle damgalar.
///
/// Düzeltme kaynakta yapılır, gelen zamanlar alıcıda kırpılmaz: her cihaz
/// kendi saatine göre farklı kırpar, birleşme değişmeli olmaktan çıkar ve
/// eşitleme durulmazdı. Farkı öğrenmeden önce yazılan kayıtlar olduğu gibi kalır.
class SyncClock {
  /// Telefonun saati ağdan mı geliyor (Android: otomatik tarih ve saat).
  static bool trusted = true;

  /// Düzeltme (ms): saati güvenilir bir üyeninki eksi bizimki.
  static int offsetMs = 0;

  /// Bu kadarlık fark gösterilir.
  static const warnAfter = Duration(minutes: 2);

  /// Bundan küçük oynamalarda düzeltme değişmez (ağ gecikmesi).
  static const _jitter = Duration(seconds: 20);

  static DateTime now() => offsetMs == 0 ? DateTime.now() : DateTime.now().add(Duration(milliseconds: offsetMs));

  /// Açılışta ve öne gelişte: saat otomatik mi; değilse kaydedilmiş düzeltme.
  static void restore({required bool auto}) {
    trusted = auto;
    offsetMs = auto ? 0 : int.tryParse(InventoryLibrary.current?.global['clock_offset'] ?? '') ?? 0;
  }

  /// Saati güvenilir bir üyenin saatini gördük ([skewMs] = onunki − bizimki).
  /// Düzeltme değiştiyse true.
  static bool adopt(int skewMs) {
    if (trusted || (skewMs - offsetMs).abs() < _jitter.inMilliseconds) return false;
    offsetMs = skewMs;
    InventoryLibrary.current?.writeGlobals({'clock_offset': '$skewMs'});
    return true;
  }
}
