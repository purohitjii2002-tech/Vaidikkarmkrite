import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'panchang_engine.dart';

class PanchangScreen extends StatefulWidget {
  final String language;
  const PanchangScreen({super.key, required this.language});
  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

class _PanchangScreenState extends State<PanchangScreen> {
  DateTime selectedDate = DateTime.now();
  Position? position;
  String city = 'स्थान पता किया जा रहा है...';
  bool _manualLocationSelected = false;
  String? error;
  Map<String, dynamic>? data;
  DateTime? sunrise, sunset, moonrise, moonset;
  List<Map<String, String>> _specialYogaRows = [];
  ({DateTime start, DateTime end, bool active})? _panchakWindow;
  double? sunriseAscendant;
  bool loading = true;
  int selectedMuhuratTab = 0;
  Timer? _liveTimer;
  DateTime _liveNow = DateTime.now();

  @override
  void initState() {
    super.initState();
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _liveNow = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() { _liveTimer?.cancel(); super.dispose(); }

  // Ujjain is the standard fallback when location permission/service is unavailable.
  static const double _ujjainLatitude = 23.1765;
  static const double _ujjainLongitude = 75.7885;

  Position _positionAt(double latitude, double longitude) => Position(
    latitude: latitude, longitude: longitude, timestamp: DateTime.now(),
    accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0,
    headingAccuracy: 0, speed: 0, speedAccuracy: 0,
  );

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = null; });
    if (!_manualLocationSelected) {
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          if (await Geolocator.isLocationServiceEnabled()) {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 15),
              ),
            );
            try {
              final places = await placemarkFromCoordinates(
                position!.latitude, position!.longitude,
              );
              if (places.isNotEmpty) {
                final p = places.first;
                city = [p.locality, p.subAdministrativeArea, p.administrativeArea]
                    .where((x) => x != null && x.trim().isNotEmpty).toSet().join(', ');
              } else {
                city = 'वर्तमान स्थान';
              }
            } catch (_) {
              city = 'वर्तमान स्थान';
            }
          } else {
            position = null;
          }
        } else {
          position = null;
        }
      } catch (_) {
        // Permission denied, GPS disabled, timeout, or location service failure.
        position = null;
      }
    }

    if (position == null) {
      position = _positionAt(_ujjainLatitude, _ujjainLongitude);
      city = 'उज्जैन (मानक स्थान)';
    }
    _calculate();
    if (mounted) setState(() { loading = false; error = null; });
  }

  Future<List<({Location location, String label})>> _searchGlobalPlaces(
    String query,
  ) async {
    // Photon uses OpenStreetMap data and supports worldwide place search.
    // Search in both Hindi and English so either script can find mapped places.
    final results = <({Location location, String label})>[];
    final seen = <String>{};
    for (final language in ['hi', 'en']) {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'limit': '8',
        'lang': language,
      });
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'VaidikKarmkrite/1.0 (Panchang location search)'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('Place search service unavailable');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = (decoded['features'] as List<dynamic>? ?? []);
      for (final feature in features) {
        final item = feature as Map<String, dynamic>;
        final geometry = item['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>?;
        final properties = item['properties'] as Map<String, dynamic>? ?? {};
        if (coordinates == null || coordinates.length < 2) continue;
        final longitude = (coordinates[0] as num).toDouble();
        final latitude = (coordinates[1] as num).toDouble();
        final key = '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
        if (!seen.add(key)) continue;

        String value(String key) => (properties[key] ?? '').toString().trim();
        final name = value('name').isNotEmpty
            ? value('name')
            : (value('city').isNotEmpty ? value('city') : query);
        final parts = <String>[
          name,
          value('district').isNotEmpty ? value('district') : value('county'),
          value('state'),
          value('country'),
        ].where((part) => part.trim().isNotEmpty).toSet().toList();
        final category = value('type').isNotEmpty ? value('type') : value('osm_value');
        final label = [
          parts.join(', '),
          if (category.isNotEmpty) category,
        ].join(' · ');
        results.add((
          location: Location(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.now(),
          ),
          label: label,
        ));
      }
    }
    return results;
  }

  Future<void> _chooseLocation() async {
    final controller = TextEditingController();
    Timer? searchTimer;
    var requestNumber = 0;
    var suggestions = <({Location location, String label})>[];
    var searching = false;
    var searchError = '';

    final selected = await showDialog<({Location location, String label})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('पंचांग के लिए स्थान चुनें'),
          content: SizedBox(
            width: 420,
            height: 390,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'गाँव / शहर / तहसील / जिला खोजें',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    searchTimer?.cancel();
                    final query = value.trim();
                    final thisRequest = ++requestNumber;
                    if (query.length < 2) {
                      setDialogState(() {
                        suggestions = [];
                        searching = false;
                        searchError = '';
                      });
                      return;
                    }
                    setDialogState(() {
                      searching = true;
                      searchError = '';
                    });
                    searchTimer = Timer(const Duration(milliseconds: 550), () async {
                      try {
                        final found = await _searchGlobalPlaces(query);
                        if (!dialogContext.mounted || thisRequest != requestNumber) return;
                        setDialogState(() {
                          suggestions = found;
                          searching = false;
                          searchError = found.isEmpty ? 'कोई स्थान नहीं मिला। नाम हिंदी या English में आज़माएँ।' : '';
                        });
                      } catch (_) {
                        if (!dialogContext.mounted || thisRequest != requestNumber) return;
                        setDialogState(() {
                          suggestions = [];
                          searching = false;
                          searchError = 'खोज पूरी नहीं हो सकी। इंटरनेट चालू करके फिर प्रयास करें।';
                        });
                      }
                    });
                  },
                  onSubmitted: (value) {
                    if (suggestions.length == 1) {
                      searchTimer?.cancel();
                      Navigator.pop(dialogContext, suggestions.first);
                    }
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: searching
                      ? const Center(child: CircularProgressIndicator())
                      : suggestions.isNotEmpty
                          ? ListView.separated(
                              itemCount: suggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = suggestions[index];
                                return ListTile(
                                  dense: false,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                  leading: const Icon(Icons.location_on_outlined,
                                      color: Color(0xFF79502B)),
                                  title: Text(item.label,
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    '${item.location.latitude.toStringAsFixed(4)}, '
                                    '${item.location.longitude.toStringAsFixed(4)}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  onTap: () {
                                    searchTimer?.cancel();
                                    Navigator.pop(dialogContext, item);
                                  },
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                searchError.isNotEmpty
                                    ? searchError
                                    : 'हिंदी या English में नाम लिखें। नीचे स्थानों के सुझाव आएँगे।',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                searchTimer?.cancel();
                Navigator.pop(dialogContext);
              },
              child: const Text('रद्द करें'),
            ),
          ],
        ),
      ),
    );
    searchTimer?.cancel();
    controller.dispose();
    if (selected == null || !mounted) return;

    setState(() => loading = true);
    final match = selected.location;
    final newPosition = _positionAt(match.latitude, match.longitude);
    if (!mounted) return;
    setState(() {
      position = newPosition;
      city = selected.label;
      _manualLocationSelected = true;
      _calculate();
      loading = false;
    });
  }

  void _calculate() {
    if (position == null) return;
    final date = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    sunrise = PanchangEngine.solarEvent(
      localDate: date, latitude: position!.latitude,
      longitude: position!.longitude, sunrise: true,
    );
    sunset = PanchangEngine.solarEvent(
      localDate: date, latitude: position!.latitude,
      longitude: position!.longitude, sunrise: false,
    );
    data = sunrise != null && sunset != null
        ? PanchangEngine.atSunrise(sunrise!) : null;
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: date.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    );
    _specialYogaRows = sunrise != null && nextSunrise != null
        ? _calculateSpecialYogas(sunrise!, nextSunrise, date.weekday % 7)
        : [];
    _panchakWindow = sunrise == null ? null
        : PanchangEngine.panchakWindow(sunrise!);
    if (position != null && sunrise != null) {
      final lunar = PanchangEngine.moonEvents(localDate: date,
        latitude: position!.latitude, longitude: position!.longitude);
      moonrise = lunar.rise;
      moonset = lunar.set;
      sunriseAscendant = PanchangEngine.ascendantSiderealLongitude(
        instant: sunrise!, latitude: position!.latitude,
        longitude: position!.longitude);
    } else { moonrise = null; moonset = null; sunriseAscendant = null; }
  }

  String _date(DateTime d) => d.day.toString().padLeft(2, '0') + '/' +
      d.month.toString().padLeft(2, '0') + '/' + d.year.toString();
  String _time(DateTime? d) {
    if (d == null) return 'उपलब्ध नहीं';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return h.toString().padLeft(2, '0') + ':' +
        d.minute.toString().padLeft(2, '0') + (d.hour < 12 ? ' AM' : ' PM');
  }
  String _weekday(DateTime d) => const [
    'सोमवार','मंगलवार','बुधवार','गुरुवार','शुक्रवार','शनिवार','रविवार'
  ][d.weekday - 1];

  String? _rahuKaal() {
    if (sunrise == null || sunset == null) return null;
    const segments = [8, 2, 7, 5, 6, 4, 3];
    final index = segments[selectedDate.weekday % 7];
    final seconds = sunset!.difference(sunrise!).inSeconds / 8;
    final start = sunrise!.add(Duration(seconds: (seconds * (index - 1)).round()));
    final end = sunrise!.add(Duration(seconds: (seconds * index).round()));
    return _time(start) + ' – ' + _time(end);
  }


  DateTime? _partTime(DateTime? start, DateTime? end, int part, int total) {
    if (start == null || end == null) return null;
    return start.add(Duration(milliseconds:
      (end.difference(start).inMilliseconds * part / total).round()));
  }

  List<Map<String, String>> _eightParts(DateTime? start, DateTime? end, List<String> names) {
    if (start == null || end == null || names.length != 8) return [];
    return List.generate(8, (i) {
      final a = _partTime(start, end, i, 8)!;
      final b = _partTime(start, end, i + 1, 8)!;
      final name = names[i];
      final good = ['अमृत','शुभ','लाभ','चर'].contains(name);
      return {'name': name, 'time': _time(a) + ' – ' + _time(b),
        'kind': good ? 'शुभ' : 'अशुभ'};
    });
  }

  List<Map<String, String>> _choghadiya(bool night) {
    if (sunrise == null || sunset == null) return [];
    const dayStarts = ['उद्वेग','अमृत','रोग','लाभ','शुभ','चर','काल'];
    const nightStarts = ['शुभ','अमृत','चर','रोग','काल','लाभ','उद्वेग'];
    const cycle = ['उद्वेग','चर','लाभ','अमृत','काल','शुभ','रोग'];
    final weekday = selectedDate.weekday % 7;
    final first = (night ? nightStarts : dayStarts)[weekday];
    final startIndex = cycle.indexOf(first);
    final names = List.generate(8, (i) => cycle[(startIndex + i) % 7]);
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    );
    return _eightParts(night ? sunset : sunrise,
      night ? nextSunrise : sunset, names);
  }

  List<Map<String, String>> _horaRows() {
    if (sunrise == null || sunset == null) return [];
    const planets = ['शनि','गुरु','मंगल','सूर्य','शुक्र','बुध','चन्द्र'];
    const weekdayLord = ['सूर्य','चन्द्र','मंगल','बुध','गुरु','शुक्र','शनि'];
    var index = planets.indexOf(weekdayLord[selectedDate.weekday % 7]);
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    ) ?? sunrise!.add(const Duration(days: 1));
    final rows = <Map<String, String>>[];
    for (var i = 0; i < 24; i++) {
      final a = i < 12 ? _partTime(sunrise, sunset, i, 12)! :
        _partTime(sunset, nextSunrise, i - 12, 12)!;
      final b = i < 12 ? _partTime(sunrise, sunset, i + 1, 12)! :
        _partTime(sunset, nextSunrise, i - 11, 12)!;
      rows.add({'name': '${planets[index]} होरा', 'time': '${_time(a)} – ${_time(b)}'});
      index = (index + 1) % planets.length;
    }
    return rows;
  }

  List<Map<String, String>> _dailyWindows() {
    if (sunrise == null || sunset == null) return [];
    final dayLength = sunset!.difference(sunrise!);
    final nightEnd = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    ) ?? sunrise!.add(const Duration(days: 1));
    final nightLength = nightEnd.difference(sunset!);
    final noon = sunrise!.add(Duration(milliseconds: dayLength.inMilliseconds ~/ 2));
    final midnight = sunset!.add(Duration(milliseconds: nightLength.inMilliseconds ~/ 2));
    String range(DateTime a, DateTime b) => '${_time(a)} – ${_time(b)}';
    const yama = [5,4,3,2,1,7,6];
    const gulika = [7,6,5,4,3,2,1];
    String segment(int number) => range(
      _partTime(sunrise, sunset, number - 1, 8)!,
      _partTime(sunrise, sunset, number, 8)!);
    final brahmaStart = sunrise!.subtract(const Duration(minutes: 96));
    final brahmaEnd = sunrise!.subtract(const Duration(minutes: 48));
    final abhijitHalf = Duration(milliseconds: dayLength.inMilliseconds ~/ 30);
    const godhuli = Duration(minutes: 24);
    final nishitaHalf = Duration(milliseconds: nightLength.inMilliseconds ~/ 30);
    final weekday = selectedDate.weekday % 7;
    return [
      {'name':'ब्रह्म मुहूर्त','time':range(brahmaStart,brahmaEnd),'kind':'शुभ'},
      {'name':'अभिजित मुहूर्त','time':range(noon.subtract(abhijitHalf),noon.add(abhijitHalf)),'kind':'शुभ'},
      {'name':'गोधूलि मुहूर्त','time':range(sunset!.subtract(godhuli),sunset!.add(godhuli)),'kind':'शुभ'},
      {'name':'निशिता काल','time':range(midnight.subtract(nishitaHalf),midnight.add(nishitaHalf)),'kind':'रात्रि'},
      {'name':'यमगण्ड','time':segment(yama[weekday]),'kind':'अशुभ'},
      {'name':'गुलिक काल','time':segment(gulika[weekday]),'kind':'अशुभ'},
    ];
  }

  // Current and next sunrise-based muhurta windows for the live dashboard.
  List<Map<String, dynamic>> _liveMuhurtaWindows() {
    if (position == null) return [];
    const rahu = [8, 2, 7, 5, 6, 4, 3];
    const yama = [5, 4, 3, 2, 1, 7, 6];
    const gulika = [7, 6, 5, 4, 3, 2, 1];
    // Traditional weekday-wise daytime Durmuhurta numbers, Sunday first.
    const durmuhurta = [[14], [9, 12], [4], [8], [6, 12], [4, 9], [1, 2]];
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; offset <= 1; offset++) {
      final day = DateTime(_liveNow.year, _liveNow.month, _liveNow.day)
          .add(Duration(days: offset));
      final rise = PanchangEngine.solarEvent(localDate: day,
          latitude: position!.latitude, longitude: position!.longitude,
          sunrise: true);
      final set = PanchangEngine.solarEvent(localDate: day,
          latitude: position!.latitude, longitude: position!.longitude,
          sunrise: false);
      if (rise == null || set == null) continue;
      final nextRise = PanchangEngine.solarEvent(localDate: day.add(const Duration(days: 1)),
          latitude: position!.latitude, longitude: position!.longitude,
          sunrise: true);
      final dayMs = set.difference(rise).inMilliseconds;
      final weekday = day.weekday % 7;
      void add(String name, DateTime start, DateTime end, String kind) {
        rows.add({'name': name, 'start': start, 'end': end, 'kind': kind});
      }
      DateTime part(int n, int total, {bool night = false}) {
        final a = night ? set : rise;
        final b = night ? (nextRise ?? set.add(const Duration(days: 1))) : set;
        return a.add(Duration(milliseconds:
            (b.difference(a).inMilliseconds * n / total).round()));
      }
      // Abhijit is the eighth daytime muhurta; Wednesday is traditionally avoided.
      if (weekday != DateTime.wednesday % 7) {
        final half = Duration(milliseconds: dayMs ~/ 30);
        final noon = rise.add(Duration(milliseconds: dayMs ~/ 2));
        add('अभिजित मुहूर्त', noon.subtract(half), noon.add(half), 'शुभ');
      }
      add('राहु काल', part(rahu[weekday] - 1, 8), part(rahu[weekday], 8), 'अशुभ');
      add('यमघण्ट / यमगण्ड', part(yama[weekday] - 1, 8), part(yama[weekday], 8), 'अशुभ');
      add('गुलिक काल', part(gulika[weekday] - 1, 8), part(gulika[weekday], 8), 'अशुभ');
      for (final n in durmuhurta[weekday]) {
        add('दुर्मुहूर्त', part(n - 1, 15), part(n, 15), 'अशुभ');
      }
    }
    rows.sort((a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime));
    return rows;
  }

  Widget _liveMuhurtaPanel() {
    final windows = _liveMuhurtaWindows();
    final active = windows.where((w) =>
      !_liveNow.isBefore(w['start'] as DateTime) &&
      _liveNow.isBefore(w['end'] as DateTime)).toList();
    final upcoming = windows.where((w) =>
      (w['start'] as DateTime).isAfter(_liveNow)).toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    final hasActive = active.isNotEmpty;
    final color = hasActive ? const Color(0xFFB3261E) : const Color(0xFF167443);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasActive ? const Color(0xFFFFEFED) : const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.schedule, color: color, size: 19),
          const SizedBox(width: 7),
          const Expanded(child: Text('अभी कौन-सा मुहूर्त / काल चल रहा है?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Text('LIVE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        if (hasActive) ...active.map((w) => Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 7),
            Expanded(child: Text('${w['name']} चल रहा है',
              style: TextStyle(color: color, fontWeight: FontWeight.w700))),
            Text(_remaining(w['end'] as DateTime),
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        )) else
          const Text('अभी अभिजित, राहु, गुलिक, यमघण्ट या दुर्मुहूर्त में से कोई काल नहीं चल रहा।',
            style: TextStyle(color: Color(0xFF286342), fontWeight: FontWeight.w600)),
        if (!hasActive && next != null) ...[
          const SizedBox(height: 6),
          Text('अगला: ${next['name']} • ${_time(next['start'] as DateTime)}–${_time(next['end'] as DateTime)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF654321))),
        ],
      ]),
    );
  }

  String _remaining(DateTime? end) {
    if (end == null) return 'समाप्ति समय उपलब्ध नहीं';
    final left = end.difference(_liveNow);
    if (left <= Duration.zero) return 'समाप्त';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    final s = left.inSeconds % 60;
    if (h > 0) return 'समाप्ति में ${h}घं ${m}मि शेष';
    if (m > 0) return 'समाप्ति में ${m}मि ${s}से शेष';
    return 'समाप्ति में ${s}से शेष';
  }

  DateTime? _nextLagnaEnd(double latitude, double longitude) {
    int sign(DateTime t) => (PanchangEngine.ascendantSiderealLongitude(
      instant:t, latitude:latitude, longitude:longitude) / 30).floor();
    final initial = sign(_liveNow);
    var low = _liveNow;
    var high = low.add(const Duration(minutes:1));
    for (var i=0; i<180; i++) {
      if (sign(high) != initial) {
        for (var j=0; j<24; j++) {
          final mid=low.add(Duration(microseconds:high.difference(low).inMicroseconds~/2));
          if (sign(mid)==initial) low=mid; else high=mid;
        }
        return high;
      }
      low=high;
      high=high.add(const Duration(minutes:1));
    }
    return null;
  }

  ({String name, DateTime start, DateTime end, bool good})? _liveChoghadiya() {
    if (position==null) return null;
    final today=DateTime(_liveNow.year,_liveNow.month,_liveNow.day);
    final todayRise=PanchangEngine.solarEvent(localDate:today,latitude:position!.latitude,longitude:position!.longitude,sunrise:true);
    final todaySet=PanchangEngine.solarEvent(localDate:today,latitude:position!.latitude,longitude:position!.longitude,sunrise:false);
    final nextRise=PanchangEngine.solarEvent(localDate:today.add(const Duration(days:1)),latitude:position!.latitude,longitude:position!.longitude,sunrise:true);
    final prev= today.subtract(const Duration(days:1));
    final prevSet=PanchangEngine.solarEvent(localDate:prev,latitude:position!.latitude,longitude:position!.longitude,sunrise:false);
    if(todayRise==null||todaySet==null||nextRise==null||prevSet==null) return null;
    final isDay=!_liveNow.isBefore(todayRise)&&_liveNow.isBefore(todaySet);
    final isEvening=!_liveNow.isBefore(todaySet);
    final start=isDay?todayRise:(isEvening?todaySet:prevSet);
    final end=isDay?todaySet:(isEvening?nextRise:todayRise);
    final weekday=(!isDay&&!isEvening?prev:today).weekday%7;
    const dayStarts=['उद्वेग','अमृत','रोग','लाभ','शुभ','चर','काल'];
    const nightStarts=['शुभ','अमृत','चर','रोग','काल','लाभ','उद्वेग'];
    const cycle=['उद्वेग','चर','लाभ','अमृत','काल','शुभ','रोग'];
    final first=(isDay?dayStarts:nightStarts)[weekday];
    final startIndex=cycle.indexOf(first);
    final elapsed=_liveNow.difference(start).inMilliseconds;
    final span=end.difference(start).inMilliseconds;
    if(elapsed<0||elapsed>=span||span<=0) return null;
    final slot=((elapsed*8)/span).floor().clamp(0,7);
    final a=start.add(Duration(milliseconds:(span*slot/8).round()));
    final b=start.add(Duration(milliseconds:(span*(slot+1)/8).round()));
    final name=cycle[(startIndex+slot)%7];
    return (name:name,start:a,end:b,good:['अमृत','शुभ','लाभ','चर'].contains(name));
  }

  ({String planet, DateTime start, DateTime end})? _liveHora() {
    if(position==null) return null;
    final today=DateTime(_liveNow.year,_liveNow.month,_liveNow.day);
    final rise=PanchangEngine.solarEvent(localDate:today,latitude:position!.latitude,longitude:position!.longitude,sunrise:true);
    final set=PanchangEngine.solarEvent(localDate:today,latitude:position!.latitude,longitude:position!.longitude,sunrise:false);
    final next=PanchangEngine.solarEvent(localDate:today.add(const Duration(days:1)),latitude:position!.latitude,longitude:position!.longitude,sunrise:true);
    final prev=today.subtract(const Duration(days:1));
    final prevRise=PanchangEngine.solarEvent(localDate:prev,latitude:position!.latitude,longitude:position!.longitude,sunrise:true);
    final prevSet=PanchangEngine.solarEvent(localDate:prev,latitude:position!.latitude,longitude:position!.longitude,sunrise:false);
    if(rise==null||set==null||next==null||prevRise==null||prevSet==null) return null;
    final isDay=!_liveNow.isBefore(rise)&&_liveNow.isBefore(set);
    final isEvening=!_liveNow.isBefore(set);
    final dayStart=isDay?rise:(isEvening?rise:prevRise);
    final dayEnd=isDay?set:(isEvening?set:prevSet);
    final nightStart=isDay?set:(isEvening?set:prevSet);
    final nightEnd=isDay?next:(isEvening?next:rise);
    const planets=['शनि','गुरु','मंगल','सूर्य','शुक्र','बुध','चन्द्र'];
    const lords=['सूर्य','चन्द्र','मंगल','बुध','गुरु','शुक्र','शनि'];
    final weekday=(!isDay&&!isEvening?prev:today).weekday%7;
    final first=planets.indexOf(lords[weekday]);
    final inDay=isDay;
    final start=inDay?dayStart:nightStart;
    final end=inDay?dayEnd:nightEnd;
    final part=inDay?0:12;
    final span=end.difference(start).inMilliseconds;
    final elapsed=_liveNow.difference(start).inMilliseconds;
    if(span<=0||elapsed<0||elapsed>=span) return null;
    final slot=((elapsed*12)/span).floor().clamp(0,11);
    final a=start.add(Duration(milliseconds:(span*slot/12).round()));
    final b=start.add(Duration(milliseconds:(span*(slot+1)/12).round()));
    return (planet:'${planets[(first+part+slot)%7]}',start:a,end:b);
  }

  Widget _liveDashboard() {
    final today=DateTime(_liveNow.year,_liveNow.month,_liveNow.day);
    final isToday=selectedDate.year==today.year&&selectedDate.month==today.month&&selectedDate.day==today.day;
    if(!isToday||position==null) return const SizedBox.shrink();
    final instantData=PanchangEngine.atSunrise(_liveNow);
    final months=PanchangEngine.lunarMonthLabels(_liveNow);
    final nakEnd=instantData['nakshatraEnd'] as DateTime?;
    final tithiEnd=instantData['tithiEnd'] as DateTime?;
    final ch=_liveChoghadiya();
    final hora=_liveHora();
    final lagna=PanchangEngine.ascendantSiderealLongitude(instant:_liveNow,latitude:position!.latitude,longitude:position!.longitude);
    final lagnaEnd=_nextLagnaEnd(position!.latitude,position!.longitude);
    Widget info(String label,String value,String sub,IconData icon,{Color color=const Color(0xFF654321),Color? tint}) => Expanded(
      child:Container(
        margin:const EdgeInsets.all(4),padding:const EdgeInsets.all(12),
        decoration:BoxDecoration(color:tint??const Color(0xFFFFF9EF),borderRadius:BorderRadius.circular(15),border:Border.all(color:color.withOpacity(.16))),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Icon(icon,size:17,color:color),const SizedBox(width:5),Expanded(child:Text(label,style:TextStyle(fontSize:11,color:color,fontWeight:FontWeight.w600)))]),
          const SizedBox(height:7),
          Text(value,style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:color),maxLines:2,overflow:TextOverflow.ellipsis),
          const SizedBox(height:4),Text(sub,style:TextStyle(fontSize:10,color:color.withOpacity(.82))),
        ]),
      ),
    );
    final nak=instantData['nakshatra']??'—';
    final pada=instantData['nakshatraPada']??'—';
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(
        width:double.infinity,padding:const EdgeInsets.all(16),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF173F35),Color(0xFF28634D),Color(0xFF9A713F)]),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.12),blurRadius:14,offset:const Offset(0,6))]),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[const Icon(Icons.auto_awesome,color:Color(0xFFFFD88A)),const SizedBox(width:8),const Expanded(child:Text('अभी का पंचांग',style:TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.bold))),Text(_time(_liveNow),style:const TextStyle(color:Color(0xFFFFE2A8),fontWeight:FontWeight.bold))]),
          const SizedBox(height:5),
          Text('लाइव गणना • हर 20 सेकंड में अद्यतन',style:TextStyle(color:Colors.white.withOpacity(.75),fontSize:11)),
          const SizedBox(height:10),
          Row(children:[
            info('वर्तमान तिथि','${instantData['tithi']}','${instantData['paksha']} • ${_remaining(tithiEnd)}',Icons.calendar_today,color:Colors.white,tint:const Color(0xFF315C4D)),
            info('हिन्दू मास',months['amanta']??'—','पूर्णिमांत: ${months['purnimanta']??'—'}',Icons.brightness_6,color:Colors.white,tint:const Color(0xFF315C4D)),
          ]),
          Row(children:[
            info('नक्षत्र • चरण','${nak} • ${pada}','${_remaining(nakEnd)}',Icons.star,color:Colors.white,tint:const Color(0xFF315C4D)),
            info('वर्तमान लग्न',_rashi(lagna),' ${_remaining(lagnaEnd)}',Icons.explore,color:Colors.white,tint:const Color(0xFF315C4D)),
          ]),
          Row(children:[
            info('वर्तमान करण',instantData['karana']?.toString() ?? '—',
              _remaining(instantData['karanaEnd'] as DateTime?),Icons.brightness_5,
              color:Colors.white,tint:const Color(0xFF315C4D)),
            info('करण समाप्ति',_time(instantData['karanaEnd'] as DateTime?),
              'अभी के समय से गणना',Icons.schedule,color:Colors.white,tint:const Color(0xFF315C4D)),
          ]),
        ]),
      ),
      const SizedBox(height:8),
      Row(children:[
        if(ch!=null) info('वर्तमान चौघड़िया',ch.name,'${ch.good?'शुभ':'अशुभ'} • ${_time(ch.start)}–${_time(ch.end)} • ${_remaining(ch.end)}',Icons.timelapse,color:ch.good?const Color(0xFF167443):const Color(0xFFB3261E),tint:ch.good?const Color(0xFFE6F5E9):const Color(0xFFFFE9E7)),
        if(hora!=null) info('वर्तमान होरा','${hora.planet} ग्रह','${_time(hora.start)}–${_time(hora.end)} • ${_remaining(hora.end)}',Icons.public,color:const Color(0xFF654321)),
      ]),
      _liveMuhurtaPanel(),
    ]);
  }

  Widget _sectionHeading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(children: [Icon(icon, color: const Color(0xFF79502B)),
      const SizedBox(width: 8), Text(title, style: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF563719)))]),
  );

  Widget _timeList(List<Map<String, String>> rows) => Card(
    color: Colors.white,
    child: Column(children: rows.map((row) {
      final kind = row['kind'];
      final good = kind == 'शुभ';
      final bad = kind == 'अशुभ';
      final color = good ? const Color(0xFF167443) :
          bad ? const Color(0xFFB3261E) : const Color(0xFF79502B);
      final tint = good ? const Color(0xFFE8F6EB) :
          bad ? const Color(0xFFFFECEA) : Colors.transparent;
      return ListTile(
        dense: true, tileColor: tint,
        leading: kind == null ? null : Icon(
          good ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          color: color, size: 18),
        title: Text(row['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: kind == null ? null : Text(kind, style: TextStyle(color: color, fontSize: 11)),
        trailing: Text(row['time'] ?? '', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
    }).toList()),
  );

  Widget _muhurtaDial() {
    if (sunrise == null || sunset == null) return const SizedBox.shrink();
    final total = sunset!.difference(sunrise!).inMilliseconds;
    final progress = (DateTime.now().difference(sunrise!).inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return Card(
      color: const Color(0xFFFFF7E8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(width: 108, height: 108, child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(value: progress, strokeWidth: 10,
              backgroundColor: const Color(0xFFE8D8BE),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF9B7042)))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wb_sunny_outlined, color: Color(0xFF9B7042)),
              Text('${(progress * 100).round()}%', style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF563719))),
              const Text('दिन व्यतीत', style: TextStyle(fontSize: 10)),
            ]),
          ])),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('आज का सूर्यकाल', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('सूर्योदय ${_time(sunrise)}'),
            Text('सूर्यास्त ${_time(sunset)}'),
            const Text('दिन के समय का दृश्य संकेत', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ])),
        ]),
      ),
    );
  }

  void _changeDate(int days) {
    final next = selectedDate.add(Duration(days: days));
    setState(() {
      selectedDate = DateTime(next.year, next.month, next.day);
      _calculate();
    });
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: selectedDate,
      firstDate: DateTime(1900), lastDate: DateTime(2100),
      helpText: 'पंचांग की तारीख चुनें',
    );
    if (picked != null) setState(() { selectedDate = picked; _calculate(); });
  }

  Widget _tile(String title, String value, IconData icon) => Card(
    color: Colors.white,
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF79502B)),
      title: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      subtitle: Text(value, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF563719),
      )),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final en = widget.language == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(en ? 'Panchang & Muhurat' : 'पंचांग एवं मुहूर्त'),
        actions: [
          IconButton(onPressed: _chooseDate, icon: const Icon(Icons.calendar_month)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_off, size: 44, color: Color(0xFF79502B)),
                    const SizedBox(height: 12),
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    ElevatedButton(onPressed: _load, child: const Text('दोबारा प्रयास करें')),
                    const SizedBox(height: 8),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0D5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE9D8B9)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _chooseLocation,
                            child: Row(children: [
                              const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF79502B)),
                              const SizedBox(width: 9),
                              Expanded(child: Text(city, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF684521)))),
                              const Text('स्थान बदलें', style: TextStyle(fontSize: 11, color: Color(0xFF98652D))),
                              const SizedBox(width: 5),
                              const Icon(Icons.edit_location_alt_outlined, size: 17, color: Color(0xFF79502B)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [Color(0xFF6B4528), Color(0xFF9B7042)]),
                        ),
                        child: Column(children: [
                          Row(children: [
                            IconButton(tooltip: 'पिछली तारीख', onPressed: () => _changeDate(-1),
                              padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 23),
                              visualDensity: VisualDensity.compact),
                            Expanded(child: Column(children: [
                              Text(_weekday(selectedDate), style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.1)),
                              Text(_date(selectedDate), style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.1, fontWeight: FontWeight.bold)),
                            ])),
                            IconButton(tooltip: 'अगली तारीख', onPressed: () => _changeDate(1),
                              padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.chevron_right, color: Colors.white, size: 23),
                              visualDensity: VisualDensity.compact),
                          ]),
                          const Divider(color: Color(0x66FFFFFF), height: 5, thickness: 0.6),
                          Row(children: [
                            Expanded(child: _sunInfo('सूर्योदय', _time(sunrise), Icons.wb_sunny_outlined)),
                            Expanded(child: _sunInfo('सूर्यास्त', _time(sunset), Icons.wb_twilight)),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      _liveDashboard(),
                      const SizedBox(height: 10),
                      _mainCategoryTabs(),
                      const SizedBox(height: 12),
                      _muhuratTabs(),
                      const SizedBox(height: 12),
                      ..._selectedTabContent(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
    );
  }

  Widget _mainCategoryTabs() => Row(children: [
    Expanded(child: Card(
      color: const Color(0xFF8B5E32),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_month, color: Colors.white, size: 19),
          SizedBox(width: 7),
          Text('पंचांग', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
    )),
    const SizedBox(width: 10),
    Expanded(child: Card(
      color: const Color(0xFFFFF0D5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MuhuratListScreen())),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.event_available, color: Color(0xFF79502B), size: 19),
            SizedBox(width: 7),
            Text('विशेष मुहूर्त', style: TextStyle(color: Color(0xFF79502B), fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    )),
  ]);

  static const _muhuratTabLabels = ['दिन', 'मुहूर्त', 'चौघड़िया', 'होरा', 'लग्न'];

  Widget _muhuratTabs() => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE9D8B9)),
    ),
    child: Row(
      children: List.generate(_muhuratTabLabels.length, (index) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => selectedMuhuratTab = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
              decoration: BoxDecoration(
                color: selectedMuhuratTab == index ? const Color(0xFF8B5E32) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_muhuratTabLabels[index], textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: selectedMuhuratTab == index ? Colors.white : const Color(0xFF684521))),
            ),
          ),
        ),
      )),
    ),
  );

  List<Widget> _selectedTabContent() {
    if (data == null || sunrise == null || sunset == null) {
      return [const Card(child: Padding(padding: EdgeInsets.all(18),
        child: Text('इस तारीख के लिए पंचांग गणना उपलब्ध नहीं है।')))];
    }
    switch (selectedMuhuratTab) {
      case 0:
        return _dayPanchangDetails();
      case 1:
        return [
          _sectionHeading('दैनिक मुहूर्त एवं काल', Icons.access_time),
          _muhurtaDial(),
          _timeList(_dailyWindows()),
          _tile('राहुकाल', _rahuKaal() ?? 'उपलब्ध नहीं', Icons.schedule),
        ];
      case 2:
        return [
          _sectionHeading('दिन का चौघड़िया', Icons.wb_sunny_outlined),
          _timeList(_choghadiya(false)),
          _sectionHeading('रात्रि का चौघड़िया', Icons.nightlight_round),
          _timeList(_choghadiya(true)),
        ];
      case 3:
        return [
          _sectionHeading('दिन-रात की ग्रह होरा', Icons.timelapse),
          _timeList(_horaRows()),
          const Padding(padding: EdgeInsets.all(8), child: Text(
            'होरा की अवधि स्थानीय सूर्योदय और सूर्यास्त के अनुसार विभाजित की जाती है।',
            style: TextStyle(fontSize: 12, color: Colors.black54))),
        ];
      case 4:
        final lagnaRows = _lagnaRows();
        return [
          _sectionHeading('लग्न समय-सारणी', Icons.auto_awesome),
          Card(color: const Color(0xFFFFF7E8), child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('लग्न निकालने की गणना-विधि', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. चयनित स्थान का अक्षांश, देशांतर और स्थानीय समय लिया जाता है।'),
              Text('2. जूलियन दिवस से ग्रीनविच प्रत्यक्ष नाक्षत्र समय निकालकर देशांतर जोड़ने पर स्थानीय नाक्षत्र समय मिलता है।'),
              Text('3. स्थानीय नाक्षत्र समय, पृथ्वी के अक्षांश और क्रांतिवृत्त की तिर्यकता से सायन लग्नांश निकाला जाता है।'),
              Text('4. सायन लग्नांश में से लाहिड़ी अयनांश घटाकर निरयन लग्न प्राप्त होता है।'),
              SizedBox(height: 8),
              Text('राशि-सीमा (0°, 30°, 60° …) पार करने का समय खोजकर प्रत्येक लग्न का आरंभ और अंत निकाला जाता है। समय स्थानीय सूर्योदय से अगले सूर्योदय तक है।',
                style: TextStyle(fontSize: 12, color: Color(0xFF705333))),
            ]),
          )),
          if (lagnaRows.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
              child: Text('इस स्थान और तारीख के लिए लग्न समय-सारणी उपलब्ध नहीं है।')))
          else
            Card(color: Colors.white, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: List.generate(lagnaRows.length, (i) =>
                _detailRow(lagnaRows[i]['name']!, lagnaRows[i]['time']!, alternate: i.isEven))),
            )),
        ];
      default:
        return [];
    }
  }


  List<Map<String, String>> _lagnaRows() {
    if (sunrise == null || position == null) return [];
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    );
    if (nextSunrise == null || !nextSunrise.isAfter(sunrise!)) return [];
    int signAt(DateTime instant) {
      final longitude = PanchangEngine.ascendantSiderealLongitude(
        instant: instant, latitude: position!.latitude,
        longitude: position!.longitude);
      return ((((longitude % 360) + 360) % 360) / 30).floor();
    }
    final rows = <Map<String, String>>[];
    var intervalStart = sunrise!;
    var previous = signAt(intervalStart);
    var cursor = intervalStart;
    while (cursor.isBefore(nextSunrise)) {
      final next = cursor.add(const Duration(minutes: 1)).isAfter(nextSunrise)
          ? nextSunrise : cursor.add(const Duration(minutes: 1));
      final current = signAt(next);
      if (current != previous) {
        var low = cursor;
        var high = next;
        for (var i = 0; i < 22; i++) {
          final mid = low.add(Duration(microseconds:
            high.difference(low).inMicroseconds ~/ 2));
          if (signAt(mid) == previous) {
            low = mid;
          } else {
            high = mid;
          }
        }
        rows.add({
          'name': '${_rashiNames[previous]} लग्न',
          'time': '${_time(intervalStart)} – ${_time(high)}',
        });
        intervalStart = high;
        previous = current;
      }
      cursor = next;
    }
    rows.add({
      'name': '${_rashiNames[previous]} लग्न',
      'time': '${_time(intervalStart)} – ${_time(nextSunrise)}',
    });
    return rows;
  }

  static const _rashiNames = ['मेष','वृषभ','मिथुन','कर्क','सिंह','कन्या','तुला','वृश्चिक','धनु','मकर','कुंभ','मीन'];
  static const _nakshatraNames = ['अश्विनी','भरणी','कृत्तिका','रोहिणी','मृगशीर्ष','आर्द्रा','पुनर्वसु','पुष्य','आश्लेषा','मघा','पूर्वा फाल्गुनी','उत्तरा फाल्गुनी','हस्त','चित्रा','स्वाती','विशाखा','अनुराधा','ज्येष्ठा','मूल','पूर्वाषाढ़ा','उत्तराषाढ़ा','श्रवण','धनिष्ठा','शतभिषा','पूर्वा भाद्रपद','उत्तरा भाद्रपद','रेवती'];
  int _siderealSign(double longitude) => ((((longitude % 360) + 360) % 360) / 30).floor();
  String _rashi(double longitude) => _rashiNames[_siderealSign(longitude)];
  String _lagnaLabel() {
    if (sunriseAscendant == null) return 'गणना उपलब्ध नहीं';
    final longitude = (sunriseAscendant! % 360 + 360) % 360;
    final totalMinutes = ((longitude % 30) * 60).round();
    final degrees = (totalMinutes ~/ 60) % 30;
    final minutes = totalMinutes % 60;
    return '${_rashi(longitude)} ${degrees}°${minutes.toString().padLeft(2, '0')}′';
  }

  List<Widget> _samvatsaraRows() {
    final date = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final southStart = DateTime(2026, 4, 14);
    final northStart = DateTime(2026, 5, 7);
    final nextSouth = DateTime(2027, 4, 14);
    final nextNorth = DateTime(2027, 5, 7);
    final supported = !date.isBefore(southStart) && date.isBefore(nextSouth);
    if (!supported) {
      return [
        _detailRow('बार्हस्पत्य संवत्सर', 'चयनित वर्ष का संदर्भ मिलान शेष', alternate: true),
        _detailRow('दक्षिण भारतीय पद्धति', 'चयनित वर्ष का संदर्भ मिलान शेष'),
        _detailRow('विक्रम / शक / कलि संवत', 'संदर्भ-पंचांग मिलान शेष', alternate: true),
      ];
    }
    final southName = 'पराभव';
    final northName = date.isBefore(northStart) ? 'पूर्व चक्र (मिलान शेष)' : date.isBefore(nextNorth) ? 'रौद्र' : 'अगला चक्र (मिलान शेष)';
    return [
      _detailRow('बार्हस्पत्य संवत्सर (उत्तर)', northName, alternate: true),
      _detailRow('बार्हस्पत्य संवत्सर (दक्षिण)', southName),
      _detailRow('विक्रम संवत', '2083 — सिद्धार्थी', alternate: true),
      _detailRow('गुजराती संवत', '2083 — कलायुक्त'),
      _detailRow('शक संवत', '1948'),
      _detailRow('कलि संवत', '5127', alternate: true),
      const Padding(padding: EdgeInsets.only(top: 6), child: Text('ये वर्ष-नाम अलग-अलग क्षेत्रीय/युग-गणना पद्धतियों के अनुसार हैं; बार्हस्पत्य संवत्सर को विक्रम संवत के नाम के रूप में न पढ़ें।', style: TextStyle(fontSize: 11, color: Color(0xFF705333)))),
    ];
  }
  double _siderealSun() => ((data!['sunLongitude'] as num).toDouble() - (data!['ayanamsha'] as num).toDouble());
  double _siderealMoon() => ((data!['moonLongitude'] as num).toDouble() - (data!['ayanamsha'] as num).toDouble());
  String _sunNakshatra() {
    final lon = (_siderealSun() % 360 + 360) % 360;
    return _nakshatraNames[(lon / (360 / 27)).floor() % 27];
  }
  // Drik Ritu follows the tropical (sayana) solar season.
  // Keep this distinct from Vedic Ritu, which is based on the sidereal Sun.
  String _ritu() {
    final tropicalSun = (data?['sunLongitude'] as num?)?.toDouble();
    if (tropicalSun == null) return 'गणना उपलब्ध नहीं';
    const drikSeasons = [
      'वसंत','ग्रीष्म','ग्रीष्म','वर्षा','वर्षा','शरद',
      'शरद','हेमंत','हेमंत','शिशिर','शिशिर','वसंत',
    ];
    final sign = (((tropicalSun % 360) + 360) % 360 / 30).floor();
    return drikSeasons[sign];
  }
  String _ayana() => (_siderealSign(_siderealSun()) >= 9 || _siderealSign(_siderealSun()) <= 2) ? 'उत्तरायण' : 'दक्षिणायन';
  String _detailDuration(Duration d) => '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
  Widget _detailCard(String title, IconData icon, List<Widget> children) => Card(
    color: Colors.white, elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(children: [
        Row(children: [Icon(icon, color: const Color(0xFF79502B)), const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF234536)))]),
        const Divider(height: 18), ...children,
      ]),
    ),
  );
  Widget _detailRow(String label, String value, {bool alternate = false, bool compact = false}) => Container(
    color: alternate ? const Color(0xFFFFF6E9) : Colors.transparent,
    padding: EdgeInsets.symmetric(vertical: compact ? 5 : 7, horizontal: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: Text(label, textAlign: TextAlign.right,
        style: TextStyle(fontSize: compact ? 12 : 13, color: const Color(0xFF98652D)))),
      const SizedBox(width: 12),
      Expanded(flex: 6, child: Text(value,
        style: TextStyle(fontSize: compact ? 13 : 14, color: const Color(0xFF286342), fontWeight: FontWeight.w600))),
    ]),
  );
  List<Widget> _vasaRows(Map<String, dynamic> d) {
    final tithiNumber = (d['tithiNumber'] as num?)?.toInt() ?? 1;
    // DateTime: Monday=1 ... Sunday=7; traditional count is Sunday=1.
    final weekdaySundayOne = selectedDate.weekday % 7 + 1;
    final shiva = PanchangEngine.shivaVasa(tithiNumber);
    final agni = PanchangEngine.agniVasa(tithiNumber, weekdaySundayOne);
    return [
      _detailRow('शिव वास', shiva['place']!, alternate: true),
      _detailRow('शिव वास फल', shiva['result']!),
      _detailRow('अग्नि वास', agni['place']!, alternate: true),
      _detailRow('अग्नि वास फल', agni['result']!),
      _detailRow('गणना आधार', 'तिथि ${d['tithiNumber']} • वार क्रमांक $weekdaySundayOne', alternate: true),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'ये पारंपरिक मुहूर्त-संकेत हैं। तिथि बदलने पर शिव वास और अग्नि वास भी बदलेंगे; हवन/रुद्राभिषेक का अंतिम मुहूर्त स्थानीय पंचांग एवं कुल-परंपरा से मिलाएँ।',
          style: TextStyle(fontSize: 11, color: Color(0xFF705333)),
        ),
      ),
    ];
  }

  List<Map<String, String>> _calculateSpecialYogas(
      DateTime dayStart, DateTime nextSunrise, int weekday) {
    // Weekday is Sunday=0 ... Saturday=6. Tithis below are numbered
    // 1..15 within each paksha; nakshatras are zero-based from Ashwini.
    const sarvartha = <List<int>>[
      [0, 7, 11, 12, 18, 20, 25], [3, 4, 7, 16, 21],
      [0, 2, 8, 25], [2, 3, 4, 12, 16], [0, 6, 7, 16, 26],
      [0, 6, 16, 21, 26], [3, 14, 21],
    ];
    const amritSiddhi = [12, 4, 0, 16, 7, 26, 3];
    const siddhaTithis = <int, List<int>>{
      5: [1, 6, 11], 3: [2, 7, 12], 2: [3, 8, 13],
      6: [4, 9, 14], 4: [5, 10, 15],
    };
    // These weekday-tithi pairs are Mrityu Yoga, not Amrit Yoga.
    const mrityuTithis = <int, List<int>>{
      0: [1, 6, 11], 1: [2, 7, 12], 2: [1, 6, 11],
      3: [3, 8, 13], 4: [4, 9, 14], 5: [2, 7, 12],
      6: [5, 10, 15],
    };
    const dagdha = [12, 11, 5, 3, 6, 8, 9];
    const visha = [4, 6, 7, 2, 8, 9, 7];
    const hutashana = [12, 6, 7, 8, 9, 10, 11];
    const kakrach = [12, 11, 10, 9, 8, 7, 6];
    const anandadiNames = [
      'आनन्द','कालदण्ड','धूम्र','धाता','सौम्य','ध्वांक्ष','केतु','श्रीवत्स',
      'वज्र','मुद्गर','छत्र','मित्र','मानस','पद्म','लुम्ब','उत्पात',
      'मृत्यु','काण','सिद्धि','शुभ','अमृत','मुसल','गद','मातंग',
      'राक्षस','चर','सुस्थिर','प्रवर्धमान',
    ];
    // Muhurta Chintamani's 28-fold count inserts Abhijit after
    // Uttarashadha. The starting points are Sunday through Saturday.
    const anandadiStart = [0, 4, 8, 12, 16, 20, 24];
    const anandadiAshubh = {
      'कालदण्ड','धूम्र','ध्वांक्ष','वज्र','मुद्गर','लुम्ब','उत्पात',
      'मृत्यु','काण','मुसल','गद','राक्षस',
    };
    Map<String, bool> stateAt(DateTime instant) {
      final found = <String, bool>{};
      void mark(String name, bool good) => found[name] = good;
      final limb = PanchangEngine.indicesAt(instant);
      final tithiNo = (limb['tithi']! % 15) + 1;
      final nak = limb['nakshatra']!;
      final sunNak = limb['sunNakshatra']!;
      final jwalamukhi =
          (tithiNo == 1 && nak == 18) || (tithiNo == 5 && nak == 1) ||
          (tithiNo == 8 && nak == 2) || (tithiNo == 9 && nak == 3) ||
          (tithiNo == 10 && nak == 8);

      if (sarvartha[weekday].contains(nak)) mark('सर्वार्थ सिद्धि योग', true);
      if (amritSiddhi[weekday] == nak) mark('अमृत सिद्धि योग', true);
      if (weekday == 0 && nak == 7) mark('रवि पुष्य योग', true);
      if (weekday == 4 && nak == 7) mark('गुरु पुष्य योग', true);
      final fromSun = ((nak - sunNak + 27) % 27) + 1;
      if ([4, 6, 9, 10, 13, 20].contains(fromSun)) mark('रवि योग', true);

      // Dwi/Tripushkar are distinguished by the nakshatra's division:
      // Mrigashira-Chitra-Dhanishtha are dual; the six listed stars are tri.
      if ([0, 2, 6].contains(weekday) && [2, 7, 12].contains(tithiNo) &&
          [4, 13, 22].contains(nak)) mark('द्विपुष्कर योग', true);
      if ([0, 2, 6].contains(weekday) && [2, 7, 12].contains(tithiNo) &&
          [2, 6, 11, 15, 20, 24].contains(nak)) mark('त्रिपुष्कर योग', true);

      if (siddhaTithis[weekday]?.contains(tithiNo) == true) {
        mark('सिद्ध योग', true);
      }
      if (mrityuTithis[weekday]?.contains(tithiNo) == true) {
        mark('मृत्यु योग', false);
      }
      if (dagdha[weekday] == tithiNo) mark('दग्ध योग', false);
      if (visha[weekday] == tithiNo) mark('विष योग', false);
      if (hutashana[weekday] == tithiNo) mark('हुताशन योग', false);
      if (kakrach[weekday] == tithiNo) mark('काक्रच / क्रकच योग', false);
      if (jwalamukhi) mark('ज्वालामुखी योग', false);

      final extendedNak = nak <= 20 ? nak : nak + 1;
      final anandadiIndex = (extendedNak - anandadiStart[weekday] + 28) % 28;
      final anandadi = anandadiNames[anandadiIndex];
      if (anandadiAshubh.contains(anandadi)) {
        final display = anandadi == 'ध्वांक्ष' ? 'ध्वांक्ष (ध्वाक्ष)' :
            anandadi == 'लुम्ब' ? 'लुम्ब / लंबक' : anandadi;
        mark(display + ' योग', false);
      }
      return found;
    }

    DateTime refine(DateTime low, DateTime high, String name, bool entering) {
      for (var i = 0; i < 24; i++) {
        final mid = low.add(Duration(
          microseconds: high.difference(low).inMicroseconds ~/ 2));
        if (stateAt(mid).containsKey(name) == entering) {
          high = mid;
        } else {
          low = mid;
        }
      }
      return high;
    }

    final rows = <Map<String, String>>[];
    final active = <String, DateTime>{};
    var previousTime = dayStart;
    var previous = stateAt(dayStart);
    for (final name in previous.keys) {
      active[name] = dayStart;
    }
    // A one-minute scan reduces the chance of missing short overlaps of
    // tithi/nakshatra boundaries; each detected boundary is then refined.
    var cursor = dayStart.add(const Duration(minutes: 1));
    while (cursor.isBefore(nextSunrise)) {
      final current = stateAt(cursor);
      for (final name in <String>{...previous.keys, ...current.keys}) {
        final was = previous.containsKey(name);
        final now = current.containsKey(name);
        if (was == now) continue;
        final boundary = refine(previousTime, cursor, name, now);
        if (was) {
          final startTime = active.remove(name) ?? dayStart;
          rows.add({
            'name': name,
            'kind': previous[name] == true ? 'शुभ' : 'अशुभ',
            'start': _time(startTime),
            'end': _time(boundary),
            '_sort': startTime.toIso8601String(),
          });
        } else {
          active[name] = boundary;
        }
      }
      previous = current;
      previousTime = cursor;
      cursor = cursor.add(const Duration(minutes: 1));
    }
    for (final entry in active.entries) {
      rows.add({
        'name': entry.key,
        'kind': previous[entry.key] == true ? 'शुभ' : 'अशुभ',
        'start': _time(entry.value),
        'end': _time(nextSunrise),
        '_sort': entry.value.toIso8601String(),
      });
    }
    rows.sort((a, b) => a['_sort']!.compareTo(b['_sort']!));
    for (final row in rows) {
      row.remove('_sort');
    }
    return rows;
  }

  // Show only the yogas calculated for the currently selected sunrise-to-sunrise day.
  List<Widget> _specialYogaCards() {
    final goodRows = _specialYogaRows
        .where((row) => row['kind'] == 'शुभ').toList();
    final badRows = _specialYogaRows
        .where((row) => row['kind'] == 'अशुभ').toList();
    final hasGood = goodRows.isNotEmpty;
    final hasBad = badRows.isNotEmpty;

    final String verdict = hasGood && hasBad
        ? 'आज शुभ और अशुभ—दोनों प्रकार के योग बन रहे हैं।'
        : hasGood
            ? 'आज शुभ योग बन रहे हैं।'
            : hasBad
                ? 'आज अशुभ योग बन रहे हैं।'
                : 'आज कोई सूचीबद्ध विशेष शुभ या अशुभ योग नहीं बन रहा।';
    final Color verdictColor = hasBad
        ? const Color(0xFF9D332B)
        : const Color(0xFF176B43);
    final Color verdictTint = hasBad
        ? const Color(0xFFFFEFEC)
        : const Color(0xFFEAF6ED);

    Widget yogaList(String title, IconData icon,
        List<Map<String, String>> rows, bool good) {
      final color = good ? const Color(0xFF176B43) : const Color(0xFFB3261E);
      final tint = good ? const Color(0xFFEAF6ED) : const Color(0xFFFFEFEC);
      return _detailCard(title, icon, [
        if (rows.isEmpty)
          _detailRow('स्थिति', good ? 'आज कोई विशेष शुभ योग नहीं' : 'आज कोई विशेष अशुभ योग नहीं',
              alternate: true)
        else
          ...rows.map((row) => Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: [
              Icon(good ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row['name'] ?? '', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${row['start'] ?? '—'} से ${row['end'] ?? '—'}', style: TextStyle(color: color.withOpacity(0.82), fontSize: 11)),
              ])),
              Text(good ? 'शुभ' : 'अशुभ',
                  style: TextStyle(color: color, fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ]),
          )),
      ]);
    }

    return [
      _detailCard('चयनित दिन के योग • ${_date(selectedDate)}',
          Icons.auto_awesome, [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: verdictTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(verdict, style: TextStyle(
            color: verdictColor, fontWeight: FontWeight.w700, height: 1.4)),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'नीचे केवल इसी चयनित दिन के सूर्योदय से अगले सूर्योदय तक बनने वाले योग दिए गए हैं।',
            style: TextStyle(fontSize: 10, color: Color(0xFF705333)),
          ),
        ),
      ]),
      yogaList('आज के शुभ योग', Icons.check_circle_outline, goodRows, true),
      yogaList('आज के अशुभ योग', Icons.warning_amber_rounded, badRows, false),
    ];
  }

  List<Map<String, String>> _bhadraWindows() {
    if (sunrise == null || position == null) return [];
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude,
      longitude: position!.longitude,
      sunrise: true,
    );
    if (nextSunrise == null || !nextSunrise.isAfter(sunrise!)) return [];

    bool isVishti(DateTime instant) =>
        PanchangEngine.indicesAt(instant)['karana'] == 6;

    DateTime refine(DateTime low, DateTime high, bool entering) {
      for (var i = 0; i < 24; i++) {
        final mid = low.add(Duration(
          microseconds: high.difference(low).inMicroseconds ~/ 2));
        if (isVishti(mid) == entering) {
          high = mid;
        } else {
          low = mid;
        }
      }
      return high;
    }

    final rows = <Map<String, String>>[];
    var cursor = sunrise!;
    var previous = isVishti(cursor);
    DateTime? activeStart = previous ? cursor : null;
    var previousTime = cursor;
    while (cursor.isBefore(nextSunrise)) {
      final next = cursor.add(const Duration(minutes: 1)).isAfter(nextSunrise)
          ? nextSunrise : cursor.add(const Duration(minutes: 1));
      final current = isVishti(next);
      if (current != previous) {
        final boundary = refine(previousTime, next, current);
        if (previous) {
          rows.add({
            'start': _time(activeStart ?? sunrise),
            'end': _time(boundary),
            'startNote': activeStart == sunrise ? 'सूर्योदय पर भद्रा जारी' : '',
          });
          activeStart = null;
        } else {
          activeStart = boundary;
        }
      }
      previous = current;
      previousTime = next;
      cursor = next;
    }
    if (previous) {
      rows.add({
        'start': _time(activeStart ?? sunrise),
        'end': _time(nextSunrise),
        'startNote': activeStart == sunrise ? 'सूर्योदय पर भद्रा जारी' : '',
      });
    }
    return rows;
  }

  Widget _bhadraCard() {
    final windows = _bhadraWindows();
    return _detailCard('भद्रा (विष्टि करण)', Icons.warning_amber_rounded, [
      _detailRow('स्थिति', windows.isEmpty ? 'आज सूर्योदय से अगले सूर्योदय तक भद्रा नहीं' :
          'इस दिन भद्रा काल है', alternate: true),
      if (windows.isEmpty)
        _detailRow('भद्रा काल', 'नहीं है')
      else
        ...windows.map((window) => _detailRow(
          'भद्रा काल',
          '${window['start']} – ${window['end']}' +
              ((window['startNote'] ?? '').isNotEmpty
                  ? '  (${window['startNote']})' : ''),
          alternate: true,
        )),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'भद्रा का निर्धारण विष्टि करण के समय से है। समय चयनित दिन के सूर्योदय से अगले सूर्योदय तक दिखाया गया है; सूर्योदय पर पहले से चल रही भद्रा का आरंभ इससे पहले हो सकता है।',
          style: TextStyle(fontSize: 10, color: Color(0xFF705333)),
        ),
      ),
    ]);
  }

  Widget _panchakCard() {
    final window = _panchakWindow;
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude, sunrise: true,
    );
    final beginsToday = window != null && window.start.isAfter(sunrise!) &&
        nextSunrise != null && window.start.isBefore(nextSunrise);
    final active = window != null && window.active;
    final status = active ? 'पंचक चल रहा है' :
        beginsToday ? 'आज पंचक आरंभ होगा' : 'आज पंचक नहीं है';
    final details = window == null ? 'समय गणना उपलब्ध नहीं' :
        _date(window.start) + ' ' + _time(window.start) + ' – ' +
        _date(window.end) + ' ' + _time(window.end);
    return _detailCard('पंचक', Icons.nights_stay_outlined, [
      _detailRow('स्थिति', status, alternate: true),
      _detailRow('आरंभ – समाप्ति', details),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('पंचक चंद्रमा के निरयन कुंभ राशि के 0° से मीन राशि के अंत (रेवती नक्षत्र समाप्ति) तक रहने पर माना गया है।',
          style: TextStyle(fontSize: 10, color: Color(0xFF705333))),
      ),
    ]);
  }

  List<Widget> _dayPanchangDetails() {
    final d = data!;
    final nextSunrise = PanchangEngine.solarEvent(
      localDate: selectedDate.add(const Duration(days: 1)),
      latitude: position!.latitude, longitude: position!.longitude,
      sunrise: true,
    );
    final dayLength = sunrise != null && sunset != null ? sunset!.difference(sunrise!) : Duration.zero;
    final nightLength = sunset != null && nextSunrise != null ? nextSunrise.difference(sunset!) : Duration.zero;
    final lunarMonths = PanchangEngine.lunarMonthLabels(sunrise ?? selectedDate);
    final tithiEnd = d['tithiEnd'] as DateTime?;
    final nakshatraEnd = d['nakshatraEnd'] as DateTime?;
    final yogaEnd = d['yogaEnd'] as DateTime?;
    final karanaEnd = d['karanaEnd'] as DateTime?;
    return [
      _detailCard('पंचांग', Icons.calendar_month, [
        _detailRow('तिथि', '${d['tithi'] ?? '—'}  •  ${_time(tithiEnd)}', alternate: true, compact: true),
        _detailRow('पक्ष', '${d['paksha'] ?? '—'}', compact: true),
        _detailRow('नक्षत्र', '${d['nakshatra'] ?? '—'} • चरण ${d['nakshatraPada'] ?? '—'} • ${_time(nakshatraEnd)}', alternate: true, compact: true),
        _detailRow('योग', '${d['yoga'] ?? '—'}  •  ${_time(yogaEnd)}', compact: true),
        _detailRow('करण', '${d['karana'] ?? '—'}  •  ${_time(karanaEnd)}', alternate: true, compact: true),
        _detailRow('वार', _weekday(selectedDate), compact: true),
      ]),
      _panchakCard(),
      _detailCard('मास, राशि, ऋतु एवं अयन', Icons.public, [
        _detailRow('माह (अमांत)', lunarMonths['amanta'] ?? '—', alternate: true),
        _detailRow('माह (पूर्णिमांत)', lunarMonths['purnimanta'] ?? '—'),
        _detailRow('चंद्र राशि', _rashi(_siderealMoon()), alternate: true),
        _detailRow('सूर्य राशि', _rashi(_siderealSun())),
        _detailRow('ऋतु', _ritu(), alternate: true),
        _detailRow('अयन', _ayana()),
        _detailRow('सौर प्रविष्टि', '${_rashi(_siderealSun())} राशि', alternate: true),
      ]),
      _detailCard('संवत्सर एवं संवत', Icons.history, [
        ..._samvatsaraRows(),
        _detailRow('लाहिड़ी अयनांश', '${(d['ayanamsha'] as num).toStringAsFixed(4)}°', alternate: true),
      ]),
      _detailCard('सूर्योदय एवं दिनमान', Icons.wb_sunny, [
        _detailRow('स्थान', city, alternate: true),
        _detailRow('सूर्योदय', _time(sunrise)),
        _detailRow('सूर्यास्त', _time(sunset), alternate: true),
        _detailRow('दिन की अवधि', _detailDuration(dayLength)),
        _detailRow('रात की अवधि', _detailDuration(nightLength), alternate: true),
        _detailRow('चंद्रोदय', _time(moonrise)),
        _detailRow('चंद्रास्त', _time(moonset), alternate: true),
      ]),
      _detailCard('सूर्योदय', Icons.wb_twilight, [
        _detailRow('लग्न', _lagnaLabel(), alternate: true),
        _detailRow('सूर्य नक्षत्र', _sunNakshatra()),
        _detailRow('चंद्र नक्षत्र', '${d['nakshatra'] ?? '—'}', alternate: true),
      ]),
      _detailCard('पद, चरण', Icons.auto_awesome, [
        _detailRow('चंद्र नक्षत्र चरण', '${d['nakshatra'] ?? '—'} — चरण ${d['nakshatraPada'] ?? '—'}', alternate: true),
        _detailRow('चरण गणना', 'प्रत्येक नक्षत्र के 3°20′ खंड के आधार पर'),
      ]),
      _detailCard('शिव वास एवं अग्नि वास', Icons.local_fire_department, [..._vasaRows(d)]),
      Card(color: const Color(0xFFFFF4E5), child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('गणना स्रोत: Meeus आधारित खगोलीय गणना (Astronomia) तथा IMD राष्ट्रीय पंचांग से संदर्भ सत्यापन। अमांत/पूर्णिमांत मास, संवत्सर और चरण-सीमाओं को प्रकाशित करने से पहले संदर्भ पंचांग से मिलान आवश्यक है。',
          style: TextStyle(fontSize: 12, color: Color(0xFF705333)),
        ),
      )),
      _bhadraCard(),
    ];
  }

  Widget _sunInfo(String label, String value, IconData icon) => Row(children: [
    Icon(icon, color: const Color(0xFFFFD88A), size: 16),
    const SizedBox(width: 4),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.1)),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.1, fontWeight: FontWeight.bold)),
    ]),
  ]);
}


class MuhuratListScreen extends StatefulWidget {
  const MuhuratListScreen({super.key});
  @override
  State<MuhuratListScreen> createState() => _MuhuratListScreenState();
}

class _MuhuratListScreenState extends State<MuhuratListScreen> {
  late Future<List<Map<String, dynamic>>> future;
  String selectedCategory = 'सभी';
  static const categories = ['सभी','वास्तु','विवाह','वाहन क्रय-विक्रय','हल / हल-पूजन','मुंडन','गृह प्रवेश','नामकरण','अन्य'];

  @override
  void initState() { super.initState(); future = loadMuhurats(); }

  Future<List<Map<String, dynamic>>> loadMuhurats() async {
    final rows = await Supabase.instance.client.from('muhurats')
      .select('id, category, title_hi, title_en, muhurat_date, start_time, end_time, location, description, special_notes')
      .eq('is_active', true)
      .order('muhurat_date', ascending: true)
      .order('start_time', ascending: true)
      .order('sort_order', ascending: true);
    final result = List<Map<String, dynamic>>.from(rows);
    // Sort again by parsed calendar date so ordering stays chronological
    // even if a backend date value is returned in a different string format.
    result.sort((a, b) {
      final da = DateTime.tryParse((a['muhurat_date'] ?? '').toString());
      final db = DateTime.tryParse((b['muhurat_date'] ?? '').toString());
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final dateCompare = DateTime(da.year, da.month, da.day)
          .compareTo(DateTime(db.year, db.month, db.day));
      if (dateCompare != 0) return dateCompare;
      final ta = (a['start_time'] ?? '').toString();
      final tb = (b['start_time'] ?? '').toString();
      return ta.compareTo(tb);
    });
    return result;
  }

  String dateKey(dynamic value) {
    final d = DateTime.tryParse((value ?? '').toString());
    if (d == null) return 'date-unavailable';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String dateLabel(dynamic value) {
    if (value == null) return 'दिनांक उपलब्ध नहीं';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return value.toString();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  Widget _dateHeading(String label, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Row(children: [
      const Icon(Icons.calendar_month, color: Color(0xFF79502B), size: 19),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF234536)))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFFFF0D5),
          borderRadius: BorderRadius.circular(20)),
        child: Text('$count मुहूर्त', style: const TextStyle(
          fontSize: 11, color: Color(0xFF79502B), fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _muhuratCard(Map<String, dynamic> item) {
    final time = [item['start_time'], item['end_time']]
        .where((x) => x != null && x.toString().trim().isNotEmpty)
        .join(' – ');
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF0D5),
          child: Icon(Icons.event, color: Color(0xFF79502B))),
        title: Text((item['title_hi'] ?? '').toString(),
          style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          (item['category'] ?? '').toString(),
          time,
        ].where((x) => x.isNotEmpty).join(' • ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if ((item['location'] ?? '').toString().isNotEmpty)
            _detailLine(Icons.location_on, item['location'].toString()),
          if ((item['description'] ?? '').toString().isNotEmpty)
            _detailLine(Icons.info_outline, item['description'].toString()),
          if ((item['special_notes'] ?? '').toString().isNotEmpty)
            _detailLine(Icons.notes, item['special_notes'].toString()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('विशेष मुहूर्त')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Text('मुहूर्त लोड नहीं हो सके।'),
            ElevatedButton(onPressed: () => setState(() => future = loadMuhurats()),
              child: const Text('दोबारा प्रयास करें')),
          ]));
        final all = snapshot.data ?? [];
        final items = selectedCategory == 'सभी'
            ? all
            : all.where((x) => (x['category'] ?? '').toString() == selectedCategory).toList();

        // Build one section per date, retaining chronological date order.
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final item in items) {
          groups.putIfAbsent(dateKey(item['muhurat_date']), () => []).add(item);
        }
        final content = <Widget>[];
        for (final entry in groups.entries) {
          final date = entry.value.first['muhurat_date'];
          content.add(_dateHeading(dateLabel(date), entry.value.length));
          content.addAll(entry.value.map(_muhuratCard));
        }

        return Column(children: [
          SizedBox(height: 58, child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: categories.map((category) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category), selected: selectedCategory == category,
                onSelected: (_) => setState(() => selectedCategory = category),
              ),
            )).toList(),
          )),
          Expanded(child: items.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24),
                child: Text('इस श्रेणी के मुहूर्त अभी एडमिन द्वारा जोड़े नहीं गए हैं।',
                  textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: () async {
                  setState(() => future = loadMuhurats());
                  await future;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  children: content,
                ),
              ),
          ),
        ]);
      },
    ),
  );

  Widget _detailLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: const Color(0xFF79502B)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
    ]),
  );
}