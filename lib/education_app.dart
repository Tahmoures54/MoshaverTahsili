import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'education/advisor_page.dart';
import 'education/assessment_pages.dart';
import 'education/backup_page.dart';
import 'education/credit_shop_page.dart';
import 'education/education_store.dart';
import 'education/learning_engine.dart';
import 'education/referral_page.dart';
import 'education/study_pages.dart';
import 'education/ui.dart';

export 'education/advisor_page.dart';
export 'education/assessment_pages.dart';
export 'education/study_pages.dart';
export 'education/ui.dart' show EmptyState;

const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.1.2');

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
  'ابتدایی': ['اول', 'دوم', 'سوم', 'چهارم', 'پنجم', 'ششم'],
  'متوسطه اول': ['هفتم', 'هشتم', 'نهم'],
  'متوسطه دوم': ['دهم', 'یازدهم', 'دوازدهم'],
  'دانش‌آموز کنکوری': [
    'پایه دهم',
    'پایه یازدهم',
    'پایه دوازدهم',
    'فارغ‌التحصیل',
  ],
  'دانشجو': ['ترم اول', 'ترم دوم یا بالاتر'],
};

int _safeHomeMinutes(Object? value) {
  final num? parsed = value is num
      ? value
      : num.tryParse(digitsToEnglish(value?.toString() ?? ''));

  if (parsed == null || !parsed.isFinite) return 0;

  return parsed.clamp(0, _maximumDailyMinutes).round();
}

String _normalizeProfileText(String value) {
  return value
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _storedText(Object? value, {String fallback = ''}) {
  final text = _normalizeProfileText(value?.toString() ?? '');

  return text.isEmpty || text == 'null' ? fallback : text;
}

DateTime? _storedDate(Object? value) {
  if (value is DateTime) return value;

  return DateTime.tryParse(value?.toString() ?? '');
}

DateTime _startOfDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _dateLabel(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');

  // This is a Gregorian date, not a Jalali conversion.
  return faNumber('${local.year}/$month/$day');
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
    return 'نام و نام خانوادگی واقعی یا مستعار را وارد کن.';
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
  if (_normalizeProfileText(value ?? '').characters.length > 300) {
    return 'هدف تحصیلی حداکثر ۳۰۰ نویسه باشد.';
  }

  return null;
}

String? _validateDailyMinutes(String? value) {
  final parsed = int.tryParse(digitsToEnglish(value ?? ''));

  if (parsed == null) {
    return 'زمان مطالعه را با عدد وارد کن.';
  }

  if (parsed < 0 || parsed > _maximumDailyMinutes) {
    return 'زمان مطالعه باید بین ۰ تا ۱۴۴۰ دقیقه باشد.';
  }

  return null;
}

String _profileGradeLine(Map<dynamic, dynamic> profile) {
  return [
    _storedText(profile['grade']),
    _storedText(profile['year']),
    _storedText(profile['field']),
  ].where((part) => part.isNotEmpty).join(' · ');
}

class _ContentWidth extends StatelessWidget {
  const _ContentWidth({required this.child, this.maxWidth = _contentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class EducationApp extends StatefulWidget {
  const EducationApp({super.key, this.store});

  final EducationStore? store;

  @override
  State<EducationApp> createState() => _EducationAppState();
}

class _EducationAppState extends State<EducationApp> {
  late Future<EducationStore> _future;

  Future<EducationStore> _createStore() {
    return Future<EducationStore>.sync(() {
      final suppliedStore = widget.store;

      if (suppliedStore != null) return suppliedStore;

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
    if (!mounted) return;

    setState(() => _future = _createStore());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سیمرغ | مشاور هوشمند تحصیلی',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: FutureBuilder<EducationStore>(
        key: ObjectKey(_future),
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingPage();
          }

          final store = snapshot.data;

          if (snapshot.hasError || store == null) {
            return _StartupErrorPage(onRetry: _retry);
          }

          return EntryScreen(key: ObjectKey(store), store: store);
        },
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.onRetry});

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
                  const Icon(Icons.storage_outlined, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'آماده‌سازی برنامه انجام نشد',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const NoticeCard(
                    text:
                        'راه‌اندازی برنامه با مشکل مواجه شد. '
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
  if (!context.mounted) return false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
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

    // Do not silently carry forward consent from an older privacy version.
    final privacyVersion =
        int.tryParse(current['privacyVersion']?.toString() ?? '') ?? 0;

    _shareProfileWithAi =
        current['aiProfileContextConsent'] == true &&
        privacyVersion >= _profilePrivacyVersion;

    _fullName = TextEditingController(
      text: _storedText(
        current['fullName'],
        fallback: _storedText(current['nickname']),
      ),
    );

    _field = TextEditingController(
      text: _storedText(current['field'], fallback: 'عمومی'),
    );

    _goal = TextEditingController(text: _storedText(current['goal']));

    final storedMinutes = current['dailyMinutes'];

    _dailyMinutes = TextEditingController(
      text: faNumber(
        storedMinutes == null
            ? _defaultDailyMinutes
            : _safeHomeMinutes(storedMinutes),
      ),
    );

    final storedGrade = _storedText(current['grade']);

    _grade = gradeYears.containsKey(storedGrade) ? storedGrade : 'متوسطه اول';

    final storedYear = _storedText(current['year']);

    _year = gradeYears[_grade]!.contains(storedYear)
        ? storedYear
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
    if (_saving || !mounted) return;
    if (_form.currentState?.validate() != true) return;

    final normalizedName = _normalizeProfileText(_fullName.text);
    final normalizedField = _normalizeProfileText(_field.text);
    final normalizedGoal = _normalizeProfileText(_goal.text);

    final dailyMinutes = int.tryParse(digitsToEnglish(_dailyMinutes.text));

    if (dailyMinutes == null) return;

    final store = widget.store;
    final navigator = Navigator.of(context);

    // Capture inputs before awaiting storage.
    final values = <String, dynamic>{
      ...?store.profile,
      'fullName': normalizedName,
      'nickname': normalizedName.split(' ').first,
      'grade': _grade,
      'year': _year,
      'field': normalizedField,
      'goal': normalizedGoal,
      'dailyMinutes': dailyMinutes,
      'aiProfileContextConsent': _shareProfileWithAi,
      'privacyVersion': _profilePrivacyVersion,
    };

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await store.saveProfile(values);

      if (!mounted) return;

      setState(() => _saving = false);

      // Allow PopScope to rebuild with canPop=true before closing.
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted || !navigator.mounted) return;

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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      'نیازی به واردکردن نام واقعی نیست؛ '
                      'می‌توانی نام و نام خانوادگی مستعار بنویسی. '
                      'در پیام‌های مشاور، نام، شماره تماس یا اطلاعات '
                      'شناسایی‌کننده وارد نکن؛ متن پیام‌ها برای '
                      'پاسخ‌گویی به سرویس بیرونی ارسال می‌شود.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const Key('profile_name_field'),
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
                      items: [
                        for (final value in gradeYears.keys)
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
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
                      items: [
                        for (final value in gradeYears[_grade]!)
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
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
                        helperText: '۰ یعنی فعلاً هدف زمانی تعیین نمی‌کنم.',
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
                      title: const Text('اجازه استفاده سیمرغ از زمینه تحصیلی'),
                      subtitle: const Text(
                        'اجازه ارسال مقطع، پایه، رشته و هدف تحصیلی '
                        'برای شخصی‌سازی پاسخ؛ این اجازه شامل نام نیست. '
                        'انتخاب اختیاری است و از همین فرم قابل لغو است. '
                        'لغو رضایت، اطلاعات ارسال‌شده قبلی را پس نمی‌گیرد.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: NoticeCard(text: _error!, warning: true),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('save_profile_button'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره پروفایل'),
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
  const EntryScreen({super.key, required this.store});

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
      setState(() => _accepted = false);
    }

    _hadProfile = hasProfile;
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  Future<void> _start() async {
    if (!_accepted || _openingProfile || !mounted) return;

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
          return Dashboard(key: ObjectKey(widget.store), store: widget.store);
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
                  const Text(
                    'سیمرغ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: navy,
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
                    style: TextStyle(color: colors.onSurfaceVariant),
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
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: const ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: EdgeInsets.only(bottom: 8),
                              title: Text(
                                'جزئیات حریم خصوصی و نکات مهم',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    'اجازه استفاده از زمینه تحصیلی '
                                    'جداگانه در پروفایل انتخاب می‌شود '
                                    'و شامل ارسال نام نیست. '
                                    'در صورت استفاده از تحلیل آنلاین، '
                                    'خلاصه اطلاعات تحصیلی ممکن است '
                                    'برای پاسخ‌گویی ارسال شود. '
                                    'اطلاعات حساس داخل پیام ننویس. '
                                    'پاسخ‌ها ممکن است اشتباه باشند و '
                                    'جایگزین معلم، مشاور مدرسه یا '
                                    'منابع رسمی نیستند. '
                                    'پاک‌کردن داده‌ها یا حذف برنامه '
                                    'می‌تواند اطلاعات محلی را از بین ببرد؛ '
                                    'پیش از آن پشتیبان‌گیری را بررسی کن.',
                                    style: TextStyle(height: 1.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CheckboxListTile(
                            key: const Key('consent_checkbox'),
                            value: _accepted,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
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
                    NoticeCard(text: widget.store.walletError!, warning: true),
                  if (profileError != null)
                    NoticeCard(text: profileError, warning: true),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('start_button'),
                      onPressed: _accepted && !_openingProfile ? _start : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        _openingProfile ? 'در حال آماده‌سازی…' : 'بزن بریم',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    faNumber(appVersionLabel),
                    textAlign: TextAlign.center,
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
  const Dashboard({super.key, required this.store});

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
    if (mounted) setState(() {});
  }

  void _go(int value) {
    if (!mounted || _deletingWorkspace || _openingPage) return;
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
      FocusScope.of(context).unfocus();

      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
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
    if (!mounted || _settingsOpen || _deletingWorkspace || _openingPage) {
      return;
    }

    _settingsOpen = true;
    final store = widget.store;

    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _SettingsSheet(
          profileSummary: _profileGradeLine(store.profile ?? {}),
        ),
      );

      if (!mounted || choice == null || !identical(store, widget.store)) {
        return;
      }

      switch (choice) {
        case 'profile':
          await showProfileSheet(context, store);
          _refresh();
          break;
        case 'wallet':
          await _push(CreditShopPage(store: store));
          break;
        case 'reports':
          await _push(ReportsPage(store: store));
          break;
        case 'progress':
          await _push(_LocalProgressPage(store: store));
          break;
        case 'backup':
          await _push(BackupPage(store: store));
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
    if (!mounted || _deletingWorkspace) return;

    final store = widget.store;

    if (store.hasActiveAiRequests) {
      showMessage(context, 'صبر کن تا درخواست فعلی مشاور کامل شود.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          title: const Text('اطلاعات تحصیلی پاک شود؟'),
          content: const SingleChildScrollView(
            child: Text(
              'پروفایل، برنامه‌ها، نمرات، فلش‌کارت‌ها و '
              'سابقه مشاوره پاک می‌شوند.\n\n'
              'این گزینه برای حذف اطلاعات تحصیلی است، '
              'نه حذف اعتبار خریداری‌شده و سابقه خرید.\n\n'
              'این کار برگشت‌پذیر نیست. '
              'اگر اطلاعاتت را لازم داری، ابتدا از بخش '
              'پشتیبان‌گیری نسخه پشتیبان تهیه کن.',
              style: TextStyle(height: 1.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف اطلاعات'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    if (!identical(store, widget.store)) return;

    if (store.hasActiveAiRequests) {
      showMessage(
        context,
        'یک درخواست مشاور در حال اجراست. '
        'پس از پایان آن دوباره تلاش کن.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _deletingWorkspace = true);

    try {
      // Contract: EducationStore.clear() must clear the educational workspace
      // without deleting the wallet or purchase records.
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

    final Widget page = switch (tabIndex) {
      0 => HomePage(
        store: widget.store,
        go: _go,
        active: _index == 0,
        onReturn: _refresh,
        onOpenPage: _openPage,
      ),
      1 => PlannerPage(store: widget.store, changed: _refresh),
      2 => ExamsPage(store: widget.store, changed: _refresh),
      3 => CardsPage(store: widget.store, changed: _refresh),
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
        if (_index != 0) _go(0);
      },
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _deletingWorkspace,
            child: Scaffold(
              appBar: AppBar(
                title: Text(_titles[_index]),
                actions: [
                  IconButton(
                    tooltip: 'تنظیمات',
                    onPressed: _deletingWorkspace ? null : _settings,
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
                  children: List<Widget>.generate(_titles.length, _buildTab),
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
            const ModalBarrier(dismissible: false, color: Colors.black38),
            Center(
              child: Semantics(
                liveRegion: true,
                label: 'در حال حذف اطلاعات تحصیلی',
                child: Card(
                  margin: const EdgeInsets.all(24),
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
  const _SettingsSheet({required this.profileSummary});

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
                padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 8, 8),
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
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('کیف اعتبار و تاریخچه خرید'),
                onTap: () => _select(context, 'wallet'),
              ),
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('گزارش محلی پیشرفت'),
                subtitle: const Text('بدون ارسال اطلاعات به سرویس بیرونی'),
                onTap: () => _select(context, 'progress'),
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
                subtitle: Text(faNumber(appVersionLabel)),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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

/// Derived local statistics; no network calls are made here.
class _LearningSnapshot {
  const _LearningSnapshot({
    required this.totalTasks,
    required this.doneTasks,
    required this.pendingTasks,
    required this.overdueTasks,
    required this.weekTasks,
    required this.weekMinutes,
    required this.todayMinutes,
    required this.dailyMinutes,
    required this.totalCards,
    required this.dueCards,
    required this.validExams,
    required this.average,
    required this.subjectAverages,
    required this.dayMinutes,
    required this.nextTask,
    required this.nextExamSubject,
    required this.nextExamDate,
  });

  final int totalTasks;
  final int doneTasks;
  final int pendingTasks;
  final int overdueTasks;
  final int weekTasks;
  final int weekMinutes;
  final int todayMinutes;
  final int dailyMinutes;
  final int totalCards;
  final int dueCards;
  final int validExams;
  final double? average;
  final Map<String, double> subjectAverages;
  final Map<DateTime, int> dayMinutes;
  final String? nextTask;
  final String? nextExamSubject;
  final DateTime? nextExamDate;

  double get completionRatio {
    if (totalTasks == 0) return 0;
    return (doneTasks / totalTasks).clamp(0.0, 1.0).toDouble();
  }

  double? get dailyRatio {
    if (dailyMinutes <= 0) return null;
    return (todayMinutes / dailyMinutes).clamp(0.0, 1.0).toDouble();
  }

  factory _LearningSnapshot.fromStore(EducationStore store, DateTime now) {
    final today = _startOfDay(now);

    // Seven calendar days including today, not a rolling 168-hour window.
    final weekStart = DateTime(today.year, today.month, today.day - 6);

    final dayMinutes = <DateTime, int>{
      for (var offset = 0; offset < 7; offset++)
        DateTime(weekStart.year, weekStart.month, weekStart.day + offset): 0,
    };

    var doneTasks = 0;
    var overdueTasks = 0;
    var weekTasks = 0;
    var weekMinutes = 0;
    var todayMinutes = 0;

    final pending = <Map<String, dynamic>>[];

    for (final task in store.tasks) {
      if (task['done'] == true) {
        doneTasks++;

        final completedAt = _storedDate(task['completedAt']);

        if (completedAt == null ||
            completedAt.isAfter(now) ||
            completedAt.isBefore(weekStart)) {
          continue;
        }

        final minutes = _safeHomeMinutes(task['minutes']);
        final completedDay = _startOfDay(completedAt);

        weekTasks++;
        weekMinutes += minutes;

        dayMinutes.update(
          completedDay,
          (oldValue) => oldValue + minutes,
          ifAbsent: () => minutes,
        );

        if (completedDay == today) {
          todayMinutes += minutes;
        }
      } else {
        pending.add(task);

        final dueDate = _storedDate(task['dueDate']);

        if (dueDate != null && _startOfDay(dueDate).isBefore(today)) {
          overdueTasks++;
        }
      }
    }

    pending.sort((a, b) {
      final aDate = _storedDate(a['dueDate']);
      final bDate = _storedDate(b['dueDate']);

      if (aDate == null && bDate == null) {
        return _storedText(a['title']).compareTo(_storedText(b['title']));
      }

      if (aDate == null) return 1;
      if (bDate == null) return -1;

      return aDate.compareTo(bDate);
    });

    final subjectScores = <String, List<double>>{};
    final percentages = <double>[];

    for (final exam in store.exams) {
      final percentage = examPercentage(exam);

      if (percentage == null ||
          !percentage.isFinite ||
          percentage < 0 ||
          percentage > 100) {
        continue;
      }

      percentages.add(percentage);

      final subject = _storedText(exam['subject'], fallback: 'درس نامشخص');

      subjectScores.putIfAbsent(subject, () => []).add(percentage);
    }

    final subjectAverages = <String, double>{
      for (final entry in subjectScores.entries)
        entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
    };

    String? nextExamSubject;
    DateTime? nextExamDate;

    for (final deadline in store.deadlines) {
      final date = _storedDate(deadline['date']);

      if (date == null) continue;

      final day = _startOfDay(date);
      if (day.isBefore(today)) continue;

      if (nextExamDate == null || day.isBefore(nextExamDate)) {
        nextExamDate = day;
        nextExamSubject = _storedText(
          deadline['subject'],
          fallback: 'درس نامشخص',
        );
      }
    }

    final storedMinutes = store.profile?['dailyMinutes'];

    return _LearningSnapshot(
      totalTasks: store.tasks.length,
      doneTasks: doneTasks,
      pendingTasks: pending.length,
      overdueTasks: overdueTasks,
      weekTasks: weekTasks,
      weekMinutes: weekMinutes,
      todayMinutes: todayMinutes,
      dailyMinutes: storedMinutes == null
          ? _defaultDailyMinutes
          : _safeHomeMinutes(storedMinutes),
      totalCards: store.cards.length,
      dueCards: store.cards.where((card) => isCardDue(card, now)).length,
      validExams: percentages.length,
      average: percentages.isEmpty
          ? null
          : percentages.reduce((a, b) => a + b) / percentages.length,
      subjectAverages: subjectAverages,
      dayMinutes: dayMinutes,
      nextTask: pending.isEmpty
          ? null
          : _storedText(pending.first['title'], fallback: 'برنامه بعدی'),
      nextExamSubject: nextExamSubject,
      nextExamDate: nextExamDate,
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
  final ValueChanged<Widget>? onOpenPage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _openingPage = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active) {
      _syncClock();
    }
  }

  void _syncClock() {
    _clock?.cancel();
    _clock = null;

    final lifecycle = WidgetsBinding.instance.lifecycleState;

    if (!widget.active ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }

    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.active) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncClock();

    if (state == AppLifecycleState.resumed && mounted && widget.active) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _push(Widget page) async {
    if (!mounted) return;

    final externalOpen = widget.onOpenPage;

    if (externalOpen != null) {
      externalOpen(page);
      return;
    }

    if (_openingPage) return;
    _openingPage = true;

    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
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
      builder: (context, _) {
        final store = widget.store;
        final profile = store.profile ?? {};
        final snapshot = _LearningSnapshot.fromStore(store, DateTime.now());

        final fullName = _storedText(profile['fullName']);
        final nickname = fullName.isNotEmpty
            ? fullName.split(' ').first
            : _storedText(profile['nickname']);

        final goal = _storedText(profile['goal']);

        return _ContentWidth(
          child: ListView(
            key: const PageStorageKey<String>('education-home-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              ..._dataNotices(store),
              SimorghHomeHero(
                nickname: nickname,
                gradeLine: _profileGradeLine(profile),
                onChat: () => widget.go(4),
              ),
              const SizedBox(height: 14),
              CreditSummary(
                store: store,
                onShop: () => _open(CreditShopPage(store: store)),
              ),
              const SimorghSectionTitle(
                title: 'پیشنهاد امروز سیمرغ',
                subtitle: 'پیشنهادهای ساده بر اساس اطلاعات محلی تو.',
              ),
              _DailySuggestions(snapshot: snapshot, go: widget.go),
              if (goal.isNotEmpty)
                NoticeCard(text: 'هدف تو: $goal', icon: Icons.flag_outlined),
              const SimorghSectionTitle(
                title: 'خلاصه مسیر یادگیری',
                subtitle: 'هفت روز تقویمی اخیر، شامل امروز.',
              ),
              _StatsGrid(snapshot: snapshot),
              _DailyGoalCard(snapshot: snapshot),
              const NoticeCard(
                text:
                    'زمان‌های نمایش‌داده‌شده، مجموع زمان برنامه‌های '
                    'انجام‌شده با تاریخ تکمیل معتبر هستند؛ '
                    'این عدد اندازه‌گیری خودکار زمان مطالعه نیست.',
                icon: Icons.timer_outlined,
              ),
              const SimorghSectionTitle(title: 'دسترسی سریع'),
              _QuickAction(
                icon: Icons.calendar_month_outlined,
                title: 'برنامه مطالعه',
                subtitle: 'افزودن کار و تنظیم برنامه هوشمند',
                onTap: () => widget.go(1),
              ),
              _QuickAction(
                icon: Icons.assessment_outlined,
                title: 'ثبت و بررسی نمره‌ها',
                subtitle: 'نتیجه‌ها را ثبت کن و تغییرها را دنبال کن',
                onTap: () => widget.go(2),
              ),
              _QuickAction(
                icon: Icons.style_outlined,
                title: 'مرور فلش‌کارت‌ها',
                subtitle: '${faNumber(snapshot.dueCards)} کارت آماده مرور',
                onTap: () => widget.go(3),
              ),
              _QuickAction(
                icon: Icons.insights_outlined,
                title: 'گزارش محلی پیشرفت',
                subtitle: 'آمار برنامه‌ها و درصد آزمون‌ها؛ بدون ارسال',
                onTap: () => _open(_LocalProgressPage(store: store)),
              ),
              _QuickAction(
                icon: Icons.menu_book_outlined,
                title: 'روش‌های مؤثر مطالعه',
                subtitle: 'مطالعه فعال، مرور فاصله‌دار و تمرکز',
                onTap: () => _open(const StudyTipsPage()),
              ),
              _QuickAction(
                icon: Icons.history_edu_outlined,
                title: 'تاریخچه مشاوره‌ها',
                subtitle: 'بازگشت به گزارش‌ها و پاسخ‌های قبلی',
                onTap: () => _open(ReportsPage(store: store)),
              ),
              _QuickAction(
                icon: Icons.backup_outlined,
                title: 'پشتیبان‌گیری',
                subtitle: 'پیش از حذف یا جابه‌جایی اطلاعات بررسی کن',
                onTap: () => _open(BackupPage(store: store)),
              ),
              const SizedBox(height: 12),
              Text(
                faNumber(appVersionLabel),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.blueGrey),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<Widget> _dataNotices(EducationStore store) {
  const keys = ['edu.profile', 'edu.tasks', 'edu.exams', 'edu.cards'];

  final messages = <String>{};

  for (final key in keys) {
    final error = store.dataError(key);

    if (error != null && error.trim().isNotEmpty) {
      messages.add(error);
    }
  }

  return [
    for (final message in messages) NoticeCard(text: message, warning: true),
  ];
}

class _DailySuggestions extends StatelessWidget {
  const _DailySuggestions({required this.snapshot, required this.go});

  final _LearningSnapshot snapshot;
  final ValueChanged<int> go;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (snapshot.overdueTasks > 0)
          _QuickAction(
            icon: Icons.event_busy_outlined,
            title: 'موعد بعضی برنامه‌ها گذشته است',
            subtitle:
                '${faNumber(snapshot.overdueTasks)} کار را '
                'بازبینی کن؛ لازم نیست همه را امروز انجام بدهی.',
            onTap: () => go(1),
          ),
        if (snapshot.nextExamDate != null)
          _QuickAction(
            icon: Icons.flag_outlined,
            title: 'امتحان پیش‌رو: ${snapshot.nextExamSubject}',
            subtitle:
                'تاریخ میلادی: '
                '${_dateLabel(snapshot.nextExamDate!)}؛ '
                'برای مرور و حل نمونه‌سؤال زمان بگذار.',
            onTap: () => go(1),
          ),
        if (snapshot.dueCards > 0)
          _QuickAction(
            icon: Icons.psychology_alt_outlined,
            title: 'یک مرور کوتاه',
            subtitle:
                '${faNumber(snapshot.dueCards)} فلش‌کارت '
                'آماده مرور است. با چند کارت شروع کن.',
            onTap: () => go(3),
          ),
        if (snapshot.nextTask != null)
          _QuickAction(
            icon: Icons.checklist_outlined,
            title: 'قدم بعدی: ${snapshot.nextTask}',
            subtitle: snapshot.dailyMinutes > 0
                ? 'با توجه به توان امروز و هدف '
                      '${faNumber(snapshot.dailyMinutes)} دقیقه‌ای '
                      'خودت، حجم کار را تنظیم کن.'
                : 'فعلاً هدف زمانی نداری؛ '
                      'یک قدم کوچک و قابل‌انجام انتخاب کن.',
            onTap: () => go(1),
          ),
        if (snapshot.pendingTasks == 0)
          _QuickAction(
            icon: Icons.add_task,
            title: 'یک قدم کوچک تعریف کن',
            subtitle:
                'برنامه انجام‌نشده‌ای نداری. '
                'اگر آماده‌ای، یک کار کوتاه اضافه کن.',
            onTap: () => go(1),
          ),
        if (snapshot.dueCards == 0 && snapshot.totalCards > 0)
          const NoticeCard(
            text:
                'فعلاً فلش‌کارت آماده مرور نداری. '
                'می‌توانی روی تمرین، فهم مفاهیم یا استراحت تمرکز کنی.',
            icon: Icons.done_all,
          ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.snapshot});

  final _LearningSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _StatCard(
        icon: Icons.timer_outlined,
        value: faNumber(snapshot.weekMinutes),
        label: 'دقیقه ثبت‌شده در ۷ روز',
      ),
      _StatCard(
        icon: Icons.task_alt,
        value: faNumber(snapshot.weekTasks),
        label: 'کار تکمیل‌شده در ۷ روز',
      ),
      _StatCard(
        icon: Icons.pending_actions,
        value: faNumber(snapshot.pendingTasks),
        label: 'کار باقی‌مانده',
      ),
      _StatCard(
        icon: Icons.style_outlined,
        value: faNumber(snapshot.dueCards),
        label: 'کارت آماده مرور',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

        final columns = constraints.maxWidth < 300 || scale > 1.6
            ? 1
            : constraints.maxWidth >= 720
            ? 4
            : 2;

        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in items) SizedBox(width: width, child: item),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: blue, size: 23)),
            const SizedBox(height: 9),
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.blueGrey,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.snapshot});

  final _LearningSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ratio = snapshot.dailyRatio;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'وضعیت امروز',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              ratio == null
                  ? '${faNumber(snapshot.todayMinutes)} دقیقه از '
                        'برنامه‌های تکمیل‌شده ثبت شده؛ هدف زمانی تعیین نشده.'
                  : '${faNumber(snapshot.todayMinutes)} دقیقه ثبت‌شده '
                        'از هدف ${faNumber(snapshot.dailyMinutes)} دقیقه',
            ),
            if (ratio != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Text(
                ratio >= 1
                    ? 'به هدف زمانی ثبت‌شده رسیده‌ای؛ '
                          'برای استراحت هم وقت بگذار.'
                    : 'این هدف راهنماست، نه معیار ارزش یا توانایی تو.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
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
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ExcludeSemantics(child: Icon(icon, color: blue)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(height: 1.7)),
        ),
        trailing: const Icon(Icons.chevron_right, size: 21),
        onTap: onTap,
      ),
    );
  }
}

class _LocalProgressPage extends StatelessWidget {
  const _LocalProgressPage({required this.store});

  final EducationStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش محلی پیشرفت')),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final snapshot = _LearningSnapshot.fromStore(store, DateTime.now());

            final subjects = snapshot.subjectAverages.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));

            return _ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const NoticeCard(
                    text:
                        'این گزارش روی دستگاه محاسبه می‌شود و '
                        'برای ساخت آن درخواست آنلاین ارسال نمی‌شود. '
                        'اعداد، خلاصه اطلاعات ثبت‌شده‌اند؛ '
                        'نه تشخیص استعداد یا اثبات تسلط.',
                    icon: Icons.privacy_tip_outlined,
                  ),
                  ..._dataNotices(store),
                  const SimorghSectionTitle(title: 'هفت روز اخیر'),
                  _StatsGrid(snapshot: snapshot),
                  _DailyGoalCard(snapshot: snapshot),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'وضعیت کل برنامه‌ها',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${faNumber(snapshot.doneTasks)} کار انجام‌شده '
                            'از ${faNumber(snapshot.totalTasks)} کار',
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: snapshot.completionRatio,
                            minHeight: 7,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${faNumber(snapshot.overdueTasks)} کار '
                            'انجام‌نشده با موعد گذشته',
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SimorghSectionTitle(
                    title: 'زمان ثبت‌شده روزانه',
                    subtitle: 'تاریخ‌ها میلادی هستند.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (final entry in snapshot.dayMinutes.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(child: Text(_dateLabel(entry.key))),
                                  Text('${faNumber(entry.value)} دقیقه'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const NoticeCard(
                    text:
                        'کارهای قدیمی که تاریخ تکمیل ندارند، '
                        'در آمار زمانی هفت روز اخیر محاسبه نمی‌شوند. '
                        'زمان‌ها بر اساس مدت ثبت‌شده برای کارها هستند.',
                    icon: Icons.timer_outlined,
                  ),
                  const SimorghSectionTitle(title: 'خلاصه آزمون‌ها'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'میانگین ساده درصد آزمون‌های معتبر',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            snapshot.average == null
                                ? 'هنوز داده معتبری نداریم'
                                : '${faNumber(snapshot.average!.toStringAsFixed(1))}٪',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${faNumber(snapshot.validExams)} آزمون '
                            'در محاسبه لحاظ شده است.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final subject in subjects)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              subject.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${faNumber(subject.value.toStringAsFixed(1))}٪',
                            ),
                            const SizedBox(height: 9),
                            LinearProgressIndicator(
                              value: (subject.value / 100)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              minHeight: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (subjects.isEmpty)
                    const EmptyState(
                      title: 'برای گزارش آزمون، داده بیشتری لازم است',
                      subtitle: 'از تب آزمون، یک نتیجه معتبر ثبت کن.',
                      icon: Icons.assessment_outlined,
                    ),
                  const NoticeCard(
                    text:
                        'تفاوت سختی آزمون‌ها، تعداد سؤال‌ها و '
                        'شرایط برگزاری در این میانگین لحاظ نشده است. '
                        'برای تصمیم آموزشی، نمره‌ها را همراه با '
                        'نوع اشتباه‌ها و نظر معلم بررسی کن.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('درباره سیمرغ')),
      body: SafeArea(
        top: false,
        child: _ContentWidth(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Center(child: SimorghMark(size: 100)),
              const SizedBox(height: 16),
              const Text(
                'سیمرغ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: navy,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'همراه دانای راه آینده',
                textAlign: TextAlign.center,
                style: TextStyle(color: teal, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(faNumber(appVersionLabel), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const _AboutSection(
                title: 'سیمرغ چه کمکی می‌کند؟',
                text:
                    'ثبت برنامه مطالعه، پیگیری نتیجه آزمون‌ها، '
                    'مرور فاصله‌دار فلش‌کارت‌ها و گفت‌وگوی تحصیلی. '
                    'پیشنهادها برای کمک به تصمیم‌گیری تو هستند؛ '
                    'نه جایگزین انتخاب و قضاوت خودت.',
              ),
              const _AboutSection(
                title: 'ذخیره‌سازی و پشتیبان‌گیری',
                text:
                    'اطلاعات تحصیلی در ذخیره‌سازی محلی برنامه '
                    'نگهداری می‌شوند. حذف برنامه یا پاک‌کردن داده‌های آن '
                    'می‌تواند اطلاعات محلی را از بین ببرد. '
                    'قبل از این کار، بخش پشتیبان‌گیری را بررسی کن. '
                    'فایل پشتیبان ممکن است اطلاعات شخصی داشته باشد؛ '
                    'آن را در محل امن نگه دار و عمومی منتشر نکن.',
              ),
              const _AboutSection(
                title: 'گفت‌وگو و سرویس بیرونی',
                text:
                    'برای پاسخ‌گویی آنلاین، متن پیام و بخشی از '
                    'گفت‌وگو به سرویس هوش مصنوعی ارسال می‌شود. '
                    'نام، شماره تماس، نشانی، رمز عبور و اطلاعات '
                    'حساس داخل پیام ننویس. '
                    'حذف سابقه محلی به معنای حذف داده‌های '
                    'ارسال‌شده از سامانه بیرونی نیست.',
              ),
              const _AboutSection(
                title: 'رضایت زمینه تحصیلی',
                text:
                    'اجازه استفاده از مقطع، پایه، رشته و هدف '
                    'تحصیلی در فرم پروفایل انتخاب می‌شود. '
                    'این انتخاب اختیاری است و شامل نام نیست. '
                    'لغو رضایت برای درخواست‌های بعدی است و '
                    'ارسال‌های قبلی را پس نمی‌گیرد.',
              ),
              const _AboutSection(
                title: 'محدودیت پاسخ‌ها و گزارش‌ها',
                text:
                    'پاسخ هوش مصنوعی ممکن است اشتباه، ناقص '
                    'یا نامتناسب با شرایط تو باشد. '
                    'اطلاعات مهم را با معلم و منابع رسمی بررسی کن.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}
