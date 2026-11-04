import 'package:geocoding/geocoding.dart';

import 'platform_bridge.dart';

class GeoResult {
  const GeoResult(this.lat, this.lng, this.label);
  final double lat;
  final double lng;
  final String? label;
}

/// Konum alınamama nedeni; metni arayüz katmanı dile çevirir.
enum LocationFailure implements Exception {
  serviceOff,
  denied,
  deniedForever,
  unknown,
}

class LocationService {
  /// Izin ister, konumu alir ve mümkünse adrese çevirir. Konum ve izin yerel tarafta, Android'in kendi
  /// konum hizmetinden (geolocator Google Play Hizmetleri'nin kapalı kaynak kütüphanesini getiriyordu).
  /// Başarısızlık her zaman [LocationFailure]: arayüz yalnızca onu yakalıyor.
  static Future<GeoResult> current() async {
    final fix = await PlatformBridge.currentLocation();
    final lat = fix['lat'];
    final lng = fix['lng'];
    if (lat is! double || lng is! double) {
      throw switch (fix['error']) {
        'off' => LocationFailure.serviceOff,
        'denied' => LocationFailure.denied,
        'deniedForever' => LocationFailure.deniedForever,
        _ => LocationFailure.unknown,
      };
    }
    return GeoResult(lat, lng, await describe(lat, lng));
  }

  /// Ters coğrafi kodlama başarısız olabilir; o zaman etiket boş kalir. Eklentisi hiç yüklenemediyse
  /// `Geocoding()` bir Error fırlatıyor: o da yakalanır, bulunan konum adressiz de olsa döner.
  static Future<String?> describe(double lat, double lng) async {
    try {
      final geocoding = Geocoding();
      if (!await geocoding.isPresent()) return null;
      final places = await geocoding.placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return null;
      final pl = places.first;
      final parts = [
        pl.street,
        pl.subLocality,
        pl.locality,
        pl.administrativeArea,
      ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().toList();
      if (parts.isEmpty) return null;
      return parts.take(3).join(', ');
    } on Object {
      return null;
    }
  }

  static String format(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}
