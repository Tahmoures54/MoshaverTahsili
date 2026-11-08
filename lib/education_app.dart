import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'education/advisor_page.dart';
import 'education/assessment_pages.dart';
import 'education/credit_shop_page.dart';
import 'education/education_store.dart';
import 'education/study_pages.dart';
import 'education/ui.dart';

export 'education/advisor_page.dart';
export 'education/assessment_pages.dart';
export 'education/study_pages.dart';
export 'education/ui.dart' show EmptyState;

class EducationApp extends StatefulWidget {
  const EducationApp({super.key, this.store});
  final EducationStore? store;
  @override
  State<EducationApp> createState() => _EducationAppState();
}

class _EducationAppState extends State<EducationApp> {
  late Future<EducationStore> future;
  @override
  void initState() { super.initState(); future = widget.store == null ? EducationStore.open() : Future.value(widget.store); }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'مشاور هوشمند تحصیلی', debugShowCheckedModeBanner: false,
    locale: const Locale('fa'), supportedLocales: const [Locale('fa'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildAppTheme(),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
    home: FutureBuilder<EducationStore>(future: future, builder: (context, snapshot) {
      if (snapshot.hasData) return EntryScreen(store: snapshot.data!);
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const NoticeCard(text: 'ذخیره‌سازی گوشی آماده نشد. اطلاعات قبلی بازنویسی نشده است. فضای خالی گوشی را بررسی کن و دوباره برنامه را باز کن.', warning: true),
          FilledButton(onPressed: () => setState(() => future = EducationStore.open()), child: const Text('تلاش دوباره')),
        ]))));
      }
      return const LoadingPage();
    }),
  );
}

const gradeYears = <String, List<String>>{
  'ابتدایی': ['اول', 'دوم', 'سوم', 'چهارم', 'پنجم', 'ششم'],
  'متوسطه اول': ['هفتم', 'هشتم', 'نهم'],
  'متوسطه دوم': ['دهم', 'یازدهم', 'دوازدهم'],
  'دانش‌آموز کنکوری': ['پایه دهم', 'پایه یازدهم', 'پایه دوازدهم', 'فارغ‌التحصیل'],
  'دانشجو': ['ترم اول', 'ترم دوم یا بالاتر'],
};

Future<bool> showProfileSheet(BuildContext context, EducationStore store) async {
  final current = store.profile ?? {};
  final nickname = TextEditingController(text: current['nickname']?.toString() ?? '');
  final field = TextEditingController(text: current['field']?.toString() ?? 'عمومی');
  final goal = TextEditingController(text: current['goal']?.toString() ?? '');
  final form = GlobalKey<FormState>();
  var grade = gradeYears.containsKey(current['grade']) ? current['grade'].toString() : 'متوسطه اول';
  var year = gradeYears[grade]!.contains(current['year']) ? current['year'].toString() : gradeYears[grade]!.first;
  var saving = false;
  String? error;
  try {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, refresh) {
          return SafeArea(child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
            child: SingleChildScrollView(child: Form(key: form, child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('کمی درباره مسیر تحصیلی‌ات بدانیم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('نام مستعار کافی است. اطلاعات هویتی یا شماره تماس وارد نکن.', style: TextStyle(color: Colors.blueGrey, height: 1.7)),
                const SizedBox(height: 18),
                TextFormField(controller: nickname, maxLength: 40, decoration: const InputDecoration(labelText: 'نام یا نام مستعار (اختیاری)')),
                DropdownButtonFormField<String>(initialValue: grade, decoration: const InputDecoration(labelText: 'مقطع تحصیلی'),
                  items: gradeYears.keys.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: saving ? null : (value) { if (value != null) refresh(() { grade = value; year = gradeYears[value]!.first; }); }),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(key: ValueKey(grade), initialValue: year, decoration: const InputDecoration(labelText: 'پایه تحصیلی'),
                  items: gradeYears[grade]!.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: saving ? null : (value) { if (value != null) refresh(() => year = value); }),
                const SizedBox(height: 14),
                TextFormField(controller: field, maxLength: 80, decoration: const InputDecoration(labelText: 'رشته یا زمینه مورد علاقه'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'رشته یا «عمومی» را بنویس.' : null),
                TextFormField(controller: goal, maxLines: 2, maxLength: 300, decoration: const InputDecoration(labelText: 'هدف تحصیلی (اختیاری)')),
                if (error != null) NoticeCard(text: error!, warning: true),
                const SizedBox(height: 12),
                FilledButton(onPressed: saving ? null : () async {
                  if (!form.currentState!.validate()) return;
                  refresh(() { saving = true; error = null; });
                  try {
                    await store.saveProfile({'nickname': nickname.text.trim(), 'grade': grade, 'year': year,
                      'field': field.text.trim(), 'goal': goal.text.trim(), 'privacyVersion': 1});
                    if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                  } on Object catch (value) {
                    if (sheetContext.mounted) refresh(() { saving = false; error = friendlyError(value); });
                  }
                }, child: Text(saving ? 'در حال ذخیره…' : 'ذخیره پروفایل')),
              ],
            ))),
          ));
        });
      },
    );
    return saved == true;
  } finally { nickname.dispose(); field.dispose(); goal.dispose(); }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.store});
  final EducationStore store;
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool accepted = false;
  Future<void> start() async {
    if (!accepted) return;
    if (await showProfileSheet(context, widget.store) && mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    if (widget.store.profile != null) return Dashboard(store: widget.store);
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: Column(children: [
        const SizedBox(height: 16),
        Container(width: 92, height: 92, decoration: BoxDecoration(color: blue.withValues(alpha: .1), borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.school_rounded, color: blue, size: 54)),
        const SizedBox(height: 20),
        const Text('مشاور هوشمند تحصیلی', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: navy)),
        const SizedBox(height: 8),
        const Text('قدم‌های کوچک، یادگیری عمیق‌تر', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey)),
        const SizedBox(height: 24),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('سخنی با اولیا و دانش‌آموزان گرامی', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('برنامه مطالعه، نمرات، فلش‌کارت‌ها و سابقه مشاوره روی همین گوشی ذخیره می‌شوند. '
              'برای پاسخ هوش مصنوعی، پرسش، گفت‌وگوهای اخیر و پروفایل تحصیلی ارسال می‌شوند. '
              'در تحلیل وضعیت تحصیلی، خلاصه نمره‌ها فقط پس از زدن دکمه تحلیل ارسال می‌شود. '
              'نام کامل، نشانی، شماره تماس و اطلاعات حساس را وارد نکن. '
              'پاسخ هوش مصنوعی ممکن است اشتباه باشد و جایگزین معلم، مشاور مدرسه یا منابع رسمی نیست. '
              'با حذف برنامه، اطلاعات و اعتبار محلی از دست می‌روند.', style: TextStyle(height: 1.9)),
          CheckboxListTile(value: accepted, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => accepted = value ?? false), title: const Text('توضیحات و نکات حریم خصوصی را خواندم.')),
        ]))),
        if (widget.store.walletError != null) NoticeCard(text: widget.store.walletError!, warning: true),
        if (widget.store.dataError('edu.profile') != null) NoticeCard(text: widget.store.dataError('edu.profile')!, warning: true),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: accepted ? start : null,
            child: const Text('بزن بریم', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
      ]))),
    )));
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
  void refresh() { if (mounted) setState(() {}); }
  void go(int value) => setState(() => index = value);
  void push(Widget page) => unawaited(Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page)).then((_) => refresh()));

  Future<void> settings() async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(18), child: Text('تنظیمات و اطلاعات', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
      ListTile(leading: const Icon(Icons.person_outline), title: const Text('ویرایش پروفایل تحصیلی'),
          subtitle: Text('${widget.store.profile?['grade'] ?? ''} · ${widget.store.profile?['year'] ?? 'پایه ثبت نشده'}'), onTap: () => Navigator.pop(context, 'profile')),
      ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('کیف اعتبار و تاریخچه خرید'), onTap: () => Navigator.pop(context, 'wallet')),
      ListTile(leading: const Icon(Icons.history_edu_outlined), title: const Text('تاریخچه مشاوره‌ها'), onTap: () => Navigator.pop(context, 'reports')),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('درباره برنامه و حریم خصوصی'), subtitle: const Text('نسخه ۱.۱.۰ · ساخت ۳'), onTap: () => Navigator.pop(context, 'about')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('حذف اطلاعات تحصیلی این گوشی', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'profile': await showProfileSheet(context, widget.store); refresh();
      case 'wallet': push(CreditShopPage(store: widget.store));
      case 'reports': push(ReportsPage(store: widget.store));
      case 'about': push(const AboutPage());
      case 'delete': await deleteWorkspace();
    }
  }

  Future<void> deleteWorkspace() async {
    if (widget.store.hasActiveAiRequests) { showMessage(context, 'صبر کن تا درخواست فعلی مشاور کامل شود.'); return; }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('اطلاعات تحصیلی پاک شود؟'),
      content: const Text('پروفایل، برنامه‌ها، نمرات، فلش‌کارت‌ها و سابقه مشاوره پاک می‌شوند. اعتبار خریداری‌شده و سابقه خرید پاک نمی‌شوند. این کار برگشت‌پذیر نیست.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف اطلاعات'))]));
    if (confirmed != true || !mounted) return;
    try { await widget.store.clear(); if (mounted) setState(() => index = 0); }
    on Object catch (error) { if (mounted) showMessage(context, friendlyError(error)); }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['خانه', 'برنامه مطالعه من', 'آزمون‌ها و کارنامه', 'مرور و فلش‌کارت', 'مشاور هوشمند'];
    return Scaffold(appBar: AppBar(title: Text(titles[index], style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(tooltip: 'تنظیمات', onPressed: settings, icon: const Icon(Icons.settings_outlined))]),
      body: IndexedStack(index: index, children: [
        HomePage(store: widget.store, go: go),
        PlannerPage(store: widget.store, changed: refresh),
        ExamsPage(store: widget.store, changed: refresh),
        CardsPage(store: widget.store, changed: refresh),
        AdvisorPage(store: widget.store),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: go, destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'برنامه'),
        NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'آزمون'),
        NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'مرور'),
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'مشاور'),
      ]));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.go});
  final EducationStore store;
  final ValueChanged<int> go;
  void push(BuildContext context, Widget page) => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final profile = store.profile ?? {};
    final tasks = store.tasks;
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final recent = tasks.where((task) { final date = DateTime.tryParse(task['createdAt']?.toString() ?? ''); return date != null && !date.isBefore(weekStart); }).toList();
    final completed = recent.where((task) => task['done'] == true).toList();
    final minutes = completed.fold<int>(0, (sum, task) => sum + ((task['minutes'] as num?)?.toInt() ?? 0));
    final nickname = profile['nickname']?.toString() ?? '';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname.isEmpty ? 'سلام، همراه پرتلاش!' : 'سلام $nickname!', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${profile['grade'] ?? ''} · پایه ${profile['year'] ?? 'ثبت‌نشده'} · ${profile['field'] ?? ''}', style: const TextStyle(color: Colors.white70, height: 1.7)),
          const SizedBox(height: 14), const Text('امروز فقط یک قدم کوچک بردار؛ استمرار از برنامه‌های سنگین مهم‌تر است.', style: TextStyle(color: Colors.white, height: 1.8)),
        ])),
      const SizedBox(height: 14),
      CreditSummary(store: store, onShop: () => push(context, CreditShopPage(store: store))),
      Row(children: [
        Expanded(child: StatCard(title: 'انجام‌شده', value: '${faNumber(tasks.where((task) => task['done'] == true).length)}/${faNumber(tasks.length)}', icon: Icons.task_alt)),
        const SizedBox(width: 8), Expanded(child: StatCard(title: 'آزمون', value: faNumber(store.exams.length), icon: Icons.assessment_outlined)),
        const SizedBox(width: 8), Expanded(child: StatCard(title: 'فلش‌کارت', value: faNumber(store.cards.length), icon: Icons.style_outlined)),
      ]),
      const SizedBox(height: 12),
      NoticeCard(text: 'هفت روز اخیر: ${faNumber(completed.length)} کار از ${faNumber(recent.length)} کار ثبت‌شده انجام شده؛ ${faNumber(minutes)} دقیقه مطالعه برنامه‌ریزی‌شده در کارهای انجام‌شده.', icon: Icons.insights_outlined),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('از کجا شروع کنیم؟', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
      QuickTile(icon: Icons.auto_awesome, title: 'گفت‌وگو با مشاور هوشمند', subtitle: 'پرسش، برنامه مطالعه و روش بهبود', onTap: () => go(4)),
      QuickTile(icon: Icons.insights_outlined, title: 'بررسی وضعیت تحصیلی', subtitle: 'نقاط قوت و ضعف بر اساس نمره‌های تو', onTap: () => push(context, AcademicInsightsPage(store: store))),
      QuickTile(icon: Icons.calendar_month, title: 'برنامه مطالعه', subtitle: 'ثبت و پیگیری کارهای درسی', onTap: () => go(1)),
      QuickTile(icon: Icons.assessment_outlined, title: 'آزمون و کارنامه', subtitle: 'ثبت نمرات و مشاهده میانگین', onTap: () => go(2)),
      QuickTile(icon: Icons.style_outlined, title: 'مرور و فلش‌کارت', subtitle: 'یادگیری ماندگار با مرور فاصله‌دار', onTap: () => go(3)),
      QuickTile(icon: Icons.explore_outlined, title: 'راهنمای انتخاب رشته', subtitle: 'شناخت علاقه‌ها و مسیرهای ممکن', onTap: () => push(context, CareerPage(store: store))),
      QuickTile(icon: Icons.history_edu_outlined, title: 'تاریخچه مشاوره‌ها', subtitle: 'پاسخ‌های قبلی و درخواست‌های ناتمام', onTap: () => push(context, ReportsPage(store: store))),
      QuickTile(icon: Icons.menu_book_outlined, title: 'روش‌های مؤثر مطالعه', subtitle: 'راهنمای آفلاین تمرکز و یادگیری', onTap: () => push(context, const StudyTipsPage())),
    ]);
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon});
  final String title, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
    child: Column(children: [Icon(icon, color: teal), const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.blueGrey))])));
}

class QuickTile extends StatelessWidget {
  const QuickTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(onTap: onTap,
    leading: Icon(icon, color: blue), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text(subtitle, style: const TextStyle(height: 1.6)), trailing: const Icon(Icons.chevron_left)));
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('درباره مشاور تحصیلی')),
    body: ListView(padding: const EdgeInsets.all(16), children: const [
      NoticeCard(text: 'نسخه ۱.۱.۰ · ساخت ۳\nشناسه برنامه: ir.moshaver.tahsili', icon: Icons.school_outlined),
      NoticeCard(text: 'اطلاعات تحصیلی و کیف اعتبار محلی هستند و به حساب کاربری یا سرور اختصاصی فرستاده نمی‌شوند. '
          'فقط درخواست‌های هوش مصنوعی و عملیات خرید بازار به اینترنت نیاز دارند. متن پرسش، بخشی از گفت‌وگو و اطلاعات تحصیلیِ اعلام‌شده در هر درخواست با سرویس هوش مصنوعی به اشتراک گذاشته می‌شوند.'),
      NoticeCard(text: 'اعتبار و خریدها با امضای بازار و دفتر محلی بررسی می‌شوند، اما این بررسی جایگزین اعتبارسنجی سمت سرور نیست. '
          'داده گوشی قابل دستکاری است و اعتبار بین دستگاه‌ها منتقل نمی‌شود. کلید هوش مصنوعی تزریق‌شده در APK نیز قابل استخراج است.'),
      NoticeCard(text: 'پاسخ هوش مصنوعی ممکن است اشتباه باشد. تصمیم‌های مهم تحصیلی را با معلم، مشاور مدرسه و منابع رسمی بررسی کن. '
          'این برنامه تشخیص پزشکی یا روان‌شناختی ارائه نمی‌دهد.'),
      NoticeCard(text: 'فونت وزیرمتن با مجوز SIL Open Font License استفاده شده است. مجوز برنامه MIT است.'),
    ]));
}
