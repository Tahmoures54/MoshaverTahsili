import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'education/advisor_page.dart';
import 'education/analytics_page.dart';
import 'education/assessment_pages.dart';
import 'education/backup_page.dart';
import 'education/credit_shop_page.dart';
import 'education/education_store.dart';
import 'education/family_progress_report.dart';
import 'education/learning_coach_page.dart';
import 'education/learning_engine.dart';
import 'education/referral_page.dart';
import 'education/simorgh_companion.dart';
import 'education/study_pages.dart';
import 'education/ui.dart';

export 'education/advisor_page.dart';
export 'education/assessment_pages.dart';
export 'education/study_pages.dart';
export 'education/ui.dart' show EmptyState;

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.1.2',
);

const appBuildNumber = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '5',
);

const appVersionLabel = 'نسخه $appVersion · ساخت $appBuildNumber';

const _profilePrivacyVersion = 3;
const _defaultDailyMinutes = 120;
const _maximumDailyMinutes = 1440;
const _contentMaxWidth = 920.0;

const gradeYears = <String, List<String>>{
  'ابتدایی': [
    'اول',
    'دوم',
    'سوم',
    'چهارم',
    'پنجم',
    'ششم',
  ],
  'متوسطه اول': [
    'هفتم',
    'هشتم',
    'نهم',
  ],
  'متوسطه دوم': [
    'دهم',
    'یازدهم',
    'دوازدهم',
  ],
  'دانش‌آموز کنکوری': [
    'پایه دهم',
    'پایه یازدهم',
    'پایه دوازدهم',
    'فارغ‌التحصیل',
  ],
  'دانشجو': [
    'ترم اول',
    'ترم دوم یا بالاتر',
  ],
};

/// Clamp before rounding to avoid rounding very large input values.
int _safeHomeMinutes(Object? value) {
  final num? parsed;

  if (value is num) {
    parsed = value;
  } else {
    final normalized = digitsToEnglish(
      value?.toString() ?? '',
    ).trim();

    parsed = num.tryParse(normalized);
  }

  if (parsed == null || !parsed.isFinite) {
    return 0;
  }

  return parsed.clamp(0, _maximumDailyMinutes).round();
}

/// Replace whitespace-like controls with spaces, rather than joining words.
/// Preserve Persian half-spaces and legitimate Unicode name characters.
String _normalizeProfileText(String value) {
  return value
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(
        RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _validateFullName(String? value) {
  final normalized = _normalizeProfileText(value ?? '');

  if (normalized.isEmpty) {
    return 'نام و نام خانوادگی را وارد کن.';
  }

  if (normalized.characters.length > 80) {
    return 'نام واردشده بیش از حد طولانی است.';
  }

  if (normalized.split(' ').length < 2) {
    return 'لطفاً نام و نام خانوادگی را وارد کن.';
  }

  return null;
}

String? _validateField(String? value) {
  final normalized = _normalizeProfileText(value ?? '');

  if (normalized.isEmpty) {
    return 'رشته یا «عمومی» را بنویس.';
  }

  if (normalized.characters.length > 80) {
    return 'رشته یا زمینه مورد علاقه حداکثر ۸۰ نویسه باشد.';
  }

  return null;
}

String? _validateGoal(String? value) {
  final normalized = _normalizeProfileText(value ?? '');

  if (normalized.characters.length > 300) {
    return 'هدف تحصیلی حداکثر ۳۰۰ نویسه باشد.';
  }

  return null;
}

String? _validateDailyMinutes(String? value) {
  final normalized = digitsToEnglish(value ?? '').trim();
  final parsed = int.tryParse(normalized);

  if (parsed == null) {
    return 'زمان مطالعه را با عدد وارد کن.';
  }

  if (parsed < 0 || parsed > _maximumDailyMinutes) {
    return 'زمان مطالعه باید بین ۰ تا ۱۴۴۰ دقیقه باشد.';
  }

  return null;
}

String _profileGradeLine(Map<dynamic, dynamic> profile) {
  // Stored year labels already contain any required prefix.
  // Adding "پایه" here would produce values such as "پایه پایه دهم".
  return [
    profile['grade']?.toString() ?? '',
    profile['year']?.toString() ?? '',
    profile['field']?.toString() ?? '',
  ]
      .map(_normalizeProfileText)
      .where((part) => part.isNotEmpty)
      .join(' · ');
}

/// Limit content width without forcing a fixed layout on small screens.
class _ContentWidth extends StatelessWidget {
  const _ContentWidth({
    required this.child,
    this.maxWidth = _contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: child,
        ),
      ),
    );
  }
}

class EducationApp extends StatefulWidget {
  const EducationApp({
    super.key,
    this.store,
  });

  final EducationStore? store;

  @override
  State<EducationApp> createState() => _EducationAppState();
}

class _EducationAppState extends State<EducationApp> {
  late Future<EducationStore> _future;

  Future<EducationStore> _createStore() {
    // Future.sync also converts synchronous initialization errors into
    // failed futures, so the startup error screen can handle them.
    return Future<EducationStore>.sync(() {
      final suppliedStore = widget.store;

      if (suppliedStore != null) {
        return suppliedStore;
      }

      return EducationStore.open();
    });
  }

  @override
  void initState() {
    super.initState();
    _future = _createStore();
  }

  @override
  void didUpdateWidget(covariant EducationApp oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.store, widget.store)) {
      _future = _createStore();
    }
  }

  void _retry() {
    setState(() {
      _future = _createStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سیمرغ | مشاور هوشمند تحصیلی',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: FutureBuilder<EducationStore>(
        key: ObjectKey(_future),
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingPage();
          }

          if (snapshot.hasError) {
            return _StartupErrorPage(onRetry: _retry);
          }

          final store = snapshot.data;

          if (store == null) {
            return _StartupErrorPage(onRetry: _retry);
          }

          return EntryScreen(
            key: ObjectKey(store),
            store: store,
          );
        },
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'آماده‌سازی برنامه انجام نشد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const NoticeCard(
                    text:
                        'دسترسی به ذخیره‌سازی گوشی با مشکل مواجه شد. '
                        'فضای خالی گوشی را بررسی کن و دوباره تلاش کن. '
                        'برای جلوگیری از از دست رفتن اطلاعات، '
                        'پیش از بررسی مشکل، داده‌های برنامه را پاک نکن.',
                    warning: true,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showProfileSheet(
  BuildContext context,
  EducationStore store,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Keep the form open until the user explicitly closes or saves it.
    // This also prevents dismissing it during a pending save operation.
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ProfileSheet(store: store),
  );

  return saved == true;
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({
    required this.store,
  });

  final EducationStore store;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _form = GlobalKey<FormState>();

  late final TextEditingController _fullName;
  late final TextEditingController _field;
  late final TextEditingController _goal;
  late final TextEditingController _dailyMinutes;

  late String _grade;
  late String _year;

  bool _saving = false;
  bool _shareProfileWithAi = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final current = widget.store.profile ?? {};

    _shareProfileWithAi = current['aiProfileContextConsent'] == true;

    _fullName = TextEditingController(
      text: current['fullName']?.toString() ??
          current['nickname']?.toString() ??
          '',
    );

    _field = TextEditingController(
      text: current['field']?.toString() ?? 'عمومی',
    );

    _goal = TextEditingController(
      text: current['goal']?.toString() ?? '',
    );

    final storedMinutes = current['dailyMinutes'];

    _dailyMinutes = TextEditingController(
      text: (
        storedMinutes == null
            ? _defaultDailyMinutes
            : _safeHomeMinutes(storedMinutes)
      ).toString(),
    );

    final storedGrade = current['grade']?.toString();

    _grade = gradeYears.containsKey(storedGrade)
        ? storedGrade!
        : 'متوسطه اول';

    final storedYear = current['year']?.toString();

    _year = gradeYears[_grade]!.contains(storedYear)
        ? storedYear!
        : gradeYears[_grade]!.first;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _field.dispose();
    _goal.dispose();
    _dailyMinutes.dispose();
    super.dispose();
  }

  void _close() {
    if (_saving) return;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_saving) return;

    final currentForm = _form.currentState;

    if (currentForm == null || !currentForm.validate()) {
      return;
    }

    final normalizedName = _normalizeProfileText(_fullName.text);
    final normalizedField = _normalizeProfileText(_field.text);
    final normalizedGoal = _normalizeProfileText(_goal.text);

    final dailyMinutes = int.parse(
      digitsToEnglish(_dailyMinutes.text).trim(),
    );

    // Capture all values before the asynchronous operation.
    final store = widget.store;
    final navigator = Navigator.of(context);
    final selectedGrade = _grade;
    final selectedYear = _year;
    final consent = _shareProfileWithAi;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await store.saveProfile({
        ...?store.profile,
        'fullName': normalizedName,
        'nickname': normalizedName.split(' ').first,
        'grade': selectedGrade,
        'year': selectedYear,
        'field': normalizedField,
        'goal': normalizedGoal,
        'dailyMinutes': dailyMinutes,
        'aiProfileContextConsent': consent,
        'privacyVersion': _profilePrivacyVersion,
      });

      if (!mounted) return;

      // Re-enable popping before closing the protected form.
      setState(() => _saving = false);

      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editing = widget.store.profile != null;

    return PopScope<bool>(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: _ContentWidth(
              maxWidth: 600,
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            editing
                                ? 'پروفایل تحصیلی تو'
                                : 'به جمع همراهان سیمرغ خوش آمدی',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'بستن',
                          onPressed: _saving ? null : _close,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اطلاعات این فرم برای ساختن پروفایل تحصیلی توست. '
                      'برای استفاده از برنامه، نیازی به واردکردن نام واقعی نیست؛ '
                      'اگر ترجیح می‌دهی، نام و نام خانوادگی مستعار بنویس. '
                      'در پیام‌های مشاور، نام، شماره تماس یا اطلاعات '
                      'شناسایی‌کننده وارد نکن؛ متن پیام‌ها برای پاسخ‌گویی '
                      'به سرویس بیرونی ارسال می‌شود.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _fullName,
                      enabled: !_saving,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'نام و نام خانوادگی',
                        hintText: 'واقعی یا مستعار؛ مثلاً سارا احمدی',
                      ),
                      validator: _validateFullName,
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _grade,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'مقطع تحصیلی',
                      ),
                      items: gradeYears.keys.map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;

                              setState(() {
                                _grade = value;
                                _year = gradeYears[value]!.first;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_grade),
                      initialValue: _year,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'پایه یا ترم تحصیلی',
                      ),
                      items: gradeYears[_grade]!.map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;

                              setState(() => _year = value);
                            },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _field,
                      enabled: !_saving,
                      maxLength: 80,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'رشته یا زمینه مورد علاقه',
                        hintText: 'مثلاً عمومی، تجربی یا مهندسی',
                      ),
                      validator: _validateField,
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _dailyMinutes,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9\u06F0-\u06F9\u0660-\u0669]'),
                        ),
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'هدف مطالعه روزانه',
                        suffixText: 'دقیقه',
                        helperText:
                            'برای پیشنهادهای روزانه؛ '
                            '۰ یعنی فعلاً هدف زمانی تعیین نمی‌کنم.',
                        helperMaxLines: 2,
                      ),
                      validator: _validateDailyMinutes,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _goal,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 300,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'هدف تحصیلی؛ اختیاری',
                        hintText: 'مثلاً بهبود نمره ریاضی',
                      ),
                      validator: _validateGoal,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _shareProfileWithAi,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _shareProfileWithAi = value ?? false;
                              });
                            },
                      title: const Text(
                        'اجازه استفاده سیمرغ از زمینه تحصیلی',
                      ),
                      subtitle: const Text(
                        'با این انتخاب، اجازه ارسال مقطع، پایه، رشته و '
                        'هدف تحصیلی برای شخصی‌سازی پاسخ را می‌دهی؛ '
                        'این اجازه شامل نام و نام خانوادگی نیست. '
                        'انتخاب اختیاری است و از همین فرم قابل لغو است. '
                        'لغو رضایت، اطلاعات ارسال‌شده قبلی را پس نمی‌گیرد.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: NoticeCard(
                          text: _error!,
                          warning: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _saving ? 'در حال ذخیره…' : 'ذخیره پروفایل',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving ? null : _close,
                      child: const Text('انصراف'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _accepted = false;
  bool _openingProfile = false;

  late bool _hadProfile;

  @override
  void initState() {
    super.initState();

    _hadProfile = widget.store.profile != null;
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);

      _hadProfile = widget.store.profile != null;
      _accepted = false;
      _openingProfile = false;

      widget.store.addListener(_handleStoreChanged);
    }
  }

  void _handleStoreChanged() {
    final hasProfile = widget.store.profile != null;

    if (_hadProfile && !hasProfile && mounted) {
      setState(() {
        _accepted = false;
        _openingProfile = false;
      });
    }

    _hadProfile = hasProfile;
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  Future<void> _start() async {
    if (!_accepted || _openingProfile) return;

    setState(() => _openingProfile = true);

    try {
      await showProfileSheet(context, widget.store);
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _openingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        if (widget.store.profile != null) {
          return Dashboard(
            key: ObjectKey(widget.store),
            store: widget.store,
          );
        }

        return _buildWelcome(context);
      },
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profileError = widget.store.dataError('edu.profile');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const SimorghMark(size: 116),
                  const SizedBox(height: 18),
                  Text(
                    'سیمرغ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'همراه دانای راه آینده',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: teal,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'مشاور هوشمند تحصیلی',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'سخنی با اولیا و دانش‌آموزان گرامی',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'سیمرغ برای برنامه‌ریزی، مرور و پیگیری '
                            'پیشرفت تحصیلی همراه توست. '
                            'اطلاعات تحصیلی و برنامه‌ها به‌صورت محلی '
                            'نگهداری می‌شوند. برای پاسخ‌گویی مشاور، '
                            'متن پرسش و بخشی از گفت‌وگو به سرویس '
                            'هوش مصنوعی ارسال می‌شود.',
                            style: TextStyle(height: 1.85),
                          ),
                          const SizedBox(height: 8),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(
                                bottom: 8,
                              ),
                              title: const Text(
                                'جزئیات حریم خصوصی و نکات مهم',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              children: const [
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    'اجازه استفاده از زمینه تحصیلی '
                                    'جداگانه در پروفایل انتخاب می‌شود '
                                    'و شامل ارسال نام نیست. '
                                    'تحلیل آنلاین وضعیت تحصیلی ممکن است '
                                    'پس از انتخاب تو، خلاصه نمره‌ها '
                                    'را ارسال کند. '
                                    'اطلاعات هویتی‌ای که داخل پیام '
                                    'می‌نویسی ممکن است به سرویس بیرونی '
                                    'برسد؛ پس اطلاعات حساس ننویس. '
                                    'پاسخ‌ها ممکن است اشتباه باشند '
                                    'و جایگزین معلم، مشاور مدرسه '
                                    'یا منابع رسمی نیستند. '
                                    'پاک‌کردن داده‌های برنامه یا حذف '
                                    'برنامه می‌تواند اطلاعات و اعتبار '
                                    'محلی را از بین ببرد؛ پیش از آن '
                                    'گزینه پشتیبان‌گیری را بررسی کن.',
                                    style: TextStyle(height: 1.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CheckboxListTile(
                            value: _accepted,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            onChanged: _openingProfile
                                ? null
                                : (value) {
                                    setState(() {
                                      _accepted = value ?? false;
                                    });
                                  },
                            title: const Text(
                              'توضیحات و نکات حریم خصوصی را خواندم.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.store.walletError != null)
                    NoticeCard(
                      text: widget.store.walletError!,
                      warning: true,
                    ),
                  if (profileError != null)
                    NoticeCard(
                      text: profileError,
                      warning: true,
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _accepted && !_openingProfile
                          ? _start
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        _openingProfile
                            ? 'در حال آماده‌سازی…'
                            : 'بزن بریم',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appVersionLabel,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const _titles = [
    'خانه',
    'برنامه مطالعه من',
    'آزمون‌ها و کارنامه',
    'مرور و فلش‌کارت',
    'مشاور هوشمند',
  ];

  int _index = 0;

  final Set<int> _visitedTabs = {0};

  bool _deletingWorkspace = false;
  bool _settingsOpen = false;
  bool _openingPage = false;

  @override
  void didUpdateWidget(covariant Dashboard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.store, widget.store)) {
      _index = 0;

      _visitedTabs
        ..clear()
        ..add(0);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _go(int value) {
    if (!mounted || _deletingWorkspace) return;
    if (value < 0 || value >= _titles.length) return;
    if (_index == value) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _index = value;
      _visitedTabs.add(value);
    });
  }

  Future<void> _push(Widget page) async {
    if (!mounted || _openingPage || _deletingWorkspace) return;

    _openingPage = true;

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => page,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      _openingPage = false;
      _refresh();
    }
  }

  void _openPage(Widget page) {
    unawaited(_push(page));
  }

  Future<void> _settings() async {
    if (_settingsOpen || _deletingWorkspace || _openingPage) {
      return;
    }

    _settingsOpen = true;

    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) {
          return _SettingsSheet(
            profileSummary: _profileGradeLine(
              widget.store.profile ?? {},
            ),
          );
        },
      );

      if (!mounted || choice == null) return;

      switch (choice) {
        case 'profile':
          await showProfileSheet(context, widget.store);
          _refresh();
          break;

        case 'wallet':
          await _push(CreditShopPage(store: widget.store));
          break;

        case 'reports':
          await _push(ReportsPage(store: widget.store));
          break;

        case 'backup':
          await _push(BackupPage(store: widget.store));
          break;

        case 'referral':
          await _push(const ReferralPage());
          break;

        case 'about':
          await _push(const AboutPage());
          break;

        case 'delete':
          await _deleteWorkspace();
          break;
      }
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      _settingsOpen = false;
    }
  }

  Future<void> _deleteWorkspace() async {
    if (_deletingWorkspace) return;

    final store = widget.store;

    if (store.hasActiveAiRequests) {
      showMessage(
        context,
        'صبر کن تا درخواست فعلی مشاور کامل شود.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('اطلاعات تحصیلی پاک شود؟'),
          content: const SingleChildScrollView(
            child: Text(
              'پروفایل، برنامه‌ها، نمرات، فلش‌کارت‌ها و '
              'سابقه مشاوره پاک می‌شوند.\n\n'
              'این گزینه برای حذف اطلاعات تحصیلی است و '
              'اعتبار خریداری‌شده و سابقه خرید را حذف نمی‌کند.\n\n'
              'این کار برگشت‌پذیر نیست. '
              'اگر اطلاعاتت را لازم داری، ابتدا از بخش '
              'پشتیبان‌گیری نسخه پشتیبان تهیه کن.',
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
              style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(dialogContext).colorScheme.error,
                foregroundColor:
                    Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('حذف اطلاعات'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    if (!identical(store, widget.store)) return;

    // A request may have started while the confirmation dialog was open.
    if (store.hasActiveAiRequests) {
      showMessage(
        context,
        'یک درخواست مشاور در حال اجراست. '
        'پس از پایان آن دوباره تلاش کن.',
      );
      return;
    }

    setState(() => _deletingWorkspace = true);

    try {
      await store.clear();

      if (!mounted) return;

      setState(() {
        _index = 0;

        _visitedTabs
          ..clear()
          ..add(0);
      });
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _deletingWorkspace = false);
      }
    }
  }

  Widget _buildTab(int tabIndex) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }

    final page = switch (tabIndex) {
      0 => HomePage(
          store: widget.store,
          go: _go,
          active: _index == 0,
          onReturn: _refresh,
          onOpenPage: _openPage,
        ),
      1 => PlannerPage(
          store: widget.store,
          changed: _refresh,
        ),
      2 => ExamsPage(
          store: widget.store,
          changed: _refresh,
        ),
      3 => CardsPage(
          store: widget.store,
          changed: _refresh,
        ),
      4 => AdvisorPage(store: widget.store),
      _ => const SizedBox.shrink(),
    };

    return TickerMode(
      enabled: _index == tabIndex && !_deletingWorkspace,
      child: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _index == 0 && !_deletingWorkspace,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _deletingWorkspace) return;

        if (_index != 0) {
          _go(0);
        }
      },
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _deletingWorkspace,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  _titles[_index],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'تنظیمات',
                    onPressed:
                        _deletingWorkspace ? null : _settings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: IndexedStack(
                  key: ObjectKey(widget.store),
                  index: _index,
                  children: List<Widget>.generate(
                    _titles.length,
                    _buildTab,
                  ),
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _go,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'خانه',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month),
                    label: 'برنامه',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.assessment_outlined),
                    selectedIcon: Icon(Icons.assessment),
                    label: 'آزمون',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.style_outlined),
                    selectedIcon: Icon(Icons.style),
                    label: 'مرور',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome),
                    label: 'مشاور',
                  ),
                ],
              ),
            ),
          ),
          if (_deletingWorkspace) ...[
            const ModalBarrier(
              dismissible: false,
              color: Colors.black38,
            ),
            Center(
              child: Semantics(
                liveRegion: true,
                label: 'در حال حذف اطلاعات تحصیلی',
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'در حال حذف اطلاعات…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text('لطفاً منتظر بمان.'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.profileSummary,
  });

  final String profileSummary;

  void _select(BuildContext context, String choice) {
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: _ContentWidth(
          maxWidth: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تنظیمات و اطلاعات',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'بستن',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('ویرایش پروفایل تحصیلی'),
                subtitle: Text(
                  profileSummary.isEmpty
                      ? 'اطلاعات تحصیلی ثبت نشده'
                      : profileSummary,
                ),
                onTap: () => _select(context, 'profile'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                ),
                title: const Text('کیف اعتبار و تاریخچه خرید'),
                onTap: () => _select(context, 'wallet'),
              ),
              ListTile(
                leading: const Icon(Icons.history_edu_outlined),
                title: const Text('تاریخچه مشاوره‌ها'),
                onTap: () => _select(context, 'reports'),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('پشتیبان‌گیری و بازیابی'),
                onTap: () => _select(context, 'backup'),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('معرفی سیمرغ به دوستان'),
                subtitle: const Text('ارسال لینک نصب از کافه‌بازار'),
                onTap: () => _select(context, 'referral'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('درباره برنامه و حریم خصوصی'),
                subtitle: const Text(appVersionLabel),
                onTap: () => _select(context, 'about'),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'حذف اطلاعات تحصیلی این گوشی',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () => _select(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.go,
    this.active = false,
    this.onReturn,
    this.onOpenPage,
  });

  final EducationStore store;
  final ValueChanged<int> go;
  final bool active;
  final VoidCallback? onReturn;

  /// Dashboard can provide a shared navigation guard.
  final ValueChanged<Widget>? onOpenPage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _openingPage = false;

  Future<void> _push(Widget page) async {
    final externalOpen = widget.onOpenPage;

    if (externalOpen != null) {
      externalOpen(page);
      return;
    }

    if (_openingPage || !mounted) return;

    _openingPage = true;

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => page,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      _openingPage = false;

      if (mounted) {
        setState(() {});
        widget.onReturn?.call();
      }
    }
  }

  void _open(Widget page) {
    unawaited(_push(page));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final store = widget.store;
    final profile = store.profile ?? {};
    final tasks = store.tasks;
    final exams = store.exams;
    final cards = store.cards;

    // Use the same timestamp for all calculations in this build.
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));

    // Only count tasks with a known completion timestamp in the window.
    // Legacy tasks without completedAt remain excluded.
    final completed = tasks.where((task) {
      if (task['done'] != true) return false;

      final date = DateTime.tryParse(
        task['completedAt']?.toString() ?? '',
      );

      return date != null &&
          !date.isBefore(weekStart) &&
          !date.isAfter(now);
    }).toList();

    final minutes = completed.fold<int>(
      0,
      (sum, task) => sum + _safeHomeMinutes(task['minutes']),
    );

    final storedDailyMinutes = profile['dailyMinutes'];

    final dailyMinutes = storedDailyMinutes == null
        ? _defaultDailyMinutes
        : _safeHomeMinutes(storedDailyMinutes);

    final report = buildLearningReport(
      exams: exams,
      tasks: tasks,
      cards: cards,
      now: now,
    );

    final suggestions = dailySuggestions(
      report: report,
      tasks: tasks,
      deadlines: store.deadlines,
      now: now,
      dailyMinutes: dailyMinutes,
    );

    final fullName = _normalizeProfileText(
      profile['fullName']?.toString() ?? '',
    );

    final nickname = fullName.isNotEmpty
        ? fullName.split(' ').first
        : _normalizeProfileText(
            profile['nickname']?.toString() ?? '',
          );

    final profileError = store.dataError('edu.profile');

    return _ContentWidth(
      child: ListView(
        key: const PageStorageKey<String>('education-home-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (store.walletError != null)
            Semantics(
              liveRegion: true,
              child: NoticeCard(
                text: store.walletError!,
                warning: true,
              ),
            ),
          if (profileError != null)
            NoticeCard(
              text: profileError,
              warning: true,
            ),
          SimorghHomeHero(
            nickname: nickname,
            gradeLine: _profileGradeLine(profile),
            onChat: () => widget.go(4),
          ),
          const SizedBox(height: 14),
          const SimorghSectionTitle(
            title: 'پیشنهاد امروز سیمرغ',
            subtitle: 'یک قدم کوچک و متناسب با وضعیت فعلی تو.',
          ),
          SimorghCompanion(
            tasks: tasks,
            cards: cards,
            grade: profile['grade']?.toString() ?? '',
            active: widget.active,
            onAction: (action) {
              widget.go(
                switch (action) {
                  SimorghAction.planner => 1,
                  SimorghAction.review => 3,
                  SimorghAction.advisor => 4,
                },
              );
            },
            onChat: () => widget.go(4),
          ),
          const SimorghSectionTitle(
            title: 'رد پای تلاش تو',
            subtitle: 'پیشرفت را با قدم‌های خودت بسنج، نه با دیگران.',
          ),
          _HomeStats(
            completedTasks: tasks.where(
              (task) => task['done'] == true,
            ).length,
            totalTasks: tasks.length,
            examCount: exams.length,
            cardCount: cards.length,
          ),
          const SizedBox(height: 8),
          NoticeCard(
            text:
                'در هفت روز اخیر، ${faNumber(completed.length)} '
                'کار تکمیل شده است؛ برای این کارها '
                '${faNumber(minutes)} دقیقه زمان برنامه‌ریزی شده بود. '
                'این عدد، زمان واقعی مطالعه را اندازه‌گیری نمی‌کند.',
            icon: Icons.insights_outlined,
          ),
          if (dailyMinutes > 0)
            NoticeCard(
              text:
                  'هدف مطالعه روزانه تو: '
                  '${faNumber(dailyMinutes)} دقیقه. '
                  'می‌توانی آن را از تنظیمات پروفایل تغییر بدهی.',
              icon: Icons.schedule_outlined,
            ),
          for (final tip in suggestions)
            NoticeCard(
              text: tip,
              icon: Icons.lightbulb_outline,
            ),
          const SimorghSectionTitle(
            title: 'برنامه‌ریزی و یادگیری',
            subtitle: 'برای ساختن عادت مطالعه و یادگیری ماندگار.',
          ),
          QuickTile(
            icon: Icons.calendar_month,
            title: 'برنامه مطالعه',
            subtitle: 'ثبت و پیگیری کارهای درسی',
            onTap: () => widget.go(1),
          ),
          QuickTile(
            icon: Icons.style_outlined,
            title: 'مرور و فلش‌کارت',
            subtitle: 'یادگیری ماندگار با مرور فاصله‌دار',
            onTap: () => widget.go(3),
          ),
          QuickTile(
            icon: Icons.auto_awesome,
            title: 'مربی یادگیری شخصی',
            subtitle: 'پیشنهاد قدم بعدی بر اساس برنامه، نمره‌ها و مرورها',
            onTap: () => _open(
              LearningCoachPage(store: store),
            ),
          ),
          QuickTile(
            icon: Icons.menu_book_outlined,
            title: 'روش‌های مؤثر مطالعه',
            subtitle: 'راهنمای آفلاین تمرکز و یادگیری',
            onTap: () => _open(const StudyTipsPage()),
          ),
          const SimorghSectionTitle(
            title: 'سنجش و تحلیل پیشرفت',
            subtitle: 'عملکردت را ببین و برای بهترشدن تصمیم بگیر.',
          ),
          QuickTile(
            icon: Icons.assessment_outlined,
            title: 'آزمون و کارنامه',
            subtitle: 'ثبت نمرات و مشاهده میانگین',
            onTap: () => widget.go(2),
          ),
          QuickTile(
            icon: Icons.insights_outlined,
            title: 'بررسی وضعیت تحصیلی',
            subtitle: 'نقاط قوت و ضعف بر اساس نمره‌های تو',
            onTap: () => _open(
              AcademicInsightsPage(store: store),
            ),
          ),
          QuickTile(
            icon: Icons.query_stats_outlined,
            title: 'تحلیل عملکرد و پایبندی',
            subtitle: 'روند درس‌ها و ساعت مطالعه، از داده‌های خودت',
            onTap: () => _open(
              AnalyticsPage(store: store),
            ),
          ),
          const SimorghSectionTitle(
            title: 'مشاوره و آینده تحصیلی',
            subtitle: 'برای پرسش‌ها و انتخاب قدم بعدی.',
          ),
          QuickTile(
            icon: Icons.auto_awesome,
            title: 'گفت‌وگو با مشاور هوشمند',
            subtitle: 'پرسش، برنامه مطالعه و روش بهبود',
            onTap: () => widget.go(4),
          ),
          QuickTile(
            icon: Icons.explore_outlined,
            title: 'راهنمای انتخاب رشته',
            subtitle: 'شناخت علاقه‌ها و مسیرهای ممکن',
            onTap: () => _open(
              CareerPage(store: store),
            ),
          ),
          const SimorghSectionTitle(
            title: 'همراهی خانواده و امکانات بیشتر',
            subtitle: 'گزارش، سوابق و معرفی سیمرغ.',
          ),
          QuickTile(
            icon: Icons.people_outline,
            title: 'گزارش برای خانواده',
            subtitle: 'پیش‌نمایش و کپی خلاصه پیشرفت با انتخاب خودت',
            onTap: () => _open(
              FamilyProgressReportPage(store: store),
            ),
          ),
          QuickTile(
            icon: Icons.history_edu_outlined,
            title: 'تاریخچه مشاوره‌ها',
            subtitle: 'پاسخ‌های قبلی و درخواست‌های ناتمام',
            onTap: () => _open(
              ReportsPage(store: store),
            ),
          ),
          QuickTile(
            icon: Icons.backup_outlined,
            title: 'پشتیبان‌گیری و بازیابی',
            subtitle: 'پیش از حذف یا جابه‌جایی داده‌ها، پشتیبان بگیر',
            onTap: () => _open(
              BackupPage(store: store),
            ),
          ),
          QuickTile(
            icon: Icons.share_outlined,
            title: 'معرفی سیمرغ به دوستان',
            subtitle: 'ارسال لینک نصب برنامه برای دوستان',
            onTap: () => _open(const ReferralPage()),
          ),
          const SimorghSectionTitle(
            title: 'کیف اعتبار',
            subtitle: 'اعتبار و پرسش‌های رایگان در یک نگاه.',
          ),
          CreditSummary(
            store: store,
            onShop: () => _open(
              CreditShopPage(store: store),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStats extends StatelessWidget {
  const _HomeStats({
    required this.completedTasks,
    required this.totalTasks,
    required this.examCount,
    required this.cardCount,
  });

  final int completedTasks;
  final int totalTasks;
  final int examCount;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      StatCard(
        title: 'کارهای انجام‌شده',
        value: '${faNumber(completedTasks)}/${faNumber(totalTasks)}',
        icon: Icons.task_alt,
      ),
      StatCard(
        title: 'آزمون‌ها',
        value: faNumber(examCount),
        icon: Icons.assessment_outlined,
      ),
      StatCard(
        title: 'فلش‌کارت‌ها',
        value: faNumber(cardCount),
        icon: Icons.style_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;

        final columns = constraints.maxWidth >= 360 && !largeText
            ? 3
            : 1;

        const spacing = 8.0;

        final width = (
          constraints.maxWidth - spacing * (columns - 1)
        ) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: '$title: $value',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 8,
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SizedBox.shrink(),
                // Icon is rendered below through the stack-free
                // replacement in the next widget.
              ),
              const SizedBox(height: 8),
              Icon(
                icon,
                color: teal,
                size: 22,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 5,
        ),
        minVerticalPadding: 10,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: teal.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: teal,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
            height: 1.5,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            height: 1.6,
            color: colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          isRtl ? Icons.chevron_left : Icons.chevron_right,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('درباره سیمرغ'),
      ),
      body: SafeArea(
        top: false,
        child: _ContentWidth(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Center(
                child: SimorghMark(size: 104),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'سیمرغ',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'همراه دانای راه آینده',
                  style: TextStyle(
                    color: teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const NoticeCard(
                text:
                    '$appVersionLabel\n'
                    'شناسه برنامه: ir.moshaver.tahsili',
                icon: Icons.auto_awesome,
              ),
              const NoticeCard(
                text:
                    'برنامه‌ریزی، ثبت نمره‌ها، فلش‌کارت‌ها و '
                    'راهنماهای مطالعه برای استفاده محلی طراحی شده‌اند. '
                    'گفت‌وگو با مشاور و عملیات خرید بازار '
                    'به اینترنت نیاز دارند.',
                icon: Icons.offline_bolt_outlined,
              ),
              const NoticeCard(
                text:
                    'برای پاسخ‌گویی مشاور، متن پرسش و بخشی از '
                    'گفت‌وگو به سرویس بیرونی ارسال می‌شود. '
                    'اطلاعات هویتی‌ای که خودت در پیام می‌نویسی '
                    'نیز می‌تواند همراه پیام ارسال شود؛ '
                    'نام، شماره تماس، نشانی یا اطلاعات حساس ننویس.',
                icon: Icons.privacy_tip_outlined,
              ),
              const NoticeCard(
                text:
                    'انتخاب اجازه استفاده از زمینه تحصیلی در '
                    'پروفایل اختیاری است و شامل ارسال نام نیست. '
                    'این انتخاب برای مقطع، پایه، رشته و هدف '
                    'تحصیلی است و از تنظیمات قابل لغو است. '
                    'لغو رضایت، اطلاعات ارسال‌شده قبلی را از '
                    'سرویس بیرونی حذف نمی‌کند. '
                    'برای فرم پروفایل می‌توانی از نام مستعار '
                    'استفاده کنی.',
                icon: Icons.manage_accounts_outlined,
              ),
              const NoticeCard(
                text:
                    'داده‌های محلی جایگزین حساب کاربری و '
                    'ذخیره‌سازی امن سمت سرور نیستند. '
                    'پاک‌کردن داده‌های برنامه یا حذف برنامه '
                    'می‌تواند اطلاعات و اعتبار محلی را از بین ببرد. '
                    'پیش از حذف یا جابه‌جایی داده‌ها، امکانات '
                    'پشتیبان‌گیری و محدودیت‌های آن را بررسی کن.',
                icon: Icons.backup_outlined,
              ),
              const NoticeCard(
                text:
                    'بررسی خرید با امضای بازار و دفتر محلی، '
                    'جایگزین اعتبارسنجی سمت سرور نیست. '
                    'داده‌های گوشی ممکن است دست‌کاری شوند و '
                    'انتقال اعتبار میان دستگاه‌ها تضمین نشده است. '
                    'اگر کلید اتصال سرویس در APK قرار بگیرد، '
                    'قابل استخراج است و نباید محرمانه فرض شود.',
                icon: Icons.security_outlined,
              ),
              const NoticeCard(
                text:
                    'پاسخ سیمرغ ممکن است اشتباه باشد. '
                    'تصمیم‌های مهم تحصیلی را با معلم، مشاور '
                    'مدرسه و منابع رسمی بررسی کن. '
                    'این برنامه تشخیص پزشکی یا روان‌شناختی '
                    'ارائه نمی‌دهد.',
                warning: true,
              ),
              const NoticeCard(
                text:
                    'در تنظیمات فعلی، فایل فونت Vazirmatn '
                    'داخل برنامه تعریف نشده است؛ نمایش آن '
                    'به در دسترس بودن فونت وابسته است و در '
                    'غیر این صورت فونت جایگزین نمایش داده می‌شود.',
                icon: Icons.text_fields_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
