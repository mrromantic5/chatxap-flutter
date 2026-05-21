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

  // ── UPDATED ERROR SCREEN WITH GAME BUTTON ──────────────────────
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
              const SizedBox(height: 30),
              // ── NEW: Game button (only shows when offline) ──
              if (!_hasInternet)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GameWidget(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.gamepad_rounded,
                        color: Colors.white, size: 20),
                    label: const Text('Play NOVA BLASTER Offline',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFC),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // ── Existing Try Again button ──
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

  // ── PREMIUM SAAS-GRADE EXIT DIALOG ──────────────────────────────
  void _showExitDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => const _PremiumExitDialog(),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║           PREMIUM ChatXAP EXIT DIALOG — v2                      ║
// ╚══════════════════════════════════════════════════════════════════╝
class _PremiumExitDialog extends StatefulWidget {
  const _PremiumExitDialog();

  @override
  State<_PremiumExitDialog> createState() => _PremiumExitDialogState();
}

class _PremiumExitDialogState extends State<_PremiumExitDialog>
    with TickerProviderStateMixin {

  // ── Controllers ────────────────────────────────────────────────
  late final AnimationController _ringA;   // ring rotation
  late final AnimationController _pulseA;  // glow pulse
  late final AnimationController _enterA;  // entrance scale

  // ── Drag state ─────────────────────────────────────────────────
  // We track which button is being dragged ('stay'/'exit'/null)
  // and where it currently is (offset from its resting center)
  String? _dragging;           // which button is being dragged
  Offset  _stayDrag = Offset.zero;
  Offset  _exitDrag = Offset.zero;
  bool    _stayOnCenter = false;
  bool    _exitOnCenter = false;
  bool    _confirmed = false;

  // ── Layout geometry (all relative to dialog center) ───────────
  // Dialog is 300×320. Center is at (150,185) within the widget.
  // Stay lives at left, Exit at right — both on horizontal axis.
  static const double _orbitR  = 100.0;  // button orbit radius
  static const double _btnR    =  34.0;  // button circle radius
  static const double _snapR   =  36.0;  // snap zone at center

  // Rest positions (relative to dialog center point)
  static const Offset _stayRest = Offset(-_orbitR, 0);
  static const Offset _exitRest = Offset( _orbitR, 0);

  @override
  void initState() {
    super.initState();
    _ringA = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _pulseA = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _enterA = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
  }

  @override
  void dispose() {
    _ringA.dispose();
    _pulseA.dispose();
    _enterA.dispose();
    super.dispose();
  }

  // ── Check if a drag offset is close enough to center ──────────
  bool _nearCenter(Offset off) => off.distance < _snapR;

  // ── Handle Stay button drag ────────────────────────────────────
  void _onStayUpdate(DragUpdateDetails d) {
    if (_confirmed) return;
    final newOff = _stayDrag + d.delta;
    // Limit how far it can travel (not beyond right side)
    final clamped = Offset(
      newOff.dx.clamp(-_orbitR - 10, _orbitR + 10),
      newOff.dy.clamp(-80.0, 80.0),
    );
    final onCenter = _nearCenter(clamped);
    if (onCenter != _stayOnCenter) HapticFeedback.selectionClick();
    setState(() {
      _stayDrag     = clamped;
      _stayOnCenter = onCenter;
      _dragging     = 'stay';
    });
  }

  void _onStayEnd(DragEndDetails d) {
    if (_confirmed) return;
    if (_stayOnCenter) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _stayDrag     = Offset.zero;
        _stayOnCenter = false;
        _dragging     = null;
      });
    }
  }

  // ── Handle Exit button drag ────────────────────────────────────
  void _onExitUpdate(DragUpdateDetails d) {
    if (_confirmed) return;
    final newOff = _exitDrag + d.delta;
    final clamped = Offset(
      newOff.dx.clamp(-_orbitR - 10, _orbitR + 10),
      newOff.dy.clamp(-80.0, 80.0),
    );
    final onCenter = _nearCenter(clamped);
    if (onCenter != _exitOnCenter) HapticFeedback.selectionClick();
    setState(() {
      _exitDrag     = clamped;
      _exitOnCenter = onCenter;
      _dragging     = 'exit';
    });
  }

  void _onExitEnd(DragEndDetails d) {
    if (_confirmed) return;
    if (_exitOnCenter) {
      HapticFeedback.heavyImpact();
      setState(() => _confirmed = true);
      Future.delayed(const Duration(milliseconds: 350),
          () => SystemNavigator.pop());
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _exitDrag     = Offset.zero;
        _exitOnCenter = false;
        _dragging     = null;
      });
    }
  }

  // ── Snap animation back when drag resets ──────────────────────
  Widget _animatedReset(Widget child, Offset current) {
    return AnimatedSlide(
      offset: current == Offset.zero ? Offset.zero : Offset(current.dx / 200, current.dy / 200),
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Accent colors depending on state
    final Color accent = _exitOnCenter || _confirmed
        ? const Color(0xFFFF4B4B)
        : _stayOnCenter
            ? const Color(0xFF4DA3FF)
            : const Color(0xFF4DA3FF);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _enterA, curve: Curves.elasticOut),
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            color: const Color(0xFF080D1A),
            border: Border.all(
              color: accent.withOpacity(0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.18),
                blurRadius: 48,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Gradient top bar ─────────────────────────────
              Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32)),
                  gradient: LinearGradient(colors: [
                    const Color(0xFF4DA3FF),
                    const Color(0xFF7C5CFC),
                    accent,
                  ]),
                ),
              ),

              const SizedBox(height: 28),

              // ── Title ────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseA,
                builder: (_, __) => Text(
                  _confirmed
                      ? 'Goodbye 👋'
                      : _exitOnCenter
                          ? 'Release to exit'
                          : _stayOnCenter
                              ? 'Release to stay'
                              : 'Exit ChatXAP?',
                  style: TextStyle(
                    color: _exitOnCenter || _confirmed
                        ? const Color(0xFFFF4B4B)
                        : _stayOnCenter
                            ? const Color(0xFF4DA3FF)
                            : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _dragging != null
                    ? 'Drop it in the center ✦'
                    : 'Drag a button to the glowing center',
                style: TextStyle(
                  color: const Color(0xFF9CA3AF).withOpacity(0.8),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 32),

              // ── Ring arena ───────────────────────────────────
              SizedBox(
                width: 290,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    // Outer rotating dashed ring
                    AnimatedBuilder(
                      animation: _ringA,
                      builder: (_, __) => Transform.rotate(
                        angle: _ringA.value * 2 * 3.14159,
                        child: CustomPaint(
                          size: const Size(250, 250),
                          painter: _DashedCirclePainter(
                            color: accent.withOpacity(0.3),
                            strokeWidth: 1.5,
                            dashCount: 40,
                          ),
                        ),
                      ),
                    ),

                    // Counter-rotating inner ring
                    AnimatedBuilder(
                      animation: _ringA,
                      builder: (_, __) => Transform.rotate(
                        angle: -_ringA.value * 2 * 3.14159,
                        child: CustomPaint(
                          size: const Size(190, 190),
                          painter: _DashedCirclePainter(
                            color: accent.withOpacity(0.15),
                            strokeWidth: 1.0,
                            dashCount: 24,
                          ),
                        ),
                      ),
                    ),

                    // Orbit dots (6 particles spinning)
                    AnimatedBuilder(
                      animation: _ringA,
                      builder: (_, __) => CustomPaint(
                        size: const Size(290, 240),
                        painter: _OrbitDotsPainter(
                          progress: _ringA.value,
                          color: accent,
                          radius: 120,
                        ),
                      ),
                    ),

                    // Center target zone — glows when something approaches
                    AnimatedBuilder(
                      animation: _pulseA,
                      builder: (_, __) {
                        final nearAny = _stayOnCenter || _exitOnCenter;
                        final pulse = 0.7 + 0.3 * _pulseA.value;
                        return Container(
                          width: nearAny ? 72 : 56,
                          height: nearAny ? 72 : 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _confirmed
                                ? const Color(0xFFFF4B4B).withOpacity(0.15)
                                : nearAny
                                    ? accent.withOpacity(0.18 * pulse)
                                    : const Color(0xFF1A2540)
                                        .withOpacity(0.8),
                            border: Border.all(
                              color: accent.withOpacity(
                                  nearAny ? 0.9 : 0.35 * pulse),
                              width: nearAny ? 2.5 : 1.5,
                            ),
                            boxShadow: nearAny
                                ? [
                                    BoxShadow(
                                      color: accent.withOpacity(0.5),
                                      blurRadius: 24,
                                      spreadRadius: 6,
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _confirmed
                                ? Icons.check_rounded
                                : nearAny
                                    ? Icons.fingerprint
                                    : Icons.add_rounded,
                            color: accent.withOpacity(
                                nearAny ? 1.0 : 0.5),
                            size: nearAny ? 30 : 22,
                          ),
                        );
                      },
                    ),

                    // ── STAY button (left side) ──────────────────
                    Transform.translate(
                      offset: _stayRest + _stayDrag,
                      child: GestureDetector(
                        onPanUpdate: _onStayUpdate,
                        onPanEnd: _onStayEnd,
                        onPanCancel: () => setState(() {
                          _stayDrag = Offset.zero;
                          _stayOnCenter = false;
                          _dragging = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _stayOnCenter
                              ? _btnR * 2 + 12
                              : _btnR * 2,
                          height: _stayOnCenter
                              ? _btnR * 2 + 12
                              : _btnR * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _stayOnCenter
                                  ? [
                                      const Color(0xFF4DA3FF),
                                      const Color(0xFF1A6FCC),
                                    ]
                                  : [
                                      const Color(0xFF1A2A45),
                                      const Color(0xFF0E1830),
                                    ],
                            ),
                            border: Border.all(
                              color: const Color(0xFF4DA3FF)
                                  .withOpacity(_stayOnCenter ? 0 : 0.7),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4DA3FF).withOpacity(
                                    _stayOnCenter ? 0.65 : 0.25),
                                blurRadius: _stayOnCenter ? 24 : 10,
                                spreadRadius: _stayOnCenter ? 4 : 0,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                color: _stayOnCenter
                                    ? Colors.white
                                    : const Color(0xFF4DA3FF),
                                size: 18,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Stay',
                                style: TextStyle(
                                  color: _stayOnCenter
                                      ? Colors.white
                                      : const Color(0xFF4DA3FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── EXIT button (right side) ─────────────────
                    Transform.translate(
                      offset: _exitRest + _exitDrag,
                      child: GestureDetector(
                        onPanUpdate: _onExitUpdate,
                        onPanEnd: _onExitEnd,
                        onPanCancel: () => setState(() {
                          _exitDrag = Offset.zero;
                          _exitOnCenter = false;
                          _dragging = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _exitOnCenter
                              ? _btnR * 2 + 12
                              : _btnR * 2,
                          height: _exitOnCenter
                              ? _btnR * 2 + 12
                              : _btnR * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _exitOnCenter || _confirmed
                                  ? [
                                      const Color(0xFFFF4B4B),
                                      const Color(0xFFCC1A1A),
                                    ]
                                  : [
                                      const Color(0xFF45101A),
                                      const Color(0xFF2A0A0E),
                                    ],
                            ),
                            border: Border.all(
                              color: const Color(0xFFFF4B4B).withOpacity(
                                  _exitOnCenter ? 0 : 0.7),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF4B4B).withOpacity(
                                    _exitOnCenter || _confirmed
                                        ? 0.65
                                        : 0.25),
                                blurRadius: _exitOnCenter ? 24 : 10,
                                spreadRadius: _exitOnCenter ? 4 : 0,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.power_settings_new_rounded,
                                color: _exitOnCenter || _confirmed
                                    ? Colors.white
                                    : const Color(0xFFFF4B4B),
                                size: 18,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Exit',
                                style: TextStyle(
                                  color: _exitOnCenter || _confirmed
                                      ? Colors.white
                                      : const Color(0xFFFF4B4B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Hint arrows ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('💙 Stay',
                        style: TextStyle(
                            color: const Color(0xFF4DA3FF).withOpacity(0.7),
                            fontSize: 12)),
                    Text('Exit 🚪',
                        style: TextStyle(
                            color: const Color(0xFFFF4B4B).withOpacity(0.7),
                            fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed circle ring painter ───────────────────────────────────
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;
  const _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - strokeWidth;
    final step = 2 * 3.14159 / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final start = i * step;
      final sweep = step * 0.55;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start, sweep, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter o) => o.color != color;
}

// ── Orbit dots painter ───────────────────────────────────────────
class _OrbitDotsPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double radius;
  const _OrbitDotsPainter(
      {required this.progress, required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const count = 5;
    for (int i = 0; i < count; i++) {
      final angle = (progress + i / count) * 2 * 3.14159;
      final pos = Offset(
        c.dx + radius * _cos(angle),
        c.dy + radius * _sin(angle),
      );
      final opacity = 0.25 + 0.55 * ((_sin(angle * 2 + progress * 6.28) + 1) / 2);
      canvas.drawCircle(
          pos, 3.0, Paint()..color = color.withOpacity(opacity));
    }
  }

  double _cos(double a) => cos(a);
  double _sin(double a) => sin(a);

  @override
  bool shouldRepaint(_OrbitDotsPainter o) => o.progress != progress;
}
