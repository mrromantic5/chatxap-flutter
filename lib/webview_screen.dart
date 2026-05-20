import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_handler.dart';

class WebViewScreen extends StatefulWidget {
  final String? initialUrl;
  const WebViewScreen({super.key, this.initialUrl});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webCtrl;
  bool _isLoading = true;
  bool _hasError = false;
  bool _hasInternet = true;
  double _progress = 0;

  static const String _baseUrl = 'https://c.x.t-lyfe.com.ng';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToFCM();
    _monitorConnectivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Connectivity monitor ────────────────────────────────────────
  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final connected = results.any((r) => r != ConnectivityResult.none);
      if (connected && !_hasInternet) {
        setState(() {
          _hasInternet = true;
          _hasError = false;
          _isLoading = true;
        });
        _webCtrl?.reload();
      } else if (!connected) {
        setState(() => _hasInternet = false);
      }
    });
  }

  // ── FCM listener ────────────────────────────────────────────────
  void _listenToFCM() {
    FirebaseMessaging.onMessage.listen((msg) {
      NotificationHandler.showNotification(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _navigateFromMessage(msg);
    });

    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        Future.delayed(const Duration(seconds: 3), () {
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

  // ── Register Flutter FCM token with ChatXAP backend ─────────────
  // Critical fix: without this the backend never knows the Flutter
  // FCM token, so notifications only go to the PWA service worker.
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final safeToken = token.replaceAll("'", "\'").replaceAll("\n", "");
      await _webCtrl?.evaluateJavascript(source: '''
(function() {
  try {
    var t = '$safeToken';
    var already = localStorage.getItem('cx_flutter_tok');
    if (already === t) return; // already registered this token
    fetch('/backend/push_subscribe.php', {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-ChatXAP-App': '1'
      },
      body: JSON.stringify({ token: t, device_type: 'android' })
    })
    .then(function(r){ return r.json(); })
    .then(function(d){
      if(d && d.success){
        localStorage.setItem('cx_flutter_tok', t);
        console.log('[ChatXAP] Flutter FCM registered:', d.action, 'user:', d.user_id);
      } else {
        console.warn('[ChatXAP] FCM register failed:', d ? d.error : 'unknown');
      }
    })
    .catch(function(e){ console.warn('[ChatXAP] FCM register error:', e); });
  } catch(ex) { console.warn('[ChatXAP] FCM register exception:', ex); }
})();
''');
    } catch (_) {}
  }

  void _navigateFromMessage(RemoteMessage msg) {
    if (_webCtrl == null) return;
    final d = msg.data;
    final type = d['type'] ?? '';
    final convId = d['conversation_id'] ?? '';
    final groupId = d['group_id'] ?? '';
    final chId = d['channel_id'] ?? '';

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

    // Text selection: disable on UI chrome, allow in message bubbles + inputs
    var styleId = 'cx-flutter-sel';
    var prev = document.getElementById(styleId);
    if (prev) prev.remove();
    var s = document.createElement('style');
    s.id = styleId;
    s.textContent =
      'body, .hdr, nav, .nav, .btm-nav, .topbar, button, ' +
      'a, label, .mhdr, .muser, .mtime, .sidebar, .menu {' +
      ' -webkit-user-select:none!important; user-select:none!important }' +
      '.bub span, .bub p, .bub div, .msg-text, input, textarea, [contenteditable] {' +
      ' -webkit-user-select:text!important; user-select:text!important }';
    document.head.appendChild(s);

    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overscrollBehavior = 'none';

    if (typeof window.registerFlutterFCMToken === 'function') {
      window.registerFlutterFCMToken('$safe');
    }
    window.dispatchEvent(new CustomEvent('flutterFCMToken', {detail: '$safe', bubbles: true}));
  } catch(e) {}
})();
''');
  }

  Future<void> _injectBridge() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _injectToken(token);
      // Register with backend on every page load — safe because
      // push_subscribe.php does INSERT IGNORE / UPDATE (no duplicates)
      await _registerTokenWithBackend(token);
    }

    await _webCtrl?.evaluateJavascript(source: '''
(function() {
  if (window.__CX_BRIDGE__) return;
  window.__CX_BRIDGE__ = true;
  window.IS_FLUTTER_APP = true;
  window.FLUTTER_PLATFORM = 'android';
  document.documentElement.style.overscrollBehavior = 'none';
  if (document.body) document.body.style.overscrollBehavior = 'none';
  window.FlutterBridge = {
    getFCMToken: function() { return window.FLUTTER_FCM_TOKEN || ''; },
    openUrl: function(u) {
      try { window.flutter_inappwebview.callHandler('Bridge','openUrl',u); } catch(e){}
    }
  };
  // Pass session cookie to Flutter for background notification reply
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
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 ChatXAPNative/1.0',
    allowsBackForwardNavigationGestures: false,
  );

  @override
  Widget build(BuildContext context) {
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
                    'X-Requested-With': 'ChatXAPNative/1.0',
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
                            await prefs.setString('session_cookie', args[1] as String);
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
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                      _hasError = false;
                      _progress = 0;
                    });
                  }
                },

                onProgressChanged: (ctrl, progress) {
                  if (mounted) setState(() => _progress = progress / 100.0);
                },

                onLoadStop: (ctrl, url) async {
                  if (mounted) setState(() => _isLoading = false);
                  await _injectBridge();
                },

                onReceivedError: (ctrl, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = true;
                    });
                  }
                },

                onReceivedHttpError: (ctrl, request, response) {
                  if (request.isForMainFrame == true &&
                      (response.statusCode ?? 0) >= 500 &&
                      mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = true;
                    });
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
                    origin: origin,
                    allow: false,
                    retain: false,
                  );
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
                  if (url.startsWith('http') || url.startsWith('https')) {
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

              // Error/offline screen
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
              Icon(
                !_hasInternet
                    ? Icons.wifi_off_rounded
                    : Icons.cloud_off_rounded,
                color: const Color(0xFF4DA3FF),
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                !_hasInternet ? 'No Internet' : 'Connection Error',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                !_hasInternet
                    ? 'ChatXAP needs internet.\nCheck your connection and try again.'
                    : 'Could not reach the server.\nPlease retry.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _isLoading = true;
                    });
                    _webCtrl?.reload();
                  },
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 20),
                  label: const Text('Try Again',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DA3FF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExitDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Exit ChatXAP?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        content: const Text('Are you sure you want to exit?',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay',
                style: TextStyle(
                    color: Color(0xFF4DA3FF),
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Exit',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
