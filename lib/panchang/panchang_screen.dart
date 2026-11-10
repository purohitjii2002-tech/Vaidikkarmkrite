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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('कृपया मोबाइल की Location सेवा चालू करें।');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('शहर के अनुसार पंचांग के लिए Location अनुमति आवश्यक है।');
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
          IconButton(onPressed: _load, icon: const Icon(Icons.my_location)),
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
