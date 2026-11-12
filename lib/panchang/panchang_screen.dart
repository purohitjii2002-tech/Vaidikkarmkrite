import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String _regionalRuleSummary = 'स्थान के अनुसार क्षेत्रीय नियम की जाँच';
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
      if (!mounted) return;
      final now = DateTime.now();
      final oldLiveDay = DateTime(_liveNow.year, _liveNow.month, _liveNow.day);
      final newLiveDay = DateTime(now.year, now.month, now.day);
      final wasFollowingToday = selectedDate.year == oldLiveDay.year &&
          selectedDate.month == oldLiveDay.month &&
          selectedDate.day == oldLiveDay.day;
      setState(() {
        _liveNow = now;
        // Keep the live Panchang on the new civil date after local midnight.
        if (wasFollowingToday && oldLiveDay != newLiveDay) {
          selectedDate = newLiveDay;
          _calculate();
        }
      });
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
      // Reuse the user's last selected location when GPS is unavailable/offline.
      try {
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble('panchang_last_latitude');
        final lon = prefs.getDouble('panchang_last_longitude');
        final savedCity = prefs.getString('panchang_last_city');
        if (lat != null && lon != null) {
          position = _positionAt(lat, lon);
          city = savedCity?.isNotEmpty == true ? savedCity! : 'पिछला चुना हुआ स्थान';
          _manualLocationSelected = true;
        }
      } catch (_) {}
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('panchang_last_latitude', match.latitude);
    await prefs.setDouble('panchang_last_longitude', match.longitude);
    await prefs.setString('panchang_last_city', selected.label);
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
        ? _calculateSpecialYogas(
            sunrise!, nextSunrise, date.weekday % 7,
            position!.latitude, position!.longitude)
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
      // Muhurta Chintamani, Vivaha-prakarana 6.54: Abhijit is prohibited on Wednesday.
      if (weekday != DateTime.wednesday % 7)
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
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('आज की दिनांक एवं वार',style:TextStyle(color:Color(0xFFFFE2A8),fontSize:10)),
              const SizedBox(height:3),
              Text('${_weekday(_liveNow)} • ${_date(_liveNow)}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:13)),
            ])),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
              const Text('सूर्योदय  /  सूर्यास्त',style:TextStyle(color:Color(0xFFFFE2A8),fontSize:10)),
              const SizedBox(height:3),
              Text('${_time(sunrise)}  /  ${_time(sunset)}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:12)),
            ])),
          ]),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFEFA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE9DCC8)),
                          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _chooseLocation,
                            child: Row(children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(color: const Color(0xFFFFF1D9), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFF79502B)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('आपका पंचांग स्थान', style: TextStyle(fontSize: 10, color: Color(0xFF9A7A55), fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(city, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF563719))),
                              ])),
                              const Text('बदलें', style: TextStyle(fontSize: 12, color: Color(0xFF98652D), fontWeight: FontWeight.w700)),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF79502B)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [Color(0xFF49301F), Color(0xFF79502E), Color(0xFF9A7044)]),
                          boxShadow: const [BoxShadow(color: Color(0x1F49301F), blurRadius: 16, offset: Offset(0, 7))],
                          border: Border.all(color: const Color(0xFFD9B879), width: 0.8),
                        ),
                        child: Column(children: [
                          Row(children: [
                            IconButton(tooltip: 'पिछली तारीख', onPressed: () => _changeDate(-1),
                              constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                              style: IconButton.styleFrom(backgroundColor: const Color(0x22FFFFFF)),
                              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28)),
                            Expanded(child: Column(children: [
                              Text(_weekday(selectedDate), style: const TextStyle(color: Color(0xFFEAD9BD), fontSize: 12, letterSpacing: 0.4)),
                              const SizedBox(height: 3),
                              Text(_date(selectedDate), style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.1, fontWeight: FontWeight.w800)),
                            ])),
                            IconButton(tooltip: 'अगली तारीख', onPressed: () => _changeDate(1),
                              constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                              style: IconButton.styleFrom(backgroundColor: const Color(0x22FFFFFF)),
                              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28)),
                          ]),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Divider(color: Color(0x55FFFFFF), height: 22, thickness: 0.7)),
                          Row(children: [
                            Expanded(child: _sunInfo('सूर्योदय', _time(sunrise), Icons.wb_sunny_outlined)),
                            Container(width: 1, height: 34, color: const Color(0x55FFFFFF)),
                            Expanded(child: _sunInfo('सूर्यास्त', _time(sunset), Icons.wb_twilight)),
                          ]),
                        ]),
                      ),
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

  Widget _mainCategoryTabs() => LayoutBuilder(builder: (context, constraints) {
    final width = (constraints.maxWidth - 10) / 2;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      SizedBox(width: width, child: _departmentTile(
        'दैनिक पंचांग', 'तिथि, नक्षत्र, योग और करण',
        Icons.calendar_month_rounded, const Color(0xFF174C3B),
        () => setState(() => selectedMuhuratTab = 0),
        selected: selectedMuhuratTab == 0,
      )),
      SizedBox(width: width, child: _departmentTile(
        'मासिक कैलेंडर', 'मास, पक्ष और तारीख़ चुनें',
        Icons.calendar_view_month_rounded, const Color(0xFF9A641E),
        _openMonthlyCalendar,
      )),
      SizedBox(width: width, child: _departmentTile(
        'व्रत एवं त्योहार', 'मासिक व्रत और पर्व सूची',
        Icons.temple_hindu_rounded, const Color(0xFF8A4F63),
        _openFestivalVrat,
      )),
      SizedBox(width: width, child: _departmentTile(
        'विशेष मुहूर्त', 'विवाह, गृह प्रवेश आदि',
        Icons.event_available_rounded, const Color(0xFF315C75),
        () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MuhuratListScreen())),
      )),
    ]);
  });

  Future<void> _openFestivalVrat() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => FestivalVratScreen(
        initialDate: selectedDate,
        latitude: position?.latitude ?? _ujjainLatitude,
        longitude: position?.longitude ?? _ujjainLongitude,
      )),
    );
  }

  Widget _departmentTile(String title, String subtitle, IconData icon,
      Color color, VoidCallback onTap, {bool selected = false}) => Material(
      color: selected ? color : Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color.withOpacity(selected ? 0 : .22)),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 7, offset: Offset(0, 3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: selected ? Colors.white : color, size: 21),
            const SizedBox(height: 7),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF263C34))),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, height: 1.2,
                color: selected ? Colors.white70 : Colors.black54)),
          ]),
        ),
      ),
    );

  Future<void> _openMonthlyCalendar() async {
    final chosen = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (_) =>
        MonthlyPanchangScreen(
          initialDate: selectedDate,
          latitude: position?.latitude ?? _ujjainLatitude,
          longitude: position?.longitude ?? _ujjainLongitude,
        )),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      selectedDate = DateTime(chosen.year, chosen.month, chosen.day);
      selectedMuhuratTab = 0;
      _calculate();
    });
  }

  static const _muhuratTabLabels = ['दिन', 'मुहूर्त', 'चौघड़िया', 'होरा', 'लग्न'];

  Widget _muhuratTabs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: List.generate(_muhuratTabLabels.length, (index) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => setState(() => selectedMuhuratTab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minWidth: 82),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: selectedMuhuratTab == index
                  ? const Color(0xFF285744) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selectedMuhuratTab == index
                    ? const Color(0xFF285744) : const Color(0xFFE4D7C5)),
            ),
            child: Text(_muhuratTabLabels[index], textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: selectedMuhuratTab == index
                    ? Colors.white : const Color(0xFF684521))),
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
          if (lagnaRows.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
              child: Text('इस स्थान और तारीख के लिए लग्न समय-सारणी उपलब्ध नहीं है।')))
          else
            Card(color: Colors.white, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: List.generate(lagnaRows.length, (i) =>
                _detailRow(lagnaRows[i]['name']!, lagnaRows[i]['time']!, alternate: i.isEven))),
            )),
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
    final latitude = position!.latitude;
    final longitude = position!.longitude;
    final southName = PanchangEngine.southSamvatsaraAt(date);
    final vikramYear = PanchangEngine.vikramSamvatChaitradi(
      localDate: date,
      latitude: latitude,
      longitude: longitude,
    );
    final sakaYear = vikramYear == null ? null : vikramYear - 135;
    final solarSakaYear = PanchangEngine.traditionalSakaSolarYearAt(date);
    final kaliYear = solarSakaYear == null ? null : solarSakaYear + 3179;

    // IMD's 2026–27 Rashtriya Panchanga explicitly verifies these North
    // Barhaspatya boundaries. Do not extrapolate this mean-Jupiter series
    // beyond the published interval without a verified ingress table.
    final northSupported = !date.isBefore(DateTime(2026, 4, 14)) &&
        date.isBefore(DateTime(2027, 4, 14));
    final northName = northSupported
        ? date.isBefore(DateTime(2026, 5, 7))
            ? 'सिद्धार्थी (53)' : 'रौद्र (54)'
        : 'संदर्भ मिलान शेष';
    final gujaratiSupported = !date.isBefore(DateTime(2026, 4, 14)) &&
        date.isBefore(DateTime(2027, 4, 14));
    final gujaratiYear = gujaratiSupported
        ? date.isBefore(DateTime(2026, 11, 10)) ? '2082' : '2083'
        : 'संदर्भ मिलान शेष';

    return [
      _detailRow('बार्हस्पत्य संवत्सर (उत्तर)', northName, alternate: true),
      _detailRow('बार्हस्पत्य संवत्सर (दक्षिण/मेषादि)',
          southName ?? 'गणना उपलब्ध नहीं'),
      _detailRow('विक्रम संवत (चैत्रादि)',
          vikramYear?.toString() ?? 'गणना उपलब्ध नहीं', alternate: true),
      _detailRow('विक्रम संवत (कार्तिकादि / गुजरात)', gujaratiYear),
      _detailRow('शक संवत (चैत्रादि)',
          sakaYear?.toString() ?? 'गणना उपलब्ध नहीं', alternate: true),
      _detailRow('शक संवत (मेषादि)', 
          solarSakaYear?.toString() ?? 'गणना उपलब्ध नहीं'),
      _detailRow('कलि संवत (मेषादि)',
          kaliYear?.toString() ?? 'गणना उपलब्ध नहीं', alternate: true),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'दक्षिण/मेषादि संवत्सर सूर्य के मेष प्रवेश से और चैत्रादि विक्रम-शक वर्ष चैत्र शुक्ल प्रतिपदा के स्थानीय सूर्योदय से निकाले जाते हैं। उत्तर भारतीय बार्हस्पत्य नाम केवल प्रकाशित 2026–27 IMD संदर्भ-सीमा में दिखाया गया है; अन्य तिथियों के लिए अप्रमाणित नाम नहीं गढ़े जाते।',
          style: TextStyle(fontSize: 11, color: Color(0xFF705333)),
        ),
      ),
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
      DateTime dayStart, DateTime nextSunrise, int weekday,
      double latitude, double longitude) {
    // Weekday is Sunday=0 ... Saturday=6. Tithis below are numbered
    // 1..15 within each paksha; nakshatras are zero-based from Ashwini.
    // Muhurta Cintamani 1.28–29. Friday follows the Sanskrit
    // reading भाग्य (Purva Phalguni), zero-based nakshatra index 10,
    // not Anuradha as in some modern secondary tables.
    const sarvartha = <List<int>>[
      [0, 7, 11, 12, 18, 20, 25], [3, 4, 7, 16, 21],
      [0, 2, 8, 25], [2, 3, 4, 12, 16], [0, 6, 7, 16, 26],
      [0, 6, 10, 21, 26], [3, 14, 21],
    ];
    const amritSiddhi = [12, 4, 0, 16, 7, 26, 3];
    const siddhaTithis = <int, List<int>>{
      5: [1, 6, 11], 3: [2, 7, 12], 2: [3, 8, 13],
      6: [4, 9, 14], 4: [5, 10, 15],
    };
    // Muhurta Cintamani 1.30: Mrityu is the second star in the
    // four-star Utpata–Mrityu–Kana–Siddhi sequence from each weekday's
    // stated starting nakshatra. Sunday–Saturday: Anuradha, Uttara
    // Ashadha, Shatabhisha, Ashwini, Mrigashira, Ashlesha, Hasta.
    // Indices are zero-based from Ashwini.
    const mrityuNakshatras = <int, List<int>>{
      0: [16], 1: [20], 2: [23], 3: [0],
      4: [4], 5: [8], 6: [12],
    };
    // Muhurta Cintamani 1.5: weekday-wise Dagdha nakshatras,
    // Sunday–Saturday: Bharani, Chitra, Uttara Ashadha, Dhanishtha,
    // Uttara Phalguni, Jyeshtha, Revati (zero-based indices).
    const dagdhaNakshatras = [1, 13, 20, 22, 11, 17, 26];
    // Muhurta Cintamani 1.8: paksha-local Dagdha, Visha and Hutashana
    // tithis for Sunday–Saturday.
    const dagdha = [12, 11, 5, 3, 6, 8, 9];
    const visha = [4, 6, 7, 2, 8, 9, 7];
    const hutashana = [12, 6, 7, 8, 9, 10, 11];

    // Muhurta Cintamani 1.10–11: month-void tithis.
    // Arrays are Chaitra..Phalguna; tithis are paksha-local (1..15).
    const shunyaShuklaTithis = <List<int>>[
      [8, 9], [12], [13], [7], [2, 3], [1, 2],
      [10, 11], [14], [7, 8], [4, 5], [6], [3],
    ];
    const shunyaKrishnaTithis = <List<int>>[
      [8, 9], [12], [4, 14], [6], [2, 3], [1, 2],
      [10, 11], [5], [7, 8], [4, 5], [5], [4],
    ];
    // Muhurta Cintamani 1.14–15: month-void nakshatras, zero-based.
    const shunyaNakshatras = <List<int>>[
      [3, 0], [13, 14], [20, 7], [10, 22],
      [20, 21], [23, 26], [24], [2, 9],
      [13, 15], [5, 0, 12], [21, 18], [1, 17],
    ];
    // Muhurta Cintamani 1.16: month-void signs, Chaitra..Phalguna.
    const shunyaRashis = [10, 11, 1, 2, 0, 5, 7, 6, 8, 3, 9, 4];
    // Muhurta Cintamani 1.17: tithi-void lagna pairs for odd tithis.
    const shunyaLagnaByOddTithi = <int, List<int>>{
      1: [10, 9], 3: [4, 9], 5: [2, 5], 7: [8, 3],
      9: [3, 4], 11: [8, 11], 13: [1, 11],
    };

    int? monthIndex(String? label) {
      if (label == null || label.startsWith('अधिक ')) return null;
      final clean = label.trim();
      const names = [
        'चैत्र', 'वैशाख', 'ज्येष्ठ', 'आषाढ़', 'श्रावण', 'भाद्रपद',
        'आश्विन', 'कार्तिक', 'मार्गशीर्ष', 'पौष', 'माघ', 'फाल्गुन',
      ];
      final index = names.indexOf(clean);
      return index < 0 ? null : index;
    }

    // Historical regions are not modern state boundaries. Malava and
    // Gauda are identified only from recognizable historical-core districts.
    // Madhyadesha uses a broad Manu-boundary coordinate envelope and is
    // explicitly labelled approximate to avoid claiming exact borders.
    final place = city.toLowerCase();
    final isMalavaByName = [
      'malwa', 'मालवा', 'indore', 'इंदौर', 'उज्जैन', 'ujjain',
      'dewas', 'देवास', 'dhar', 'धार', 'ratlam', 'रतलाम',
      'shajapur', 'शाजापुर', 'mandsaur', 'मंदसौर', 'neemuch', 'नीमच',
      'agar malwa', 'आगर मालवा', 'rajgarh', 'राजगढ़',
    ].any(place.contains);
    final isGaudaByName = [
      'murshidabad', 'मुर्शिदाबाद', 'birbhum', 'बीरभूम',
      'purba bardhaman', 'paschim bardhaman', 'bardhaman', 'burdwan',
      'malda', 'মালদা',
    ].any(place.contains);
    final region = isGaudaByName
        ? 'गौड़ (ऐतिहासिक मूल क्षेत्र)'
        : isMalavaByName
            ? 'मालव (जिला-आधारित पहचान)'
            : (latitude >= 24.5 && latitude <= 32.2 &&
                longitude >= 74.0 && longitude <= 82.0)
                ? 'मध्यदेश (अनुमानित भौगोलिक सीमा)'
                : 'अन्य / अनिर्धारित';
    _regionalRuleSummary = 'क्षेत्रीय नियम: $region';
    // Sunday=1 ... Saturday=7. Krakach (Kakrach) is formed
    // when weekday number + paksha-local tithi number equals 13.
    const anandadiNames = [
      'आनन्द','कालदण्ड','धूम्र','धाता','सौम्य','ध्वांक्ष','केतु','श्रीवत्स',
      'वज्र','मुद्गर','छत्र','मित्र','मानस','पद्म','लुम्ब','उत्पात',
      'मृत्यु','काण','सिद्धि','शुभ','अमृत','मुसल','गद','मातंग',
      'राक्षस','चर','सुस्थिर','प्रवर्धमान',
    ];
    // Muhurta Chintamani's 28-fold count inserts Abhijit after
    // Uttarashadha. The starting points are Sunday through Saturday.
    const anandadiStart = [0, 4, 8, 12, 16, 20, 24];
    Map<String, bool?> stateAt(DateTime instant) {
      final found = <String, bool?>{};
      void mark(String name, bool? good) => found[name] = good;
      final limb = PanchangEngine.indicesAt(instant);
      final tithiNo = (limb['tithi']! % 15) + 1;
      final nak = limb['nakshatra']!;
      final sunNak = limb['sunNakshatra']!;
      final pakshaTithi = (limb['tithi']! % 15) + 1;
      final isShukla = limb['tithi']! < 15;
      // Re-evaluate month names at each instant. The engine caches the
      // surrounding lunation, while the Purnimanta label changes at Purnima.
      final monthLabels = PanchangEngine.lunarMonthLabels(
        instant, isKrishna: !isShukla,
      );
      final amantaMonth = monthIndex(monthLabels['amanta']);
      final purnimantaMonth = monthIndex(monthLabels['purnimanta']);
      final lunarMonthIndexes = <int>{
        if (amantaMonth != null) amantaMonth,
        if (purnimantaMonth != null) purnimantaMonth,
      };
      for (final month in lunarMonthIndexes) {
        final shunyaTithis = isShukla
            ? shunyaShuklaTithis[month] : shunyaKrishnaTithis[month];
        if (region.startsWith('मध्यदेश') &&
            shunyaTithis.contains(pakshaTithi)) {
          final convention = amantaMonth == purnimantaMonth
              ? 'दोनों मास-गणना'
              : month == amantaMonth ? 'अमांत' : 'पूर्णिमांत';
          mark('मास-शून्य तिथि ($convention)', false);
        }
        if (shunyaNakshatras[month].contains(nak)) {
          final convention = month == amantaMonth ? 'अमांत' : 'पूर्णिमांत';
          mark('मास-शून्य नक्षत्र ($convention)', false);
        }
      }
      // Jwalamukhi: a traditional five-pair tithi–nakshatra rule
      // (Pratipada–Mula, Panchami–Bharani, Ashtami–Krittika,
      // Navami–Rohini, Dashami–Ashlesha). Jyotishsara Prakrit 147–148
      // records this set; other paddhatis give variant sets, so keep
      // its provenance distinct from Muhurta Cintamani's numbered rules.
      final jwalamukhi =
          (tithiNo == 1 && nak == 18) || (tithiNo == 5 && nak == 1) ||
          (tithiNo == 8 && nak == 2) || (tithiNo == 9 && nak == 3) ||
          (tithiNo == 10 && nak == 8);

      if (sarvartha[weekday].contains(nak)) mark('सर्वार्थ सिद्धि योग', true);
      // Muhurta Cintamani 1.20–21: the Amritsiddhi weekday-star
      // pair is not to be used on its corresponding tithi (Sunday–Saturday:
      // Panchami, Shashthi, Saptami, Ashtami, Navami, Dashami, Ekadashi).
      const amritSiddhiAvoidTithi = [5, 6, 7, 8, 9, 10, 11];
      if (amritSiddhi[weekday] == nak &&
          amritSiddhiAvoidTithi[weekday] == tithiNo) {
        mark('निषिद्ध वार-नक्षत्र-तिथि संयोग', false);
      } else if (amritSiddhi[weekday] == nak) {
        mark('अमृत सिद्धि योग', true);
      }
      if (weekday == 0 && nak == 7) mark('रवि पुष्य योग', true);
      if (weekday == 4 && nak == 7) mark('गुरु पुष्य योग', true);
      final fromSun = ((nak - sunNak + 27) % 27) + 1;
      if ([4, 6, 9, 10, 13, 20].contains(fromSun)) mark('रवि योग', true);

      // Narada Purana, Purvabhaga 55 (verses 198–199 in this edition):
      // Sunday/Tuesday/Saturday + Bhadra tithi (2, 7, 12) + the
      // three Dwi or six Tri nakshatras listed below.
      if ([0, 2, 6].contains(weekday) && [2, 7, 12].contains(tithiNo) &&
          [4, 13, 22].contains(nak)) mark('द्विपुष्कर योग', true);
      if ([0, 2, 6].contains(weekday) && [2, 7, 12].contains(tithiNo) &&
          [2, 6, 11, 15, 20, 24].contains(nak)) mark('त्रिपुष्कर योग', true);

      if (siddhaTithis[weekday]?.contains(tithiNo) == true) {
        mark('सिद्ध योग', true);
      }
      if (mrityuNakshatras[weekday]?.contains(nak) == true) {
        mark('मृत्यु योग', false);
      }
      if (dagdha[weekday] == tithiNo) mark('दग्ध तिथि योग', false);
      if (dagdhaNakshatras[weekday] == nak) {
        mark('दग्ध नक्षत्र', false);
      }
      if (visha[weekday] == tithiNo) mark('विष योग', false);
      if (hutashana[weekday] == tithiNo) mark('हुताशन योग', false);
      // Muhurta Cintamani 1.6: Krakacha/Kakracha is the
      // weekday(1..7) + paksha-local tithi = 13 combination.
      if ((weekday + 1 + tithiNo) == 13) {
        mark('काक्रच / क्रकच योग', false);
      }
      // The same verse separately rejects Wednesday-Pratipada and
      // Sunday-Saptami. These are kept distinct as Samvartaka,
      // not incorrectly merged into the sum-13 Krakacha yoga.
      if ((weekday == 3 && tithiNo == 1) ||
          (weekday == 0 && tithiNo == 7)) {
        mark('संवर्तक योग', false);
      }
      if (jwalamukhi) mark('ज्वालामुखी योग', false);

      final ascendant = PanchangEngine.ascendantSiderealLongitude(
        instant: instant, latitude: latitude, longitude: longitude);
      final lagnaSign = (ascendant / 30).floor();
      if (region.startsWith('मध्यदेश') &&
          shunyaLagnaByOddTithi[pakshaTithi]?.contains(lagnaSign) == true) {
        mark('तिथि-शून्य लग्न', false);
      }
      final isGaudaOrMalava = region.startsWith('मालव') ||
          region.startsWith('गौड़');
      if (isGaudaOrMalava &&
          lunarMonthIndexes.any((month) => shunyaRashis[month] == lagnaSign)) {
        mark('मास-शून्य राशि लग्न', false);
      }
      // Pangu, Andha and Kana are defined in Muhurta Cintamani's
      // Vivaha-prakarana (6.81–83), not as generic daily Panchanga yogas.
      // They must be evaluated only inside a marriage-muhurta workflow;
      // verse 6.82 also gives a differing afternoon/twilight scheme.

      final extendedNak = nak <= 20 ? nak : nak + 1;
      final anandadiIndex = (extendedNak - anandadiStart[weekday] + 28) % 28;
      final anandadi = anandadiNames[anandadiIndex];
      final anandadiDisplay = anandadi == 'ध्वांक्ष'
          ? 'ध्वांक्ष (ध्वाक्ष)'
          : anandadi == 'लुम्ब' ? 'लुम्ब / लंबक' : anandadi;
      // Report all 28 daily Anandadi names as informational. The source
      // assigns results by each yoga's own name; it does not make every
      // unlisted name automatically auspicious or inauspicious.
      mark('$anandadiDisplay (आनन्दादि) योग', null);
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
            'kind': previous[name] == null ? 'विशेष' :
                previous[name] == true ? 'शुभ' : 'अशुभ',
            'start': _time(startTime),
            'end': _time(boundary),
            '_startIso': startTime.toIso8601String(),
            '_endIso': boundary.toIso8601String(),
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
        'kind': previous[entry.key] == null ? 'विशेष' :
            previous[entry.key] == true ? 'शुभ' : 'अशुभ',
        'start': _time(entry.value),
        'end': _time(nextSunrise),
        '_startIso': entry.value.toIso8601String(),
        '_endIso': nextSunrise.toIso8601String(),
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
    final infoRows = _specialYogaRows
        .where((row) => row['kind'] == 'विशेष').toList();
    final hasBad = badRows.isNotEmpty;
    // Compare the actual sunrise-to-sunrise intervals. The presence of
    // both categories during a day does not mean they occur simultaneously.
    final hasSimultaneousGoodAndBad = hasGood && hasBad &&
        goodRows.any((good) => badRows.any((bad) {
          final goodStart = DateTime.parse(good['_startIso']!);
          final goodEnd = DateTime.parse(good['_endIso']!);
          final badStart = DateTime.parse(bad['_startIso']!);
          final badEnd = DateTime.parse(bad['_endIso']!);
          return goodStart.isBefore(badEnd) && badStart.isBefore(goodEnd);
        }));

    final String verdict = hasGood && hasBad
        ? hasSimultaneousGoodAndBad
            ? 'कुछ समय में शुभ और अशुभ योगों के समय में परस्पर मेल है। नीचे प्रत्येक योग का सटीक समय देखें।'
            : 'आज शुभ और अशुभ योग अलग-अलग समय पर बन रहे हैं; इसका अर्थ यह नहीं कि वे एक ही समय में प्रभावी हैं।'
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
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$_regionalRuleSummary। ऐतिहासिक क्षेत्रों की सीमाएँ अनुमानित हैं; अस्पष्ट स्थान पर क्षेत्रीय दोष स्वतः लागू नहीं किए जाते।',
            style: const TextStyle(fontSize: 10, color: Color(0xFF705333)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'नीचे केवल इसी चयनित दिन के सूर्योदय से अगले सूर्योदय तक बनने वाले योग दिए गए हैं।',
            style: TextStyle(fontSize: 10, color: Color(0xFF705333)),
          ),
        ),
        if (hasSimultaneousGoodAndBad)
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'शास्त्रीय टिप्पणी: मुहूर्त चिंतामणि, शुभाशुभ प्रकरण श्लोक 41–42 में कुछ आचार्यों के मत से चन्द्रमा की अनुकूलता, एक पहर के बाद तथा शुभ योग/लग्नशुद्धि से कुछ दोषों के परिहार का उल्लेख है। ऐप अभी इन मतों को स्वतः लागू नहीं करता; इसलिए संयुक्त समय को विचारार्थ दिखाया गया है।',
              style: TextStyle(fontSize: 10, color: Color(0xFF705333), height: 1.35),
            ),
          ),
      ]),
      yogaList('आज के शुभ योग', Icons.check_circle_outline, goodRows, true),
      yogaList('आज के अशुभ योग', Icons.warning_amber_rounded, badRows, false),
      if (infoRows.isNotEmpty)
        _detailCard('आनन्दादि योग • 28 योगों की दैनिक गणना', Icons.info_outline, [
          ...infoRows.map((row) => Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1F8),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF315B83), size: 17),
              const SizedBox(width: 8),
              Expanded(child: Text(row['name'] ?? '',
                style: const TextStyle(color: Color(0xFF315B83), fontWeight: FontWeight.w700))),
              const Text('विशेष', style: TextStyle(color: Color(0xFF315B83), fontSize: 11)),
            ]),
          )),
          const Text('आनन्दादि योग का फल उसके नाम के अनुसार माना जाता है; इसे स्वतः शुभ/अशुभ घोषित नहीं किया गया है।',
            style: TextStyle(fontSize: 10, color: Color(0xFF705333))),
        ]),
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

    // A Bhadra period may begin before sunrise or end after the next
    // sunrise. Scan beyond both edges so the card reports the real
    // Vishti boundaries rather than clipping them to the Panchang day.
    int signatureAt(DateTime instant) {
      final limb = PanchangEngine.indicesAt(instant);
      if (limb['karana'] != 6) return -1;
      return (PanchangEngine.siderealMoonLongitude(instant) / 30).floor() % 12;
    }

    DateTime refine(DateTime low, DateTime high, int oldSignature) {
      for (var i = 0; i < 32; i++) {
        final mid = low.add(Duration(
          microseconds: high.difference(low).inMicroseconds ~/ 2));
        if (signatureAt(mid) == oldSignature) {
          low = mid;
        } else {
          high = mid;
        }
      }
      return high;
    }

    const signs = ['मेष','वृषभ','मिथुन','कर्क','सिंह','कन्या',
      'तुला','वृश्चिक','धनु','मकर','कुंभ','मीन'];
    String residence(int sign) {
      if ([0, 1, 2, 7].contains(sign)) return 'स्वर्ग लोक';
      if ([5, 6, 8, 9].contains(sign)) return 'पाताल लोक';
      return 'पृथ्वी लोक';
    }

    final scanStart = sunrise!.subtract(const Duration(hours: 14));
    final scanEnd = nextSunrise.add(const Duration(hours: 14));
    final rows = <Map<String, String>>[];
    var segmentStart = scanStart;
    var previousTime = scanStart;
    var previous = signatureAt(scanStart);
    var cursor = scanStart;
    while (cursor.isBefore(scanEnd)) {
      final next = cursor.add(const Duration(minutes: 1)).isAfter(scanEnd)
          ? scanEnd : cursor.add(const Duration(minutes: 1));
      final current = signatureAt(next);
      if (current != previous) {
        final boundary = refine(previousTime, next, previous);
        if (previous >= 0 &&
            boundary.isAfter(sunrise!) &&
            segmentStart.isBefore(nextSunrise)) {
          rows.add({
            'start': _date(segmentStart) + ' ' + _time(segmentStart),
            'end': _date(boundary) + ' ' + _time(boundary),
            'sign': signs[previous],
            'residence': residence(previous),
            'kind': residence(previous) == 'पृथ्वी लोक' ? 'अशुभ' : 'अन्य लोक',
          });
        }
        segmentStart = boundary;
      }
      previous = current;
      previousTime = next;
      cursor = next;
    }
    if (previous >= 0 &&
        scanEnd.isAfter(sunrise!) &&
        segmentStart.isBefore(nextSunrise)) {
      rows.add({
        'start': _date(segmentStart) + ' ' + _time(segmentStart),
        'end': _date(scanEnd) + ' ' + _time(scanEnd),
        'sign': signs[previous],
        'residence': residence(previous),
        'kind': residence(previous) == 'पृथ्वी लोक' ? 'अशुभ' : 'अन्य लोक',
      });
    }
    return rows;
  }

  Widget _bhadraCard() {
    final windows = _bhadraWindows();
    final earthActive = windows.any((w) => w['kind'] == 'अशुभ');
    return _detailCard('भद्रा (विष्टि करण)', Icons.warning_amber_rounded, [
      _detailRow('स्थिति', windows.isEmpty ? 'इस पंचांग-दिन में भद्रा नहीं' :
          earthActive ? 'भद्रा पृथ्वी लोक में भी रहेगी' :
          'भद्रा है, पर गणना अनुसार स्वर्ग / पाताल लोक में', alternate: true),
      if (windows.isEmpty)
        _detailRow('भद्रा काल', 'नहीं है')
      else
        ...windows.map((window) => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: window['kind'] == 'अशुभ'
                ? const Color(0xFFFFEFEC) : const Color(0xFFEAF6ED),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${window['start']} से ${window['end']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 3),
            Text('चंद्र राशि: ${window['sign']}  •  भद्रा निवास: ${window['residence']}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: window['kind'] == 'अशुभ'
                  ? const Color(0xFFB3261E) : const Color(0xFF176B43))),
          ]),
        )),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'भद्रा विष्टि करण से निर्धारित होती है। चंद्रमा की निरयन राशि बदलने पर भद्रा का निवास भी बदल सकता है; इसलिए अवधि को राशि-परिवर्तन पर अलग दिखाया गया है। पृथ्वी लोक वाली भद्रा में शुभ कार्य सामान्यतः टालने की परंपरा है।',
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

  Widget _lagnaTimeCard() {
    final rows = _lagnaRows();
    return _detailCard('लग्न समय-सारणी', Icons.auto_awesome, [
      _detailRow('सूर्योदय का लग्न', _lagnaLabel(), alternate: true),
      _detailRow('सूर्य नक्षत्र', _sunNakshatra()),
      _detailRow('चंद्र नक्षत्र', "${data?['nakshatra'] ?? '—'}", alternate: true),
      if (rows.isEmpty)
        _detailRow('समय-सारणी', 'इस स्थान और तारीख के लिए उपलब्ध नहीं')
      else
        ...rows.asMap().entries.map((entry) => _detailRow(
          entry.value['name']!, entry.value['time']!, alternate: entry.key.isEven)),
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
      // 1. Live Panchang is shown first for the current local date.
      if (selectedDate.year == _liveNow.year &&
          selectedDate.month == _liveNow.month &&
          selectedDate.day == _liveNow.day)
        _liveDashboard(),
      // 2. Main Panchang.
      _detailCard('पंचांग', Icons.calendar_month, [
        _detailRow('तिथि', '${d['tithi'] ?? '—'}  •  ${_time(tithiEnd)}', alternate: true, compact: true),
        _detailRow('पक्ष', '${d['paksha'] ?? '—'}', compact: true),
        _detailRow('नक्षत्र', '${d['nakshatra'] ?? '—'} • चरण ${d['nakshatraPada'] ?? '—'} • ${_time(nakshatraEnd)}', alternate: true, compact: true),
        _detailRow('योग', '${d['yoga'] ?? '—'}  •  ${_time(yogaEnd)}', compact: true),
        _detailRow('करण', '${d['karana'] ?? '—'}  •  ${_time(karanaEnd)}', alternate: true, compact: true),
        _detailRow('वार', _weekday(selectedDate), compact: true),
      ]),
      // 3. Month, rashi, season and ayana.
      _detailCard('मास, राशि, ऋतु एवं अयन', Icons.public, [
        _detailRow('माह (अमांत)', lunarMonths['amanta'] ?? '—', alternate: true),
        _detailRow('माह (पूर्णिमांत)', lunarMonths['purnimanta'] ?? '—'),
        _detailRow('चंद्र राशि', _rashi(_siderealMoon()), alternate: true),
        _detailRow('सूर्य राशि', _rashi(_siderealSun())),
        _detailRow('ऋतु', _ritu(), alternate: true),
        _detailRow('अयन', _ayana()),
        _detailRow('सौर प्रविष्टि', '${_rashi(_siderealSun())} राशि', alternate: true),
      ]),
      // 4. Samvatsara and Samvat.
      _detailCard('संवत्सर एवं संवत्', Icons.history, [
        ..._samvatsaraRows(),
        _detailRow('लाहिड़ी अयनांश', '${(d['ayanamsha'] as num).toStringAsFixed(4)}°', alternate: true),
      ]),
      // 5. Sunrise, sunset and day length.
      _detailCard('सूर्योदय एवं दिनमान', Icons.wb_sunny, [
        _detailRow('स्थान', city, alternate: true),
        _detailRow('सूर्योदय', _time(sunrise)),
        _detailRow('सूर्यास्त', _time(sunset), alternate: true),
        _detailRow('दिन की अवधि', _detailDuration(dayLength)),
        _detailRow('रात की अवधि', _detailDuration(nightLength), alternate: true),
        _detailRow('चंद्रोदय', _time(moonrise)),
        _detailRow('चंद्रास्त', _time(moonset), alternate: true),
      ]),
      // 6. Complete ascendant time table.
      _lagnaTimeCard(),
      // 7. Panchak and other important details.
      _panchakCard(),
      _bhadraCard(),
      // 8. Shiva residence and Agni residence.
      _detailCard('शिव वास एवं अग्नि वास', Icons.local_fire_department, [..._vasaRows(d)]),
      // 9. Auspicious and inauspicious yogas stay at the end.
      ..._specialYogaCards(),
      // Calculation-source note is kept after all nine requested sections.
      Card(color: const Color(0xFFFFF4E5), child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('गणना स्रोत: Meeus आधारित खगोलीय गणना (Astronomia) तथा IMD राष्ट्रीय पंचांग से संदर्भ सत्यापन। अमांत/पूर्णिमांत मास, संवत्सर और चरण-सीमाओं को प्रकाशित करने से पहले संदर्भ पंचांग से मिलान आवश्यक है。',
          style: TextStyle(fontSize: 12, color: Color(0xFF705333)),
        ),
      )),
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


/// Month-at-a-glance calendar. Selecting a date returns it to the main
/// Panchang so every daily calculation is refreshed for that location.
class MonthlyPanchangScreen extends StatefulWidget {
  final DateTime initialDate;
  final double latitude;
  final double longitude;
  const MonthlyPanchangScreen({
    super.key,
    required this.initialDate,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<MonthlyPanchangScreen> createState() => _MonthlyPanchangScreenState();
}

class _MonthlyPanchangScreenState extends State<MonthlyPanchangScreen> {
  late DateTime month;
  late DateTime selected;
  late Future<Map<int, Map<String, String>>> dayInfoFuture;

  static const weekdays = ['रवि', 'सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि'];
  static const months = ['जनवरी','फरवरी','मार्च','अप्रैल','मई','जून',
    'जुलाई','अगस्त','सितंबर','अक्टूबर','नवंबर','दिसंबर'];

  @override
  void initState() {
    super.initState();
    selected = DateTime(widget.initialDate.year, widget.initialDate.month,
      widget.initialDate.day);
    month = DateTime(selected.year, selected.month);
    dayInfoFuture = _loadMonthInfo();
  }

  Future<Map<int, Map<String, String>>> _loadMonthInfo() async {
    final result = <int, Map<String, String>>{};
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    for (var day = 1; day <= totalDays; day++) {
      final date = DateTime(month.year, month.month, day);
      final sunrise = PanchangEngine.solarEvent(
        localDate: date,
        latitude: widget.latitude,
        longitude: widget.longitude,
        sunrise: true,
      );
      if (sunrise == null) continue;
      final limbs = PanchangEngine.indicesAt(sunrise);
      final tithiIndex = limbs['tithi'];
      if (tithiIndex == null) continue;
      final paksha = tithiIndex < 15 ? 'शु' : 'कृ';
      final tithiName = PanchangEngine.tithis[tithiIndex];
      final event = switch (tithiIndex) {
        10 => 'एकादशी व्रत',
        25 => 'एकादशी व्रत',
        14 => 'पूर्णिमा',
        29 => 'अमावस्या',
        3 => 'विनायक चतुर्थी',
        18 => 'संकष्टी चतुर्थी',
        7 => 'अष्टमी',
        22 => 'अष्टमी',
        _ => '',
      };
      final monthName = PanchangEngine.lunarMonthLabels(sunrise)['amanta'] ?? '';
      result[day] = {
        'tithi': '$paksha $tithiName',
        'event': event,
        'month': monthName,
      };
    }
    return result;
  }

  void moveMonth(int amount) => setState(() {
    month = DateTime(month.year, month.month + amount);
    dayInfoFuture = _loadMonthInfo();
  });

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final count = ((firstWeekday + days + 6) ~/ 7) * 7;
    return Scaffold(
      appBar: AppBar(
        title: const Text('मासिक पंचांग'),
        actions: [
          IconButton(
            tooltip: 'आज',
            onPressed: () => setState(() {
              selected = DateTime.now();
              month = DateTime(selected.year, selected.month);
              dayInfoFuture = _loadMonthInfo();
            }),
            icon: const Icon(Icons.today_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF174C3B), Color(0xFF28705A)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              IconButton(onPressed: () => moveMonth(-1),
                icon: const Icon(Icons.chevron_left, color: Colors.white)),
              Expanded(child: Text('${months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 19,
                  fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => moveMonth(1),
                icon: const Icon(Icons.chevron_right, color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E9E4))),
            child: Column(children: [
              Row(children: weekdays.map((d) => Expanded(child: Center(
                child: Text(d, style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: Color(0xFF587064))),
              ))).toList()),
              const SizedBox(height: 8),
              FutureBuilder<Map<int, Map<String, String>>>(
                future: dayInfoFuture,
                builder: (context, snapshot) {
                  final info = snapshot.data ?? const <int, Map<String, String>>{};
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: count,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5,
                      childAspectRatio: .72,
                    ),
                    itemBuilder: (context, index) {
                      final day = index - firstWeekday + 1;
                      if (day < 1 || day > days) return const SizedBox.shrink();
                      final date = DateTime(month.year, month.month, day);
                      final isSelected = date.year == selected.year &&
                        date.month == selected.month && date.day == selected.day;
                      final isToday = date.year == DateTime.now().year &&
                        date.month == DateTime.now().month && date.day == DateTime.now().day;
                      final dayInfo = info[day];
                      final event = dayInfo?['event'] ?? '';
                      return InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => setState(() => selected = date),
                        child: Container(
                          padding: const EdgeInsets.only(top: 5, bottom: 3),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF174C3B) :
                              isToday ? const Color(0xFFFFE9BD) : const Color(0xFFF5F7F5),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: isSelected
                              ? const Color(0xFF174C3B) : const Color(0xFFE9EEEA)),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('$day', style: TextStyle(fontSize: 13,
                              fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected ? Colors.white : const Color(0xFF263C34))),
                            const SizedBox(height: 2),
                            Text(dayInfo?['tithi'] ?? '—',
                              maxLines: 1, overflow: TextOverflow.clip,
                              style: TextStyle(fontSize: 7,
                                color: isSelected ? Colors.white70 : const Color(0xFF64766C))),
                            if (event.isNotEmpty)
                              Icon(Icons.circle, size: 5,
                                color: isSelected ? const Color(0xFFFFD88A) : const Color(0xFFB27625)),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ]),
          ),
          const SizedBox(height: 14),
          FutureBuilder<Map<int, Map<String, String>>>(
            future: dayInfoFuture,
            builder: (context, snapshot) {
              final info = snapshot.data ?? const <int, Map<String, String>>{};
              final events = info.entries.where((e) =>
                (e.value['event'] ?? '').isNotEmpty).toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E9E4))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('इस माह के व्रत एवं तिथि संकेत',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF174C3B))),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (events.isEmpty)
                    const Text('इस माह के तिथि-आधारित संकेत उपलब्ध नहीं हैं।',
                      style: TextStyle(fontSize: 12, color: Colors.black54))
                  else
                    ...events.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(children: [
                        const Icon(Icons.event_note, size: 18,
                          color: Color(0xFF9A641E)),
                        const SizedBox(width: 9),
                        Expanded(child: Text(entry.value['event']!,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${entry.key} ${months[month.month - 1]}',
                          style: const TextStyle(fontSize: 12,
                            color: Color(0xFF65736C))),
                      ]),
                    )),
                  const SizedBox(height: 5),
                  const Text('ये संकेत स्थानीय सूर्योदय की तिथि पर आधारित हैं; क्षेत्रीय पर्व-निर्णय अलग हो सकता है।',
                    style: TextStyle(fontSize: 10, color: Colors.black54)),
                ]),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFF0DFC2))),
            child: Row(children: [
              const Icon(Icons.event_note_rounded, color: Color(0xFF9A641E)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('चयनित तारीख़', style: TextStyle(fontSize: 11,
                    color: Color(0xFF80613C))),
                  Text('${selected.day} ${months[selected.month - 1]} ${selected.year}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF263C34))),
                  const Text('दैनिक तिथि, नक्षत्र और मुहूर्त देखने के लिए तारीख़ खोलें।',
                    style: TextStyle(fontSize: 10, color: Color(0xFF80613C))),
                ])),
            ]),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF174C3B),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => Navigator.pop(context, selected),
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('इस तारीख़ का पंचांग देखें'),
          ),
        ],
      ),
    );
  }
}


/// Separate monthly observance department. Dates are derived from local
/// sunrise tithi; region-specific festival decisions are explicitly labelled
/// for later Panchanga verification.
class FestivalVratScreen extends StatefulWidget {
  final DateTime initialDate;
  final double latitude;
  final double longitude;
  const FestivalVratScreen({
    super.key,
    required this.initialDate,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<FestivalVratScreen> createState() => _FestivalVratScreenState();
}

class _FestivalVratScreenState extends State<FestivalVratScreen> {
  late DateTime month;
  late Future<List<Map<String, String>>> eventsFuture;

  static const monthNames = ['जनवरी','फरवरी','मार्च','अप्रैल','मई','जून',
    'जुलाई','अगस्त','सितंबर','अक्टूबर','नवंबर','दिसंबर'];

  @override
  void initState() {
    super.initState();
    month = DateTime(widget.initialDate.year, widget.initialDate.month);
    eventsFuture = _loadEvents();
  }

  Future<List<Map<String, String>>> _loadEvents() async {
    final rows = <Map<String, String>>[];
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var day = 1; day <= days; day++) {
      final date = DateTime(month.year, month.month, day);
      final sunrise = PanchangEngine.solarEvent(
        localDate: date,
        latitude: widget.latitude,
        longitude: widget.longitude,
        sunrise: true,
      );
      if (sunrise == null) continue;
      final tithiIndex = PanchangEngine.indicesAt(sunrise)['tithi'];
      if (tithiIndex == null) continue;
      final event = switch (tithiIndex) {
        10 || 25 => 'एकादशी व्रत',
        14 => 'पूर्णिमा',
        29 => 'अमावस्या',
        3 => 'विनायक चतुर्थी',
        18 => 'संकष्टी चतुर्थी',
        _ => '',
      };
      if (event.isEmpty) continue;
      final paksha = tithiIndex < 15 ? 'शुक्ल पक्ष' : 'कृष्ण पक्ष';
      rows.add({
        'date': '$day ${monthNames[month.month - 1]} ${month.year}',
        'weekday': ['रविवार','सोमवार','मंगलवार','बुधवार','गुरुवार','शुक्रवार','शनिवार'][date.weekday % 7],
        'event': event,
        'detail': '$paksha • ${PanchangEngine.tithis[tithiIndex]}',
      });
    }
    return rows;
  }

  void _moveMonth(int amount) => setState(() {
    month = DateTime(month.year, month.month + amount);
    eventsFuture = _loadEvents();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('व्रत एवं त्योहार')),
    body: ListView(padding: const EdgeInsets.all(14), children: [
      Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF174C3B), Color(0xFF28705A)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          IconButton(onPressed: () => _moveMonth(-1),
            icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(child: Text('${monthNames[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => _moveMonth(1),
            icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('इस माह के व्रत एवं तिथि-आधारित पर्व',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
          color: Color(0xFF174C3B))),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, String>>>(
        future: eventsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()));
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Card(child: Padding(padding: EdgeInsets.all(18),
              child: Text('इस महीने के तिथि-आधारित व्रत संकेत उपलब्ध नहीं हैं।')));
          }
          return Card(child: Column(children: rows.map((row) => ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF0D5),
              child: Icon(Icons.event, color: Color(0xFF9A641E))),
            title: Text(row['event']!,
              style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${row['date']} • ${row['weekday']}\n${row['detail']}'),
            isThreeLine: true,
          )).toList())),
        },
      ),
      const SizedBox(height: 12),
      const Card(color: Color(0xFFFFF7E8), child: Padding(
        padding: EdgeInsets.all(14),
        child: Text('महत्वपूर्ण: यह सूची स्थानीय सूर्योदय पर तिथि की उपस्थिति से तैयार होती है। एकादशी, संकष्टी, क्षेत्रीय पर्व, अधिकमास तथा क्षय तिथि के अंतिम व्रत-निर्णय के लिए संबंधित परंपरा के धर्मशास्त्रीय नियमों का अलग मिलान आवश्यक है।',
          style: TextStyle(fontSize: 11, height: 1.45,
            color: Color(0xFF705333))),
      )),
    ]),
  );
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
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'cached_special_muhurats_v1';
    List<Map<String, dynamic>> sortRows(List<Map<String, dynamic>> result) {
      result.sort((a, b) {
        final da = DateTime.tryParse((a['muhurat_date'] ?? '').toString());
        final db = DateTime.tryParse((b['muhurat_date'] ?? '').toString());
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        final dateCompare = DateTime(da.year, da.month, da.day)
            .compareTo(DateTime(db.year, db.month, db.day));
        if (dateCompare != 0) return dateCompare;
        return (a['start_time'] ?? '').toString()
            .compareTo((b['start_time'] ?? '').toString());
      });
      return result;
    }
    try {
      final rows = await Supabase.instance.client.from('muhurats')
        .select('id, category, title_hi, title_en, muhurat_date, start_time, end_time, location, description, special_notes')
        .eq('is_active', true)
        .order('muhurat_date', ascending: true)
        .order('start_time', ascending: true)
        .order('sort_order', ascending: true);
      final result = sortRows(List<Map<String, dynamic>>.from(rows));
      await prefs.setString(cacheKey, jsonEncode(result));
      return result;
    } catch (error) {
      debugPrint('KARMKRITE MUHURAT OFFLINE FALLBACK: $error');
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return sortRows(List<Map<String, dynamic>>.from(
          (jsonDecode(cached) as List)
              .map((x) => Map<String, dynamic>.from(x as Map)),
        ));
      }
      return [];
    }
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