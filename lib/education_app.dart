import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'education/advisor_page.dart';
import 'education/analytics_page.dart';
import 'education/assessment_pages.dart';
import 'education/backup_page.dart';
import 'education/credit_shop_page.dart';
import 'education/education_store.dart';
import 'education/learning_engine.dart';
import 'education/learning_coach_page.dart';
import 'education/family_progress_report.dart';
import 'education/study_pages.dart';
import 'education/simorgh_companion.dart';
import 'education/referral_page.dart';
import 'education/ui.dart';

export 'education/advisor_page.dart';
export 'education/assessment_pages.dart';
export 'education/study_pages.dart';
export 'education/ui.dart' show EmptyState;

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.1.2');
const appBuildNumber = String.fromEnvironment('APP_BUILD_NUMBER', defaultValue: '5');
const appVersionLabel = 'نسخه $appVersion · ساخت $appBuildNumber';

int _safeHomeMinutes(Object? value) {
  if (value is num && value.isFinite) {
    return value.clamp(0, 1440).toInt();
  }
  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());
  return parsed?.clamp(0, 1440).toInt() ?? 0;
}

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
    title: 'سیمرغ | مشاور هوشمند تحصیلی', debugShowCheckedModeBanner: false,
    locale: const Locale('fa'), supportedLocales: const [Locale('fa'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildAppTheme(),
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
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProfileSheet(store: store),
  );
  return saved == true;
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.store});
  final EducationStore store;
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final form = GlobalKey<FormState>();
  late final TextEditingController fullName;
  late final TextEditingController field;
  late final TextEditingController goal;
  late String grade;
  late String year;
  bool saving = false;
  bool shareProfileWithAi = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final current = widget.store.profile ?? {};
    shareProfileWithAi = current['aiProfileContextConsent'] == true;
    fullName = TextEditingController(text: current['fullName']?.toString() ?? current['nickname']?.toString() ?? '');
    field = TextEditingController(text: current['field']?.toString() ?? 'عمومی');
    goal = TextEditingController(text: current['goal']?.toString() ?? '');
    grade = gradeYears.containsKey(current['grade']) ? current['grade'].toString() : 'متوسطه اول';
    year = gradeYears[grade]!.contains(current['year']) ? current['year'].toString() : gradeYears[grade]!.first;
  }

  @override
  void dispose() {
    fullName.dispose();
    field.dispose();
    goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() { saving = true; error = null; });
    try {
      await widget.store.saveProfile({...?widget.store.profile, 'fullName': fullName.text.trim(), 'nickname': fullName.text.trim().split(RegExp(r'\s+')).first, 'grade': grade, 'year': year,
        'field': field.text.trim(), 'goal': goal.text.trim(),
        'aiProfileContextConsent': shareProfileWithAi, 'privacyVersion': 3});
      if (mounted) Navigator.pop(context, true);
    } on Object catch (value) {
      if (mounted) setState(() { saving = false; error = friendlyError(value); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('به جمع همراهان سیمرغ خوش آمدی', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('برای اینکه بهتر بشناسمت و راهنمایی دقیق‌تری داشته باشم، نام و نام خانوادگی واقعی‌ات را وارد کن. نام ثبت‌شده در پروفایل فقط روی همین گوشی می‌ماند و به‌صورت خودکار برای سرویس بیرونی فرستاده نمی‌شود. توجه کن متن پرسش‌ها و پیام‌هایی که در گفت‌وگو می‌نویسی به سرویس پاسخ‌گویی ارسال می‌شوند؛ پس نام، شماره تماس یا اطلاعات شناسایی‌کننده را داخل پیام‌ها ننویس.', style: TextStyle(color: Colors.blueGrey, height: 1.7)),
          const SizedBox(height: 18),
          TextFormField(controller: fullName, maxLength: 80, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'نام و نام خانوادگی', hintText: 'مثلاً سارا احمدی'), validator: (value) { final parts = (value ?? '').trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty); return parts.length < 2 ? 'لطفاً نام و نام خانوادگی را وارد کن.' : null; }),
          DropdownButtonFormField<String>(initialValue: grade, decoration: const InputDecoration(labelText: 'مقطع تحصیلی'),
            items: gradeYears.keys.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: saving ? null : (value) { if (value != null) setState(() { grade = value; year = gradeYears[value]!.first; }); }),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(key: ValueKey(grade), initialValue: year, decoration: const InputDecoration(labelText: 'پایه تحصیلی'),
            items: gradeYears[grade]!.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: saving ? null : (value) { if (value != null) setState(() => year = value); }),
          const SizedBox(height: 14),
          TextFormField(controller: field, maxLength: 80, decoration: const InputDecoration(labelText: 'رشته یا زمینه مورد علاقه'),
            validator: (value) => value == null || value.trim().isEmpty ? 'رشته یا «عمومی» را بنویس.' : null),
          TextFormField(controller: goal, maxLines: 2, maxLength: 300, decoration: const InputDecoration(labelText: 'هدف تحصیلی (اختیاری)')),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: shareProfileWithAi,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: saving ? null : (value) => setState(() => shareProfileWithAi = value ?? false),
            title: const Text('اجازه استفاده سیمرغ از زمینه تحصیلی'),
            subtitle: const Text('در صورت فعال‌سازی، مقطع، پایه، رشته و هدف تحصیلی برای شخصی‌سازی پاسخ ارسال می‌شوند. نام و نام خانوادگی ارسال نمی‌شود. این انتخاب اختیاری است و هر زمان می‌توانی آن را لغو کنی.'),
          ),
          if (error != null) NoticeCard(text: error!, warning: true),
          const SizedBox(height: 12),
          FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'در حال ذخیره…' : 'ذخیره پروفایل')),
        ],
      ))),
    ));
  }
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
        const SimorghMark(size: 116),
        const SizedBox(height: 18),
        const Text('سیمرغ', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: navy)),
        const SizedBox(height: 6),
        const Text('همراه دانای راه آینده', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: teal)),
        const SizedBox(height: 5),
        const Text('مشاور هوشمند تحصیلی', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey)),
        const SizedBox(height: 24),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('سخنی با اولیا و دانش‌آموزان گرامی', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('برنامه مطالعه، نمرات، فلش‌کارت‌ها و سابقه مشاوره روی همین گوشی ذخیره می‌شوند. '
              'برای پاسخ‌گویی سیمرغ، متن پرسش و بخش‌هایی از گفت‌وگوهای اخیر به یک سرویس بیرونی ارسال می‌شوند. زمینه پروفایل تحصیلی فقط در صورت فعال‌کردن رضایت جداگانه در ویرایش پروفایل ارسال می‌شود. '
              'در تحلیل وضعیت تحصیلی، خلاصه نمره‌ها فقط پس از زدن دکمه تحلیل ارسال می‌شود. '
              'نشانی، شماره تماس و اطلاعات حساس را در پیام‌ها وارد نکن. نام و نام خانوادگی پروفایل روی همین گوشی می‌ماند و به‌صورت خودکار ارسال نمی‌شود؛ اما هر اطلاعاتی که خودت داخل متن پرسش یا گفت‌وگو بنویسی، ممکن است به سرویس بیرونی فرستاده شود. '
              'پاسخ‌های سیمرغ ممکن است اشتباه باشند و جایگزین معلم، مشاور مدرسه یا منابع رسمی نیستند. '
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
      ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('پشتیبان‌گیری و بازیابی'), onTap: () => Navigator.pop(context, 'backup')),
      ListTile(leading: const Icon(Icons.share_outlined), title: const Text('معرفی سیمرغ به دوستان'), subtitle: const Text('ارسال لینک نصب از کافه‌بازار'), onTap: () => Navigator.pop(context, 'referral')),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('درباره برنامه و حریم خصوصی'), subtitle: Text(appVersionLabel), onTap: () => Navigator.pop(context, 'about')),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('حذف اطلاعات تحصیلی این گوشی', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(context, 'delete')),
    ])));
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'profile': await showProfileSheet(context, widget.store); refresh();
      case 'wallet': push(CreditShopPage(store: widget.store));
      case 'reports': push(ReportsPage(store: widget.store));
      case 'backup': push(BackupPage(store: widget.store));
      case 'about': push(const AboutPage());
      case 'referral': push(const ReferralPage());
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
        HomePage(store: widget.store, go: go, active: index == 0),
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
  const HomePage({super.key, required this.store, required this.go, this.active = false});
  final EducationStore store;
  final ValueChanged<int> go;
  final bool active;
  void push(BuildContext context, Widget page) => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final profile = store.profile ?? {};
    final tasks = store.tasks;
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    // Completion progress must use the completion timestamp, not task creation.
    // Older tasks without completedAt are intentionally excluded from this
    // time-bounded metric because their completion date cannot be inferred.
    final completed = tasks.where((task) {
      if (task['done'] != true) return false;
      final date = DateTime.tryParse(task['completedAt']?.toString() ?? '');
      return date != null && !date.isBefore(weekStart);
    }).toList();
    final minutes = completed.fold<int>(0, (sum, task) => sum + _safeHomeMinutes(task['minutes']));
    final now = DateTime.now();
    final dailyValue = profile['dailyMinutes'];
    final dailyMinutes = dailyValue is int ? dailyValue : 120;
    final report = buildLearningReport(exams: store.exams, tasks: tasks, cards: store.cards, now: now);
    final suggestions = dailySuggestions(report: report, tasks: tasks, deadlines: store.deadlines, now: now, dailyMinutes: dailyMinutes);
    final fullName = profile['fullName']?.toString().trim() ?? '';
    final nickname = fullName.isNotEmpty ? fullName.split(RegExp(r'\s+')).first : (profile['nickname']?.toString() ?? '');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      SimorghHomeHero(
        nickname: nickname,
        gradeLine: [
          profile['grade']?.toString() ?? '',
          profile['year'] == null ? '' : 'پایه ${profile['year']}',
          profile['field']?.toString() ?? '',
        ].where((part) => part.trim().isNotEmpty).join(' · '),
        onChat: () => go(4),
      ),
      const SizedBox(height: 14),
      CreditSummary(store: store, onShop: () => push(context, CreditShopPage(store: store))),
      const SimorghSectionTitle(
        title: 'رد پای تلاش تو',
        subtitle: 'پیشرفت را با قدم‌های خودت بسنج، نه با دیگران.',
      ),
      Row(children: [
        Expanded(child: StatCard(title: 'کارهای انجام‌شده', value: '${faNumber(tasks.where((task) => task['done'] == true).length)}/${faNumber(tasks.length)}', icon: Icons.task_alt)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(title: 'آزمون‌ها', value: faNumber(store.exams.length), icon: Icons.assessment_outlined)),
        const SizedBox(width: 8),
        Expanded(child: StatCard(title: 'فلش‌کارت‌ها', value: faNumber(store.cards.length), icon: Icons.style_outlined)),
      ]),
      const SizedBox(height: 4),
      NoticeCard(
        text: 'هفت روز اخیر: ${faNumber(completed.length)} کار تکمیل شده؛ '
            '${faNumber(minutes)} دقیقه زمان برای این کارها برنامه‌ریزی شده است.',
        icon: Icons.insights_outlined,
      ),
      const SimorghSectionTitle(
        title: 'پیشنهاد امروز سیمرغ',
        subtitle: 'یک پیشنهاد کوچک و متناسب با مسیر فعلی تو.',
      ),
      SimorghCompanion(
        tasks: tasks,
        cards: store.cards,
        grade: profile['grade']?.toString() ?? '',
        active: active,
        onAction: (action) => go(switch (action) {
          SimorghAction.planner => 1,
          SimorghAction.review => 3,
          SimorghAction.advisor => 4,
        }),
        onChat: () => go(4),
      ),
      for (final tip in suggestions) NoticeCard(text: tip, icon: Icons.lightbulb_outline),
      const SimorghSectionTitle(
        title: 'ابزارهای مسیر یادگیری',
        subtitle: 'هر بار یک مسیر را انتخاب کن؛ لازم نیست همه کارها را هم‌زمان انجام بدهی.',
      ),
      QuickTile(icon: Icons.auto_awesome, title: 'گفت‌وگو با مشاور هوشمند', subtitle: 'پرسش، برنامه مطالعه و روش بهبود', onTap: () => go(4)),
      QuickTile(icon: Icons.share_outlined, title: 'معرفی سیمرغ به دوستان', subtitle: 'ارسال لینک نصب برنامه برای هم‌کلاسی‌ها و دوستان', onTap: () => push(context, const ReferralPage())),
      QuickTile(icon: Icons.insights_outlined, title: 'بررسی وضعیت تحصیلی', subtitle: 'نقاط قوت و ضعف بر اساس نمره‌های تو', onTap: () => push(context, AcademicInsightsPage(store: store))),
      QuickTile(icon: Icons.auto_awesome, title: 'مربی یادگیری شخصی', subtitle: 'پیشنهاد قدم بعدی بر اساس برنامه، نمره‌ها و مرورها', onTap: () => push(context, LearningCoachPage(store: store))),
      QuickTile(icon: Icons.people_outline, title: 'گزارش برای خانواده', subtitle: 'پیش‌نمایش و کپی خلاصه پیشرفت با انتخاب خودت', onTap: () => push(context, FamilyProgressReportPage(store: store))),
      QuickTile(icon: Icons.query_stats_outlined, title: 'تحلیل عملکرد و پایبندی', subtitle: 'روند درس‌ها و ساعت مطالعه، فقط از داده‌های خودت', onTap: () => push(context, AnalyticsPage(store: store))),
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: teal.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: navy, size: 19),
          ),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: navy)),
          const SizedBox(height: 3),
          Text(title, textAlign: TextAlign.center, maxLines: 2,
            style: const TextStyle(fontSize: 10, height: 1.35, color: Color(0xFF617387))),
        ],
      ),
    ),
  );
}

class QuickTile extends StatelessWidget {
  const QuickTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      minVerticalPadding: 10,
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6F4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: teal, size: 22),
      ),
      title: Text(title, style: const TextStyle(
        fontWeight: FontWeight.w800, color: navy, height: 1.5,
      )),
      subtitle: Text(subtitle, style: const TextStyle(
        height: 1.6, color: Color(0xFF617387), fontSize: 12,
      )),
      trailing: const Icon(Icons.chevron_left, color: Color(0xFF617387)),
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('درباره سیمرغ')),
    body: ListView(padding: const EdgeInsets.all(16), children: const [
      Center(child: SimorghMark(size: 104)),
      SizedBox(height: 14),
      Center(child: Text('سیمرغ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: navy))),
      Center(child: Text('همراه دانای راه آینده', style: TextStyle(color: teal, fontWeight: FontWeight.w700))),
      SizedBox(height: 14),
      NoticeCard(text: '$appVersionLabel\nشناسه برنامه: ir.moshaver.tahsili', icon: Icons.auto_awesome),
      NoticeCard(text: 'اطلاعات تحصیلی و کیف اعتبار محلی هستند و به حساب کاربری یا سرور اختصاصی فرستاده نمی‌شوند. '
          'فقط گفت‌وگو با سیمرغ و عملیات خرید بازار به اینترنت نیاز دارند. نام و نام خانوادگی ثبت‌شده در پروفایل به‌صورت خودکار ارسال نمی‌شود؛ اما متن پرسش و بخشی از گفت‌وگو، از جمله هر اطلاعات هویتی که خودت داخل پیام بنویسی، و اطلاعات تحصیلیِ مجازشده در هر درخواست با سرویس پاسخ‌گویی بیرونی به اشتراک گذاشته می‌شوند.'),
      NoticeCard(text: 'اعتبار و خریدها با امضای بازار و دفتر محلی بررسی می‌شوند، اما این بررسی جایگزین اعتبارسنجی سمت سرور نیست. '
          'داده گوشی قابل دستکاری است و اعتبار بین دستگاه‌ها منتقل نمی‌شود. کلید اتصال سرویس پاسخ‌گویی که در APK قرار می‌گیرد نیز قابل استخراج است.'),
      NoticeCard(text: 'پاسخ سیمرغ ممکن است اشتباه باشد. تصمیم‌های مهم تحصیلی را با معلم، مشاور مدرسه و منابع رسمی بررسی کن. '
          'این برنامه تشخیص پزشکی یا روان‌شناختی ارائه نمی‌دهد.'),
      NoticeCard(text: 'فونت Vazirmatn فقط در صورت موجود بودن روی دستگاه به‌کار می‌رود؛ فایل آن داخل APK بسته‌بندی نشده و در غیر این صورت فونت جایگزین دستگاه نمایش داده می‌شود. مجوز برنامه MIT است.'),
    ]));
}
