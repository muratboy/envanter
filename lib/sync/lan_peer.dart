import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'discovery.dart';
import 'wire.dart';

/// Yeni bir cihazın katılma isteği.
class JoinRequest {
  const JoinRequest({
    required this.deviceId,
    required this.name,
    required this.from,
    this.signed = false,
  });

  final String deviceId;
  final String name;
  final InternetAddress from;

  /// İstek ortak anahtarla imzalanmış: gönderen gerçekten bu envanterin
  /// üyesi. İmzasız istek yalnızca onayla kabul edilir; yoksa ağdaki herkes
  /// duyurudan okuduğu bir cihaz kimliğini söyleyip anahtarı alabilirdi.
  final bool signed;
}

/// Kabul edilen isteğe verilen her şey: ortak envanterin kimliği ve anahtarı.
class JoinGrant {
  const JoinGrant({
    required this.inventoryId,
    required this.inventoryName,
    required this.ownerDeviceId,
    required this.key,
    required this.members,
    this.governance,
  });

  final String inventoryId;
  final String inventoryName;
  final String ownerDeviceId;
  final List<int> key;
  final List<Member> members;

  /// Yönetici ve varis, zamanlarıyla.
  final Governance? governance;

  Map<String, Object?> toJson() => {
        'accepted': true,
        'inventoryId': inventoryId,
        'inventoryName': inventoryName,
        'ownerDeviceId': ownerDeviceId,
        'key': base64Encode(key),
        'members': [for (final m in members) m.toJson()],
        if (governance != null) 'governance': governance!.toJson(),
      };

  static JoinGrant? fromJson(Object? json) {
    if (json is! Map || json['accepted'] != true) return null;
    final id = json['inventoryId'];
    final owner = json['ownerDeviceId'];
    final key = json['key'];
    if (id is! String || id.isEmpty || owner is! String || key is! String) return null;
    final List<int> keyBytes;
    try {
      keyBytes = base64Decode(key);
    } on FormatException {
      return null;
    }
    if (keyBytes.length < 16) return null;
    final rawMembers = json['members'];
    return JoinGrant(
      inventoryId: id,
      inventoryName: json['inventoryName'] is String ? json['inventoryName'] as String : '',
      ownerDeviceId: owner,
      key: keyBytes,
      members: [
        if (rawMembers is List)
          for (final m in rawMembers) ?Member.fromJson(m),
      ],
      governance: Governance.fromJson(json['governance']),
    );
  }
}

/// Karşı cihaz yanıt vermedi ya da beklenmedik yanıt verdi.
class PeerException implements Exception {
  const PeerException(this.message, {this.status, this.timedOut = false, this.dataVersion, this.unreachable = false});
  final String message;
  final int? status;
  final bool timedOut;

  /// Karşıya bağlanılamadı (soket hatası).
  final bool unreachable;

  /// Karşının veri sürümü (sürüm uyuşmazlığında).
  final int? dataVersion;

  bool get unauthorized => status == HttpStatus.unauthorized;
  bool get incompatible => status == HttpStatus.upgradeRequired;

  /// Karşı taraf bizi ortak kullanımdan çıkarılmış (ya da ayrılmış) biliyor.
  bool get removed => status == HttpStatus.forbidden;

  @override
  String toString() => 'PeerException($status): $message';
}

/// Her cihazda, ortak kullanım açıkken çalışan küçük HTTP sunucusu.
///
///   GET  /info          duyurunun aynısı (imzasız)
///   POST /join          katılma isteği; sahip karar verene kadar bekler
///   GET  /state         kayıtlar + izler + üyeler            (imzalı)
///   POST /state         karşının durumu; yanıt: eksik resimler (imzalı)
///   GET  `/image/{yol}` resim                                (imzalı)
///   PUT  `/image/{yol}` eksik resmi yükleme                  (imzalı)
///   GET  `/file/{yol}`  ek dosyası, akışla                   (imzalı)
class PeerServer {
  PeerServer({
    required this.info,
    required this.signer,
    required this.onJoin,
    required this.readState,
    required this.applyState,
    required this.readImage,
    required this.saveImage,
    this.openFile,
    this.onPeerVersion,
    this.isRemoved,
    this.clock = DateTime.now,
  });

  /// Bu cihazın saati: gelen imzaların zamanı buna göre denetlenir.
  final DateTime Function() clock;

  /// Karşıya verilebilecek ek dosyası; yoksa null. Ekler büyük olabilir
  /// (video): belleğe alınmaz, diskten akıtılır; yalnızca isteyen çeker.
  final File? Function(String relativePath)? openFile;

  /// Ortak kullanımdan çıkarılan cihaz: anahtarı hâlâ elinde olsa da durum
  /// ve resim alışverişi yapılmaz; 403 yanıtıyla çıkarıldığını öğrenir.
  final bool Function(String? deviceId)? isRemoved;

  /// Durum isteyen ya da getiren cihazın veri sürümü (her /state isteğinde).
  /// Bizimkinden farklıysa alışveriş yapılmaz; arayüz kimin güncellemesi
  /// gerektiğini söyler, sürüm tutunca işaret kalkar.
  final void Function(String? deviceId, int dataVersion)? onPeerVersion;

  final Announcement Function() info;
  final RequestSigner Function() signer;

  /// null dönerse istek reddedildi.
  final Future<JoinGrant?> Function(JoinRequest request) onJoin;
  final SyncState Function() readState;

  /// Birleştirir; birleşmeden sonra eksik kalan resimleri döner.
  final Future<Set<String>> Function(SyncState incoming) applyState;
  final Future<Uint8List?> Function(String relativePath) readImage;
  final Future<bool> Function(String relativePath, Uint8List bytes) saveImage;

  static const maxStateBytes = 32 * 1024 * 1024;
  static const maxImageBytes = 20 * 1024 * 1024;

  HttpServer? _server;
  int get port => _server?.port ?? 0;

  Future<int> start({int port = 0}) async {
    if (_server != null) return _server!.port;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.idleTimeout = const Duration(seconds: 20);
    server.listen((request) => unawaited(_handle(request)));
    _server = server;
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final res = request.response;
    try {
      final path = request.uri.path;
      final method = request.method;
      if (method == 'GET' && path == '/info') {
        return await _json(res, info().toJson());
      }
      if (method == 'POST' && path == '/join') {
        return await _join(request);
      }

      final isImage = path.startsWith('/image/');
      final limit = isImage ? maxImageBytes : maxStateBytes;
      final body = await _readBody(request, limit);
      if (body == null) return await _status(res, HttpStatus.requestEntityTooLarge);
      // Gönderilen durum büyük olabilir: imzası doğrulanıp çözülmesi (ikisi de
      // gövdenin tamamını okur) ana iş parçacığını bekletmesin (bkz. wire.dart).
      // Çözme yalnızca imza tutuyorsa ve aşağıdaki denetimler geçecekse yapılır.
      final posting = path == '/state' && method == 'POST';
      final bool ok;
      SyncState? posted;
      if (posting) {
        final theirs = int.tryParse(request.headers.value(kDataHeader) ?? '') ?? 0;
        final removed = isRemoved?.call(request.headers.value(kFromHeader)) ?? false;
        (ok, posted) = await verifyAndDecodeState(
          key: signer().key,
          method: method,
          path: path,
          body: body,
          time: request.headers.value(RequestSigner.timeHeader),
          signature: request.headers.value(RequestSigner.signatureHeader),
          now: clock(),
          decode: theirs == kDataVersion && !removed,
        );
      } else {
        ok = signer().verify(
          method: method,
          path: path,
          body: body,
          time: request.headers.value(RequestSigner.timeHeader),
          signature: request.headers.value(RequestSigner.signatureHeader),
          now: clock(),
        );
      }
      if (!ok) return await _unauthorized(res);
      if (isRemoved?.call(request.headers.value(kFromHeader)) ?? false) {
        return await _status(res, HttpStatus.forbidden);
      }

      // Farklı veri sürümüyle durum alışverişi yok (bkz. kDataVersion): ne
      // bizimkini veririz ne onunkini alırız. Başlığı göndermeyen eski uygulama.
      if (path == '/state') {
        final theirs = int.tryParse(request.headers.value(kDataHeader) ?? '') ?? 0;
        onPeerVersion?.call(request.headers.value(kFromHeader), theirs);
        if (theirs != kDataVersion) {
          res.statusCode = HttpStatus.upgradeRequired;
          return await _json(res, {'data': kDataVersion});
        }
      }

      if (path == '/state' && method == 'GET') {
        final encoded = await encodeState(readState());
        res.headers.contentType = ContentType.json;
        res.add(encoded.body);
        return await res.close();
      }
      if (posting) {
        final incoming = posted;
        if (incoming == null) return await _status(res, HttpStatus.badRequest);
        final missing = await applyState(incoming);
        return await _json(res, {'missing': missing.toList()});
      }
      if (method == 'GET' && path.startsWith('/file/')) {
        final rel = Uri.decodeComponent(path.substring('/file/'.length));
        if (!isSafeFilePath(rel)) return await _status(res, HttpStatus.badRequest);
        final file = openFile?.call(rel);
        if (file == null) return await _status(res, HttpStatus.notFound);
        res.headers.contentType = ContentType.binary;
        res.contentLength = await file.length();
        await res.addStream(file.openRead());
        return await res.close();
      }
      if (isImage) {
        final rel = Uri.decodeComponent(path.substring('/image/'.length));
        if (!isSafeImagePath(rel)) return await _status(res, HttpStatus.badRequest);
        if (method == 'GET') {
          final bytes = await readImage(rel);
          if (bytes == null) return await _status(res, HttpStatus.notFound);
          res.headers.contentType = ContentType('image', 'jpeg');
          res.add(bytes);
          return await res.close();
        }
        if (method == 'PUT') {
          final saved = await saveImage(rel, body);
          return await _status(res, saved ? HttpStatus.noContent : HttpStatus.conflict);
        }
      }
      return await _status(res, HttpStatus.notFound);
    } on Object {
      try {
        return await _status(res, HttpStatus.internalServerError);
      } on Object {
        // Bağlantı çoktan kopmuş olabilir.
      }
    }
  }

  Future<void> _join(HttpRequest request) async {
    final res = request.response;
    if (!info().joinable) return _status(res, HttpStatus.forbidden);
    final body = await _readBody(request, 16 * 1024);
    if (body == null) return _status(res, HttpStatus.requestEntityTooLarge);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return _status(res, HttpStatus.badRequest);
    }
    if (json is! Map || json['deviceId'] is! String || (json['deviceId'] as String).isEmpty) {
      return _status(res, HttpStatus.badRequest);
    }
    final grant = await onJoin(JoinRequest(
      deviceId: json['deviceId'] as String,
      name: json['name'] is String ? json['name'] as String : '',
      from: request.connectionInfo?.remoteAddress ?? InternetAddress.anyIPv4,
      signed: signer().verify(
        method: 'POST',
        path: '/join',
        body: body,
        time: request.headers.value(RequestSigner.timeHeader),
        signature: request.headers.value(RequestSigner.signatureHeader),
        now: clock(),
      ),
    ));
    return _json(res, grant?.toJson() ?? {'accepted': false});
  }

  /// İmza tutmadı: saatimiz de söylenir. Sebep saat farkıysa karşı taraf isteği bizim saatimize
  /// göre yeniden imzalar ([PeerClient.timeShift]); anahtar yanlışsa bunun bir faydası olmaz.
  Future<void> _unauthorized(HttpResponse res) {
    res.headers.set(RequestSigner.nowHeader, '${clock().millisecondsSinceEpoch}');
    return _status(res, HttpStatus.unauthorized);
  }

  static Future<Uint8List?> _readBody(HttpRequest request, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) return null;
    }
    return builder.takeBytes();
  }

  static Future<void> _json(HttpResponse res, Object json) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(json));
    return res.close();
  }

  static Future<void> _status(HttpResponse res, int code) {
    res.statusCode = code;
    return res.close();
  }
}

/// Karşı cihaza istek atan taraf.
class PeerClient {
  PeerClient(
    this.base, {
    this.signer,
    this.from,
    HttpClient? http,
    this.clock = DateTime.now,
    this.timeShift = Duration.zero,
  }) : _http = http ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  final Uri base;
  final RequestSigner? signer;

  /// Bu cihazın kimliği; karşı taraf sürüm uyuşmazlığında kimin eski
  /// olduğunu gösterebilsin.
  final String? from;
  final HttpClient _http;

  /// Bu cihazın saati: istekler bununla, [timeShift] eklenerek imzalanır.
  final DateTime Function() clock;

  /// Karşının saatiyle bu cihazınki arasındaki fark. İlk 401'de karşının bildirdiği saatten
  /// öğrenilir ([_learnClock]); servis üye başına saklar, sonraki istekler baştan doğru imzalanır.
  Duration timeShift;

  bool _closed = false;

  /// Süren istek ağ hatasıyla biter; kapandıktan sonra yeni istek de aynı hatayı alır
  /// (kapalı istemci başka türden bir hata fırlatır, çağıranlar yalnızca ağ hatasını bekler).
  void close() {
    _closed = true;
    _http.close(force: true);
  }

  Future<Announcement?> info() async {
    final json = await _send('GET', '/info', signed: false);
    return Announcement.fromJson(json);
  }

  /// Sahip karar verene kadar bekler. Reddedilirse null.
  Future<JoinGrant?> join({
    required String deviceId,
    required String name,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    // İmza eklenir: zaten üyeysek karşı taraf bunu doğrulayıp onay
    // sormadan kabul eder. Yeni cihazın anahtarı tutmadığı için imzası
    // geçersizdir, istek normal onay yoluna düşer.
    final json = await _send(
      'POST',
      '/join',
      body: utf8.encode(jsonEncode({'deviceId': deviceId, 'name': name})),
      signed: signer != null,
      timeout: timeout,
    );
    return JoinGrant.fromJson(json);
  }

  Future<SyncState> getState() async {
    final bytes = await _sendRaw('GET', '/state');
    // Büyük durum ayrı yalıtımda çözülür ve doğrulanır.
    final state = bytes == null || bytes.isEmpty ? null : await decodeState(bytes);
    if (state == null) throw const PeerException('geçersiz durum');
    return state;
  }

  /// Yanıt: karşının birleşmeden sonra eksik kalan resimleri.
  Future<List<String>> postState(SyncState state) async {
    // Büyük durum ayrı yalıtımda metne çevrilir; imza için özeti de orada alınır.
    final encoded = await encodeState(state);
    final json = await _send('POST', '/state', body: encoded.body, digest: encoded.digest);
    final missing = json is Map ? json['missing'] : null;
    return [
      if (missing is List)
        for (final m in missing)
          if (m is String && isSafeImagePath(m)) m,
    ];
  }

  Future<Uint8List?> getImage(String relativePath) async {
    final bytes = await _sendRaw('GET', _imagePath(relativePath), allowNotFound: true);
    return bytes;
  }

  Future<void> putImage(String relativePath, Uint8List bytes) async {
    await _sendRaw('PUT', _imagePath(relativePath), body: bytes);
  }

  static String _imagePath(String rel) => '/image/${Uri.encodeComponent(rel)}';

  /// Ek dosyasını [into]'ya akıtır (belleğe almadan). Karşıda yoksa false.
  /// [limit]: beklenen boyut; aşan yanıt yarıda kesilir (disk dolmasın).
  Future<bool> downloadFile(
    String relativePath,
    File into, {
    required int limit,
    Duration timeout = const Duration(seconds: 30),
    void Function(int received, int total)? onProgress,
  }) async {
    final path = '/file/${Uri.encodeComponent(relativePath)}';
    IOSink? sink;
    try {
      final response = await _open('GET', path, const [], signed: true, timeout: timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        if (response.statusCode == HttpStatus.notFound) return false;
        throw PeerException('HTTP ${response.statusCode}', status: response.statusCode);
      }
      if (response.contentLength > limit) {
        throw const PeerException('ek beklenenden büyük');
      }
      await into.parent.create(recursive: true);
      sink = into.openWrite();
      var received = 0;
      final total = response.contentLength;
      // Zaman aşımı parça başına: büyük dosya uzun sürer ama akış durmamalı.
      await for (final chunk in response.timeout(timeout)) {
        received += chunk.length;
        if (received > limit) throw const PeerException('ek beklenenden büyük');
        sink.add(chunk);
        if (total > 0) onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return true;
    } on TimeoutException {
      throw const PeerException('zaman aşımı', timedOut: true);
    } on SocketException catch (e) {
      throw PeerException('bağlanamadı: ${e.message}', unreachable: true);
    } on HttpException catch (e) {
      throw PeerException('HTTP hatası: ${e.message}');
    } finally {
      // Yarım kalan indirme: geçici dosya bir dahakine baştan yazılır.
      if (sink != null) {
        try {
          await sink.close();
        } on Object {
          // Bağlantı kopmuşken kapatma da düşebilir.
        }
      }
    }
  }

  static Object? _tryJson(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  Future<Object?> _send(
    String method,
    String path, {
    List<int> body = const [],
    bool signed = true,
    Duration timeout = const Duration(seconds: 30),
    String? digest,
  }) async {
    final bytes = await _sendRaw(method, path, body: body, signed: signed, timeout: timeout, digest: digest);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const PeerException('JSON değil');
    }
  }

  /// İsteği açar, imzalar ve gönderir. İmza saat yüzünden tutmadıysa ([_learnClock]) bir kez karşının
  /// saatine göre yeniden imzalanıp gönderilir.
  Future<HttpClientResponse> _open(
    String method,
    String path,
    List<int> body, {
    required bool signed,
    required Duration timeout,
    String? digest,
  }) async {
    for (var attempt = 0;; attempt++) {
      if (_closed) throw const PeerException('bağlantı kapalı');
      final request = await _http.openUrl(method, base.replace(path: path)).timeout(timeout);
      if (signed) {
        final s = signer;
        if (s == null) throw const PeerException('anahtar yok');
        s.headers(method, path, body, clock().add(timeShift), digest: digest).forEach(request.headers.set);
      }
      request.headers.set(kDataHeader, '$kDataVersion');
      if (from != null) request.headers.set(kFromHeader, from!);
      if (body.isNotEmpty) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      if (!signed || attempt > 0 || response.statusCode != HttpStatus.unauthorized || !_learnClock(response)) {
        return response;
      }
      await response.drain<void>();
    }
  }

  /// 401 yanıtındaki karşı saat ([RequestSigner.nowHeader]) imzanın zaman penceresinin dışında
  /// kalıyorsa sebep saattir: fark [timeShift]'e eklenir. Saatler yakınsa (anahtar tutmuyor) ya da
  /// saat bildirilmediyse (eski uygulama) yeniden denemenin anlamı yok.
  bool _learnClock(HttpClientResponse response) {
    final theirs = int.tryParse(response.headers.value(RequestSigner.nowHeader) ?? '');
    if (theirs == null) return false;
    final gap = Duration(milliseconds: theirs - clock().add(timeShift).millisecondsSinceEpoch);
    if (gap.abs() < RequestSigner.tolerance ~/ 2) return false;
    timeShift += gap;
    return true;
  }

  Future<Uint8List?> _sendRaw(
    String method,
    String path, {
    List<int> body = const [],
    bool signed = true,
    bool allowNotFound = false,
    Duration timeout = const Duration(seconds: 30),
    String? digest,
  }) async {
    try {
      final response = await _open(method, path, body, signed: signed, timeout: timeout, digest: digest);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      if (allowNotFound && response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode == HttpStatus.upgradeRequired) {
        final json = _tryJson(builder.takeBytes());
        final theirs = json is Map && json['data'] is int ? json['data'] as int : 0;
        throw PeerException('veri sürümü farklı', status: response.statusCode, dataVersion: theirs);
      }
      if (response.statusCode >= 400) {
        throw PeerException('HTTP ${response.statusCode}', status: response.statusCode);
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw const PeerException('zaman aşımı', timedOut: true);
    } on SocketException catch (e) {
      throw PeerException('bağlanamadı: ${e.message}', unreachable: true);
    } on HttpException catch (e) {
      throw PeerException('HTTP hatası: ${e.message}');
    }
  }
}
