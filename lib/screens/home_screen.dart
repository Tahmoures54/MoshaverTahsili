import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/car.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/share_service.dart';
import '../utils/persian_numbers.dart';
import '../widgets/brand_logo.dart';
import '../widgets/car_selector_widget.dart';
import '../widgets/enamad_badge.dart';
import '../widgets/home_plan_purchase_card.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'local_phone_screen.dart';
import 'shop_screen.dart';
import 'terms_screen.dart';

part 'home_screen_widgets.dart';

const String _kCustomCarId = 'custom';

/// TODO: بهتر است این کلید به Constants منتقل شود تا همهٔ کلیدهای
/// SharedPreferences یک‌جا مدیریت شوند.
const String _kKeyLastDescription = 'last_description';

/* ---------------------------------------------------------------------------
 * پیش‌نویس فرم — مدل + ذخیره‌سازی، جدا از UI تا قابل تست باشد.
 * ------------------------------------------------------------------------ */

class _HomeDraft {
  const _HomeDraft({
    this.year = '',
    this.description = '',
    this.customCarName = '',
    this.carId,
  });

  final String year;
  final String description;
  final String customCarName;
  final String? carId;

  bool get isCustomCar => carId == _kCustomCarId && customCarName.trim().length >= 2;
}

class _DraftStore {
  _DraftStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<_DraftStore> open() async => _DraftStore(await SharedPreferences.getInstance());

  _HomeDraft read() => _HomeDraft(
        year: _prefs.getString(Constants.keyLastYear) ?? '',
        description: _prefs.getString(_kKeyLastDescription) ?? '',
        customCarName: _prefs.getString(Constants.keyLastCustomCar) ?? '',
        carId: _prefs.getString(Constants.keyLastCarId),
      );

  Future<void> write(_HomeDraft draft) async {
    await Future.wait<void>([
      _prefs.setString(Constants.keyLastYear, draft.year),
      _prefs.setString(_kKeyLastDescription, draft.description),
      _prefs.setString(Constants.keyLastCustomCar, draft.customCarName),
      if (draft.carId != null)
        _prefs.setString(Constants.keyLastCarId, draft.carId!)
      else
        _prefs.remove(Constants.keyLastCarId),
    ]);
  }

  Future<void> clearDescription() => _prefs.remove(_kKeyLastDescription);
}

/* ---------------------------------------------------------------------------
 * اعتبارسنجی — خالص و بدون side-effect. تصمیم UI جداگانه گرفته می‌شود.
 * ------------------------------------------------------------------------ */

enum _FormIssue { noCar, customCarName, year, description, noCredit }

/* ---------------------------------------------------------------------------
 * صفحهٔ اصلی
 * ------------------------------------------------------------------------ */

/// صفحه اصلی — مسیر ساده: خودرو → شرح مشکل → ارسال
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _descController = TextEditingController();
  final _customCarController = TextEditingController();
  final _yearController = TextEditingController();

  final _carCardKey = GlobalKey();
  final _descFieldKey = GlobalKey();

  List<Car> _cars = [];
  Car? _selectedCar;

  bool _isLoadingCars = true;
  bool _isRefreshing = false;
  bool _hasCarLoadError = false;
  bool _isCustomCar = false;

  String? _descError;

  _DraftStore? _draftStore;
  String? _pendingCarId;

  Timer? _draftDebounce;
  bool _isRestoringDraft = false;

  /// شمارندهٔ درخواست — پاسخ‌های قدیمی که دیر می‌رسند نادیده گرفته می‌شوند.
  int _carsRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _yearController.addListener(_onFormChanged);
    _customCarController.addListener(_onFormChanged);
    _descController.addListener(_onDescriptionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreDraft();
      if (!mounted) return;
      await _loadCars();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();

    _yearController.removeListener(_onFormChanged);
    _customCarController.removeListener(_onFormChanged);
    _descController.removeListener(_onDescriptionChanged);

    _descController.dispose();
    _customCarController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // وقتی اپ به پس‌زمینه می‌رود، پیش‌نویس را فوراً ذخیره کن (بدون منتظرماندن
    // برای debounce) تا اگر سیستم اپ را kill کرد چیزی از دست نرود.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_flushDraft());
    }
  }

  /* ----------------------------- Draft ----------------------------- */

  _HomeDraft _currentDraft() => _HomeDraft(
        year: _yearController.text.trim(),
        description: _descController.text.trim(),
        customCarName: _customCarController.text.trim(),
        carId: _isCustomCar ? _kCustomCarId : _selectedCar?.id,
      );

  void _onFormChanged() {
    if (_isRestoringDraft) return;
    _scheduleDraftSave();
  }

  void _onDescriptionChanged() {
    if (_descError != null) setState(() => _descError = null);
    if (_isRestoringDraft) return;
    _scheduleDraftSave();
  }

  /// به‌جای نوشتن روی دیسک در هر کاراکتر، ۶۰۰ میلی‌ثانیه بعد از آخرین تغییر
  /// یک‌بار می‌نویسیم.
  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), () => unawaited(_flushDraft()));
  }

  Future<void> _flushDraft() async {
    _draftDebounce?.cancel();
    final store = _draftStore;
    if (store == null) return;
    await store.write(_currentDraft());
  }

  Future<void> _restoreDraft() async {
    final store = await _DraftStore.open();
    if (!mounted) return;

    _draftStore = store;
    final draft = store.read();

    _isRestoringDraft = true;
    setState(() {
      _yearController.text = draft.year;
      _descController.text = draft.description;

      if (draft.isCustomCar) {
        _isCustomCar = true;
        _customCarController.text = draft.customCarName;
        _pendingCarId = null;
      } else {
        _pendingCarId = draft.carId;
      }
    });
    _isRestoringDraft = false;
  }

  /* ------------------------------ Cars ------------------------------ */

  Future<void> _loadCars({bool isRefresh = false}) async {
    if (!mounted) return;

    final requestId = ++_carsRequestId;

    setState(() {
      if (isRefresh) {
        _isRefreshing = true;
      } else {
        _isLoadingCars = true;
      }
      _hasCarLoadError = false;
    });

    try {
      final fetched = await context.read<ApiService>().getCars();

      // اگر درخواست تازه‌تری شروع شده، این پاسخ منسوخ است.
      if (!mounted || requestId != _carsRequestId) return;

      // کپی می‌گیریم تا اگر ApiService لیست cache داخلی‌اش را برگردانده باشد،
      // با sort کردن، state مشترک را خراب نکنیم.
      final cars = [...fetched]..sort((a, b) => a.fullName.compareTo(b.fullName));

      setState(() {
        _cars = cars;
        _selectedCar = _resolveSelectedCar(cars);
        _pendingCarId = null; // بعد از resolve دیگر لازم نیست
      });
    } catch (_) {
      if (!mounted || requestId != _carsRequestId) return;
      setState(() => _hasCarLoadError = true);
      _snack('لیست وسایل نقلیه لود نشد. فایل داخلی یا اینترنت را چک کنید.');
    } finally {
      if (mounted && requestId == _carsRequestId) {
        setState(() {
          _isLoadingCars = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Car? _resolveSelectedCar(List<Car> cars) {
    if (_isCustomCar) return null;

    final targetId = _selectedCar?.id ?? _pendingCarId;
    if (targetId == null) return null;

    for (final car in cars) {
      if (car.id == targetId) return car;
    }
    return null;
  }

  /* --------------------------- Validation --------------------------- */

  bool _isValidYear(String raw) {
    final n = parseFlexibleInt(raw);
    if (n == null) return false;

    // بازه‌ها از سال جاری محاسبه می‌شوند تا منطق با گذشت زمان منسوخ نشود.
    final gregorianNow = DateTime.now().year;
    final jalaliNow = gregorianNow - 621;

    final isJalali = n >= 1300 && n <= jalaliNow + 1;
    final isGregorian = n >= 1950 && n <= gregorianNow + 1;
    return isJalali || isGregorian;
  }

  _FormIssue? _findIssue({required bool needDescription}) {
    if (!_isCustomCar && _selectedCar == null) return _FormIssue.noCar;
    if (_isCustomCar && _customCarController.text.trim().length < 2) {
      return _FormIssue.customCarName;
    }
    if (!_isValidYear(_yearController.text)) return _FormIssue.year;
    if (needDescription && _descController.text.trim().length < 5) {
      return _FormIssue.description;
    }
    if (!context.read<AuthProvider>().canDiagnose) return _FormIssue.noCredit;
    return null;
  }

  /// اعتبارسنجی side-effect ندارد؛ واکنش UI اینجا و فقط اینجا انجام می‌شود.
  Future<void> _handleIssue(_FormIssue issue) async {
    switch (issue) {
      case _FormIssue.noCar:
        _snack('اول خودرو را انتخاب کنید.');
        await _ensureVisible(_carCardKey);
        return;
      case _FormIssue.customCarName:
        _snack('نام خودرو را بنویسید (مثلاً تویوتا کمری).');
        await _ensureVisible(_carCardKey);
        return;
      case _FormIssue.year:
        _snack('سال ساخت را وارد کنید (مثلاً ۱۴۰۲ یا ۲۰۲۳).');
        await _ensureVisible(_carCardKey);
        return;
      case _FormIssue.description:
        setState(() => _descError = 'کمی واضح‌تر بنویس تا تشخیص دقیق‌تر باشد.');
        await _ensureVisible(_descFieldKey);
        return;
      case _FormIssue.noCredit:
        await _showNoCreditDialog();
        return;
    }
  }

  Future<void> _ensureVisible(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  /* ---------------------------- Actions ---------------------------- */

  /// اگر کاربر لاگین نیست، لاگین را باز می‌کند و **بعد از موفقیت، جریان
  /// اصلی ادامه پیدا می‌کند** — کاربر مجبور نیست دوباره دکمه بزند.
  Future<bool> _ensureAuthenticated() async {
    if (context.read<AuthProvider>().isAuthenticated) return true;

    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LocalPhoneScreen()));
    if (!mounted) return false;
    return context.read<AuthProvider>().isAuthenticated;
  }

  ({String id, String name, String year}) _carInfo() {
    // سال همیشه با ارقام لاتین به بک‌اند/مدل زبانی فرستاده می‌شود.
    final year = normalizeDigits(_yearController.text).trim();

    if (_isCustomCar) {
      return (id: _kCustomCarId, name: _customCarController.text.trim(), year: year);
    }
    final car = _selectedCar!; // _findIssue تضمین کرده null نیست
    return (id: car.id, name: car.fullName, year: year);
  }

  Future<void> _diagnose() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!await _ensureAuthenticated()) return;
    if (!mounted) return;

    final issue = _findIssue(needDescription: true);
    if (issue != null) {
      await _handleIssue(issue);
      return;
    }

    final car = _carInfo();
    final text = _descController.text.trim();
    await _flushDraft();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          carName: car.name,
          carId: car.id,
          year: car.year,
          initialUserMessage: text,
          isCustomCar: _isCustomCar,
        ),
      ),
    );
    await context.read<AuthProvider>().refreshLocalState();

    // متن فقط بعد از بازگشت پاک می‌شود (نه قبل از رفتن)، و با امکان بازگردانی —
    // تا اگر چت خطا داد یا کاربر back زد، نوشتهٔ کاربر از بین نرود.
    if (!mounted) return;
    _clearDescriptionWithUndo(text);
  }

  void _clearDescriptionWithUndo(String previous) {
    if (previous.isEmpty) return;

    _descController.clear();
    unawaited(_draftStore?.clearDescription() ?? Future<void>.value());

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('شرح مشکل پاک شد.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'بازگردانی',
          onPressed: () {
            _descController.text = previous;
            _descController.selection =
                TextSelection.collapsed(offset: previous.length);
            _scheduleDraftSave();
          },
        ),
      ),
    );
  }

  Future<void> _showNoCreditDialog() async {
    final goToShop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('اعتبار کافی نیست'),
        content: const Text(
          'دوره استفاده رایگان شما به پایان رسیده است.\n'
          'برای ادامه می‌توانید بسته اعتبار یا اشتراک طلایی تهیه کنید.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعداً')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مشاهده بسته‌ها'),
          ),
        ],
      ),
    );

    if (goToShop != true || !mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
  }

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? theme.colorScheme.error : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /* ------------------------------ Build ------------------------------ */

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.secondary;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(auth, secondary),
        body: RefreshIndicator(
          color: secondary,
          onRefresh: () async {
            await _loadCars(isRefresh: true);
            if (!mounted) return;
            if (context.read<AuthProvider>().isAuthenticated) {
              await context.read<AuthProvider>().fetchProfile(force: true);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              HomePlanPurchaseCard(
                credits: auth.credits,
                isGoldenActive: auth.isGoldenActive,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(number: '۱', title: 'وسیله نقلیه را انتخاب کنید'),
              const SizedBox(height: 10),
              KeyedSubtree(
                key: _carCardKey,
                child: _CarCard(
                  isCustom: _isCustomCar,
                  cars: _cars,
                  selectedCar: _selectedCar,
                  isLoading: _isLoadingCars && !_isRefreshing,
                  hasError: _hasCarLoadError && _cars.isEmpty,
                  customController: _customCarController,
                  yearController: _yearController,
                  onRetry: () => unawaited(_loadCars()),
                  onCarSelected: _onCarSelected,
                  onToggleCustom: _onToggleCustom,
                ),
              ),

              const SizedBox(height: 22),

              _SectionLabel(number: '۲', title: 'مشکل را بنویسید'),
              const SizedBox(height: 10),
              _buildDescriptionField(theme, secondary),

              const SizedBox(height: 22),

              _SectionLabel(number: '۳', title: 'ارسال برای عیب‌یابی'),
              const SizedBox(height: 12),
              _DiagnoseCtaButton(onPressed: () => unawaited(_diagnose())),
              const SizedBox(height: 12),
              const SizedBox(height: 22),

              const _WhyItWorksSection(),
              const SizedBox(height: 14),
              const _GrowthShareBanner(),
              const SizedBox(height: 18),

              const SizedBox(height: 14),
              const _SupportCard(),
              const SizedBox(height: 20),
              const Center(child: EnamadBadge()),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
                  ),
                  child: const Text('قوانین و مقررات', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AuthProvider auth, Color secondary) {
    return AppBar(
      title: const BrandAppBarTitle(),
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        if (auth.isAuthenticated)
          IconButton(
            tooltip: 'حساب کاربری',
            icon: const Icon(Icons.account_circle_rounded),
            onPressed: () => _showAccountDialog(auth),
          )
        else
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const LocalPhoneScreen()),
            ),
            child: Text(
              'ورود',
              style: TextStyle(color: secondary, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Future<void> _showAccountDialog(AuthProvider auth) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('حساب کاربری', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              ListTile(leading: const Icon(Icons.phone_rounded), title: const Text('شماره موبایل'), subtitle: Text(_orDash(auth.phone))),
              ListTile(leading: const Icon(Icons.person_rounded), title: const Text('نام'), subtitle: Text(_orDash(auth.userName))),
              ListTile(leading: const Icon(Icons.credit_card_rounded), title: const Text('اعتبار'), subtitle: Text('${auth.credits} اعتبار')),
              if (auth.isGoldenActive) const ListTile(leading: Icon(Icons.workspace_premium_rounded), title: Text('اشتراک طلایی'), subtitle: Text('فعال')),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text('مشاهده تاریخچه'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionField(ThemeData theme, Color secondary) {
    return KeyedSubtree(
      key: _descFieldKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _descController,
            maxLines: 4,
            maxLength: 300,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onEditingComplete: () => FocusManager.instance.primaryFocus?.unfocus(),
            style: const TextStyle(height: 1.5),
            decoration: InputDecoration(
              hintText: 'مثال: صبح‌ها که هوا سرد است، موقع استارت ریپ می‌زند و صدای تق‌تق می‌آید...',
              hintStyle: TextStyle(color: theme.hintColor, fontSize: 13, height: 1.4),
              errorText: _descError,
              filled: true,
              fillColor: theme.brightness == Brightness.dark
                  ? const Color(0xFF3A251A)
                  : const Color(0xFFFFFCF8),
              contentPadding: const EdgeInsets.all(16),
              counterStyle: TextStyle(color: theme.hintColor, fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: secondary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _appendSymptom(String symptom) {
    final current = _descController.text.trim();
    final next = current.isEmpty ? symptom : '$current، $symptom';
    if (next.length > Constants.maxDescriptionLength) {
      _snack('متن شرح مشکل به حداکثر ${Constants.maxDescriptionLength} کاراکتر رسیده است.');
      return;
    }
    _descController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focusNodeAfterSuggestion();
  }

  void _focusNodeAfterSuggestion() {
    // بعد از انتخاب نشانه، صفحه‌کلید باز نمی‌شود؛ فقط مکان‌نما در پایان متن
    // قرار می‌گیرد تا کاربر بتواند جزئیات را ادامه دهد.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onCarSelected(Car car) {
    setState(() => _selectedCar = car);
    _scheduleDraftSave();
  }

  void _onToggleCustom() {
    setState(() {
      _isCustomCar = !_isCustomCar;
      _selectedCar = null;
      if (!_isCustomCar) _customCarController.clear();
    });
    _scheduleDraftSave();
  }
}
