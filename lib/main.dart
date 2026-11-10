
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
        scaffoldBackgroundColor: const Color(0xFFFFFBF3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF79502B),
          primary: const Color(0xFF79502B),
          secondary: const Color(0xFFD5A34B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFBF3),
          foregroundColor: Color(0xFF563719),
          elevation: 0,
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
      'practice': 'अभ्यास',
      'saved': 'सहेजे गए',
      'profile': 'प्रोफाइल',
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
      'practice': 'अभ्यासः',
      'saved': 'संगृहीतम्',
      'profile': 'परिचयः',
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
      'practice': 'Practice',
      'saved': 'Saved',
      'profile': 'Profile',
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
    title: 'पंचांग एवं मुहूर्त',
    subtitle: 'तिथि, नक्षत्र एवं शुभ समय',
    icon: '🌞',
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
  try {
    final response = await Supabase.instance.client
        .from('categories')
        .select('id, name_hi, name_en, description, icon')
        .eq('is_active', true)
        .order('sort_order').order('created_at');

    final rows = response as List;

    const iconMap = {
      'book': '📚',
      'temple': '🪔',
      'om': '🕉️',
      'flower': '🙏',
      'calendar': '🌞',
      'headphones': '🎧',
    };

    return rows.map((row) {
      final hindiName =
          (row['name_hi'] ?? '').toString();

      final englishName =
          (row['name_en'] ?? hindiName).toString();

      final template = modules.firstWhere(
        (module) => module.title == hindiName,
        orElse: () => ModuleInfo(
          id: '',
          title: hindiName,
          subtitle: '',
          icon: '📖',
          items: const [],
        ),
      );

      final iconName = (row['icon'] ?? '').toString();

      return ModuleInfo(
        id: row['id'].toString(),
        title: language == 'en' ? englishName : hindiName,
        subtitle: (row['description'] ?? template.subtitle).toString(),
        icon: iconMap[iconName] ?? template.icon,
        items: const [],
      );
    }).toList();
  } catch (error, stackTrace) {
    debugPrint('KARMKRITE DATABASE ERROR: $error');
    debugPrint('$stackTrace');
    rethrow;
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
      appBar: AppBar(
        title: const BrandMark(),
        actions: [
          IconButton(
            tooltip: tr('notifications'),
            onPressed: () => showInfo(
              context,
              tr('notifications'),
              'नई सूचनाएँ शीघ्र उपलब्ध होंगी।',
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
      ),
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
            icon: const Icon(Icons.self_improvement_outlined),
            label: tr('practice'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_border_rounded),
            label: tr('saved'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            label: tr('profile'),
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
                const SizedBox(height: 12),
                const HomeBanners(),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (value) {
                    setState(() => searchText = value);
                  },
                  decoration: InputDecoration(
                    hintText: tr('search'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('modules'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF563719),
                  ),
                ),
                const SizedBox(height: 12),
                if (filteredModules.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('कोई Category नहीं मिली।'),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredModules.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.12,
                    ),
                    itemBuilder: (context, index) {
                      final module = filteredModules[index];

                      return ModuleCard(
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6B4528),
            Color(0xFF9B7042),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '॥ ॐ ॥',
            style: TextStyle(
              fontSize: 28,
              color: Color(0xFFFFD88A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('welcome'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'भारतीय ज्ञान, वैदिक परंपरा और संस्कारों का डिजिटल मंच।',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
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
            ],
          ),
        );
      },
    );
  }

  Widget _otherTabBody() {
    switch (selectedTab) {
      case 1: return BooksScreen(language: widget.language);
      case 2: return PracticeScreen(language: widget.language);
      case 3: return SavedScreen(language: widget.language);
      case 4: return ProfileScreen(language: widget.language, onLanguageChanged: widget.onLanguageChanged);
      default: return _homeBody();
    }
  }
}

// Category Card
class ModuleCard extends StatelessWidget {
  final ModuleInfo module;
  final VoidCallback onTap;

  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFEADCC8)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                module.icon,
                style: const TextStyle(fontSize: 30),
              ),
              const SizedBox(height: 10),
              Text(
                module.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF563719),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                module.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
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
    final response = await Supabase.instance.client
        .from('content_items')
        .select(
          'id, title, title_hi, title_en, description, body, type',
        )
        .eq('category_id', widget.module.id)
        .eq('is_active', true)
        .order('created_at');

    return List<Map<String, dynamic>>.from(response);
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
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0D5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Text(
                  widget.module.icon,
                  style: const TextStyle(fontSize: 42),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.module.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(widget.module.subtitle),
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

                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const
                          Color(0xFFFFF0D5),
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          getTitle(item),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          (item['description'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                        ),
                        onTap: () => openContent(item),
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
class SavedStore {
  static const key = 'saved_content_items';
  static Future<List<Map<String,dynamic>>> read() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(key) ?? []).map((x) {
      try { return Map<String,dynamic>.from(jsonDecode(x)); } catch (_) { return <String,dynamic>{}; }
    }).where((x) => x.isNotEmpty).toList();
  }
  static Future<bool> has(String title) async => (await read()).any((x) => x['title'] == title);
  static Future<void> toggle(Map<String,dynamic> item) async {
    final p = await SharedPreferences.getInstance();
    final all = await read();
    all.removeWhere((x) => x['title'] == item['title']);
    if (item['_remove'] != true) all.insert(0, item);
    await p.setStringList(key, all.map(jsonEncode).toList());
  }
}

class ContentDetailScreen extends StatefulWidget {
  final String title, content, description;
  const ContentDetailScreen({super.key, required this.title, required this.content, required this.description});
  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}
class _ContentDetailScreenState extends State<ContentDetailScreen> {
  bool saved = false;
  @override
  void initState() { super.initState(); SavedStore.has(widget.title).then((v) { if (mounted) setState(() => saved = v); }); }
  Future<void> toggle() async {
    await SavedStore.toggle({'title':widget.title,'body':widget.content,'description':widget.description,'_remove':saved});
    if (!mounted) return;
    setState(() => saved = !saved);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? 'सहेज दिया गया।' : 'सहेजी गई सामग्री से हटाया गया।')));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [IconButton(onPressed: toggle, icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border))]),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.title, style: const TextStyle(fontSize:23,fontWeight:FontWeight.bold,color:Color(0xFF563719))),
      if (widget.description.isNotEmpty) ...[const SizedBox(height:12), Text(widget.description,style:const TextStyle(fontSize:16,color:Colors.black54))],
      const SizedBox(height:20),
      SelectableText(widget.content.isEmpty ? 'इस विषय की विस्तृत सामग्री शीघ्र उपलब्ध होगी।' : widget.content,style:const TextStyle(fontSize:17,height:1.8))
    ]))
  );
}

class BooksScreen extends StatefulWidget {
  final String language;
  const BooksScreen({super.key,required this.language});
  @override
  State<BooksScreen> createState()=>_BooksScreenState();
}
class _BooksScreenState extends State<BooksScreen> {
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState(){super.initState();future=load();}
  Future<List<Map<String,dynamic>>> load() async {
    final rows=await Supabase.instance.client.from('books')
      .select('id,title_hi,title_en,author,description,cover_url,book_versions(pdf_url,version_no)')
      .eq('is_active',true).order('created_at',ascending:false);
    return List<Map<String,dynamic>>.from(rows);
  }
  Future<void> openBook(Map<String,dynamic> b) async {
    final versions=List<Map<String,dynamic>>.from(b['book_versions']??[]);
    versions.sort((a,b)=>((b['version_no']??0) as num).compareTo((a['version_no']??0) as num));
    final url=versions.isEmpty?'':(versions.first['pdf_url']??'').toString();
    final uri=Uri.tryParse(url);
    if(uri==null || url.isEmpty || !await launchUrl(uri,mode:LaunchMode.externalApplication)){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('इस पुस्तक की PDF अभी उपलब्ध नहीं है।')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final en=widget.language=='en';
    return Scaffold(appBar:AppBar(title:Text(en?'Digital Library':'डिजिटल पुस्तकालय')),
      body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){
        if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('पुस्तकें लोड नहीं हो सकीं।'),ElevatedButton(onPressed:()=>setState(()=>future=load()),child:const Text('पुनः प्रयास करें'))]));
        final books=s.data??[];
        if(books.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('मास्टर एडमिन से जोड़ी गई पुस्तकें यहाँ दिखाई देंगी।',textAlign:TextAlign.center)));
        return RefreshIndicator(onRefresh:()async=>setState(()=>future=load()),child:ListView.builder(padding:const EdgeInsets.all(14),itemCount:books.length,itemBuilder:(context,i){
          final b=books[i]; final title=(en?b['title_en']:b['title_hi'])??b['title_hi']??'';
          return Card(child:ListTile(leading:const Icon(Icons.menu_book_rounded,color:Color(0xFF79502B),size:32),
            title:Text(title.toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
            subtitle:Text([b['author'],b['description']].where((x)=>x!=null&&x.toString().isNotEmpty).join(' • '),maxLines:2,overflow:TextOverflow.ellipsis),
            trailing:const Icon(Icons.picture_as_pdf),onTap:()=>openBook(b)));
        }));
      }));
  }
}

class PracticeScreen extends StatefulWidget {
  final String language;
  const PracticeScreen({super.key,required this.language});
  @override
  State<PracticeScreen> createState()=>_PracticeScreenState();
}
class _PracticeScreenState extends State<PracticeScreen> {
  int question=0, score=0; int? selected; bool answered=false;
  final data=<Map<String,dynamic>>[
    {'q':'“सत्यं वद” का अर्थ क्या है?','a':['सत्य बोलो','दान करो','मौन रहो','यात्रा करो'],'c':0,'e':'तैत्तिरीय उपनिषद् की शिक्षा है—सत्य बोलो।'},
    {'q':'गायत्री मंत्र ऋग्वेद के किस मंडल में है?','a':['प्रथम','तृतीय','सप्तम','दशम'],'c':1,'e':'गायत्री मंत्र ऋग्वेद के तृतीय मंडल में मिलता है।'},
    {'q':'“धर्मं चर” का अर्थ क्या है?','a':['धर्म का आचरण करो','केवल पढ़ो','मौन रहो','यात्रा करो'],'c':0,'e':'इसका आशय धर्मानुसार आचरण करना है।'}
  ];
  void answer(int i){if(answered)return;setState((){selected=i;answered=true;if(i==data[question]['c'])score++;});}
  void next(){setState((){if(question<data.length-1){question++;}else{question=0;score=0;}selected=null;answered=false;});}
  @override
  Widget build(BuildContext context){
    final q=data[question];final c=q['c'] as int;
    return Scaffold(appBar:AppBar(title:Text(widget.language=='en'?'Daily Practice':'दैनिक अभ्यास')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFFFFF0D5),borderRadius:BorderRadius.circular(18)),
          child:Text('प्रश्न ' + (question+1).toString() + ' / ' + data.length.toString() + '     •     सही उत्तर: ' + score.toString(),style:const TextStyle(fontWeight:FontWeight.bold))),
        const SizedBox(height:22),Text(q['q'],style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:14),
        ...List.generate((q['a'] as List).length,(i)=>Card(color:answered&&i==c?const Color(0xFFE5F3E5):answered&&i==selected?const Color(0xFFFFE6E6):Colors.white,
          child:ListTile(title:Text(q['a'][i]),trailing:answered&&i==c?const Icon(Icons.check_circle,color:Colors.green):null,onTap:()=>answer(i)))),
        if(answered)...[const SizedBox(height:10),Text(selected==c?'सही उत्तर!':'सही उत्तर: ' + q['a'][c],style:const TextStyle(fontWeight:FontWeight.bold)),Text(q['e']),const SizedBox(height:12),ElevatedButton(onPressed:next,child:Text(question==data.length-1?'फिर से अभ्यास करें':'अगला प्रश्न'))]
      ]));
  }
}

class SavedScreen extends StatefulWidget {
  final String language;
  const SavedScreen({super.key,required this.language});
  @override
  State<SavedScreen> createState()=>_SavedScreenState();
}
class _SavedScreenState extends State<SavedScreen>{
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState(){super.initState();future=SavedStore.read();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.language=='en'?'Saved Items':'सहेजी गई सामग्री')),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){
      if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      final items=s.data??[];
      if(items.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('लेख पर बुकमार्क दबाएँ, वह यहाँ दिखाई देगा।',textAlign:TextAlign.center)));
      return ListView.builder(padding:const EdgeInsets.all(14),itemCount:items.length,itemBuilder:(context,i){final x=items[i];return Card(child:ListTile(
        leading:const Icon(Icons.bookmark,color:Color(0xFF79502B)),title:Text(x['title']??''),subtitle:Text(x['description']??'',maxLines:2,overflow:TextOverflow.ellipsis),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ContentDetailScreen(title:x['title']??'',content:x['body']??'',description:x['description']??''))).then((_){setState(()=>future=SavedStore.read());}),
        trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{await SavedStore.toggle({...x,'_remove':true});setState(()=>future=SavedStore.read());})));});
    }));
}

class ProfileScreen extends StatelessWidget {
  final String language; final ValueChanged<String> onLanguageChanged;
  const ProfileScreen({super.key,required this.language,required this.onLanguageChanged});
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(language=='en'?'Profile & Settings':'प्रोफाइल एवं सेटिंग्स')),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      const SizedBox(height:12),const Center(child:BrandMark()),const Center(child:Text('शास्त्र से संस्कार तक')),
      const SizedBox(height:24),const Text('ऐप की भाषा',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
      Card(child:Column(children:[
        RadioListTile<String>(value:'hi',groupValue:language,title:const Text('हिंदी'),onChanged:(v){if(v!=null)onLanguageChanged(v);}),
        RadioListTile<String>(value:'sa',groupValue:language,title:const Text('संस्कृत'),onChanged:(v){if(v!=null)onLanguageChanged(v);}),
        RadioListTile<String>(value:'en',groupValue:language,title:const Text('English'),onChanged:(v){if(v!=null)onLanguageChanged(v);})
      ])),
      const ListTile(leading:Icon(Icons.info_outline),title:Text('KARMKRITE'),subtitle:Text('वैदिक ज्ञान, शास्त्र एवं संस्कारों का डिजिटल मंच।')),
      const ListTile(leading:Icon(Icons.verified_outlined),title:Text('संस्करण'),subtitle:Text('1.0.0'))
    ]));
}

// App Brand - uses the logo already uploaded in assets/images.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/karmkrite logo.png.jpg',
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
        const Text(
          'KARMKRITE',
          style: TextStyle(
            color: Color(0xFF563719),
            fontWeight: FontWeight.bold,
            fontSize: 19,
            letterSpacing: 1,
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
