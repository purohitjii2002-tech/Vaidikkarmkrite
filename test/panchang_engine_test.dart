import 'package:flutter_test/flutter_test.dart';
import 'package:vaidikkarmkrite/panchang/panchang_engine.dart';

void main() {
  group('Ujjain Panchang astronomical reference checks', () {
    const latitude = 23.1765;
    const longitude = 75.7885;

    test('Meeus solar rise is close to the 11 Nov 2026 Ujjain reference', () {
      final sunrise = PanchangEngine.solarEvent(
        localDate: DateTime(2026, 11, 11),
        latitude: latitude,
        longitude: longitude,
        sunrise: true,
      );

      expect(sunrise, isNotNull);
      // Drik Panchang rounds Ujjain sunrise to 06:38 IST (01:08 UTC).
      // Allow a two-minute envelope for differences in coordinates/refraction.
      final expectedUtc = DateTime.utc(2026, 11, 11, 1, 8);
      expect(sunrise!.toUtc().difference(expectedUtc).inSeconds.abs(),
          lessThanOrEqualTo(120));
    });

    test('sunrise ascendant is Tula and Scorpio begins near 07:07 IST', () {
      // MyPanchang Ujjain Lagna table: 11 Nov 2026 Tula until 07:07:06 IST.
      final atSunrise = PanchangEngine.ascendantSiderealLongitude(
        instant: DateTime.utc(2026, 11, 11, 1, 9, 12),
        latitude: latitude,
        longitude: longitude,
      );
      expect(atSunrise, inInclusiveRange(203.5, 204.3)); // Tula ~23°54′

      final atScorpioIngress = PanchangEngine.ascendantSiderealLongitude(
        instant: DateTime.utc(2026, 11, 11, 1, 37, 6),
        latitude: latitude,
        longitude: longitude,
      );
      expect(atScorpioIngress, inInclusiveRange(209.7, 210.3));
    });
  });
}
