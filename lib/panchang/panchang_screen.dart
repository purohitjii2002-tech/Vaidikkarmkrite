import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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
  String? error;
  Map<String, dynamic>? data;
  DateTime? sunrise, sunset;
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLat = prefs.getDouble('panchang_latitude');
      final savedLon = prefs.getDouble('panchang_longitude');
      final savedCity = prefs.getString('panchang_city');
      if (savedLat != null && savedLon != null) {
        position = Position(
          latitude: savedLat, longitude: savedLon, timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0,
          headingAccuracy: 0, speed: 0, speedAccuracy: 0,
        );
        city = savedCity ?? 'चुना हुआ स्थान';
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw Exception('मोबाइल Location बंद है। आप सूची से अपना शहर चुन सकते हैं।');
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw Exception('आप Location अनुमति दिए बिना भी सूची से अपना शहर चुन सकते हैं।');
        }
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 20),
          ),
        );
        final places = await placemarkFromCoordinates(
          position!.latitude, position!.longitude,
        );
        if (places.isNotEmpty) {
          final p = places.first;
          city = [p.locality, p.subAdministrativeArea, p.administrativeArea]
              .where((x) => x != null && x.trim().isNotEmpty).toSet().join(', ');
          if (city.isEmpty) city = 'वर्तमान स्थान';
        }
      }
      _calculate();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _chooseLocation() async {
    try {
      final raw = await rootBundle.loadString('assets/data/india_states_districts.json');
      final states = List<Map<String, dynamic>>.from(jsonDecode(raw));
      String selectedState = states.first['name'].toString();
      String? selectedDistrict;
      final cityController = TextEditingController();
      final choice = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final stateData = states.firstWhere((x) => x['name'] == selectedState);
            final districts = List<Map<String, dynamic>>.from(stateData['districts']);
            selectedDistrict ??= districts.first['name'].toString();
            return AlertDialog(
              title: const Text('पंचांग के लिए स्थान चुनें'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Align(alignment: Alignment.centerLeft, child: Text('राज्य / केंद्रशासित प्रदेश')),
                    DropdownButtonFormField<String>(
                      isExpanded: true, value: selectedState,
                      items: states.map((x) => DropdownMenuItem<String>(
                        value: x['name'].toString(),
                        child: Text(x['name'].toString(), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          selectedState = v;
                          final d = states.firstWhere((x) => x['name'] == v)['districts'] as List;
                          selectedDistrict = d.first['name'].toString();
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    const Align(alignment: Alignment.centerLeft, child: Text('जिला')),
                    DropdownButtonFormField<String>(
                      isExpanded: true, value: selectedDistrict,
                      items: districts.map((x) => DropdownMenuItem<String>(
                        value: x['name'].toString(),
                        child: Text(x['name'].toString(), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) => setDialogState(() => selectedDistrict = v),
                    ),
                    const SizedBox(height: 14),
                    const Align(alignment: Alignment.centerLeft, child: Text('शहर / कस्बा (वैकल्पिक)')),
                    TextField(
                      controller: cityController,
                      decoration: const InputDecoration(
                        hintText: 'जैसे: उज्जैन, इंदौर, झालरापाटन',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('शहर का नाम भरें या केवल जिला चुनें। पंचांग चुने गए स्थान के निर्देशांकों से बनेगा।',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('रद्द करें')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, {
                    'state': selectedState,
                    'district': selectedDistrict ?? '',
                    'city': cityController.text.trim(),
                  }),
                  child: const Text('स्थान चुनें'),
                ),
              ],
            );
          },
        ),
      );
      cityController.dispose();
      if (choice == null) return;
      final enteredCity = choice['city'] ?? '';
      final district = choice['district'] ?? '';
      final state = choice['state'] ?? '';
      final searchName = enteredCity.isNotEmpty
          ? '$enteredCity, $district, $state, India'
          : '$district, $state, India';
      setState(() { loading = true; error = null; });
      final locations = await locationFromAddress(searchName);
      if (locations.isEmpty) throw Exception('इस स्थान के निर्देशांक नहीं मिले। कृपया शहर का नाम जाँचें।');
      final loc = locations.first;
      position = Position(
        latitude: loc.latitude, longitude: loc.longitude, timestamp: DateTime.now(),
        accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0,
        headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      );
      city = enteredCity.isNotEmpty
          ? '$enteredCity, $district, $state'
          : '$district, $state';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('panchang_latitude', loc.latitude);
      await prefs.setDouble('panchang_longitude', loc.longitude);
      await prefs.setString('panchang_city', city);
      _calculate();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
      return {'name': names[i], 'time': '${_time(a)} – ${_time(b)}'};
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
    return _eightParts(night ? sunset : sunrise,
      night ? sunrise!.add(const Duration(days: 1)) : sunset, names);
  }

  List<Map<String, String>> _horaRows() {
    if (sunrise == null || sunset == null) return [];
    const planets = ['शनि','गुरु','मंगल','सूर्य','शुक्र','बुध','चन्द्र'];
    const weekdayLord = ['सूर्य','चन्द्र','मंगल','बुध','गुरु','शुक्र','शनि'];
    var index = planets.indexOf(weekdayLord[selectedDate.weekday % 7]);
    final nextSunrise = sunrise!.add(const Duration(days: 1));
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
    final nightEnd = sunrise!.add(const Duration(days: 1));
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

  Widget _sectionHeading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(children: [Icon(icon, color: const Color(0xFF79502B)),
      const SizedBox(width: 8), Text(title, style: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF563719)))]),
  );

  Widget _timeList(List<Map<String, String>> rows) => Card(
    color: Colors.white,
    child: Column(children: rows.map((row) => ListTile(
      dense: true,
      title: Text(row['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: row['kind'] == null ? null : Text(row['kind']!),
      trailing: Text(row['time'] ?? '', style: const TextStyle(
        color: Color(0xFF79502B), fontSize: 12, fontWeight: FontWeight.w600)),
    )).toList()),
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
          IconButton(tooltip: 'शहर चुनें', onPressed: _chooseLocation, icon: const Icon(Icons.location_city)),
          IconButton(tooltip: 'वर्तमान स्थान', onPressed: () async { final p = await SharedPreferences.getInstance(); await p.remove('panchang_latitude'); await p.remove('panchang_longitude'); await p.remove('panchang_city'); _load(); }, icon: const Icon(Icons.my_location)),
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
                    OutlinedButton.icon(onPressed: _chooseLocation, icon: const Icon(Icons.location_city), label: const Text('अपना शहर चुनें')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6B4528), Color(0xFF9B7042)],
                          ),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.location_on, color: Color(0xFFFFD88A)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(city, style: const TextStyle(color: Colors.white))),
                            IconButton(tooltip: 'शहर बदलें', onPressed: _chooseLocation, icon: const Icon(Icons.edit_location_alt, color: Colors.white)),
                            TextButton(onPressed: _chooseDate,
                              child: const Text('तारीख बदलें', style: TextStyle(color: Colors.white))),
                          ]),
                          const SizedBox(height: 8),
                          Text(_weekday(selectedDate), style: const TextStyle(color: Colors.white70)),
                          Text(_date(selectedDate), style: const TextStyle(
                            color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold,
                          )),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: _sunInfo('सूर्योदय', _time(sunrise), Icons.wb_sunny_outlined)),
                            Expanded(child: _sunInfo('सूर्यास्त', _time(sunset), Icons.wb_twilight)),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (data == null)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('इस तारीख के लिए सूर्योदय/सूर्यास्त उपलब्ध नहीं है।'),
                        ))
                      else ...[
                        const Text('पंचांग विवरण', style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF563719),
                        )),
                        const SizedBox(height: 8),
                        _tile('तिथि', data!['tithi'].toString() + ' • ' + data!['paksha'].toString(), Icons.brightness_3_outlined),
                        _tile('नक्षत्र', data!['nakshatra'].toString() + ' • चरण ' + data!['nakshatraPada'].toString(), Icons.star_outline),
                        _tile('योग', data!['yoga'].toString(), Icons.auto_awesome),
                        _tile('करण', data!['karana'].toString(), Icons.circle_outlined),
                        _tile('राहुकाल', _rahuKaal() ?? 'उपलब्ध नहीं', Icons.schedule),
                        _sectionHeading('दैनिक मुहूर्त एवं काल', Icons.access_time),
                        _muhurtaDial(),
                        _timeList(_dailyWindows()),
                        _sectionHeading('दिन का चौघड़िया', Icons.wb_sunny_outlined),
                        _timeList(_choghadiya(false)),
                        _sectionHeading('रात्रि का चौघड़िया', Icons.nightlight_round),
                        _timeList(_choghadiya(true)),
                        _sectionHeading('दिन-रात की ग्रह होरा', Icons.timelapse),
                        _timeList(_horaRows()),
                        _tile('अयनांश (लाहिड़ी)', (data!['ayanamsha'] as double).toStringAsFixed(4) + '°', Icons.explore_outlined),
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'गणना स्थानीय सूर्योदय पर आधारित है। यह प्रारंभिक संस्करण है; तिथि-समाप्ति, मुहूर्त और व्रत-त्योहार का सत्यापन जारी है।',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ],
                      Card(
                        color: const Color(0xFFFFF0D5),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF79502B), child: Icon(Icons.event_available, color: Colors.white)),
                          title: const Text('विशेष मुहूर्त', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('वास्तु, विवाह, वाहन, हल, मुंडन आदि के मुहूर्त देखें'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 17),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MuhuratListScreen())),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sunInfo(String label, String value, IconData icon) => Row(children: [
    Icon(icon, color: const Color(0xFFFFD88A), size: 20),
    const SizedBox(width: 6),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      .eq('is_active', true).order('muhurat_date').order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  String dateLabel(dynamic value) {
    if (value == null) return '';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return value.toString();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('विशेष मुहूर्त')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('मुहूर्त लोड नहीं हो सके।'),
          ElevatedButton(onPressed: () => setState(() => future = loadMuhurats()), child: const Text('दोबारा प्रयास करें')),
        ]));
        final all = snapshot.data ?? [];
        final items = selectedCategory == 'सभी' ? all : all.where((x) => (x['category'] ?? '').toString() == selectedCategory).toList();
        return Column(children: [
          SizedBox(height: 58, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: categories.map((category) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
              label: Text(category), selected: selectedCategory == category,
              onSelected: (_) => setState(() => selectedCategory = category),
            ))).toList(),
          )),
          Expanded(child: items.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('इस श्रेणी के मुहूर्त अभी एडमिन द्वारा जोड़े नहीं गए हैं।', textAlign: TextAlign.center)))
            : RefreshIndicator(onRefresh: () async { setState(() => future = loadMuhurats()); await future; },
              child: ListView.builder(padding: const EdgeInsets.fromLTRB(14, 4, 14, 20), itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final time = [item['start_time'], item['end_time']].where((x) => x != null && x.toString().trim().isNotEmpty).join(' – ');
                  return Card(margin: const EdgeInsets.only(bottom: 12), child: ExpansionTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFFFF0D5), child: Icon(Icons.event, color: Color(0xFF79502B))),
                    title: Text((item['title_hi'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([(item['category'] ?? '').toString(), dateLabel(item['muhurat_date']), time].where((x) => x.isNotEmpty).join(' • ')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if ((item['location'] ?? '').toString().isNotEmpty) _detailLine(Icons.location_on, item['location'].toString()),
                      if ((item['description'] ?? '').toString().isNotEmpty) _detailLine(Icons.info_outline, item['description'].toString()),
                      if ((item['special_notes'] ?? '').toString().isNotEmpty) _detailLine(Icons.notes, item['special_notes'].toString()),
                    ],
                  ));
                },
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
