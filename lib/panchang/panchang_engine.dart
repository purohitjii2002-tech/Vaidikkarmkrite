import 'dart:math' as math;

import 'package:astronomia/astronomia.dart';
import 'package:astronomia/solar.dart' as solar;
import 'package:astronomia/moonposition.dart' as moon;
import 'package:astronomia/rise.dart' as rise;
import 'package:astronomia/sidereal.dart' as sid;
import 'package:astronomia/coord.dart' as coord;

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

  static int _karanaIndexForHalfTithi(int halfTithi) {
    // Kimstughna is the first half of Shukla Pratipada. The seven
    // movable karanas repeat for the next 56 half-tithis; the final
    // three are Shakuni, Chatushpada and Naga.
    return switch (halfTithi) {
      0 => 10,
      57 => 7,
      58 => 8,
      59 => 9,
      _ => (halfTithi - 1) % 7,
    };
  }

  static int _limbIndex(DateTime utc, String limb) {
    final angle = _limbAngle(utc, limb);
    switch (limb) {
      case 'tithi':
        return (angle / 12).floor();
      case 'karana':
        return _karanaIndexForHalfTithi((angle / 6).floor());
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

  /// Sidereal Moon longitude (Lahiri), normalized to 0..360 degrees.
  static double siderealMoonLongitude(DateTime instant) {
    final utc = instant.toUtc();
    final positions = tropicalLongitudes(utc);
    return _norm(positions.moon - lahiriAyanamsha(utc));
  }

  /// Fast limb indices at an arbitrary instant, without calculating end times.
  static Map<String, int> indicesAt(DateTime instant) {
    final utc = instant.toUtc();
    final positions = tropicalLongitudes(utc);
    final ayanamsha = lahiriAyanamsha(utc);
    final sun = _norm(positions.sun - ayanamsha);
    final moon = _norm(positions.moon - ayanamsha);
    final elongation = _norm(positions.moon - positions.sun);
    final halfTithi = (elongation / 6).floor();
    return {
      'tithi': (elongation / 12).floor(),
      'karana': _karanaIndexForHalfTithi(halfTithi),
      'nakshatra': (moon / (360 / 27)).floor(),
      'sunNakshatra': (sun / (360 / 27)).floor(),
      'yoga': (_norm(sun + moon) / (360 / 27)).floor(),
    };
  }

  /// Panchak: Moon's sidereal longitude from 300° (Dhanishtha pada 3)
  /// through the end of Revati at 360°. Returns the active or next interval.
  static ({DateTime start, DateTime end, bool active})? panchakWindow(DateTime instant) {
    final now = instant.toUtc();
    final from = now.subtract(const Duration(days: 8));
    final to = now.add(const Duration(days: 35));
    final starts = <DateTime>[];
    final ends = <DateTime>[];
    var previous = from;
    var previousLon = siderealMoonLongitude(previous);

    DateTime refine(DateTime lowStart, DateTime highStart, {required bool entering}) {
      var low = lowStart;
      var high = highStart;
      for (var i = 0; i < 36; i++) {
        final mid = low.add(Duration(microseconds:
            high.difference(low).inMicroseconds ~/ 2));
        final longitude = siderealMoonLongitude(mid);
        if (entering) {
          if (longitude >= 300.0) {
            high = mid;
          } else {
            low = mid;
          }
        } else {
          if (longitude >= 300.0) {
            low = mid;
          } else {
            high = mid;
          }
        }
      }
      return high;
    }

    for (var cursor = from.add(const Duration(hours: 3));
        !cursor.isAfter(to);
        cursor = cursor.add(const Duration(hours: 3))) {
      final longitude = siderealMoonLongitude(cursor);
      if (previousLon < 300.0 && longitude >= 300.0) {
        starts.add(refine(previous, cursor, entering: true));
      }
      if (previousLon >= 300.0 && longitude < 10.0) {
        ends.add(refine(previous, cursor, entering: false));
      }
      previous = cursor;
      previousLon = longitude;
    }

    DateTime? selectedStart;
    for (final value in starts) {
      if (!value.isAfter(now)) selectedStart = value;
    }
    if (selectedStart != null) {
      for (final end in ends) {
        if (end.isAfter(selectedStart)) {
          return (start: selectedStart.toLocal(), end: end.toLocal(),
            active: !now.isBefore(selectedStart) && now.isBefore(end));
        }
      }
    }
    for (final start in starts) {
      if (start.isAfter(now)) {
        for (final end in ends) {
          if (end.isAfter(start)) {
            return (start: start.toLocal(), end: end.toLocal(), active: false);
          }
        }
      }
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

    final karanaIndex = _karanaIndexForHalfTithi(halfTithi);

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

  /// Finds the Amanta and Purnimanta month labels from adjacent new moons.
  /// A lunation is named from the sidereal solar sign at its opening new moon;
  /// a lunation without a solar sign ingress is marked Adhika.
  static Map<String, String> lunarMonthLabels(DateTime instant) {
    const monthBySunSign = <String>[
      'वैशाख','ज्येष्ठ','आषाढ़','श्रावण','भाद्रपद','आश्विन',
      'कार्तिक','मार्गशीर्ष','पौष','माघ','फाल्गुन','चैत्र',
    ];
    double elongation(DateTime t) {
      final p = tropicalLongitudes(t.toUtc());
      return _norm(p.moon - p.sun);
    }
    // Find the most recent new-moon crossing (elongation wraps 360 -> 0).
    DateTime? left;
    DateTime? right;
    var newer = instant.toUtc();
    for (var h = 6; h <= 36 * 24; h += 6) {
      final older = instant.toUtc().subtract(Duration(hours: h));
      final a = elongation(older);
      final b = elongation(newer);
      if (a > 180 && b <= 180) { left = older; right = newer; break; }
      newer = older;
    }
    if (left == null || right == null) {
      return {'amanta': 'गणना उपलब्ध नहीं', 'purnimanta': 'गणना उपलब्ध नहीं'};
    }
    // Refine the 360° -> 0° crossing to within approximately one second.
    var lo = left;
    var hi = right;
    for (var i = 0; i < 36; i++) {
      final mid = lo.add(Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2));
      if (elongation(mid) > 180) { lo = mid; } else { hi = mid; }
    }
    final newMoon = hi;
    final sun = tropicalLongitudes(newMoon).sun;
    final sign = (_norm(sun - lahiriAyanamsha(newMoon)) / 30).floor() % 12;

    // A second new moon with the same sidereal solar sign means no Sankranti
    // occurred in this lunation: this is Adhika Maas.
    var nextLeft = newMoon;
    DateTime? nextRight;
    for (var h = 6; h <= 36 * 24; h += 6) {
      final candidate = newMoon.add(Duration(hours: h));
      if (elongation(nextLeft) < 180 && elongation(candidate) > 180) {
        // Search for the next wrap; the scan above brackets the opposite
        // half-cycle, so continue until the actual 360° -> 0° crossing.
      }
      final prevAngle = elongation(nextLeft);
      final currentAngle = elongation(candidate);
      if (prevAngle > 180 && currentAngle <= 180) { nextRight = candidate; break; }
      nextLeft = candidate;
    }
    var adhika = false;
    if (nextRight != null) {
      var a = nextLeft;
      var b = nextRight;
      for (var i = 0; i < 36; i++) {
        final mid = a.add(Duration(microseconds: b.difference(a).inMicroseconds ~/ 2));
        if (elongation(mid) > 180) { a = mid; } else { b = mid; }
      }
      final nextSign = (_norm(tropicalLongitudes(b).sun -
          lahiriAyanamsha(b)) / 30).floor() % 12;
      adhika = nextSign == sign;
    }
    final amanta = monthBySunSign[sign];
    final isKrishna = elongation(instant.toUtc()) >= 180;
    final purnimantaSign = isKrishna ? (sign + 1) % 12 : sign;
    final purnimanta = monthBySunSign[purnimantaSign];
    return {
      'amanta': adhika ? 'अधिक $amanta' : amanta,
      'purnimanta': adhika && !isKrishna
          ? 'अधिक $purnimanta' : purnimanta,
    };
  }

  /// Geocentric moonrise and moonset using Meeus rise/set interpolation.
  /// Longitude is east-positive in the app; astronomia uses west-positive.
  static ({DateTime? rise, DateTime? set, DateTime? transit}) moonEvents({
    required DateTime localDate,
    required double latitude,
    required double longitude,
  }) {
    final wanted = DateTime(localDate.year, localDate.month, localDate.day);
    final utcDate = DateTime.utc(localDate.year, localDate.month, localDate.day);

    DateTime? localEvent(double seconds, DateTime utcMidnight) =>
        utcMidnight.add(Duration(milliseconds: (seconds * 1000).round())).toLocal();

    DateTime? moonEventForUtcDate(DateTime day, String event) {
      final jd = julianDay(day);
      final theta0 = sid.apparent0UT(jd);
      final result = rise.moonTimes(
        jd, _rad(latitude), _rad(-longitude), 69, theta0, (jde) {
          final p = moon.position(jde);
          final eps = _rad(23.4393);
          final eq = coord.eclToEq(p.lon, p.lat, math.sin(eps), math.cos(eps));
          return (ra: eq.ra, dec: eq.dec, parallax: moon.parallax(p.delta));
        },
      );
      if (result == null) return null;
      final seconds = switch (event) {
        'rise' => result.rise,
        'set' => result.set,
        _ => result.transit,
      };
      return localEvent(seconds, day);
    }

    // India local midnight can fall on the previous UTC date. Evaluate both
    // adjacent UT dates, then retain only events belonging to the requested
    // local civil date so events around midnight are not lost or mislabelled.
    final previousUtcDate = utcDate.subtract(const Duration(days: 1));
    DateTime? choose(String event) {
      final candidates = [
        moonEventForUtcDate(previousUtcDate, event),
        moonEventForUtcDate(utcDate, event),
      ].whereType<DateTime>().where((value) =>
        value.year == wanted.year && value.month == wanted.month &&
        value.day == wanted.day).toList()..sort();
      return candidates.isEmpty ? null : candidates.first;
    }

    return (
      rise: choose('rise'),
      set: choose('set'),
      transit: choose('transit'),
    );
  }

  /// Geometric ascendant at a given instant, using local apparent sidereal
  /// time, true obliquity approximation and Lahiri sidereal correction.
  static double ascendantSiderealLongitude({
    required DateTime instant,
    required double latitude,
    required double longitude,
  }) {
    final utc = instant.toUtc();
    final jd = julianDay(utc);
    // astronomia.apparent(jd) returns Greenwich apparent sidereal time
    // in sidereal seconds, not radians. Convert seconds -> degrees -> radians.
    final greenwichSidereal = _rad(sid.apparent(jd) / 240.0);
    final localSidereal = greenwichSidereal + _rad(longitude);
    final t = (jd - 2451545.0) / 36525.0;
    final obliquity = _rad(23.439291 - 0.0130042 * t);
    final theta = localSidereal;
    final tropicalAscendant = _norm(_deg(math.atan2(
      math.cos(theta),
      -(math.sin(theta) * math.cos(obliquity) +
          math.tan(_rad(latitude)) * math.sin(obliquity)),
    )));
    return _norm(tropicalAscendant - lahiriAyanamsha(utc));
  }

  /// Traditional Shiva-vasa calculation: (tithi number × 2 + 5) mod 7.
  /// Tithi is counted continuously from Shukla Pratipada (1) to Amavasya (30).
  static Map<String, String> shivaVasa(int tithiNumber) {
    if (tithiNumber < 1 || tithiNumber > 30) {
      throw RangeError.range(tithiNumber, 1, 30, 'tithiNumber');
    }
    final remainder = (tithiNumber * 2 + 5) % 7;
    const places = <int, String>{
      1: 'कैलाश', 2: 'गौरी सन्निधि', 3: 'वृषभारूढ़ (नंदी)',
      4: 'सभा', 5: 'भोजन', 6: 'क्रीड़ा', 0: 'श्मशान',
    };
    const results = <int, String>{
      1: 'शुभ — सुख की प्राप्ति', 2: 'शुभ — सुख-सम्पदा',
      3: 'शुभ — अभीष्ट कार्यसिद्धि', 4: 'अनुकूल नहीं — संतापकारी',
      5: 'अनुकूल नहीं — पीड़ादायक', 6: 'अनुकूल नहीं — कष्टकारी',
      0: 'अनुकूल नहीं — अशुभ फल का संकेत',
    };
    return {'place': places[remainder]!, 'result': results[remainder]!,
      'remainder': remainder.toString(), 'formula': '($tithiNumber × 2 + 5) ÷ 7'};
  }

  /// Traditional Agni-vasa calculation: (tithi + weekday + 1) mod 4.
  /// Weekday is numbered Sunday=1 ... Saturday=7; tithi 1..30 from
  /// Shukla Pratipada. Remainders 0/3=Earth, 1=Sky, 2=Netherworld.
  static Map<String, String> agniVasa(int tithiNumber, int weekdaySundayOne) {
    if (tithiNumber < 1 || tithiNumber > 30) {
      throw RangeError.range(tithiNumber, 1, 30, 'tithiNumber');
    }
    if (weekdaySundayOne < 1 || weekdaySundayOne > 7) {
      throw RangeError.range(weekdaySundayOne, 1, 7, 'weekdaySundayOne');
    }
    final remainder = (tithiNumber + weekdaySundayOne + 1) % 4;
    final place = (remainder == 0 || remainder == 3)
        ? 'पृथ्वी' : remainder == 1 ? 'आकाश' : 'पाताल';
    final result = (remainder == 0 || remainder == 3)
        ? 'शुभ — हवन के लिए अनुकूल संकेत'
        : remainder == 1 ? 'अनुकूल नहीं — प्राण-हानि का पारंपरिक संकेत'
        : 'अनुकूल नहीं — धन-हानि का पारंपरिक संकेत';
    return {'place': place, 'result': result,
      'remainder': remainder.toString(),
      'formula': '($tithiNumber + $weekdaySundayOne + 1) ÷ 4'};
  }

  /// Solar rise/set using Meeus chapter 15 three-day interpolation.
  /// The standard solar altitude (-0°50′) includes the upper limb and
  /// mean atmospheric refraction. App longitudes are east-positive;
  /// astronomia expects west-positive.
  static DateTime? solarEvent({
    required DateTime localDate,
    required double latitude,
    required double longitude,
    required bool sunrise,
  }) {
    final utcMidnight = DateTime.utc(localDate.year, localDate.month, localDate.day);
    final jd = julianDay(utcMidnight);
    final th0 = sid.apparent0UT(jd);
    final p0 = solar.apparentEquatorial(jd - 1);
    final p1 = solar.apparentEquatorial(jd);
    final p2 = solar.apparentEquatorial(jd + 1);
    final result = rise.times(
      _rad(latitude),
      _rad(-longitude),
      69,
      rise.stdh0Solar,
      th0,
      [p0.ra, p1.ra, p2.ra],
      [p0.dec, p1.dec, p2.dec],
    );
    if (result == null) return null;
    final seconds = sunrise ? result.rise : result.set;
    return utcMidnight
        .add(Duration(milliseconds: (seconds * 1000).round()))
        .toLocal();
  }
}
