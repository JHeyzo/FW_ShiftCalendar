package com.jheyzo.fwcal

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.jheyzo.fwcal/system_calendar"
    private val permissionRequestCode = 48172
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingOperation: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        val operation: () -> Unit = {
            when (call.method) {
                "listCalendars" -> listCalendars(result)
                "readInstances" -> readInstances(call, result)
                "upsertEvents" -> upsertEvents(call, result)
                else -> result.notImplemented()
            }
        }
        if (call.method !in setOf("listCalendars", "readInstances", "upsertEvents")) {
            result.notImplemented()
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "已有日历权限请求正在处理，请稍后重试", null)
            return
        }
        val required = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
        val missing = required.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            operation()
        } else {
            pendingPermissionResult = result
            pendingOperation = operation
            requestPermissions(missing.toTypedArray(), permissionRequestCode)
        }
    }

    @Deprecated("Deprecated in Android API; retained for FlutterActivity compatibility")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val result = pendingPermissionResult ?: return
        val operation = pendingOperation
        pendingPermissionResult = null
        pendingOperation = null
        val readGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        val writeGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
        if (!readGranted || !writeGranted) {
            result.error("PERMISSION_DENIED", "未授予读取及写入系统日历权限，未执行操作。请在系统设置中允许日历权限后重试。", null)
        } else if (operation == null) {
            result.error("PERMISSION_DENIED", "日历权限请求未能继续，请重试。", null)
        } else {
            operation.invoke()
        }
    }

    private fun runIo(result: MethodChannel.Result, task: () -> Any?) {
        io.execute {
            try {
                val value = task()
                mainHandler.post { result.success(value) }
            } catch (error: SecurityException) {
                mainHandler.post {
                    result.error("PERMISSION_DENIED", "系统拒绝访问日历：${error.message ?: "权限不足"}", null)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("CALENDAR_ERROR", error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun listCalendars(result: MethodChannel.Result) = runIo(result) {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.CALENDAR_COLOR
        )
        val calendars = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME} COLLATE NOCASE ASC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accountCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
            val accessCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
            val colorCol = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_COLOR)
            while (cursor.moveToNext()) {
                val access = cursor.getInt(accessCol)
                calendars.add(mapOf(
                    "id" to cursor.getLong(idCol),
                    "name" to cursor.getString(nameCol).orEmpty(),
                    "accountName" to cursor.getString(accountCol).orEmpty(),
                    "canWrite" to (access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR),
                    "color" to cursor.getInt(colorCol)
                ))
            }
        }
        calendars
    }

    private fun readInstances(call: MethodCall, result: MethodChannel.Result) {
        val calendarId = call.argument<Number>("calendarId")?.toLong()
        val from = call.argument<Number>("from")?.toLong()
        val to = call.argument<Number>("to")?.toLong()
        if (calendarId == null || from == null || to == null || to <= from) {
            result.error("INVALID_ARGUMENT", "系统日历或日期范围无效", null)
            return
        }
        runIo(result) {
            val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
                .appendPath(from.toString()).appendPath(to.toString()).build()
            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.DESCRIPTION,
                CalendarContract.Instances.EVENT_TIMEZONE,
                CalendarContract.Instances.CALENDAR_ID
            )
            val rows = mutableListOf<Map<String, Any?>>()
            contentResolver.query(
                uri,
                projection,
                "${CalendarContract.Instances.CALENDAR_ID} = ? AND ${CalendarContract.Instances.BEGIN} < ? AND (${CalendarContract.Instances.END} > ? OR (${CalendarContract.Instances.BEGIN} = ${CalendarContract.Instances.END} AND ${CalendarContract.Instances.BEGIN} >= ?))",
                arrayOf(calendarId.toString(), to.toString(), from.toString(), from.toString()),
                "${CalendarContract.Instances.BEGIN} ASC"
            )?.use { cursor ->
                val eventId = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
                val begin = cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
                val end = cursor.getColumnIndexOrThrow(CalendarContract.Instances.END)
                val title = cursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
                val allDay = cursor.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
                val description = cursor.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION)
                val timezone = cursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_TIMEZONE)
                while (cursor.moveToNext() && rows.size < 501) {
                    rows.add(mapOf(
                        "eventId" to cursor.getLong(eventId),
                        "begin" to cursor.getLong(begin),
                        "end" to cursor.getLong(end),
                        "title" to cursor.getString(title).orEmpty(),
                        "allDay" to (cursor.getInt(allDay) != 0),
                        "notes" to cursor.getString(description).orEmpty(),
                        "timeZone" to cursor.getString(timezone).orEmpty()
                    ))
                }
            }
            val truncated = rows.size > 500
            mapOf("instances" to rows.take(500), "truncated" to truncated)
        }
    }

    private fun upsertEvents(call: MethodCall, result: MethodChannel.Result) {
        val calendarId = call.argument<Number>("calendarId")?.toLong()
        val events = call.argument<List<Map<String, Any?>>> ("events")
        if (calendarId == null || events == null || events.size > 500) {
            result.error("INVALID_ARGUMENT", "系统日历或导出数量无效（单次最多500项）", null)
            return
        }
        runIo(result) {
            val writable = isWritableCalendar(calendarId)
            if (!writable) throw IllegalArgumentException("所选系统日历不可写，请选择有写入权限的日历")
            var completed = 0
            var created = 0
            var updated = 0
            val prefs = getSharedPreferences("fwcal_system_calendar_exports", MODE_PRIVATE)
            try {
                for (event in events) {
                    val key = event["key"] as? String ?: throw IllegalArgumentException("导出项缺少稳定标识")
                    val start = (event["start"] as? Number)?.toLong() ?: throw IllegalArgumentException("开始时间无效")
                    val end = (event["end"] as? Number)?.toLong() ?: throw IllegalArgumentException("结束时间无效")
                    val allDay = event["allDay"] as? Boolean ?: false
                    val title = event["title"] as? String ?: "(无标题)"
                    val timezone = (event["timeZone"] as? String).orEmpty().ifBlank { java.util.TimeZone.getDefault().id }
                    val originalNotes = (event["notes"] as? String).orEmpty()
                    val marker = "[风味日历导出 · $key]"
                    val description = if (originalNotes.isBlank()) marker else "$originalNotes\n\n$marker"
                    val values = ContentValues().apply {
                        put(CalendarContract.Events.CALENDAR_ID, calendarId)
                        put(CalendarContract.Events.TITLE, title)
                        put(CalendarContract.Events.DTSTART, start)
                        put(CalendarContract.Events.DTEND, end)
                        put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
                        put(CalendarContract.Events.EVENT_TIMEZONE, if (allDay) "UTC" else timezone)
                        put(CalendarContract.Events.DESCRIPTION, description)
                        put(CalendarContract.Events.HAS_ALARM, 0)
                    }
                    val mapKey = "${calendarId}_$key"
                    var existingId = prefs.getLong(mapKey, -1L)
                    if (existingId < 0L) {
                        existingId = findExportedEvent(calendarId, marker)
                    }
                    var didUpdate = false
                    if (existingId >= 0L) {
                        val existingUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, existingId)
                        val changed = contentResolver.update(
                            existingUri,
                            values,
                            "${CalendarContract.Events.CALENDAR_ID} = ?",
                            arrayOf(calendarId.toString())
                        )
                        didUpdate = changed > 0
                    }
                    if (!didUpdate) {
                        val inserted = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                            ?: throw IllegalStateException("系统日历未能创建导出项：$title")
                        val newId = ContentUris.parseId(inserted)
                        if (!prefs.edit().putLong(mapKey, newId).commit()) {
                            throw IllegalStateException("导出项已创建，但本机映射保存失败；重试时将通过来源标记恢复，避免重复创建")
                        }
                        created++
                    } else {
                        prefs.edit().putLong(mapKey, existingId).commit()
                        updated++
                    }
                    completed++
                }
            } catch (error: Exception) {
                throw IllegalStateException("导出中断：已成功处理 $completed 项（新增 $created，更新 $updated），原因：${error.message}", error)
            }
            mapOf("total" to completed, "created" to created, "updated" to updated)
        }
    }

    private fun findExportedEvent(calendarId: Long, marker: String): Long {
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID, CalendarContract.Events.DESCRIPTION),
            "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} = 0 AND ${CalendarContract.Events.DESCRIPTION} LIKE ?",
            arrayOf(calendarId.toString(), "%$marker%"),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1).orEmpty().contains(marker)) return cursor.getLong(0)
            }
        }
        return -1L
    }

    private fun isWritableCalendar(calendarId: Long): Boolean {
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            "${CalendarContract.Calendars._ID} = ?",
            arrayOf(calendarId.toString()),
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return false
            return cursor.getInt(0) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
        }
        return false
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }
}
