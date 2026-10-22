// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn alarm_method(signature string, body string) string {
	if signature.contains('static synchronized ') {
		// DEX only honors ACC_SYNCHRONIZED for native methods. Protect the
		// shared map explicitly; v6/v7 are reserved in these three methods.
		guarded := body.replace('return-void', 'monitor-exit v6\nreturn-void').replace('return v0', 'monitor-exit v6\nreturn v0')
		return '.method ' + signature.replace('synchronized ', '') + '\n.locals 8\nconst-class v6, Landroid/app/AlarmManager;\nmonitor-enter v6\n:vinix_lock_start\n' + guarded + '\n:vinix_lock_end\n.catchall {:vinix_lock_start .. :vinix_lock_end} :vinix_lock_failed\n:vinix_lock_failed\nmove-exception v7\nmonitor-exit v6\nthrow v7\n.end method\n'
	}
	return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

// Process-lifetime alarms use Handler queues. There is no suspend/wakeup or
// battery accounting backend; a windowed alarm may fire at the window start.
fn framework_alarm(smali string) ! {
	owner := 'Landroid/app/AlarmManager;'
	task := 'Landroid/app/VinixAlarmTask;'
	map_type := 'Ljava/util/IdentityHashMap;'
	mut text := '.class public ' + owner + '\n.super Ljava/lang/Object;\n.field private static tasks:' + map_type + '\n'
	for index, name in ['RTC_WAKEUP', 'RTC', 'ELAPSED_REALTIME_WAKEUP', 'ELAPSED_REALTIME'] {
		text += '.field public static final ' + name + ':I = ' + index.str() + '\n'
	}
	text += alarm_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		alarm_method('static constructor <clinit>()V', 'new-instance v0, ' + map_type + '\ninvoke-direct {v0}, ' + map_type + '-><init>()V\nsput-object v0, ' + owner + '->tasks:' + map_type + '\nreturn-void') +
		alarm_method('public canScheduleExactAlarms()Z', 'const/4 v0, 1\nreturn v0')
	// Keep every overload on the same scheduling and cancellation path.
	for name in ['set', 'setExact', 'setAndAllowWhileIdle', 'setExactAndAllowWhileIdle'] {
		text += alarm_method('public ' + name + '(IJLandroid/app/PendingIntent;)V', alarm_forward('p1', 'p2', '', 'p4', ''))
	}
	for name in ['setRepeating', 'setInexactRepeating'] {
		text += alarm_method('public ' + name + '(IJJLandroid/app/PendingIntent;)V', alarm_forward('p1', 'p2', 'p4', 'p6', ''))
	}
	text += alarm_method('public setWindow(IJJLandroid/app/PendingIntent;)V', alarm_forward('p1', 'p2', '', 'p6', '')) +
		alarm_method('public set(IJJJLandroid/app/PendingIntent;Landroid/os/WorkSource;)V', alarm_forward('p1', 'p2', 'p6', 'p8', ''))
	for name in ['set', 'setExact'] {
		text += alarm_method('public ' + name + '(IJLjava/lang/String;Landroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;)V', alarm_forward('p1', 'p2', '', 'p5', 'p6'))
	}
	text += alarm_method('public setWindow(IJJLjava/lang/String;Landroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;)V', alarm_forward('p1', 'p2', '', 'p7', 'p8')) +
		alarm_method('public set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V', alarm_forward('p1', 'p2', 'p6', 'p8', 'p9')) +
		alarm_method('public set(IJJJLjava/lang/String;Landroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V', alarm_forward('p1', 'p2', 'p6', 'p9', 'p10')) +
		alarm_method('public setAlarmClock(Landroid/app/AlarmManager$AlarmClockInfo;Landroid/app/PendingIntent;)V', 'invoke-virtual {p1}, Landroid/app/AlarmManager$AlarmClockInfo;->getTriggerTime()J\nmove-result-wide v1\nconst/4 v0, 0\nconst-wide/16 v3, 0\nmove-object v5, p2\nconst/4 v6, 0\ninvoke-static/range {v0 .. v6}, ' + owner + '->vinixSchedule(IJJLjava/lang/Object;Landroid/os/Handler;)V\nreturn-void')
	for kind in ['Landroid/app/PendingIntent;', 'Landroid/app/AlarmManager$OnAlarmListener;'] {
		text += alarm_method('public cancel(' + kind + ')V', 'invoke-static {p1}, ' + owner + '->vinixCancel(Ljava/lang/Object;)V\nreturn-void')
	}
	text += alarm_method('private static synchronized vinixCancel(Ljava/lang/Object;)V', 'if-eqz p0, :null\nsget-object v0, ' + owner + '->tasks:' + map_type + '\ninvoke-virtual {v0, p0}, ' + map_type + '->remove(Ljava/lang/Object;)Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, ' + task + '\nif-eqz v1, :done\niget-object v0, v1, ' + task + '->handler:Landroid/os/Handler;\ninvoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V\n:done\nreturn-void\n:null\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0')
	text += alarm_method('private static synchronized vinixSchedule(IJJLjava/lang/Object;Landroid/os/Handler;)V', '
if-ltz p0, :bad_type
const/4 v0, 3
if-gt p0, v0, :bad_type
if-eqz p5, :bad_target
instance-of v0, p5, Landroid/app/AlarmManager$OnAlarmListener;
if-eqz v0, :target_ok
const-wide/16 v0, 0
cmp-long v0, p3, v0
if-gtz v0, :bad_repeat
:target_ok
invoke-static {p5}, Landroid/app/AlarmManager;->vinixCancel(Ljava/lang/Object;)V
if-nez p6, :handler_ready
new-instance p6, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-direct {p6, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
:handler_ready
const-wide/16 v0, 0
cmp-long v0, p3, v0
if-gez v0, :interval_ready
const-wide/16 p3, 0
:interval_ready
new-instance v0, Landroid/app/VinixAlarmTask;
move-object v1, p5
move-object v2, p6
move-wide v3, p3
invoke-direct/range {v0 .. v4}, Landroid/app/VinixAlarmTask;-><init>(Ljava/lang/Object;Landroid/os/Handler;J)V
sget-object v1, Landroid/app/AlarmManager;->tasks:Ljava/util/IdentityHashMap;
invoke-virtual {v1, p5, v0}, Ljava/util/IdentityHashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const/4 v1, 2
if-lt p0, v1, :wall_clock
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v1
goto :clock_ready
:wall_clock
invoke-static {}, Ljava/lang/System;->currentTimeMillis()J
move-result-wide v1
:clock_ready
# Clamp past times before subtracting, avoiding overflow for Long.MIN_VALUE.
cmp-long v3, p1, v1
if-lez v3, :immediate
sub-long v1, p1, v1
goto :delay_ready
:immediate
const-wide/16 v1, 0
:delay_ready
invoke-static {p6, v0, v1, v2}, Landroid/app/AlarmManager;->vinixPost(Landroid/os/Handler;Ljava/lang/Runnable;J)Z
move-result v1
if-nez v1, :done
invoke-static {p5}, Landroid/app/AlarmManager;->vinixCancel(Ljava/lang/Object;)V
:done
return-void
:bad_type
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Invalid alarm type"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:bad_target
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Alarm must have a PendingIntent or listener"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:bad_repeat
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Repeating alarms require a PendingIntent"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0')
	text += alarm_method('public static synchronized vinixPrepare(Landroid/app/VinixAlarmTask;)Z', '
iget-object v0, p0, Landroid/app/VinixAlarmTask;->target:Ljava/lang/Object;
sget-object v1, Landroid/app/AlarmManager;->tasks:Ljava/util/IdentityHashMap;
invoke-virtual {v1, v0}, Ljava/util/IdentityHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v2
if-ne v2, p0, :stale
iget-wide v2, p0, Landroid/app/VinixAlarmTask;->interval:J
const-wide/16 v4, 0
cmp-long v4, v2, v4
if-lez v4, :remove
iget-object v4, p0, Landroid/app/VinixAlarmTask;->handler:Landroid/os/Handler;
invoke-static {v4, p0, v2, v3}, Landroid/app/AlarmManager;->vinixPost(Landroid/os/Handler;Ljava/lang/Runnable;J)Z
move-result v2
if-nez v2, :deliver
:remove
invoke-virtual {v1, v0}, Ljava/util/IdentityHashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;
:deliver
const/4 v0, 1
return v0
:stale
const/4 v0, 0
return v0')
	// Handler.postDelayed adds uptime without saturation in the baseline. Keep
	// very distant alarms queued in the future instead of overflowing to now.
	text += alarm_method('private static vinixPost(Landroid/os/Handler;Ljava/lang/Runnable;J)Z', '
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
const-wide v2, 0x7fffffffffffffffL
sub-long v4, v2, v0
cmp-long v4, p2, v4
if-gez v4, :post
add-long v2, v0, p2
:post
invoke-virtual {p0, p1, v2, v3}, Landroid/os/Handler;->postAtTime(Ljava/lang/Runnable;J)Z
move-result v0
return v0')
	os.write_file(smali + '/android/app/VinixAlarmTask.smali', '.class public final ' + task + '\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field public final target:Ljava/lang/Object;\n.field public final handler:Landroid/os/Handler;\n.field public final interval:J\n' +
		alarm_method('public constructor <init>(Ljava/lang/Object;Landroid/os/Handler;J)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + task + '->target:Ljava/lang/Object;\niput-object p2, p0, ' + task + '->handler:Landroid/os/Handler;\niput-wide p3, p0, ' + task + '->interval:J\nreturn-void') +
		alarm_method('public run()V', 'invoke-static {p0}, ' + owner + '->vinixPrepare(' + task + ')Z\nmove-result v0\nif-eqz v0, :done\niget-object v0, p0, ' + task + '->target:Ljava/lang/Object;\ninstance-of v1, v0, Landroid/app/AlarmManager$OnAlarmListener;\nif-eqz v1, :pending\ncheck-cast v0, Landroid/app/AlarmManager$OnAlarmListener;\ninvoke-interface {v0}, Landroid/app/AlarmManager$OnAlarmListener;->onAlarm()V\nreturn-void\n:pending\ncheck-cast v0, Landroid/app/PendingIntent;\n:try_start\ninvoke-virtual {v0}, Landroid/app/PendingIntent;->send()V\n:try_end\ngoto :done\n.catch Landroid/app/PendingIntent$CanceledException; {:try_start .. :try_end} :canceled\n:canceled\nmove-exception v1\ninvoke-static {v0}, ' + owner + '->vinixCancelPending(Landroid/app/PendingIntent;)V\n:done\nreturn-void'))!
	// Called after a canceled PendingIntent delivery; reuses the same lock.
	text += alarm_method('public static vinixCancelPending(Landroid/app/PendingIntent;)V', 'invoke-static {p0}, ' + owner + '->vinixCancel(Ljava/lang/Object;)V\nreturn-void')
	os.write_file(smali + '/android/app/AlarmManager.smali', text)!
}

fn alarm_forward(kind string, trigger string, interval string, target string, handler string) string {
	// /from16 is required by the hidden overloads' many wide parameters.
	return 'move/from16 v0, ' + kind + '\nmove-wide/from16 v1, ' + trigger + '\n' +
		if interval == '' { 'const-wide/16 v3, 0\n' } else { 'move-wide/from16 v3, ' + interval + '\n' } +
		'move-object/from16 v5, ' + target + '\n' + if handler == '' { 'const/4 v6, 0\n' } else { 'move-object/from16 v6, ' + handler + '\n' } +
		'invoke-static/range {v0 .. v6}, Landroid/app/AlarmManager;->vinixSchedule(IJJLjava/lang/Object;Landroid/os/Handler;)V\nreturn-void'
}
