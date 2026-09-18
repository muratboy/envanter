import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ortak kullanım açık bir cihazın yerel ağa duyurusu.
class Announcement {
  const Announcement({
    required this.deviceId,
    required this.deviceName,
    required this.inventoryId,
    required this.inventoryName,
    required this.joinable,
    required this.httpPort,
    this.stamp = '',
    this.dataVersion = 0,
  });

  final String deviceId;
  final String deviceName;

  /// Ortak envanterin kimliği; üyeler aynı kimliği duyurur.
  final String inventoryId;
  final String inventoryName;

  /// Envanterin sahibi mi, yani katılma isteği kabul ediyor mu.
  final bool joinable;
  final int httpPort;

  /// Cihazın envanter durumunun özeti (bkz. SyncTarget.stateStamp). Boşsa
  /// bilinmiyor demektir ve eşitleme atlanmaz.
  final String stamp;

  /// Cihazın eşitlediği verinin biçimi (wire.dart'taki kDataVersion); eski
  /// uygulama göndermez, 0 sayılır. Farklıysa eşitlenmez.
  final int dataVersion;

  Map<String, Object?> toJson() => {
        'app': 'envanter',
        'v': 1,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'inventoryId': inventoryId,
        'inventoryName': inventoryName,
        'joinable': joinable,
        'port': httpPort,
        'stamp': stamp,
        'd': dataVersion,
      };

  static Announcement? fromJson(Object? json) {
    if (json is! Map || json['app'] != 'envanter') return null;
    final deviceId = json['deviceId'];
    final inventoryId = json['inventoryId'];
    final port = json['port'];
    if (deviceId is! String || deviceId.isEmpty) return null;
    if (inventoryId is! String || inventoryId.isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    String text(Object? v) => v is String ? v : '';
    return Announcement(
      deviceId: deviceId,
      deviceName: text(json['deviceName']),
      inventoryId: inventoryId,
      inventoryName: text(json['inventoryName']),
      joinable: json['joinable'] == true,
      httpPort: port,
      stamp: text(json['stamp']),
      dataVersion: json['d'] is int ? json['d'] as int : 0,
    );
  }
}

/// Ağda görülen bir cihaz. Adresi duyurunun içinden değil, paketin geldiği
/// yerden alınır.
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.info,
    required this.address,
    required this.lastSeen,
  });

  final Announcement info;
  final InternetAddress address;
  final DateTime lastSeen;

  Uri get baseUri => Uri(scheme: 'http', host: address.address, port: info.httpPort);
}

/// UDP yayınıyla bulma. Sunucu yok: her cihaz kendini duyurur, herkes dinler.
///
/// Ağ sürekli taranmaz: cihaz kendini seyrek duyurur (üyeler birbirini
/// bulsun diye). Kullanıcı "ağı tara" deyince ya da uygulama açılınca bir
/// soru ([probe]) yayınlanır; onu duyan her cihaz hemen kendini duyurur.
///
/// Varsayılan hedefler 255.255.255.255 ve her IPv4 arayüzünün /24 yayın
/// adresi (x.y.z.255): Dart ağ maskesini vermiyor, evlerde neredeyse hep /24.
/// Konuk ağları gibi istemcileri birbirinden yalıtan ağlarda çalışmaz.
class LanDiscovery {
  LanDiscovery({
    this.port = defaultPort,
    List<(InternetAddress, int)>? targets,
    this.interval = const Duration(seconds: 30),
    this.expiry = const Duration(seconds: 95),
  }) : _fixedTargets = targets;

  static const defaultPort = 47810;

  final int port;
  final List<(InternetAddress, int)>? _fixedTargets;
  final Duration interval;
  final Duration expiry;

  RawDatagramSocket? _socket;
  Timer? _timer;
  Announcement Function()? _current;
  final Map<String, DiscoveredPeer> _peers = {};
  final _controller = StreamController<List<DiscoveredPeer>>.broadcast();

  /// Görülen cihazlar her değiştiğinde (biri gelince ya da düşünce).
  Stream<List<DiscoveredPeer>> get changes => _controller.stream;
  List<DiscoveredPeer> get peers => List.unmodifiable(_peers.values);
  bool get running => _socket != null;

  Future<void> start(Announcement Function() current) async {
    if (_socket != null) return;
    _current = current;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event == RawSocketEvent.read) _receive(socket);
    });
    _socket = socket;
    _timer = Timer.periodic(interval, (_) => _tick());
    unawaited(_announce());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
    if (_peers.isNotEmpty) {
      _peers.clear();
      _controller.add(peers);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  /// Duyuruyu hemen gönder (ör. ad değişince beklemeden).
  Future<void> announceNow() => _announce();

  /// "Ağda kim var?" sorusu: duyan cihazlar hemen kendini duyurur.
  Future<void> probe() async {
    final mine = _current?.call();
    if (_socket == null || mine == null) return;
    await _send(utf8.encode(jsonEncode({'app': 'envanter', 'v': 1, 'probe': true, 'deviceId': mine.deviceId})));
    await _announce();
  }

  DateTime _lastProbeAnswer = DateTime.fromMillisecondsSinceEpoch(0);

  void _receive(RawDatagramSocket socket) {
    Datagram? d;
    while ((d = socket.receive()) != null) {
      final datagram = d!;
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(datagram.data));
      } on Object {
        continue; // başka bir uygulamanın paketi
      }
      final mine = _current?.call();
      if (json is Map && json['app'] == 'envanter' && json['probe'] == true) {
        // Birisi ağı tarıyor: hemen duyur (sık sorulara saniyede bir yanıt).
        final now = DateTime.now();
        if (json['deviceId'] != mine?.deviceId && now.difference(_lastProbeAnswer).inMilliseconds > 800) {
          _lastProbeAnswer = now;
          unawaited(_announce());
        }
        continue;
      }
      final info = Announcement.fromJson(json);
      if (info == null || info.deviceId == mine?.deviceId) continue;
      final isNew = !_peers.containsKey(info.deviceId);
      final previous = _peers[info.deviceId];
      _peers[info.deviceId] = DiscoveredPeer(
        info: info,
        address: datagram.address,
        lastSeen: DateTime.now(),
      );
      final changed = isNew ||
          previous!.info.inventoryName != info.inventoryName ||
          previous.info.inventoryId != info.inventoryId ||
          previous.info.joinable != info.joinable ||
          previous.info.deviceName != info.deviceName ||
          previous.address != datagram.address;
      if (changed) _controller.add(peers);
    }
  }

  void _tick() {
    final cutoff = DateTime.now().subtract(expiry);
    final before = _peers.length;
    _peers.removeWhere((_, p) => p.lastSeen.isBefore(cutoff));
    if (_peers.length != before) _controller.add(peers);
    unawaited(_announce());
  }

  Future<void> _announce() async {
    final current = _current;
    if (_socket == null || current == null) return;
    await _send(utf8.encode(jsonEncode(current().toJson())));
  }

  Future<void> _send(List<int> data) async {
    final socket = _socket;
    if (socket == null) return;
    for (final (address, port) in await _targets()) {
      try {
        socket.send(data, address, port);
      } on SocketException {
        // Arayüz o an kullanılamıyor (ör. Wi-Fi yeni koptu): sonraki turda.
      }
    }
  }

  Future<List<(InternetAddress, int)>> _targets() async {
    final fixed = _fixedTargets;
    if (fixed != null) return fixed;
    final targets = <(InternetAddress, int)>[(InternetAddress('255.255.255.255'), port)];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          targets.add((InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'), port));
        }
      }
    } on SocketException {
      // Arayüz listesi alınamazsa genel yayın adresi yeter.
    }
    return targets;
  }
}
