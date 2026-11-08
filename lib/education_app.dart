import 'dart:async';
import 'package:flutter/material.dart';
import 'education/education_store.dart';
import 'education/ai_advisor_service.dart';

const Color navy = Color(0xFF17324D);
const Color blue = Color(0xFF2867A8);
const Color teal = Color(0xFF2C9C91);
const Color pale = Color(0xFFF4F7FB);

String _digitsToEnglish(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var result = value;
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(persian[i], i.toString());
    result = result.replaceAll(arabic[i], i.toString());
  }
  return result.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '.');
}

class EducationApp extends StatefulWidget {
  const EducationApp({super.key});
  @override
  State<EducationApp> createState() => _EducationAppState();
}
class _EducationAppState extends State<EducationApp> {
  late final Future<EducationStore> future = EducationStore.open();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'مشاور هوشمند تحصیلی',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: pale,
      colorScheme: ColorScheme.fromSeed(seedColor: blue),
      appBarTheme: const AppBarTheme(backgroundColor: pale, foregroundColor: navy, centerTitle: true),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
    home: FutureBuilder<EducationStore>(
      future: future,
      builder: (context, snap) => snap.hasData
        ? EntryScreen(store: snap.data!)
        : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.store});
  final EducationStore store;
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}
class _EntryScreenState extends State<EntryScreen> {
  bool accepted = false;
  @override
  Widget build(BuildContext context) {
    if (widget.store.profile != null) return Dashboard(store: widget.store);
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480), child: Column(children: [
          const SizedBox(height: 18),
          Container(width: 100, height: 100, decoration: BoxDecoration(color: blue.withOpacity(.1), borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.school_rounded, color: blue, size: 58)),
          const SizedBox(height: 20),
          const Text('مشاور هوشمند تحصیلی', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: navy)),
          const SizedBox(height: 8),
          const Text('همراه هوشمند تو در مسیر یادگیری و موفقیت', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 24),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('سخنی با اولیا و دانش‌آموزان گرامی', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: navy)),
            const SizedBox(height: 10),
            const Text('این برنامه برای کمک به یادگیری، برنامه‌ریزی و شناخت مسیرهای تحصیلی طراحی شده است. برنامه درسی، نمرات و یادداشت‌ها روی همین گوشی ذخیره می‌شوند. برای پاسخ‌گویی هوش مصنوعی، متن پرسش، مقطع و رشته تحصیلی ثبت‌شده و بخشی از گفت‌وگوهای قبلی از طریق اینترنت به سرویس هوش مصنوعی فرستاده می‌شود؛ نمرات و برنامه درسی برای این درخواست ارسال نمی‌شوند. اطلاعات حساس، نام کامل، نشانی و شماره تماس را وارد نکنید. پاسخ هوش مصنوعی ممکن است اشتباه باشد و جایگزین نظر معلم، مشاور مدرسه یا منابع رسمی نیست.', style: TextStyle(height: 1.8)),
            CheckboxListTile(value: accepted, contentPadding: EdgeInsets.zero, onChanged: (v) => setState(() => accepted = v ?? false),
              title: const Text('توضیحات و نکات حریم خصوصی را خواندم.'), controlAffinity: ListTileControlAffinity.leading),
          ]))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: accepted ? _profileDialog : null,
            child: const Padding(padding: EdgeInsets.all(13), child: Text('بزن بریم', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          )),
        ]),
      ),
    ))));
  }

  Future<void> _profileDialog() async {
    final nickname = TextEditingController();
    final field = TextEditingController(text: 'عمومی');
    final goal = TextEditingController();
    String grade = 'متوسطه اول';
    final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, refresh) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('پروفایل تحصیلی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          const SizedBox(height: 14),
          TextField(controller: nickname, decoration: const InputDecoration(labelText: 'نام یا نام مستعار (اختیاری)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: grade, decoration: const InputDecoration(labelText: 'مقطع تحصیلی'),
            items: const ['ابتدایی', 'متوسطه اول', 'متوسطه دوم', 'دانش‌آموز کنکوری', 'دانشجو'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) { if (v != null) refresh(() => grade = v); }),
          const SizedBox(height: 10),
          TextField(controller: field, decoration: const InputDecoration(labelText: 'رشته یا وضعیت تحصیلی')),
          const SizedBox(height: 10),
          TextField(controller: goal, maxLines: 2, decoration: const InputDecoration(labelText: 'هدف تحصیلی (اختیاری)')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره و ورود'))),
        ])),
      )));
    if (saved == true) {
      await widget.store.saveProfile({'nickname': nickname.text.trim(), 'grade': grade, 'field': field.text.trim().isEmpty ? 'عمومی' : field.text.trim(), 'goal': goal.text.trim()});
      if (mounted) setState(() {});
    }
    nickname.dispose(); field.dispose(); goal.dispose();
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.store});
  final EducationStore store;
  @override
  State<Dashboard> createState() => _DashboardState();
}
class _DashboardState extends State<Dashboard> {
  int index = 0;
  void refresh() => setState(() {});
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store, go: (v) => setState(() => index = v)),
      PlannerPage(store: widget.store, changed: refresh),
      ExamsPage(store: widget.store, changed: refresh),
      CardsPage(store: widget.store, changed: refresh),
      AdvisorPage(store: widget.store),
    ];
    const titles = ['خانه', 'برنامه درسی من', 'آزمون‌ها و کارنامه', 'مرور و فلش‌کارت', 'مشاور هوشمند'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _settings, icon: const Icon(Icons.settings_outlined))]),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'برنامه'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'آزمون'),
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'مرور'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'مشاور'),
        ]),
    );
  }

  Future<void> _settings() async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.person_outline), title: Text((widget.store.profile?['grade'] ?? '').toString()), subtitle: const Text('ویرایش پروفایل تحصیلی'), onTap: () => Navigator.pop(context, 'edit')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('حذف تمام اطلاعات این گوشی', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (choice == 'edit' && mounted) {
      final current = widget.store.profile ?? {};
      final nickname = TextEditingController(text: (current['nickname'] ?? '').toString());
      final field = TextEditingController(text: (current['field'] ?? 'عمومی').toString());
      final goal = TextEditingController(text: (current['goal'] ?? '').toString());
      String grade = (current['grade'] ?? 'متوسطه اول').toString();
      final saved = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
        builder: (context) => StatefulBuilder(builder: (context, refresh) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ویرایش پروفایل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            TextField(controller: nickname, decoration: const InputDecoration(labelText: 'نام یا نام مستعار')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(value: grade, decoration: const InputDecoration(labelText: 'مقطع تحصیلی'),
              items: const ['ابتدایی', 'متوسطه اول', 'متوسطه دوم', 'دانش‌آموز کنکوری', 'دانشجو'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) refresh(() => grade = v); }),
            const SizedBox(height: 8), TextField(controller: field, decoration: const InputDecoration(labelText: 'رشته یا وضعیت تحصیلی')),
            const SizedBox(height: 8), TextField(controller: goal, decoration: const InputDecoration(labelText: 'هدف تحصیلی')),
            const SizedBox(height: 14), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره تغییرات')),
          ])),
        )));
      if (saved == true) {
        await widget.store.saveProfile({'nickname': nickname.text.trim(), 'grade': grade, 'field': field.text.trim(), 'goal': goal.text.trim()});
        if (mounted) setState(() {});
      }
      nickname.dispose(); field.dispose(); goal.dispose();
    }
    if (choice == 'delete' && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('حذف اطلاعات؟'),
        content: const Text('پروفایل، برنامه‌ها، نمرات، فلش‌کارت‌ها و تاریخچه گفتگو پاک می‌شوند.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))]));
      if (ok == true) {
        await widget.store.clear();
        if (mounted) {
          unawaited(Navigator.of(context).pushAndRemoveUntil<void>(
            MaterialPageRoute<void>(builder: (_) => EntryScreen(store: widget.store)),
            (route) => false,
          ));
        }
      }
    }
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.go});
  final EducationStore store;
  final ValueChanged<int> go;
  @override
  Widget build(BuildContext context) {
    final p = store.profile ?? {};
    final tasks = store.tasks;
    final exams = store.exams;
    final cards = store.cards;
    final done = tasks.where((e) => e['done'] == true).length;
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final weekTasks = tasks.where((e) {
      final created = DateTime.tryParse((e['createdAt'] ?? '').toString());
      return created != null && !created.isBefore(weekStart);
    }).toList();
    final weekDone = weekTasks.where((e) => e['done'] == true).length;
    final weekMinutes = weekTasks.fold<int>(0, (sum, e) => sum + ((e['minutes'] as num?)?.toInt() ?? 0));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [blue, teal]), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((p['nickname'] == null || p['nickname'] == '' ? 'خوش آمدی!' : 'سلام ' + p['nickname'].toString() + '!'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 6),
          Text((p['grade'] ?? '').toString() + ' · ' + (p['field'] ?? '').toString(), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const Text('قدم‌های کوچک و پیوسته، نتیجه‌های بزرگ می‌سازند.', style: TextStyle(color: Colors.white)),
        ])),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: StatCard(title: 'کارهای انجام‌شده', value: done.toString() + '/' + tasks.length.toString(), icon: Icons.task_alt)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(title: 'آزمون‌ها', value: exams.length.toString(), icon: Icons.assessment)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(title: 'فلش‌کارت‌ها', value: cards.length.toString(), icon: Icons.style)),
      ]),
      const SizedBox(height: 14),
      Card(child: ListTile(
        leading: const Icon(Icons.insights_outlined, color: teal, size: 28),
        title: const Text('گزارش هفت روز اخیر', style: TextStyle(fontWeight: FontWeight.bold, color: navy)),
        subtitle: Text(weekDone.toString() + ' کار از ' + weekTasks.length.toString() + ' کار انجام شده · ' + weekMinutes.toString() + ' دقیقه برنامه‌ریزی مطالعه'),
      )),
      const SizedBox(height: 20),
      const Text('میانبرها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
      QuickTile(icon: Icons.auto_awesome, title: 'مشاور هوشمند', subtitle: 'رفع اشکال و راهنمایی تحصیلی', onTap: () => go(4)),
      QuickTile(icon: Icons.calendar_month, title: 'برنامه مطالعه', subtitle: 'ثبت و پیگیری کارهای درسی', onTap: () => go(1)),
      QuickTile(icon: Icons.assessment, title: 'آزمون و کارنامه', subtitle: 'ثبت نمرات و بررسی عملکرد', onTap: () => go(2)),
      QuickTile(icon: Icons.style, title: 'مرور و فلش‌کارت', subtitle: 'مرور پرسش و پاسخ‌ها', onTap: () => go(3)),
      QuickTile(icon: Icons.explore_outlined, title: 'راهنمای انتخاب رشته', subtitle: 'بررسی علاقه‌ها و توانایی‌ها با کمک مشاور', onTap: () => unawaited(Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => CareerPage(store: store))))),
      QuickTile(icon: Icons.menu_book_outlined, title: 'روش‌های مؤثر مطالعه', subtitle: 'تکنیک‌های یادگیری، تمرکز و آمادگی امتحان', onTap: () => unawaited(Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const StudyTipsPage())))),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('انتخاب رشته را با شناخت علاقه‌ها، توانایی‌ها و واقعیت‌های هر مسیر انجام بده؛ هیچ آزمونی به‌تنهایی آینده تو را تعیین نمی‌کند.', style: TextStyle(height: 1.7)))),
    ]);
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon});
  final String title, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
    child: Column(children: [Icon(icon, color: teal), const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: navy)),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.blueGrey))])));
}

class QuickTile extends StatelessWidget {
  const QuickTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title, subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(onTap: onTap, leading: Icon(icon, color: blue),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: navy)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left)));
}

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.store, required this.changed});
  final EducationStore store; final VoidCallback changed;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}
class _PlannerPageState extends State<PlannerPage> {
  Future<void> add() async {
    final title = TextEditingController(); final subject = TextEditingController(); final duration = TextEditingController(text: '30');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('برنامه مطالعه جدید'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'موضوع یا کار')),
        const SizedBox(height: 8), TextField(controller: subject, decoration: const InputDecoration(labelText: 'درس')),
        const SizedBox(height: 8), TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدت (دقیقه)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('افزودن'))]));
    if (ok == true && title.text.trim().isNotEmpty) {
      await widget.store.addTask({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'title': title.text.trim(),
        'subject': subject.text.trim().isEmpty ? 'عمومی' : subject.text.trim(), 'minutes': int.tryParse(_digitsToEnglish(duration.text)) ?? 30, 'done': false, 'createdAt': DateTime.now().toIso8601String()});
      setState(() {}); widget.changed();
    }
    title.dispose(); subject.dispose(); duration.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.tasks;
    final minutes = tasks.fold<int>(0, (sum, e) => sum + ((e['minutes'] as num?)?.toInt() ?? 0));
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('افزودن برنامه')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
        Card(child: ListTile(leading: const Icon(Icons.timer_outlined, color: blue), title: Text('زمان برنامه‌ریزی‌شده: ' + minutes.toString() + ' دقیقه'))),
        if (tasks.isEmpty) const EmptyState(title: 'هنوز برنامه‌ای نساخته‌ای', subtitle: 'اولین کار درسی‌ات را ثبت کن.', icon: Icons.event_note),
        ...tasks.map((t) => Card(child: CheckboxListTile(value: t['done'] == true, onChanged: (_) async { await widget.store.toggleTask(t['id'].toString()); setState(() {}); widget.changed(); },
          title: Text(t['title'].toString(), style: TextStyle(fontWeight: FontWeight.bold, decoration: t['done'] == true ? TextDecoration.lineThrough : null)),
          subtitle: Text(t['subject'].toString() + ' · ' + t['minutes'].toString() + ' دقیقه'),
          secondary: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await widget.store.deleteTask(t['id'].toString()); setState(() {}); widget.changed(); }),
          controlAffinity: ListTileControlAffinity.leading))),
      ]));
  }
}

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key, required this.store, required this.changed});
  final EducationStore store; final VoidCallback changed;
  @override
  State<ExamsPage> createState() => _ExamsPageState();
}
class _ExamsPageState extends State<ExamsPage> {
  Future<void> add() async {
    final subject = TextEditingController(); final score = TextEditingController(); final max = TextEditingController(text: '20');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('ثبت نتیجه آزمون'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: subject, decoration: const InputDecoration(labelText: 'نام درس')),
        const SizedBox(height: 8), TextField(controller: score, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نمره کسب‌شده')),
        const SizedBox(height: 8), TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نمره از')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ثبت'))]));
    final s = double.tryParse(_digitsToEnglish(score.text)); final m = double.tryParse(_digitsToEnglish(max.text)) ?? 20;
    if (ok == true && subject.text.trim().isNotEmpty && s != null && m > 0 && s >= 0 && s <= m) {
      await widget.store.addExam({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'subject': subject.text.trim(), 'score': s, 'max': m});
      setState(() {}); widget.changed();
    }
    subject.dispose(); score.dispose(); max.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final exams = widget.store.exams;
    final average = exams.isEmpty ? 0.0 : exams.fold<double>(0, (sum, e) => sum + ((e['score'] as num).toDouble() / (e['max'] as num).toDouble() * 100)) / exams.length;
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('ثبت نمره')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          const Text('میانگین درصد نمره‌ها'), const SizedBox(height: 8),
          Text(average.toStringAsFixed(1) + '٪', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: blue)),
          LinearProgressIndicator(value: average / 100, minHeight: 7),
        ]))),
        if (exams.isEmpty) const EmptyState(title: 'هنوز نمره‌ای ثبت نشده', subtitle: 'نتایج آزمون‌ها را ثبت کن.', icon: Icons.assessment),
        ...exams.map((e) => Card(child: ListTile(title: Text(e['subject'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('نمره ' + e['score'].toString() + ' از ' + e['max'].toString()),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await widget.store.deleteExam(e['id'].toString()); setState(() {}); widget.changed(); })))),
      ]));
  }
}

class CardsPage extends StatefulWidget {
  const CardsPage({super.key, required this.store, required this.changed});
  final EducationStore store; final VoidCallback changed;
  @override
  State<CardsPage> createState() => _CardsPageState();
}
class _CardsPageState extends State<CardsPage> {
  String? revealed;
  Future<void> add() async {
    final q = TextEditingController(); final a = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('فلش‌کارت جدید'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: q, maxLines: 2, decoration: const InputDecoration(labelText: 'پرسش')),
        const SizedBox(height: 8), TextField(controller: a, maxLines: 3, decoration: const InputDecoration(labelText: 'پاسخ')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره'))]));
    if (ok == true && q.text.trim().isNotEmpty && a.text.trim().isNotEmpty) {
      await widget.store.addCard({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'q': q.text.trim(), 'a': a.text.trim(), 'interval': 0, 'dueAt': DateTime.now().toIso8601String()});
      setState(() {}); widget.changed();
    }
    q.dispose(); a.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final cards = widget.store.cards;
    final now = DateTime.now();
    final dueCount = cards.where((c) {
      final raw = c['dueAt']?.toString();
      final due = raw == null ? null : DateTime.tryParse(raw);
      return due == null || !due.isAfter(now);
    }).length;
    return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('ساخت فلش‌کارت')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
        Card(child: ListTile(leading: const Icon(Icons.psychology_alt, color: Colors.deepPurple), title: Text(cards.length.toString() + ' فلش‌کارت · ' + dueCount.toString() + ' آماده مرور'), subtitle: const Text('فاصله مرور کارت‌ها با میزان تسلط تو بیشتر می‌شود.'))),
        if (cards.isEmpty) const EmptyState(title: 'فلش‌کارتی نداری', subtitle: 'یک پرسش و پاسخ بساز.', icon: Icons.style),
        ...cards.map((c) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c['q'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: navy)),
          if (revealed == c['id']) ...[const Divider(), Text(c['a'].toString(), style: const TextStyle(height: 1.6)),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () async { c['interval'] = 1; c['dueAt'] = DateTime.now().add(const Duration(days: 1)).toIso8601String(); await widget.store.updateCard(c); setState(() => revealed = null); }, child: const Text('دوباره مرور می‌کنم')),
              FilledButton(onPressed: () async { c['interval'] = ((c['interval'] as num?)?.toInt() ?? 0) < 1 ? 1 : (c['interval'] as num).toInt() * 2; c['dueAt'] = DateTime.now().add(Duration(days: (c['interval'] as num).toInt())).toIso8601String(); await widget.store.updateCard(c); setState(() => revealed = null); }, child: const Text('یاد گرفتم')),
            ])
          ] else TextButton(onPressed: () => setState(() => revealed = c['id'].toString()), child: const Text('نمایش پاسخ')),
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () async { await widget.store.deleteCard(c['id'].toString()); setState(() {}); widget.changed(); }, icon: const Icon(Icons.delete_outline))),
        ])))),
      ]));
  }
}

class AdvisorPage extends StatefulWidget {
  const AdvisorPage({super.key, required this.store});
  final EducationStore store;
  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}
class _AdvisorPageState extends State<AdvisorPage> {
  final input = TextEditingController();
  final service = AiAdvisorService();
  late List<Map<String, dynamic>> messages;
  bool busy = false;
  @override
  void initState() { super.initState(); messages = widget.store.messages; }
  @override
  void dispose() { input.dispose(); service.dispose(); super.dispose(); }
  Future<void> send() async {
    final text = input.text.trim(); if (text.isEmpty || busy) return;
    input.clear();
    setState(() { busy = true; messages.add({'role': 'user', 'content': text}); });
    await widget.store.saveMessages(messages);
    try {
      final answer = await service.ask(profile: widget.store.profile, history: messages.take(messages.length - 1).toList(), question: text);
      if (!mounted) return;
      setState(() => messages.add({'role': 'assistant', 'content': answer}));
      await widget.store.saveMessages(messages);
    } catch (e) {
      if (!mounted) return;
      setState(() => messages.add({'role': 'assistant', 'content': e.toString().replaceFirst('Exception: ', '')}));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(child: messages.isEmpty
      ? const Center(child: Padding(padding: EdgeInsets.all(26), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, color: blue, size: 46), SizedBox(height: 12),
          Text('سلام! من مشاور هوشمند تحصیلی هستم.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 18)),
          SizedBox(height: 8), Text('درباره درس‌ها، روش مطالعه، برنامه‌ریزی و انتخاب مسیر تحصیلی از من بپرس.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey, height: 1.7)),
        ])))
      : ListView(padding: const EdgeInsets.all(14), children: [
          ...messages.map((m) {
            final user = m['role'] == 'user';
            return Align(alignment: user ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(constraints: const BoxConstraints(maxWidth: 330), margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: user ? blue : Colors.white,
                  borderRadius: BorderRadius.circular(16), border: user ? null : Border.all(color: const Color(0xFFE3EAF2))),
                child: SelectableText(m['content'].toString(), style: TextStyle(color: user ? Colors.white : navy, height: 1.6))));
          }),
          if (busy) const Padding(padding: EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight, child: CircularProgressIndicator())),
        ])),
    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: SafeArea(top: false, child: Row(children: [
      Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send,
        onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'سؤالت را اینجا بنویس...', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
      const SizedBox(width: 8), IconButton.filled(onPressed: busy ? null : send, icon: const Icon(Icons.send_rounded)),
    ]))),
  ]);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle, required this.icon});
  final String title, subtitle; final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
    child: Column(children: [Icon(icon, size: 46, color: Colors.blueGrey.shade300), const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: navy)), const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey))]));
}

class CareerPage extends StatefulWidget {
  const CareerPage({super.key, required this.store});
  final EducationStore store;
  @override
  State<CareerPage> createState() => _CareerPageState();
}

class _CareerPageState extends State<CareerPage> {
  final interests = TextEditingController();
  final strengths = TextEditingController();
  final favoriteSubjects = TextEditingController();
  final workStyle = TextEditingController();
  final advisor = AiAdvisorService();
  String? result;
  String? error;
  bool busy = false;

  @override
  void dispose() {
    interests.dispose();
    strengths.dispose();
    favoriteSubjects.dispose();
    workStyle.dispose();
    advisor.dispose();
    super.dispose();
  }

  Future<void> analyze() async {
    if (interests.text.trim().isEmpty || favoriteSubjects.text.trim().isEmpty) {
      setState(() => error = 'لطفاً دست‌کم علاقه‌ها و درس‌های موردعلاقه‌ات را بنویس.');
      return;
    }
    setState(() { busy = true; error = null; result = null; });
    final question = 'برای راهنمایی انتخاب رشته، این اطلاعات را بررسی کن. '
      'علاقه‌ها: ' + interests.text.trim() +
      '. توانایی‌ها و نقاط قوت از نگاه خود دانش‌آموز: ' + strengths.text.trim() +
      '. درس‌های مورد علاقه: ' + favoriteSubjects.text.trim() +
      '. سبک کاری مورد علاقه: ' + workStyle.text.trim() +
      '. چند مسیر تحصیلی احتمالی را با دلیل، مزایا، دشواری‌ها و سؤال‌های تکمیلی معرفی کن. '
      'هیچ رشته‌ای را قطعی تجویز نکن و تأکید کن که بررسی با مشاور مدرسه و منابع رسمی لازم است.';
    try {
      final answer = await advisor.ask(profile: widget.store.profile, history: const [], question: question);
      if (mounted) setState(() => result = answer);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: const Text('راهنمای انتخاب رشته')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
        'این پرسش‌نامه برای شروع گفت‌وگو و شناخت گزینه‌هاست؛ نتیجه آن آزمون روان‌سنجی یا تشخیص قطعی استعداد نیست. پاسخ‌ها برای تحلیل به سرویس هوش مصنوعی ارسال می‌شوند.',
        style: TextStyle(height: 1.7),
      ))),
      const SizedBox(height: 12),
      TextField(controller: interests, maxLines: 3, decoration: const InputDecoration(labelText: 'به چه موضوع‌ها و فعالیت‌هایی علاقه داری؟')),
      const SizedBox(height: 10),
      TextField(controller: strengths, maxLines: 3, decoration: const InputDecoration(labelText: 'در چه کارهایی احساس توانمندی می‌کنی؟')),
      const SizedBox(height: 10),
      TextField(controller: favoriteSubjects, maxLines: 2, decoration: const InputDecoration(labelText: 'درس‌های مورد علاقه یا قوی‌تر تو')),
      const SizedBox(height: 10),
      TextField(controller: workStyle, maxLines: 2, decoration: const InputDecoration(labelText: 'کار عملی، پژوهشی، هنری، ارتباط با مردم یا چه سبک دیگری را دوست داری؟')),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: busy ? null : analyze, icon: const Icon(Icons.auto_awesome), label: Text(busy ? 'در حال بررسی...' : 'بررسی گزینه‌های تحصیلی')),
      if (busy) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
      if (error != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(error!, style: const TextStyle(color: Colors.red)))),
      if (result != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(result!, style: const TextStyle(height: 1.75)))),
    ]),
  );
}

class StudyTipsPage extends StatelessWidget {
  const StudyTipsPage({super.key});

  static const tips = <Map<String, String>>[
    {
      'title': 'مطالعه فعال',
      'body': 'بعد از خواندن یک بخش، کتاب را ببند و با زبان خودت توضیح بده چه یاد گرفته‌ای. به‌جای چندبار روخوانی، از خودت سؤال بپرس و پاسخ را از حافظه بازیابی کن.',
      'action': 'پس از هر ۲۰ تا ۳۰ دقیقه مطالعه، سه پرسش از همان مبحث طرح کن.'
    },
    {
      'title': 'مرور فاصله‌دار',
      'body': 'مرور را به یک شب قبل از امتحان موکول نکن. فاصله مرورها را به‌تدریج بیشتر کن و مطالبی را که فراموش می‌کنی زودتر دوباره مرور کن.',
      'action': 'یک مرور کوتاه در روز بعد و مرورهای بعدی در فاصله‌های طولانی‌تر تنظیم کن.'
    },
    {
      'title': 'بازه‌های تمرکز',
      'body': 'برای شروع می‌توانی ۲۵ دقیقه مطالعه متمرکز و ۵ دقیقه استراحت را امتحان کنی. اگر این بازه با شرایطت سازگار نیست، آن را کوتاه‌تر یا بلندتر کن.',
      'action': 'هنگام مطالعه اعلان‌ها را خاموش کن و در زمان استراحت از جای خود بلند شو.'
    },
    {
      'title': 'خلاصه‌نویسی مفهومی',
      'body': 'خلاصه خوب رونویسی کتاب نیست. رابطه علت و معلول، فرمول‌های مهم، مثال‌ها و تفاوت مفاهیم را با کلمات خودت ثبت کن.',
      'action': 'برای هر فصل یک صفحه نکته و یک مثال حل‌شده نگه دار.'
    },
    {
      'title': 'آمادگی برای امتحان',
      'body': 'نمونه‌سؤال را در شرایط نزدیک به امتحان حل کن. پس از بررسی پاسخ‌ها، اشتباه‌ها را دسته‌بندی کن: بی‌دقتی، ضعف مفهوم، فراموشی یا کمبود زمان.',
      'action': 'برای هر اشتباه، یک تمرین مشابه انتخاب کن و دوباره حل کن.'
    },
    {
      'title': 'تعادل و آرامش',
      'body': 'خواب کافی، آب و غذا، حرکت بدنی و استراحت بخشی از یادگیری‌اند. برنامه‌ای که زمان بازیابی و استراحت ندارد معمولاً پایدار نمی‌ماند.',
      'action': 'برنامه روزانه را واقع‌بینانه ببند و بین بازه‌های سنگین استراحت قرار بده.'
    },
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: const Text('روش‌های مؤثر مطالعه')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
        'این راهنما پیشنهادهای عمومی برای بهتر درس خواندن است. هر روش را متناسب با درس، سن، شرایط و تجربه خودت تنظیم کن.',
        style: TextStyle(height: 1.7),
      ))),
      ...tips.map((tip) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip['title']!, style: const TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 16)),
          const SizedBox(height: 8),
          Text(tip['body']!, style: const TextStyle(height: 1.7)),
          const SizedBox(height: 10),
          Text('تمرین پیشنهادی: ' + tip['action']!, style: const TextStyle(color: teal, height: 1.6, fontWeight: FontWeight.w600)),
        ],
      )))),
    ]),
  );
}
