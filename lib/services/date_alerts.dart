import '../core/time_span.dart';
import '../data/node.dart';

enum DateAlertKind {
  /// Uyarı süresine girdi ("3 ay kaldı").
  expiring,

  /// Son kullanma günü.
  lastDay,

  /// Garantinin bitmesine bir ay var.
  warranty,

  /// Periyodik bakımın günü.
  service,
}

/// Bir günün bildirimi: o gün uyarılacak eşyalar. Aynı güne düşenler tek
/// bildirimde toplanır ("3 eşyanın tarihi yaklaştı: Süt, Yoğurt, Peynir").
class DateAlert {
  const DateAlert(this.day, this.items);

  /// Bildirimin günü (saat [notifyHour]).
  final DateTime day;
  /// Eşya, ne uyarısı ve hangi tarih için (paketli eşyada her paket ayrı).
  final List<(Node node, DateAlertKind kind, DateTime date)> items;

  DateTime get at => DateTime(day.year, day.month, day.day, notifyHour);
}

/// Bildirimler sabahları gelir; gece yarısı uyandırmasın.
const notifyHour = 9;

/// Garanti bitişinden bu kadar önce haber verilir.
const warrantyLead = TimeSpan(1, SpanUnit.month);

/// Önümüzdeki bildirim günleri, en yakın önce ve en fazla [maxDays] gün.
/// Android zamanlayıcıya verilecek alarm sayısı sınırlı; uzak günler, liste
/// yeniden kurulunca (her değişiklikte ve açılışta) sıraya girer.
///
/// Geçmişte kalan anlar (bugünün 09:00'u geçtiyse bugün de) atlanır: onlar
/// zaten kartta ve "Tarihi yaklaşanlar"da görünüyor.
///
/// [services]: periyodik bakımı olanlar; bakım gününde bir kez haber verilir (gecikince her gün
/// yinelenmez: "Bugün" şeridinde ve "Tarihi yaklaşanlar"da durur).
List<DateAlert> planDateAlerts(
  Iterable<Node> items, {
  Iterable<Node> services = const [],
  required TimeSpan Function(Node n) warnOf,
  required DateTime now,
  int maxDays = 30,
}) {
  final byDay = <DateTime, List<(Node, DateAlertKind, DateTime)>>{};
  void add(DateTime day, Node n, DateAlertKind kind, DateTime date) {
    final d = dateOnly(day);
    if (!DateTime(d.year, d.month, d.day, notifyHour).isAfter(now)) return;
    (byDay[d] ??= []).add((n, kind, date));
  }

  for (final n in items) {
    // Farklı tarihli paketlerin her biri ayrı haber verir.
    for (final expiry in n.expiryDates) {
      final warnDay = warnOf(n).subtractFrom(expiry);
      // Uyarı günü son güne denk gelirse (çok kısa süre) tek bildirim yeter.
      if (dateOnly(warnDay) != dateOnly(expiry)) add(warnDay, n, DateAlertKind.expiring, expiry);
      add(expiry, n, DateAlertKind.lastDay, expiry);
    }
    final warranty = n.effectiveWarrantyEnd;
    if (warranty != null) add(warrantyLead.subtractFrom(warranty), n, DateAlertKind.warranty, warranty);
  }
  for (final n in services) {
    final next = n.nextService;
    if (next != null) add(next, n, DateAlertKind.service, next);
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days.take(maxDays)) DateAlert(d, byDay[d]!)];
}
