import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'ai_advisor_service.dart';
import 'ai_safety_policy.dart';
import 'credit_shop_page.dart';
import 'education_store.dart';
import 'simorgh_companion.dart';
import 'simorgh_teaching_engine.dart';
import 'study_pages.dart' show newId;
import 'ui.dart';

class _TeachingTurn {
  const _TeachingTurn({
    required this.feedback,
    required this.outcome,
    required this.error,
    required this.nextQuestion,
  });

  final String feedback;
  final SimorghAnswerOutcome outcome;
  final SimorghErrorKind error;
  final String nextQuestion;
}

List<Map<String, dynamic>> _copyRecords(
  List<Map<String, dynamic>> records,
) {
  return records
      .map((record) => Map<String, dynamic>.from(record))
      .toList();
}

class AdvisorPage extends StatefulWidget {
  const AdvisorPage({
    super.key,
    required this.store,
    this.service,
  });

  final EducationStore store;
  final AiAdvisorService? service;

  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();

  late AiAdvisorService _service;
  late bool _ownsService;

  final Set<AiAdvisorService> _runningServices = {};
  final Set<AiAdvisorService> _retiredServices = {};

  late List<Map<String, dynamic>> _messages;

  SimorghTeachingSession? _teachingSession;
  String? _teachingSessionId;

  bool _busy = false;
  bool _recovering = false;
  bool _managingSession = false;
  bool _clearing = false;
  bool _openingShop = false;

  String? _error;

  // A prepared question is not an answer to be evaluated.
  String? _preparedPrompt;

  // Invalidate UI updates when the supplied store/service changes.
  int _generation = 0;
  bool _disposed = false;
  bool _scrollScheduled = false;

  bool get _locked =>
      _busy ||
      _recovering ||
      _managingSession ||
      _clearing ||
      _openingShop;

  bool get _storeHasActiveRequest => widget.store.hasActiveAiRequests;

  bool get _canOperate => !_locked && !_storeHasActiveRequest;

  @override
  void initState() {
    super.initState();

    _configureService();
    _loadLocalState();

    _input.addListener(_handleInputChanged);
    widget.store.addListener(_handleStoreChanged);

    unawaited(_recoverPendingMessages());
    _scrollToBottom();
  }

  void _configureService() {
    _ownsService = widget.service == null;
    _service = widget.service ?? AiAdvisorService(store: widget.store);
  }

  void _retireService(AiAdvisorService service, bool owned) {
    if (!owned) return;

    if (_runningServices.contains(service)) {
      _retiredServices.add(service);
    } else {
      service.dispose();
    }
  }

  void _loadLocalState() {
    _messages = _copyRecords(widget.store.messages);

    _teachingSession = null;
    _teachingSessionId = null;

    // Try the newest valid active session, without modifying damaged records.
    for (final record in widget.store.teachingSessions.reversed) {
      if (record['active'] != true) continue;

      final id = record['id'];
      final session = _decodeSession(record);

      if (id is String && id.trim().isNotEmpty && session != null) {
        _teachingSession = session;
        _teachingSessionId = id;
        break;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AdvisorPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final storeChanged = !identical(oldWidget.store, widget.store);
    final serviceChanged = !identical(oldWidget.service, widget.service);

    if (!storeChanged && !serviceChanged) return;

    _generation++;

    if (storeChanged) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }

    _retireService(_service, _ownsService);
    _configureService();

    _busy = false;
    _recovering = false;
    _managingSession = false;
    _clearing = false;
    _openingShop = false;

    _error = null;
    _preparedPrompt = null;
    _input.clear();

    _loadLocalState();

    unawaited(_recoverPendingMessages());
    _scrollToBottom();
  }

  bool _isCurrent(int generation, EducationStore store) {
    return mounted &&
        !_disposed &&
        generation == _generation &&
        identical(store, widget.store);
  }

  void _handleInputChanged() {
    if (_preparedPrompt != null &&
        _input.text.trim() != _preparedPrompt) {
      _preparedPrompt = null;
    }

    if (mounted) setState(() {});
  }

  void _handleStoreChanged() {
    if (!mounted) return;

    // Do not replace the working transcript during our own operation.
    if (!_busy && !_recovering && !_clearing && !_managingSession) {
      _loadLocalState();
    }

    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;

    widget.store.removeListener(_handleStoreChanged);
    _input.removeListener(_handleInputChanged);

    _input.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();

    // Do not dispose a service while an owned request is still saving.
    _retireService(_service, _ownsService);

    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollScheduled || !mounted) return;

    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;

      if (!mounted || !_scrollController.hasClients) return;

      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  SimorghTeachingSession? _decodeSession(
    Map<String, dynamic> data,
  ) {
    try {
      final topic = data['topic'];
      final grade = data['grade'];

      if (topic is! String ||
          topic.trim().isEmpty ||
          topic.length > SimorghTeachingEngine.maxTopicLength ||
          grade is! String ||
          grade.length > SimorghTeachingEngine.maxGradeLength) {
        throw const FormatException('Invalid lesson identity.');
      }

      int counter(String key, {required int maximum}) {
        final value = data[key] ?? 0;

        if (value is! int || value < 0 || value > maximum) {
          throw FormatException('Invalid lesson counter: $key');
        }

        return value;
      }

      final stageName = data['stage'];

      if (stageName is! String) {
        throw const FormatException('Missing lesson stage.');
      }

      final stages = SimorghTeachingStage.values
          .where((value) => value.name == stageName)
          .toList();

      if (stages.length != 1) {
        throw const FormatException('Unknown lesson stage.');
      }

      final diagnosticCount = counter(
        'diagnosticCount',
        maximum: SimorghTeachingEngine.diagnosticQuestionLimit,
      );

      final diagnosticCorrect = counter(
        'diagnosticCorrect',
        maximum: SimorghTeachingEngine.diagnosticQuestionLimit,
      );

      final practiceAttempts = counter(
        'practiceAttempts',
        maximum: 1000,
      );

      final masteryCount = counter(
        'masteryCount',
        maximum: SimorghTeachingEngine.masteryQuestionLimit,
      );

      final masteryCorrect = counter(
        'masteryCorrect',
        maximum: SimorghTeachingEngine.masteryQuestionLimit,
      );

      final reteachCount = counter(
        'reteachCount',
        maximum: 1000,
      );

      final explanationVariant = counter(
        'explanationVariant',
        maximum: 1000,
      );

      if (diagnosticCorrect > diagnosticCount ||
          masteryCorrect > masteryCount) {
        throw const FormatException('Invalid lesson scores.');
      }

      SimorghErrorKind? lastError;
      final rawError = data['lastError'];

      if (rawError != null) {
        if (rawError is! String) {
          throw const FormatException('Invalid error type.');
        }

        final errors = SimorghErrorKind.values
            .where((value) => value.name == rawError)
            .toList();

        if (errors.length != 1) {
          throw const FormatException('Unknown error type.');
        }

        lastError = errors.single;
      }

      return SimorghTeachingSession(
        topic: topic.trim(),
        grade: grade.trim(),
        stage: stages.single,
        diagnosticCount: diagnosticCount,
        diagnosticCorrect: diagnosticCorrect,
        practiceAttempts: practiceAttempts,
        masteryCount: masteryCount,
        masteryCorrect: masteryCorrect,
        reteachCount: reteachCount,
        explanationVariant: explanationVariant,
        lastError: lastError,
      );
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> _sessionRecord(
    SimorghTeachingSession session, {
    required String id,
    bool active = true,
  }) {
    return {
      'id': id,
      'active': active,
      'topic': session.topic,
      'grade': session.grade,
      'stage': session.stage.name,
      'diagnosticCount': session.diagnosticCount,
      'diagnosticCorrect': session.diagnosticCorrect,
      'practiceAttempts': session.practiceAttempts,
      'masteryCount': session.masteryCount,
      'masteryCorrect': session.masteryCorrect,
      'reteachCount': session.reteachCount,
      'explanationVariant': session.explanationVariant,
      'lastError': session.lastError?.name,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic>? _findSessionRecord(
    EducationStore store,
    String id,
  ) {
    for (final record in store.teachingSessions.reversed) {
      if (record['id'] == id) {
        return Map<String, dynamic>.from(record);
      }
    }

    return null;
  }

  bool _sameSessionState(
    SimorghTeachingSession first,
    SimorghTeachingSession second,
  ) {
    return first.topic == second.topic &&
        first.grade == second.grade &&
        first.stage == second.stage &&
        first.diagnosticCount == second.diagnosticCount &&
        first.diagnosticCorrect == second.diagnosticCorrect &&
        first.practiceAttempts == second.practiceAttempts &&
        first.masteryCount == second.masteryCount &&
        first.masteryCorrect == second.masteryCorrect &&
        first.reteachCount == second.reteachCount &&
        first.explanationVariant == second.explanationVariant &&
        first.lastError == second.lastError;
  }

  Future<void> _saveSession(
    EducationStore store,
    SimorghTeachingSession session, {
    required String id,
    required bool active,
    String? appliedRequestId,
    bool replaceActive = false,
  }) async {
    final previous = _findSessionRecord(store, id);
    final records = _copyRecords(store.teachingSessions);

    records.removeWhere((record) => record['id'] == id);

    if (replaceActive) {
      for (final record in records) {
        if (record['active'] == true) {
          record['active'] = false;
          record['updatedAt'] = DateTime.now().toIso8601String();
        }
      }
    }

    // Preserve request IDs so transcript retries cannot evaluate twice.
    final appliedIds = <String>{
      if (previous?['appliedRequestIds'] is List)
        ...(previous!['appliedRequestIds'] as List).whereType<String>(),
    };

    if (appliedRequestId != null) {
      appliedIds.add(appliedRequestId);
    }

    records.add({
      ...?previous,
      ..._sessionRecord(session, id: id, active: active),
      'appliedRequestIds': appliedIds.toList(),
    });

    await store.saveTeachingSessions(records);
  }

  Future<void> _recoverPendingMessages() async {
    final store = widget.store;
    final generation = _generation;

    if (_locked || store.hasActiveAiRequests) return;

    final recovered = _copyRecords(store.messages);

    if (!recovered.any(
      (message) =>
          message['role'] == 'user' &&
          message['status'] == 'pending',
    )) {
      return;
    }

    setState(() {
      _recovering = true;
      _error = null;
    });

    var changed = false;

    try {
      for (final message in recovered.toList()) {
        if (message['role'] != 'user' ||
            message['status'] != 'pending') {
          continue;
        }

        final id = message['id'];

        if (id is! String || id.isEmpty) continue;

        final answer = store.savedAiAnswer(id);

        if (answer == null) {
          message['status'] = 'failed';
          changed = true;
          continue;
        }

        var display = answer;

        if (message['teachingSnapshot'] is Map) {
          try {
            final turn = _decodeTeachingTurn(answer);
            display = _joinTeachingText(
              turn.feedback,
              turn.nextQuestion,
            );

            final sessionId = message['teachingSessionId'];
            final record = sessionId is String
                ? _findSessionRecord(store, sessionId)
                : null;

            final applied = record?['appliedRequestIds'];

            final alreadyApplied = applied is List &&
                applied.contains(id);

            if (message['teachingPreparation'] != true &&
                !alreadyApplied) {
              // Recovery must not infer an unrecorded teaching transition.
              display =
                  '$display\n\n'
                  'پاسخ قبلی بازیابی شد، اما ثبت پیشرفت این گام '
                  'تأیید نشده است؛ مرحله جلسه خودکار تغییر نکرد.';
            }
          } on AiException {
            // This may be an intentional local safety response.
            // Do not expose malformed JSON or refund again during recovery.
            final source = answer.trim();

            if (source.startsWith('{') ||
                source.startsWith('```')) {
              display =
                  'پاسخ قبلی بازیابی شد، اما قالب آموزشی آن '
                  'قابل نمایش نیست. وضعیت جلسه تغییر نکرده است. '
                  'برای بررسی نتیجه درخواست، تاریخچه مشاوره '
                  'و کیف اعتبار را ببین.';
            }
          }
        }

        message['status'] = 'completed';

        if (!recovered.any(
          (item) => item['id'] == '$id-answer',
        )) {
          final position = recovered.indexOf(message);

          recovered.insert(position + 1, {
            'id': '$id-answer',
            'role': 'assistant',
            'content': display,
            'status': 'completed',
            'createdAt':
                message['createdAt'] ??
                DateTime.now().toIso8601String(),
            'recovered': true,
          });
        }

        changed = true;
      }

      if (changed) {
        await store.saveMessages(recovered);
      }

      if (_isCurrent(generation, store)) {
        setState(() {
          _messages = recovered;
        });

        _scrollToBottom();
      }
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() {
          _error =
              'بازیابی گفت‌وگو کامل نشد. '
              '${friendlyError(error)}';
        });
      }
    } finally {
      if (_isCurrent(generation, store)) {
        setState(() => _recovering = false);
      }
    }
  }

  Future<void> _startTeaching() async {
    if (!_canOperate) return;

    final store = widget.store;
    final generation = _generation;

    setState(() => _managingSession = true);

    final controller = TextEditingController();
    final form = GlobalKey<FormState>();

    try {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('شروع تدریس با سیمرغ'),
            content: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_teachingSession != null) ...[
                      const Text(
                        'با شروع جلسه جدید، جلسه قبلی '
                        'پایان می‌یابد و سابقه آن روی گوشی باقی می‌ماند.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      maxLength: SimorghTeachingEngine.maxTopicLength,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'امروز چه مبحثی را یاد بگیریم؟',
                        hintText: 'مثلاً کسرها، تابع یا فتوسنتز',
                      ),
                      validator: (value) {
                        final topic = value?.trim() ?? '';

                        if (topic.isEmpty) {
                          return 'نام مبحث را وارد کن.';
                        }

                        if (topic.length >
                            SimorghTeachingEngine.maxTopicLength) {
                          return 'نام مبحث بیش از حد طولانی است.';
                        }

                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  if (form.currentState?.validate() != true) return;

                  Navigator.of(dialogContext).pop(
                    controller.text.trim(),
                  );
                },
                child: const Text('شروع ارزیابی'),
              ),
            ],
          );
        },
      );

      if (!_isCurrent(generation, store) || selected == null) {
        return;
      }

      if (store.hasActiveAiRequests) {
        throw StateError(
          'یک درخواست مشاور در حال اجراست؛ پس از پایان آن تلاش کن.',
        );
      }

      final profile = store.profile ?? <String, dynamic>{};

      var grade = [
        profile['grade'],
        profile['year'],
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(' · ');

      if (grade.length > SimorghTeachingEngine.maxGradeLength) {
        grade = '';
      }

      final session = SimorghTeachingEngine.start(
        topic: selected,
        grade: grade,
      );

      final id = newId('simorgh-lesson');

      await _saveSession(
        store,
        session,
        id: id,
        active: true,
        replaceActive: true,
      );

      if (!_isCurrent(generation, store)) return;

      setState(() {
        _teachingSession = session;
        _teachingSessionId = id;
        _error = null;
      });

      _fillPrompt(_preparePrompt(session), preparation: true);

      showMessage(
        context,
        'جلسه ذخیره شد. برای دریافت سؤال آغازین، پیام آماده را ارسال کن.',
      );
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      // Allow the dialog route to finish before disposing its controller.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });

      if (_isCurrent(generation, store)) {
        setState(() => _managingSession = false);
      }
    }
  }

  Future<void> _endTeaching() async {
    if (!_canOperate) return;

    final session = _teachingSession;
    final id = _teachingSessionId;

    if (session == null || id == null) return;

    final store = widget.store;
    final generation = _generation;

    setState(() => _managingSession = true);

    try {
      await _saveSession(
        store,
        session,
        id: id,
        active: false,
      );

      if (!_isCurrent(generation, store)) return;

      setState(() {
        _teachingSession = null;
        _teachingSessionId = null;
        _preparedPrompt = null;
        _error = null;
      });
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (_isCurrent(generation, store)) {
        setState(() => _managingSession = false);
      }
    }
  }

  String _teachingStageLabel(SimorghTeachingStage stage) {
    return switch (stage) {
      SimorghTeachingStage.diagnostic => 'ارزیابی آغازین',
      SimorghTeachingStage.explanation => 'توضیح درس',
      SimorghTeachingStage.guidedPractice => 'تمرین هدایت‌شده',
      SimorghTeachingStage.reteach => 'بازآموزی',
      SimorghTeachingStage.masteryCheck => 'سنجش یادگیری',
      SimorghTeachingStage.completed => 'جلسه تکمیل‌شده',
    };
  }

  String _preparePrompt(SimorghTeachingSession session) {
    return switch (session.stage) {
      SimorghTeachingStage.diagnostic =>
        'برای سنجش سطح من در ${session.topic}، یک سؤال کوتاه بپرس.',
      SimorghTeachingStage.explanation =>
        'توضیح ${session.topic} را با یک مثال ساده ادامه بده.',
      SimorghTeachingStage.guidedPractice =>
        'یک تمرین هدایت‌شده برای ${session.topic} بده تا با هم حل کنیم.',
      SimorghTeachingStage.reteach =>
        'لطفاً ${session.topic} را با روش دیگری دوباره توضیح بده.',
      SimorghTeachingStage.masteryCheck =>
        'برای سنجش یادگیری ${session.topic} یک سؤال تازه بپرس.',
      SimorghTeachingStage.completed => '',
    };
  }

  void _fillPrompt(
    String text, {
    bool preparation = false,
  }) {
    _preparedPrompt = null;
    _input.text = text;

    _input.selection = TextSelection.collapsed(
      offset: text.length,
    );

    _preparedPrompt = preparation ? text.trim() : null;

    _inputFocus.requestFocus();

    if (mounted) setState(() {});
  }

  String _teachingResponseContract(
    SimorghTeachingSession session, {
    required bool shareProfile,
    required bool preparation,
  }) {
    final promptSession = session.copyWith(
      grade: shareProfile ? session.grade : '',
    );

    final modeInstruction = preparation
        ? 'پیام فعلی فقط درخواست آماده‌سازی درس یا پرسش است، '
            'نه پاسخ دانش‌آموز. هیچ ارزیابی یا ادعای موفقیت نکن. '
            'outcome را unclear و error را unknown قرار بده. '
            'در feedback توضیح لازم را بنویس و در nextQuestion '
            'حداکثر یک سؤال متناسب با مرحله فعلی بده.'
        : 'فقط پاسخ فعلی دانش‌آموز را با توجه به سؤال قبلی ارزیابی کن. '
            'اگر سؤال قبلی مشخص نیست یا پیام صرفاً درخواست راهنمایی است، '
            'outcome را unclear قرار بده.';

    return '${SimorghTeachingEngine.instructionFor(promptSession)}\n'
        '$modeInstruction\n'
        'پاسخ را فقط به صورت JSON معتبر و بدون Markdown برگردان. '
        'ساختار دقیق: '
        '{"feedback":"بازخورد آموزشی فارسی",'
        '"outcome":"correct|partial|incorrect|unclear",'
        '"error":"conceptual|prerequisite|procedural|calculation|careless|unknown",'
        '"nextQuestion":"یک پرسش کوتاه یا رشته خالی"}. '
        'correct فقط وقتی پاسخ و استدلال اصلی درست و کافی است؛ '
        'partial برای مسیر درست اما ناقص؛ '
        'incorrect برای پاسخ ناسازگار با مفهوم یا روش درست؛ '
        'unclear وقتی شواهد برای داوری کافی نیست. '
        'حدس را جای شواهد نگذار. '
        'conceptual یعنی برداشت نادرست از مفهوم؛ '
        'prerequisite یعنی ضعف در پیش‌نیاز مشخص؛ '
        'procedural یعنی اجرای نادرست روش؛ '
        'calculation یعنی خطای عددی؛ '
        'careless یعنی لغزش جزئی با فهم درست قابل مشاهده؛ '
        'unknown یعنی شواهد برای تشخیص کافی نیست. '
        'برای correct یا unclear، error حتماً unknown باشد. '
        'بازخورد محترمانه، مشخص و بدون تعریف بی‌پایه باشد. '
        'یک گام اصلاحی کوچک پیشنهاد کن. '
        'از نمره قطعی، تضمین تسلط و افشای بی‌مورد جواب تمرین خودداری کن. '
        'nextQuestion حداکثر یک پرسش کوتاه باشد.';
  }

  _TeachingTurn _decodeTeachingTurn(String raw) {
    try {
      final source = raw.trim();

      if (source.isEmpty ||
          source.length > 12000 ||
          !source.startsWith('{') ||
          !source.endsWith('}')) {
        throw const FormatException();
      }

      final decoded = jsonDecode(source);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }

      const requiredKeys = {
        'feedback',
        'outcome',
        'error',
        'nextQuestion',
      };

      if (decoded.length != requiredKeys.length ||
          !decoded.keys.toSet().containsAll(requiredKeys)) {
        throw const FormatException();
      }

      final rawFeedback = decoded['feedback'];
      final rawOutcome = decoded['outcome'];
      final rawError = decoded['error'];
      final rawNext = decoded['nextQuestion'];

      if (rawFeedback is! String ||
          rawOutcome is! String ||
          rawError is! String ||
          rawNext is! String) {
        throw const FormatException();
      }

      final outcomes = SimorghAnswerOutcome.values
          .where((value) => value.name == rawOutcome)
          .toList();

      final errors = SimorghErrorKind.values
          .where((value) => value.name == rawError)
          .toList();

      final feedback = rawFeedback.trim();
      final next = rawNext.trim();

      if (outcomes.length != 1 ||
          errors.length != 1 ||
          feedback.isEmpty ||
          feedback.length > 5000 ||
          next.length > 2000) {
        throw const FormatException();
      }

      final outcome = outcomes.single;
      final errorKind = errors.single;

      if ((outcome == SimorghAnswerOutcome.correct ||
              outcome == SimorghAnswerOutcome.unclear) &&
          errorKind != SimorghErrorKind.unknown) {
        throw const FormatException();
      }

      return _TeachingTurn(
        feedback: feedback,
        outcome: outcome,
        error: errorKind,
        nextQuestion: next,
      );
    } on Object {
      throw const AiException(
        AiErrorKind.response,
        'پاسخ آموزشی قالب معتبری نداشت. '
        'وضعیت جلسه تغییر نکرده است.',
      );
    }
  }

  SimorghTeachingSession _applyTeachingEvaluation(
    SimorghTeachingSession session,
    _TeachingTurn turn,
  ) {
    // Insufficient evidence must not consume an assessment attempt.
    if (turn.outcome == SimorghAnswerOutcome.unclear) {
      return session;
    }

    return switch (session.stage) {
      SimorghTeachingStage.diagnostic =>
        SimorghTeachingEngine.recordDiagnostic(
          session,
          turn.outcome,
        ),
      SimorghTeachingStage.explanation =>
        SimorghTeachingEngine.recordExplanationCheck(
          session,
          turn.outcome,
        ),
      SimorghTeachingStage.guidedPractice =>
        SimorghTeachingEngine.recordPractice(
          session: session,
          outcome: turn.outcome,
          error: turn.error,
        ),
      SimorghTeachingStage.reteach =>
        SimorghTeachingEngine.recordReteachCheck(
          session: session,
          outcome: turn.outcome,
          error: turn.error,
        ),
      SimorghTeachingStage.masteryCheck =>
        SimorghTeachingEngine.recordMasteryCheck(
          session: session,
          outcome: turn.outcome,
          error: turn.error,
        ),
      SimorghTeachingStage.completed => session,
    };
  }

  String _joinTeachingText(String feedback, String question) {
    return question.isEmpty
        ? feedback
        : '$feedback\n\n$question';
  }

  List<Map<String, dynamic>> _historyBefore(
    List<Map<String, dynamic>> messages,
    String id,
  ) {
    final position = messages.indexWhere(
      (message) => message['id'] == id,
    );

    final previous = position < 0
        ? <Map<String, dynamic>>[]
        : messages.take(position);

    // Do not send storage metadata, teaching snapshots or failed turns.
    return previous
        .where(
          (message) =>
              (message['role'] == 'user' ||
                  message['role'] == 'assistant') &&
              message['status'] != 'failed' &&
              message['status'] != 'pending',
        )
        .map(
          (message) => <String, dynamic>{
            'role': message['role'],
            'content': message['content']?.toString() ?? '',
          },
        )
        .toList();
  }

  Future<void> _send() async {
    if (!_canOperate) return;

    final text = _input.text.trim();

    if (text.isEmpty) return;

    if (text.length > EducationStore.maxQuestionLength) {
      setState(() {
        _error =
            'پرسش می‌تواند حداکثر '
            '${faNumber(EducationStore.maxQuestionLength)} نویسه داشته باشد.';
      });
      return;
    }

    final store = widget.store;
    final generation = _generation;

    final session = _teachingSession;
    final lessonActive = session != null && !session.isComplete;

    final preparation = lessonActive && _preparedPrompt == text;

    final id = newId('ai');

    final message = <String, dynamic>{
      'id': id,
      'role': 'user',
      'content': text,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      if (lessonActive) ...{
        'teachingSessionId': _teachingSessionId,
        'teachingSnapshot': _sessionRecord(
          session,
          id: _teachingSessionId!,
        ),
        'teachingPreparation': preparation,
      },
    };

    final candidate = _copyRecords(store.messages)..add(message);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Persist before changing the visible transcript or clearing the draft.
      await store.saveMessages(candidate);

      if (!_isCurrent(generation, store)) return;

      setState(() => _messages = candidate);

      _preparedPrompt = null;
      _input.clear();

      _scrollToBottom();

      await _request(
        id,
        alreadyBusy: true,
      );
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (_isCurrent(generation, store)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _processTeachingAnswer({
    required EducationStore store,
    required Map<String, dynamic> message,
    required String answer,
    required String id,
    required List<Map<String, dynamic>> history,
  }) async {
    final snapshot = message['teachingSnapshot'];

    if (snapshot is! Map) return answer;

    final text = message['content']?.toString() ?? '';

    if (AiSafetyPolicy.assessTurn(text, history).shouldBlockRemoteAi) {
      // A safety response is not a teaching assessment.
      return answer;
    }

    final session = _decodeSession(
      Map<String, dynamic>.from(snapshot),
    );

    if (session == null) {
      return 'پاسخ دریافت شد، اما زمینه آموزشی این درخواست '
          'قابل بازیابی نیست. وضعیت جلسه تغییر نکرده است.';
    }

    final _TeachingTurn turn;

    try {
      turn = _decodeTeachingTurn(answer);
    } on AiException catch (error) {
      // Report a successful refund only after it has been persisted.
      await store.refundInvalidAiResponse(id);

      return '${error.message}\n\n'
          'بازپرداخت این پاسخ نامعتبر ثبت شد.';
    }

    if (message['teachingPreparation'] == true) {
      return _joinTeachingText(
        turn.feedback,
        turn.nextQuestion,
      );
    }

    final sessionId = message['teachingSessionId'];

    if (sessionId is! String || sessionId.isEmpty) {
      return '${turn.feedback}\n\n'
          'شناسه جلسه موجود نیست؛ پیشرفت آموزشی تغییر نکرد.';
    }

    final record = _findSessionRecord(store, sessionId);
    final current = record == null ? null : _decodeSession(record);

    final appliedIds = record?['appliedRequestIds'];

    if (appliedIds is List && appliedIds.contains(id)) {
      return '${turn.feedback}\n\n'
          'نتیجه این درخواست قبلاً در جلسه ثبت شده است.';
    }

    if (current == null ||
        record?['active'] != true ||
        !_sameSessionState(current, session)) {
      return '${turn.feedback}\n\n'
          'این پاسخ مربوط به وضعیت قبلی جلسه است؛ '
          'پیشرفت جلسه فعلی تغییر نکرد.';
    }

    final updated = _applyTeachingEvaluation(session, turn);

    await _saveSession(
      store,
      updated,
      id: sessionId,
      active: !updated.isComplete,
      appliedRequestId: id,
    );

    if (updated.isComplete) {
      return '${turn.feedback}\n\n'
          'جلسه به پایان رسید. در سنجش پایانی، '
          '${faNumber(updated.masteryCorrect)} پاسخ از '
          '${faNumber(updated.masteryCount)} پاسخ درست بود. '
          'این نتیجه مربوط به شواهد همین جلسه است، '
          'نه تضمین تسلط کامل. '
          'برای تثبیت یادگیری، فردا یک تمرین تازه حل کن.';
    }

    if (updated.stage != session.stage) {
      return '${turn.feedback}\n\n'
          'مرحله بعدی آموزش آماده است. '
          'برای دریافت پرسش متناسب با آن، '
          '«آماده‌سازی گام آموزشی» را بزن.';
    }

    return _joinTeachingText(
      turn.feedback,
      turn.nextQuestion,
    );
  }

  Future<void> _request(
    String id, {
    bool alreadyBusy = false,
  }) async {
    if (!mounted) return;

    if (alreadyBusy) {
      if (_recovering || _clearing || _managingSession) return;
    } else {
      if (!_canOperate) return;
    }

    final store = widget.store;
    final generation = _generation;
    final service = _service;

    final working = _copyRecords(store.messages);

    final position = working.indexWhere(
      (message) =>
          message['id'] == id &&
          message['role'] == 'user',
    );

    if (position < 0) {
      setState(() => _error = 'درخواست موردنظر پیدا نشد.');
      return;
    }

    final message = working[position];
    final text = message['content']?.toString().trim() ?? '';

    if (text.isEmpty ||
        text.length > EducationStore.maxQuestionLength) {
      setState(() => _error = 'متن درخواست معتبر نیست.');
      return;
    }

    // Refuse repeat evaluation of a completed transcript.
    if (message['status'] == 'completed') return;

    setState(() {
      _busy = true;
      _error = null;
    });

    _runningServices.add(service);

    try {
      message['status'] = 'pending';

      // Retry status is durable too.
      await store.saveMessages(working);

      if (_isCurrent(generation, store)) {
        setState(() => _messages = _copyRecords(working));
        _scrollToBottom();
      }

      final history = _historyBefore(working, id);

      final rawSnapshot = message['teachingSnapshot'];

      final session = rawSnapshot is Map
          ? _decodeSession(
              Map<String, dynamic>.from(rawSnapshot),
            )
          : null;

      if (rawSnapshot != null && session == null) {
        throw StateError(
          'زمینه آموزشی این درخواست معتبر نیست. '
          'یک جلسه جدید شروع کن.',
        );
      }

      final profile = store.profile == null
          ? null
          : Map<String, dynamic>.from(store.profile!);

      final answer = await service.ask(
        profile: profile,
        history: history,
        question: text,
        requestId: id,
        systemInstruction: session == null
            ? null
            : _teachingResponseContract(
                session,
                // Consent is checked again at retry time.
                shareProfile:
                    profile?['aiProfileContextConsent'] == true,
                preparation:
                    message['teachingPreparation'] == true,
              ),
      );

      final display = await _processTeachingAnswer(
        store: store,
        message: message,
        answer: answer,
        id: id,
        history: history,
      );

      final updated = _copyRecords(store.messages);

      final userPosition = updated.indexWhere(
        (item) => item['id'] == id && item['role'] == 'user',
      );

      if (userPosition < 0) {
        // Another owner removed the conversation. Do not resurrect it.
        throw StateError(
          'گفت‌وگو هنگام اجرای درخواست تغییر کرده است. '
          'نتیجه را از تاریخچه مشاوره بررسی کن.',
        );
      }

      updated[userPosition]['status'] = 'completed';

      updated.removeWhere(
        (item) => item['id'] == '$id-answer',
      );

      final insertionPosition = updated.indexWhere(
        (item) => item['id'] == id,
      );

      updated.insert(insertionPosition + 1, {
        'id': '$id-answer',
        'role': 'assistant',
        'content': display,
        'status': 'completed',
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Finish persistence even if the page is no longer mounted.
      await store.saveMessages(updated);

      if (_isCurrent(generation, store)) {
        setState(() {
          _messages = updated;
        });

        _scrollToBottom();
      }
    } on Object catch (error) {
      final failed = _copyRecords(store.messages);

      for (final item in failed) {
        if (item['id'] == id && item['status'] != 'completed') {
          item['status'] = 'failed';
        }
      }

      var persistenceFailed = false;

      try {
        await store.saveMessages(failed);
      } on Object {
        persistenceFailed = true;
      }

      if (_isCurrent(generation, store)) {
        setState(() {
          _messages = persistenceFailed
              ? _copyRecords(store.messages)
              : failed;

          _error = friendlyError(error);

          if (persistenceFailed) {
            _error =
                '$_error\n'
                'ثبت وضعیت گفت‌وگو هم انجام نشد؛ '
                'نتیجه درخواست ممکن است در تاریخچه مشاوره موجود باشد.';
          }
        });
      }
    } finally {
      _runningServices.remove(service);

      if (_retiredServices.remove(service)) {
        service.dispose();
      }

      if (_isCurrent(generation, store)) {
        setState(() {
          _busy = false;
          _loadLocalState();
        });

        _scrollToBottom();
      }
    }
  }

  Future<void> _openShop() async {
    if (!_canOperate) return;

    final store = widget.store;
    final generation = _generation;

    setState(() => _openingShop = true);

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CreditShopPage(store: store),
        ),
      );
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (_isCurrent(generation, store)) {
        setState(() => _openingShop = false);
      }
    }
  }

  Future<void> _clearChat() async {
    if (!_canOperate || _messages.isEmpty) return;

    final store = widget.store;
    final generation = _generation;

    setState(() => _clearing = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('گفت‌وگو پاک شود؟'),
            content: const SingleChildScrollView(
              child: Text(
                'پیام‌های این گفت‌وگو پاک می‌شوند. '
                'اعتبار، سابقه خرید و سوابق مستقل مشاوره '
                'تغییر نمی‌کنند.\n\n'
                'جلسه آموزشی فعال، در صورت وجود، پایان می‌یابد. '
                'این کار اطلاعات قبلاً ارسال‌شده '
                'به سرویس بیرونی را حذف نمی‌کند.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('پاک کردن'),
              ),
            ],
          );
        },
      );

      if (!_isCurrent(generation, store) || confirmed != true) {
        return;
      }

      if (store.hasActiveAiRequests) {
        throw StateError(
          'یک درخواست مشاور در حال اجراست؛ '
          'پس از پایان آن گفت‌وگو را پاک کن.',
        );
      }

      final sessions = _copyRecords(store.teachingSessions);
      var changed = false;

      for (final record in sessions) {
        if (record['active'] == true) {
          record['active'] = false;
          record['updatedAt'] = DateTime.now().toIso8601String();
          changed = true;
        }
      }

      if (changed) {
        await store.saveTeachingSessions(sessions);
      }

      await store.saveMessages(<Map<String, dynamic>>[]);

      if (!_isCurrent(generation, store)) return;

      setState(() {
        _messages = [];
        _teachingSession = null;
        _teachingSessionId = null;
        _preparedPrompt = null;
        _error = null;
      });
    } on Object catch (error) {
      if (_isCurrent(generation, store)) {
        setState(() {
          _loadLocalState();
          _error = friendlyError(error);
        });
      }
    } finally {
      if (_isCurrent(generation, store)) {
        setState(() => _clearing = false);
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = _teachingSession;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height < 600 ? 140 : 230,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: SimorghChatAvatar(
                state: resolveSimorghChatState(
                  busy: _busy,
                  messages: _messages,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('simorgh-start-teaching'),
                  onPressed: _canOperate ? _startTeaching : null,
                  icon: const Icon(Icons.school_outlined),
                  label: Text(
                    session == null
                        ? 'شروع تدریس با سیمرغ'
                        : 'جلسه: ${session.topic}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (session != null)
                IconButton(
                  tooltip: 'پایان جلسه آموزشی',
                  onPressed: _canOperate ? _endTeaching : null,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (session != null) ...[
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'روش تدریس سیمرغ · '
                      '${_teachingStageLabel(session.stage)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'پاسخ سؤال قبلی را در گفت‌وگو بنویس. '
                      'اگر هنوز سؤالی دریافت نکرده‌ای، '
                      'از آماده‌سازی گام آموزشی استفاده کن.',
                    ),
                    if (!session.isComplete)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: _canOperate
                              ? () => _fillPrompt(
                                    _preparePrompt(session),
                                    preparation: true,
                                  )
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text(
                            'آماده‌سازی گام آموزشی',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          CreditSummary(
            store: widget.store,
            onShop: _canOperate ? _openShop : null,
          ),
          if (widget.store.walletError != null)
            NoticeCard(
              text: widget.store.walletError!,
              warning: true,
            ),
          if (!_service.isConfigured)
            const NoticeCard(
              text:
                  'گفت‌وگوی آنلاین در حال حاضر پیکربندی نشده است. '
                  'برنامه مطالعه، نمرات، مرور و راهنمای مطالعه '
                  'همچنان به‌صورت آفلاین قابل استفاده‌اند.',
              warning: true,
            ),
          if (_recovering)
            const NoticeCard(
              text: 'در حال بررسی و بازیابی درخواست‌های قبلی…',
              icon: Icons.restore,
            ),
          if (!_busy && _storeHasActiveRequest)
            const NoticeCard(
              text:
                  'یک درخواست مشاور در بخش دیگری از برنامه '
                  'در حال اجراست. پس از پایان آن دوباره تلاش کن.',
              icon: Icons.hourglass_top,
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    if (_error == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 110),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: colors.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'بستن پیام خطا',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() => _error = null);
              },
              icon: Icon(
                Icons.close,
                color: colors.onErrorContainer,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    const prompts = [
      'برای این هفته یک برنامه مطالعه واقع‌بینانه پیشنهاد بده.',
      'چطور نقاط قوت و ضعف درسی‌ام را بشناسم؟',
      'برای بهتر شدن تمرکزم چه تمرین‌هایی انجام دهم؟',
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Icon(
          Icons.auto_awesome,
          color: blue,
          size: 46,
        ),
        const SizedBox(height: 14),
        const Text(
          'سلام! من سیمرغم؛ '
          'بیا با هم مسیر یادگیری‌ات را پیدا کنیم.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'در فهم درس‌ها، برنامه‌ریزی و شناخت مسیرهای پیش رو '
          'همراهت هستم. پاسخ من ممکن است کامل یا درست نباشد؛ '
          'تصمیم‌های مهم را با معلم، مشاور مدرسه یا '
          'بزرگسال مورد اعتماد هم بررسی کن.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'متن پیام‌ها برای پاسخ‌گویی به سرویس بیرونی '
          'ارسال می‌شود؛ اطلاعات شخصی یا حساس ننویس.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            height: 1.7,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),
        for (final prompt in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: _canOperate
                  ? () => _fillPrompt(prompt)
                  : null,
              child: Text(
                prompt,
                textAlign: TextAlign.start,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessage(
    BuildContext context,
    Map<String, dynamic> message,
    double availableWidth,
  ) {
    final colors = Theme.of(context).colorScheme;

    final user = message['role'] == 'user';
    final status = message['status']?.toString();
    final id = message['id'];

    final incomplete = status == 'failed' || status == 'pending';

    final background = user
        ? colors.primary
        : colors.surfaceContainerLow;

    final foreground = user
        ? colors.onPrimary
        : colors.onSurface;

    final secondary = user
        ? colors.onPrimary.withValues(alpha: .8)
        : colors.onSurfaceVariant;

    return Align(
      alignment: user
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: availableWidth * .88,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: user
              ? null
              : Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'پرسش تو' : 'سیمرغ',
              style: TextStyle(
                fontSize: 11,
                color: secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              message['content']?.toString() ?? '',
              style: TextStyle(
                color: foreground,
                height: 1.8,
              ),
            ),
            if (user && incomplete) ...[
              const SizedBox(height: 8),
              Text(
                status == 'pending'
                    ? 'پاسخ این درخواست هنوز در گفت‌وگو ثبت نشده است.'
                    : 'این درخواست کامل ثبت نشد.',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                ),
              ),
              if (id is String && id.isNotEmpty)
                TextButton.icon(
                  key: ValueKey('advisor-retry-$id'),
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    disabledForegroundColor:
                        foreground.withValues(alpha: .4),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: _canOperate
                      ? () => unawaited(_request(id))
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'تلاش دوباره همین درخواست',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversation(BuildContext context) {
    if (_messages.isEmpty && !_busy) {
      return _buildEmptyState(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            (constraints.maxWidth - 32).clamp(0.0, double.infinity);

        return ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          itemCount: _messages.length + (_busy ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _messages.length) {
              return const Semantics(
                liveRegion: true,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'سیمرغ دارد پاسخ را آماده و ثبت می‌کند…',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final message = _messages[index];

            return KeyedSubtree(
              key: ValueKey(message['id'] ?? 'message-$index'),
              child: _buildMessage(
                context,
                message,
                availableWidth.toDouble(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildComposer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_preparedPrompt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text(
                  'این پیام برای دریافت گام آموزشی است '
                  'و پاسخ ارزیابی‌شونده محسوب نمی‌شود.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'پاک کردن گفت‌وگو',
                  onPressed: _canOperate && _messages.isNotEmpty
                      ? _clearChat
                      : null,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    // Drafting is allowed while the request is running.
                    enabled: !_clearing && !_managingSession,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: EducationStore.maxQuestionLength,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'با سیمرغ حرف بزن…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'ارسال پیام به سیمرغ',
                  onPressed: _canOperate &&
                          _input.text.trim().isNotEmpty
                      ? _send
                      : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              _buildHeader(context),
              _buildError(context),
              Expanded(
                child: _buildConversation(context),
              ),
              _buildComposer(context),
            ],
          ),
        ),
      ),
    );
  }
}
