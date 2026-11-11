import 'package:flutter/material.dart';
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
  int selectedMuhuratTab = 0;

  @override
  void initState() { super.initState(); _load(); }

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
      // Permission denied, GPS disabled, timeout, or location service failure:
      // show a useful Panchang for Ujjain instead of a blocking error.
      position = null;
    }

    if (position == null) {
      position = _positionAt(_ujjainLatitude, _ujjainLongitude);
      city = 'उज्जैन (मानक स्थान)';
    }
    _calculate();
    if (mounted) setState(() { loading = false; error = null; });
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
                      _muhuratTabs(),
                      const SizedBox(height: 12),
                      ..._selectedTabContent(),
                      const SizedBox(height: 10),
                      Card(
                        color: const Color(0xFFFFF0D5),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF79502B), child: Icon(Icons.event_available, color: Colors.white)),
                          title: const Text('विशेष मुहूर्त', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('एडमिन द्वारा प्रकाशित वास्तु, विवाह, वाहन, हल-पूजन, मुंडन आदि के मुहूर्त'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 17),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MuhuratListScreen())),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

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
        return [
          _sectionHeading('लग्न समय-सारणी', Icons.auto_awesome),
          Card(color: const Color(0xFFFFF7E8), child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('बारहों लग्न', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('लग्न के आरंभ और समाप्ति का समय स्थानीय अक्षांश, देशांतर और सटीक खगोलीय समय पर निर्भर करता है।'),
              SizedBox(height: 8),
              Text('इसकी गणना का सत्यापन पूरा होने तक समय प्रकाशित नहीं किया जाएगा।',
                style: TextStyle(color: Color(0xFF8A4B20), fontWeight: FontWeight.w600)),
            ]),
          )),
        ];
      default:
        return [];
    }
  }


  static const _rashiNames = ['मेष','वृषभ','मिथुन','कर्क','सिंह','कन्या','तुला','वृश्चिक','धनु','मकर','कुंभ','मीन'];
  static const _nakshatraNames = ['अश्विनी','भरणी','कृत्तिका','रोहिणी','मृगशीर्ष','आर्द्रा','पुनर्वसु','पुष्य','आश्लेषा','मघा','पूर्वा फाल्गुनी','उत्तरा फाल्गुनी','हस्त','चित्रा','स्वाती','विशाखा','अनुराधा','ज्येष्ठा','मूल','पूर्वाषाढ़ा','उत्तराषाढ़ा','श्रवण','धनिष्ठा','शतभिषा','पूर्वा भाद्रपद','उत्तरा भाद्रपद','रेवती'];
  int _siderealSign(double longitude) => ((((longitude % 360) + 360) % 360) / 30).floor();
  String _rashi(double longitude) => _rashiNames[_siderealSign(longitude)];
  double _siderealSun() => ((data!['sunLongitude'] as num).toDouble() - (data!['ayanamsha'] as num).toDouble());
  double _siderealMoon() => ((data!['moonLongitude'] as num).toDouble() - (data!['ayanamsha'] as num).toDouble());
  String _sunNakshatra() {
    final lon = (_siderealSun() % 360 + 360) % 360;
    return _nakshatraNames[(lon / (360 / 27)).floor() % 27];
  }
  String _ritu() {
    const seasons = ['वसंत','वसंत','ग्रीष्म','ग्रीष्म','वर्षा','वर्षा','शरद','शरद','हेमंत','हेमंत','शिशिर','शिशिर'];
    return seasons[_siderealSign(_siderealSun())];
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
  Widget _detailRow(String label, String value, {bool alternate = false}) => Container(
    color: alternate ? const Color(0xFFFFF6E9) : Colors.transparent,
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: Text(label, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Color(0xFF98652D)))),
      const SizedBox(width: 12),
      Expanded(flex: 6, child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF286342), fontWeight: FontWeight.w600))),
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
  List<Widget> _dayPanchangDetails() {
    final d = data!;
    final dayLength = sunrise != null && sunset != null ? sunset!.difference(sunrise!) : Duration.zero;
    final nightLength = const Duration(days: 1) - dayLength;
    final vikram = selectedDate.year + (selectedDate.month >= 4 ? 57 : 56);
    final shaka = selectedDate.year - (selectedDate.month >= 3 ? 78 : 79);
    return [
      _detailCard('पंचांग विवरण', Icons.calendar_month, [
        _detailRow('तिथि', '${d['tithi'] ?? '—'}', alternate: true),
        _detailRow('पक्ष', '${d['paksha'] ?? '—'}'),
        _detailRow('नक्षत्र', '${d['nakshatra'] ?? '—'}', alternate: true),
        _detailRow('योग', '${d['yoga'] ?? '—'}'),
        _detailRow('करण', '${d['karana'] ?? '—'}', alternate: true),
        _detailRow('वार', _weekday(selectedDate)),
        _detailRow('तिथि समाप्ति', _time(d['tithiEnd'] as DateTime?)),
        _detailRow('नक्षत्र समाप्ति', _time(d['nakshatraEnd'] as DateTime?), alternate: true),
        _detailRow('योग समाप्ति', _time(d['yogaEnd'] as DateTime?)),
        _detailRow('करण समाप्ति', _time(d['karanaEnd'] as DateTime?), alternate: true),
      ]),
      _detailCard('शिव वास एवं अग्नि वास', Icons.local_fire_department, [
        ..._vasaRows(d),
      ]),
      _detailCard('मास, राशि, ऋतु एवं अयन', Icons.public, [
        _detailRow('माह (अमांत)', 'चंद्र मास गणना सत्यापनाधीन', alternate: true),
        _detailRow('माह (पूर्णिमांत)', 'चंद्र मास गणना सत्यापनाधीन'),
        _detailRow('चंद्र राशि', _rashi(_siderealMoon()), alternate: true),
        _detailRow('सूर्य राशि', _rashi(_siderealSun())),
        _detailRow('ऋतु', _ritu(), alternate: true),
        _detailRow('अयन', _ayana()),
        _detailRow('सौर मास / प्रविष्टि', '${_rashi(_siderealSun())} सौर मास', alternate: true),
      ]),
      _detailCard('संवत्सर एवं संवत', Icons.history, [
        _detailRow('संवत्सर नाम', '60-वर्षीय चक्र सत्यापनाधीन', alternate: true),
        _detailRow('विक्रम संवत', '$vikram विक्रम संवत'),
        _detailRow('गुजराती संवत', 'क्षेत्रीय संवत गणना सत्यापनाधीन', alternate: true),
        _detailRow('शक संवत', '$shaka शक संवत'),
        _detailRow('कलि संवत', '${selectedDate.year + 3101} कलि संवत', alternate: true),
        _detailRow('लाहिड़ी अयनांश', '${(d['ayanamsha'] as num).toStringAsFixed(4)}°'),
      ]),
      _detailCard('सूर्योदय एवं दिनमान', Icons.wb_sunny, [
        _detailRow('स्थान', city, alternate: true),
        _detailRow('सूर्योदय', _time(sunrise)),
        _detailRow('सूर्यास्त', _time(sunset), alternate: true),
        _detailRow('दिन की अवधि', _detailDuration(dayLength)),
        _detailRow('रात की अवधि', _detailDuration(nightLength), alternate: true),
      ]),
      _detailCard('सूर्योदय समय का ज्योतिषीय विवरण', Icons.wb_twilight, [
        _detailRow('सूर्य नक्षत्र', _sunNakshatra(), alternate: true),
        _detailRow('चंद्र नक्षत्र', '${d['nakshatra'] ?? '—'}'),
        _detailRow('चंद्र नक्षत्र चरण', '${d['nakshatraPada'] ?? '—'}', alternate: true),
        _detailRow('लग्न', 'सटीक लग्न गणना सत्यापनाधीन'),
        _detailRow('चंद्रोदय', 'खगोलीय गणना सत्यापनाधीन', alternate: true),
        _detailRow('चंद्रास्त', 'खगोलीय गणना सत्यापनाधीन'),
      ]),
      Card(color: const Color(0xFFFFF4E5), child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('सूचना: तिथि, नक्षत्र, योग और करण दृक् गणित से निकाले जा रहे हैं। मास, संवत्सर, चंद्रोदय-चंद्रास्त, लग्न तथा पर्व-निर्णय के परिणाम पारंपरिक उज्जैन पंचांग से सत्यापन के बाद ही अंतिम माने जाएँगे।',
          style: TextStyle(fontSize: 12, color: Color(0xFF705333))),
      )),
    ];
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
