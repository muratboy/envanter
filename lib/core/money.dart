import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Bir para tutarı: kuruş/sent cinsinden tam sayı + ISO 4217 para birimi.
///
/// Tam sayı tutulur: toplamlarda ondalık kayması olmasın (0,1 + 0,2). Kayıtta ve
/// ağda tek metin ("1250.50 TRY"): her cihazda aynı metin çıksın diye biçim sabit
/// (iki ondalık, nokta, boşluk, büyük harfli birim); [clean] her girdiyi bu biçime
/// çevirir, uymayanı atar. Kur çevrimi yok: sunucu yok, kur internetten gelirdi.
/// Farklı birimler ayrı ayrı toplanır ("12.500 ₺ + 300 $").
@immutable
class Money {
  const Money(this.cents, this.currency);

  /// Kuruş (birimin yüzde biri). Negatif olmaz.
  final int cents;

  /// Üç büyük harf (TRY, USD, EUR...).
  final String currency;

  /// Bir trilyon birim: daha büyüğü yazım hatasıdır (ve toplamı taşırabilir).
  static const maxCents = 100000000000000;

  /// Seçicide önce görünen birimler; başka bir kod da yazılabilir.
  static const common = ['TRY', 'USD', 'EUR', 'GBP', 'CHF', 'JPY', 'RUB', 'SAR', 'AED', 'AZN'];

  static final _code = RegExp(r'^[A-Z]{3}$');
  static final _stored = RegExp(r'^(\d{1,15})\.(\d{2}) ([A-Z]{3})$');

  static bool validCurrency(String code) => _code.hasMatch(code);

  /// Telefonun bölgesine göre varsayılan birim; ayarlardan değiştirilir. Bölge bilinmiyorsa
  /// dile bakılır (Türkçe → TRY), o da değilse USD. Liste tam değil: kod elle de yazılabilir.
  static String localDefault([Locale? locale]) {
    final l = locale ?? PlatformDispatcher.instance.locale;
    final byCountry = _countryCurrency[l.countryCode?.toUpperCase()];
    if (byCountry != null) return byCountry;
    return l.languageCode == 'tr' ? 'TRY' : 'USD';
  }

  static const _euro = ['AT', 'BE', 'CY', 'DE', 'EE', 'ES', 'FI', 'FR', 'GR', 'HR', 'IE', 'IT', 'LT', 'LU', 'LV',
    'MT', 'NL', 'PT', 'SI', 'SK'];

  static final Map<String, String> _countryCurrency = {
    for (final c in _euro) c: 'EUR',
    'TR': 'TRY', 'US': 'USD', 'GB': 'GBP', 'CH': 'CHF', 'JP': 'JPY', 'RU': 'RUB', 'SA': 'SAR', 'AE': 'AED',
    'AZ': 'AZN', 'CA': 'CAD', 'AU': 'AUD', 'NZ': 'NZD', 'CN': 'CNY', 'IN': 'INR', 'SE': 'SEK', 'NO': 'NOK',
    'DK': 'DKK', 'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF', 'RO': 'RON', 'BG': 'BGN', 'UA': 'UAH', 'GE': 'GEL',
    'KZ': 'KZT', 'IL': 'ILS', 'EG': 'EGP', 'BR': 'BRL', 'MX': 'MXN', 'KR': 'KRW', 'QA': 'QAR', 'KW': 'KWD',
  };

  /// Kayıttaki metin.
  String encode() => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')} $currency';

  /// Kayıttaki metinden; bozuksa null.
  static Money? decode(Object? raw) {
    if (raw is! String) return null;
    final m = _stored.firstMatch(raw.trim());
    if (m == null) return null;
    final cents = int.parse(m[1]!) * 100 + int.parse(m[2]!);
    return cents > maxCents ? null : Money(cents, m[3]!);
  }

  /// Ağdan, yedekten, veritabanından gelen değer: geçerliyse sabit biçimde, değilse null.
  static String? clean(Object? raw) => decode(raw)?.encode();

  /// Kullanıcının yazdığı tutar ("1.250,50", "1,250.50", "1250", "12,5"). Ayırıcı
  /// tahmini: ikisi birden varsa sondaki ondalıktır; tek çeşit varsa ve bir kez,
  /// ardından en çok iki rakamla geçiyorsa ondalık, yoksa binlik. Boş ya da
  /// anlaşılmazsa null.
  static Money? parseInput(String text, String currency) {
    var t = text.replaceAll(RegExp(r'[\s\u00A0₺$€£¥]'), '');
    if (t.isEmpty || !validCurrency(currency)) return null;
    if (!RegExp(r'^[\d.,]+$').hasMatch(t)) return null;
    final lastDot = t.lastIndexOf('.');
    final lastComma = t.lastIndexOf(',');
    String whole;
    var frac = '';
    if (lastDot >= 0 && lastComma >= 0) {
      final at = lastDot > lastComma ? lastDot : lastComma;
      frac = t.substring(at + 1);
      if (frac.contains(RegExp('[.,]'))) return null;
      // Öndeki kısım binlik gruplu olmalı ("1.250,50"); "1,2,50.1" yazım hatasıdır.
      final groups = t.substring(0, at).split(at == lastDot ? ',' : '.');
      if (groups.first.isEmpty || groups.skip(1).any((g) => g.length != 3)) return null;
      whole = groups.join();
      if (whole.contains(RegExp('[.,]'))) return null;
    } else if (lastDot >= 0 || lastComma >= 0) {
      final sep = lastDot >= 0 ? '.' : ',';
      final parts = t.split(sep);
      if (parts.length == 2 && parts[1].length <= 2) {
        whole = parts[0];
        frac = parts[1];
      } else {
        // Binlik ayırıcı: her grup üç rakam olmalı ("1.250.000").
        if (parts.skip(1).any((p) => p.length != 3)) return null;
        whole = parts.join();
      }
    } else {
      whole = t;
    }
    if (whole.isEmpty) whole = '0';
    if (frac.length > 2 || whole.length > 15) return null;
    final cents = int.parse(whole) * 100 + (frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0')));
    return cents > maxCents ? null : Money(cents, currency);
  }

  /// [n] tanesinin tutarı (adet tutulan eşyada birim fiyat × adet). Sınırda kesilir:
  /// adet milyona, fiyat trilyona çıkabilir, çarpım 64 bitte taşardı.
  Money times(int n) {
    const limit = maxCents * 1000;
    if (n <= 0) return Money(0, currency);
    return Money(cents > limit ~/ n ? limit : cents * n, currency);
  }

  /// Kısa simge; bilinmeyen birimde kodun kendisi.
  static String symbol(String currency) => switch (currency) {
        'TRY' => '₺',
        'USD' => r'$',
        'EUR' => '€',
        'GBP' => '£',
        'JPY' => '¥',
        'RUB' => '₽',
        'AZN' => '₼',
        _ => currency,
      };

  /// Okunur biçim. Türkçede "1.250,50 ₺", İngilizcede "₺1,250.50"; kuruşu
  /// sıfırsa ondalık yazılmaz ("1.250 ₺"). Simgesi olmayan birim kodla, sonda.
  String format({required bool turkish}) {
    final group = turkish ? '.' : ',';
    final dec = turkish ? ',' : '.';
    final digits = (cents ~/ 100).toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(group);
      buf.write(digits[i]);
    }
    if (cents % 100 != 0) buf.write('$dec${(cents % 100).toString().padLeft(2, '0')}');
    final sym = symbol(currency);
    if (sym == currency) return '$buf $currency';
    return turkish ? '$buf $sym' : '$sym$buf';
  }

  /// Düzenleme alanına konacak metin (binlik ayırıcısız): "1250,5" / "1250.5".
  String inputText({required bool turkish}) {
    final whole = cents ~/ 100;
    final c = cents % 100;
    if (c == 0) return '$whole';
    final frac = c % 10 == 0 ? '${c ~/ 10}' : c.toString().padLeft(2, '0');
    return '$whole${turkish ? ',' : '.'}$frac';
  }

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents && other.currency == currency;

  @override
  int get hashCode => Object.hash(cents, currency);

  @override
  String toString() => encode();
}

/// Birim birim toplam (para birimi → kuruş). Kur çevrimi yapılmaz.
class MoneyTotals {
  final Map<String, int> _byCurrency = {};

  void add(Money m) => _byCurrency[m.currency] = (_byCurrency[m.currency] ?? 0) + m.cents;

  void addAll(MoneyTotals other) => other._byCurrency.forEach((c, v) => _byCurrency[c] = (_byCurrency[c] ?? 0) + v);

  bool get isEmpty => _byCurrency.values.every((v) => v == 0);

  /// Büyükten küçüğe; eşitlikte koda göre (her çizimde aynı sıra).
  List<Money> get amounts {
    final list = [
      for (final e in _byCurrency.entries)
        if (e.value > 0) Money(e.value, e.key),
    ]..sort((a, b) {
        final c = b.cents.compareTo(a.cents);
        return c != 0 ? c : a.currency.compareTo(b.currency);
      });
    return list;
  }

  /// En büyük tutarın birimi (sıralama ve varsayılan birim için).
  String? get mainCurrency => amounts.isEmpty ? null : amounts.first.currency;

  /// Ana birimdeki tutar; sıralamada kullanılır (öteki birimler karşılaştırılamaz).
  int centsIn(String currency) => _byCurrency[currency] ?? 0;

  String format({required bool turkish}) => amounts.map((m) => m.format(turkish: turkish)).join(' + ');
}
