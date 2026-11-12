import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  group('KARMKRITE library structure', () {
    test('Panchang category is not exposed in the app modules', () {
      expect(
        modules.any((module) =>
            module.title.contains('पंचांग') ||
            module.title.toLowerCase().contains('panchang')),
        isFalse,
      );
    });

    test('core scripture and ritual departments remain available', () {
      final titles = modules.map((module) => module.title).toSet();
      expect(titles, contains('वेद एवं शास्त्र'));
      expect(titles, contains('कर्मकांड'));
      expect(titles, contains('मंत्र एवं स्तोत्र'));
      expect(titles, contains('षोडश संस्कार'));
      expect(titles, contains('ऑडियो एवं पुस्तकें'));
    });
  });
}
