import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'services/api_service.dart';
import 'services/local_first_store.dart';
import 'services/bazaar_billing_service.dart';
import 'screens/local_phone_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'theme/app_theme.dart';
import 'theme/brand.dart';
import 'widgets/brand_logo.dart';
import 'widgets/mechanic_backdrop.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[dotenv] فایل .env یافت نشد یا خطا در بارگذاری: $e');
    debugPrint('[dotenv] از مقادیر پیش‌فرض constants استفاده می‌شود.');
  }

  _setupErrorWidget();
  Constants.printInfo();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final localStore = await LocalFirstStore.open();

  final api = await _initServices(localStore: localStore);
  final localeProvider = await LocaleProvider.create();
  final themeProvider = await ThemeProvider.create();

  runApp(
    MultiProvider(
      providers: [
        // ApiService owns the HTTP client for the lifetime of the app.
        Provider<ApiService>(create: (_) => api),
        Provider<LocalFirstStore>.value(value: localStore),
        Provider<BazaarBillingService>(create: (_) => BazaarBillingService(localStore)),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api, localStore: localStore)..checkAuthStatus(),
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
      ],
      child: const SmartMechanicApp(),
    ),
  );
}

void _setupErrorWidget() {
  ErrorWidget.builder = (details) {
    debugPrint('[ErrorBoundary] ${details.exception}');
    return const Material(
      color: BrandColors.darkBackground,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandLogo(size: 88),
              SizedBox(height: 20),
              Text(
                'مشکلی پیش آمد',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'لطفاً اپلیکیشن را مجدداً باز کنید.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };
}

Future<ApiService> _initServices({required LocalFirstStore localStore}) async {
  return ApiService(
    httpClient: http.Client(),
    defaultTimeout: Constants.defaultTimeout,
    diagnoseTimeout: Constants.diagnoseTimeout,
    localStore: localStore,
  );
}

class SmartMechanicApp extends StatelessWidget {
  const SmartMechanicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();

    return MaterialApp(
      title: Constants.appName,
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      supportedLocales: LocaleConfig.flutterLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: brightness == Brightness.dark
              ? BrandColors.darkBackground
              : BrandColors.lightBackground,
          systemNavigationBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Directionality(
            textDirection: localeProvider.textDirection,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const MechanicBackdrop(),
                child ?? const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
      home: const _AppEntryPoint(),
      routes: {
        '/notification-settings': (_) => const NotificationSettingsScreen(),
      },
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) return const _SplashScreen();
    if (auth.phone == null || auth.phone!.isEmpty) return const LocalPhoneScreen();
    return const HomeScreen();
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 120, showGlow: true),
                const SizedBox(height: 20),
                Text(
                  Brand.nameFa,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Brand.tagline,
                  style: TextStyle(fontSize: 13, color: theme.hintColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'در حال بارگذاری...',
                  style: TextStyle(fontSize: 13, color: theme.hintColor),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    backgroundColor: theme.colorScheme.secondary.withOpacity(0.15),
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
