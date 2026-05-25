import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app_settings.dart';
import 'remote_config_service.dart';
import 'sync_service.dart';
import 'badge_service.dart';
import 'notification_handler.dart';
import 'splash_screen.dart';

// ── Background FCM handler ──────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  await Firebase.initializeApp();
  await NotificationHandler.showNotification(msg);
  await BadgeService.increment();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase ─────────────────────────────────────────────────────
  await Firebase.initializeApp();

  // Crashlytics — catch all Flutter errors automatically
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;


  // Performance monitoring
  FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

  // ── Background notification handler ──────────────────────────────
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── Load user settings ────────────────────────────────────────────
  await AppSettings.load();

  // ── Badge count ───────────────────────────────────────────────────
  await BadgeService.init();

  // ── Remote Config ─────────────────────────────────────────────────
  await RemoteConfigService.initialize();

  // ── Background sync ───────────────────────────────────────────────
  await SyncService.initialize();
  await SyncService.startPeriodicSync();

  // ── Notification channels ─────────────────────────────────────────
  await NotificationHandler.initialize();

  // ── Portrait lock ─────────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Edge-to-edge + Status bar ─────────────────────────────────────
  // edgeToEdge: Flutter draws from the very top of the screen (behind the
  // transparent status bar). Web pages use env(safe-area-inset-top) in
  // their CSS to push their own headers below the status bar. Without this
  // call, SafeArea(top:false) in WebViewScreen has no visible effect and
  // env(safe-area-inset-top) reports 0 inside the WebView.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    // Navigation bar also transparent — the web pages use
    // env(safe-area-inset-bottom) to pad themselves off the nav bar.
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ChatXAPApp());
}

class ChatXAPApp extends StatelessWidget {
  const ChatXAPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatXAP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DA3FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0F1F),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
