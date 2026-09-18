/// Aramada harf farkı gözetilmez: büyük/küçük harf, Türkçe'nin noktalı/noktasız
/// i'si ve çengelli, şapkalı harfler aynı sayılır. Telefonda çoğu kişi
/// "cekic" yazar; Dart'ın toLowerCase'i ise "I"yı "ı" değil "i" yapar, yani
/// "ısıtıcı" araması "ISITICI"yı bulmuyordu.
///
/// Katlama harf harf yapılır ve uzunluğu değiştirmez: katlanmış metinde
/// bulunan yer, özgün metinde de aynı yerdir (vurgulama buna dayanıyor).
String foldForSearch(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    final folded = _fold[unit];
    if (folded != null) {
      out.writeCharCode(folded);
      continue;
    }
    final char = String.fromCharCode(unit);
    final lower = char.toLowerCase();
    // Tek harften çok harfe açılan küçültmeler (nadir) olduğu gibi kalır.
    out.write(lower.length == 1 ? lower : char);
  }
  return out.toString();
}

const _a = 0x61, _c = 0x63, _e = 0x65, _g = 0x67, _i = 0x69, _n = 0x6E, _o = 0x6F, _s = 0x73, _u = 0x75;

final Map<int, int> _fold = {
  for (final c in 'IİıÎîÍíÌìÏï'.codeUnits) c: _i,
  for (final c in 'ÇçĆćČč'.codeUnits) c: _c,
  for (final c in 'Ğğ'.codeUnits) c: _g,
  for (final c in 'ÖöÔôÓóÒòÕõ'.codeUnits) c: _o,
  for (final c in 'ŞşŚśŠš'.codeUnits) c: _s,
  for (final c in 'ÜüÛûÚúÙù'.codeUnits) c: _u,
  for (final c in 'ÂâÁáÀàÄäÃãÅå'.codeUnits) c: _a,
  for (final c in 'ÉéÈèÊêËë'.codeUnits) c: _e,
  for (final c in 'Ññ'.codeUnits) c: _n,
};

/// Arama kutusundaki metnin kelimeleri, katlanmış. Her kelime kaydın bir
/// yerinde geçmeli ("kırmızı kalem" → adı "Kalem", notu "kırmızı" olan bulunur).
List<String> searchTokens(String query) =>
    foldForSearch(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

/// [text] içinde kelimelerin geçtiği yerler, soldan sağa ve birleştirilmiş.
/// [text] katlanmamış özgün metindir; aralıklar onun üzerindedir.
List<(int, int)> matchRanges(String text, List<String> tokens) {
  if (text.isEmpty || tokens.isEmpty) return const [];
  final folded = foldForSearch(text);
  final ranges = <(int, int)>[];
  for (final t in tokens) {
    var from = 0;
    while (true) {
      final at = folded.indexOf(t, from);
      if (at < 0) break;
      ranges.add((at, at + t.length));
      from = at + t.length;
    }
  }
  if (ranges.length < 2) return ranges;
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[ranges.first];
  for (final r in ranges.skip(1)) {
    final last = merged.last;
    if (r.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, r.$2 > last.$2 ? r.$2 : last.$2);
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// Uzun bir notun, ilk eşleşmenin çevresindeki parçası: sonuç satırına tek
/// satır sığar ve neden bulunduğu görünür. Satır sonları boşluğa çevrilir;
/// baştan ya da sondan kesildiyse "…" eklenir.
String snippetAround(String text, List<String> tokens, {int before = 18, int length = 64}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final ranges = matchRanges(flat, tokens);
  if (ranges.isEmpty || flat.length <= length) return flat;
  var start = (ranges.first.$1 - before).clamp(0, flat.length);
  // Kelimenin ortasından başlamasın.
  if (start > 0) {
    final space = flat.lastIndexOf(' ', start);
    if (space >= 0 && ranges.first.$1 - space <= before + 12) start = space + 1;
  }
  final end = (start + length).clamp(0, flat.length);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
}

/// Adları sıralamak için: harf farkı gözetmez ([foldForSearch]) ve içindeki
/// sayıları sayı olarak karşılaştırır ("Adsız 2", "Adsız 10"dan önce gelir;
/// düz metin karşılaştırması "10"u "2"nin önüne koyardı).
int compareNatural(String a, String b) {
  final x = foldForSearch(a.trim());
  final y = foldForSearch(b.trim());
  var i = 0;
  var j = 0;
  bool digit(int c) => c >= 0x30 && c <= 0x39;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    if (digit(cx) && digit(cy)) {
      var ei = i;
      while (ei < x.length && digit(x.codeUnitAt(ei))) {
        ei++;
      }
      var ej = j;
      while (ej < y.length && digit(y.codeUnitAt(ej))) {
        ej++;
      }
      // Baştaki sıfırlar atılır; sonra önce uzunluk (basamak sayısı), sonra metin.
      final nx = x.substring(i, ei).replaceFirst(RegExp('^0+(?=.)'), '');
      final ny = y.substring(j, ej).replaceFirst(RegExp('^0+(?=.)'), '');
      final c = nx.length != ny.length ? nx.length.compareTo(ny.length) : nx.compareTo(ny);
      if (c != 0) return c;
      i = ei;
      j = ej;
      continue;
    }
    if (cx != cy) return cx.compareTo(cy);
    i++;
    j++;
  }
  return (x.length - i).compareTo(y.length - j);
}
