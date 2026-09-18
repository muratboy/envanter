import 'dart:math';

import '../core/time_span.dart';
import 'node.dart';

/// Paket işlemleri: aynı eşyanın farklı son kullanma tarihli kısımları
/// ([Node.lots]). Hepsi saf, yeni bir [Node] döner; mağaza kaydeder.
///
/// Kurallar:
/// - Kullanılan (−) her zaman en eski tarihli paketten gider: insanlar da önce
///   tarihi yakın olanı açar, kimse hangisini kullandığını seçmek zorunda kalmaz.
/// - Eklenen (+), raf ömrü varsa bugün alınmış sayılır, tarihi bugün + raf
///   ömrü olan pakete; yoksa en yeni tarihli pakete girer. Farklı tarihli paket
///   ayrıca eklenir ([addLot]).
/// - Aynı günler birleşir; tek tarih kalınca paket listesi kalkar, o tarih
///   eşyanın kendi tarihi olur (eşya eskisi gibi tek tarihli görünür).

/// Sıralar, aynı günleri birleştirir, boşları atar.
List<Lot> normalizeLots(Iterable<Lot> lots) {
  final byDay = <DateTime, int>{};
  for (final l in lots) {
    if (l.count <= 0) continue;
    final d = dateOnly(l.expires);
    byDay[d] = (byDay[d] ?? 0) + l.count;
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) Lot(byDay[d]!, d)];
}

/// Eşyaya paketleri koyar. İki ya da daha çok tarih: paket listesi, adet
/// toplamları. Tek tarih: liste kalkar, tarih eşyanın olur. Hiç kalmadıysa
/// adet 0 (son tarih yerinde kalır; biten eşyanın tarihine bakılmaz).
Node withLots(Node n, Iterable<Lot> lots) {
  final list = normalizeLots(lots);
  if (list.length >= 2) {
    return n.copyWith(lots: list, quantity: list.fold<int>(0, (a, l) => a + l.count), clearExpires: true);
  }
  if (list.length == 1) {
    return n.copyWith(lots: const [], quantity: list.single.count, expiresAt: list.single.expires);
  }
  return n.copyWith(lots: const [], quantity: 0);
}

/// Eşyanın şu anki paketleri. Paket listesi yoksa ve adet ile tarih varsa tek
/// paket; yoksa boş (tarihsiz ya da adetsiz eşya).
List<Lot> currentLots(Node n) {
  if (n.lots.isNotEmpty) return n.lots;
  final q = n.quantity ?? 0;
  final d = n.effectiveExpiry;
  return q > 0 && d != null ? [Lot(q, dateOnly(d))] : const [];
}

/// Tarihi geçmiş birim sayısı (son günü bugün olan henüz geçmedi).
int expiredUnits(Node n, DateTime today) {
  final day = dateOnly(today);
  return currentLots(n).where((l) => day.isAfter(l.expires)).fold(0, (a, l) => a + l.count);
}

/// En eski tarihli paketlerden [count] birim düşer.
List<Lot> _consume(List<Lot> lots, int count) {
  var left = count;
  final out = <Lot>[];
  for (final l in lots) {
    if (left <= 0) {
      out.add(l);
    } else if (l.count <= left) {
      left -= l.count;
    } else {
      out.add(l.withCount(l.count - left));
      left = 0;
    }
  }
  return out;
}

/// Adedi [quantity] yapar (kartta − / +, düzenleyicideki adet). Tarihli
/// eşyada azalan, tarihi geçmemiş en eski paketten gider: bozulmuş olan
/// "kullanıldı" sayılmasın, o "Tarihi geçenleri at" ile gider (hepsi geçmişse
/// yine de ondan). Artan, raf ömrü varsa bugünün tarihli pakete, yoksa en yeni
/// pakete girer.
Node setQuantityByLots(Node n, int quantity, DateTime today) {
  final q = max(0, quantity);
  // Adedi tutulmayan eşya "bitmiş" değildir: saymaya başlamak eldekinin tarihlerine
  // dokunmaz. Boş adet 0 sayılırken raf ömürlü eşyada ilk + alış tarihini bugüne çekip
  // yazılı tarihi siliyor, 0 yazmak da "değişmedi" diye yok sayılıyordu.
  final current = n.quantity;
  if (current == null) return n.copyWith(quantity: q);
  if (q == current) return n;
  final life = TimeSpan.parse(n.shelfLife);
  final lots = currentLots(n);
  if (lots.isEmpty) {
    // Tarihsiz ya da bitmiş eşya. Raf ömürlü biten eşyaya eklenen bugün alınmıştır:
    // eski (yazılı) tarih kalkar, yenisi raf ömründen hesaplanır.
    if (current == 0 && q > 0 && life != null) {
      return n.copyWith(quantity: q, purchasedAt: dateOnly(today), clearExpires: true);
    }
    return n.copyWith(quantity: q);
  }
  if (q < current) {
    final day = dateOnly(today);
    return withLots(n, _consume([
      for (final l in lots) if (!day.isAfter(l.expires)) l,
      for (final l in lots) if (day.isAfter(l.expires)) l,
    ], current - q));
  }
  final date = life != null ? dateOnly(life.addTo(dateOnly(today))) : lots.last.expires;
  return withLots(n, [...lots, Lot(q - current, date)]);
}

/// Farklı tarihli yeni paket: [count] tane, [expires] tarihli; eldekiler
/// kendi tarihleriyle kalır. Tarihsiz eşyada bu tarih eşyanın tarihi olur.
Node addLot(Node n, int count, DateTime expires) {
  if (count <= 0) return n;
  final lots = currentLots(n);
  if (lots.isEmpty) {
    return n.copyWith(quantity: (n.quantity ?? 0) + count, expiresAt: dateOnly(expires), lots: const []);
  }
  return withLots(n, [...lots, Lot(count, dateOnly(expires))]);
}

/// Tarihi geçenleri atar; kalanlar yerinde. Hepsi gittiyse adet 0.
Node discardExpired(Node n, DateTime today) {
  final day = dateOnly(today);
  final lots = currentLots(n);
  if (lots.isEmpty) return n;
  return withLots(n, [for (final l in lots) if (!day.isAfter(l.expires)) l]);
}

/// [index]'teki paketin adedi (düzenleyicide); 0 olursa paket kalkar.
Node setLotCount(Node n, int index, int count) {
  final lots = [...currentLots(n)];
  if (index < 0 || index >= lots.length) return n;
  lots[index] = lots[index].withCount(max(0, count));
  return withLots(n, lots);
}

/// [index]'teki paketin tarihi (düzenleyicide satıra dokununca).
Node redateLot(Node n, int index, DateTime date) {
  final lots = [...currentLots(n)];
  if (index < 0 || index >= lots.length) return n;
  lots[index] = Lot(lots[index].count, dateOnly(date));
  return withLots(n, lots);
}

/// [count] birimi [from] tarihli paketten [to] tarihine taşır (kartta + ile
/// eklenenin tarihi farklıysa).
Node moveUnits(Node n, int count, DateTime from, DateTime to) {
  final lots = [...currentLots(n)];
  final i = lots.indexWhere((l) => l.expires == dateOnly(from));
  if (i < 0 || count <= 0) return n;
  final moved = min(count, lots[i].count);
  lots[i] = lots[i].withCount(lots[i].count - moved);
  return withLots(n, [...lots, Lot(moved, dateOnly(to))]);
}
