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

    test('Amanta month changes at the exact new-moon boundary', () {
      final beforeNewMoon = DateTime.utc(2026, 11, 9, 6, 45);
      final afterNewMoon = DateTime.utc(2026, 11, 9, 7, 15);

      expect(PanchangEngine.indicesAt(beforeNewMoon)['tithi'], 29);
      expect(PanchangEngine.indicesAt(afterNewMoon)['tithi'], 0);

      final before = PanchangEngine.lunarMonthLabels(beforeNewMoon);
      final after = PanchangEngine.lunarMonthLabels(afterNewMoon);

      expect(before['amanta'], 'आश्विन');
      expect(after['amanta'], 'कार्तिक');
      expect(before['purnimanta'], 'कार्तिक');
      expect(after['purnimanta'], 'कार्तिक');
    });

    test('Purnimanta month changes at the exact full-moon boundary', () {
      final beforeFullMoon = DateTime.utc(2026, 11, 24, 14, 45);
      final afterFullMoon = DateTime.utc(2026, 11, 24, 15, 0);

      expect(PanchangEngine.indicesAt(beforeFullMoon)['tithi'], 14);
      expect(PanchangEngine.indicesAt(afterFullMoon)['tithi'], 15);

      final before = PanchangEngine.lunarMonthLabels(beforeFullMoon);
      final after = PanchangEngine.lunarMonthLabels(afterFullMoon);

      expect(before['amanta'], 'कार्तिक');
      expect(after['amanta'], 'कार्तिक');
      expect(before['purnimanta'], 'कार्तिक');
      expect(after['purnimanta'], 'मार्गशीर्ष');
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

    test('Ujjain ascendant follows the full published 12-sign transition table', () {
      // MyPanchang Ujjain, 11 Nov 2026; IST boundaries converted to UTC.
      final transitions = <(DateTime, double)>[
        (DateTime.utc(2026, 11, 11, 1, 37, 6), 210),
        (DateTime.utc(2026, 11, 11, 3, 53, 5), 240),
        (DateTime.utc(2026, 11, 11, 5, 58, 14), 270),
        (DateTime.utc(2026, 11, 11, 7, 44, 42), 300),
        (DateTime.utc(2026, 11, 11, 9, 17, 32), 330),
        (DateTime.utc(2026, 11, 11, 10, 48, 3), 0),
        (DateTime.utc(2026, 11, 11, 12, 28, 9), 30),
        (DateTime.utc(2026, 11, 11, 14, 26, 17), 60),
        (DateTime.utc(2026, 11, 11, 16, 39, 44), 90),
        (DateTime.utc(2026, 11, 11, 18, 55, 52), 120),
        (DateTime.utc(2026, 11, 11, 21, 7, 45), 150),
        (DateTime.utc(2026, 11, 11, 23, 18, 30), 180),
      ];
      for (final transition in transitions) {
        final actual = PanchangEngine.ascendantSiderealLongitude(
          instant: transition.$1,
          latitude: latitude,
          longitude: longitude,
        );
        final difference = ((actual - transition.$2 + 540) % 360) - 180;
        expect(
          difference.abs(),
          lessThan(0.8),
          reason: 'Lagna boundary mismatch at ' +
              transition.$1.toIso8601String() + ': got ' +
              actual.toString() + '°',
        );
      }
    });
  });

  group('Regional Samvatsara and Chaitradi era calculations', () {
    const latitude = 23.1765;
    const longitude = 75.7885;

    test('60-year southern cycle is anchored to IMD 1948 Parabhava', () {
      expect(PanchangEngine.southSamvatsaraForSakaYear(1948), 'पराभव');
      expect(PanchangEngine.southSamvatsaraForSakaYear(1949), 'प्लवंग');
      expect(PanchangEngine.southSamvatsaraForSakaYear(1950), 'कीलक');
      expect(PanchangEngine.southSamvatsaraAt(DateTime(2026, 4, 14)),
          'पराभव');
      expect(PanchangEngine.traditionalSakaSolarYearAt(DateTime(2026, 4, 14)),
          1948);
    });

    test('Mesha ingress is calculated near the published April dates', () {
      final ingress2026 = PanchangEngine.meshaSankrantiUtc(2026);
      final ingress2027 = PanchangEngine.meshaSankrantiUtc(2027);
      expect(ingress2026, isNotNull);
      expect(ingress2027, isNotNull);
      expect(ingress2026!.difference(DateTime.utc(2026, 4, 14)).inHours.abs(),
          lessThan(24));
      expect(ingress2027!.difference(DateTime.utc(2027, 4, 14)).inHours.abs(),
          lessThan(24));
    });

    test('Ujjain Chaitra Shukla Pratipada sets Vikram 2084 on 7 Apr 2027', () {
      final newYear = PanchangEngine.chaitraNewYearDate(
        year: 2027,
        latitude: latitude,
        longitude: longitude,
      );
      expect(newYear, DateTime(2027, 4, 7));
      expect(
        PanchangEngine.vikramSamvatChaitradi(
          localDate: DateTime(2027, 4, 6),
          latitude: latitude,
          longitude: longitude,
        ),
        2083,
      );
      expect(
        PanchangEngine.vikramSamvatChaitradi(
          localDate: DateTime(2027, 4, 7),
          latitude: latitude,
          longitude: longitude,
        ),
        2084,
      );
    });
  });
}
