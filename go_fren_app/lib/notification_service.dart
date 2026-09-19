import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'gofren_matches';
  static const String channelName = 'Go Fren Matches';
  static const String channelDescription =
      'Notifications for new Go Fren matches.';

  static const String chatChannelId = 'gofren_messages';
  static const String chatChannelName = 'Go Fren Messages';
  static const String chatChannelDescription =
      'Notifications for new Go Fren messages.';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await plugin.initialize(
      settings: initializationSettings,
    );

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    const chatChannel = AndroidNotificationChannel(
      chatChannelId,
      chatChannelName,
      description: chatChannelDescription,
      importance: Importance.high,
    );

    final androidPlugin =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(chatChannel);

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();

    final androidPlugin =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final result = await androidPlugin?.requestNotificationsPermission();

    return result != false;
  }

  Future<bool> areNotificationsEnabled() async {
    await initialize();

    final androidPlugin =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final result = await androidPlugin?.areNotificationsEnabled();

    return result ?? true;
  }

  Future<void> showMatchNotification({
    required String name,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    final notificationId =
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    await plugin.show(
      id: notificationId,
      title: "It's a Match! 🎉",
      body: 'You matched with $name.',
      notificationDetails: details,
      payload: 'match',
    );
  }

  Future<void> showMessageNotification({
    required String name,
    required String message,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      chatChannelId,
      chatChannelName,
      channelDescription: chatChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    final notificationId =
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);

    final displayMessage = message.startsWith('image:')
        ? '📷 Sent a photo'
        : message;

    await plugin.show(
      id: notificationId,
      title: 'New message from $name',
      body: displayMessage,
      notificationDetails: details,
      payload: 'message',
    );
  }

  Future<void> showTestNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await plugin.show(
      id: 999999,
      title: 'Go Fren Notifications',
      body: 'Notifications are now enabled. 🎉',
      notificationDetails: details,
      payload: 'notification-settings-test',
    );
  }
}
