import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'notification_handler.dart';
import 'game_widget.dart';
import 'app_settings.dart';
import 'badge_service.dart';
import 'biometric_lock.dart';
import 'native_settings_page.dart';
import 'package:share_plus/share_plus.dart';
import 'update_service.dart';
import 'remote_config_service.dart';
import 'pip_service.dart';

class WebViewScreen extends StatefulWidget {
  final String? initialUrl;
  const WebViewScreen({super.key, this.initialUrl});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webCtrl;
  bool _isLoading   = true;
  bool _hasError    = false;
  bool _hasInternet = true;
  double _progress  = 0;

  // ── Lock state ──────────────────────────────────────────────────────────
  // Lock on cold start when biometric lock is enabled AND a PIN has been set.
  // A pinHash that starts with '_legacy_' still counts as "PIN set" — the
  // lock screen handles the transparent migration to v2.
  bool _locked = AppSettings.biometricLock && AppSettings.pinHash.isNotEmpty;
  DateTime? _backgroundedAt;

  static const String _baseUrl = 'https://c.x.t-lyfe.com.ng';

  bool get _screenshotBlocked => AppSettings.screenshotBlock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToFCM();
    _monitorConnectivity();
    Future.microtask(() => _applyScreenshotPrevention());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final blocked = await RemoteConfigService.checkForceUpdate(context);
      if (blocked) return;
      await RemoteConfigService.checkMaintenance(context);
      await Future.delayed(const Duration(seconds: 10));
      if (mounted) UpdateService.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── App lifecycle — handles auto-lock ──────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt = DateTime.now();
      // Record timestamp whenever biometric or auto-lock is active,
      // so isAutoLockExpired() always has a valid reference.
      if (AppSettings.biometricLock || AppSettings.autoLock) {
        AppSettings.setLastLocked(DateTime.now().millisecondsSinceEpoch);
      }
    }

    if (state == AppLifecycleState.resumed) {
      BadgeService.clear();

      // Check if we should lock on resume.
      if (AppSettings.biometricLock && AppSettings.pinHash.isNotEmpty) {
        final shouldLock = AppSettings.autoLock
            ? AppSettings.isAutoLockExpired()
            // No auto-lock timer: lock after 30 s in background,
            // or if _backgroundedAt is null (cold launch / killed & relaunched).
            : (_backgroundedAt == null ||
                DateTime.now().difference(_backgroundedAt!) >
                    const Duration(seconds: 30));
        if (shouldLock && !_locked) {
          setState(() => _locked = true);
        }
      }

      Future.microtask(() => _applyScreenshotPrevention());
    }
  }

  static const _mainChannel = MethodChannel('com.tlyfe.chatxap/pip');

  Future<void> _applyScreenshotPrevention() async {
    try {
      await _mainChannel.invokeMethod(
          'setSecureFlag', {'secure': AppSettings.screenshotBlock});
    } catch (_) {}
  }

  // ── Connectivity monitor ────────────────────────────────────────────────
  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final connected = results.any((r) => r != ConnectivityResult.none);
      if (connected && !_hasInternet) {
        setState(() {
          _hasInternet = true;
          _hasError    = false;
          _isLoading   = true;
        });
        _webCtrl?.reload();
      } else if (!connected) {
        setState(() => _hasInternet = false);
      }
    });
  }

  // ── FCM listener ────────────────────────────────────────────────────────
  void _listenToFCM() {
    FirebaseMessaging.onMessage.listen((msg) {
      NotificationHandler.showNotification(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      BadgeService.clear();
      _navigateFromMessage(msg);
    });

    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        Future.delayed(const Duration(seconds: 3), () {
          BadgeService.clear();
          _navigateFromMessage(msg);
        });
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _injectToken(token);
      await _registerTokenWithBackend(token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
    });
  }

  // ── Register FCM token with backend ─────────────────────────────────────
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final safeToken = token.replaceAll("'", "\\'").replaceAll("\n", "");
      await _webCtrl?.evaluateJavascript(source: '''
(function() {
  try {
    var t = '$safeToken';
    var already = localStorage.getItem('cx_flutter_tok');
    if (already === t) return;
    fetch('/backend/push_subscribe.php', {
      method: 'POST', credentials: 'same-origin',
      headers: {'Content-Type':'application/json',
                'X-Requested-With':'XMLHttpRequest','X-ChatXAP-App':'1'},
      body: JSON.stringify({ token: t, device_type: 'android' })
    }).then(function(r){ return r.json(); })
    .then(function(d){
      if(d && d.success) localStorage.setItem('cx_flutter_tok', t);
    }).catch(function(){});
  } catch(ex) {}
})();
''');
    } catch (_) {}
  }

  void _navigateFromMessage(RemoteMessage msg) {
    if (_webCtrl == null) return;
    final d       = msg.data;
    final type    = d['type'] ?? '';
    final convId  = d['conversation_id'] ?? '';
    final groupId = d['group_id'] ?? '';
    final chId    = d['channel_id'] ?? '';

    String url = '$_baseUrl/rc.html';
    if ((type == 'private_message' || type == 'dm') && convId.isNotEmpty) {
      url = '$_baseUrl/dm.html?conversation_id=$convId';
    } else if (type == 'public_message') {
      url = '$_baseUrl/chat.html';
    } else if (type == 'group_message' && groupId.isNotEmpty) {
      url = '$_baseUrl/group.html?group_id=$groupId';
    } else if (type == 'channel_message' && chId.isNotEmpty) {
      url = '$_baseUrl/channel.html?channel_id=$chId';
    }
    _webCtrl!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _injectToken(String token) async {
    if (_webCtrl == null) return;
    final safe = token
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '');

    await _webCtrl!.evaluateJavascript(source: '''
(function() {
  try {
    window.FLUTTER_FCM_TOKEN = '$safe';
    window.IS_FLUTTER_APP = true;
    window.FLUTTER_PLATFORM = 'android';
    var styleId = 'cx-flutter-sel';
    var prev = document.getElementById(styleId);
    if (prev) prev.remove();
    var s = document.createElement('style');
    s.id = styleId;
    s.textContent =
      'body,.hdr,nav,.nav,.btm-nav,.topbar,button,a,label,.mhdr,.muser,.mtime,.sidebar,.menu{' +
      '-webkit-user-select:none!important;user-select:none!important}' +
      '.bub span,.bub p,.bub div,.msg-text,input,textarea,[contenteditable]{' +
      '-webkit-user-select:text!important;user-select:text!important}';
    document.head.appendChild(s);
    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overscrollBehavior = 'none';
    if (typeof window.registerFlutterFCMToken === 'function') {
      window.registerFlutterFCMToken('$safe');
    }
    window.dispatchEvent(new CustomEvent('flutterFCMToken',{detail:'$safe',bubbles:true}));
  } catch(e) {}
})();
''');
  }

  Future<void> _injectBridge() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _injectToken(token);
      await _registerTokenWithBackend(token);
    }

    final settingsJs = AppSettings.jsSettingsObject;

    await _webCtrl?.evaluateJavascript(source: '''
(function() {
  if (window.__CX_BRIDGE__) return;
  window.__CX_BRIDGE__ = true;
  window.IS_FLUTTER_APP = true;
  window.FLUTTER_PLATFORM = 'android';
  document.documentElement.style.overscrollBehavior = 'none';
  if (document.body) document.body.style.overscrollBehavior = 'none';

  $settingsJs

  (function() {
    var urlParams = new URLSearchParams(window.location.search);
    var convId = urlParams.get('conversation_id') ||
                 urlParams.get('group_id') ||
                 urlParams.get('channel_id') || '';
    if (convId) {
      window.flutter_inappwebview.callHandler('Bridge', 'setActiveConv', convId);
    }
    window.addEventListener('beforeunload', function() {
      window.flutter_inappwebview.callHandler('Bridge', 'setActiveConv', '');
    });
  })();

  window.FlutterBridge = {
    getFCMToken: function() { return window.FLUTTER_FCM_TOKEN || ''; },
    openUrl: function(u) {
      try { window.flutter_inappwebview.callHandler('Bridge','openUrl',u); } catch(e){}
    },
    openNativeSettings: function() {
      try { window.flutter_inappwebview.callHandler('Bridge','openNativeSettings'); } catch(e){}
    },
    haptic: function(type) {
      try { window.flutter_inappwebview.callHandler('Bridge','haptic',type||'light'); } catch(e){}
    },
    clearBadge: function() {
      try { window.flutter_inappwebview.callHandler('Bridge','clearBadge'); } catch(e){}
    },
    shareText: function(text) {
      try { window.flutter_inappwebview.callHandler('Bridge','shareText',text); } catch(e){}
    },
    shareUrl: function(url, title) {
      try { window.flutter_inappwebview.callHandler('Bridge','shareUrl',url,title||''); } catch(e){}
    },
    enterPiP: function() {
      try { window.flutter_inappwebview.callHandler('Bridge','enterPiP'); } catch(e){}
    },
    getRemoteConfig: async function(key) {
      try { return await window.flutter_inappwebview.callHandler('Bridge','getRemoteConfig',key); }
      catch(e){ return null; }
    }
  };

  try {
    window.flutter_inappwebview.callHandler('Bridge', 'saveSessionCookie', document.cookie);
  } catch(e) {}
})();
''');
  }

  final InAppWebViewSettings _webSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    cacheEnabled: true,
    clearSessionCache: false,
    thirdPartyCookiesEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    allowFileAccess: true,
    allowContentAccess: true,
    useHybridComposition: true,
    hardwareAcceleration: true,
    transparentBackground: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    overScrollMode: OverScrollMode.NEVER,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    geolocationEnabled: false,
    useShouldOverrideUrlLoading: true,
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; ChatXAP) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 ChatXAPNative/1.1',
    allowsBackForwardNavigationGestures: false,
  );

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show full-screen biometric lock when app is locked.
    if (_locked) {
      return BiometricLockScreen(
        onUnlocked: () {
          if (mounted) setState(() => _locked = false);
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (_webCtrl != null && await _webCtrl!.canGoBack()) {
          await _webCtrl!.goBack();
        } else {
          _showExitDialog();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F1F),
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.initialUrl ?? '$_baseUrl/?app=1'),
                  headers: {
                    'X-Requested-With': 'ChatXAPNative/1.1',
                    'X-ChatXAP-App': '1',
                  },
                ),
                initialSettings: _webSettings,

                onWebViewCreated: (ctrl) {
                  _webCtrl = ctrl;
                  NotificationHandler.setWebController(ctrl);

                  ctrl.addJavaScriptHandler(
                    handlerName: 'Bridge',
                    callback: (args) async {
                      if (args.isEmpty) return null;
                      switch (args[0] as String) {

                        case 'getFCMToken':
                          return await FirebaseMessaging.instance.getToken();

                        case 'openUrl':
                          if (args.length > 1) {
                            final uri = Uri.tryParse(args[1] as String);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          }
                          return null;

                        case 'saveSessionCookie':
                          if (args.length > 1) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                                'session_cookie', args[1] as String);
                          }
                          return null;

                        case 'setActiveConv':
                          final convId = args.length > 1
                              ? args[1] as String : '';
                          NotificationHandler.setActiveConversation(
                              convId.isEmpty ? null : convId);
                          return null;

                        case 'openNativeSettings':
                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const NativeSettingsPage()),
                            ).then((_) {
                              Future.microtask(() => _applyScreenshotPrevention());
                              _injectBridge();
                            });
                          }
                          return null;

                        case 'haptic':
                          if (!AppSettings.hapticFeedback) return null;
                          final type = args.length > 1
                              ? args[1] as String : 'light';
                          switch (type) {
                            case 'heavy':
                              HapticFeedback.heavyImpact(); break;
                            case 'medium':
                              HapticFeedback.mediumImpact(); break;
                            case 'selection':
                              HapticFeedback.selectionClick(); break;
                            default:
                              HapticFeedback.lightImpact();
                          }
                          return null;

                        case 'clearBadge':
                          await BadgeService.clear();
                          return null;

                        case 'shareText':
                          if (args.length > 1) {
                            await Share.share(args[1] as String);
                          }
                          return null;

                        case 'shareUrl':
                          if (args.length > 1) {
                            await Share.share(args[1] as String,
                                subject: args.length > 2
                                    ? args[2] as String : 'ChatXAP');
                          }
                          return null;

                        case 'enterPiP':
                          await PiPService.enterPiP();
                          return null;

                        case 'isPiPSupported':
                          return await PiPService.isPiPSupported();

                        case 'getRemoteConfig':
                          if (args.length > 1) {
                            final key = args[1] as String;
                            switch (key) {
                              case 'gamesEnabled':
                                return RemoteConfigService.gamesEnabled;
                              case 'aiEnabled':
                                return RemoteConfigService.aiEnabled;
                              case 'bannerEnabled':
                                return RemoteConfigService.bannerEnabled;
                              case 'bannerMessage':
                                return RemoteConfigService.bannerMessage;
                              default:
                                return null;
                            }
                          }
                          return null;

                        case 'closeApp':
                          SystemNavigator.pop();
                          return null;

                        default:
                          return null;
                      }
                    },
                  );
                },

                onLoadStart: (ctrl, url) {
                  if (mounted) setState(() {
                    _isLoading = true;
                    _hasError  = false;
                    _progress  = 0;
                  });
                },

                onProgressChanged: (ctrl, progress) {
                  if (mounted) setState(() => _progress = progress / 100.0);
                },

                onLoadStop: (ctrl, url) async {
                  if (mounted) setState(() => _isLoading = false);
                  await _injectBridge();
                  await BadgeService.clear();
                  _schedulePreload(ctrl, url?.toString() ?? '');
                },

                onReceivedError: (ctrl, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() { _isLoading = false; _hasError = true; });
                  }
                },

                onReceivedHttpError: (ctrl, request, response) {
                  if (request.isForMainFrame == true &&
                      (response.statusCode ?? 0) >= 500 && mounted) {
                    setState(() { _isLoading = false; _hasError = true; });
                  }
                },

                onPermissionRequest: (ctrl, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },

                onGeolocationPermissionsShowPrompt: (ctrl, origin) async {
                  return GeolocationPermissionShowPromptResponse(
                      origin: origin, allow: false, retain: false);
                },

                shouldOverrideUrlLoading: (ctrl, action) async {
                  final url = action.request.url?.toString() ?? '';
                  if (url.contains('t-lyfe.com.ng') ||
                      url.startsWith('blob:') ||
                      url.startsWith('data:') ||
                      url.startsWith('javascript:') ||
                      url.startsWith('about:') ||
                      url.contains('onrender.com')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (url.startsWith('http')) {
                    try {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    } catch (_) {}
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),

              // Progress bar
              if (_isLoading)
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: LinearProgressIndicator(
                    value: _progress > 0.03 ? _progress : null,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4DA3FF)),
                    minHeight: 2.5,
                  ),
                ),

              if (_hasError || !_hasInternet) _buildErrorScreen(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: const Color(0xFF0A0F1F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(!_hasInternet
                  ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                  color: const Color(0xFF4DA3FF), size: 80),
              const SizedBox(height: 24),
              Text(!_hasInternet ? 'No Internet' : 'Connection Error',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(!_hasInternet
                  ? 'ChatXAP needs internet.\nCheck your connection and try again.'
                  : 'Could not reach the server.\nPlease retry.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 15, height: 1.6)),
              const SizedBox(height: 30),
              if (!_hasInternet)
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const GameWidget())),
                    icon: const Icon(Icons.gamepad_rounded,
                        color: Colors.white, size: 20),
                    label: const Text('Play NOVA BLASTER Offline',
                        style: TextStyle(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFC),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _hasError = false; _isLoading = true; });
                    _webCtrl?.reload();
                  },
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 20),
                  label: const Text('Try Again',
                      style: TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DA3FF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Predictive preloading ─────────────────────────────────────────────────
  void _schedulePreload(InAppWebViewController ctrl, String currentUrl) {
    if (currentUrl.contains('login') || currentUrl.contains('index')) {
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await ctrl.evaluateJavascript(source: '''
(function(){
  var link = document.createElement('link');
  link.rel = 'prefetch';
  link.href = '/rc.html';
  document.head.appendChild(link);
})();
''');
        } catch (_) {}
      });
    }
  }

  void _showExitDialog() {
    if (!mounted) return;
    String? _message;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Dialog(
          backgroundColor: const Color(0xFF0F1626),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4B4B).withOpacity(0.1),
                  ),
                  child: const Icon(Icons.power_settings_new_rounded,
                      color: Color(0xFFFF4B4B), size: 30),
                ),
                const SizedBox(height: 20),
                const Text('Exit ChatXAP?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text(
                  'Are you sure you want to exit ChatXAP?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14, height: 1.5),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _message == 'Goodbye 👋'
                          ? const Color(0xFFFF4B4B)
                          : const Color(0xFF4DA3FF),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (AppSettings.hapticFeedback) {
                          HapticFeedback.mediumImpact();
                        }
                        setDlgState(() => _message = 'Great 💙');
                        Future.delayed(
                            const Duration(milliseconds: 700), () {
                          if (ctx.mounted) Navigator.pop(ctx);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF4DA3FF).withOpacity(0.12),
                          border: Border.all(
                              color: const Color(0xFF4DA3FF).withOpacity(0.4)),
                        ),
                        child: const Center(
                          child: Text('NO',
                              style: TextStyle(
                                  color: Color(0xFF4DA3FF),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (AppSettings.hapticFeedback) {
                          HapticFeedback.heavyImpact();
                        }
                        setDlgState(() => _message = 'Goodbye 👋');
                        Future.delayed(
                            const Duration(milliseconds: 700), () {
                          SystemNavigator.pop();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFFFF4B4B).withOpacity(0.12),
                          border: Border.all(
                              color: const Color(0xFFFF4B4B).withOpacity(0.4)),
                        ),
                        child: const Center(
                          child: Text('YES',
                              style: TextStyle(
                                  color: Color(0xFFFF4B4B),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
