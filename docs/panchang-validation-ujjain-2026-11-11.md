# Panchang reference baseline — Ujjain — 2026-11-11

Purpose: establish a dated, location-specific comparison fixture before changing calendar rules.
This is a reference snapshot, not a claim that the app engine has passed validation.

## Place and civil date
- Place: Ujjain, Madhya Pradesh, India
- Drik Panchang place selector: geoname-id=1253914
- Civil date: Wednesday, 11 November 2026
- Time zone: Asia/Kolkata (IST, UTC+05:30)

## Drik Panchang reference values
Source: https://www.drikpanchang.com/panchang/month-panchang.html?geoname-id=1253914
- Sunrise: 06:38
- Sunset: 17:44
- Moonrise: 08:27
- Moonset: 18:59
- Shaka Samvat: 1948, Parabhava
- Vikram Samvat: 2083, Siddharthi
- Gujarati Samvat: 2083, Kalayukta
- Amanta month: Kartika
- Purnimanta month: Kartika
- Weekday: Budhawara
- Paksha: Shukla Paksha
- Tithi: Dwitiya until 15:53
- Nakshatra: Anuradha until 11:38
- Yoga: Atiganda until 03:40 on 12 November
- Karana: Kaulava until 15:53
- Karana: Taitila until 04:58 on 12 November
- Sun sign: Tula
- Moon sign: Vrishchika

## Independent comparison
Source: https://panchangsaathi.com/calendar/ujjain/
- Sunrise: 06:38
- Sunset: 17:44
- Moonrise: 08:23
- Moonset: 19:03
- Tithi: Shukla Dwitiya until 15:54
- Nakshatra: Anuradha until 11:38
- Yoga: Atiganda until 03:40 on 12 November
- Karana: Kaulava until 15:54
- Samvatsara: Parabhava
- Amanta/Purnimanta month: Kartika

## Validation interpretation
- The sunrise/sunset, tithi, nakshatra and yoga references agree to the displayed minute (tithi differs by one minute).
- Moonrise/moonset differ by four minutes between the two sources. Do not silently force a match: inspect horizon/refraction, parallax, ephemeris and rounding conventions.
- The Drik page's stated local-time convention and sunrise-based Hindu day boundary must be respected.
- The engine's current moonrise/moonset and ascendant implementations are not yet independently validated against this fixture.
- Month, Samvatsara and regional-year calculations must not be inferred from Gregorian-year arithmetic. Keep them explicitly marked unverified until their lunation/sankranti and regional new-year rules are implemented and tested.
- Never replace computed values with copied website values in production.

## Sources
- Drik Panchang Ujjain: https://www.drikpanchang.com/panchang/month-panchang.html?geoname-id=1253914
- Drik Panchang Gujarati Ujjain: https://www.drikpanchang.com/gujarati/panchang/gujarati-month-panchang.html?geoname-id=1253914
- PanchangSaathi Ujjain calendar: https://panchangsaathi.com/calendar/ujjain/
- Astronomia API documentation: https://pub.dev/documentation/astronomia/latest/astronomia/
