import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// Bir testin loopback'teki cihazları için boş kapılar: [portBlockSize] ardışık kapının
/// ilkini döner (`base`, `base + 1`…); test bitince kendiliğinden bırakılır.
///
/// Eskiden her test 41000–61000 arasından rastgele bir kapı seçiyordu ve seyrek olarak
/// (tam turların yaklaşık yirmide birinde) "koşul zamanında sağlanmadı" diye düşüyordu.
/// Yük altında yeniden üretildi, iki nedeni vardı:
///  - O aralık Linux'un geçici kapı aralığının (32768–60999) içinde. Makinedeki başka bir
///    programın o an tuttuğu bir UDP kapısına denk gelince keşif soketi açılamıyor
///    ("Address already in use"), cihazlar birbirini hiç görmüyordu.
///  - Keşif soketi `reuseAddress` ile açılır: aynı anda çalışan iki test dosyası aynı kapıya
///    denk gelince ikisi de bağlanır, duyurular yanlış teste gider (ağda fazladan bir
///    envanter görünür ya da hiç görünmez).
/// Burada kapılar geçici aralığın dışından seçilir, keşif soketinin hepsini açabildiğine
/// bakılır ve bloğun ardındaki kapı test boyunca **paylaşımsız** tutulur: aynı bloğu isteyen
/// başka bir süreç onu alamaz, sıradakine geçer.
Future<int> takePorts() async {
  final lease = await leasePorts();
  addTearDown(lease.release);
  return lease.base;
}

/// [takePorts]'un elle bırakılanı (tek testte art arda çok kez kapı isteyen ölçümler için).
Future<({int base, void Function() release})> leasePorts() async {
  final random = Random();
  for (var attempt = 0; attempt < 200; attempt++) {
    final base = _lowest + random.nextInt(_blocks) * (portBlockSize + 1);
    final lease = await _exclusive(base + portBlockSize);
    if (lease == null) continue;
    var free = true;
    for (var port = base; port < base + portBlockSize && free; port++) {
      free = await _usable(port);
    }
    if (!free) {
      lease.close();
      continue;
    }
    return (base: base, release: lease.close);
  }
  throw StateError('test için boş kapı bulunamadı');
}

/// Bir testin kullanabileceği kapı sayısı (`base` … `base + portBlockSize - 1`).
const portBlockSize = 7;

// 12000–32000: geçici kapı aralığının altında, bilinen servislerin üstünde. Her blokta
// kullanılan kapılardan sonra bir de kira kapısı var.
const _lowest = 12000;
const _blocks = 20000 ~/ (portBlockSize + 1);

/// Keşif soketi bu kapıyı açabilir mi: başka bir program paylaşımsız tutuyorsa açamaz.
/// Yoklama keşifle aynı biçimde (paylaşımlı) açılır: soketin kapanması eşzamansız, paylaşımsız
/// yoklama yük altında geç kapanınca hemen ardından açılan keşif soketini kendisi engelliyordu.
Future<bool> _usable(int port) async {
  try {
    (await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true)).close();
    return true;
  } on SocketException {
    return false;
  }
}

/// Kapıyı paylaşımsız açar; üzerinde başka bir soket varsa (paylaşımlı da olsa) açılamaz.
/// `reuseAddress` Dart'ta varsayılan olarak açık: burada bilerek kapatılır.
Future<RawDatagramSocket?> _exclusive(int port) async {
  try {
    return await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: false);
  } on SocketException {
    return null;
  }
}
