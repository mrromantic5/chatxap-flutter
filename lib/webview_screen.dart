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

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final safeToken = token.replaceAll("'", "\'").replaceAll("\n", "");
      await _webCtrl?.evaluateJavascript(source: '''
(function() {
  try {
    var t = '$safeToken';
    var already = localStorage.getItem('cx_flutter_tok');
    if (already === t) return;
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
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => const _PremiumExitDialog(),
    );
  }
}

class _PremiumExitDialog extends StatefulWidget {
  const _PremiumExitDialog();

  @override
  State<_PremiumExitDialog> createState() => _PremiumExitDialogState();
}

class _PremiumExitDialogState extends State<_PremiumExitDialog> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isStaySelected = false;
  bool _isExitSelected = false;
  double _dragProgress = 0.0;
  
  static const double _radius = 140.0;
  static const double _buttonSize = 64.0;
  static const double _centerZoneRadius = 40.0;
  
  bool _isStayHovered = false;
  bool _isExitHovered = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOutSine,
      ),
    );
    _glowController.repeat(reverse: true);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleDragStart(Offset localPosition) {
    setState(() {
      _isDragging = true;
      _dragOffset = localPosition;
    });
  }

  void _handleDragUpdate(Offset localPosition) {
    if (!_isDragging) return;
    
    setState(() {
      _dragOffset = localPosition;
      
      final center = Offset(_radius + _buttonSize / 2, _radius + _buttonSize / 2);
      final dx = localPosition.dx - center.dx;
      final dy = localPosition.dy - center.dy;
      final distance = sqrt(dx * dx + dy * dy);
      
      _dragProgress = (1 - distance / _radius).clamp(0.0, 1.0);
      
      final startAngle = atan2(dy, dx);
      final angleDeg = startAngle * 180 / pi;
      
      if (angleDeg > -90 && angleDeg < 90) {
        _isExitSelected = _dragProgress > 0.7;
        _isStaySelected = false;
      } else {
        _isStaySelected = _dragProgress > 0.7;
        _isExitSelected = false;
      }
      
      if (_dragProgress > 0.85) {
        _triggerSelection();
      }
    });
  }

  void _handleDragEnd() {
    if (!_isDragging) return;
    
    setState(() {
      _isDragging = false;
      if (_dragProgress < 0.7) {
        _dragOffset = Offset.zero;
        _dragProgress = 0.0;
        _isStaySelected = false;
        _isExitSelected = false;
      }
    });
  }

  void _triggerSelection() {
    if (_isStaySelected) {
      Navigator.pop(context);
    } else if (_isExitSelected) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 420,
        height: 520,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1F),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: const Color(0xFF4DA3FF).withOpacity(0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4DA3FF).withOpacity(0.08),
              blurRadius: 60,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF4DA3FF).withOpacity(0.08 * _glowAnimation.value),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6],
                        center: Alignment.center,
                        radius: 0.8,
                      ),
                    ),
                  );
                },
              ),
            ),
            
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                  gradient: LinearGradient(
                    colors: [Color(0xFF4DA3FF), Color(0xFF7C5CFC), Color(0xFF4DA3FF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            
            Positioned(
              top: 40,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  const Text(
                    'Exit ChatXAP?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag a button to the center to select',
                    style: TextStyle(
                      color: const Color(0xFF9CA3AF).withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              bottom: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, child) {
                      return Container(
                        width: _radius * 2 + _buttonSize,
                        height: _radius * 2 + _buttonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF4DA3FF).withOpacity(0.2 * _glowAnimation.value),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4DA3FF).withOpacity(0.15 * _glowAnimation.value),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Stack(
                        children: List.generate(12, (index) {
                          final angle = (index / 12) * 2 * pi;
                          final x = _radius * cos(angle);
                          final y = _radius * sin(angle);
                          return Positioned(
                            left: _radius + x - 3,
                            top: _radius + y - 3,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF4DA3FF).withOpacity(0.3 * _pulseAnimation.value),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  
                  Container(
                    width: _centerZoneRadius * 2,
                    height: _centerZoneRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.03),
                      border: Border.all(
                        color: const Color(0xFF4DA3FF).withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: const Color(0xFF4DA3FF).withOpacity(0.3),
                        size: 30,
                      ),
                    ),
                  ),
                  
                  if (_dragProgress > 0.5)
                    Center(
                      child: AnimatedOpacity(
                        opacity: _dragProgress > 0.5 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _isStaySelected ? '✓ Stay' : _isExitSelected ? '✕ Exit' : '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  _buildButton(
                    position: const Offset(-1, 0),
                    label: 'Stay',
                    color: const Color(0xFF4DA3FF),
                    isSelected: _isStaySelected,
                    isHovered: _isStayHovered,
                    onDragStart: _handleDragStart,
                    onDragUpdate: _handleDragUpdate,
                    onDragEnd: _handleDragEnd,
                  ),
                  
                  _buildButton(
                    position: const Offset(1, 0),
                    label: 'Exit',
                    color: const Color(0xFFE74C3C),
                    isSelected: _isExitSelected,
                    isHovered: _isExitHovered,
                    onDragStart: _handleDragStart,
                    onDragUpdate: _handleDragUpdate,
                    onDragEnd: _handleDragEnd,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required Offset position,
    required String label,
    required Color color,
    required bool isSelected,
    required bool isHovered,
    required Function(Offset) onDragStart,
    required Function(Offset) onDragUpdate,
    required VoidCallback onDragEnd,
  }) {
    final baseX = _radius * position.dx;
    final baseY = _radius * position.dy;
    
    final dragX = _isDragging ? _dragOffset.dx - (_radius + _buttonSize / 2) : 0;
    final dragY = _isDragging ? _dragOffset.dy - (_radius + _buttonSize / 2) : 0;
    
    final currentX = _isDragging ? _radius + dragX : baseX + _radius;
    final currentY = _isDragging ? _radius + dragY : baseY + _radius;
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Positioned(
          left: currentX - _buttonSize / 2,
          top: currentY - _buttonSize / 2,
          child: GestureDetector(
            onPanStart: (details) {
              onDragStart(details.localPosition);
            },
            onPanUpdate: (details) {
              onDragUpdate(details.localPosition);
            },
            onPanEnd: (_) => onDragEnd(),
            child: MouseRegion(
              onEnter: () {
                setState(() {
                  if (label == 'Stay') {
                    _isStayHovered = true;
                    _isExitHovered = false;
                  } else {
                    _isExitHovered = true;
                    _isStayHovered = false;
                  }
                });
              },
              onExit: () {
                setState(() {
                  if (label == 'Stay') {
                    _isStayHovered = false;
                  } else {
                    _isExitHovered = false;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? color.withOpacity(0.9) : color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: isSelected ? 40 : 20,
                      spreadRadius: isSelected ? 8 : 0,
                    ),
                    if (isSelected)
                      BoxShadow(
                        color: color.withOpacity(0.6),
                        blurRadius: 60,
                        spreadRadius: 4,
                      ),
                  ],
                  gradient: isSelected ? null : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.9),
                      color.withOpacity(0.6),
                    ],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isSelected)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.2),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.6],
                          ),
                        ),
                      ),
                    
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
