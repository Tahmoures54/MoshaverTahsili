import 'dart:async';

import 'package:flutter/material.dart';
import 'ai_advisor_service.dart';
import 'credit_shop_page.dart';
import 'education_store.dart';
import 'study_pages.dart';
import 'ui.dart';

class AcademicInsightsPage extends StatefulWidget {
  const AcademicInsightsPage({super.key, required this.store, this.service});
  final EducationStore store;
  final AiAdvisorService? service;
  @override
  State<AcademicInsightsPage> createState() => _AcademicInsightsPageState();
}

class _AcademicInsightsPageState extends State<AcademicInsightsPage> {
  String? question;
  Map<String, ({double average, int count})> subjects() {
    final result = <String, ({double average, int count})>{};
    for (final exam in widget.store.exams) {
      final percentage = examPercentage(exam);
      if (percentage == null) continue;
      final subject = exam['subject']?.toString().trim() ?? '';
      if (subject.isEmpty || subject.length > 80) continue;
      final previous = result[subject];
      final count = (previous?.count ?? 0) + 1;
      result[subject] = (average: ((previous?.average ?? 0) * (count - 1) + percentage) / count, count: count);
    }
    return result;
  }

  void analyze() {
    final entries = subjects().entries.toList()..sort((a, b) => b.value.average.compareTo(a.value.average));
    final selected = entries.take(20).toList();
    final tasks = widget.store.tasks;
    final done = tasks.where((task) => task['done'] == true).length;
    final summary = selected.map((entry) => '${entry.key}: میانگین ${entry.value.average.toStringAsFixed(1)} درصد از ${entry.value.count} آزمون').join('؛ ');
    setState(() => question = 'وضعیت تحصیلی ثبت‌شده من را تحلیل کن. $summary. '
        'تعداد کارهای مطالعه: ${tasks.length}، انجام‌شده: $done. '
        'این آمار محدود است و آزمون روان‌سنجی نیست. نقاط قوت و ضعف احتمالی، روش بهبود، مسیر مطالعه و یک برنامه هفتگی واقع‌بینانه با استراحت پیشنهاد بده. '
        'کمبود داده را صریح بگو و نتیجه قطعی یا تضمین آینده نده.');
  }

  @override
  Widget build(BuildContext context) {
    final entries = subjects().entries.toList()..sort((a, b) => b.value.average.compareTo(a.value.average));
    final tasks = widget.store.tasks;
    final done = tasks.where((task) => task['done'] == true).length;
    return Scaffold(appBar: AppBar(title: const Text('بررسی وضعیت تحصیلی')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const NoticeCard(text: 'این بخش ابتدا داده‌های خودت را روی گوشی خلاصه می‌کند. تحلیل هوش مصنوعی فقط با دکمه زیر و پس از ارسال خلاصه نمره‌ها انجام می‌شود؛ پاسخ جایگزین ارزیابی معلم یا مشاور مدرسه نیست.'),
        CreditSummary(store: widget.store, onShop: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CreditShopPage(store: widget.store)))),
        if (entries.isEmpty) const EmptyState(title: 'برای بررسی، نمره لازم داریم', subtitle: 'از بخش آزمون، نتیجه دست‌کم یک درس را ثبت کن.', icon: Icons.insights_outlined),
        for (final entry in entries) Card(child: ListTile(
          leading: Icon(entry.value.average >= 75 ? Icons.trending_up : Icons.flag_outlined, color: entry.value.average >= 75 ? teal : blue),
          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${faNumber(entry.value.count)} آزمون · ${entry.value.average >= 75 ? 'نقطه قوت فعلی' : entry.value.average < 60 ? 'نیازمند تمرین بیشتر' : 'در حال پیشرفت'}'),
          trailing: Text('${faNumber(entry.value.average.toStringAsFixed(0))}٪', style: const TextStyle(fontWeight: FontWeight.bold)),
        )),
        if (tasks.isNotEmpty) NoticeCard(text: '${faNumber(done)} کار از ${faNumber(tasks.length)} کار مطالعه انجام شده است. این نسبت، میزان تلاش واقعی یا یادگیری را به‌تنهایی اندازه نمی‌گیرد.', icon: Icons.task_alt),
        if (entries.isNotEmpty && question == null) ...[
          const NoticeCard(text: 'با زدن دکمه زیر، نام درس‌ها و میانگین نمره‌ها، تعداد کارهای مطالعه و پروفایل تحصیلی به سرویس هوش مصنوعی ارسال می‌شود. این درخواست پس از پاسخ موفق یک اعتبار مصرف می‌کند.', icon: Icons.privacy_tip_outlined),
          FilledButton.icon(onPressed: analyze, icon: const Icon(Icons.auto_awesome), label: const Text('دریافت تحلیل و برنامه پیشنهادی')),
        ],
        if (question != null) ConsultationRunner(store: widget.store, service: widget.service,
            kind: 'academic', title: 'تحلیل وضعیت تحصیلی', question: question!),
      ]));
  }
}

class CareerPage extends StatefulWidget {
  const CareerPage({super.key, required this.store, this.service});
  final EducationStore store;
  final AiAdvisorService? service;
  @override
  State<CareerPage> createState() => _CareerPageState();
}

class _CareerPageState extends State<CareerPage> {
  late final TextEditingController interests;
  late final TextEditingController strengths;
  late final TextEditingController favorites;
  late final TextEditingController workStyle;
  final form = GlobalKey<FormState>();
  String? question;
  String? error;

  @override
  void initState() {
    super.initState();
    final draft = widget.store.careerDraft ?? {};
    interests = TextEditingController(text: draft['interests']?.toString() ?? '');
    strengths = TextEditingController(text: draft['strengths']?.toString() ?? '');
    favorites = TextEditingController(text: draft['favorites']?.toString() ?? '');
    workStyle = TextEditingController(text: draft['workStyle']?.toString() ?? '');
  }
  @override
  void dispose() { interests.dispose(); strengths.dispose(); favorites.dispose(); workStyle.dispose(); super.dispose(); }

  Future<void> analyze() async {
    if (!form.currentState!.validate()) return;
    final draft = {'interests': interests.text.trim(), 'strengths': strengths.text.trim(),
      'favorites': favorites.text.trim(), 'workStyle': workStyle.text.trim()};
    try { await widget.store.saveCareerDraft(draft); } on Object catch (value) {
      setState(() => error = friendlyError(value)); return;
    }
    if (!mounted) return;
    setState(() { error = null; question = 'برای راهنمای انتخاب رشته، این اطلاعات را بررسی کن: '
        'علاقه‌ها: ${draft['interests']}. توانایی‌های خوداظهاری: ${draft['strengths']}. '
        'درس‌های مورد علاقه: ${draft['favorites']}. سبک فعالیت مورد علاقه: ${draft['workStyle']}. '
        'چند مسیر تحصیلی متناسب را با دلیل، نقاط قوت و ضعف، دشواری‌ها و قدم بعدی معرفی کن. '
        'سؤال تکمیلی بپرس، هیچ رشته‌ای را قطعی تجویز نکن و بررسی با مشاور مدرسه و منابع رسمی را یادآوری کن.'; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('راهنمای انتخاب رشته')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const NoticeCard(text: 'این پرسش‌نامه برای شناخت گزینه‌هاست، نه تشخیص قطعی استعداد. پاسخ‌ها روی گوشی ذخیره می‌شوند و هنگام درخواست تحلیل به سرویس هوش مصنوعی فرستاده می‌شوند.'),
      CreditSummary(store: widget.store, onShop: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CreditShopPage(store: widget.store)))),
      if (error != null) NoticeCard(text: error!, warning: true),
      Form(key: form, child: Column(children: [
        for (final field in [
          (interests, 'به چه فعالیت‌ها و موضوع‌هایی علاقه داری؟', true),
          (strengths, 'در چه کارهایی احساس توانمندی می‌کنی؟', false),
          (favorites, 'کدام درس‌ها را بیشتر دوست داری یا بهتر یاد می‌گیری؟', true),
          (workStyle, 'کار عملی، پژوهشی، هنری یا ارتباط با مردم را ترجیح می‌دهی؟', false),
        ]) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
          controller: field.$1, maxLines: 3, maxLength: 600,
          decoration: InputDecoration(labelText: field.$2),
          validator: (value) => field.$3 && (value == null || value.trim().isEmpty) ? 'این بخش را کوتاه هم که شده کامل کن.' : null,
        )),
      ])),
      FilledButton.icon(onPressed: analyze, icon: const Icon(Icons.explore_outlined), label: const Text('بررسی مسیرهای تحصیلی')),
      const SizedBox(height: 12),
      if (question != null) ConsultationRunner(key: ValueKey(question.hashCode), store: widget.store, service: widget.service,
          kind: 'career', title: 'راهنمای انتخاب رشته', question: question!),
    ]));
}

/// Persists the logical request ID before sending. Retrying a completed report
/// retrieves its saved answer; it does not call the provider or charge again.
class ConsultationRunner extends StatefulWidget {
  const ConsultationRunner({super.key, required this.store, required this.kind,
    required this.title, required this.question, this.service, this.existingId,
    this.savedAnswer, this.autoStart = true});
  final EducationStore store;
  final AiAdvisorService? service;
  final String kind, title, question;
  final String? existingId, savedAnswer;
  final bool autoStart;
  @override
  State<ConsultationRunner> createState() => _ConsultationRunnerState();
}

class _ConsultationRunnerState extends State<ConsultationRunner> {
  late final AiAdvisorService service = widget.service ?? AiAdvisorService(store: widget.store);
  late final String id = widget.existingId ?? newId('report');
  late String? answer = widget.savedAnswer;
  String? error;
  bool busy = false;

  @override
  void initState() { super.initState(); if (widget.autoStart && answer == null) unawaited(run()); }
  @override
  void dispose() { service.dispose(); super.dispose(); }

  Future<void> save(String status, {String? answer}) async {
    final reports = widget.store.reports;
    final report = {'id': id, 'kind': widget.kind, 'title': widget.title,
      'question': widget.question, 'status': status, 'createdAt': DateTime.now().toIso8601String(),
      if (answer != null) 'answer': answer};
    final index = reports.indexWhere((report) => report['id'] == id);
    if (index >= 0) { reports[index] = report; } else { reports.insert(0, report); }
    await widget.store.writeList('edu.reports', reports.take(50).toList());
  }

  Future<void> run() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await save('pending');
      final result = await service.ask(profile: widget.store.profile, history: const [],
          question: widget.question, requestId: id);
      if (!mounted) return;
      setState(() => answer = result);
      await save('completed', answer: result);
    } on Object catch (value) {
      if (mounted) setState(() => error = friendlyError(value));
      try { await save('failed'); } on Object { /* Preserve wallet; never fabricate a report. */ }
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (busy) const Padding(padding: EdgeInsets.all(16), child: Column(children: [
        CircularProgressIndicator(), SizedBox(height: 12), Text('در حال بررسی اطلاعات تو…'),
      ])),
      if (error != null) ...[NoticeCard(text: error!, warning: true),
        OutlinedButton.icon(onPressed: busy ? null : run, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره همین درخواست'))],
      if (answer != null) ...[SelectableText(answer!, style: const TextStyle(height: 1.9)),
        const SizedBox(height: 12), const Text('پاسخ هوش مصنوعی · در تاریخچه مشاوره‌ها ذخیره شد', style: TextStyle(color: teal, fontSize: 12))],
      if (!busy && answer == null && error == null)
        FilledButton(onPressed: run, child: const Text('ادامه درخواست ذخیره‌شده')),
    ])));
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});
  final EducationStore store;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('تاریخچه مشاوره‌ها')),
    body: ListenableBuilder(listenable: store, builder: (context, _) {
      final reports = store.reports;
      return ListView(padding: const EdgeInsets.all(16), children: [
        const NoticeCard(text: 'پاسخ‌های واقعی دریافت‌شده روی گوشی نگهداری می‌شوند. درخواست ناموفق پاسخ ساختگی ندارد و از همین‌جا قابل ادامه است.'),
        if (reports.isEmpty) const EmptyState(title: 'هنوز گزارشی نداری', subtitle: 'تحلیل وضعیت تحصیلی یا راهنمای انتخاب رشته را از خانه شروع کن.', icon: Icons.history_edu_outlined),
        for (final report in reports) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          ListTile(title: Text(report['title'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(report['status'] == 'completed' ? 'پاسخ دریافت و ذخیره شده' : 'درخواست کامل نشده'),
            trailing: IconButton(tooltip: 'حذف گزارش', icon: const Icon(Icons.delete_outline), onPressed: () async {
              try { await store.deleteReport(report['id'].toString()); } on Object catch (error) {
                if (context.mounted) showMessage(context, friendlyError(error));
              }
            })),
          if (report['answer'] != null) ExpansionTile(title: const Text('نمایش پاسخ'),
            children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(report['answer'].toString(), style: const TextStyle(height: 1.8)))]),
          if (report['status'] != 'completed') TextButton.icon(icon: const Icon(Icons.refresh), label: const Text('ادامه درخواست'), onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => Scaffold(
            appBar: AppBar(title: Text(report['title'].toString())),
            body: ListView(padding: const EdgeInsets.all(16), children: [ConsultationRunner(store: store,
              kind: report['kind'].toString(), title: report['title'].toString(), question: report['question'].toString(),
              existingId: report['id'].toString(), autoStart: false)]),
          )))),
        ]))),
      ]);
    }));
}
