import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/settings_screen.dart';
import 'services/locale_service.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const YorigoApp());
}

class YorigoApp extends StatefulWidget {
  const YorigoApp({super.key});

  @override
  State<YorigoApp> createState() => _YorigoAppState();
}

class _YorigoAppState extends State<YorigoApp> {
  final LocaleService _localeService = LocaleService();

  @override
  void initState() {
    super.initState();
    _localeService.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    _localeService.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LocaleProvider(
      localeService: _localeService,
      child: MaterialApp(
        title: '요리고',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        locale: _localeService.locale,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ko', ''), Locale('en', '')],
        initialRoute: '/',
        routes: {
          '/': (context) => const MainNavigator(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignupScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

class LocaleProvider extends InheritedWidget {
  final LocaleService localeService;

  const LocaleProvider({
    super.key,
    required this.localeService,
    required super.child,
  });

  static LocaleService of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LocaleProvider>()!
        .localeService;
  }

  @override
  bool updateShouldNotify(LocaleProvider oldWidget) {
    return localeService != oldWidget.localeService;
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const RecipesScreen(),
    const FeedScreen(),
    const CartScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    // Import BottomNav widget
    // Since we can't import it here without circular dependency,
    // we'll build it inline
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(context, Icons.home_outlined, 0),
              _buildNavItem(context, Icons.restaurant_outlined, 1),
              _buildNavItem(context, Icons.people_outline, 2),
              _buildNavItem(context, Icons.shopping_cart_outlined, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, int index) {
    final l10n = AppLocalizations.of(context);
    final isActive = _currentIndex == index;
    final color = isActive ? const Color(0xFFFF6900) : const Color(0xFF999999);

    String label;
    switch (index) {
      case 0:
        label = l10n?.home ?? '홈';
        break;
      case 1:
        label = l10n?.recipes ?? '레시피';
        break;
      case 2:
        label = l10n?.feed ?? '피드';
        break;
      case 3:
        label = l10n?.cart ?? '장바구니';
        break;
      default:
        label = '';
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
