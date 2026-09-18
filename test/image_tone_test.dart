import 'dart:io';
import 'dart:typed_data';

import 'package:envanter/core/palette.dart';
import 'package:envanter/services/image_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List solid(int r, int g, int b) {
  final im = img.Image(width: 40, height: 40);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('canlı fotoğrafa tonu en yakın kart rengi', () {
    final red = nearestPaletteColor(const Color(0xFFD03030));
    final hue = HSVColor.fromColor(red).hue;
    expect(hue < 20 || hue > 340, isTrue, reason: 'kırmızıya kırmızımsı: $hue');
    final green = HSVColor.fromColor(nearestPaletteColor(const Color(0xFF3FA050))).hue;
    expect(green, inInclusiveRange(90, 170));
  });

  test('soluk fotoğrafa nötr renk', () {
    final grey = nearestPaletteColor(const Color(0xFF8A8A8A));
    expect(HSVColor.fromColor(grey).saturation, lessThan(0.35));
  });

  test('baskın ton doygun piksellerden gelir, beyaz zemin soldurmaz', () {
    // Beyaz zemin üzerinde mavi bir nesne.
    final im = img.Image(width: 40, height: 40);
    img.fill(im, color: img.ColorRgb8(245, 245, 245));
    img.fillRect(im, x1: 12, y1: 12, x2: 28, y2: 28, color: img.ColorRgb8(40, 90, 200));
    final tone = Color(dominantTone(Uint8List.fromList(img.encodePng(im)))!);
    final hsv = HSVColor.fromColor(tone);
    expect(hsv.hue, inInclusiveRange(200, 240));
    expect(hsv.saturation, greaterThan(0.3));
    expect(dominantTone(solid(250, 250, 250)), isNotNull);
    expect(dominantTone(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('gerçek fotoğrafta çalışır', () {
    final bytes = File('test/fixtures/visual/stored_kutu.jpg').readAsBytesSync();
    expect(dominantTone(bytes), isNotNull);
  });
}
