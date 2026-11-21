
import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_advisor_service.dart';
import 'credit_shop_page.dart';
import 'education_store.dart';
import 'study_pages.dart';
import 'ui.dart';

// -----------------------------------------------------------------------------
// Safe data helpers
// -----------------------------------------------------------------------------

int _safeCount(Object? value) {
  if (value is int && value >= 0) return value;

  if (value is num && value.isFinite && value >= 0) {
    return value.toInt();
  }

  final parsed = int.tryParse(
    digitsToEnglish(value?.toString() ?? ''),
  );

  return parsed != null && parsed >= 0 ? parsed : 0;
}

double _safePercentage(Object? value) {
  if (value is! num || !value.isFinite) return 0;

  return value.toDouble().clamp(0.0, 100.0).toDouble();
}

String _safeText(Object? value, {String fallback = ''}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

// -----------------------------------------------------------------------------
// Academic insights
// -----------------------------------------------------------------------------

class AcademicInsightsPage extends StatefulWidget {
  const AcademicInsightsPage({
    super.key,
    required this.store,
    this.service,
  });

  final EducationStore store;
  final AiAdvisorService? service;

  @override
  State<AcademicInsightsPage> createState() =>
      _AcademicInsightsPageState();
}

class _AcademicInsightsPageState extends State<AcademicInsightsPage> {
  String? question;

  Map<String, ({double average, int count})> subjects() {
    final result = <String, ({double average, int count})>{};

    for (final exam in widget.store.exams) {
      final rawPercentage = examPercentage(exam);

      if (rawPercentage is! num || !rawPercentage.isFinite) {
        continue;
      }

      final percentage = _safePercentage(rawPercentage);

      final subject = _safeText(exam['subject']);

      if (subject.isEmpty || subject.length > 80) {
        continue;
      }

      final previous = result[subject];
      final count = (previous?.count ?? 0) + 1;

      final previousTotal =
          (previous?.average ?? 0) * (count - 1);

      result[subject] = (
        average: (previousTotal + percentage) / count,
        count: count,
      );
    }

    return result;
  }

  void analyze() {
    if (question != null) return;

    final entries = subjects().entries.toList()
      ..sort(
        (a, b) => b.value.average.compareTo(a.value.average),
      );

    final selected = entries.take(20).toList();

    final tasks = widget.store.tasks;

    final done = tasks.where(
      (task) => task['done'] == true,
    ).length;

    final summary = selected.map((entry) {
      return '${entry.key}: میانگین '
          '${entry.value.average.toStringAsFixed(1)} درصد '
          'از ${entry.value.count} آزمون';
    }).join('؛ ');

    final request = 'وضعیت تحصیلی ثبت‌شده من را تحلیل کن. '
        'اطلاعات درس‌ها: $summary. '
        'تعداد کارهای مطالعه: ${tasks.length}، '
        'انجام‌شده: $done. '
        'این آمار محدود است و آزمون روان‌سنجی نیست. '
        'نقاط قوت و ضعف احتمالی، روش بهبود، مسیر مطالعه '
        'و یک برنامه هفتگی واقع‌بینانه با استراحت پیشنهاد بده. '
        'کمبود داده را صریح بگو و نتیجه قطعی یا تضمین آینده نده. '
        'از برچسب‌زنی درباره استعداد یا توانایی قطعی دانش‌آموز '
        'خودداری کن.';

    setState(() => question = request);
  }

  @override
  Widget build(BuildContext context) {
    final entries = subjects().entries.toList()
      ..sort(
        (a, b) => b.value.average.compareTo(a.value.average),
      );

    final tasks = widget.store.tasks;

    final done = tasks.where(
      (task) => task['done'] == true,
    ).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بررسی وضعیت تحصیلی'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const NoticeCard(
            text: 'این بخش ابتدا داده‌های خودت را روی گوشی خلاصه می‌کند. '
                'تحلیل سیمرغ فقط با درخواست آگاهانه تو انجام می‌شود. '
                'پاسخ جایگزین ارزیابی معلم یا مشاور مدرسه نیست.',
          ),

          CreditSummary(
            store: widget.store,
            onShop: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreditShopPage(
                    store: widget.store,
                  ),
                ),
              );
            },
          ),

          if (entries.isEmpty)
            const EmptyState(
              title: 'برای بررسی، نمره لازم داریم',
              subtitle: 'از بخش آزمون، نتیجه دست‌کم یک درس را ثبت کن.',
              icon: Icons.insights_outlined,
            ),

          for (final entry in entries)
            _subjectCard(entry),

          if (tasks.isNotEmpty)
            NoticeCard(
              text: '${faNumber(done)} کار از '
                  '${faNumber(tasks.length)} کار مطالعه انجام شده است. '
                  'این نسبت، میزان یادگیری یا کیفیت مطالعه را به‌تنهایی '
                  'اندازه نمی‌گیرد.',
              icon: Icons.task_alt,
            ),

          if (entries.isNotEmpty && question == null) ...[
            const NoticeCard(
              text: 'با انتخاب دکمه زیر، خلاصه نمره‌ها و اطلاعات '
                  'مجازشده تحصیلی برای تحلیل به سرویس بیرونی ارسال می‌شود. '
                  'اطلاعات ارسالی به اندازه نیاز تحلیل محدود شده‌اند. '
                  'این درخواست پس از پاسخ موفق یک پر سیمرغ مصرف می‌کند.',
              icon: Icons.privacy_tip_outlined,
            ),

            FilledButton.icon(
              onPressed: analyze,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('دریافت تحلیل و برنامه پیشنهادی'),
            ),
          ],

          if (question != null)
            ConsultationRunner(
              store: widget.store,
              service: widget.service,
              kind: 'academic',
              title: 'تحلیل وضعیت تحصیلی',
              question: question!,
            ),
        ],
      ),
    );
  }

  Widget _subjectCard(
    MapEntry<String, ({double average, int count})> entry,
  ) {
    final average = _safePercentage(entry.value.average);

    final hasEnoughEvidence = entry.value.count >= 2;

    final description = !hasEnoughEvidence
        ? 'شواهد اولیه؛ برای بررسی روند آزمون بیشتری لازم است'
        : average >= 75
            ? 'میانگین فعلی بالاتر است'
            : average < 60
                ? 'نیازمند بررسی و تمرین بیشتر'
                : 'نیازمند ادامه تمرین و بررسی روند';

    return Card(
      child: ListTile(
        leading: Icon(
          average >= 75
              ? Icons.trending_up
              : Icons.flag_outlined,
          color: average >= 75 ? teal : blue,
        ),
        title: Text(
          entry.key,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${faNumber(entry.value.count)} آزمون · $description',
        ),
        trailing: Text(
          '${faNumber(average.toStringAsFixed(0))}٪',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Career guidance
// -----------------------------------------------------------------------------

class CareerPage extends StatefulWidget {
  const CareerPage({
    super.key,
    required this.store,
    this.service,
  });

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

  bool saving = false;

  @override
  void initState() {
    super.initState();

    final draft = widget.store.careerDraft ?? {};

    interests = TextEditingController(
      text: draft['interests']?.toString() ?? '',
    );

    strengths = TextEditingController(
      text: draft['strengths']?.toString() ?? '',
    );

    favorites = TextEditingController(
      text: draft['favorites']?.toString() ?? '',
    );

    workStyle = TextEditingController(
      text: draft['workStyle']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    interests.dispose();
    strengths.dispose();
    favorites.dispose();
    workStyle.dispose();
    super.dispose();
  }

  Future<void> analyze() async {
    if (saving || question != null) return;

    if (!(form.currentState?.validate() ?? false)) {
      return;
    }

    final draft = <String, String>{
      'interests': interests.text.trim(),
      'strengths': strengths.text.trim(),
      'favorites': favorites.text.trim(),
      'workStyle': workStyle.text.trim(),
    };

    setState(() {
      saving = true;
      error = null;
    });

    try {
      await widget.store.saveCareerDraft(draft);

      if (!mounted) return;

      final request = _buildCareerQuestion(draft);

      setState(() {
        question = request;
        saving = false;
      });
    } on Object catch (value) {
      if (!mounted) return;

      setState(() {
        error = friendlyError(value);
        saving = false;
      });
    }
  }

  String _buildCareerQuestion(Map<String, String> draft) {
    return 'برای راهنمای انتخاب رشته، این اطلاعات خوداظهاری را '
        'بررسی کن: '
        'علاقه‌ها: ${draft['interests']}. '
        'توانایی‌های خوداظهاری: ${draft['strengths']}. '
        'درس‌های مورد علاقه: ${draft['favorites']}. '
        'سبک فعالیت مورد علاقه: ${draft['workStyle']}. '
        'این گفت‌وگو آزمون استاندارد RIASEC یا سنجش استعداد نیست. '
        'از منطق CIP برای تعریف مسئله، شناخت گزینه‌ها، مقایسه '
        'و برنامه اقدام استفاده کن. '
        'از پرسش‌های علاقه‌محور الهام‌گرفته از RIASEC فقط '
        'برای کاوش فعالیت‌ها استفاده کن، نه نمره‌سازی یا برچسب شخصیت. '
        'خودکارآمدی، تجربه موفقیت، حمایت‌های موجود و موانع احتمالی '
        'را با احتیاط بررسی کن و اگر داده کم است سؤال تکمیلی بپرس. '
        '۲ تا ۴ گزینه شامل مسیرهای نظری، فنی‌وحرفه‌ای و مهارتی '
        'مرتبط را در صورت تناسب معرفی کن. '
        'برای هر گزینه دلیل ارتباط با گفته‌های من، مزایا، دشواری‌ها، '
        'اطلاعات نامعلوم و یک آزمایش کوچک مانند پروژه یا گفت‌وگو '
        'با فرد آگاه پیشنهاد بده. '
        'علاقه را با توانایی یکی نگیر؛ نمره را معادل استعداد ندان؛ '
        'از کلیشه جنسیتی، طبقاتی و منطقه‌ای پرهیز کن. '
        'شرایط رسمی هدایت تحصیلی، ظرفیت منطقه، بازار کار و مقررات '
        'متغیر را حدس نزن؛ اگر منبع رسمی به‌روز در اختیار نداری، '
        'آن را نیازمند بررسی اعلام کن. '
        'در پایان یک تصمیم موقت و قابل بازنگری بده، نه حکم قطعی؛ '
        'بررسی با مشاور مدرسه و خانواده را یادآوری کن.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('راهنمای انتخاب رشته'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const NoticeCard(
            text: 'این پرسش‌نامه برای شناخت گزینه‌هاست، نه تشخیص قطعی استعداد. '
                'پاسخ‌ها روی گوشی ذخیره می‌شوند و هنگام درخواست تحلیل '
                'به سرویس پاسخ‌گویی بیرونی فرستاده می‌شوند.',
          ),

          CreditSummary(
            store: widget.store,
            onShop: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreditShopPage(
                    store: widget.store,
                  ),
                ),
              );
            },
          ),

          if (error != null)
            NoticeCard(
              text: error!,
              warning: true,
            ),

          Form(
            key: form,
            child: Column(
              children: [
                _field(
                  controller: interests,
                  label: 'به چه فعالیت‌ها و موضوع‌هایی علاقه داری؟',
                  required: true,
                ),

                _field(
                  controller: strengths,
                  label: 'در چه کارهایی احساس توانمندی می‌کنی؟',
                ),

                _field(
                  controller: favorites,
                  label: 'کدام درس‌ها را بیشتر دوست داری یا بهتر یاد می‌گیری؟',
                  required: true,
                ),

                _field(
                  controller: workStyle,
                  label: 'کار عملی، پژوهشی، هنری یا ارتباط با مردم را ترجیح می‌دهی؟',
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          FilledButton.icon(
            onPressed: saving || question != null ? null : analyze,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.explore_outlined),
            label: Text(
              saving
                  ? 'در حال ذخیره اطلاعات…'
                  : 'بررسی مسیرهای تحصیلی',
            ),
          ),

          const SizedBox(height: 12),

          if (question != null)
            ConsultationRunner(
              key: ValueKey(question),
              store: widget.store,
              service: widget.service,
              kind: 'career',
              title: 'راهنمای انتخاب رشته',
              question: question!,
            ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: 3,
        maxLength: 600,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
        ),
        validator: (value) {
          if (required &&
              (value == null || value.trim().isEmpty)) {
            return 'این بخش را کوتاه هم که شده کامل کن.';
          }

          return null;
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Consultation runner
// -----------------------------------------------------------------------------

/// Manages one logical consultation.
///
/// The same request ID is reused for retries.
/// Actual provider-side idempotency and wallet transaction guarantees
/// must be implemented by AiAdvisorService and its backend.
class ConsultationRunner extends StatefulWidget {
  const ConsultationRunner({
    super.key,
    required this.store,
    required this.kind,
    required this.title,
    required this.question,
    this.service,
    this.existingId,
    this.savedAnswer,
    this.autoStart = true,
  });

  final EducationStore store;
  final AiAdvisorService? service;

  final String kind;
  final String title;
  final String question;

  final String? existingId;
  final String? savedAnswer;

  final bool autoStart;

  @override
  State<ConsultationRunner> createState() =>
      _ConsultationRunnerState();
}

class _ConsultationRunnerState extends State<ConsultationRunner> {
  late final AiAdvisorService service =
      widget.service ?? AiAdvisorService(store: widget.store);

  late final String id =
      widget.existingId ?? newId('report');

  late String? answer = widget.savedAnswer;

  String? error;

  bool busy = false;

  bool _disposeServiceWhenFinished = false;

  @override
  void initState() {
    super.initState();

    if (widget.autoStart && answer == null) {
      unawaited(run());
    }
  }

  @override
  void dispose() {
    // Do not dispose an internally owned service while its request
    // is still running. It must finish and persist its result first.
    if (widget.service == null) {
      if (busy) {
        _disposeServiceWhenFinished = true;
      } else {
        service.dispose();
      }
    }

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistent report storage
  // ---------------------------------------------------------------------------

  Future<void> save(
    String status, {
    String? answer,
  }) async {
    final reports = List<Map<String, dynamic>>.from(
      widget.store.reports,
    );

    final index = reports.indexWhere(
      (report) => report['id'] == id,
    );

    final previous = index >= 0 ? reports[index] : null;

    final now = DateTime.now().toIso8601String();

    final report = <String, dynamic>{
      'id': id,
      'kind': widget.kind,
      'title': widget.title,
      'question': widget.question,
      'status': status,

      // Preserve the original creation time across status updates.
      'createdAt': previous?['createdAt'] ?? now,

      'updatedAt': now,

      if (answer != null) 'answer': answer,
    };

    if (index >= 0) {
      reports[index] = report;
    } else {
      reports.insert(0, report);
    }

    await widget.store.writeList(
      'edu.reports',
      reports.take(50).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Request execution
  // ---------------------------------------------------------------------------

  Future<void> run() async {
    if (busy || answer != null) return;

    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    } else {
      return;
    }

    try {
      // Persist pending state before contacting the provider.
      await save('pending');

      final result = await service.ask(
        profile: widget.store.profile,
        history: const [],
        question: widget.question,
        requestId: id,
      );

      // Persist the actual response even if the user has navigated away.
      await save(
        'completed',
        answer: result,
      );

      if (!mounted) return;

      setState(() {
        answer = result;
        error = null;
      });
    } on Object catch (value) {
      // Never fabricate an answer after a failed request.
      if (mounted) {
        setState(() {
          error = friendlyError(value);
        });
      }

      try {
        await save('failed');
      } on Object {
        // Preserve the original error.
        // The request may still be recoverable through its service ledger.
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }

      if (_disposeServiceWhenFinished &&
          widget.service == null) {
        service.dispose();
        _disposeServiceWhenFinished = false;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Presentation
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('در حال بررسی اطلاعات تو…'),
                  ],
                ),
              ),

            if (error != null) ...[
              NoticeCard(
                text: error!,
                warning: true,
              ),

              OutlinedButton.icon(
                onPressed: busy || answer != null ? null : run,
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'تلاش دوباره همین درخواست',
                ),
              ),
            ],

            if (answer != null) ...[
              SelectableText(
                answer!,
                style: const TextStyle(
                  height: 1.9,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'پاسخ سیمرغ · در تاریخچه مشاوره‌ها ذخیره شد',
                style: TextStyle(
                  color: teal,
                  fontSize: 12,
                ),
              ),
            ],

            if (!busy && answer == null && error == null)
              FilledButton(
                onPressed: run,
                child: const Text(
                  'ادامه درخواست ذخیره‌شده',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Consultation history
// -----------------------------------------------------------------------------

class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه مشاوره‌ها'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final reports = store.reports;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NoticeCard(
                text: 'پاسخ‌های واقعی دریافت‌شده روی گوشی نگهداری می‌شوند. '
                    'درخواست ناموفق پاسخ ساختگی ندارد و از همین‌جا قابل ادامه است.',
              ),

              if (reports.isEmpty)
                const EmptyState(
                  title: 'هنوز گزارشی نداری',
                  subtitle: 'تحلیل وضعیت تحصیلی یا راهنمای انتخاب رشته '
                      'را از خانه شروع کن.',
                  icon: Icons.history_edu_outlined,
                ),

              for (final report in reports)
                _reportCard(
                  context,
                  report,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _reportCard(
    BuildContext context,
    Map<String, dynamic> report,
  ) {
    final title = _safeText(
      report['title'],
      fallback: 'مشاوره بدون عنوان',
    );

    final id = _safeText(report['id']);

    final status = _safeText(report['status']);

    final answer = report['answer'];

    final question = report['question'];

    final completed = status == 'completed';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                completed
                    ? 'پاسخ دریافت و ذخیره شده'
                    : status == 'pending'
                        ? 'درخواست در انتظار تکمیل است'
                        : 'درخواست کامل نشده',
              ),
              trailing: IconButton(
                tooltip: 'حذف گزارش',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  try {
                    await store.deleteReport(id);
                  } on Object catch (error) {
                    if (context.mounted) {
                      showMessage(
                        context,
                        friendlyError(error),
                      );
                    }
                  }
                },
              ),
            ),

            if (answer is String && answer.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('نمایش پاسخ'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      answer,
                      style: const TextStyle(
                        height: 1.8,
                      ),
                    ),
                  ),
                ],
              ),

            if (!completed && question is String && question.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('ادامه درخواست'),
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: Text(title),
                        ),
                        body: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            ConsultationRunner(
                              store: store,
                              kind: _safeText(
                                report['kind'],
                                fallback: 'academic',
                              ),
                              title: title,
                              question: question,
                              existingId: id,
                              autoStart: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
