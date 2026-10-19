import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemCalendarInfo {
  const SystemCalendarInfo({
    required this.id,
    required this.name,
    required this.accountName,
    required this.canWrite,
    required this.color,
  });

  final int id;
  final String name;
  final String accountName;
  final bool canWrite;
  final int color;

  factory SystemCalendarInfo.fromMap(Map<Object?, Object?> map) =>
      SystemCalendarInfo(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String? ?? '系统日历',
        accountName: map['accountName'] as String? ?? '',
        canWrite: map['canWrite'] == true,
        color: (map['color'] as num?)?.toInt() ?? 0xff0066ff,
      );
}

class SystemCalendarInstance {
  const SystemCalendarInstance({
    required this.eventId,
    required this.beginMillis,
    required this.endMillis,
    required this.title,
    required this.allDay,
    required this.notes,
    required this.timeZone,
  });

  final int eventId;
  final int beginMillis;
  final int endMillis;
  final String title;
  final bool allDay;
  final String notes;
  final String timeZone;

  String get stableId => 'system:$eventId:$beginMillis';

  factory SystemCalendarInstance.fromMap(Map<Object?, Object?> map) =>
      SystemCalendarInstance(
        eventId: (map['eventId'] as num).toInt(),
        beginMillis: (map['begin'] as num).toInt(),
        endMillis: (map['end'] as num).toInt(),
        title: map['title'] as String? ?? '(无标题)',
        allDay: map['allDay'] == true,
        notes: map['notes'] as String? ?? '',
        timeZone: map['timeZone'] as String? ?? '',
      );
}

class SystemCalendarReadResult {
  const SystemCalendarReadResult(this.instances, this.truncated);

  final List<SystemCalendarInstance> instances;
  final bool truncated;
}

class SystemCalendarExportItem {
  const SystemCalendarExportItem({
    required this.occurrenceKey,
    required this.title,
    required this.startMillis,
    required this.endMillis,
    required this.allDay,
    required this.timeZone,
    required this.notes,
  });

  final String occurrenceKey;
  final String title;
  final int startMillis;
  final int endMillis;
  final bool allDay;
  final String timeZone;
  final String notes;

  Map<String, Object?> toMap() => <String, Object?>{
    'key': occurrenceKey,
    'title': title,
    'start': startMillis,
    'end': endMillis,
    'allDay': allDay,
    'timeZone': timeZone,
    'notes': notes,
  };
}

class SystemCalendarService {
  SystemCalendarService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.jheyzo.fwcal/system_calendar');

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<SystemCalendarInfo>> listCalendars() async {
    _requireAndroid();
    final raw = await _channel.invokeListMethod<Object?>('listCalendars');
    return (raw ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(SystemCalendarInfo.fromMap)
        .toList(growable: false);
  }

  Future<SystemCalendarReadResult> readInstances({
    required int calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    _requireAndroid();
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'readInstances',
      <String, Object?>{
        'calendarId': calendarId,
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      },
    );
    final rows = (raw?['instances'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(SystemCalendarInstance.fromMap)
        .toList(growable: false);
    return SystemCalendarReadResult(rows, raw?['truncated'] == true);
  }

  Future<int> upsertEvents({
    required int calendarId,
    required List<SystemCalendarExportItem> events,
  }) async {
    _requireAndroid();
    if (events.length > 500) {
      throw ArgumentError('单次最多导出500个日程实例');
    }
    final result = await _channel.invokeMethod<Object?>(
      'upsertEvents',
      <String, Object?>{
        'calendarId': calendarId,
        'events': events.map((event) => event.toMap()).toList(),
      },
    );
    if (result is Map<Object?, Object?>) {
      return (result['total'] as num?)?.toInt() ?? 0;
    }
    return (result as num?)?.toInt() ?? 0;
  }

  void _requireAndroid() {
    if (!isSupported) throw UnsupportedError('系统日历导入/导出目前仅支持 Android');
  }
}
