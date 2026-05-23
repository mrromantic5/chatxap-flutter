import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'badge_service.dart';

class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static InAppWebViewController? _webCtrl;

  // Tracks which conversation is currently open so we can suppress
  // duplicate notifications when user is already viewing that chat
  static String? _activeConvId;

  // ── Channel IDs ─────────────────────────────────────────────────
  static const _chMsg     = 'chatxap_msg';
  static const _chDm      = 'chatxap_dm';
  static const _chGroup   = 'chatxap_group';
  static const _chMention = 'chatxap_mention';
  static const _chCall    = 'chatxap_call';
  static const _chSystem  = 'chatxap_system';

  static const _replyActionId = 'cx_reply';
  static const _readActionId  = 'cx_read';

  static void setWebController(InAppWebViewController ctrl) {
    _webCtrl = ctrl;
  }

  static void setActiveConversation(String? convId) {
    _activeConvId = convId;
  }

  // ── Initialize all notification channels ────────────────────────
  static Future<void> initialize() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Create one channel per notification type — user can manage each
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chDm, 'Direct Messages',
        description: 'Private message notifications',
        importance: Importance.max, enableVibration: true,
        playSound: true, showBadge: true));

    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chMsg, 'Global Chat',
        description: 'Public chat notifications',
        importance: Importance.high, enableVibration: true,
        playSound: true, showBadge: true));

    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chGroup, 'Groups & Channels',
        description: 'Group and channel message notifications',
        importance: Importance.high, enableVibration: true,
        playSound: true, showBadge: true));

    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chMention, 'Mentions',
        description: 'When someone mentions you',
        importance: Importance.max, enableVibration: true,
        playSound: true, showBadge: true));

    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chCall, 'Calls',
        description: 'Incoming call notifications',
        importance: Importance.max, enableVibration: true,
        playSound: true, showBadge: false));

    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _chSystem, 'System',
        description: 'App updates and system alerts',
        importance: Importance.low, enableVibration: false,
        playSound: false, showBadge: false));

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false, badge: true, sound: false,
    );
  }

  // ── Main show notification entry point ───────────────────────────
  static Future<void> showNotification(RemoteMessage message) async {
    final n = message.notification;
    final d = message.data;

    final String title   = n?.title ?? d['title'] ?? 'ChatXAP';
    final String body    = n?.body  ?? d['body']  ?? '';
    final String type    = d['type'] ?? 'message';
    final String convId  = d['conversation_id'] ?? d['group_id'] ??
                           d['channel_id'] ?? '';
    final String senderName = (d['sender_name'] ?? '').isNotEmpty
        ? d['sender_name']! : title;

    // ── Smart suppression: skip if this chat is open ───────────────
    if (AppSettings.notifSuppress &&
        convId.isNotEmpty &&
        convId == _activeConvId) {
      return;
    }

    // ── Notification ID — same conv = same ID (stacks like WhatsApp)
    final int notifId = convId.isNotEmpty
        ? convId.hashCode.abs() % 99998
        : DateTime.now().millisecondsSinceEpoch % 99998;

    // ── Message preview setting ─────────────────────────────────────
    final String displayBody = AppSettings.messagePreview
        ? body : 'New message';

    // ── Haptic on notification receive ──────────────────────────────
    if (AppSettings.hapticFeedback) {
      try { HapticFeedback.lightImpact(); } catch (_) {}
    }

    // ── Increment badge ─────────────────────────────────────────────
    await BadgeService.increment();

    final bool isCall = type == 'incoming_call' || type == 'voice_call';

    if (isCall) {
      await _showCallNotification(notifId, title, displayBody, d);
    } else {
      await _showMessageNotification(
          notifId, title, displayBody, type, senderName, convId, d);
    }
  }

  // ── Message notification — WhatsApp style ───────────────────────
  static Future<void> _showMessageNotification(
    int notifId, String title, String body,
    String type, String senderName, String convId,
    Map<String, dynamic> d,
  ) async {
    // Pick correct channel per type
    final channelId = (type == 'private_message' || type == 'dm')
        ? _chDm
        : (type == 'group_message' || type == 'channel_message')
            ? _chGroup
            : _chMsg;

    final channelName = (type == 'private_message' || type == 'dm')
        ? 'Direct Messages'
        : (type == 'group_message' || type == 'channel_message')
            ? 'Groups & Channels'
            : 'Global Chat';

    final person = Person(name: senderName, important: true, bot: false);

    final msgStyle = MessagingStyleInformation(
      person,
      conversationTitle: _conversationTitle(type, d),
      groupConversation: type == 'public_message' || type == 'group_message',
      messages: [Message(body, DateTime.now(), person)],
    );

    final androidDetails = AndroidNotificationDetails(
      channelId, channelName,
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: msgStyle,
      color: const Color(0xFF4DA3FF),
      enableLights: true,
      ledColor: const Color(0xFF4DA3FF),
      ledOnMs: 500, ledOffMs: 1000,
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      enableVibration: AppSettings.hapticFeedback,
      playSound: true,
      autoCancel: true,
      ongoing: false,
      actions: [
        AndroidNotificationAction(
          _replyActionId, 'Reply',
          inputs: [const AndroidNotificationActionInput(
            label: 'Type a reply…', allowFreeFormInput: true)],
          showsUserInterface: false,
          cancelNotification: false,
          icon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
        const AndroidNotificationAction(
          _readActionId, '✓ Mark Read',
          showsUserInterface: false, cancelNotification: true,
        ),
      ],
    );

    await _plugin.show(notifId, title, body,
        NotificationDetails(android: androidDetails),
        payload: '$type|$convId');
  }

  // ── Call notification ────────────────────────────────────────────
  static Future<void> _showCallNotification(
    int notifId, String title, String body, Map<String, dynamic> d,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      _chCall, 'Calls',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      color: const Color(0xFF4DA3FF),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: [
        const AndroidNotificationAction('cx_accept_call', '📞 Accept',
            showsUserInterface: true, cancelNotification: true),
        const AndroidNotificationAction('cx_decline_call', '❌ Decline',
            showsUserInterface: false, cancelNotification: true),
      ],
    );

    await _plugin.show(notifId, title, body,
        NotificationDetails(android: androidDetails),
        payload: 'incoming_call|${d['caller_id'] ?? ''}');
  }

  static String? _conversationTitle(String type, Map<String, dynamic> d) {
    if (type == 'public_message')  return 'Global Chat';
    if (type == 'group_message')   return d['group_name'] as String?;
    if (type == 'channel_message') return d['channel_name'] as String?;
    return null;
  }

  // ── Notification response handlers ──────────────────────────────
  static void _onNotificationResponse(NotificationResponse r) {
    final payload  = r.payload ?? '';
    final actionId = r.actionId ?? '';

    if (actionId == _replyActionId) {
      final text = r.input?.trim() ?? '';
      if (text.isNotEmpty) _sendReply(text, payload);
      return;
    }
    if (actionId == _readActionId)    return;
    if (actionId == 'cx_accept_call') { _navigateFromPayload(payload); return; }
    if (actionId == 'cx_decline_call') return;

    // Clear badge when user taps notification
    BadgeService.clear();
    _navigateFromPayload(payload);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse r) {
    if (r.actionId == _replyActionId) {
      final text = r.input?.trim() ?? '';
      if (text.isNotEmpty) _sendReply(text, r.payload ?? '');
    }
  }

  // ── Send inline reply ────────────────────────────────────────────
  static Future<void> _sendReply(String text, String payload) async {
    final parts  = payload.split('|');
    final type   = parts.isNotEmpty ? parts[0] : '';
    final convId = parts.length > 1 ? parts[1] : '';
    await _postReplyDirect(text, type, convId);
  }

  // ── Direct HTTP reply with session cookie ────────────────────────
  static Future<void> _postReplyDirect(
      String text, String type, String convId) async {
    try {
      final escaped = text
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"')
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '');

      final String endpoint;
      final String bodyJson;

      if (type == 'private_message' || type == 'dm') {
        endpoint = 'https://c.x.t-lyfe.com.ng/backend/dm_send.php';
        bodyJson = '{"conversation_id":"$convId","message":"$escaped"}';
      } else if (type == 'group_message') {
        endpoint = 'https://c.x.t-lyfe.com.ng/backend/group_message_send.php';
        bodyJson = '{"group_id":"$convId","message":"$escaped"}';
      } else {
        endpoint = 'https://c.x.t-lyfe.com.ng/backend/chat_send.php';
        bodyJson = '{"message":"$escaped"}';
      }

      final prefs  = await SharedPreferences.getInstance();
      final cookie = prefs.getString('session_cookie') ?? '';

      final client  = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set('X-ChatXAP-App', '1');
      if (cookie.isNotEmpty) request.headers.set('Cookie', cookie);
      request.write(bodyJson);
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {}
  }

  // ── Navigate WebView to correct page ────────────────────────────
  static void _navigateFromPayload(String payload) {
    if (_webCtrl == null) return;
    final parts = payload.split('|');
    final type  = parts.isNotEmpty ? parts[0] : '';
    final id    = parts.length > 1 ? parts[1] : '';
    const base  = 'https://c.x.t-lyfe.com.ng';

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
