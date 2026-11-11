import 'dart:math' as math;

import 'package:astronomia/astronomia.dart';
import 'package:astronomia/solar.dart' as solar;
import 'package:astronomia/moonposition.dart' as moon;

/// Local astronomical calculations for Vaidik Karmkrite.
/// Tithi/nakshatra/yoga are evaluated at the location's local sunrise.
class PanchangEngine {
  static const tithis = <String>[
    'प्रतिपदा','द्वितीया','तृतीया','चतुर्थी','पञ्चमी','षष्ठी','सप्तमी',
    'अष्टमी','नवमी','दशमी','एकादशी','द्वादशी','त्रयोदशी','चतुर्दशी','पूर्णिमा',
    'प्रतिपदा','द्वितीया','तृतीया','चतुर्थी','पञ्चमी','षष्ठी','सप्तमी',
    'अष्टमी','नवमी','दशमी','एकादशी','द्वादशी','त्रयोदशी','चतुर्दशी','अमावस्या',
  ];

  static const nakshatras = <String>[
    'अश्विनी','भरणी','कृत्तिका','रोहिणी','मृगशीर्ष','आर्द्रा','पुनर्वसु',
    'पुष्य','आश्लेषा','मघा','पूर्वा फाल्गुनी','उत्तरा फाल्गुनी','हस्त',
    'चित्रा','स्वाती','विशाखा','अनुराधा','ज्येष्ठा','मूल','पूर्वाषाढ़ा',
    'उत्तराषाढ़ा','श्रवण','धनिष्ठा','शतभिषा','पूर्वा भाद्रपद',
    'उत्तरा भाद्रपद','रेवती',
  ];

  static const yogas = <String>[
    'विष्कुम्भ','प्रीति','आयुष्मान','सौभाग्य','शोभन','अतिगण्ड','सुकर्मा',
    'धृति','शूल','गण्ड','वृद्धि','ध्रुव','व्याघात','हर्षण','वज्र','सिद्धि',
    'व्यतीपात','वरीयान','परिघ','शिव','सिद्ध','साध्य','शुभ','शुक्ल',
    'ब्रह्म','इन्द्र','वैधृति',
  ];

  static const karanas = <String>[
    'बव','बालव','कौलव','तैतिल','गर','वणिज','विष्टि',
    'शकुनि','चतुष्पद','नाग','किंस्तुघ्न',
  ];

  static double _norm(double x) => (x % 360 + 360) % 360;
  static double _rad(double x) => x * math.pi / 180;
  static double _deg(double x) => x * 180 / math.pi;

  static double julianDay(DateTime utc) {
    final d = DateTime.utc(utc.year, utc.month, utc.day);
    final fraction = (utc.hour + utc.minute / 60 + utc.second / 3600 +
        utc.millisecond / 3600000) / 24;
    return calendarGregorianToJD(d.year, d.month, d.day + fraction);
  }

  /// Mean Lahiri (Chitrapaksha) ayanamsha.
  ///
  /// Anchored to 24°13′19″ at 2026-01-01 00:00 UTC and advanced at
  /// 50.29 arcseconds/year. This is a mean-value model (not a full
  /// Swiss-Ephemeris true ayanamsha with nutation).
  static double lahiriAyanamsha(DateTime utc) {
    final instant = utc.toUtc();
    final epoch = DateTime.utc(2026, 1, 1);
    final elapsedYears = instant.difference(epoch).inMicroseconds /
        Duration.microsecondsPerDay / 365.2422;
    const epochDegrees = 24 + 13 / 60 + 19 / 3600;
    const annualPrecessionDegrees = 50.29 / 3600;
    return epochDegrees + elapsedYears * annualPrecessionDegrees;
  }

  static ({double sun, double moon}) tropicalLongitudes(DateTime utc) {
    final jd = julianDay(utc);
    final sunLon = _norm(_deg(solar.apparentLongitude(j2000Century(jd))));
    final moonLon = _norm(_deg(moon.position(jd).lon));
    return (sun: sunLon, moon: moonLon);
  }

  static double _limbAngle(DateTime utc, String limb) {
    final positions = tropicalLongitudes(utc);
    final ayanamsha = lahiriAyanamsha(utc);
    final siderealSun = _norm(positions.sun - ayanamsha);
    final siderealMoon = _norm(positions.moon - ayanamsha);
    switch (limb) {
      case 'tithi':
      case 'karana':
        return _norm(positions.moon - positions.sun);
      case 'nakshatra':
        return siderealMoon;
      case 'yoga':
        return _norm(siderealSun + siderealMoon);
      default:
        throw ArgumentError.value(limb, 'limb');
    }
  }

  static int _limbIndex(DateTime utc, String limb) {
    final angle = _limbAngle(utc, limb);
    switch (limb) {
      case 'tithi':
        return (angle / 12).floor();
      case 'karana':
        return (angle / 6).floor();
      case 'nakshatra':
      case 'yoga':
        return (angle / (360 / 27)).floor();
      default:
        throw ArgumentError.value(limb, 'limb');
    }
  }

  /// Finds the next limb transition after sunrise and refines it to
  /// approximately one-second precision using a bounded binary search.
  static DateTime? nextLimbEnd(DateTime localSunrise, String limb) {
    final start = localSunrise.toUtc();
    final initialIndex = _limbIndex(start, limb);
    var previous = start;
    for (var minute = 15; minute <= 36 * 60; minute += 15) {
      final current = start.add(Duration(minutes: minute));
      if (_limbIndex(current, limb) != initialIndex) {
        var low = previous;
        var high = current;
        for (var i = 0; i < 32; i++) {
          final middle = low.add(
            Duration(microseconds: high.difference(low).inMicroseconds ~/ 2),
          );
          if (_limbIndex(middle, limb) == initialIndex) {
            low = middle;
          } else {
            high = middle;
          }
        }
        return high.toLocal();
      }
      previous = current;
    }
    return null;
  }

  static Map<String, dynamic> atSunrise(DateTime localSunrise) {
    final utc = localSunrise.toUtc();
    final positions = tropicalLongitudes(utc);
    final ayanamsha = lahiriAyanamsha(utc);
    final siderealSun = _norm(positions.sun - ayanamsha);
    final siderealMoon = _norm(positions.moon - ayanamsha);
    final elongation = _norm(positions.moon - positions.sun);

    final tithiNumber = (elongation / 12).floor();
    final nakshatraRaw = siderealMoon / (360 / 27);
    final yogaRaw = _norm(siderealSun + siderealMoon) / (360 / 27);
    final halfTithi = (elongation / 6).floor();

    // Kimstughna is the first half of Shukla Pratipada (index 0).
    // The seven movable karanas then repeat for 56 half-tithis;
    // the final three are Shakuni, Chatushpada and Naga.
    final karanaIndex = switch (halfTithi) {
      0 => 10,
      57 => 7,
      58 => 8,
      59 => 9,
      _ => (halfTithi - 1) % 7,
    };

    return {
      'tithi': tithis[tithiNumber],
      'tithiNumber': tithiNumber + 1,
      'paksha': tithiNumber < 15 ? 'शुक्ल पक्ष' : 'कृष्ण पक्ष',
      'nakshatra': nakshatras[nakshatraRaw.floor() % 27],
      'nakshatraPada': (nakshatraRaw.remainder(1) * 4).floor() + 1,
      'yoga': yogas[yogaRaw.floor() % 27],
      'karana': karanas[karanaIndex],
      'tithiEnd': nextLimbEnd(localSunrise, 'tithi'),
      'nakshatraEnd': nextLimbEnd(localSunrise, 'nakshatra'),
      'yogaEnd': nextLimbEnd(localSunrise, 'yoga'),
      'karanaEnd': nextLimbEnd(localSunrise, 'karana'),
      'sunLongitude': positions.sun,
      'moonLongitude': positions.moon,
      'ayanamsha': ayanamsha,
      'engine': 'Meeus algorithms (MIT astronomia) + Karmkrite Panchang rules',
    };
  }

  /// NOAA solar event approximation. Longitude is east-positive.
  static DateTime? solarEvent({
    required DateTime localDate,
    required double latitude,
    required double longitude,
    required bool sunrise,
  }) {
    final day = DateTime(localDate.year, localDate.month, localDate.day)
        .difference(DateTime(localDate.year, 1, 1)).inDays + 1;
    final lngHour = longitude / 15;
    final t = day + ((sunrise ? 6 : 18) - lngHour) / 24;
    final meanAnomaly = 0.9856 * t - 3.289;
    final trueLongitude = _norm(meanAnomaly +
        1.916 * math.sin(_rad(meanAnomaly)) +
        0.020 * math.sin(2 * _rad(meanAnomaly)) + 282.634);
    var rightAscension = _norm(_deg(math.atan(
        0.91764 * math.tan(_rad(trueLongitude)))));
    rightAscension += (trueLongitude ~/ 90) * 90 -
        (rightAscension ~/ 90) * 90;
    rightAscension /= 15;
    final sinDeclination = 0.39782 * math.sin(_rad(trueLongitude));
    final cosDeclination = math.cos(math.asin(sinDeclination));
    final cosHourAngle = (math.cos(_rad(90.833)) -
        sinDeclination * math.sin(_rad(latitude))) /
        (cosDeclination * math.cos(_rad(latitude)));
    if (cosHourAngle.abs() > 1) return null;
    final hourAngle = (sunrise
        ? 360 - _deg(math.acos(cosHourAngle))
        : _deg(math.acos(cosHourAngle))) / 15;
    final localMeanTime = hourAngle + rightAscension - 0.06571 * t - 6.622;
    final utcHour = (localMeanTime - lngHour) % 24;
    final utcMidnight = DateTime.utc(localDate.year, localDate.month, localDate.day);
    return utcMidnight.add(Duration(milliseconds: (utcHour * 3600000).round()))
        .toLocal();
  }
}
