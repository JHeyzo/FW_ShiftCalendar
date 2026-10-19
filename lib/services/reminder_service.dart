import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/app_store.dart';

/// Synchronizes calendar reminders to Android local notifications.
///
/// Call [initialize] during app startup (it does not request permission), then
/// call [requestPermission] only from an explicit user action. [synchronize]
/// replaces the managed notification set only when its content has changed.
class ReminderService {
  ReminderService({this.onSelectDate});

  final void Function(DateTime date)? onSelectDate;

  static const int _maxScheduledReminders = 64;
  static const Duration _schedulingHorizon = Duration(days: 30);
  static const String _channelId = 'fwcal_calendar_reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initialization;
  Future<void> _syncQueue = Future<void>.value();
  bool _initialized = false;
  bool _supported = false;
  String? _statusMessage;
  String? _lastAppliedSignature;

  String? get statusMessage => _statusMessage;

  /// Initializes Android notifications without prompting for permission.
  Future<void> initialize() {
    if (_initialization != null) return _initialization!;
    _initialization = _initializeAndroid();
    return _initialization!;
  }

  Future<void> _initializeAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _statusMessage = '日历提醒目前仅支持 Android。';
      return;
    }
    _supported = true;
    try {
      tz_data.initializeTimeZones();
      await _refreshLocalTimezone();
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _openPayload(response.payload),
      );
      if (initialized != true) {
        _statusMessage = '通知插件未能完成初始化。';
        return;
      }
      _initialized = true;
      _statusMessage = null;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openPayload(launch?.notificationResponse?.payload);
      }
    } catch (error) {
      _statusMessage = '通知初始化失败：$error';
    }
  }

  /// Requests Android 13+ notification permission after an explicit user tap.
  /// Older Android versions do not show a runtime permission prompt.
  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _statusMessage = '日历提醒目前仅支持 Android。';
      return false;
    }
    await initialize();
    if (!_initialized) return false;
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      final result = granted ?? false;
      _statusMessage = result ? '通知权限已允许。' : '通知权限未开启；请在系统设置中允许本应用发送通知。';
      return result;
    } catch (error) {
      _statusMessage = '请求通知权限失败：$error';
      return false;
    }
  }

  /// Replaces the scheduled set when its effective contents have changed.
  ///
  /// Hidden calendars are intentionally included (`visibleOnly: false`):
  /// visibility affects the calendar UI, not a user's reminder subscription.
  /// Repeated calls caused by date selection are deduplicated by a content
  /// signature, and all actual replacements are serialized to avoid races.
  Future<void> synchronize(AppStore store) async {
    await initialize();
    if (!_supported || !_initialized) return;

    final operation = _syncQueue.then((_) => _synchronizeSerial(store));
    // Keep the queue usable even if an unexpected error escapes the guarded
    // implementation; _synchronizeSerial reports expected/plugin errors.
    _syncQueue = operation.catchError((Object _) {});
    await operation;
  }

  Future<void> _synchronizeSerial(AppStore store) async {
    try {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      if (enabled != true) {
        _lastAppliedSignature = null;
        _statusMessage = '通知权限未开启；请在设置中开启通知后刷新提醒。';
        return;
      }
      await _refreshLocalTimezone();
      final now = DateTime.now();
      final horizonEnd = now.add(_schedulingHorizon);
      final reminders = store.entries
          .map((entry) => entry.reminderMinutes ?? 0)
          .where((minutes) => minutes > 0)
          .toList();
      final maxLeadMinutes = reminders.isEmpty
          ? 0
          : reminders.reduce((a, b) => a > b ? a : b);
      var occurrenceEnd = horizonEnd.add(Duration(minutes: maxLeadMinutes));
      // AppStore dates are bounded to years 1900–2100. Avoid date overflow and
      // do not query occurrences beyond its supported range.
      final maximumOccurrenceEnd = DateTime(2101);
      if (occurrenceEnd.isAfter(maximumOccurrenceEnd)) {
        occurrenceEnd = maximumOccurrenceEnd;
      }

      final occurrences = store.occurrences(
        now,
        occurrenceEnd,
        visibleOnly: false,
      );
      final candidates = <_ReminderCandidate>[];
      for (final occurrence in occurrences) {
        final entry = occurrence.entry;
        final minutes = entry.reminderMinutes;
        if (minutes == null || minutes < 0) continue;
        if (entry.kind == EntryKind.todo && occurrence.done) continue;

        final scheduledAt = occurrence.start.subtract(
          Duration(minutes: minutes),
        );
        if (!scheduledAt.isAfter(now) || scheduledAt.isAfter(horizonEnd)) {
          continue;
        }
        candidates.add(
          _ReminderCandidate(
            entry: entry,
            occurrenceStart: occurrence.start,
            scheduledAt: scheduledAt,
            payload: dayKey(occurrence.start),
          ),
        );
      }
      candidates.sort((a, b) {
        final byTime = a.scheduledAt.compareTo(b.scheduledAt);
        if (byTime != 0) return byTime;
        final byTitle = a.entry.title.compareTo(b.entry.title);
        if (byTitle != 0) return byTitle;
        final byEntry = a.entry.id.compareTo(b.entry.id);
        return byEntry != 0 ? byEntry : a.payload.compareTo(b.payload);
      });
      if (candidates.length > _maxScheduledReminders) {
        candidates.removeRange(_maxScheduledReminders, candidates.length);
      }

      final usedIds = <int>{};
      final planned = <_PlannedReminder>[];
      for (final candidate in candidates) {
        final id = _notificationId(
          '${candidate.entry.id}\u0000${candidate.payload}',
          usedIds,
        );
        planned.add(_PlannedReminder(candidate, id));
      }
      final signature = jsonEncode(<Object?>[
        tz.local.name,
        for (final reminder in planned)
          <Object?>[
            reminder.id,
            reminder.candidate.entry.title,
            reminder.candidate.entry.kind.name,
            reminder.candidate.scheduledAt.toIso8601String(),
            reminder.candidate.payload,
          ],
      ]);
      if (signature == _lastAppliedSignature) return;

      // Replacement is deliberately all-or-rebuild: on any failure the cache
      // remains unset so the next synchronization can retry the full snapshot.
      await _plugin.cancelAll();
      for (final reminder in planned) {
        final candidate = reminder.candidate;
        final kindLabel = candidate.entry.kind == EntryKind.todo ? '待办' : '日程';
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: candidate.entry.title,
          body: '$kindLabel提醒',
          scheduledDate: tz.TZDateTime.from(candidate.scheduledAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              '日历提醒',
              channelDescription: '日程和待办的提前提醒',
              importance: Importance.high,
              priority: Priority.high,
              icon: 'ic_notification',
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: candidate.payload,
        );
      }
      _lastAppliedSignature = signature;
      _statusMessage = '已同步 ${planned.length} 条提醒（未来30天内，系统可能延迟投递）。';
    } catch (error) {
      _statusMessage = '同步日历提醒失败：$error';
    }
  }

  Future<void> _refreshLocalTimezone() async {
    final localZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localZone.identifier));
  }

  void _openPayload(String? payload) {
    final date = payload == null ? null : DateTime.tryParse(payload);
    if (date != null && date.year >= 1900 && date.year <= 2100) {
      onSelectDate?.call(dateOnly(date));
    }
  }

  int _notificationId(String key, Set<int> usedIds) {
    // FNV-1a over UTF-8 keeps notification ids stable across app launches.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    var id = hash & 0x7fffffff;
    while (!usedIds.add(id)) {
      id = (id + 1) & 0x7fffffff;
    }
    return id;
  }
}

class _ReminderCandidate {
  const _ReminderCandidate({
    required this.entry,
    required this.occurrenceStart,
    required this.scheduledAt,
    required this.payload,
  });

  final CalendarEntry entry;
  final DateTime occurrenceStart;
  final DateTime scheduledAt;
  final String payload;
}

class _PlannedReminder {
  const _PlannedReminder(this.candidate, this.id);

  final _ReminderCandidate candidate;
  final int id;
}
