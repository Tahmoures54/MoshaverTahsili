import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

String newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, required this.store, required this.changed});
  final EducationStore store;
  final VoidCallback changed;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  static const dailyChoices = [60, 90, 120, 150];
  bool saving = false;

  Future<void> mutate(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try { await action(); widget.changed(); } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally { if (mounted) setState(() => saving = false); }
  }

  int get dailyMinutes {
    final value = widget.store.profile?['dailyMinutes'];
    return value is int && dailyChoices.contains(value) ? value : 120;
  }

  Future<void> add() async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => const _TaskDialog());
    if (result != null && mounted) {
      await mutate(() => widget.store.addTask({
        'id': newId('task'), 'title': result['title']!,
        'subject': result['subject']!.isEmpty ? 'عمومی' : result['subject'],
        'minutes': int.parse(digitsToEnglish(result['minutes']!)), 'done': false,
        'dueDate': isoDay(DateTime.now()),
        'createdAt': DateTime.now().toIso8601String(),
      }));
    }
  }

  Future<void> addDeadline() async {
    final subject = await showDialog<String>(context: context, builder: (_) => const _DeadlineDialog());
    if (subject == null || !mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now,
        lastDate: now.add(const Duration(days: 730)), helpText: 'تاریخ امتحان');
    if (picked == null || !mounted) return;
    await mutate(() => widget.store.addDeadline({'id': newId('deadline'), 'subject': subject, 'date': isoDay(picked)}));
  }

  Future<void> setDailyMinutes(int minutes) => mutate(() =>
      widget.store.saveProfile({...?widget.store.profile, 'dailyMinutes': minutes}));

  Future<void> smartPlan() async {
    final plan = buildAdaptivePlan(
      tasks: widget.store.tasks,
      exams: widget.store.exams,
      deadlines: widget.store.deadlines,
      today: DateTime.now(),
      dailyMinutes: dailyMinutes,
      restWeekdays: const {DateTime.friday},
    );
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanReportDialog(plan: plan),
    );
    if (accepted != true || !mounted) return;
    await mutate(() => widget.store.applyPlanDates(
      plan.assignments,
      changes: plan.changes,
      now: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.tasks;
    final deadlines = widget.store.deadlines;
    final minutes = tasks.fold<int>(0, (sum, item) => sum + ((item['minutes'] as num?)?.toInt() ?? 0));
    return Scaffold(backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: saving ? null : add, icon: const Icon(Icons.add), label: const Text('افزودن برنامه')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 92), children: [
        NoticeCard(text: '${faNumber(minutes)} دقیقه مطالعه برنامه‌ریزی کرده‌ای. کارهای کوچک و قابل انجام انتخاب کن.', icon: Icons.timer_outlined),
        if (widget.store.dataError('edu.tasks') != null) NoticeCard(text: widget.store.dataError('edu.tasks')!, warning: true),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ساعت مطالعه روزانه', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final choice in dailyChoices)
              ChoiceChip(label: Text('${faNumber(choice)} دقیقه'), selected: dailyMinutes == choice,
                  onSelected: saving ? null : (_) => setDailyMinutes(choice)),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: saving ? null : smartPlan, icon: const Icon(Icons.auto_fix_high_outlined), label: const Text('ساخت برنامه هوشمند')),
          const SizedBox(height: 8),
          const Text('جمعه‌ها روز استراحت است. برنامه بر اساس نمره‌های ثبت‌شده، امتحان‌های پیش‌رو و موعد کارها ساخته می‌شود و علت هر تغییر نمایش داده می‌شود.',
              style: TextStyle(fontSize: 12.5, height: 1.7)),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 6, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('امتحان‌های پیش‌رو', style: TextStyle(fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: saving ? null : addDeadline, icon: const Icon(Icons.flag_outlined), label: const Text('ثبت امتحان')),
          ]),
          if (deadlines.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 10), child: Text('امتحانی ثبت نشده است.')),
          for (final deadline in deadlines) ListTile(
            title: Text(deadline['subject'].toString()),
            subtitle: Text(faNumber(deadline['date'])),
            trailing: IconButton(tooltip: 'حذف امتحان', icon: const Icon(Icons.delete_outline),
                onPressed: saving ? null : () => mutate(() => widget.store.deleteDeadline(deadline['id'].toString()))),
          ),
        ]))),
        if (tasks.isEmpty) const EmptyState(title: 'از یک قدم کوچک شروع کنیم', subtitle: 'اولین کار درسی‌ات را اضافه کن و پس از انجام، تیک بزن.', icon: Icons.event_note),
        for (final task in tasks) Card(child: CheckboxListTile(value: task['done'] == true,
          onChanged: saving ? null : (_) => mutate(() => widget.store.toggleTask(task['id'].toString())),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(task['title'].toString(), style: TextStyle(fontWeight: FontWeight.bold,
              decoration: task['done'] == true ? TextDecoration.lineThrough : null)),
          subtitle: Text('${task['subject']} · ${faNumber(task['minutes'] ?? 0)} دقیقه'
              '${task['dueDate'] == null ? '' : ' · ${faNumber(task['dueDate'])}'}'),
          secondary: IconButton(tooltip: 'حذف برنامه', icon: const Icon(Icons.delete_outline),
              onPressed: saving ? null : () => mutate(() => widget.store.deleteTask(task['id'].toString()))))),
      ]));
  }
}

class _DeadlineDialog extends StatefulWidget {
  const _DeadlineDialog();
  @override
  State<_DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<_DeadlineDialog> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController();
  @override
  void dispose() { subject.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('امتحان پیش‌رو'),
    content: SizedBox(width: 420, child: Form(key: form, child: TextFormField(controller: subject, maxLength: 80,
        decoration: const InputDecoration(labelText: 'نام درس'),
        validator: (v) => v == null || v.trim().isEmpty ? 'نام درس را بنویس.' : null))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, subject.text.trim()); }, child: const Text('ادامه'))]);
}

class _PlanReportDialog extends StatelessWidget {
  const _PlanReportDialog({required this.plan});
  final AdaptivePlan plan;
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('برنامه هوشمند ساخته شد'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${faNumber(plan.assignments.length)} کار زمان‌بندی شد.'),
      if (plan.changes.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('تغییری نسبت به تاریخ‌های قبلی لازم نبود.')),
      for (final change in plan.changes) Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(change.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('تاریخ جدید: ${faNumber(change.newDate)}'),
        Text(change.reason, style: const TextStyle(height: 1.7)),
      ])),
      if (plan.unplacedIds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(
          '${faNumber(plan.unplacedIds.length)} کار در افق ۱۴ روزه جا نشد. مدت آن‌ها را کوتاه‌تر کن یا ساعت مطالعه روزانه را بالاتر ببر.',
          style: const TextStyle(color: Colors.red, height: 1.7))),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('فعلاً نه')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعمال برنامه')),
    ]);
}

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key, required this.store, required this.changed});
  final EducationStore store;
  final VoidCallback changed;
  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  bool saving = false;
  Future<void> mutate(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try { await action(); widget.changed(); } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> add() async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => const _ExamDialog());
    if (result != null && mounted) {
      await mutate(() => widget.store.addExam({'id': newId('exam'),
        'subject': result['subject']!, 'score': double.parse(digitsToEnglish(result['score']!)),
        'max': double.parse(digitsToEnglish(result['max']!)), 'createdAt': DateTime.now().toIso8601String()}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exams = widget.store.exams;
    final percentages = exams.map(examPercentage).whereType<double>().toList();
    final average = percentages.isEmpty ? 0.0 : percentages.reduce((a, b) => a + b) / percentages.length;
    return Scaffold(backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: saving ? null : add, icon: const Icon(Icons.add), label: const Text('ثبت نمره')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 92), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          const Text('میانگین درصدهای ثبت‌شده'), const SizedBox(height: 8),
          Text(exams.isEmpty ? 'هنوز داده‌ای نداریم' : '${faNumber(average.toStringAsFixed(1))}٪',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: blue)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: average / 100, minHeight: 7, borderRadius: BorderRadius.circular(8)),
        ]))),
        const NoticeCard(text: 'نمره‌ها فقط روی گوشی می‌مانند. برای تحلیل نقاط قوت و ضعف، از خانه بخش «بررسی وضعیت تحصیلی» را باز کن.'),
        if (exams.isEmpty) const EmptyState(title: 'کارنامه‌ات را کامل کنیم', subtitle: 'نتیجه اولین آزمون را ثبت کن.', icon: Icons.assessment_outlined),
        for (final exam in exams) Card(child: ListTile(title: Text(exam['subject'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('نمره ${faNumber(exam['score'] ?? '')} از ${faNumber(exam['max'] ?? '')}'),
          trailing: IconButton(tooltip: 'حذف نمره', icon: const Icon(Icons.delete_outline),
              onPressed: saving ? null : () => mutate(() => widget.store.deleteExam(exam['id'].toString()))))),
      ]));
  }
}

double? examPercentage(Map<String, dynamic> exam) => examPercent(exam);

class CardsPage extends StatefulWidget {
  const CardsPage({super.key, required this.store, required this.changed});
  final EducationStore store;
  final VoidCallback changed;
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  String? revealed;
  bool saving = false;
  Future<void> mutate(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try { await action(); widget.changed(); } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> add() async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => const _CardDialog());
    if (result != null && mounted) {
      await mutate(() => widget.store.addCard({'id': newId('card'),
        'q': result['q']!, 'a': result['a']!, 'interval': 0, 'ease': 2.5, 'reps': 0, 'lapses': 0,
        'dueAt': DateTime.now().toIso8601String()}));
    }
  }

  /// Quality follows SM-2: 1 forgot, 3 hard, 4 good, 5 easy.
  Future<void> review(Map<String, dynamic> card, int quality) async {
    await mutate(() => widget.store.reviewCard(card['id'].toString(), quality, DateTime.now()));
    if (mounted) setState(() => revealed = null);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.store.cards;
    final now = DateTime.now();
    final due = cards.where((card) => isCardDue(card, now)).length;
    return Scaffold(backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: saving ? null : add, icon: const Icon(Icons.add), label: const Text('ساخت فلش‌کارت')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 92), children: [
        NoticeCard(text: '${faNumber(cards.length)} فلش‌کارت · ${faNumber(due)} آماده مرور. کارت‌هایی که سخت بوده‌اند زودتر و کارت‌های مسلط با فاصله بیشتر دوباره نشان داده می‌شوند.', icon: Icons.psychology_alt_outlined),
        if (widget.store.dataError('edu.cards') != null) NoticeCard(text: widget.store.dataError('edu.cards')!, warning: true),
        if (cards.isEmpty) const EmptyState(title: 'یادگیری را ماندگار کنیم', subtitle: 'یک پرسش و پاسخ کوتاه بساز و در فاصله‌های مناسب مرور کن.', icon: Icons.style_outlined),
        for (final card in cards) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SelectableText(card['q'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, height: 1.7)),
          if (revealed == card['id']) ...[const Divider(), SelectableText(card['a'].toString(), style: const TextStyle(height: 1.8)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: saving ? null : () => review(card, 1), child: const Text('دوباره')),
              OutlinedButton(onPressed: saving ? null : () => review(card, 3), child: const Text('سخت بود')),
              FilledButton(onPressed: saving ? null : () => review(card, 4), child: const Text('یاد گرفتم')),
              FilledButton.tonal(onPressed: saving ? null : () => review(card, 5), child: const Text('خیلی آسان')),
            ]),
          ] else Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => revealed = card['id'].toString()), child: const Text('نمایش پاسخ'))),
          Align(alignment: Alignment.centerLeft, child: IconButton(tooltip: 'حذف فلش‌کارت', icon: const Icon(Icons.delete_outline),
              onPressed: saving ? null : () => mutate(() => widget.store.deleteCard(card['id'].toString())))),
        ]))),
      ]));
  }
}

class StudyTipsPage extends StatelessWidget {
  const StudyTipsPage({super.key});
  static const tips = [
    ('مطالعه فعال', 'بعد از خواندن، کتاب را ببند و با زبان خودت توضیح بده چه یاد گرفته‌ای. از حافظه پاسخ بده، نه فقط از روی متن.', 'پس از هر بخش، سه پرسش کوتاه طرح کن.'),
    ('مرور فاصله‌دار', 'مرور را به شب امتحان موکول نکن. کارت‌های دشوار را زودتر و مطالب مسلط را با فاصله بیشتر مرور کن.', 'یک مرور کوتاه فردا و مرور بعدی چند روز بعد انجام بده.'),
    ('بازه‌های تمرکز', 'بازه ۲۵ دقیقه مطالعه و ۵ دقیقه استراحت یک نقطه شروع است؛ آن را با توان و شرایط خودت تنظیم کن.', 'اعلان‌ها را خاموش کن و در استراحت از جای خود بلند شو.'),
    ('خلاصه‌نویسی مفهومی', 'خلاصه خوب رونویسی نیست. رابطه‌ها، تفاوت مفاهیم و مثال‌های مهم را با کلمات خودت ثبت کن.', 'برای هر فصل یک صفحه نکته و یک مثال حل‌شده بنویس.'),
    ('آمادگی برای امتحان', 'نمونه‌سؤال حل کن و اشتباه‌ها را به بی‌دقتی، ضعف مفهوم، فراموشی و کمبود زمان دسته‌بندی کن.', 'برای هر اشتباه یک تمرین مشابه حل کن.'),
    ('تعادل و آرامش', 'خواب کافی، غذا، آب و حرکت بدنی بخشی از یادگیری‌اند. برنامه بدون استراحت پایدار نمی‌ماند.', 'بین بازه‌های سنگین، استراحت واقعی قرار بده.'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('روش‌های مؤثر مطالعه')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const NoticeCard(text: 'این راهنمای عمومی و آفلاین است. روش مناسب را با توجه به درس، سن و شرایط خودت انتخاب کن.', icon: Icons.menu_book_outlined),
      for (final tip in tips) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tip.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Text(tip.$2, style: const TextStyle(height: 1.8)),
        const SizedBox(height: 10), Text('تمرین پیشنهادی: ${tip.$3}', style: const TextStyle(color: teal, height: 1.7)),
      ]))),
    ]));
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog();
  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final subject = TextEditingController();
  final duration = TextEditingController(text: '۳۰');
  @override
  void dispose() { title.dispose(); subject.dispose(); duration.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('یک قدم تازه برای مطالعه'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'چه کاری می‌خواهی انجام بدهی؟'),
          validator: (v) => v == null || v.trim().isEmpty ? 'عنوان کار را بنویس.' : null),
      const SizedBox(height: 10),
      TextFormField(controller: subject, maxLength: 80, decoration: const InputDecoration(labelText: 'درس (اختیاری)')),
      TextFormField(controller: duration, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'زمان مطالعه به دقیقه'),
          validator: (v) { final n = int.tryParse(digitsToEnglish(v ?? '')); return n == null || n < 1 || n > 1440 ? 'زمان باید بین ۱ تا ۱۴۴ دقیقه باشد.' : null; }),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, {'title': title.text.trim(), 'subject': subject.text.trim(), 'minutes': duration.text}); }, child: const Text('افزودن'))]);
}

class _ExamDialog extends StatefulWidget {
  const _ExamDialog();
  @override
  State<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends State<_ExamDialog> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController();
  final score = TextEditingController();
  final max = TextEditingController(text: '۲۰');
  @override
  void dispose() { subject.dispose(); score.dispose(); max.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('ثبت نتیجه آزمون'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: subject, maxLength: 80, decoration: const InputDecoration(labelText: 'نام درس'),
          validator: (v) => v == null || v.trim().isEmpty ? 'نام درس را بنویس.' : null),
      TextFormField(controller: score, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نمره کسب‌شده'),
          validator: (v) { final s = double.tryParse(digitsToEnglish(v ?? '')); final m = double.tryParse(digitsToEnglish(max.text));
            return s == null || !s.isFinite || m == null || !m.isFinite || m <= 0 || m > 1000 || s < 0 || s > m ? 'نمره باید بین صفر و نمره کل باشد.' : null; }),
      const SizedBox(height: 12),
      TextFormField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نمره کل')),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, {'subject': subject.text.trim(), 'score': score.text, 'max': max.text}); }, child: const Text('ثبت نمره'))]);
}

class _CardDialog extends StatefulWidget {
  const _CardDialog();
  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  final form = GlobalKey<FormState>();
  final q = TextEditingController();
  final a = TextEditingController();
  @override
  void dispose() { q.dispose(); a.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('فلش‌کارت جدید'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: q, maxLines: 2, maxLength: 1000, decoration: const InputDecoration(labelText: 'پرسش'),
          validator: (v) => v == null || v.trim().isEmpty ? 'پرسش را بنویس.' : null),
      TextFormField(controller: a, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(labelText: 'پاسخ'),
          validator: (v) => v == null || v.trim().isEmpty ? 'پاسخ را بنویس.' : null),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, {'q': q.text.trim(), 'a': a.text.trim()}); }, child: const Text('ذخیره'))]);
}
