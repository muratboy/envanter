
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/node.dart';
import 'merge.dart';

/// Ortak kullanımın eşitlediği envanter. Uygulamada [InventoryStore];
/// testlerde bellek içi bir sahte.
abstract interface class SyncTarget {
  /// Kayıtların (çöptekiler dahil) ve kalıcı silme izlerinin anlık görüntüsü.
  ({Map<String, Node> nodes, Map<String, int> tombstones}) snapshot();

  /// Karşıdan gelen durumu birleştirir. Resimler sonra ayrıca gelir.
  ///
  /// [review] açıkken değişiklikler hemen uygulanmaz, kullanıcının onayını
  /// bekler. [from] değişikliği getiren cihaz.
  Future<MergeStats> mergeRemote({
    required Map<String, Node> nodes,
    required Map<String, int> tombstones,
    bool review = false,
    String? from,
  });

  /// Bir kaydın işaret ettiği ama diskte olmayan resimler.
  Set<String> missingImages();

  Future<Uint8List?> readImage(String relativePath);

  /// Yalnızca bir kaydın işaret ettiği ve eksik olan resim yazılır.
  Future<bool> saveImage(String relativePath, Uint8List bytes);

  /// Eklerin diskte olmayan dosyaları: yol → beklenen boyut (0: bilinmiyor).
  /// Resimlerden ayrı: büyük olabilirler, bellekte değil akışla taşınırlar.
  Map<String, int> missingFiles();

  /// Karşıya verilebilecek ek dosyası (ortak bir kaydın eki ve diskte); yoksa null.
  File? outgoingFile(String relativePath);

  /// İndirilen ekin yazılacağı geçici dosya.
  File incomingFile(String relativePath);

  /// İndirme bitince geçici dosyayı yerine koyar; beklenmiyorsa ya da boyutu
  /// tutmuyorsa siler ve false döner.
  Future<bool> adoptFile(String relativePath, File temp);

  /// Çöpte olmayan kayıt sayısı (katılırken "sendeki N kayıt da eklenecek").
  int get liveRecordCount;

  /// Eşitlenecek durumun küçük özeti; değişince değişir. Karşı cihaz bunu
  /// duyurusunda görür ve değişmemişse eşitlemeyi atlar.
  String get stateStamp;

  /// Yalnızca bu cihazdaki düzenlemelerde artar; karşıdan gelen
  /// birleştirmelerde artmaz, yoksa iki cihaz birbirine sonsuz gönderirdi.
  ValueListenable<int> get localRevision;
}
