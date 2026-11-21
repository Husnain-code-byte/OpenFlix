import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/main.dart';

void main() {
  test('OpenFlixApp can be constructed', () {
    expect(const OpenFlixApp(), isA<Widget>());
    expect(const PixelApp(), isA<Widget>());
  });
}