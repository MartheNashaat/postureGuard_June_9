import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/session_summary.dart';
import 'screens/home_screen.dart';
import 'screens/calibration_screen.dart';
import 'screens/session_screen.dart';
import 'screens/summary_screen.dart';
import 'screens/history_screen.dart';
import 'background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
//   runApp(const PostureGuardApp());
// }
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WakelockPlus.enable();
  await Permission.notification.request();
  // Initialize the background service configuration
  await initializeService();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PostureGuardApp());
}

class PostureGuardApp extends StatelessWidget {
  const PostureGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostureGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/calibration': (context) => const CalibrationScreen(),
        '/session': (context) => const SessionScreen(),
        '/history': (context) => const HistoryScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/summary') {
          final summary = settings.arguments as SessionSummary;
          return MaterialPageRoute(
            builder: (context) => SummaryScreen(summary: summary),
          );
        }
        return null;
      },
    );
  }
}
