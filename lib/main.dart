
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:audioplayers/audioplayers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://srhypcyogbojcpbmshmu.supabase.co',
    anonKey: 'sb_publishable_viNNn3p8q9e2HtAS8Lypow_AmWRVRth',
  );

  runApp(const KarmKriteApp());
}

class KarmKriteApp extends StatefulWidget {
  const KarmKriteApp({super.key});

  @override
  State<KarmKriteApp> createState() => _KarmKriteAppState();
}

class _KarmKriteAppState extends State<KarmKriteApp> {
  String language = 'hi';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KARMKRITE',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F1E7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF123D32),
          primary: const Color(0xFF123D32),
          secondary: const Color(0xFFC9A45C),
          surface: const Color(0xFFFFFCF4),
          onPrimary: const Color(0xFFFFFCF4),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF123D32),
          foregroundColor: Color(0xFFFFF8E8),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(color: Color(0xFFFFF8E8), fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: .6),
          iconTheme: IconThemeData(color: Color(0xFFE5C77E)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF10352D),
          indicatorColor: const Color(0xFF315B4D),
          labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            TextStyle(fontSize: 11, fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800 : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                ? const Color(0xFFFFD98B) : const Color(0xFFD7D0BE))),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
              ? const Color(0xFFFFD98B) : const Color(0xFFD7D0BE))),
          elevation: 12,
          shadowColor: const Color(0x33000000),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFCF4),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: HomeScreen(
        language: language,
        onLanguageChanged: (value) {
          setState(() => language = value);
        },
      ),
    );
  }
}

class AppText {
  static const translations = {
    'hi': {
      'home': 'होम',
      'library': 'पुस्तकालय',
      'saved': 'सहेजे गए',
      'search': 'यहाँ खोजें...',
      'modules': 'ज्ञान के प्रमुख विभाग',
      'daily': 'आज का वैदिक विचार',
      'welcome': 'शास्त्र से संस्कार तक',
      'coming': 'यह सामग्री शीघ्र उपलब्ध होगी।',
      'select': 'भाषा चुनें',
      'notifications': 'सूचनाएँ',
      'empty': 'इस विभाग की सामग्री शीघ्र उपलब्ध होगी।',
      'error': 'सामग्री लोड नहीं हो सकी।',
      'retry': 'दोबारा प्रयास करें',
    },
    'sa': {
      'home': 'गृहम्',
      'library': 'ग्रन्थालयः',
      'saved': 'संगृहीतम्',
      'search': 'अन्वेषणम्...',
      'modules': 'ज्ञानविभागाः',
      'daily': 'अद्यतनः वैदिकः विचारः',
      'welcome': 'शास्त्रात् संस्कारपर्यन्तम्',
      'coming': 'इयं सामग्री शीघ्रं उपलब्धा भविष्यति।',
      'select': 'भाषां चिनुत',
      'notifications': 'सूचनाः',
      'empty': 'इयं सामग्री शीघ्रं उपलब्धा भविष्यति।',
      'error': 'सामग्री लोड नहीं हो सकी।',
      'retry': 'पुनः प्रयत्न करें',
    },
    'en': {
      'home': 'Home',
      'library': 'Library',
      'saved': 'Saved',
      'search': 'Search here...',
      'modules': 'Knowledge Categories',
      'daily': 'Today’s Vedic Thought',
      'welcome': 'From Scriptures to Values',
      'coming': 'This content will be available soon.',
      'select': 'Select Language',
      'notifications': 'Notifications',
      'empty': 'Content for this category will be available soon.',
      'error': 'Could not load content.',
      'retry': 'Try Again',
    },
  };

  static String get(String language, String key) {
    return translations[language]?[key] ??
        translations['hi']![key] ??
        key;
  }
}

// Category Model
class ModuleInfo {
  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final List<String> items;

  const ModuleInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
  });
}

// Category design templates
const List<ModuleInfo> modules = [
  ModuleInfo(
    id: '',
    title: 'वेद एवं शास्त्र',
    subtitle: 'प्राचीन ज्ञान का अध्ययन',
    icon: '📚',
    items: [],
  ),
  ModuleInfo(
    id: '',
    title: 'कर्मकांड',
    subtitle: 'पूजा एवं धार्मिक विधियाँ',
    icon: '🪔',
    items: [],
  ),
  ModuleInfo(
    id: '',
    title: 'मंत्र एवं स्तोत्र',
    subtitle: 'मंत्र पाठ एवं स्तुति',
    icon: '🕉️',
    items: [],
  ),
  ModuleInfo(
    id: '',
    title: 'षोडश संस्कार',
    subtitle: 'जीवन के सोलह संस्कार',
    icon: '🙏',
    items: [],
  ),
  ModuleInfo(
    id: '',
    title: 'ऑडियो एवं पुस्तकें',
    subtitle: 'श्रवण एवं अध्ययन सामग्री',
    icon: '🎧',
    items: [],
  ),
];

// Load Categories from Supabase
Future<List<ModuleInfo>> loadModules(String language) async {
  final prefs = await SharedPreferences.getInstance();
  const cacheKey = 'cached_public_categories_v1';

  List<ModuleInfo> parseRows(List<dynamic> rows) {
    const iconMap = {
      'book': '📚', 'temple': '🪔', 'om': '🕉️',
      'flower': '🙏', 'calendar': '🌞', 'headphones': '🎧',
    };
    final visibleRows = rows.where((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final hindi = (row['name_hi'] ?? '').toString().toLowerCase();
      final english = (row['name_en'] ?? '').toString().toLowerCase();
      return !hindi.contains('पंचांग') &&
          !english.contains('panchang');
    }).toList();
    return visibleRows.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final hindiName = (row['name_hi'] ?? '').toString();
      final englishName = (row['name_en'] ?? hindiName).toString();
      final template = modules.firstWhere(
        (module) => module.title == hindiName,
        orElse: () => ModuleInfo(
          id: '', title: hindiName,
          subtitle: (row['description'] ?? '').toString(),
          icon: '📖', items: const [],
        ),
      );
      final iconName = (row['icon'] ?? '').toString();
      return ModuleInfo(
        id: (row['id'] ?? '').toString(),
        title: language == 'en' ? englishName : hindiName,
        subtitle: (row['description'] ?? template.subtitle).toString(),
        icon: iconMap[iconName] ?? template.icon,
        items: const [],
      );
    }).toList();
  }

  try {
    final response = await Supabase.instance.client
        .from('categories')
        .select('id, name_hi, name_en, description, icon')
        .eq('is_active', true)
        .order('sort_order').order('created_at');
    final rows = List<dynamic>.from(response as List);
    await prefs.setString(cacheKey, jsonEncode(rows));
    return parseRows(rows);
  } catch (error, stackTrace) {
    debugPrint('KARMKRITE DATABASE ERROR (offline fallback): $error');
    debugPrint('$stackTrace');
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        return parseRows(List<dynamic>.from(jsonDecode(cached) as List));
      } catch (cacheError) {
        debugPrint('KARMKRITE CATEGORY CACHE ERROR: $cacheError');
      }
    }
    // First launch without internet: keep the app navigable using built-in categories.
    return modules.map((module) => ModuleInfo(
      id: module.id,
      title: language == 'en' ? const {
        'वेद एवं शास्त्र': 'Vedas & Scriptures',
        'कर्मकांड': 'Rituals',
        'मंत्र एवं स्तोत्र': 'Mantras & Hymns',
        'षोडश संस्कार': 'Sixteen Samskaras',
          'ऑडियो एवं पुस्तकें': 'Audio & Books',
      }[module.title] ?? module.title : module.title,
      subtitle: module.subtitle,
      icon: module.icon,
      items: module.items,
    )).toList();
  }
}

class HomeScreen extends StatefulWidget {
  final String language;
  final ValueChanged<String> onLanguageChanged;

  const HomeScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedTab = 0;
  String searchText = '';

  late Future<List<ModuleInfo>> modulesFuture;

  String tr(String key) => AppText.get(widget.language, key);

  @override
  void initState() {
    super.initState();
    modulesFuture = loadModules(widget.language);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.language != widget.language) {
      modulesFuture = loadModules(widget.language);
    }
  }

  Future<void> refreshModules() async {
    final future = loadModules(widget.language);
    setState(() {
      modulesFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: selectedTab == 0 ? AppBar(
        title: const BrandMark(dark: true),
        actions: [
          IconButton(
            tooltip: tr('notifications'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: tr('select'),
            icon: const Icon(Icons.language_rounded),
            onSelected: widget.onLanguageChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'hi', child: Text('हिंदी')),
              PopupMenuItem(value: 'sa', child: Text('संस्कृत')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ) : null,
      body: selectedTab == 0 ? _homeBody() : _otherTabBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: tr('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            label: tr('library'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_border_rounded),
            label: tr('saved'),
          ),
        ],
      ),
    );
  }

  Widget _homeBody() {
    return FutureBuilder<List<ModuleInfo>>(
      future: modulesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: Color(0xFF79502B),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'डेटाबेस से जानकारी नहीं मिल सकी।',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: refreshModules,
                    child: const Text('दोबारा प्रयास करें'),
                  ),
                ],
              ),
            ),
          );
        }

        final allModules = snapshot.data ?? [];

        final filteredModules = allModules.where((module) {
          final query = searchText.trim().toLowerCase();

          if (query.isEmpty) return true;

          return module.title.toLowerCase().contains(query) ||
              module.subtitle.toLowerCase().contains(query);
        }).toList();

        return RefreshIndicator(
          onRefresh: refreshModules,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeBanner(),
                const SizedBox(height: 18),
                _quickAccessStrip(),
                const SizedBox(height: 18),
                const HomeBanners(),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) {
                    setState(() => searchText = value);
                  },
                  decoration: InputDecoration(
                    hintText: tr('search'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFFFFCF4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
                    prefixIconColor: const Color(0xFF9A7A42),
                    hintStyle: const TextStyle(color: Color(0xFF988B76), fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: Color(0xFFE2D5B8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: Color(0xFFE2D5B8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: Color(0xFFC9A45C), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Container(width: 4, height: 24, decoration: BoxDecoration(
                    color: const Color(0xFFC9A45C), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr('modules'), style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF173E34)))),
                  const Text('EXPLORE', style: TextStyle(fontSize: 9, letterSpacing: 1.6,
                    fontWeight: FontWeight.w900, color: Color(0xFF9A7A42))),
                ]),
                const SizedBox(height: 12),
                if (filteredModules.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('कोई Category नहीं मिली।'),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredModules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final module = filteredModules[index];
                      return SizedBox(
                        height: 94,
                        child: ModuleCard(
                          module: module,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ModuleScreen(
                                  module: module,
                                  language: widget.language,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 22),
                _dailyThought(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _welcomeBanner() {
    final now = DateTime.now();
    const months = ['जनवरी','फरवरी','मार्च','अप्रैल','मई','जून','जुलाई','अगस्त','सितंबर','अक्टूबर','नवंबर','दिसंबर'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 19, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C2D26), Color(0xFF145044), Color(0xFF1C6553)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFD9B96E).withOpacity(.85), width: 1.1),
        boxShadow: const [BoxShadow(color: Color(0x24133D35), blurRadius: 20, offset: Offset(0, 9))],
      ),
      child: Stack(
        children: [
          Positioned(right: -18, top: -24,
            child: Icon(Icons.spa_rounded, size: 150, color: Colors.white.withOpacity(.055))),
          Positioned(right: 8, bottom: -25,
            child: Icon(Icons.temple_hindu_rounded, size: 102, color: const Color(0xFFDDBB79).withOpacity(.10))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 43, height: 43,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: const Color(0xFFFFF5DE).withOpacity(.13),
                    border: Border.all(color: const Color(0xFFE7C987), width: 1.2)),
                  child: const Center(child: Text('ॐ', style: TextStyle(
                    fontSize: 26, color: Color(0xFFFFD98B), fontWeight: FontWeight.w600))),
                ),
                const SizedBox(width: 11),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('KARMKRITE', style: TextStyle(color: Color(0xFFFFE2A6),
                    fontSize: 12, letterSpacing: 2.0, fontWeight: FontWeight.w900)),
                  SizedBox(height: 2),
                  Text('वैदिक ज्ञान • परंपरा • संस्कार', style: TextStyle(
                    color: Color(0xFFE5F0E9), fontSize: 10, letterSpacing: .35)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.10),
                    borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)),
                  child: Text('${now.day} ${months[now.month-1]}',
                    style: const TextStyle(color: Color(0xFFFFE7BC), fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 22),
              Text(tr('welcome'), style: const TextStyle(
                color: Colors.white, fontSize: 25, height: 1.18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('भारतीय ज्ञान, वैदिक परंपरा और संस्कारों का आपका अपना डिजिटल मंच।',
                style: TextStyle(color: Color(0xFFE3EEE8), fontSize: 12.5, height: 1.55)),
              const SizedBox(height: 17),
              Row(children: [
                Container(width: 34, height: 2, decoration: BoxDecoration(
                  color: const Color(0xFFE6BE70), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                const Text('ज्ञान से जीवन को आलोकित करें',
                  style: TextStyle(color: Color(0xFFFFE3B0), fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAccessStrip() {
    Widget action({required IconData icon, required String title,
      required String subtitle, required VoidCallback onTap}) {
      return Expanded(child: Material(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE0D4B9)),
              boxShadow: const [BoxShadow(color: Color(0x0B332514), blurRadius: 9, offset: Offset(0, 3))],
            ),
            child: Row(children: [
              Container(width: 39, height: 39,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF174A3E), Color(0xFF0D332B)]),
                  borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: const Color(0xFFE7C77D), size: 21)),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF173E34), fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF887B67), fontSize: 9.5)),
              ])),
            ]),
          ),
        ),
      ));
    }
    return Row(children: [
      action(icon: Icons.temple_hindu_rounded, title: 'पूजा एवं यज्ञ',
        subtitle: 'कर्मकांड • विधि • मंत्र', onTap: () async {
          final available = await modulesFuture;
          if (!mounted || available.isEmpty) return;
          final module = available.firstWhere(
            (item) => item.title.contains('कर्मकांड') ||
                item.title.toLowerCase().contains('ritual'),
            orElse: () => available.first,
          );
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ModuleScreen(module: module, language: widget.language),
          ));
        }),
      const SizedBox(width: 10),
      action(icon: Icons.menu_book_rounded, title: 'ज्ञान पुस्तकालय',
        subtitle: 'ग्रंथ • मंत्र • विधियाँ', onTap: () {
          setState(() => selectedTab = 1);
        }),
    ]);
  }

  Widget _dailyThought() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('daily_thoughts')
          .select('thought_hi, thought_sa, thought_en, meaning_hi, source')
          .eq('is_active', true)
          .order('display_date', ascending: false)
          .limit(1)
          .then((rows) => List<Map<String, dynamic>>.from(rows)),
      builder: (context, snapshot) {
        final item = snapshot.data?.isNotEmpty == true ? snapshot.data!.first : null;
        final thought = item == null ? 'सत्यं वद। धर्मं चर।' :
            (widget.language == 'en' ? (item['thought_en'] ?? item['thought_hi']) :
             widget.language == 'sa' ? (item['thought_sa'] ?? item['thought_hi']) : item['thought_hi']).toString();
        final meaning = item == null ? 'सत्य बोलो और धर्म के मार्ग पर चलो।' :
            (item['meaning_hi'] ?? '').toString();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0D5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7C98E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('daily'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF68451F))),
              const SizedBox(height: 12),
              Text(thought, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Color(0xFF79502B))),
              if (meaning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(meaning, style: const TextStyle(fontSize: 14)),
              ],
              if ((item?['source'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('स्रोत: ' + item!['source'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
              if(item!=null) Align(alignment:Alignment.centerRight,child:SaveItemButton(item:{'id':'daily-thought-'+(item['source']??thought).toString(),'title':thought,'body':meaning,'description':'आज का वैदिक विचार','category':'आज का वैदिक विचार'})),
            ],
          ),
        );
      },
    );
  }

  Widget _otherTabBody() {
    switch (selectedTab) {
      case 1: return BooksScreen(language: widget.language, onBack: () => setState(() => selectedTab = 0));
      case 2: return SavedScreen(language: widget.language, onBack: () => setState(() => selectedTab = 0));
      default: return _homeBody();
    }
  }
}

// Category Card
class ModuleCard extends StatelessWidget {
  final ModuleInfo module;
  final VoidCallback onTap;
  const ModuleCard({super.key, required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF173E34);
    const gold = Color(0xFFB18A43);
    return Material(
      color: const Color(0xFFFFFCF4),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0D4B9)),
            boxShadow: const [
              BoxShadow(color: Color(0x0C2B1A0D), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF174A3E), Color(0xFF0D332B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFC9A45C), width: 1.1),
                  ),
                  alignment: Alignment.center,
                  child: Text(module.icon, style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        module.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.3, color: Color(0xFF817565)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Color(0xFFF1E7D1), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded, color: gold, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Category Content Screen
class ModuleScreen extends StatefulWidget {
  final ModuleInfo module;
  final String language;

  const ModuleScreen({
    super.key,
    required this.module,
    required this.language,
  });

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  late Future<List<Map<String, dynamic>>> contentFuture;

  String tr(String key) => AppText.get(widget.language, key);

  @override
  void initState() {
    super.initState();
    contentFuture = loadContent();
  }

  Future<List<Map<String, dynamic>>> loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cached_category_content_v1_${widget.module.id.isEmpty ? widget.module.title : widget.module.id}';
    try {
      final response = await Supabase.instance.client
          .from('content_items')
          .select(
            'id, title, title_hi, title_en, description, body, type, media_url, media_type, media_name',
          )
          .eq('category_id', widget.module.id)
          .eq('is_active', true)
          .order('created_at');
      final items = List<Map<String, dynamic>>.from(response);
      await prefs.setString(cacheKey, jsonEncode(items));
      return items;
    } catch (error) {
      debugPrint('KARMKRITE CONTENT OFFLINE FALLBACK: $error');
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          (jsonDecode(cached) as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      }
      return [];
    }
  }

  String getTitle(Map<String, dynamic> item) {
    if (widget.language == 'en') {
      return (item['title_en'] ??
              item['title'] ??
              item['title_hi'] ??
              '')
          .toString();
    }

    return (item['title_hi'] ?? item['title'] ?? '').toString();
  }

  void openContent(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContentDetailScreen(
          title: getTitle(item),
          content: (item['body'] ?? '').toString(),
          description: (item['description'] ?? '').toString(),
          mediaUrl: (item['media_url'] ?? '').toString(),
          mediaType: (item['media_type'] ?? '').toString(),
          savedItem:{...item,'title':getTitle(item),'category':widget.module.title,'body':(item['body']??'').toString(),'description':(item['description']??'').toString()},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0C2D26), Color(0xFF145044), Color(0xFF1C6553)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: const Color(0xFFD9B96E).withOpacity(.85)),
              boxShadow: const [
                BoxShadow(color: Color(0x24133D35), blurRadius: 19, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4DC).withOpacity(.13),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: const Color(0xFFD5A34B).withOpacity(.55)),
                  ),
                  alignment: Alignment.center,
                  child: Text(widget.module.icon, style: const TextStyle(fontSize: 34)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('KARMKRITE KNOWLEDGE',
                        style: TextStyle(color: Color(0xFFE8C98E), fontSize: 9,
                          letterSpacing: 1.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(widget.module.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 19,
                          height: 1.2, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(widget.module.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFE8DED0), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: contentFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr('error'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                contentFuture = loadContent();
                              });
                            },
                            child: Text(tr('retry')),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        tr('empty'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFEFA),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE9DDC8)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x0D332514), blurRadius: 12, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => openContent(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 43,
                                  height: 43,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF1DF),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('${index + 1}',
                                    style: const TextStyle(color: Color(0xFF805522),
                                      fontWeight: FontWeight.w800, fontSize: 15)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(getTitle(item), maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Color(0xFF563719),
                                          fontWeight: FontWeight.w800, fontSize: 14, height: 1.25)),
                                      if ((item['description'] ?? '').toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text((item['description'] ?? '').toString(),
                                          maxLines: 2, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF817565), fontSize: 11, height: 1.3)),
                                      ],
                                    ],
                                  ),
                                ),
                                SaveItemButton(item:{...item,'title':getTitle(item),'category':widget.module.title,'body':(item['body']??'').toString(),'description':(item['description']??'').toString()}),
                                const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9853E), size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Full Content Detail Screen
class SaveItemButton extends StatefulWidget { final Map<String,dynamic> item; const SaveItemButton({super.key,required this.item}); @override State<SaveItemButton> createState()=>_SaveItemButtonState(); }
class _SaveItemButtonState extends State<SaveItemButton>{ bool saved=false; bool busy=false; @override void initState(){super.initState();SavedStore.has(widget.item).then((v){if(mounted)setState(()=>saved=v);});} Future<void> toggle() async {if(busy)return;setState(()=>busy=true);await SavedStore.toggle({...widget.item,'_remove':saved});if(!mounted)return;setState((){saved=!saved;busy=false;});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(saved?'सहेज दिया गया।':'सहेजी गई सामग्री से हटाया गया।')));} @override Widget build(BuildContext context)=>IconButton(tooltip:saved?'सहेजे गए से हटाएँ':'सहेजें',onPressed:busy?null:toggle,icon:Icon(saved?Icons.bookmark:Icons.bookmark_border,color:const Color(0xFF173E34))); }
class SavedStore {
  static const key = 'saved_content_items';
  static Future<List<Map<String,dynamic>>> read() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(key) ?? []).map((x) {
      try { return Map<String,dynamic>.from(jsonDecode(x)); } catch (_) { return <String,dynamic>{}; }
    }).where((x) => x.isNotEmpty).toList();
  }
  static String identity(Map<String,dynamic> x) => (x['id'] ?? x['media_url'] ?? x['pdf_url'] ?? '${x['title']}|${x['category']}').toString();
  static Future<bool> has(Map<String,dynamic> item) async => (await read()).any((x)=>identity(x)==identity(item));
  static Future<void> toggle(Map<String,dynamic> item) async { final p=await SharedPreferences.getInstance(); final all=await read(); final id=identity(item); all.removeWhere((x)=>identity(x)==id); if(item['_remove']!=true){final clean=Map<String,dynamic>.from(item)..remove('_remove');all.insert(0,clean);} await p.setStringList(key,all.map(jsonEncode).toList()); }
}

class ContentDetailScreen extends StatefulWidget {
  final String title, content, description;
  final String mediaUrl, mediaType;
  final Map<String,dynamic> savedItem;
  const ContentDetailScreen({
    super.key, required this.title, required this.content, required this.description,
    this.mediaUrl = '', this.mediaType = '', this.savedItem = const {},
  });
  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  bool saved = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  File? _cachedMediaFile;
  bool _mediaLoading = false;

  @override
  void initState() {
    super.initState();
    SavedStore.has(widget.savedItem.isEmpty ? {'title':widget.title} : widget.savedItem).then((v) { if (mounted) setState(() => saved = v); });
    _audioPlayer.onPlayerStateChanged.listen((v) { if (mounted) setState(() => _playerState = v); });
    _audioPlayer.onDurationChanged.listen((v) { if (mounted) setState(() => _duration = v); });
    _audioPlayer.onPositionChanged.listen((v) { if (mounted) setState(() => _position = v); });
    if (widget.mediaUrl.isNotEmpty &&
        (widget.mediaType == 'image' || widget.mediaType == 'audio')) {
      _prepareMediaCache();
    }
  }

  Future<void> _prepareMediaCache() async {
    if (!mounted) return;
    setState(() => _mediaLoading = true);
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/media_cache');
      await cacheDir.create(recursive: true);
      final key = sha256.convert(utf8.encode(widget.mediaUrl)).toString();
      final uri = Uri.parse(widget.mediaUrl);
      var extension = uri.pathSegments.isEmpty ? '' :
          uri.pathSegments.last.split('.').last;
      if (extension.isEmpty || extension.length > 5) {
        extension = widget.mediaType == 'image' ? 'img' : 'audio';
      }
      final file = File('${cacheDir.path}/$key.$extension');
      if (!await file.exists() || await file.length() == 0) {
        final response = await http.get(uri).timeout(const Duration(seconds: 45));
        if (response.statusCode < 200 || response.statusCode >= 300 ||
            response.bodyBytes.isEmpty) {
          throw Exception('Media download failed');
        }
        final part = File('${file.path}.part');
        await part.writeAsBytes(response.bodyBytes, flush: true);
        if (await file.exists()) await file.delete();
        await part.rename(file.path);
      }
      if (mounted) setState(() => _cachedMediaFile = file);
    } catch (error) {
      debugPrint('KARMKRITE MEDIA CACHE: $error');
    } finally {
      if (mounted) setState(() => _mediaLoading = false);
    }
  }

  Future<void> toggle() async {
    final item=widget.savedItem.isEmpty?{'title':widget.title,'body':widget.content,'description':widget.description}:Map<String,dynamic>.from(widget.savedItem);
    await SavedStore.toggle({...item,'_remove':saved});
    if (!mounted) return;
    setState(() => saved = !saved);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved ? 'सहेज दिया गया।' : 'सहेजी गई सामग्री से हटाया गया।')));
  }

  Future<void> playPause() async {
    if (_playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else if (_cachedMediaFile != null && await _cachedMediaFile!.exists()) {
      await _audioPlayer.play(DeviceFileSource(_cachedMediaFile!.path));
    } else if (widget.mediaUrl.isNotEmpty) {
      await _audioPlayer.play(UrlSource(widget.mediaUrl));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('यह ऑडियो ऑफलाइन उपलब्ध नहीं है। इंटरनेट चालू करके इसे एक बार डाउनलोड करें।')),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const BrandMark(),
      actions: [
        IconButton(
          tooltip: saved ? 'सहेजी गई सामग्री से हटाएँ' : 'सहेजें',
          onPressed: toggle,
          icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0C2D26), Color(0xFF145044), Color(0xFF1C6553)],
            ),
            border: Border.all(color: const Color(0xFFD9B879), width: 0.8),
            boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 15, offset: Offset(0, 6))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_stories_rounded, color: Color(0xFFE8C987), size: 18),
              const SizedBox(width: 7),
              const Text('KARMKRITE  •  ज्ञान-संग्रह',
                style: TextStyle(color: Color(0xFFFFD98B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const Spacer(),
              if (saved) const Icon(Icons.bookmark_rounded, color: Color(0xFFE8C987), size: 18),
            ]),
            const SizedBox(height: 13),
            Text(widget.title, style: const TextStyle(
              fontSize: 24, height: 1.3, fontWeight: FontWeight.w800, color: Colors.white)),
            if (widget.description.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(widget.description, style: const TextStyle(
                fontSize: 14, height: 1.55, color: Color(0xFFEFE3D1))),
            ],
          ]),
        ),
        if (widget.mediaType == 'image' && widget.mediaUrl.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFFFCF4),
              borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE0D4B9))),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: _cachedMediaFile != null && _cachedMediaFile!.existsSync()
                  ? Image.file(_cachedMediaFile!, width: double.infinity, fit: BoxFit.contain)
                  : _mediaLoading
                      ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
                      : const Padding(padding: EdgeInsets.all(20),
                          child: Text('फोटो ऑफलाइन उपलब्ध नहीं है। इंटरनेट चालू करके इसे एक बार खोलें।'))),
          ),
        ],
        if (widget.mediaType == 'audio' && widget.mediaUrl.isNotEmpty) ...[
          const SizedBox(height: 18),
          Card(
            color: const Color(0xFFFFFCF4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFD9C99F))),
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 16, 10), child: Row(children: [
              IconButton(
                iconSize: 42, color: const Color(0xFF174A3E), onPressed: playPause,
                icon: Icon(_playerState == PlayerState.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ऑडियो सुनें', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF563719))),
                Slider(value: _duration.inMilliseconds == 0 ? 0 :
                  _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
                  max: _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds.toDouble(),
                  activeColor: const Color(0xFFC9A45C),
                  onChanged: _duration.inMilliseconds == 0 ? null :
                    (v) => _audioPlayer.seek(Duration(milliseconds: v.round()))),
                Text('${_position.inSeconds} / ${_duration.inSeconds} सेकंड',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8B7965))),
              ])),
            ])),
          ),
        ],
        const SizedBox(height: 22),
        Row(children: [
          Container(width: 4, height: 22, decoration: BoxDecoration(
            color: const Color(0xFFD5A34B), borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 9),
          const Text('विस्तृत जानकारी', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF173E34))),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: const Color(0xFFFFFEFA),
            borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFECE2D3))),
          child: SelectableText(
            widget.content.isEmpty ? 'इस विषय की विस्तृत सामग्री शीघ्र उपलब्ध होगी।' : widget.content,
            style: const TextStyle(fontSize: 16, height: 1.9, color: Color(0xFF3F352B))),
        ),
      ]),
    ),
  );
}

class BooksScreen extends StatefulWidget {
  final String language;
  final VoidCallback onBack;
  const BooksScreen({super.key,required this.language,required this.onBack});
  @override
  State<BooksScreen> createState()=>_BooksScreenState();
}
class _BooksScreenState extends State<BooksScreen> {
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState(){super.initState();future=load();}
  Future<List<Map<String,dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = await Supabase.instance.client.from('books')
        .select('id,title_hi,title_en,author,description,cover_url,book_versions(pdf_url,version_no)')
        .eq('is_active',true).order('created_at',ascending:false);
      final books = List<Map<String,dynamic>>.from(rows)
        .where((book) {
          final versions = book['book_versions'] as List<dynamic>? ?? const [];
          return versions.any((version) =>
            (version is Map ? (version['pdf_url'] ?? '').toString().trim() : '').isNotEmpty);
        }).toList();
      // Hide admin-created entries without an uploaded PDF; they cannot be opened.
      await prefs.setString('cached_library_books', jsonEncode(books));
      return books;
    } catch (error) {
      final cached = prefs.getString('cached_library_books');
      if (cached != null && cached.isNotEmpty) {
        return List<Map<String,dynamic>>.from(
          (jsonDecode(cached) as List).map((item) =>
            Map<String,dynamic>.from(item as Map)),
        );
      }
      rethrow;
    }
  }
  Future<void> openBook(Map<String,dynamic> b) async {
    final versions=List<Map<String,dynamic>>.from(b['book_versions']??[]);
    versions.sort((a,b)=>((b['version_no']??0) as num).compareTo((a['version_no']??0) as num));
    final url=versions.isEmpty?'':(versions.first['pdf_url']??'').toString().trim();
    final uri=Uri.tryParse(url);
    if(uri==null || !uri.hasScheme || (uri.scheme!='https' && uri.scheme!='http')){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('इस पुस्तक की PDF का लिंक सही नहीं है।')));
      return;
    }
    if(!mounted)return;
    final title=(widget.language=='en'?b['title_en']:b['title_hi'])??b['title_hi']??'पुस्तक';
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>InAppPdfReader(title:title.toString(),url:url)));
  }
  @override
  Widget build(BuildContext context) {
    final en=widget.language=='en';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip:'वापस जाएँ', icon:const Icon(Icons.arrow_back), onPressed:widget.onBack),
        title: Text(en?'Digital Library':'डिजिटल पुस्तकालय'),
      ),
      body: FutureBuilder<List<Map<String,dynamic>>>(
        future:future,
        builder:(context,s){
          if(s.connectionState==ConnectionState.waiting) {
            return const Center(child:CircularProgressIndicator(color:Color(0xFF9A6B35)));
          }
          if(s.hasError) {
            return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Icon(Icons.cloud_off_rounded,size:42,color:Color(0xFF9A6B35)),
              const SizedBox(height:12),
              const Text('पुस्तकें लोड नहीं हो सकीं।'),
              const SizedBox(height:10),
              ElevatedButton(onPressed:()=>setState(()=>future=load()),child:const Text('पुनः प्रयास करें')),
            ]));
          }
          final books=s.data??[];
          return RefreshIndicator(
            color:const Color(0xFF9A6B35),
            onRefresh:()async { setState(()=>future=load()); await future; },
            child: ListView(
              padding:const EdgeInsets.fromLTRB(16,12,16,24),
              children:[
                Container(
                  padding:const EdgeInsets.all(19),
                  decoration:BoxDecoration(
                    gradient:const LinearGradient(
                      colors:[Color(0xFF0C2D26),Color(0xFF145044),Color(0xFF1C6553)],
                      begin:Alignment.topLeft,end:Alignment.bottomRight,
                    ),
                    borderRadius:BorderRadius.circular(22),
                    border:Border.all(color:const Color(0xFFD9B96E).withOpacity(.85)),
                  ),
                  child:Row(children:[
                    Container(
                      width:54,height:54,
                      decoration:BoxDecoration(
                        color:Colors.white.withOpacity(.12),
                        borderRadius:BorderRadius.circular(16),
                      ),
                      child:const Icon(Icons.auto_stories_rounded,color:Color(0xFFFFD98B),size:29),
                    ),
                    const SizedBox(width:14),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(en?'KARMKRITE LIBRARY':'कर्मकृते डिजिटल ग्रंथालय',
                        style:const TextStyle(color:Color(0xFFFFE2A6),fontSize:15,fontWeight:FontWeight.w800)),
                      const SizedBox(height:5),
                      Text(en?'Read and explore the knowledge collection':'ग्रंथों, पुस्तकों और संदर्भ सामग्री का अध्ययन करें',
                        style:const TextStyle(color:Color(0xFFE8DED0),fontSize:11,height:1.35)),
                    ])),
                  ]),
                ),
                const SizedBox(height:20),
                Row(children:[
                  const Expanded(child:Text('उपलब्ध पुस्तकें',
                    style:TextStyle(color:Color(0xFF563719),fontSize:17,fontWeight:FontWeight.w800))),
                  Text('${books.length} पुस्तकें',
                    style:const TextStyle(color:Color(0xFF8A765C),fontSize:11,fontWeight:FontWeight.w700)),
                ]),
                const SizedBox(height:10),
                if(books.isEmpty)
                  Container(
                    padding:const EdgeInsets.all(24),
                    decoration:BoxDecoration(color:const Color(0xFFFFFEFA),
                      borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFE9DDC8))),
                    child:const Column(children:[
                      Icon(Icons.menu_book_rounded,size:42,color:Color(0xFFB9853E)),
                      SizedBox(height:10),
                      Text('मास्टर एडमिन से जोड़ी गई पुस्तकें यहाँ दिखाई देंगी।',textAlign:TextAlign.center,
                        style:TextStyle(color:Color(0xFF817565),height:1.4)),
                    ]),
                  )
                else
                  ...books.map((b){
                    final title=(en?b['title_en']:b['title_hi'])??b['title_hi']??'';
                    final coverUrl=(b['cover_url']??'').toString().trim();
                    final author=(b['author']??'').toString();
                    final description=(b['description']??'').toString();
                    return Container(
                      margin:const EdgeInsets.only(bottom:12),
                      decoration:BoxDecoration(
                        color:const Color(0xFFFFFEFA),
                        borderRadius:BorderRadius.circular(18),
                        border:Border.all(color:const Color(0xFFE9DDC8)),
                        boxShadow:const[BoxShadow(color:Color(0x0D332514),blurRadius:12,offset:Offset(0,4))],
                      ),
                      child:Material(
                        color:Colors.transparent,
                        borderRadius:BorderRadius.circular(18),
                        child:InkWell(
                          borderRadius:BorderRadius.circular(18),
                          onTap:()=>openBook(b),
                          child:Padding(
                            padding:const EdgeInsets.all(12),
                            child:Row(children:[
                              ClipRRect(
                                borderRadius:BorderRadius.circular(11),
                                child:coverUrl.isNotEmpty
                                  ?Image.network(coverUrl,width:62,height:78,fit:BoxFit.cover,
                                    errorBuilder:(_,__,___)=>_bookCoverPlaceholder())
                                  :_bookCoverPlaceholder(),
                              ),
                              const SizedBox(width:13),
                              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                                Text(title.toString(),maxLines:2,overflow:TextOverflow.ellipsis,
                                  style:const TextStyle(color:Color(0xFF563719),fontSize:14,fontWeight:FontWeight.w800,height:1.25)),
                                if(author.isNotEmpty)...[
                                  const SizedBox(height:5),
                                  Text(author,maxLines:1,overflow:TextOverflow.ellipsis,
                                    style:const TextStyle(color:Color(0xFF9A6B35),fontSize:11,fontWeight:FontWeight.w700)),
                                ],
                                if(description.isNotEmpty)...[
                                  const SizedBox(height:4),
                                  Text(description,maxLines:2,overflow:TextOverflow.ellipsis,
                                    style:const TextStyle(color:Color(0xFF817565),fontSize:10.5,height:1.3)),
                                ],
                                const SizedBox(height:8),
                                const Row(children:[
                                  Icon(Icons.picture_as_pdf_rounded,size:14,color:Color(0xFFB9853E)),
                                  SizedBox(width:5),
                                  Text('PDF में पढ़ें',style:TextStyle(color:Color(0xFF805522),fontSize:10.5,fontWeight:FontWeight.w800)),
                                ]),
                              ])),
                              const SizedBox(width:5),
                              const Icon(Icons.chevron_right_rounded,color:Color(0xFFB9853E)),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bookCoverPlaceholder() => Container(
    width:62,height:78,
    color:const Color(0xFFFAF1DF),
    alignment:Alignment.center,
    child:const Icon(Icons.menu_book_rounded,color:Color(0xFFB9853E),size:30),
  );
}

class InAppPdfReader extends StatefulWidget {
  final String title;
  final String url;
  const InAppPdfReader({super.key,required this.title,required this.url});

  @override
  State<InAppPdfReader> createState()=>_InAppPdfReaderState();
}

class _InAppPdfReaderState extends State<InAppPdfReader> {
  late Future<PdfControllerPinch> _controllerFuture;
  PdfControllerPinch? _controller;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _rightToLeft = false;
  final TextEditingController _pageSearchController = TextEditingController();

  List<int> get _visiblePageNumbers {
    if (_totalPages <= 0) return const [];
    final count = _totalPages < 11 ? _totalPages : 11;
    var start = _currentPage - 5;
    if (start < 1) start = 1;
    final maxStart = _totalPages - count + 1;
    if (start > maxStart) start = maxStart;
    return List<int>.generate(count, (index) => start + index);
  }

  void _jumpToPage(PdfControllerPinch controller, int page) {
    if (page < 1 || page > _totalPages) return;
    controller.jumpToPage(page);
    if (mounted) setState(() => _currentPage = page);
  }

  void _goToPage(PdfControllerPinch controller) {
    final page = int.tryParse(_pageSearchController.text.trim());
    if (page == null || page < 1 || page > _totalPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('कृपया 1 से $_totalPages के बीच सही पेज नंबर लिखें।')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    controller.jumpToPage(page);
    setState(()=>_currentPage=page);
  }

  @override
  void initState(){
    super.initState();
    _controllerFuture=_loadPdf();
  }

  Future<PdfControllerPinch> _loadPdf({bool forceRefresh = false}) async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}/pdf_cache');
    await cacheDir.create(recursive: true);
    final cacheKey = sha256.convert(utf8.encode(widget.url)).toString();
    final cachedFile = File('${cacheDir.path}/$cacheKey.pdf');

    bool validPdfBytes(List<int> bytes) =>
        bytes.length >= 5 &&
        bytes[0] == 0x25 && bytes[1] == 0x50 &&
        bytes[2] == 0x44 && bytes[3] == 0x46 && bytes[4] == 0x2D;

    // Reuse only a real PDF cache; older builds could cache an HTML error page.
    if (!forceRefresh && await cachedFile.exists()) {
      final cachedBytes = await cachedFile.openRead(0, 5).fold<List<int>>(
        <int>[], (all, chunk) => all..addAll(chunk));
      if (validPdfBytes(cachedBytes)) {
        final cachedController = PdfControllerPinch(
          document: PdfDocument.openFile(cachedFile.path),
        );
        _controller = cachedController;
        return cachedController;
      }
      await cachedFile.delete();
    }

    try {
      final response = await http.get(
        Uri.parse(widget.url),
        headers: const {'Accept': 'application/pdf, application/octet-stream;q=0.9'},
      ).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('सर्वर ने HTTP ${response.statusCode} दिया।');
      }
      if (!validPdfBytes(response.bodyBytes)) {
        final contentType = response.headers['content-type'] ?? 'अज्ञात';
        throw Exception('लिंक से PDF के बजाय दूसरी सामग्री मिली (Content-Type: $contentType)।');
      }

      // Write atomically; never replace a good offline copy with a bad response.
      final temporaryFile = File('${cachedFile.path}.part');
      await temporaryFile.writeAsBytes(response.bodyBytes, flush: true);
      final writtenBytes = await temporaryFile.openRead(0, 5).fold<List<int>>(
        <int>[], (all, chunk) => all..addAll(chunk));
      if (!validPdfBytes(writtenBytes)) {
        await temporaryFile.delete();
        throw Exception('डाउनलोड की गई PDF अधूरी या अमान्य है।');
      }
      if (await cachedFile.exists()) await cachedFile.delete();
      await temporaryFile.rename(cachedFile.path);

      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(cachedFile.path),
      );
      _controller = controller;
      return controller;
    } catch (error) {
      // If refresh fails (or the device is offline), retain a verified old copy.
      if (await cachedFile.exists()) {
        final cachedBytes = await cachedFile.openRead(0, 5).fold<List<int>>(
          <int>[], (all, chunk) => all..addAll(chunk));
        if (validPdfBytes(cachedBytes)) {
          final cachedController = PdfControllerPinch(
            document: PdfDocument.openFile(cachedFile.path),
          );
          _controller = cachedController;
          return cachedController;
        }
      }
      rethrow;
    }
  }

  void _reloadPdf() {
    _controller?.dispose();
    _controller = null;
    _currentPage = 1;
    _totalPages = 0;
    setState(()=>_controllerFuture=_loadPdf(forceRefresh: true));
  }

  @override
  void dispose(){
    _pageSearchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      backgroundColor:const Color(0xFFF5F1E7),
      appBar:AppBar(
        title:Row(children:[
          const Icon(Icons.menu_book_rounded,color:Color(0xFFE8C987),size:20),
          const SizedBox(width:9),
          Expanded(child:Text(widget.title,maxLines:1,overflow:TextOverflow.ellipsis)),
        ]),
        actions:[
          IconButton(
            tooltip:_rightToLeft ? 'बाएँ से दाएँ पढ़ें' : 'दाएँ से बाएँ पढ़ें',
            icon:Icon(_rightToLeft ? Icons.format_textdirection_l_to_r : Icons.format_textdirection_r_to_l),
            onPressed:()=>setState(()=>_rightToLeft=!_rightToLeft),
          ),
          IconButton(tooltip:'पुनः लोड करें',icon:const Icon(Icons.refresh),onPressed:_reloadPdf),
          const SizedBox(width:4),
        ],
      ),
      body:FutureBuilder<PdfControllerPinch>(
        future:_controllerFuture,
        builder:(context,snapshot){
          if(snapshot.connectionState==ConnectionState.waiting){
            return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              CircularProgressIndicator(),
              SizedBox(height:14),
              Text('पुस्तक खोली जा रही है…',style:TextStyle(color:Color(0xFF684521),fontWeight:FontWeight.w600)),
            ]));
          }
          if(snapshot.hasError){
            return Center(child:Padding(
              padding:const EdgeInsets.all(24),
              child:Container(
                padding:const EdgeInsets.all(22),
                decoration:BoxDecoration(color:const Color(0xFFFFFCF4),borderRadius:BorderRadius.circular(20),
                  border:Border.all(color:const Color(0xFFD9C99F))),
                child:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.picture_as_pdf_outlined,size:52,color:Color(0xFF79502B)),
                  const SizedBox(height:12),
                  Text(
                    'PDF अभी नहीं खुल सकी।\n${snapshot.error ?? 'कृपया पुनः प्रयास करें।'}',
                    textAlign:TextAlign.center,
                    style:const TextStyle(height:1.5),
                  ),
                  const SizedBox(height:14),
                  ElevatedButton.icon(onPressed:_reloadPdf,icon:const Icon(Icons.refresh),label:const Text('पुनः प्रयास करें')),
                ]),
              ),
            ));
          }
          final controller=snapshot.data!;
          return Column(children:[
            Padding(
              padding:const EdgeInsets.fromLTRB(12,10,12,9),
              child:Container(
                padding:const EdgeInsets.fromLTRB(12,8,8,8),
                decoration:BoxDecoration(color:const Color(0xFFFFFCF4),borderRadius:BorderRadius.circular(16),
                  border:Border.all(color:const Color(0xFFD9C99F)),
                  boxShadow:const [BoxShadow(color:Color(0x0C000000),blurRadius:9,offset:Offset(0,3))]),
                child:Row(children:[
                  const Icon(Icons.search_rounded,color:Color(0xFF98652D),size:21),
                  const SizedBox(width:8),
                  Expanded(child:TextField(
                    controller:_pageSearchController,keyboardType:TextInputType.number,textInputAction:TextInputAction.go,
                    decoration:const InputDecoration(
                      hintText:'पेज नंबर लिखें',isDense:true,border:InputBorder.none,
                      contentPadding:EdgeInsets.symmetric(vertical:8)),
                    onSubmitted:(_)=>_goToPage(controller),
                  )),
                  Container(
                    padding:const EdgeInsets.symmetric(horizontal:9,vertical:7),
                    decoration:BoxDecoration(color:const Color(0xFFECE2C9),borderRadius:BorderRadius.circular(9)),
                    child:Text(_totalPages>0 ? '$_currentPage / $_totalPages' : 'पेज',
                      style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:Color(0xFF79502B))),
                  ),
                  const SizedBox(width:7),
                  ElevatedButton(
                    style:ElevatedButton.styleFrom(minimumSize:const Size(54,40),padding:const EdgeInsets.symmetric(horizontal:12),
                      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
                    onPressed:()=>_goToPage(controller),child:const Text('जाएँ'),
                  ),
                ]),
              ),
            ),
            Expanded(
              child:Container(
                margin:const EdgeInsets.fromLTRB(8,0,8,8),
                decoration:BoxDecoration(color:const Color(0xFFECE5D9),borderRadius:BorderRadius.circular(14)),
                clipBehavior:Clip.antiAlias,
                child:Directionality(
                  textDirection:_rightToLeft ? TextDirection.rtl : TextDirection.ltr,
                  child:PdfViewPinch(
                    controller:controller,scrollDirection:Axis.horizontal,
                    onDocumentLoaded:(document){if(mounted)setState(()=>_totalPages=document.pagesCount);},
                    onPageChanged:(page){if(mounted)setState(()=>_currentPage=page);},
                    builders:PdfViewPinchBuilders<DefaultBuilderOptions>(
                      options:const DefaultBuilderOptions(),
                      documentLoaderBuilder:(_)=>const Center(child:CircularProgressIndicator()),
                      pageLoaderBuilder:(_)=>const ColoredBox(color:Colors.white),
                      errorBuilder:(_,error)=>Center(child:Text('पेज लोड नहीं हो सका: '+error.toString(),textAlign:TextAlign.center)),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top:false,
              child:Container(
                width:double.infinity,
                padding:const EdgeInsets.fromLTRB(7,9,7,9),
                decoration:const BoxDecoration(color:Color(0xFFFFFCF4),
                  border:Border(top:BorderSide(color:Color(0xFFD9C99F))),
                  boxShadow:[BoxShadow(color:Color(0x10000000),blurRadius:10,offset:Offset(0,-3))]),
                child:Row(children:[
                  SizedBox(width:44,height:48,child:IconButton(
                    tooltip:'पिछला पेज',padding:EdgeInsets.zero,
                    constraints:const BoxConstraints.tightFor(width:44,height:48),
                    style:IconButton.styleFrom(backgroundColor:const Color(0xFFECE2C9),foregroundColor:const Color(0xFF174A3E)),
                    onPressed:_currentPage>1 ? ()=>_jumpToPage(controller,_currentPage-1) : null,
                    icon:const Icon(Icons.chevron_left_rounded,size:32))),
                  const SizedBox(width:4),
                  Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.center,
                    children:_visiblePageNumbers.map((page){
                      final isCurrent=page==_currentPage;
                      return Expanded(child:Padding(
                        padding:const EdgeInsets.symmetric(horizontal:1.5),
                        child:Material(
                          color:isCurrent ? const Color(0xFF174A3E) : const Color(0xFFFFFCF4),
                          borderRadius:BorderRadius.circular(9),
                          child:InkWell(
                            borderRadius:BorderRadius.circular(9),onTap:()=>_jumpToPage(controller,page),
                            child:Container(
                              height:44,alignment:Alignment.center,
                              decoration:BoxDecoration(borderRadius:BorderRadius.circular(9),
                                border:Border.all(color:isCurrent ? const Color(0xFFC9A45C) : const Color(0xFFD9C99F))),
                              child:FittedBox(fit:BoxFit.scaleDown,child:Text('$page',
                                style:TextStyle(fontSize:13,fontWeight:isCurrent ? FontWeight.w800 : FontWeight.w600,
                                  color:isCurrent ? Colors.white : const Color(0xFF563719)))),
                            ),
                          ),
                        ),
                      ));
                    }).toList())),
                  const SizedBox(width:4),
                  SizedBox(width:44,height:48,child:IconButton(
                    tooltip:'अगला पेज',padding:EdgeInsets.zero,
                    constraints:const BoxConstraints.tightFor(width:44,height:48),
                    style:IconButton.styleFrom(backgroundColor:const Color(0xFFFFF1D9),foregroundColor:const Color(0xFF79502B)),
                    onPressed:_totalPages>0 && _currentPage<_totalPages ? ()=>_jumpToPage(controller,_currentPage+1) : null,
                    icon:const Icon(Icons.chevron_right_rounded,size:32))),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class SavedScreen extends StatefulWidget {
  final String language;
  final VoidCallback onBack;
  const SavedScreen({super.key,required this.language,required this.onBack});
  @override
  State<SavedScreen> createState()=>_SavedScreenState();
}
class _SavedScreenState extends State<SavedScreen>{
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState(){super.initState();future=SavedStore.read();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(leading:IconButton(tooltip:'वापस जाएँ',icon:const Icon(Icons.arrow_back),onPressed:widget.onBack),title:Text(widget.language=='en'?'Saved Items':'सहेजी गई सामग्री')),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){
      if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      final items=s.data??[];
      if(items.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('किसी सामग्री, फोटो, ऑडियो या विचार के बुकमार्क बटन को दबाएँ। वह यहाँ दिखाई देगा।',textAlign:TextAlign.center)));
      return ListView.builder(padding:const EdgeInsets.all(14),itemCount:items.length,itemBuilder:(context,i){final x=items[i];final image=x['media_type']=='image'?(x['media_url']??'').toString():'';
        return Card(child:ListTile(
        leading:image.isNotEmpty?ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.network(image,width:48,height:54,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.image_not_supported))):Icon(x['media_type']=='audio'?Icons.headphones:Icons.bookmark,color:const Color(0xFF173E34)),
        title:Text((x['title']??'').toString()),subtitle:Text((x['description']??x['category']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ContentDetailScreen(title:(x['title']??'').toString(),content:(x['body']??'').toString(),description:(x['description']??'').toString(),mediaUrl:(x['media_url']??'').toString(),mediaType:(x['media_type']??'').toString(),savedItem:x))).then((_){setState(()=>future=SavedStore.read());}),
        trailing:IconButton(icon:const Icon(Icons.delete_outline),tooltip:'हटाएँ',onPressed:()async{await SavedStore.toggle({...x,'_remove':true});setState(()=>future=SavedStore.read());})));});
    }));
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}
class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState() { super.initState(); future = load(); }
  Future<List<Map<String,dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'cached_public_notifications_v1';
    try {
      final rows = await Supabase.instance.client
        .from('notifications')
        .select('id,title,message,scheduled_at,sent_at,created_at')
        .eq('is_active', true)
        .order('created_at', ascending: false);
      final items = List<Map<String,dynamic>>.from(rows);
      await prefs.setString(cacheKey, jsonEncode(items));
      return items;
    } catch (error) {
      debugPrint('KARMKRITE NOTIFICATION OFFLINE FALLBACK: $error');
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return List<Map<String,dynamic>>.from(
          (jsonDecode(cached) as List).map((x) => Map<String,dynamic>.from(x as Map)),
        );
      }
      return [];
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('सूचनाएँ')),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
        if (snapshot.hasError) return Center(child:ElevatedButton(onPressed:()=>setState(()=>future=load()),child:const Text('पुनः प्रयास करें')));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child:Text('अभी कोई नई सूचना नहीं है।'));
        return RefreshIndicator(
          onRefresh: () async { setState(()=>future=load()); await future; },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_,__)=>const SizedBox(height:8),
            itemBuilder: (context,index) {
              final item=items[index];
              return Card(child:ListTile(
                leading:const CircleAvatar(backgroundColor:Color(0xFFECE2C9),child:Icon(Icons.notifications_active_outlined,color:Color(0xFF174A3E))),
                title:Text((item['title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
                subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Text((item['message']??'').toString())),
              ));
            },
          ),
        );
      },
    ),
  );
}

// App Brand - uses the logo already uploaded in assets/images.
class BrandMark extends StatelessWidget {
  final bool dark;
  const BrandMark({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/karmkrite_logo.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.temple_hindu_rounded,
              color: Color(0xFF79502B),
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'KARMKRITE',
          style: TextStyle(
            color: dark ? const Color(0xFFFFE7B0) : const Color(0xFF173E34),
            fontWeight: FontWeight.w900,
            fontSize: 19,
            letterSpacing: 1.25,
          ),
        ),
      ],
    );
  }
}

// Information Dialog
void showInfo(
  BuildContext context,
  String title,
  String message,
) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFFFFFBF3),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ठीक है'),
          ),
        ],
      );
    },
  );
}
class HomeBanners extends StatelessWidget {
  const HomeBanners({super.key});

  Future<List<Map<String, dynamic>>> getBanners() async {
    final data = await Supabase.instance.client
        .from('banners')
        .select('id,title,image_url,link_url')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: getBanners(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 10,
          );
        }

        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final banners = snapshot.data!;

        return SizedBox(
          height: 165,
          child: PageView.builder(
            itemCount: banners.length,
            controller: PageController(viewportFraction: 0.92),
            itemBuilder: (context, index) {
              final banner = banners[index];

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      banner['image_url'] ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(
                        child: Text('Banner Image उपलब्ध नहीं है'),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Text(
                        banner['title'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
