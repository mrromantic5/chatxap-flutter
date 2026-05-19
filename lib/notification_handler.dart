import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static InAppWebViewController? _webCtrl;

  static const String _channelId = 'chatxap_msg';
  static const String _channelName = 'ChatXAP Messages';
  static const String _channelIdCall = 'chatxap_call';
  static const String _channelNameCall = 'ChatXAP Calls';
  static const String _replyActionId = 'cx_reply';
  static const String _readActionId = 'cx_read';

  static void setWebController(InAppWebViewController ctrl) {
    _webCtrl = ctrl;
  }

  // ── Initialize channels and permissions ─────────────────────────
  static Future<void> initialize() async {
    // Message channel — high priority
    const msgChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'ChatXAP message notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    // Call channel — max priority for voice/video calls
    const callChannel = AndroidNotificationChannel(
      _channelIdCall,
      _channelNameCall,
      description: 'ChatXAP call notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(msgChannel);
    await androidImpl?.createNotificationChannel(callChannel);

    // Init settings
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    // Request FCM permission
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // We show our own foreground notifications — disable default system ones
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  // ── Show notification ────────────────────────────────────────────
  static Future<void> showNotification(RemoteMessage message) async {
    final n = message.notification;
    final d = message.data;

    final String title = n?.title ?? d['title'] ?? 'ChatXAP';
    final String body = n?.body ?? d['body'] ?? '';
    final String type = d['type'] ?? 'message';
    final String senderName = d['sender_name'] ?? title;
    final String convId =
        d['conversation_id'] ?? d['group_id'] ?? d['channel_id'] ?? '';

    // Determine notification ID — same conversation = same notif ID
    // so messages from same person stack up like WhatsApp
    final int notifId = convId.isNotEmpty
        ? convId.hashCode.abs() % 99998
        : DateTime.now().millisecondsSinceEpoch % 99998;

    final bool isCall = type == 'incoming_call' || type == 'voice_call';

    if (isCall) {
      await _showCallNotification(notifId, title, body, d);
    } else {
      await _showMessageNotification(
          notifId, title, body, type, senderName, convId, d);
    }
  }

  // ── Message notification (WhatsApp style) ───────────────────────
  static Future<void> _showMessageNotification(
    int notifId,
    String title,
    String body,
    String type,
    String senderName,
    String convId,
    Map<String, dynamic> d,
  ) async {
    final person = Person(
      name: senderName,
      important: true,
      bot: false,
    );

    // Build messaging style — enables stacking like WhatsApp
    final msgStyle = MessagingStyleInformation(
      person,
      conversationTitle: _conversationTitle(type, d),
      groupConversation:
          type == 'public_message' || type == 'group_message',
      messages: [
        Message(body, DateTime.now(), person),
      ],
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: msgStyle,
      color: const Color(0xFF4DA3FF),
      enableLights: true,
      ledColor: const Color(0xFF4DA3FF),
      ledOnMs: 500,
      ledOffMs: 1000,
      largeIcon:
          const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      enableVibration: true,
      playSound: true,
      autoCancel: true,
      ongoing: false,
      // Inline Reply action — exactly like WhatsApp
      actions: [
        AndroidNotificationAction(
          _replyActionId,
          'Reply',
          inputs: [
            const AndroidNotificationActionInput(
              label: 'Type a reply…',
              allowFreeFormInput: true,
            ),
          ],
          showsUserInterface: false,
          cancelNotification: false,
          icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
        const AndroidNotificationAction(
          _readActionId,
          '✓ Mark Read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(
      notifId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: '$type|$convId',
    );
  }

  // ── Call notification ────────────────────────────────────────────
  static Future<void> _showCallNotification(
    int notifId,
    String title,
    String body,
    Map<String, dynamic> d,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      _channelIdCall,
      _channelNameCall,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      color: const Color(0xFF4DA3FF),
      largeIcon:
          const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: [
        const AndroidNotificationAction(
          'cx_accept_call',
          '📞 Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'cx_decline_call',
          '❌ Decline',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(
      notifId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: 'incoming_call|${d['caller_id'] ?? ''}',
    );
  }

  static String? _conversationTitle(
      String type, Map<String, dynamic> d) {
    if (type == 'public_message') return 'Global Chat';
    if (type == 'group_message') return d['group_name'] as String?;
    if (type == 'channel_message') return d['channel_name'] as String?;
    return null;
  }

  // ── Foreground notification tap / action ─────────────────────────
  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final actionId = response.actionId ?? '';

    if (actionId == _replyActionId) {
      final text = response.input?.trim() ?? '';
      if (text.isNotEmpty) _sendReply(text, payload);
      return;
    }

    if (actionId == _readActionId) {
      // Just cancel the notification — already done by cancelNotification: true
      return;
    }

    if (actionId == 'cx_accept_call') {
      _navigateFromPayload(payload);
      return;
    }

    // Normal tap — navigate to the right chat
    _navigateFromPayload(payload);
  }

  // ── Background notification action ──────────────────────────────
  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) {
    final actionId = response.actionId ?? '';
    if (actionId == _replyActionId) {
      final text = response.input?.trim() ?? '';
      if (text.isNotEmpty) {
        _sendReply(text, response.payload ?? '');
      }
    }
  }

  // ── Send inline reply ────────────────────────────────────────────
  static Future<void> _sendReply(String text, String payload) async {
    final parts = payload.split('|');
    final type = parts.isNotEmpty ? parts[0] : '';
    final convId = parts.length > 1 ? parts[1] : '';

    if (_webCtrl != null) {
      // App is open — inject reply into the active WebView page
      final safe = text
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('"', '\\"')
          .replaceAll('\n', ' ');

      await _webCtrl!.evaluateJavascript(source: '''
(function() {
  try {
    var inp = document.getElementById('ti') ||
              document.getElementById('mi') ||
              document.querySelector('textarea[id]') ||
              document.querySelector('input[type="text"]');
    if (!inp) return;
    inp.focus();
    inp.value = '$safe';
    inp.dispatchEvent(new Event('input', {bubbles:true}));
    inp.dispatchEvent(new Event('change', {bubbles:true}));
    // Try clicking the send button
    var btn = document.getElementById('send') ||
              document.querySelector('.send-btn') ||
              document.querySelector('[onclick*="sendMsg"]') ||
              document.querySelector('[onclick*="sendMessage"]') ||
              document.querySelector('button[type="submit"]');
    if (btn) { btn.click(); return; }
    // Fallback: dispatch Enter key
    inp.dispatchEvent(new KeyboardEvent('keydown',
      {key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));
  } catch(e) { console.warn('CX reply inject:', e); }
})();
''');
    } else {
      // App is closed — send directly to PHP backend
      await _postReplyDirect(text, type, convId);
    }
  }

  // ── Direct HTTP post when app is closed ─────────────────────────
  static Future<void> _postReplyDirect(
      String text, String type, String convId) async {
    try {
      final String endpoint;
      final String bodyJson;
      final escaped =
          text.replaceAll('"', '\\"').replaceAll('\n', '\\n');

      if (type == 'private_message' || type == 'dm') {
        endpoint =
            'https://c.x.t-lyfe.com.ng/backend/dm_send.php';
        bodyJson =
            '{"conversation_id":"$convId","message":"$escaped"}';
      } else if (type == 'group_message') {
        endpoint =
            'https://c.x.t-lyfe.com.ng/backend/group_message_send.php';
        bodyJson =
            '{"group_id":"$convId","message":"$escaped"}';
      } else {
        // public chat
        endpoint =
            'https://c.x.t-lyfe.com.ng/backend/chat_send.php';
        bodyJson = '{"message":"$escaped"}';
      }

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request =
          await client.postUrl(Uri.parse(endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set('X-ChatXAP-App', '1');
      request.write(bodyJson);
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {
      // Silent fail — user will see message unsent when they open app
    }
  }

  // ── Navigate WebView to correct page ────────────────────────────
  static void _navigateFromPayload(String payload) {
    if (_webCtrl == null) return;
    final parts = payload.split('|');
    final type = parts.isNotEmpty ? parts[0] : '';
    final id = parts.length > 1 ? parts[1] : '';
    const base = 'https://c.x.t-lyfe.com.ng';

    String url = '$base/rc.html';
    if ((type == 'private_message' || type == 'dm') && id.isNotEmpty) {
      url = '$base/dm.html?conversation_id=$id';
    } else if (type == 'public_message') {
      url = '$base/chat.html';
    } else if (type == 'group_message' && id.isNotEmpty) {
      url = '$base/group.html?group_id=$id';
    } else if (type == 'channel_message' && id.isNotEmpty) {
      url = '$base/channel.html?channel_id=$id';
    } else if (type == 'incoming_call' && id.isNotEmpty) {
      url = '$base/voice_call.html?caller=$id';
    }

    _webCtrl!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }
}
