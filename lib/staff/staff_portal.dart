
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/karmkrite_theme.dart';

class StaffPortalScreen extends StatefulWidget {
  const StaffPortalScreen({super.key});
  @override
  State<StaffPortalScreen> createState() => _StaffPortalScreenState();
}

class _StaffPortalScreenState extends State<StaffPortalScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false, hidePassword = true;
  String? error, role;

  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentUser != null) verifyRole();
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> verifyRole() async {
    setState(() { busy = true; error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('कृपया Staff Login करें।');
      final row = await Supabase.instance.client.from('admin_users')
          .select('role,is_active').eq('id', user.id).maybeSingle();
      if (row == null || row['is_active'] != true) {
        await Supabase.instance.client.auth.signOut();
        throw Exception('इस खाते को Staff Portal की अनुमति नहीं है।');
      }
      final value = (row['role'] ?? '').toString();
      if (!['super_admin','admin','teacher'].contains(value)) {
        await Supabase.instance.client.auth.signOut();
        throw Exception('इस खाते की भूमिका मान्य नहीं है।');
      }
      if (mounted) setState(() => role = value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'ईमेल और पासवर्ड दोनों भरें।'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email.text.trim(), password: password.text);
      await verifyRole();
    } catch (_) {
      if (mounted) setState(() => error = 'लॉगिन नहीं हो सका। ईमेल और पासवर्ड जाँचें।');
      if (Supabase.instance.client.auth.currentUser != null) {
        await Supabase.instance.client.auth.signOut();
      }
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) setState(() { role = null; error = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (role == 'super_admin' || role == 'admin') {
      return AdminDashboardScreen(role: role!, onLogout: logout);
    }
    if (role == 'teacher') return TeacherDashboardScreen(onLogout: logout);
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Portal')),
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(child: Padding(padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 60, height: 60, alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [KarmKritePalette.maroonDeep, KarmKritePalette.maroon]),
                  borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.admin_panel_settings_rounded, color: KarmKritePalette.goldLight, size: 30)),
              const SizedBox(height: 18),
              const Text('KARMKRITE STAFF', style: TextStyle(
                color: KarmKritePalette.gold, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              const Text('प्रबंधन पोर्टल में प्रवेश करें', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 18),
              TextField(controller: email, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Staff Email', prefixIcon: Icon(Icons.mail_outline_rounded))),
              const SizedBox(height: 12),
              TextField(controller: password, obscureText: hidePassword,
                decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(onPressed: () => setState(() => hidePassword = !hidePassword),
                    icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              SizedBox(height: 50, child: ElevatedButton(
                onPressed: busy ? null : login,
                child: busy ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))
                  : const Text('सुरक्षित लॉगिन करें'))),
              const SizedBox(height: 12),
              const Text('प्रवेश अधिकार डेटाबेस में सत्यापित होते हैं।',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          )),
        ),
      )),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  final String role;
  final Future<void> Function() onLogout;
  const AdminDashboardScreen({super.key, required this.role, required this.onLogout});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}
class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<Map<String,dynamic>> dataFuture;
  @override
  void initState() { super.initState(); dataFuture = loadData(); }
  Future<Map<String,dynamic>> loadData() async {
    final db = Supabase.instance.client;
    final rows = await Future.wait([
      db.from('courses').select('id,title,academy,level,is_published,created_at').order('created_at', ascending:false),
      db.from('admin_users').select('id,email,role,is_active').order('created_at', ascending:false),
      db.from('student_enrollments').select('id,student_id,course_id,status,enrolled_at').order('enrolled_at', ascending:false),
      db.from('course_lessons').select('id'),
      db.from('student_profiles').select('user_id,email,full_name,created_at').order('created_at', ascending:false),
    ]);
    return {
      'courses': rows[0], 'staff': rows[1], 'enrollments': rows[2],
      'students': (rows[4] as List).length, 'lessons': (rows[3] as List).length,
    };
  }
  Future<void> refresh() async { final f=loadData(); setState(()=>dataFuture=f); await f; }
  Future<void> inviteTeacher() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final values = await showDialog<Map<String,String>>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Teacher को आमंत्रित करें'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name, textCapitalization:TextCapitalization.words,
          decoration:const InputDecoration(labelText:'शिक्षक का नाम (वैकल्पिक)')),
        const SizedBox(height:10),
        TextField(controller:email, keyboardType:TextInputType.emailAddress,
          decoration:const InputDecoration(labelText:'शिक्षक का ईमेल')),
        const SizedBox(height:8),
        const Text('शिक्षक को account setup के लिए invitation email भेजा जाएगा।',style:TextStyle(fontSize:11)),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('रद्द करें')),
        ElevatedButton(onPressed:()=>Navigator.pop(dialogContext,{
          'name':name.text.trim(),'email':email.text.trim(),
        }),child:const Text('Invitation भेजें')),
      ],
    ));
    if(values==null){name.dispose();email.dispose();return;}
    final address=values['email']??'';
    if(address.isEmpty || !address.contains('@')){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('सही ईमेल पता भरें।')));
      name.dispose();email.dispose();return;
    }
    try{
      final response=await Supabase.instance.client.functions.invoke('invite-teacher',
        body:{'email':address,'display_name':values['name']??''});
      if(response.status<200 || response.status>=300){
        final message=(response.data is Map)?(response.data['error']??'Invitation असफल रही।'):'Invitation असफल रही।';
        throw Exception(message);
      }
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$address पर शिक्षक आमंत्रण भेज दिया गया।')));
        await refresh();
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Invitation नहीं भेजी जा सकी: $e')));
    }
    name.dispose();email.dispose();
  }

  Future<void> addCourse() async {
    final title=TextEditingController(), description=TextEditingController();
    String academy='vedic', level='beginner';
    final values=await showDialog<Map<String,String>>(context:context,builder:(dialogContext)=>
      StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
        title:const Text('नया कोर्स बनाएँ'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:title,decoration:const InputDecoration(labelText:'कोर्स का नाम')),
          const SizedBox(height:10),
          TextField(controller:description,maxLines:3,decoration:const InputDecoration(labelText:'विवरण')),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(value:academy,decoration:const InputDecoration(labelText:'Academy'),
            items:const [
              DropdownMenuItem(value:'jyotish',child:Text('Jyotish Academy')),
              DropdownMenuItem(value:'karmkand',child:Text('Karmkand Academy')),
              DropdownMenuItem(value:'vedic',child:Text('Vedic Academy')),
            ],onChanged:(v)=>setDialogState(()=>academy=v??'vedic')),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(value:level,decoration:const InputDecoration(labelText:'स्तर'),
            items:const [
              DropdownMenuItem(value:'beginner',child:Text('Beginner')),
              DropdownMenuItem(value:'intermediate',child:Text('Intermediate')),
              DropdownMenuItem(value:'advanced',child:Text('Advanced')),
              DropdownMenuItem(value:'research',child:Text('Research')),
            ],onChanged:(v)=>setDialogState(()=>level=v??'beginner')),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('रद्द करें')),
          ElevatedButton(onPressed:()=>Navigator.pop(dialogContext,{
            'title':title.text.trim(),'description':description.text.trim(),'academy':academy,'level':level,
          }),child:const Text('कोर्स बनाएँ')),
        ],
      )));
    if(values==null || (values['title']??'').isEmpty){title.dispose();description.dispose();return;}
    try {
      await Supabase.instance.client.from('courses').insert({
        ...values,'created_by':Supabase.instance.client.auth.currentUser?.id,
      });
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('कोर्स बना दिया गया। अभी यह unpublished है।')));await refresh();}
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('कोर्स नहीं बन सका: $e')));
    }
    title.dispose(); description.dispose();
  }
  Future<void> assignTeacher(Map<String,dynamic> course, List<Map<String,dynamic>> staff) async {
    final teachers=staff.where((person)=>person['role']=='teacher' && person['is_active']==true).toList();
    if(teachers.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('पहले Staff Portal में Teacher account provision करें।')));
      return;
    }
    String selected=(teachers.first['id']??'').toString();
    final teacherId=await showDialog<String>(context:context,builder:(dialogContext)=>
      StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
        title:const Text('Teacher assign करें'),
        content:DropdownButtonFormField<String>(
          value:selected,decoration:const InputDecoration(labelText:'Teacher'),
          items:teachers.map((person)=>DropdownMenuItem<String>(
            value:(person['id']??'').toString(),
            child:Text((person['email']??'Teacher').toString(),overflow:TextOverflow.ellipsis),
          )).toList(),
          onChanged:(value)=>setDialogState(()=>selected=value??selected),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('रद्द करें')),
          ElevatedButton(onPressed:()=>Navigator.pop(dialogContext,selected),child:const Text('Assign करें')),
        ],
      )));
    if(teacherId==null)return;
    try{
      await Supabase.instance.client.from('teacher_course_assignments').upsert({
        'teacher_id':teacherId,'course_id':course['id'],
        'assigned_by':Supabase.instance.client.auth.currentUser?.id,
      },onConflict:'teacher_id,course_id');
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Teacher को course assign कर दिया गया।')));await refresh();}
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Assignment नहीं हो सका: $e')));
    }
  }

  Future<void> manageStudents(List<Map<String,dynamic>> courses) async {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('पहले कम-से-कम एक कोर्स बनाएँ।')));
      return;
    }
    final db = Supabase.instance.client;
    List<Map<String,dynamic>> students;
    List<Map<String,dynamic>> enrollments;
    try {
      final result = await Future.wait([
        db.from('student_profiles').select('user_id,email,full_name,created_at').order('created_at', ascending: false),
        db.from('student_enrollments').select('id,student_id,course_id,status,enrolled_at').order('enrolled_at', ascending: false),
      ]);
      students = List<Map<String,dynamic>>.from(result[0]);
      enrollments = List<Map<String,dynamic>>.from(result[1]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('विद्यार्थी सूची लोड नहीं हुई: $e')));
      return;
    }
    if (students.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('अभी किसी विद्यार्थी ने लॉगिन करके प्रोफाइल नहीं बनाई है।')));
      return;
    }
    String selectedStudent = students.first['user_id'].toString();
    String selectedCourse = courses.first['id'].toString();
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('विद्यार्थी एवं कोर्स प्रवेश'),
          content: SizedBox(
            width: 520, height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedStudent, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'विद्यार्थी चुनें'),
                  items: students.map((student) => DropdownMenuItem<String>(
                    value: student['user_id'].toString(),
                    child: Text(
                      (student['full_name']?.toString().trim().isNotEmpty == true
                        ? student['full_name'] : student['email']).toString(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: saving ? null : (value) => setDialogState(
                    () => selectedStudent = value ?? selectedStudent),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCourse, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'कोर्स चुनें'),
                  items: courses.map((course) => DropdownMenuItem<String>(
                    value: course['id'].toString(),
                    child: Text(course['title'].toString(), overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: saving ? null : (value) => setDialogState(
                    () => selectedCourse = value ?? selectedCourse),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: saving ? null : () async {
                    setDialogState(() => saving = true);
                    try {
                      await db.from('student_enrollments').upsert({
                        'student_id': selectedStudent,
                        'course_id': selectedCourse,
                        'status': 'active',
                        'enrolled_at': DateTime.now().toUtc().toIso8601String(),
                      }, onConflict: 'student_id,course_id');
                      final refreshed = await db.from('student_enrollments')
                        .select('id,student_id,course_id,status,enrolled_at')
                        .order('enrolled_at', ascending: false);
                      enrollments = List<Map<String,dynamic>>.from(refreshed);
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('विद्यार्थी को कोर्स में प्रवेश दे दिया गया।')));
                        await refresh();
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Enrollment नहीं हो सका: $e')));
                    } finally {
                      setDialogState(() => saving = false);
                    }
                  },
                  icon: saving
                    ? const SizedBox(width: 16,height: 16,child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('कोर्स में प्रवेश दें'),
                ),
                const Divider(height: 24),
                const Text('विद्यार्थी सूची', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final student = students[index];
                      final id = student['user_id'].toString();
                      final studentEnrollments = enrollments.where(
                        (entry) => entry['student_id'].toString() == id).toList();
                      final active = studentEnrollments.where(
                        (entry) => entry['status'] == 'active').toList();
                      final name = (student['full_name'] ?? '').toString().trim();
                      return ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(name.isEmpty ? student['email'].toString() : name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        subtitle: Text('\${student['email']} • \${active.length} सक्रिय कोर्स',
                          style: const TextStyle(fontSize: 10)),
                        children: [
                          if (studentEnrollments.isEmpty)
                            const ListTile(dense: true,title: Text('अभी कोई कोर्स नहीं दिया गया।'))
                          else ...studentEnrollments.map((entry) {
                            final course = courses.where(
                              (item) => item['id'].toString() == entry['course_id'].toString());
                            final courseName = course.isEmpty ? 'कोर्स' : course.first['title'].toString();
                            final isActive = entry['status'] == 'active';
                            return ListTile(
                              dense: true,
                              title: Text(courseName, style: const TextStyle(fontSize: 12)),
                              subtitle: Text(entry['status'].toString()),
                              trailing: isActive ? IconButton(
                                tooltip: 'प्रवेश रद्द करें',
                                icon: const Icon(Icons.remove_circle_outline,color: Colors.redAccent),
                                onPressed: () async {
                                  try {
                                    await db.from('student_enrollments')
                                      .update({'status':'cancelled'}).eq('id',entry['id']);
                                    final refreshed = await db.from('student_enrollments')
                                      .select('id,student_id,course_id,status,enrolled_at')
                                      .order('enrolled_at', ascending: false);
                                    setDialogState(() => enrollments =
                                      List<Map<String,dynamic>>.from(refreshed));
                                    if (mounted) await refresh();
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(content: Text('प्रवेश रद्द नहीं हुआ: $e')));
                                  }
                                },
                              ) : null,
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('बंद करें')),
          ],
        ),
      ),
    );
  }

  Future<bool> addLesson(Map<String,dynamic> course) async {
    final title=TextEditingController(), description=TextEditingController(), media=TextEditingController();
    final duration=TextEditingController(text:'0');
    String type='video';
    final values=await showDialog<Map<String,String>>(context:context,builder:(dialogContext)=>
      StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
        title:const Text('नया पाठ जोड़ें'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:title,decoration:const InputDecoration(labelText:'पाठ का शीर्षक')),
          const SizedBox(height:8),
          TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'विवरण')),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'सामग्री का प्रकार'),
            items:const [
              DropdownMenuItem(value:'video',child:Text('Video')),
              DropdownMenuItem(value:'pdf',child:Text('PDF / पुस्तक')),
              DropdownMenuItem(value:'audio',child:Text('Audio / मंत्र')),
              DropdownMenuItem(value:'article',child:Text('Text Lesson')),
            ],onChanged:(v)=>setDialogState(()=>type=v??'video')),
          const SizedBox(height:8),
          TextField(controller:media,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Media URL (वैकल्पिक)')),
          const SizedBox(height:8),
          TextField(controller:duration,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'अवधि (मिनट)')),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('रद्द करें')),
          ElevatedButton(onPressed:()=>Navigator.pop(dialogContext,{
            'title':title.text.trim(),'description':description.text.trim(),'lesson_type':type,
            'media_url':media.text.trim(),'duration':duration.text.trim(),
          }),child:const Text('पाठ सेव करें')),
        ],
      )));
    if(values==null){title.dispose();description.dispose();media.dispose();duration.dispose();return false;}
    if((values['title']??'').isEmpty){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('पाठ का शीर्षक आवश्यक है।')));
      title.dispose();description.dispose();media.dispose();duration.dispose();return false;
    }
    try{
      final existing=await Supabase.instance.client.from('course_lessons')
        .select('id').eq('course_id',course['id']);
      await Supabase.instance.client.from('course_lessons').insert({
        'course_id':course['id'],'title':values['title'],'description':values['description'],
        'lesson_type':values['lesson_type'],'media_url':(values['media_url']??'').isEmpty?null:values['media_url'],
        'duration_minutes':int.tryParse(values['duration']??'0')??0,'sort_order':existing.length,
        'created_by':Supabase.instance.client.auth.currentUser?.id,
      });
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('पाठ सेव हो गया। अभी unpublished है।')));
      await refresh();
      title.dispose();description.dispose();media.dispose();duration.dispose();
      return true;
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('पाठ सेव नहीं हुआ: $e')));
      title.dispose();description.dispose();media.dispose();duration.dispose();
      return false;
    }
  }

  Future<void> manageLessons(Map<String,dynamic> course) async {
    Future<List<Map<String,dynamic>>> load() async {
      final rows=await Supabase.instance.client.from('course_lessons')
        .select('id,title,lesson_type,duration_minutes,is_published,sort_order')
        .eq('course_id',course['id']).order('sort_order');
      return List<Map<String,dynamic>>.from(rows);
    }
    var lessonsFuture=load();
    await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(
      builder:(context,setDialogState)=>AlertDialog(
        title:Text('पाठ: ${course['title']}'),
        content:SizedBox(width:420,height:360,child:FutureBuilder<List<Map<String,dynamic>>>(
          future:lessonsFuture,builder:(context,snapshot){
            if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
            if(snapshot.hasError)return const Center(child:Text('पाठ लोड नहीं हो सके।'));
            final rows=snapshot.data??[];
            if(rows.isEmpty)return const Center(child:Text('अभी कोई पाठ नहीं जोड़ा गया है।'));
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final lesson = rows[index];
                final lessonIcon = lesson['lesson_type'] == 'video'
                    ? Icons.play_circle_outline
                    : lesson['lesson_type'] == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : lesson['lesson_type'] == 'audio'
                            ? Icons.headphones
                            : Icons.article_outlined;
                final stateLabel = lesson['is_published'] == true ? 'Published' : 'Draft';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(lessonIcon, color: KarmKritePalette.maroon),
                  title: Text((lesson['title'] ?? '').toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${lesson['lesson_type']} • ${lesson['duration_minutes']} min • $stateLabel'),
                );
              },
            );
          },
        )),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('बंद करें')),
          ElevatedButton.icon(onPressed:()async{
            final added=await addLesson(course);
            if(added)setDialogState(()=>lessonsFuture=load());
          },icon:const Icon(Icons.add),label:const Text('पाठ जोड़ें')),
        ],
      ),
    ));
  }

  Future<void> togglePublish(Map<String,dynamic> course) async {
    try {
      await Supabase.instance.client.from('courses')
        .update({'is_published':!(course['is_published']==true)}).eq('id',course['id']);
      await refresh();
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('स्थिति बदली नहीं जा सकी: $e')));
    }
  }
  Widget metric(String label,String value,IconData icon)=>Expanded(child:Container(
    padding:const EdgeInsets.all(13),
    decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(16),
      border:Border.all(color:Theme.of(context).dividerColor.withOpacity(.4))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:KarmKritePalette.gold,size:21),const SizedBox(height:10),
      Text(value,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
      Text(label,style:TextStyle(fontSize:10,color:Theme.of(context).colorScheme.onSurface.withOpacity(.62))),
    ]),
  ));

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('KARMKRITE Admin'),actions:[
      IconButton(onPressed:refresh,icon:const Icon(Icons.refresh_rounded)),
      IconButton(onPressed:widget.onLogout,icon:const Icon(Icons.logout_rounded)),
    ]),
    floatingActionButton:widget.role=='editor'?null:FloatingActionButton.extended(
      onPressed:addCourse,backgroundColor:KarmKritePalette.maroon,foregroundColor:KarmKritePalette.goldLight,
      icon:const Icon(Icons.add_rounded),label:const Text('नया कोर्स')),
    body:FutureBuilder<Map<String,dynamic>>(future:dataFuture,builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Admin डेटा लोड नहीं हो सका।'),TextButton(onPressed:refresh,child:const Text('पुनः प्रयास करें')),
      ]));
      final data=snapshot.data!;
      final courses=List<Map<String,dynamic>>.from(data['courses']);
      final staff=List<Map<String,dynamic>>.from(data['staff']);
      return RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.fromLTRB(18,14,18,90),children:[
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(
          gradient:const LinearGradient(colors:[KarmKritePalette.maroonDeep,KarmKritePalette.maroon]),borderRadius:BorderRadius.circular(22)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(widget.role.toUpperCase().replaceAll('_',' '),style:const TextStyle(color:KarmKritePalette.goldLight,fontSize:10,letterSpacing:2,fontWeight:FontWeight.w900)),
            const SizedBox(height:8),const Text('ज्ञान मंच का नियंत्रण केंद्र',style:TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.w900)),
            const SizedBox(height:5),Text('Courses, staff और learning activity का प्रबंधन।',style:TextStyle(color:Colors.white.withOpacity(.8),fontSize:12)),
          ])),
        const SizedBox(height:15),
        Row(children:[metric('Courses','${courses.length}',Icons.video_library_outlined),const SizedBox(width:9),metric('Students','${data['students']}',Icons.groups_2_outlined)]),
        const SizedBox(height:9),
        Row(children:[metric('Enrolments','${(data['enrollments'] as List).length}',Icons.school_outlined),const SizedBox(width:9),metric('Lessons','${data['lessons']}',Icons.play_lesson_outlined)]),
        const SizedBox(height:9),
        Row(children:[metric('Staff','${staff.length}',Icons.badge_outlined),const SizedBox(width:9),metric('Published','${courses.where((x)=>x['is_published']==true).length}',Icons.public_rounded)]),
        const SizedBox(height:22),
        Card(child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFF4EBDD),
            child: Icon(Icons.groups_rounded, color: KarmKritePalette.maroon)),
          title: const Text('विद्यार्थी एवं Enrollment प्रबंधन',
            style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('विद्यार्थियों की सूची देखें और कोर्स assign / revoke करें।'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => manageStudents(courses),
        )),
        const SizedBox(height:22),
        Row(children:[const Expanded(child:Text('कोर्स प्रबंधन',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900))),
          Text('${courses.where((x)=>x['is_published']==true).length} Published',style:const TextStyle(color:KarmKritePalette.gold,fontSize:11,fontWeight:FontWeight.w800))]),
        const SizedBox(height:9),
        if(courses.isEmpty)const Padding(padding:EdgeInsets.all(22),child:Text('अभी कोई कोर्स नहीं है। “नया कोर्स” से शुरुआत करें।',textAlign:TextAlign.center))
        else ...courses.map((course)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
          leading:Container(width:40,height:40,alignment:Alignment.center,
            decoration:BoxDecoration(color:KarmKritePalette.maroon.withOpacity(.09),borderRadius:BorderRadius.circular(12)),
            child:Icon(course['academy']=='jyotish'?Icons.auto_awesome:course['academy']=='karmkand'?Icons.temple_hindu:Icons.menu_book,color:KarmKritePalette.maroon)),
          title:Text((course['title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
          subtitle:Text('${course['academy']} • ${course['level']}'),
          trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(tooltip:'पाठ प्रबंधित करें',onPressed:()=>manageLessons(course),
              icon:const Icon(Icons.library_add_outlined,color:KarmKritePalette.maroon,size:20)),
            IconButton(tooltip:'Teacher assign करें',onPressed:()=>assignTeacher(course,staff),
              icon:const Icon(Icons.person_add_alt_1_rounded,color:KarmKritePalette.maroon,size:20)),
            Switch(value:course['is_published']==true,onChanged:(_)=>togglePublish(course),
              activeThumbColor:KarmKritePalette.gold),
          ]),
        ))),
        const SizedBox(height:18),
        Row(children:[
          const Expanded(child:Text('Staff Directory',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900))),
          if(widget.role=='super_admin') TextButton.icon(
            onPressed:inviteTeacher, icon:const Icon(Icons.person_add_alt_1_rounded,size:18),
            label:const Text('Teacher Invite')),
        ]),
        const SizedBox(height:7),
        ...staff.map((person)=>ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:4),
          leading:CircleAvatar(backgroundColor:KarmKritePalette.maroon.withOpacity(.1),
            child:Icon(person['role']=='teacher'?Icons.co_present_rounded:Icons.admin_panel_settings_rounded,color:KarmKritePalette.maroon)),
          title:Text((person['email']??'Staff account').toString()),
          subtitle:Text((person['role']??'').toString().toUpperCase()),
          trailing:Icon(person['is_active']==true?Icons.check_circle:Icons.block,
            color:person['is_active']==true?Colors.green:Colors.redAccent,size:18))),
      ]));
    }),
  );
}

class TeacherDashboardScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const TeacherDashboardScreen({super.key,required this.onLogout});
  @override
  State<TeacherDashboardScreen> createState()=>_TeacherDashboardScreenState();
}
class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  late Future<Map<String,dynamic>> dataFuture;
  @override
  void initState(){super.initState();dataFuture=loadData();}
  Future<Map<String,dynamic>> loadData() async {
    final db=Supabase.instance.client, id=db.auth.currentUser!.id;
    final assigned=await db.from('teacher_course_assignments')
      .select('course_id,courses(id,title,academy,level)').eq('teacher_id',id);
    final sessions=await db.from('class_sessions')
      .select('id,title,starts_at,status,meeting_url,course_id').eq('teacher_id',id).order('starts_at');
    return {'courses':assigned,'sessions':sessions};
  }
  Future<void> refresh() async {final f=loadData();setState(()=>dataFuture=f);await f;}
  Future<void> scheduleClass(Map<String,dynamic> entry) async {
    final title=TextEditingController();
    final start=TextEditingController(text:DateTime.now().add(const Duration(days:1)).toIso8601String().substring(0,16));
    final link=TextEditingController();
    final values=await showDialog<Map<String,String>>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Live Class Schedule करें'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'Class का नाम')),
        const SizedBox(height:8),TextField(controller:start,decoration:const InputDecoration(labelText:'Start (YYYY-MM-DDTHH:MM)')),
        const SizedBox(height:8),TextField(controller:link,decoration:const InputDecoration(labelText:'Meeting URL (optional)')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('रद्द करें')),
        ElevatedButton(onPressed:()=>Navigator.pop(dialogContext,{'title':title.text.trim(),'starts_at':start.text.trim(),'meeting_url':link.text.trim()}),child:const Text('Schedule')),
      ],
    ));
    if(values==null){title.dispose();start.dispose();link.dispose();return;}
    final date=DateTime.tryParse(values['starts_at']??'');
    if((values['title']??'').isEmpty||date==null){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Class का नाम और सही तारीख/समय भरें।')));
      title.dispose();start.dispose();link.dispose();return;
    }
    try{
      await Supabase.instance.client.from('class_sessions').insert({
        'course_id':entry['course_id'],'teacher_id':Supabase.instance.client.auth.currentUser!.id,
        'title':values['title'],'starts_at':date.toUtc().toIso8601String(),
        'meeting_url':(values['meeting_url']??'').isEmpty?null:values['meeting_url'],
      });
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Live class schedule हो गई।')));await refresh();}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Schedule नहीं हो सकी: $e')));}
    title.dispose();start.dispose();link.dispose();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Teacher Dashboard'),actions:[
      IconButton(onPressed:refresh,icon:const Icon(Icons.refresh_rounded)),
      IconButton(onPressed:widget.onLogout,icon:const Icon(Icons.logout_rounded)),
    ]),
    body:FutureBuilder<Map<String,dynamic>>(future:dataFuture,builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Teacher data लोड नहीं हो सका।'),TextButton(onPressed:refresh,child:const Text('पुनः प्रयास करें')),
      ]));
      final data=snapshot.data!;
      final courses=List<Map<String,dynamic>>.from(data['courses']);
      final sessions=List<Map<String,dynamic>>.from(data['sessions']);
      return RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(
          gradient:const LinearGradient(colors:[KarmKritePalette.maroonDeep,KarmKritePalette.maroon]),borderRadius:BorderRadius.circular(22)),
          child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('TEACHER WORKSPACE',style:TextStyle(color:KarmKritePalette.goldLight,fontSize:10,letterSpacing:2,fontWeight:FontWeight.w900)),
            SizedBox(height:8),Text('आपकी कक्षाएँ, आपका ज्ञान',style:TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.w900)),
            SizedBox(height:5),Text('Assigned courses और live classes एक ही जगह।',style:TextStyle(color:Color(0xFFF1DDE0),fontSize:12)),
          ])),
        const SizedBox(height:20),
        Row(children:[const Expanded(child:Text('मेरे कोर्स',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Text('${courses.length} Assigned',style:const TextStyle(color:KarmKritePalette.gold,fontWeight:FontWeight.w800,fontSize:11))]),
        const SizedBox(height:8),
        if(courses.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('अभी कोई कोर्स assign नहीं किया गया है। Admin से संपर्क करें।',textAlign:TextAlign.center))
        else ...courses.map((entry){
          final course=Map<String,dynamic>.from(entry['courses'] as Map);
          return Card(child:ListTile(
            leading:const CircleAvatar(backgroundColor:Color(0xFFF4EBDD),child:Icon(Icons.menu_book_rounded,color:KarmKritePalette.maroon)),
            title:Text((course['title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
            subtitle:Text('${course['academy']} • ${course['level']}'),
            trailing:IconButton(tooltip:'Live class schedule करें',onPressed:()=>scheduleClass(entry),
              icon:const Icon(Icons.add_circle_outline,color:KarmKritePalette.maroon)),
          ));
        }),
        const SizedBox(height:20),const Text('मेरी Live Classes',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        if(sessions.isEmpty)const Padding(padding:EdgeInsets.all(18),child:Text('अभी कोई class scheduled नहीं है।',textAlign:TextAlign.center))
        else ...sessions.map((session)=>Card(child:ListTile(
          leading:const Icon(Icons.video_camera_front_outlined,color:KarmKritePalette.maroon),
          title:Text((session['title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
          subtitle:Text('${session['starts_at']} • ${session['status']}'),
          trailing:session['meeting_url']==null?null:IconButton(icon:const Icon(Icons.open_in_new),
            onPressed:()=>launchUrl(Uri.parse(session['meeting_url'].toString()),mode:LaunchMode.externalApplication)),
        ))),
      ]));
    }),
  );
}
