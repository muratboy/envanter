import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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
  /// Izin ister, konumu alir ve mümkünse adrese çevirir.
  static Future<GeoResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationFailure.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationFailure.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationFailure.deniedForever;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return GeoResult(pos.latitude, pos.longitude, await describe(pos.latitude, pos.longitude));
  }

  /// Ters coğrafi kodlama başarısız olabilir; o zaman etiket boş kalir.
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
    } on Exception {
      return null;
    }
  }

  static String format(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}
