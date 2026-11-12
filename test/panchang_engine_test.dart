import 'package:flutter_test/flutter_test.dart';
import 'package:vaidikkarmkrite/panchang/panchang_engine.dart';

void main() {
  group('Marriage lagna defect classifications', () {
    test('daytime deaf, blind and lame signs follow Vivaha 6.81', () {
      expect(PanchangEngine.marriageLagnaDefect(6, isDaytime: true), 'बधिर लग्न');
      expect(PanchangEngine.marriageLagnaDefect(7, isDaytime: true), 'बधिर लग्न');
      for (final sign in [4, 0, 1]) {
        expect(PanchangEngine.marriageLagnaDefect(sign, isDaytime: true),
            'दिवान्ध लग्न');
      }
      expect(PanchangEngine.marriageLagnaDefect(10, isDaytime: true), 'पंगु लग्न');
    });

    test('nighttime deaf, blind and lame signs follow Vivaha 6.81', () {
      for (final sign in [9, 8]) {
        expect(PanchangEngine.marriageLagnaDefect(sign, isDaytime: false),
            'बधिर लग्न');
      }
      for (final sign in [5, 2, 3]) {
        expect(PanchangEngine.marriageLagnaDefect(sign, isDaytime: false),
            'निशान्ध लग्न');
      }
      expect(PanchangEngine.marriageLagnaDefect(11, isDaytime: false), 'पंगु लग्न');
    });

    test('unlisted sign is not assigned one of these marriage defects', () {
      expect(PanchangEngine.marriageLagnaDefect(2, isDaytime: true), isNull);
      expect(PanchangEngine.marriageLagnaDefect(6, isDaytime: false), isNull);
    });

    test('rejects a sign index outside the zodiac', () {
      expect(() => PanchangEngine.marriageLagnaDefect(12, isDaytime: true),
          throwsRangeError);
    });
  });

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

    test('11 Nov 2026 Ujjain sunrise Panchang matches independent references', () {
      final sunrise = DateTime.utc(2026, 11, 11, 1, 8);
      final limbs = PanchangEngine.indicesAt(sunrise);

      // RealPanchang, Vedangam and PanchangSaathi independently report
      // Kartika Shukla Dwitiya and Anuradha at Ujjain sunrise.
      expect(limbs['tithi'], 1); // Shukla Dwitiya, zero-based
      expect(limbs['nakshatra'], 16); // Anuradha, zero-based
      expect(PanchangEngine.lunarMonthLabels(sunrise)['amanta'], 'कार्तिक');
      expect(PanchangEngine.lunarMonthLabels(sunrise)['purnimanta'], 'कार्तिक');
    });

    test('11 Nov 2026 Ujjain moonrise agrees with published reference', () {
      final events = PanchangEngine.moonEvents(
        localDate: DateTime(2026, 11, 11),
        latitude: latitude,
        longitude: longitude,
      );
      expect(events.rise, isNotNull);
      // Published Ujjain references cluster around 08:22–08:27 IST.
      final expectedUtc = DateTime.utc(2026, 11, 11, 2, 53);
      expect(events.rise!.toUtc().difference(expectedUtc).inSeconds.abs(),
          lessThanOrEqualTo(5 * 60));
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
