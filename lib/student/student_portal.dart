import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _studentMaroon = Color(0xFF681D24);
const _studentDeep = Color(0xFF421219);
const _studentGold = Color(0xFFC69A43);
const _studentGoldLight = Color(0xFFE5C77E);
const _studentSand = Color(0xFFF4EBDD);
const _studentMuted = Color(0xFF817565);

class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({super.key});
  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@') || password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('सही ईमेल और कम-से-कम 8 अक्षर का पासवर्ड भरें।')));
      return;
    }
    if (_register && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('अपना पूरा नाम भरें।')));
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(email: email, password: password,
          data: {'full_name': _name.text.trim(), 'account_type': 'student'});
        if (result.session == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('पंजीकरण अनुरोध सफल। ईमेल सत्यापन के बाद लॉगिन करें।'),
              duration: Duration(seconds: 5)));
            setState(() => _register = false);
          }
          return;
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
      if (!mounted) return;
      final user = auth.currentUser!;
      final profileName = (user.userMetadata?['full_name'] ?? _name.text.trim()).toString().trim();
      await Supabase.instance.client.from('student_profiles').upsert({
        'user_id': user.id,
        'email': (user.email ?? email).toLowerCase(),
        'full_name': profileName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const StudentDashboardScreen()));
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('लॉगिन नहीं हो सका: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF171214) : _studentSand,
      appBar: AppBar(title: const Text('विद्यार्थी प्रवेश'),
        backgroundColor: _studentDeep, foregroundColor: _studentGoldLight, elevation: 0),
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF241B1D) : const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _studentGold.withOpacity(.45)),
              boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 24, offset: Offset(0, 10))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 66, height: 66, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _studentDeep,
                  border: Border.all(color: _studentGold, width: 1.4)),
                child: const Text('ॐ', style: TextStyle(color: _studentGoldLight, fontSize: 36))),
              const SizedBox(height: 16),
              const Text('KARMKRITE', textAlign: TextAlign.center,
                style: TextStyle(color: _studentMaroon, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 20)),
              const SizedBox(height: 5),
              Text(_register ? 'अपना विद्यार्थी खाता बनाएँ' : 'अपनी शिक्षा जारी रखें',
                textAlign: TextAlign.center,
                style: TextStyle(color: dark ? _studentGoldLight : _studentMuted, fontSize: 13)),
              const SizedBox(height: 24),
              if (_register) ...[
                TextField(controller: _name, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'पूरा नाम', prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 13),
              ],
              TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'ईमेल पता', prefixIcon: Icon(Icons.email_outlined))),
              const SizedBox(height: 13),
              TextField(controller: _password, obscureText: _hidePassword,
                autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: 'पासवर्ड', prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
              const SizedBox(height: 20),
              SizedBox(height: 50, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _studentMaroon,
                  foregroundColor: _studentGoldLight, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: _busy ? null : _submit,
                child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _studentGoldLight))
                  : Text(_register ? 'खाता बनाएँ' : 'लॉगिन करें', style: const TextStyle(fontWeight: FontWeight.w800)))),
              const SizedBox(height: 12),
              TextButton(onPressed: _busy ? null : () => setState(() => _register = !_register),
                child: Text(_register ? 'पहले से खाता है? लॉगिन करें' : 'नए विद्यार्थी हैं? पंजीकरण करें',
                  style: const TextStyle(color: _studentMaroon, fontWeight: FontWeight.w700))),
              const SizedBox(height: 6),
              const Text('कोर्स में प्रवेश Admin द्वारा Enrollment के बाद मिलेगा।',
                textAlign: TextAlign.center, style: TextStyle(color: _studentMuted, fontSize: 11)),
            ]),
          ),
        ),
      )),
    );
  }
}

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});
  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  late Future<Map<String, dynamic>> _dataFuture;
  final _db = Supabase.instance.client;
  String get _uid => _db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final enrollments = await _db.from('student_enrollments')
      .select('course_id,enrolled_at,status')
      .eq('student_id', _uid).eq('status', 'active')
      .order('enrolled_at', ascending: false);
    final enrollmentRows = List<Map<String, dynamic>>.from(enrollments);
    final ids = enrollmentRows.map((e) => e['course_id'].toString()).toList();
    if (ids.isEmpty) {
      return {'courses': <Map<String, dynamic>>[], 'progress': <String>{}, 'sessions': <Map<String, dynamic>>[]};
    }

    final results = await Future.wait([
      _db.from('courses').select('id,title,description,academy,level,thumbnail_url').inFilter('id', ids),
      _db.from('lesson_progress').select('lesson_id,course_id,completed_at').eq('student_id', _uid),
      _db.from('class_sessions').select('id,course_id,title,starts_at,ends_at,meeting_url,status')
        .inFilter('course_id', ids).gte('starts_at', DateTime.now().toUtc().toIso8601String()).order('starts_at'),
    ]);
    final courses = List<Map<String, dynamic>>.from(results[0]);
    final progressRows = List<Map<String, dynamic>>.from(results[1]);
    final progress = progressRows.map((p) => p['lesson_id'].toString()).toSet();
    final sessions = List<Map<String, dynamic>>.from(results[2]);

    final lessonGroups = await Future.wait(courses.map((course) async {
      final lessons = await _db.from('course_lessons')
        .select('id,title,description,lesson_type,media_url,duration_minutes,sort_order')
        .eq('course_id', course['id']).eq('is_published', true).order('sort_order');
      return {'course_id': course['id'], 'lessons': List<Map<String, dynamic>>.from(lessons)};
    }));
    final lessonsByCourse = <String, List<Map<String, dynamic>>>{};
    for (final group in lessonGroups) {
      lessonsByCourse[group['course_id'].toString()] = group['lessons'] as List<Map<String, dynamic>>;
    }
    for (final course in courses) {
      final lessons = lessonsByCourse[course['id'].toString()] ?? <Map<String, dynamic>>[];
      course['lessons'] = lessons;
      course['completed_count'] = lessons.where((l) => progress.contains(l['id'].toString())).length;
    }
    return {'courses': courses, 'progress': progress, 'sessions': sessions};
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() => _dataFuture = future);
    await future;
  }

  Future<void> _toggleLesson(Map<String, dynamic> course, Map<String, dynamic> lesson, bool completed) async {
    try {
      if (completed) {
        await _db.from('lesson_progress').delete()
          .eq('student_id', _uid).eq('lesson_id', lesson['id']);
      } else {
        await _db.from('lesson_progress').insert({
          'student_id': _uid, 'course_id': course['id'], 'lesson_id': lesson['id']});
      }
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('प्रगति अपडेट नहीं हुई: $e')));
    }
  }

  Future<void> _openLesson(Map<String, dynamic> course, Map<String, dynamic> lesson, bool completed) async {
    final type = (lesson['lesson_type'] ?? 'video').toString();
    final url = (lesson['media_url'] ?? '').toString().trim();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 4,
            decoration: BoxDecoration(color: _studentGold, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          Text((lesson['title'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text((lesson['description'] ?? '').toString(), style: const TextStyle(color: _studentMuted, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            Chip(label: Text(type.toUpperCase())),
            Chip(label: Text('${lesson['duration_minutes'] ?? 0} मिनट')),
          ]),
          const SizedBox(height: 14),
          if (url.isNotEmpty) SizedBox(width: double.infinity, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _studentMaroon, foregroundColor: _studentGoldLight),
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('यह Media URL मान्य नहीं है।')));
                return;
              }
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('लिंक नहीं खुल सका।')));
            },
            icon: Icon(type == 'pdf' ? Icons.picture_as_pdf : type == 'audio' ? Icons.headphones : Icons.play_circle),
            label: Text(type == 'pdf' ? 'PDF खोलें' : type == 'audio' ? 'Audio सुनें' : 'कक्षा देखें'))),
          if (url.isEmpty) const Text('इस पाठ की सामग्री अभी उपलब्ध नहीं कराई गई है।', style: TextStyle(color: _studentMuted)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              _toggleLesson(course, lesson, completed);
            },
            icon: Icon(completed ? Icons.undo_rounded : Icons.check_circle_outline),
            label: Text(completed ? 'पूर्ण चिह्न हटाएँ' : 'पाठ पूर्ण हुआ चिह्नित करें'))),
        ]),
      )),
    );
  }

  Future<void> _logout() async {
    await _db.auth.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF171214) : _studentSand,
      appBar: AppBar(backgroundColor: _studentDeep, foregroundColor: _studentGoldLight, elevation: 0,
        title: const Text('विद्यार्थी डैशबोर्ड', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'लॉगआउट', onPressed: _logout, icon: const Icon(Icons.logout)),
        ]),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _studentGold));
          }
          if (snapshot.hasError) return _message('जानकारी लोड नहीं हो सकी।\n${snapshot.error}', _refresh);
          final data = snapshot.data ?? {};
          final courses = List<Map<String, dynamic>>.from(data['courses'] ?? []);
          final progress = Set<String>.from(data['progress'] ?? <String>{});
          final sessions = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
          final total = courses.fold<int>(0, (sum, c) => sum + (c['lessons'] as List).length);
          final done = progress.length;
          final pct = total == 0 ? 0 : (done * 100 ~/ total);
          return RefreshIndicator(color: _studentGold, onRefresh: _refresh,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30), children: [
              Container(padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_studentDeep, _studentMaroon, Color(0xFF873640)]),
                  borderRadius: BorderRadius.circular(24), border: Border.all(color: _studentGold.withOpacity(.7))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('स्वाध्याय की ओर आपका अगला कदम',
                    style: TextStyle(color: _studentGoldLight, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .7)),
                  const SizedBox(height: 8),
                  Text(_db.auth.currentUser?.userMetadata?['full_name']?.toString() ??
                    _db.auth.currentUser?.email ?? 'विद्यार्थी',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _stat('कोर्स', courses.length.toString()),
                    const SizedBox(width: 10), _stat('पूर्ण पाठ', done.toString()),
                    const SizedBox(width: 10), _stat('प्रगति', '$pct%'),
                  ]),
                  const SizedBox(height: 14),
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: total == 0 ? 0 : done / total,
                      minHeight: 7, backgroundColor: Colors.white24, color: _studentGoldLight)),
                ])),
              const SizedBox(height: 22),
              _sectionTitle('मेरे कोर्स', 'YOUR LEARNING'),
              if (courses.isEmpty) _emptyCourses(),
              ...courses.map((course) => _courseCard(course, progress)),
              const SizedBox(height: 22),
              _sectionTitle('आगामी लाइव कक्षाएँ', 'UPCOMING LIVE CLASSES'),
              if (sessions.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('अभी कोई आगामी Live Class निर्धारित नहीं है।', style: TextStyle(color: _studentMuted))),
              ...sessions.map((session) => _sessionCard(session, courses)),
            ]),
          );
        },
      ),
    );
  }

  Widget _message(String text, VoidCallback retry) => Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_rounded, size: 42, color: _studentMaroon),
      const SizedBox(height: 12), Text(text, textAlign: TextAlign.center),
      const SizedBox(height: 14), ElevatedButton(onPressed: retry, child: const Text('दोबारा प्रयास करें')),
    ])));

  Widget _stat(String label, String value) => Expanded(child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.09), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: _studentGoldLight, fontWeight: FontWeight.w900, fontSize: 20)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ])));

  Widget _sectionTitle(String title, String overline) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(overline, style: const TextStyle(color: _studentGold, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
    const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
  ]);

  Widget _emptyCourses() => Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _studentGold.withOpacity(.4))),
    child: const Column(children: [
      Icon(Icons.menu_book_rounded, size: 38, color: _studentGold), SizedBox(height: 10),
      Text('आपके खाते में अभी कोई कोर्स नहीं है।', style: TextStyle(fontWeight: FontWeight.w800)),
      SizedBox(height: 5),
      Text('कोर्स में प्रवेश के लिए KARMKRITE Admin से संपर्क करें।',
        textAlign: TextAlign.center, style: TextStyle(color: _studentMuted, fontSize: 12)),
    ]));

  Widget _courseCard(Map<String, dynamic> course, Set<String> progress) {
    final lessons = List<Map<String, dynamic>>.from(course['lessons'] ?? []);
    final done = lessons.where((l) => progress.contains(l['id'].toString())).length;
    final ratio = lessons.isEmpty ? 0.0 : done / lessons.length;
    final academy = {
      'jyotish': 'JYOTISH ACADEMY',
      'karmkand': 'KARMKAND ACADEMY',
      'vedic': 'VEDIC ACADEMY',
    }[course['academy']] ?? 'KARMKRITE ACADEMY';
    return Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _studentGold.withOpacity(.32)),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(academy, style: const TextStyle(color: _studentGold, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5), Text(course['title']?.toString() ?? '',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        if ((course['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 5), Text(course['description'].toString(), maxLines: 2,
            overflow: TextOverflow.ellipsis, style: const TextStyle(color: _studentMuted, fontSize: 11, height: 1.4)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: _studentSand, color: _studentMaroon))),
          const SizedBox(width: 10),
          Text('$done / ${lessons.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        if (lessons.isEmpty) const Text('इस कोर्स के पाठ शीघ्र उपलब्ध होंगे।', style: TextStyle(color: _studentMuted, fontSize: 11)),
        ...lessons.map((lesson) {
          final complete = progress.contains(lesson['id'].toString());
          final type = lesson['lesson_type']?.toString() ?? 'video';
          return ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: Icon(complete ? Icons.check_circle : type == 'pdf' ? Icons.picture_as_pdf_outlined :
              type == 'audio' ? Icons.headphones_rounded : type == 'article' ? Icons.article_outlined : Icons.play_circle_outline,
              color: complete ? Colors.green : _studentMaroon),
            title: Text(lesson['title']?.toString() ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text('$type • ${lesson['duration_minutes'] ?? 0} मिनट',
              style: const TextStyle(fontSize: 10, color: _studentMuted)),
            trailing: const Icon(Icons.chevron_right_rounded, color: _studentGold),
            onTap: () => _openLesson(course, lesson, complete),
          );
        }),
      ]));
  }

  Widget _sessionCard(Map<String, dynamic> session, List<Map<String, dynamic>> courses) {
    final matching = courses.where((c) => c['id'] == session['course_id']);
    final course = matching.isEmpty ? null : matching.first;
    final start = DateTime.tryParse(session['starts_at']?.toString() ?? '')?.toLocal();
    final date = start == null ? 'समय निर्धारित नहीं' :
      '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year} • ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final url = (session['meeting_url'] ?? '').toString();
    return Card(color: Theme.of(context).colorScheme.surface, margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _studentGold.withOpacity(.35))),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: _studentDeep,
          child: Icon(Icons.video_camera_front_rounded, color: _studentGoldLight)),
        title: Text(session['title']?.toString() ?? 'Live Class',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        subtitle: Text('${course?['title'] ?? 'Course'}\n$date',
          style: const TextStyle(fontSize: 10, color: _studentMuted)),
        isThreeLine: true,
        trailing: IconButton(tooltip: 'कक्षा में जाएँ', onPressed: url.isEmpty ? null : () async {
          final uri = Uri.tryParse(url);
          if (uri != null && {'http', 'https'}.contains(uri.scheme)) {
            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Meeting link नहीं खुला।')));
          }
        }, icon: const Icon(Icons.open_in_new, color: _studentMaroon)),
      ));
  }
}
