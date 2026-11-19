import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'ai_advisor_service.dart';
import 'ai_safety_policy.dart';
import 'credit_shop_page.dart';
import 'education_store.dart';
import 'study_pages.dart' show newId;
import 'simorgh_companion.dart';
import 'simorgh_teaching_engine.dart';
import 'ui.dart';

class _TeachingTurn {
  const _TeachingTurn({required this.feedback, required this.outcome, required this.error, required this.nextQuestion});
  final String feedback;
  final SimorghAnswerOutcome outcome;
  final SimorghErrorKind error;
  final String nextQuestion;
}

class AdvisorPage extends StatefulWidget {
  const AdvisorPage({super.key, required this.store, this.service});
  final EducationStore store;
  final AiAdvisorService? service;
  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final input = TextEditingController();
  late final bool _ownsService = widget.service == null;
  late final AiAdvisorService service = widget.service ?? AiAdvisorService(store: widget.store);
  late List<Map<String, dynamic>> messages;
  bool busy = false;
  String? error;
  SimorghTeachingSession? teachingSession;
  String? teachingSessionId;

  @override
  void initState() {
    super.initState();
    messages = widget.store.messages;
    teachingSession = _restoreTeachingSession(widget.store.teachingSessions);
  }

  @override
  void dispose() {
    input.dispose();
    if (_ownsService) service.dispose();
    super.dispose();
  }

  SimorghTeachingSession? _restoreTeachingSession(List<Map<String, dynamic>> saved) {
    final active = saved.where((item) => item['active'] == true).toList();
    if (active.isEmpty) return null;
    final data = active.last;
    teachingSessionId = data['id']?.toString();
    try {
      if (data['active'] != true) return null;
      final session = SimorghTeachingEngine.start(
        topic: data['topic']?.toString() ?? '',
        grade: data['grade']?.toString() ?? '',
      );
      return session.copyWith(
        stage: SimorghTeachingStage.values.byName(data['stage']?.toString() ?? 'diagnostic'),
        diagnosticCount: data['diagnosticCount'] as int? ?? 0,
        diagnosticCorrect: data['diagnosticCorrect'] as int? ?? 0,
        practiceAttempts: data['practiceAttempts'] as int? ?? 0,
        masteryCount: data['masteryCount'] as int? ?? 0,
        masteryCorrect: data['masteryCorrect'] as int? ?? 0,
        reteachCount: data['reteachCount'] as int? ?? 0,
        explanationVariant: data['explanationVariant'] as int? ?? 0,
        lastError: data['lastError'] == null ? null : SimorghErrorKind.values.byName(data['lastError'].toString()),
      );
    } on Object { return null; }
  }

  Map<String, dynamic> _sessionRecord(SimorghTeachingSession session, {required String id, bool active = true}) => {
    'id': id, 'active': active, 'topic': session.topic,
    'grade': session.grade, 'stage': session.stage.name,
    'diagnosticCount': session.diagnosticCount, 'diagnosticCorrect': session.diagnosticCorrect,
    'practiceAttempts': session.practiceAttempts, 'masteryCount': session.masteryCount,
    'masteryCorrect': session.masteryCorrect, 'reteachCount': session.reteachCount,
    'explanationVariant': session.explanationVariant, 'lastError': session.lastError?.name,
    'updatedAt': DateTime.now().toIso8601String(),
  };

  Future<void> _persistTeachingSession(SimorghTeachingSession session, {bool active = true}) async {
    final id = teachingSessionId ?? newId('simorgh-lesson');
    teachingSessionId = id;
    final records = widget.store.teachingSessions
        .where((record) => record['id'] != id)
        .toList();
    records.add(_sessionRecord(session, id: id, active: active));
    await widget.store.saveTeachingSessions(records);
  }

  Future<void> startTeaching() async {
    var topicValue = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('شروع تدریس با سیمرغ'),
        content: TextField(
          autofocus: true,
          maxLength: 120,
          onChanged: (value) => topicValue = value,
          decoration: const InputDecoration(
            labelText: 'امروز چه مبحثی را یاد بگیریم؟',
            hintText: 'مثلاً کسرها، تابع یا فتوسنتز',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, topicValue.trim()),
            child: const Text('شروع ارزیابی'),
          ),
        ],
      ),
    );
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    final profile = widget.store.profile ?? const <String, dynamic>{};
    final grade = [profile['grade'], profile['year']]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');
    final session = SimorghTeachingEngine.start(topic: selected, grade: grade);
    teachingSessionId = newId('simorgh-lesson');
    try {
      await _persistTeachingSession(session);
      if (!mounted) return;
      setState(() {
        teachingSession = session;
        input.text =
            'می‌خواهم مبحث $selected را یاد بگیرم. لطفاً با یک سؤال کوتاه سطح من را بسنج.';
      });
      showMessage(
        context,
        'جلسه آموزشی روی گوشی ذخیره شد. پرسش ارزیابی را می‌توانی ارسال کنی.',
      );
    } on Object catch (value) {
      if (mounted) showMessage(context, friendlyError(value));
    }
  }

  Future<void> endTeaching() async {
    final session = teachingSession;
    if (session == null) return;
    try {
      await _persistTeachingSession(session, active: false);
      if (mounted) setState(() { teachingSession = null; teachingSessionId = null; });
    } on Object catch (value) { if (mounted) showMessage(context, friendlyError(value)); }
  }

  String _teachingStageLabel(SimorghTeachingStage stage) {
    switch (stage) {
      case SimorghTeachingStage.diagnostic: return 'ارزیابی آغازین';
      case SimorghTeachingStage.explanation: return 'توضیح درس';
      case SimorghTeachingStage.guidedPractice: return 'تمرین هدایت‌شده';
      case SimorghTeachingStage.reteach: return 'بازآموزی';
      case SimorghTeachingStage.masteryCheck: return 'سنجش یادگیری';
      case SimorghTeachingStage.completed: return 'جلسه تکمیل‌شده';
    }
  }

  String _teachingResponseContract(SimorghTeachingSession session) =>
      '${SimorghTeachingEngine.instructionFor(session)}\n'
      'پاسخ را فقط به صورت JSON معتبر و بدون Markdown برگردان. ساختار دقیق: '
      '{"feedback":"بازخورد کوتاه و آموزشی فارسی","outcome":"correct|partial|incorrect|unclear",'
      '"error":"conceptual|prerequisite|procedural|calculation|careless|unknown",'
      '"nextQuestion":"یک پرسش یا تمرین بعدی کوتاه"}. '
      'outcome را فقط بر اساس پاسخ واقعی دانش‌آموز تعیین کن. اگر پاسخ مبهم است unclear بده.';

  _TeachingTurn _decodeTeachingTurn(String raw) {
    try {
      // Do not salvage JSON from prose or Markdown: accepting a partial object
      // can silently turn a malformed model response into a state transition.
      final source = raw.trim();
      if (source.isEmpty || source.length > 12000 ||
          !source.startsWith('{') || !source.endsWith('}')) {
        throw const FormatException();
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      const requiredKeys = {'feedback', 'outcome', 'error', 'nextQuestion'};
      if (decoded.length != requiredKeys.length ||
          !decoded.keys.toSet().containsAll(requiredKeys)) {
        throw const FormatException();
      }

      final rawOutcome = decoded['outcome'];
      final rawError = decoded['error'];
      final rawFeedback = decoded['feedback'];
      final rawNextQuestion = decoded['nextQuestion'];
      if (rawOutcome is! String ||
          rawError is! String ||
          rawFeedback is! String ||
          rawNextQuestion is! String) {
        throw const FormatException();
      }

      final outcome = SimorghAnswerOutcome.values
          .where((item) => item.name == rawOutcome)
          .firstOrNull;
      final error = SimorghErrorKind.values
          .where((item) => item.name == rawError)
          .firstOrNull;
      final feedback = rawFeedback.trim();
      final next = rawNextQuestion.trim();
      if (outcome == null || error == null || feedback.isEmpty ||
          feedback.length > 5000 || next.length > 2000) {
        throw const FormatException();
      }
      return _TeachingTurn(
        feedback: feedback,
        outcome: outcome,
        error: error,
        nextQuestion: next,
      );
    } on Object {
      throw const AiException(AiErrorKind.response,
          'پاسخ آموزشی ساختار معتبری نداشت. دوباره تلاش کن؛ وضعیت جلسه تغییر نکرده است.');
    }
  }

  SimorghTeachingSession _applyTeachingEvaluation(
      SimorghTeachingSession session, _TeachingTurn turn) {
    switch (session.stage) {
      case SimorghTeachingStage.diagnostic:
        return SimorghTeachingEngine.recordDiagnostic(session, turn.outcome);
      case SimorghTeachingStage.explanation:
        return SimorghTeachingEngine.recordExplanationCheck(session, turn.outcome);
      case SimorghTeachingStage.guidedPractice:
        return SimorghTeachingEngine.recordPractice(
            session: session, outcome: turn.outcome, error: turn.error);
      case SimorghTeachingStage.reteach:
        return SimorghTeachingEngine.recordReteachCheck(
            session: session, outcome: turn.outcome, error: turn.error);
      case SimorghTeachingStage.masteryCheck:
        return SimorghTeachingEngine.recordMasteryCheck(
            session: session, outcome: turn.outcome, error: turn.error);
      case SimorghTeachingStage.completed:
        return session;
    }
  }

  Future<void> openShop() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CreditShopPage(store: widget.store)));
    if (mounted) setState(() {});
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (busy || text.isEmpty) return;
    if (text.length > EducationStore.maxQuestionLength) {
      setState(() => error = 'پرسش می‌تواند حداکثر ۴۰۰۰ نویسه داشته باشد.');
      return;
    }
    final id = newId('ai');
    final message = {'id': id, 'role': 'user', 'content': text,
      'status': 'pending', 'createdAt': DateTime.now().toIso8601String()};
    setState(() { busy = true; error = null; messages.add(message); });
    try { await widget.store.saveMessages(messages); } on Object catch (value) {
      if (mounted) setState(() { busy = false; messages.removeLast(); error = friendlyError(value); });
      return;
    }
    input.clear();
    await request(id, text, alreadyBusy: true);
  }

  Future<void> request(String id, String text, {bool alreadyBusy = false}) async {
    if (busy && !alreadyBusy) return;
    setState(() { busy = true; error = null; });
    final history = messages.where((m) => m['id'] != id).toList();
    try {
      final sessionAtRequest = teachingSession;
      final teachingMode = sessionAtRequest != null;
      final answer = await service.ask(profile: widget.store.profile, history: history,
          question: text, requestId: id,
          systemInstruction: teachingMode ? _teachingResponseContract(sessionAtRequest) : null);
      var displayedAnswer = answer;
      final localSafetyResponse = AiSafetyPolicy.assess(text).shouldBlockRemoteAi ||
          history.any((message) => message['role'] == 'user' &&
              message['content'] is String &&
              AiSafetyPolicy.assess(message['content'] as String).shouldBlockRemoteAi);
      if (teachingMode && !localSafetyResponse) {
        try {
          final turn = _decodeTeachingTurn(answer);
          final updated = _applyTeachingEvaluation(sessionAtRequest, turn);
          await _persistTeachingSession(updated);
          teachingSession = updated;
          displayedAnswer = turn.feedback;
          if (updated.isComplete) {
            displayedAnswer = '$displayedAnswer\n\nجلسه به پایان رسید. در سنجش پایانی، ${updated.masteryCorrect} پاسخ از ${updated.masteryCount} پاسخ درست بود. این نتیجه شواهد همین جلسه است، نه تضمین تسلط کامل. برای تثبیت یادگیری، فردا یک تمرین تازه از همین مبحث حل کن.';
          } else if (updated.stage == sessionAtRequest.stage &&
              turn.nextQuestion.isNotEmpty) {
            // The model generated this question under the current stage's
            // instruction. Never show it after the deterministic engine has
            // moved to a different stage (for example, diagnostic -> reteach).
            displayedAnswer = '$displayedAnswer\n\n${turn.nextQuestion}';
          } else if (updated.stage != sessionAtRequest.stage) {
            displayedAnswer = '$displayedAnswer\n\nمرحله بعدی آموزش آماده است. برای دریافت پرسش متناسب با این مرحله، «آماده‌سازی گام آموزشی» را بزن.';
          }
        } on AiException catch (value) {
          if (value.kind != AiErrorKind.response) rethrow;
          // The model answered but its evaluation payload was malformed.
          // Keep the lesson stage unchanged and allow a fresh student turn.
          displayedAnswer = value.message;
        }
      } else if (teachingMode && localSafetyResponse) {
        // Local crisis support is not a structured lesson evaluation.
        // Preserve it and never advance the teaching state.
        displayedAnswer = answer;
      }
      if (!mounted) return;
      setState(() {
        for (final message in messages) { if (message['id'] == id) message['status'] = 'completed'; }
        messages.removeWhere((m) => m['id'] == '$id-answer');
        messages.add({'id': '$id-answer', 'role': 'assistant', 'content': displayedAnswer,
          'status': 'completed', 'createdAt': DateTime.now().toIso8601String()});
      });
      await widget.store.saveMessages(messages);
    } on Object catch (value) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(value);
        for (final message in messages) { if (message['id'] == id) message['status'] = 'failed'; }
      });
      try { await widget.store.saveMessages(messages); } on Object {
        // The wallet still holds the completed answer/refund. A storage error
        // must never turn a real answer into a fabricated one.
      }
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> clearChat() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('گفت‌وگو پاک شود؟'), content: const Text('تاریخچه گفت‌وگو پاک می‌شود؛ اعتبار و سابقه خرید تغییر نمی‌کند.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک کردن'))]));
    if (confirmed != true || !mounted) return;
    try { await widget.store.saveMessages([]); if (mounted) setState(() { messages = []; error = null;  }); }
    on Object catch (value) { if (mounted) showMessage(context, friendlyError(value)); }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Flexible(
      fit: FlexFit.loose,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFF1F8F6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SimorghChatAvatar(
          state: resolveSimorghChatState(busy: busy, messages: messages),
        ),
      ),
    )),
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Row(children: [
      Expanded(child: OutlinedButton.icon(
        key: const ValueKey('simorgh-start-teaching'),
        onPressed: busy ? null : startTeaching,
        icon: const Icon(Icons.school_outlined),
        label: Text(teachingSession == null ? 'شروع تدریس با سیمرغ' : 'جلسه: ${teachingSession!.topic}'),
      )),
      if (teachingSession != null) IconButton(tooltip: 'پایان جلسه آموزشی', onPressed: busy ? null : endTeaching, icon: const Icon(Icons.close)),
    ])),
    if (teachingSession != null)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'روش تدریس سیمرغ · ${_teachingStageLabel(teachingSession!.stage)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'وضعیت جلسه روی همین گوشی نگهداری می‌شود. پاسخ پرسش سیمرغ را در گفت‌وگو بنویس تا مرحله بعدی تنظیم شود.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(
                              () => input.text = 'برای ادامه یادگیری ${teachingSession!.topic} آماده‌ام؛ سؤال بعدی را بپرس.',
                            ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('آماده‌سازی گام آموزشی'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: CreditSummary(store: widget.store, onShop: busy ? null : openShop)),
    if (!service.isConfigured) const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
      child: NoticeCard(text: 'مشاور هوش مصنوعی در این نسخه پیکربندی نشده است. برنامه مطالعه، نمرات، مرور و راهنمای روش مطالعه بدون اینترنت کار می‌کنند.', warning: true)),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: NoticeCard(text: error!, icon: Icons.error_outline, warning: true)),
        ],
      ),
    ),
    ),
    Expanded(child: messages.isEmpty ? ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 18), const Icon(Icons.auto_awesome, color: blue, size: 46),
      const SizedBox(height: 14), const Text('سلام! من سیمرغم؛ بیا با هم مسیر یادگیری‌ات را پیدا کنیم.', textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      const SizedBox(height: 8), const Text('من یک همراه گفت‌وگویی با کمک هوش مصنوعی هستم؛ می‌توانم در فهم درس، برنامه‌ریزی و شناخت مسیرها کمکت کنم. پاسخ‌ها ممکن است اشتباه باشند؛ تصمیم‌های مهم را با معلم، مشاور مدرسه یا بزرگسال مورد اعتماد هم بررسی کن.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey, height: 1.8)),
      const SizedBox(height: 20),
      for (final prompt in ['برای این هفته یک برنامه مطالعه واقع‌بینانه پیشنهاد بده.', 'چطور نقاط قوت و ضعف درسی‌ام را بشناسم؟', 'برای بهتر شدن تمرکزم چه تمرین‌هایی انجام دهم؟'])
        Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(
            onPressed: busy ? null : () => setState(() => input.text = prompt), child: Text(prompt, textAlign: TextAlign.right))),
    ]) : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), itemCount: messages.length + (busy ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const Padding(padding: EdgeInsets.all(12), child: Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12),
              Expanded(child: Text('سیمرغ دارد پاسخ را آماده می‌کند… درخواست ناموفق هزینه نهایی ندارد.')),
            ]));
          }
          final message = messages[index];
          final user = message['role'] == 'user';
          final failed = message['status'] == 'failed' || message['status'] == 'pending';
          return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: user ? blue : Colors.white, borderRadius: BorderRadius.circular(18),
                  border: user ? null : Border.all(color: const Color(0xFFE3EAF2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user ? 'پرسش تو' : 'سیمرغ', style: TextStyle(fontSize: 11, color: user ? Colors.white70 : teal, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(message['content'].toString(), style: TextStyle(color: user ? Colors.white : navy, height: 1.8)),
                if (user && failed) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
                    message['status'] == 'pending' ? 'پاسخ این درخواست هنوز ثبت نشده است.' : 'این درخواست کامل نشد.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12))),
                if (user && failed)
                  TextButton.icon(
                      key: ValueKey('advisor-retry-${message['id']}'),
                      onPressed: busy ? null : () => request(
                          message['id'].toString(), message['content'].toString()),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('تلاش دوباره همین درخواست', style: TextStyle(color: Colors.white))),
              ])));
        })),
    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: SafeArea(top: false,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(tooltip: 'پاک کردن گفت‌وگو', onPressed: busy || messages.isEmpty ? null : clearChat, icon: const Icon(Icons.delete_sweep_outlined)),
        Expanded(child: TextField(controller: input, enabled: !busy, minLines: 1, maxLines: 4,
          maxLength: EducationStore.maxQuestionLength, textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: 'با سیمرغ حرف بزن…', counterText: ''))),
        const SizedBox(width: 8),
        IconButton.filled(tooltip: 'ارسال پرسش', onPressed: busy ? null : send, icon: const Icon(Icons.send_rounded)),
      ]))),
  ]);
}
