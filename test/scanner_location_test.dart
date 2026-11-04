import 'package:envanter/services/location_service.dart';
import 'package:envanter/services/platform_bridge.dart';
import 'package:envanter/ui/scan_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('envanter/platform');

/// Yerel tarafın yerine: [answer] her çağrıya döner, çağrılar [calls]'a yazılır.
List<MethodCall> _fakeNative(Object? Function(MethodCall call) answer) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    return answer(call);
  });
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
  );

  group('tarayıcının gördüğü kodlar', () {
    final t0 = DateTime(2026, 11, 4, 12);
    const can = (text: '8690000000017', qr: false);
    const label = (text: 'envanter:abc', qr: true);

    test('görüş alanında duran kod bir kez sayılır, gözden çıkıp dönünce yeniden', () {
      final seen = SeenCodes();
      expect(seen.fresh([can], t0), [can]);
      // Her karede yeniden okunuyor: hâlâ aynı kutu.
      expect(seen.fresh([can], t0.add(const Duration(milliseconds: 300))), isEmpty);
      expect(seen.fresh([can], t0.add(const Duration(milliseconds: 1200))), isEmpty);
      // Bir saniyeden uzun okunmadı (kutu çekildi), sonra aynı üründen ikincisi geldi.
      expect(seen.fresh([can], t0.add(const Duration(milliseconds: 2400))), [can]);
    });

    test('yanında duran kod yeni gelenin sayılmasını engellemez', () {
      final seen = SeenCodes();
      expect(seen.fresh([can], t0), [can]);
      expect(seen.fresh([can, label], t0.add(const Duration(milliseconds: 200))), [label]);
      expect(seen.fresh([label, can], t0.add(const Duration(milliseconds: 400))), isEmpty);
    });
  });

  group('kare okuma', () {
    test('karenin parlaklık düzlemi ve biçimler yerel tarafa gider, sonuçlar ayrılır', () async {
      final calls = _fakeNative((_) => [
            {'text': 'envanter:abc', 'qr': true},
            {'text': '8690000000017', 'qr': false},
            {'qr': true}, // metni olmayan (ikili içerikli) kod atlanır
          ]);
      final codes = await PlatformBridge.readBarcodes(
        bytes: Uint8List(8 * 4),
        width: 6,
        height: 4,
        stride: 8,
        rotation: 90,
        formats: [ScanPage.qrFormat, ...ScanPage.productFormats],
      );
      expect(codes, [(text: 'envanter:abc', qr: true), (text: '8690000000017', qr: false)]);
      expect(calls.single.method, 'readBarcodes');
      final args = calls.single.arguments as Map;
      expect([args['width'], args['height'], args['stride'], args['rotation']], [6, 4, 8, 90]);
      expect((args['bytes'] as Uint8List).length, 32);
      expect(args['formats'], ['QR_CODE_MODEL_2', 'EAN_13', 'EAN_8', 'UPC_A', 'UPC_E', 'CODE_128', 'CODE_39_STD']);
    });

    test('yerel taraf yoksa ya da hata verirse hiçbir şey okunmamış sayılır', () async {
      Future<List<({String text, bool qr})>> read() => PlatformBridge.readBarcodes(
            bytes: Uint8List(4),
            width: 2,
            height: 2,
            stride: 2,
            rotation: 0,
            formats: ScanPage.productFormats,
          );
      expect(await read(), isEmpty);
      _fakeNative((_) => throw PlatformException(code: 'x'));
      expect(await read(), isEmpty);
    });
  });

  group('konum', () {
    test('yerel tarafın cevabı arayüzün beklediği hatalara çevrilir', () async {
      for (final (error, failure) in [
        ('off', LocationFailure.serviceOff),
        ('denied', LocationFailure.denied),
        ('deniedForever', LocationFailure.deniedForever),
        ('unavailable', LocationFailure.unknown),
      ]) {
        _fakeNative((_) => {'error': error});
        await expectLater(LocationService.current(), throwsA(failure), reason: error);
      }
    });

    test('yerel taraf yoksa ya da hata verirse yine LocationFailure', () async {
      await expectLater(LocationService.current(), throwsA(LocationFailure.unknown));
      _fakeNative((_) => throw PlatformException(code: 'x'));
      await expectLater(LocationService.current(), throwsA(LocationFailure.unknown));
    });

    test('bulunan konum döner; adres bulunamazsa etiket boş kalır', () async {
      final calls = _fakeNative((_) => {'lat': 41.0151, 'lng': 28.9795});
      final result = await LocationService.current();
      expect([result.lat, result.lng, result.label], [41.0151, 28.9795, null]);
      expect(calls.single.method, 'currentLocation');
    });
  });
}
