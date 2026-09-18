import 'package:flutter/foundation.dart';

enum SpanUnit { day, week, month, year }

/// "3 ay", "2 hafta" gibi takvim süresi. Raf ömrü, garanti süresi ve son
/// kullanma uyarısı bununla tutulur. Gün sayısına çevrilmez: "1 ay" 31 Ocak'tan
/// 28 Şubat'a gider, 30 gün değil; garanti belgesindeki gibi.
///
/// Kayıtta kısa metin olarak durur ("3m"): okunur, eşitlemede de öyle gider.
@immutable
class TimeSpan {
  const TimeSpan(this.amount, this.unit);

  final int amount;
  final SpanUnit unit;

  static const _codes = {SpanUnit.day: 'd', SpanUnit.week: 'w', SpanUnit.month: 'm', SpanUnit.year: 'y'};

  static final _pattern = RegExp(r'^(\d{1,4})([dwmy])$');

  /// Bozuk ya da boş metin null döner; sıfır süre de anlamsız sayılır.
  static TimeSpan? parse(String? raw) {
    final m = _pattern.firstMatch(raw?.trim() ?? '');
    if (m == null) return null;
    final amount = int.parse(m.group(1)!);
    if (amount == 0) return null;
    final unit = _codes.entries.firstWhere((e) => e.value == m.group(2)).key;
    return TimeSpan(amount, unit);
  }

  static bool isValid(String? raw) => parse(raw) != null;

  String encode() => '$amount${_codes[unit]}';

  /// [date]'e eklenir. Ay ve yılda gün, ayın son gününe kırpılır (31 Ocak + 1 ay
  /// = 28/29 Şubat).
  DateTime addTo(DateTime date) => _shift(date, amount);

  DateTime subtractFrom(DateTime date) => _shift(date, -amount);

  DateTime _shift(DateTime date, int n) {
    final d = dateOnly(date);
    switch (unit) {
      case SpanUnit.day:
        return DateTime(d.year, d.month, d.day + n);
      case SpanUnit.week:
        return DateTime(d.year, d.month, d.day + 7 * n);
      case SpanUnit.month:
      case SpanUnit.year:
        final months = unit == SpanUnit.year ? 12 * n : n;
        final first = DateTime(d.year, d.month + months);
        final last = DateTime(first.year, first.month + 1, 0).day;
        return DateTime(first.year, first.month, d.day > last ? last : d.day);
    }
  }

  @override
  bool operator ==(Object other) => other is TimeSpan && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => encode();
}

/// Günün başı (yerel saat). Tarihler gün olarak karşılaştırılır: saat farkı
/// "bugün bitiyor"u "yarın" yapmasın.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Son kullanma durumu.
enum ExpiryState {
  /// Uyarı zamanı gelmedi.
  fine,

  /// Uyarı süresine girdi (bugün son gün dahil).
  soon,

  /// Tarihi geçti.
  expired,
}

/// [expiry] günü, [warnBefore] kadar önceden uyarılır. [today] günün kendisi.
ExpiryState expiryStateOf(DateTime expiry, TimeSpan warnBefore, DateTime today) {
  final day = dateOnly(today);
  final end = dateOnly(expiry);
  if (day.isAfter(end)) return ExpiryState.expired;
  if (!day.isBefore(warnBefore.subtractFrom(end))) return ExpiryState.soon;
  return ExpiryState.fine;
}

/// [from] gününden [to] gününe kaç gün (geçmişse eksi). Günler UTC'de
/// sayılır: yaz saati geçişindeki 23 saatlik gün de bir gündür.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
