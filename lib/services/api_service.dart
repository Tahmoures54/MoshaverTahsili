import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/car.dart';
import '../models/diagnostic.dart';
import 'local_first_store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? details;

  const ApiException(this.statusCode, this.message, {this.details});

  bool get isUnauthorized => statusCode == 401;
  bool get isPaymentRequired => statusCode == 402;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;
  bool get isNetworkError => statusCode == 0;
  bool get isTimeout => statusCode == 408;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class DiagnosisApiResult {
  final String result;
  final String? diagnosticId;
  final String responseMode;
  final Map<String, dynamic>? structured;

  const DiagnosisApiResult({
    required this.result,
    this.diagnosticId,
    this.responseMode = 'diagnosis',
    this.structured,
  });
}

class ApiResponse<T> {
  final T data;
  final int statusCode;
  final Map<String, dynamic>? meta;

  const ApiResponse({required this.data, required this.statusCode, this.meta});
}

class PaginationParams {
  final int page;
  final int limit;

  const PaginationParams({this.page = 1, this.limit = 20});

  Map<String, String> toQueryParams() => {
        'page': page.toString(),
        'limit': limit.toString(),
      };
}

class ApiService {
  final http.Client _httpClient;
  final Duration _defaultTimeout;
  final Duration _diagnoseTimeout;
  final LocalFirstStore? _localStore;

  List<Car>? _carsCache;
  DateTime? _carsCacheTime;
  static const _carsCacheDuration = Duration(hours: 6);

  final Map<String, DateTime> _lastRequestTime = {};
  static const _minRequestInterval = Duration(milliseconds: 800);

  ApiService({
    http.Client? httpClient,
    Duration defaultTimeout = const Duration(seconds: 20),
    Duration diagnoseTimeout = const Duration(seconds: 45),
    LocalFirstStore? localStore,
  })  : _httpClient = httpClient ?? http.Client(),
        _defaultTimeout = defaultTimeout,
        _diagnoseTimeout = diagnoseTimeout,
        _localStore = localStore;

  Map<String, String> _getHeaders([String? token]) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _parseBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};

    final raw = utf8.decode(response.bodyBytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trim();
    if (raw.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(raw);
    } catch (_) {
      final contentType = response.headers['content-type'] ?? 'unknown';
      debugPrint(
        '[API Error] Invalid JSON: ${response.statusCode}, '
        'content-type=$contentType, body=${_truncate(raw, max: 180)}',
      );
      throw ApiException(
        response.statusCode,
        response.statusCode >= 500
            ? 'سرور موقتاً پاسخ معتبر نداد. لطفاً چند لحظه بعد دوباره تلاش کنید.'
            : 'پاسخ سرور قابل پردازش نیست. لطفاً اتصال اینترنت را بررسی و دوباره تلاش کنید.',
      );
    }
  }

  Map<String, dynamic> _parseAndEnsure(
    http.Response response, {
    String? defaultError,
  }) {
    final data = _parseBody(response);

    if (response.statusCode >= 400 || (data is Map && data['success'] == false)) {
      final msg = data is Map
          ? (data['error'] ?? data['message'] ?? defaultError ?? 'خطای سرور')
          : (defaultError ?? 'خطای ناشناخته');
      final details = data is Map ? Map<String, dynamic>.from(data) : null;
      throw ApiException(response.statusCode, msg.toString(), details: details);
    }

    if (data is List) return {'data': data};
    return data is Map<String, dynamic>
        ? data
        : <String, dynamic>{'data': data};
  }

  Future<void> _checkRateLimit(String key) async {
    final last = _lastRequestTime[key];
    final interval = _minRequestInterval;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < interval) await Future.delayed(interval - elapsed);
    }
    _lastRequestTime[key] = DateTime.now();
  }

  Future<http.Response> _safeCall(
    Future<http.Response> Function() call, {
    Duration? timeout,
    String? rateLimitKey,
  }) async {
    if (rateLimitKey != null) await _checkRateLimit(rateLimitKey);

    try {
      final response = await call().timeout(timeout ?? _defaultTimeout);
      _log('${response.statusCode}', response.request?.url.toString() ?? '');
      return response;
    } on SocketException catch (e) {
      _logError('SocketException', e.message);
      throw const ApiException(0, 'عدم اتصال به اینترنت. لطفاً شبکه خود را بررسی کنید.');
    } on TimeoutException {
      _logError('Timeout', 'درخواست بیش از حد طول کشید.');
      throw const ApiException(408, 'زمان درخواست پایان یافت. لطفاً دوباره تلاش کنید.');
    } on HandshakeException catch (e) {
      _logError('TLS Error', e.message);
      throw const ApiException(0, 'خطا در اتصال امن. لطفاً اینترنت خود را بررسی کنید.');
    } catch (e) {
      if (e is ApiException) rethrow;
      _logError('Unknown', e.toString());
      throw const ApiException(500, 'خطای نامشخص در برقراری ارتباط با سرور.');
    }
  }

  void _log(String status, String url) => debugPrint('[API] $status → ${_truncate(url)}');
  void _logError(String type, String msg) => debugPrint('[API Error] $type: ${_truncate(msg)}');
  String _truncate(String s, {int max = 100}) => s.length > max ? '${s.substring(0, max)}...' : s;

  static const _bundledCarsAsset = 'assets/data/cars.json';

  Future<List<Car>> getCars({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _carsCache != null &&
        _carsCacheTime != null &&
        DateTime.now().difference(_carsCacheTime!) < _carsCacheDuration) {
      return _carsCache!;
    }

    // The Bazaar app uses the bundled vehicle catalog; no custom server call.
    final cars = await _loadBundledCars();
    if (cars.isEmpty) {
      throw const ApiException(500, 'فهرست خودروهای داخلی برنامه قابل خواندن نیست.');
    }
    _carsCache = cars;
    _carsCacheTime = DateTime.now();
    return cars;
  }

  Future<List<Car>> _loadBundledCars() async {
    try {
      final raw = await rootBundle.loadString(_bundledCarsAsset);
      return _parseCarsJson(json.decode(raw));
    } catch (e) {
      debugPrint('[API] خواندن کاتالوگ داخلی ناموفق بود: $e');
      return const [];
    }
  }

  List<Car> _parseCarsJson(dynamic body) {
    final List<dynamic> rawList;
    if (body is List<dynamic>) {
      rawList = body;
    } else if (body is Map && body['cars'] is List<dynamic>) {
      rawList = body['cars'] as List<dynamic>;
    } else {
      rawList = const [];
    }
    return rawList
        .whereType<Map>()
        .map((j) => Car.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  void clearCarsCache() {
    _carsCache = null;
    _carsCacheTime = null;
  }

  static const String _directAiKey = String.fromEnvironment('AI_API_KEY');
  static const String _directAiEndpoint = String.fromEnvironment(
    'AI_API_ENDPOINT',
    defaultValue: 'https://api.avalai.ir/v1/chat/completions',
  );
  static const String _directAiModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'deepseek-chat',
  );

  Future<DiagnosisApiResult> diagnoseDetailed(
    String token,
    String carId,
    String description, {
    required String year,
    String? carName,
    String? previousDiagnosticId,
    List<Map<String, String>> conversationHistory = const [],
    String? requestId,
    double? lat,
    double? lng,
    String? city,
  }) async {
    if (_directAiKey.trim().isEmpty) {
      throw const ApiException(
        503,
        'کلید سرویس هوش مصنوعی در نسخه برنامه تنظیم نشده است.',
      );
    }

    final matchingCars =
        _carsCache?.where((car) => car.id == carId).toList(growable: false) ??
            const <Car>[];
    final resolvedCarName = (carName?.trim().isNotEmpty ?? false)
        ? carName!.trim()
        : (matchingCars.isNotEmpty ? matchingCars.first.fullName : carId);
    final vehicle = 'خودرو: $resolvedCarName، سال ساخت: $year';
    // پیام واقعی کاربر حفظ می‌شود؛ فقط زمینهٔ لازم برای عیب‌یابی افزوده می‌شود.
    final userPrompt = '''
زمینهٔ خودرو:
$vehicle

شرح مشکل از زبان راننده:
${description.trim().length <= 1600 ? description.trim() : '${description.trim().substring(0, 1600)}…'}

بر اساس همین اطلاعات و تاریخچهٔ گفتگو پاسخ بده. اگر پیام فعلی ادامهٔ سؤال قبلی است، پاسخ‌های قبلی را در نظر بگیر و از کاربر نخواه اطلاعاتی را که قبلاً داده دوباره تکرار کند. اگر اطلاعاتی مانند زمان بروز مشکل، چراغ هشدار یا شرایط سرد/گرم بودن موتور کم است، پاسخ را با پرسش متوقف نکن؛ ابتدا برداشت فعلی، چند احتمال مشروط و اقدام ایمن را ارائه بده و در پایان مشخص کن کدام اطلاعات در پیام بعدی به دقیق‌تر شدن تشخیص کمک می‌کند. اطلاعاتی را که کاربر قبلاً داده دوباره درخواست نکن. پاسخ را متناسب با همین مسئله تنظیم کن؛ از تحمیل تیترهای غیرضروری خودداری کن و ایمنی را مقدم بدان.
'''.trim();

    // فقط پیام‌های واقعی user/assistant وارد مدل می‌شوند؛ پیام‌های خطا و UI حذف‌اند.
    final suppliedHistory = conversationHistory
        .where((entry) =>
            (entry['role'] == 'user' || entry['role'] == 'assistant') &&
            (entry['content']?.trim().isNotEmpty ?? false))
        .map((entry) => <String, String>{
              'role': entry['role']!,
              'content': entry['content']!.trim(),
            })
        .toList(growable: true);
    if (suppliedHistory.isEmpty ||
        suppliedHistory.last['role'] != 'user' ||
        suppliedHistory.last['content'] != description.trim()) {
      suppliedHistory.add({'role': 'user', 'content': description.trim()});
    }

    // برای کنترل هزینه، فقط ۸ پیام اخیر نگه داشته می‌شوند و متن هر پیام
    // قدیمی حداکثر ۱۲۰۰ نویسه است. پرسش جاری با زمینهٔ خودرو جداگانه ساخته می‌شود.
    final recentHistory = suppliedHistory.length <= 8
        ? suppliedHistory
        : suppliedHistory.skip(suppliedHistory.length - 8).toList();
    final boundedHistory = recentHistory
        .map((entry) => <String, String>{
              'role': entry['role']!,
              'content': entry['content']!.length <= 1200
                  ? entry['content']!
                  : '${entry['content']!.substring(0, 1200)}…',
            })
        .toList(growable: false);
    final requestHistory = <Map<String, String>>[
      for (var i = 0; i < boundedHistory.length; i++)
        {
          'role': boundedHistory[i]['role']!,
          'content': i == boundedHistory.length - 1 &&
                  boundedHistory[i]['role'] == 'user'
              ? userPrompt
              : boundedHistory[i]['content']!,
        },
    ];

    final LocalFirstStore? configuredStore = _localStore;
    if (configuredStore == null) {
      // Direct AI calls must always have a local entitlement ledger; otherwise
      // a caller that constructs ApiService without the store could bypass
      // free-trial and credit accounting entirely.
      throw const ApiException(
        503,
        'ذخیره‌سازی محلی اعتبار در این نسخه پیکربندی نشده است.',
      );
    }
    final store = configuredStore;
    final TrialStatus trialBefore = await store.trialStatus;
    final int creditsBefore = await store.credits;
    if (trialBefore.shouldShowPlans && creditsBefore <= 0) {
      throw const ApiException(
        402,
        'دوره رایگان به پایان رسیده است. برای ادامه یکی از پلن‌ها را تهیه کنید.',
      );
    }

    final uri = Uri.parse(_directAiEndpoint);
    final response = await _safeCall(
      () => _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_directAiKey',
        },
        body: jsonEncode({
          'model': _directAiModel,
          'messages': [
            {
              'role': 'system',
              'content': '''تو «دستیار عیب‌یابی هوشمند خودرو» هستی و باید با رویکرد یک مکانیک ارشد بسیار باتجربه، دقیق و محتاط عمل کنی. هدف تو کمک به راننده برای فهم علت‌های محتمل و انتخاب اقدام بعدی است؛ نه وانمود کردن به داشتن تجربه یا مدرک واقعی و نه جایگزین شدن با بازدید فیزیکی خودرو.

روش عیب‌یابی:
۱) ابتدا علامت اصلی، شرایط بروز آن و اطلاعات خودروی ارائه‌شده را درک کن. بین «استارت نمی‌چرخد» و «استارت می‌چرخد اما موتور روشن نمی‌شود»، یا بین «داغ کردن» و «بالا رفتن آمپر بدون نشانه دیگر» تفاوت بگذار.
۲) این برنامه در هر نوبت باید یک پاسخ کاربردی و کامل بدهد و نباید گفتگو را با سؤال مستقیم متوقف کند. اگر اطلاعات کافی نیست، محدودیت تشخیص را روشن کن، فقط چند علت مشروط و محتمل را با عبارت‌هایی مانند «اگر ...» توضیح بده و بگو کدام اطلاعات در پیام بعدی به دقیق‌تر شدن پاسخ کمک می‌کند؛ اطلاعات قبلاً ارائه‌شده را دوباره درخواست نکن.
۳) وقتی شواهد کافی است، حداکثر ۲ تا ۴ علت محتمل را به ترتیب منطقی بیان کن. برای هر علت، نشانه پشتیبان و در صورت امکان بررسی‌ای را بگو که آن را از علت‌های دیگر متمایز می‌کند. علت‌های کم‌احتمال را فقط برای طولانی‌تر شدن پاسخ اضافه نکن.
۴) پیشنهادها را از بررسی‌های ساده، کم‌هزینه و ایمن شروع کن و سپس در صورت لزوم به دیاگ یا تعمیرکار متخصص برس. هرگز صرفاً بر اساس یک صدا، چراغ یا علامت، خرابی قطعه‌ای را قطعی اعلام نکن و تعویض بی‌هدف قطعات را توصیه نکن.
۵) بین واقعیت گزارش‌شده، احتمال فنی و چیزی که هنوز مشخص نیست تفاوت بگذار. درصد اطمینان نساز، اطلاعات فنی، مشخصات خودرو، کد خطا، قیمت روز یا نتیجه آزمایشی را که انجام نشده جعل نکن. اگر چند علت با اطلاعات موجود قابل تفکیک نیستند، صریح و کوتاه بگو چه اطلاعاتی لازم است.
۶) از نام خودرو و سال ساخت استفاده کن. اگر تیپ، کد موتور، نوع گیربکس یا نسخه سیستم در تشخیص اثر دارد و معلوم نیست، سؤال کن؛ آن را از روی نام مدل حدس نزن. توصیه‌های عمومی را به‌عنوان مشخصات قطعی همان خودرو معرفی نکن.
۷) در ادامه گفتگو، تاریخچه پیام‌های user و assistant را لحاظ کن. پاسخ‌هایی مثل «بله»، «خیر» و «همان مورد» را در ارتباط با سؤال قبلی تفسیر کن، اطلاعات داده‌شده را حفظ کن و اگر موضوع عوض شد، فرض نکن که مشکل قبلی همچنان مطرح است.
۸) اگر کاربر فقط معنی چراغ، قطعه یا یک سؤال ساده را می‌پرسد، مستقیم و مختصر پاسخ بده؛ فرایند کامل عیب‌یابی را به سؤال ساده تحمیل نکن. اگر مشکل پیچیده است، مراحل را مرتب و روشن توضیح بده.
۹) ایمنی مقدم است. در نشانه‌هایی مانند افت یا از دست رفتن ترمز، افت فشار روغن، داغ‌کردن شدید، دود غیرعادی، بوی سوخت یا نشت سوخت، خطر آتش‌سوزی یا فرمان‌پذیری نامطمئن، ابتدا اقدام فوری و ایمن را بیان کن و از ادامه رانندگی در صورت خطر منع کن. کاربر عادی را به رفتن زیر خودرویی که فقط با جک نگه داشته شده، لمس قطعات داغ یا متحرک، آزمایش مدار فشارقوی، باز کردن درِ سیستم خنک‌کننده داغ، یا کار تخصصی با سوخت و ترمز راهنمایی نکن.
۱۰) سطح فوریت را فقط وقتی شواهد کافی است مشخص کن: 🔴 توقف در محل امن و کمک تخصصی؛ 🟠 بررسی زودهنگام؛ 🟢 بررسی عادی. از هشدار بی‌مورد یا اطمینان‌بخشی بی‌پایه پرهیز کن.
۱۱) پاسخ را به زبان فارسی روان و محترمانه، مناسب راننده ایرانی بنویس. اصطلاح فنی را کوتاه توضیح بده. قیمت یا هزینه را قطعی نگو؛ اگر لازم بود، ابتدا خودرو، شهر و جزئیات لازم را بپرس.
۱۲) برای خوانایی از Markdown ساده و کم‌حجم استفاده کن: نکته‌های کلیدی، نام قطعه، شرط مهم و اقدام اصلی را با **بولد** مشخص کن؛ عنوان‌های کوتاه را با تیترهای کوچک یا عبارت بولد جدا کن. هشدار ایمنی را در خط جدا بیاور و در صورت نیاز از 🔴، 🟠 یا 🟢 استفاده کن. هر پاراگراف را کوتاه نگه دار؛ از بولد کردن همه متن، جدول‌های غیرضروری، ایموجی زیاد و نشانه‌گذاری تزئینی پرهیز کن. قالب‌بندی نباید باعث طولانی‌تر شدن پاسخ شود.
۱۳) توضیح داخلی یا زنجیره طولانی استدلال را نمایش نده. فقط نتیجه، دلیل‌های کوتاه و قابل فهم، سؤال‌های ضروری و اقدام‌های عملی را ارائه کن.

قالب پاسخ انعطاف‌پذیر است و نباید به همه سؤال‌ها تحمیل شود:
- جمع‌بندی: یک یا دو جمله درباره برداشت فعلی.
- علت‌های محتمل: فقط اگر شواهد برای مطرح‌کردن آن‌ها کافی است.
- بررسی بعدی: یک یا چند اقدام مشخص و ایمن.
- فوریت: فقط اگر برای تصمیم راننده مفید است.
اگر اطلاعات کافی نیست، تشخیص قطعی نده؛ پاسخ را با برداشت فعلی و محدودیت اطلاعات شروع کن، سناریوهای مشروط کوتاه ارائه بده و بدون پرسش مستقیم، اطلاعات مفید برای پیام بعدی را مشخص کن. از مقدمه‌های کلی، تکرار سؤال، تبلیغ، فهرست‌های طولانی و تیترهای غیرضروری پرهیز کن.''',
            },
            ...requestHistory.map((entry) => {
              'role': entry['role']!,
              'content': entry['content']!,
            }),
          ],
          'temperature': 0.3,
          'thinking': {'type': 'disabled'},
          'max_tokens': 1800,
        }),
      ),
      timeout: _diagnoseTimeout,
      rateLimitKey: 'directAiDiagnose',
    );

    final data = _parseBody(response);
    if (response.statusCode >= 400) {
      final error = data is Map
          ? (data['error'] is Map
              ? (data['error']['message'] ?? data['message'])
              : (data['error'] ?? data['message']))
          : null;
      final status = response.statusCode == 401 || response.statusCode == 403
          ? 'کلید هوش مصنوعی نامعتبر یا فاقد دسترسی است.'
          : response.statusCode == 429
              ? 'سرویس هوش مصنوعی موقتاً شلوغ است؛ کمی بعد دوباره تلاش کنید.'
              : 'سرویس هوش مصنوعی پاسخ موفق نداد.';
      throw ApiException(
        response.statusCode,
        status,
        details: {'providerMessage': error?.toString() ?? ''},
      );
    }

    // مصرف توکن و مدل برگشتی را بدون ثبت متن خصوصی گفتگو در لاگ ثبت می‌کنیم.
    if (data is Map) {
      final usage = data['usage'];
      final actualModel = data['model']?.toString() ?? _directAiModel;
      if (usage is Map) {
        debugPrint(
          '[AI Usage] model=$actualModel '
          'prompt=${usage['prompt_tokens'] ?? '?'} '
          'completion=${usage['completion_tokens'] ?? '?'} '
          'total=${usage['total_tokens'] ?? '?'}',
        );
      } else {
        debugPrint('[AI Usage] model=$actualModel; usage metadata unavailable');
      }
    }

    final choices = data is Map ? data['choices'] : null;
    final message = choices is List && choices.isNotEmpty && choices.first is Map
        ? (choices.first as Map)['message']
        : null;
    final content = message is Map ? message['content'] : null;
    final result = content is String
        ? content.trim()
        : content is List
            ? content
                .whereType<Map>()
                .map((part) => part['text']?.toString() ?? '')
                .join('\n')
                .trim()
            : '';
    if (result.isEmpty) {
      throw const ApiException(502, 'سرویس هوش مصنوعی پاسخ قابل استفاده‌ای نداد.');
    }

    try {
      await store.saveDiagnosis(
        carName: resolvedCarName,
        carYear: year,
        description: description,
        result: result,
      );
    } on InsufficientLocalCreditsException {
      // A concurrent request may have used the final credit after the
      // preflight check; route the user to the package shop, not a retry loop.
      throw const ApiException(
        402,
        'اعتبار عیب‌یابی تمام شده است. برای ادامه بسته جدید بخرید.',
      );
    } catch (e) {
      // Never return a successful diagnosis when the atomic local transaction
      // (credit deduction + history write) failed. Otherwise the user could
      // receive a paid result without a recorded entitlement deduction.
      debugPrint('[LocalStore] ثبت نتیجه/اعتبار محلی ناموفق بود: $e');
      throw const ApiException(
        500,
        'پاسخ هوش مصنوعی دریافت شد، اما ثبت نتیجه و اعتبار در گوشی ناموفق بود. لطفاً دوباره تلاش کنید.',
      );
    }

    return DiagnosisApiResult(
      result: result,
      diagnosticId: requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      responseMode: 'diagnosis',
    );
  }

  Future<String> diagnose(String token, String carId, String description, {required String year, String? carName}) async {
    final response = await diagnoseDetailed(token, carId, description, year: year, carName: carName);
    return response.result;
  }

  String? _extractResult(Map<String, dynamic> data) {
    if (data['data'] is Map) {
      final d = data['data'] as Map;
      return d['result']?.toString() ?? d['answer']?.toString() ?? d['text']?.toString();
    }
    return data['result']?.toString() ?? data['answer']?.toString() ?? data['text']?.toString();
  }

  Future<List<Diagnostic>> getHistory(String token, {PaginationParams? pagination}) async {
    if (_localStore != null) {
      final rows = await _localStore!.history;
      return rows.map((row) => Diagnostic.fromJson({
        'id': row['id'].toString(),
        'carId': row['car_name']?.toString() ?? '',
        'carName': row['car_name']?.toString(),
        'carYear': row['car_year']?.toString(),
        'description': row['description']?.toString(),
        'result': row['result']?.toString(),
        'createdAt': DateTime.fromMillisecondsSinceEpoch(
          row['created_at_ms'] as int,
        ).toIso8601String(),
        'status': 'completed',
        'type': 'text',
      })).toList(growable: false);
    }

    final params = {'history': 'true', ...?(pagination?.toQueryParams())};
    final uri = Uri.parse(Constants.diagnose).replace(queryParameters: params);
    final response = await _safeCall(
      () => _httpClient.get(uri, headers: _getHeaders(token)),
      rateLimitKey: 'getHistory',
    );
    final data = _parseAndEnsure(response, defaultError: 'خطا در دریافت تاریخچه');
    final List<dynamic> rawList;
    if (data['data'] is List) {
      rawList = data['data'] as List;
    } else if (data['history'] is List) {
      rawList = data['history'] as List;
    } else if (data['items'] is List) {
      rawList = data['items'] as List;
    } else {
      rawList = [];
    }
    return rawList.whereType<Map<String, dynamic>>().map(Diagnostic.fromJson).toList();
  }

  Future<void> deleteHistory(String token, String diagnosticId) async {
    if (diagnosticId.isEmpty) throw const ApiException(400, 'شناسه تاریخچه نامعتبر است.');
    if (_localStore != null) {
      await _localStore!.deleteDiagnosis(diagnosticId);
      return;
    }
    final uri = Uri.parse('${Constants.diagnose}/$diagnosticId');
    final response = await _safeCall(
      () => _httpClient.delete(uri, headers: _getHeaders(token)),
      rateLimitKey: 'deleteHistory',
    );
    _parseAndEnsure(response, defaultError: 'خطا در حذف تاریخچه');
  }

}