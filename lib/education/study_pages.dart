import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'mastery_estimator.dart';
import 'ui.dart';

int _idSequence = 0;

/// Creates a readable, collision-resistant ID within this Dart isolate.
/// The timestamp also makes collisions unlikely across normal app restarts.
String newId(String prefix) {
  _idSequence++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
}

const int _maxTaskMinutes = 1440;

int _safeTaskMinutes(Map<String, dynamic> task) {
  final value = task['minutes'];

  if (value is num && value.isFinite && value >= 0) {
    return value.clamp(0, _maxTaskMinutes).toInt();
  }

  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());

  if (parsed == null || parsed < 0) return 0;

  return parsed.clamp(0, _maxTaskMinutes).toInt();
}

String _safeLabel(Object? value, {String fallback = 'بدون عنوان'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == 'null' ? fallback : text;
}

String _recordId(Map<String, dynamic> record) {
  final id = record['id']?.toString().trim() ?? '';
  return id == 'null' ? '' : id;
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;

  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;

  return DateTime.tryParse(text);
}

String _formatDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return 'بدون تاریخ';

  return faNumber(text);
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'حذف',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.7)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('انصراف'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result == true;
}

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
    if (!mounted || saving) return;

    setState(() => saving = true);

    try {
      await action();

      if (mounted) {
        widget.changed();
      }
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  int get dailyMinutes {
    final value = widget.store.profile?['dailyMinutes'];

    final parsed = value is num
        ? (value.isFinite ? value.toInt() : null)
        : int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());

    return parsed != null && dailyChoices.contains(parsed) ? parsed : 120;
  }

  Future<void> add() async {
    if (saving) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _TaskDialog(),
    );

    if (result == null || !mounted) return;

    final title = result['title']?.trim() ?? '';
    final subject = result['subject']?.trim() ?? '';
    final minutes = int.tryParse(
      digitsToEnglish(result['minutes'] ?? '').trim(),
    );

    if (title.isEmpty ||
        minutes == null ||
        minutes < 1 ||
        minutes > _maxTaskMinutes) {
      showMessage(context, 'اطلاعات برنامه معتبر نیست. دوباره تلاش کن.');
      return;
    }

    final now = DateTime.now();

    await mutate(
      () => widget.store.addTask({
        'id': newId('task'),
        'title': title,
        'subject': subject.isEmpty ? 'عمومی' : subject,
        'minutes': minutes,
        'done': false,
        'dueDate': isoDay(now),
        'createdAt': now.toIso8601String(),
      }),
    );
  }

  Future<void> addDeadline() async {
    if (saving) return;

    final subject = await showDialog<String>(
      context: context,
      builder: (_) => const _DeadlineDialog(),
    );

    if (subject == null || !mounted) return;

    final normalizedSubject = subject.trim();

    if (normalizedSubject.isEmpty) {
      showMessage(context, 'نام درس را بنویس.');
      return;
    }

    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      helpText: 'تاریخ امتحان',
    );

    if (picked == null || !mounted) return;

    await mutate(
      () => widget.store.addDeadline({
        'id': newId('deadline'),
        'subject': normalizedSubject,
        'date': isoDay(picked),
      }),
    );
  }

  Future<void> deleteDeadline(Map<String, dynamic> deadline) async {
    if (saving) return;

    final subject = _safeLabel(deadline['subject'], fallback: 'این امتحان');

    final confirmed = await _confirmDelete(
      context,
      title: 'حذف امتحان',
      message: '«$subject» از فهرست امتحان‌ها حذف شود؟',
    );

    if (!confirmed || !mounted) return;

    final id = _recordId(deadline);

    if (id.isEmpty) {
      showMessage(context, 'شناسه امتحان معتبر نیست.');
      return;
    }

    await mutate(() => widget.store.deleteDeadline(id));
  }

  Future<void> deleteTask(Map<String, dynamic> task) async {
    if (saving) return;

    final title = _safeLabel(task['title'], fallback: 'این برنامه');

    final confirmed = await _confirmDelete(
      context,
      title: 'حذف برنامه',
      message: 'برنامه «$title» حذف شود؟ این کار قابل بازگشت نیست.',
    );

    if (!confirmed || !mounted) return;

    final id = _recordId(task);

    if (id.isEmpty) {
      showMessage(context, 'شناسه برنامه معتبر نیست.');
      return;
    }

    await mutate(() => widget.store.deleteTask(id));
  }

  Future<void> setDailyMinutes(int minutes) {
    if (!dailyChoices.contains(minutes)) {
      return Future<void>.value();
    }

    return mutate(
      () => widget.store.saveProfile({
        ...?widget.store.profile,
        'dailyMinutes': minutes,
      }),
    );
  }

  Future<void> smartPlan() async {
    if (saving) return;

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

    await mutate(
      () => widget.store.applyPlanDates(
        plan.assignments,
        changes: plan.changes,
        now: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.tasks;
    final deadlines = widget.store.deadlines;

    final minutes = tasks.fold<int>(
      0,
      (sum, item) => sum + _safeTaskMinutes(item),
    );

    final completed = tasks.where((task) => task['done'] == true).length;

    final pending = tasks.length - completed;
    final tasksError = widget.store.dataError('edu.tasks');

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: saving ? null : add,
        icon: const Icon(Icons.add),
        label: const Text('افزودن برنامه'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        children: [
          NoticeCard(
            text:
                '${faNumber(minutes)} دقیقه زمان برای برنامه‌ها ثبت کرده‌ای؛ '
                '${faNumber(completed)} کار انجام‌شده و '
                '${faNumber(pending)} کار باقی‌مانده. '
                'برنامه را متناسب با توان و زمان واقعی خودت نگه دار.',
            icon: Icons.timer_outlined,
          ),
          if (tasksError != null) NoticeCard(text: tasksError, warning: true),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'زمان مطالعه روزانه',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in dailyChoices)
                        ChoiceChip(
                          label: Text('${faNumber(choice)} دقیقه'),
                          selected: dailyMinutes == choice,
                          onSelected: saving
                              ? null
                              : (_) => setDailyMinutes(choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : smartPlan,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('ساخت برنامه هوشمند'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'جمعه‌ها روز استراحت است. برنامه با توجه به '
                    'نمره‌های ثبت‌شده، امتحان‌های پیش‌رو و موعد کارها '
                    'پیشنهاد می‌شود. پیش از اعمال، تغییرها را بررسی می‌کنی.',
                    style: TextStyle(fontSize: 12.5, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'امتحان‌های پیش‌رو',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: saving ? null : addDeadline,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('ثبت امتحان'),
                      ),
                    ],
                  ),
                  if (deadlines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                      child: Text('امتحانی ثبت نشده است.'),
                    ),
                  for (final deadline in deadlines)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        _safeLabel(deadline['subject'], fallback: 'درس نامشخص'),
                      ),
                      subtitle: Text('تاریخ: ${_formatDate(deadline['date'])}'),
                      trailing: IconButton(
                        tooltip: 'حذف امتحان',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: saving
                            ? null
                            : () => deleteDeadline(deadline),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (tasks.isEmpty)
            const EmptyState(
              title: 'از یک قدم کوچک شروع کنیم',
              subtitle: 'اولین کار درسی‌ات را اضافه کن و پس از انجام، تیک بزن.',
              icon: Icons.event_note,
            ),
          for (final task in tasks)
            Card(
              child: CheckboxListTile(
                value: task['done'] == true,
                onChanged: saving || _recordId(task).isEmpty
                    ? null
                    : (_) => mutate(
                        () => widget.store.toggleTask(_recordId(task)),
                      ),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  _safeLabel(task['title']),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    decoration: task['done'] == true
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${_safeLabel(task['subject'], fallback: 'عمومی')} · '
                  '${faNumber(_safeTaskMinutes(task))} دقیقه'
                  '${task['dueDate'] == null ? '' : ' · ${_formatDate(task['dueDate'])}'}',
                ),
                secondary: IconButton(
                  tooltip: 'حذف برنامه',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: saving ? null : () => deleteTask(task),
                ),
              ),
            ),
        ],
      ),
    );
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
  void dispose() {
    subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('امتحان پیش‌رو'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: TextFormField(
            controller: subject,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'نام درس'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'نام درس را بنویس.'
                : null,
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState?.validate() == true) {
            Navigator.pop(context, subject.text.trim());
          }
        },
        child: const Text('ادامه'),
      ),
    ],
  );
}

class _PlanReportDialog extends StatelessWidget {
  const _PlanReportDialog({required this.plan});

  final AdaptivePlan plan;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('پیش‌نمایش برنامه هوشمند'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${faNumber(plan.assignments.length)} کار در برنامه بررسی شد.',
            ),
            if (plan.changes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('تغییری نسبت به تاریخ‌های قبلی لازم نبود.'),
              ),
            for (final change in plan.changes)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      change.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('تاریخ پیشنهادی: ${faNumber(change.newDate)}'),
                    Text(change.reason, style: const TextStyle(height: 1.7)),
                  ],
                ),
              ),
            if (plan.unplacedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${faNumber(plan.unplacedIds.length)} کار '
                  'در افق ۱۴ روزه جا نشد. '
                  'می‌توانی حجم کارها را خردتر کنی یا '
                  'زمان مطالعه روزانه را بازبینی کنی.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    height: 1.7,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('فعلاً نه'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('اعمال برنامه'),
      ),
    ],
  );
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
    if (!mounted || saving) return;

    setState(() => saving = true);

    try {
      await action();

      if (mounted) {
        widget.changed();
      }
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> add() async {
    if (saving) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ExamDialog(),
    );

    if (result == null || !mounted) return;

    final score = double.tryParse(
      digitsToEnglish(result['score'] ?? '').trim(),
    );

    final max = double.tryParse(digitsToEnglish(result['max'] ?? '').trim());

    final subject = result['subject']?.trim() ?? '';

    if (subject.isEmpty ||
        score == null ||
        max == null ||
        !score.isFinite ||
        !max.isFinite ||
        max <= 0 ||
        max > 1000 ||
        score < 0 ||
        score > max) {
      showMessage(context, 'اطلاعات نمره معتبر نیست. دوباره بررسی کن.');
      return;
    }

    await mutate(
      () => widget.store.addExam({
        'id': newId('exam'),
        'subject': subject,
        'score': score,
        'max': max,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> deleteExam(Map<String, dynamic> exam) async {
    if (saving) return;

    final subject = _safeLabel(exam['subject'], fallback: 'این نتیجه');

    final confirmed = await _confirmDelete(
      context,
      title: 'حذف نتیجه آزمون',
      message: 'نتیجه ثبت‌شده درس «$subject» حذف شود؟',
    );

    if (!confirmed || !mounted) return;

    final id = _recordId(exam);

    if (id.isEmpty) {
      showMessage(context, 'شناسه نتیجه آزمون معتبر نیست.');
      return;
    }

    await mutate(() => widget.store.deleteExam(id));
  }

  @override
  Widget build(BuildContext context) {
    final exams = widget.store.exams;

    final percentages = exams
        .map(examPercentage)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();

    final average = percentages.isEmpty
        ? 0.0
        : percentages.reduce((a, b) => a + b) / percentages.length;

    final examsError = widget.store.dataError('edu.exams');

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: saving ? null : add,
        icon: const Icon(Icons.add),
        label: const Text('ثبت نمره'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('میانگین درصد آزمون‌های معتبر'),
                  const SizedBox(height: 8),
                  Text(
                    percentages.isEmpty
                        ? 'هنوز داده‌ای نداریم'
                        : '${faNumber(average.toStringAsFixed(1))}٪',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (average / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${faNumber(percentages.length)} آزمون '
                    'در محاسبه لحاظ شده است. '
                    'این میانگین، میانگین ساده درصد آزمون‌هاست '
                    'و به‌تنهایی معیار استعداد یا تسلط نیست.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.blueGrey,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const NoticeCard(
            text:
                'نمره‌ها به‌صورت محلی روی گوشی نگهداری می‌شوند. '
                'برای بررسی دقیق‌تر نقاط قوت و بخش‌های نیازمند تمرین، '
                'از خانه بخش «بررسی وضعیت تحصیلی» را باز کن.',
          ),
          if (examsError != null) NoticeCard(text: examsError, warning: true),
          if (exams.isEmpty)
            const EmptyState(
              title: 'کارنامه‌ات را کامل کنیم',
              subtitle:
                  'نتیجه اولین آزمون را ثبت کن؛ '
                  'یک نمره، فقط یک شاهد از مسیر یادگیری است.',
              icon: Icons.assessment_outlined,
            ),
          for (final exam in exams)
            Card(
              child: ListTile(
                title: Text(
                  _safeLabel(exam['subject']),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'نمره ${faNumber(exam['score'] ?? '')} '
                  'از ${faNumber(exam['max'] ?? '')}'
                  '${exam['createdAt'] == null ? '' : ' · ${_formatDate(exam['createdAt'].toString().split('T').first)}'}',
                ),
                trailing: IconButton(
                  tooltip: 'حذف نمره',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: saving ? null : () => deleteExam(exam),
                ),
              ),
            ),
        ],
      ),
    );
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

  Future<bool> mutate(Future<void> Function() action) async {
    if (!mounted || saving) return false;

    setState(() => saving = true);

    try {
      await action();

      if (mounted) {
        widget.changed();
      }

      return true;
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }

      return false;
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> add() async {
    if (saving) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _CardDialog(),
    );

    if (result == null || !mounted) return;

    final question = result['q']?.trim() ?? '';
    final answer = result['a']?.trim() ?? '';
    final topic = result['topic']?.trim() ?? '';

    if (question.isEmpty || answer.isEmpty) {
      showMessage(context, 'پرسش و پاسخ فلش‌کارت نباید خالی باشند.');
      return;
    }

    await mutate(
      () => widget.store.addCard({
        'id': newId('card'),
        'q': question,
        'a': answer,
        'topic': topic,
        'interval': 0,
        'ease': 2.5,
        'reps': 0,
        'lapses': 0,
        'dueAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// SM-2 quality scale: 1 = forgot, 3 = hard, 4 = good, 5 = easy.
  Future<void> review(Map<String, dynamic> card, int quality) async {
    if (saving) return;

    final id = _recordId(card);

    if (id.isEmpty || quality < 0 || quality > 5) {
      showMessage(context, 'اطلاعات مرور فلش‌کارت معتبر نیست.');
      return;
    }

    final success = await mutate(
      () => widget.store.reviewCard(id, quality, DateTime.now()),
    );

    if (mounted && success && revealed == id) {
      setState(() => revealed = null);
    }
  }

  Future<void> deleteCard(Map<String, dynamic> card) async {
    if (saving) return;

    final confirmed = await _confirmDelete(
      context,
      title: 'حذف فلش‌کارت',
      message: 'این فلش‌کارت و سابقه مرور محلی آن حذف شود؟',
    );

    if (!confirmed || !mounted) return;

    final id = _recordId(card);

    if (id.isEmpty) {
      showMessage(context, 'شناسه فلش‌کارت معتبر نیست.');
      return;
    }

    final success = await mutate(() => widget.store.deleteCard(id));

    if (mounted && success && revealed == id) {
      setState(() => revealed = null);
    }
  }

  void revealCard(Map<String, dynamic> card) {
    if (!mounted || saving) return;

    final id = _recordId(card);

    if (id.isEmpty) {
      showMessage(context, 'شناسه فلش‌کارت معتبر نیست.');
      return;
    }

    setState(() => revealed = id);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.store.cards;
    final now = DateTime.now();

    final due = cards.where((card) => isCardDue(card, now)).length;

    final topicEvidence = estimateTopicMastery(cards);
    final cardsError = widget.store.dataError('edu.cards');

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: saving ? null : add,
        icon: const Icon(Icons.add),
        label: const Text('ساخت فلش‌کارت'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        children: [
          NoticeCard(
            text:
                '${faNumber(cards.length)} فلش‌کارت داری؛ '
                '${faNumber(due)} کارت آماده مرور است. '
                'کارت‌های دشوار زودتر و کارت‌هایی که آسان‌تر '
                'به یاد می‌آیند با فاصله بیشتر مرور می‌شوند.',
            icon: Icons.psychology_alt_outlined,
          ),
          if (topicEvidence.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'شواهد یادآوری بر اساس مبحث',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'این شاخص از مرورهای ثبت‌شده فلش‌کارت‌ها '
                      'برآورد می‌شود؛ نتیجه امتحان یا '
                      'اثبات تسلط کامل نیست.',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                    for (final item in topicEvidence)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.topic,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${faNumber((item.estimate * 100).round())}٪',
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            LinearProgressIndicator(
                              value: item.estimate.clamp(0.0, 1.0).toDouble(),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${faNumber(item.evidenceCount)} مرور · '
                              '${item.confidence} · '
                              'بازه تقریبی '
                              '${faNumber((item.lowerBound * 100).round())} '
                              'تا '
                              '${faNumber((item.upperBound * 100).round())}٪',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (cardsError != null) NoticeCard(text: cardsError, warning: true),
          if (cards.isEmpty)
            const EmptyState(
              title: 'یادگیری را ماندگار کنیم',
              subtitle:
                  'یک پرسش و پاسخ کوتاه بساز '
                  'و در فاصله‌های مناسب مرور کن.',
              icon: Icons.style_outlined,
            ),
          for (final card in cards)
            _FlashcardTile(
              key: _recordId(card).isEmpty
                  ? ObjectKey(card)
                  : ValueKey<String>(_recordId(card)),
              card: card,
              isRevealed: revealed != null && revealed == _recordId(card),
              saving: saving,
              onReveal: () => revealCard(card),
              onReview: (quality) => review(card, quality),
              onDelete: () => deleteCard(card),
            ),
        ],
      ),
    );
  }
}

class _FlashcardTile extends StatelessWidget {
  const _FlashcardTile({
    super.key,
    required this.card,
    required this.isRevealed,
    required this.saving,
    required this.onReveal,
    required this.onReview,
    required this.onDelete,
  });

  final Map<String, dynamic> card;
  final bool isRevealed;
  final bool saving;
  final VoidCallback onReveal;
  final ValueChanged<int> onReview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final due = isCardDue(card, DateTime.now());
    final topic = _safeLabel(card['topic'], fallback: '');
    final dueAt = _parseDate(card['dueAt']);
    final hasValidId = _recordId(card).isNotEmpty;
    final canReview = !saving && hasValidId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    _safeLabel(card['q']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      height: 1.7,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  due ? Icons.notifications_active_outlined : Icons.schedule,
                  size: 19,
                  color: due ? teal : Colors.blueGrey,
                ),
              ],
            ),
            if (topic.isNotEmpty || due || dueAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (topic.isNotEmpty) topic,
                    if (due)
                      'آماده مرور'
                    else if (dueAt != null)
                      'مرور بعدی: '
                          '${_formatDate(dueAt.toLocal().toIso8601String().split('T').first)}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            if (isRevealed) ...[
              const Divider(height: 24),
              SelectableText(
                _safeLabel(card['a']),
                style: const TextStyle(height: 1.8),
              ),
              const SizedBox(height: 12),
              const Text(
                'پس از تلاش برای یادآوری، کیفیت پاسخ را انتخاب کن:',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: canReview ? () => onReview(1) : null,
                    child: const Text('فراموش کردم'),
                  ),
                  OutlinedButton(
                    onPressed: canReview ? () => onReview(3) : null,
                    child: const Text('سخت بود'),
                  ),
                  FilledButton(
                    onPressed: canReview ? () => onReview(4) : null,
                    child: const Text('خوب بود'),
                  ),
                  FilledButton.tonal(
                    onPressed: canReview ? () => onReview(5) : null,
                    child: const Text('خیلی آسان'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: canReview ? onReveal : null,
                  child: const Text('نمایش پاسخ'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'حذف فلش‌کارت',
                icon: const Icon(Icons.delete_outline),
                onPressed: saving ? null : onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StudyTipsPage extends StatelessWidget {
  const StudyTipsPage({super.key});

  static const tips = [
    (
      'مطالعه فعال',
      'بعد از خواندن، کتاب را ببند و با زبان خودت توضیح بده '
          'چه یاد گرفته‌ای. از حافظه پاسخ بده، نه فقط از روی متن.',
      'پس از هر بخش، سه پرسش کوتاه طرح کن.',
    ),
    (
      'مرور فاصله‌دار',
      'مرور را به شب امتحان موکول نکن. کارت‌های دشوار را زودتر '
          'و مطالبی را که راحت به یاد می‌آوری با فاصله بیشتر مرور کن.',
      'یک مرور کوتاه فردا و مرور بعدی چند روز بعد انجام بده.',
    ),
    (
      'بازه‌های تمرکز',
      'بازه ۲۵ دقیقه مطالعه و ۵ دقیقه استراحت یک نقطه شروع است؛ '
          'آن را با توان، سن و شرایط خودت تنظیم کن.',
      'اعلان‌ها را خاموش کن و در استراحت کمی حرکت کن.',
    ),
    (
      'خلاصه‌نویسی مفهومی',
      'خلاصه خوب رونویسی نیست. رابطه‌ها، تفاوت مفاهیم و مثال‌های '
          'مهم را با کلمات خودت ثبت کن.',
      'برای هر فصل یک صفحه نکته و یک مثال حل‌شده بنویس.',
    ),
    (
      'آمادگی برای امتحان',
      'نمونه‌سؤال حل کن و اشتباه‌ها را به ضعف مفهوم، پیش‌نیاز، '
          'روش حل، محاسبه یا بی‌دقتی دسته‌بندی کن.',
      'برای هر اشتباه، پس از فهم علت، یک تمرین مشابه حل کن.',
    ),
    (
      'تعادل و آرامش',
      'خواب کافی، غذا، آب و حرکت بدنی بخشی از یادگیری‌اند. '
          'برنامه بدون استراحت پایدار نمی‌ماند.',
      'بین بازه‌های سنگین، استراحت واقعی قرار بده.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('روش‌های مؤثر مطالعه')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const NoticeCard(
          text:
              'این راهنمای عمومی و آفلاین است. '
              'لازم نیست همه روش‌ها را هم‌زمان اجرا کنی؛ '
              'یک روش کوچک و قابل‌دوام را انتخاب کن.',
          icon: Icons.menu_book_outlined,
        ),
        for (final tip in tips)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tip.$1,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(tip.$2, style: const TextStyle(height: 1.8)),
                  const SizedBox(height: 10),
                  Text(
                    'تمرین پیشنهادی: ${tip.$3}',
                    style: const TextStyle(color: teal, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
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
  void dispose() {
    title.dispose();
    subject.dispose();
    duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('یک قدم تازه برای مطالعه'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'چه کاری می‌خواهی انجام بدهی؟',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'عنوان کار را بنویس.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: subject,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'درس (اختیاری)'),
              ),
              TextFormField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'زمان مطالعه به دقیقه',
                ),
                validator: (value) {
                  final number = int.tryParse(
                    digitsToEnglish(value ?? '').trim(),
                  );

                  return number == null ||
                          number < 1 ||
                          number > _maxTaskMinutes
                      ? 'زمان باید بین ۱ تا ۱۴۴۰ دقیقه باشد.'
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState?.validate() == true) {
            Navigator.pop(context, {
              'title': title.text.trim(),
              'subject': subject.text.trim(),
              'minutes': digitsToEnglish(duration.text.trim()),
            });
          }
        },
        child: const Text('افزودن'),
      ),
    ],
  );
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
  void dispose() {
    subject.dispose();
    score.dispose();
    max.dispose();
    super.dispose();
  }

  double? _number(String value) =>
      double.tryParse(digitsToEnglish(value).trim());

  String? _validateScore(String? value) {
    final earned = _number(value ?? '');
    final total = _number(max.text);

    if (earned == null ||
        !earned.isFinite ||
        total == null ||
        !total.isFinite ||
        total <= 0 ||
        total > 1000 ||
        earned < 0 ||
        earned > total) {
      return 'نمره باید بین صفر و نمره کل باشد.';
    }

    return null;
  }

  String? _validateMax(String? value) {
    final total = _number(value ?? '');
    final earned = _number(score.text);

    if (total == null || !total.isFinite || total <= 0 || total > 1000) {
      return 'نمره کل باید بیشتر از صفر و حداکثر ۱۰۰۰ باشد.';
    }

    if (earned != null) {
      if (!earned.isFinite || earned < 0) {
        return 'نمره کسب‌شده باید عددی معتبر و نامنفی باشد.';
      }

      if (earned > total) {
        return 'نمره کسب‌شده نباید از نمره کل بیشتر باشد.';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ثبت نتیجه آزمون'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: subject,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'نام درس'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'نام درس را بنویس.'
                    : null,
              ),
              TextFormField(
                controller: score,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'نمره کسب‌شده'),
                validator: _validateScore,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: max,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'نمره کل'),
                validator: _validateMax,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState?.validate() == true) {
            Navigator.pop(context, {
              'subject': subject.text.trim(),
              'score': digitsToEnglish(score.text.trim()),
              'max': digitsToEnglish(max.text.trim()),
            });
          }
        },
        child: const Text('ثبت نمره'),
      ),
    ],
  );
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
  final topic = TextEditingController();

  @override
  void dispose() {
    q.dispose();
    a.dispose();
    topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('فلش‌کارت جدید'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: q,
                maxLines: 2,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'پرسش'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'پرسش را بنویس.'
                    : null,
              ),
              TextFormField(
                controller: a,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'پاسخ'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'پاسخ را بنویس.'
                    : null,
              ),
              TextFormField(
                controller: topic,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'مبحث (اختیاری؛ برای گزارش یادگیری)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState?.validate() == true) {
            Navigator.pop(context, {
              'q': q.text.trim(),
              'a': a.text.trim(),
              'topic': topic.text.trim(),
            });
          }
        },
        child: const Text('ذخیره'),
      ),
    ],
  );
}
