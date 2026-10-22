// SPDX-License-Identifier: GPL-2.0-or-later
// Two signed APKs exercise lazy companion Application/provider/service startup.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn alarm_classes(dir string) ! {
	probe := 'Lorg/vinix/service/AlarmProbe;'
	os.write_file(dir + '/AlarmProbe.smali', '.class public ' + probe + '\n.super Ljava/lang/Object;\n.implements Landroid/app/AlarmManager$OnAlarmListener;\n.field public volatile calls:I\n.field public volatile failed:Z\n.field public expected:Landroid/os/Looper;\n.field public latch:Ljava/util/concurrent/CountDownLatch;\n' +
		method('public constructor <init>(Landroid/os/Looper;I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + probe + '->expected:Landroid/os/Looper;\nnew-instance v0, Ljava/util/concurrent/CountDownLatch;\ninvoke-direct {v0, p2}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V\niput-object v0, p0, ' + probe + '->latch:Ljava/util/concurrent/CountDownLatch;\nreturn-void') +
		method('public onAlarm()V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\niget-object v1, p0, ' + probe + '->expected:Landroid/os/Looper;\nif-eq v0, v1, :thread_ok\nconst/4 v0, 1\niput-boolean v0, p0, ' + probe + '->failed:Z\n:thread_ok\niget v0, p0, ' + probe + '->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ' + probe + '->calls:I\niget-object v0, p0, ' + probe + '->latch:Ljava/util/concurrent/CountDownLatch;\ninvoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V\nreturn-void') +
		method('public await()V', 'iget-object v0, p0, ' + probe + '->latch:Ljava/util/concurrent/CountDownLatch;\nconst-wide/16 v1, 10\nsget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;\ninvoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z\nmove-result v0\nif-eqz v0, :bad\niget-boolean v0, p0, ' + probe + '->failed:Z\nif-nez v0, :bad\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "alarm delivery timed out or used the wrong Handler"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'))!
	os.write_file(dir + '/AlarmReceiver.smali', '.class public Lorg/vinix/service/AlarmReceiver;\n.super Landroid/content/BroadcastReceiver;\n.field public probe:' + probe + '\n.field public manager:Landroid/app/AlarmManager;\n.field public operation:Landroid/app/PendingIntent;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V\nreturn-void') +
		method('public onReceive(Landroid/content/Context;Landroid/content/Intent;)V', 'iget-object v0, p0, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\ninvoke-virtual {v0}, ' + probe + '->onAlarm()V\niget v0, v0, ' + probe + '->calls:I\nconst/4 v1, 3\nif-lt v0, v1, :done\niget-object v0, p0, Lorg/vinix/service/AlarmReceiver;->manager:Landroid/app/AlarmManager;\niget-object v1, p0, Lorg/vinix/service/AlarmReceiver;->operation:Landroid/app/PendingIntent;\ninvoke-virtual {v0, v1}, Landroid/app/AlarmManager;->cancel(Landroid/app/PendingIntent;)V\n:done\nreturn-void'))!
}

fn alarm_probe(handler bool, count int) string {
	return 'new-instance v8, Lorg/vinix/service/AlarmProbe;\n' +
		if handler { 'invoke-virtual {v9}, Landroid/os/Handler;->getLooper()Landroid/os/Looper;\n' } else { 'invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\n' } +
		'move-result-object v12\nconst/16 v13, ' + count.str() + '\ninvoke-direct {v8, v12, v13}, Lorg/vinix/service/AlarmProbe;-><init>(Landroid/os/Looper;I)V\n'
}

fn alarm_time(wall bool, delay int) string {
	return 'const/4 v1, ' + if wall { '1' } else { '3' } + '\ninvoke-static {}, ' +
		if wall { 'Ljava/lang/System;->currentTimeMillis()J\n' } else { 'Landroid/os/SystemClock;->elapsedRealtime()J\n' } +
		'move-result-wide v2\nconst-wide/16 v12, ' + delay.str() + '\nadd-long/2addr v2, v12\n'
}

fn alarm_checks() string {
	owner := 'Landroid/app/AlarmManager;'
	probe := 'Lorg/vinix/service/AlarmProbe;'
	mut body := 'move-object/from16 v15, p0\nnew-instance v0, ' + owner + '\ninvoke-direct {v0}, ' + owner + '-><init>()V\nconst-wide/16 v4, 0\nconst-wide/16 v6, 0\nconst/4 v9, 0\nnew-instance v10, Landroid/os/WorkSource;\ninvoke-direct {v10}, Landroid/os/WorkSource;-><init>()V\n'
	// Both hidden listener signatures and the public tagged overload use real
	// queues; the waiting test runs on the service worker, not the main looper.
	body += alarm_probe(false, 1) + alarm_time(false, 40) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\n'
	body += alarm_probe(false, 1) + alarm_time(false, 40) + 'move-object v11, v10\nmove-object v10, v9\nmove-object v9, v8\nconst-string v8, "tagged-hidden"\ninvoke-virtual/range {v0 .. v11}, ' + owner + '->set(IJJJLjava/lang/String;Landroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v9}, ' + probe + '->await()V\nmove-object v10, v11\nconst/4 v9, 0\n'
	body += 'new-instance v14, Landroid/os/HandlerThread;\nconst-string v12, "alarm-fixture"\ninvoke-direct {v14, v12}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V\ninvoke-virtual {v14}, Ljava/lang/Thread;->start()V\ninvoke-virtual {v14}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;\nmove-result-object v12\nnew-instance v9, Landroid/os/Handler;\ninvoke-direct {v9, v12}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V\n'
	body += alarm_probe(true, 1) + alarm_time(true, 40) + 'const-string v4, "rtc-listener"\nmove-object v5, v8\nmove-object v6, v9\ninvoke-virtual/range {v0 .. v6}, ' + owner + '->setExact(IJLjava/lang/String;Landroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\nconst-wide/16 v4, 0\nconst-wide/16 v6, 0\n'
	// Replacing an existing listener must remove the original queue entry.
	body += alarm_probe(true, 1) + alarm_time(false, 500) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\n' +
		alarm_time(false, 40) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\nmove-object v11, v8\n'
	// A barrier on the same queue follows the replaced alarm's old deadline.
	body += alarm_probe(true, 1) + alarm_time(false, 650) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\niget v12, v11, ' + probe + '->calls:I\nconst/4 v13, 1\nif-ne v12, v13, :bad\n'
	// Cancellation works through another manager instance.
	body += alarm_probe(true, 1) + alarm_time(false, 100) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\nnew-instance v12, ' + owner + '\ninvoke-direct {v12}, ' + owner + '-><init>()V\ninvoke-virtual {v12, v8}, ' + owner + '->cancel(Landroid/app/AlarmManager$OnAlarmListener;)V\nmove-object v11, v8\n' +
		alarm_probe(true, 1) + alarm_time(false, 200) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\niget v12, v11, ' + probe + '->calls:I\nif-nez v12, :bad\n'
	// A past RTC trigger is immediate, even at the signed long minimum.
	body += alarm_probe(true, 1) + 'const/4 v1, 1\nconst-wide v2, -0x8000000000000000L\ninvoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\n'
	// Hidden PendingIntent overload: real broadcast delivery and repeating
	// cancellation inside onReceive, followed by a barrier proving it stops.
	body += alarm_probe(false, 3) + 'new-instance v11, Lorg/vinix/service/AlarmReceiver;\ninvoke-direct {v11}, Lorg/vinix/service/AlarmReceiver;-><init>()V\niput-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\niput-object v0, v11, Lorg/vinix/service/AlarmReceiver;->manager:' + owner + '\nnew-instance v12, Landroid/content/IntentFilter;\nconst-string v13, "org.vinix.fixture.ALARM"\ninvoke-direct {v12, v13}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V\ninvoke-virtual {v15, v11, v12}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;\nnew-instance v12, Landroid/content/Intent;\ninvoke-direct {v12, v13}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V\nconst/16 v13, 871\nconst v8, 0x4000000\ninvoke-static {v15, v13, v12, v8}, Landroid/app/PendingIntent;->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;\nmove-result-object v8\niput-object v8, v11, Lorg/vinix/service/AlarmReceiver;->operation:Landroid/app/PendingIntent;\n' +
		alarm_time(false, 40) + 'const-wide/16 v6, 60\nmove-object v9, v10\ninvoke-virtual/range {v0 .. v9}, ' + owner + '->set(IJJJLandroid/app/PendingIntent;Landroid/os/WorkSource;)V\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\ninvoke-virtual {v8}, ' + probe + '->await()V\nconst/4 v9, 0\nconst-wide/16 v6, 0\n' +
		alarm_probe(false, 1) + alarm_time(false, 200) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\niget v12, v8, ' + probe + '->calls:I\nconst/4 v13, 3\nif-ne v12, v13, :bad\ninvoke-virtual {v15, v11}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V\ninvoke-virtual {v14}, Landroid/os/HandlerThread;->quitSafely()Z\n' +
		'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "ALARM-PASS hidden-overloads elapsed rtc handler replacement cancellation past-time pending-intent repeating"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "alarm replacement cancellation or repeating delivery"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	// A huge repeat interval must remain in the future rather than overflow
	// Handler uptime arithmetic and create an immediate broadcast loop.
	large_repeat := alarm_probe(false, 1) + 'iput-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->operation:Landroid/app/PendingIntent;\n' +
		alarm_time(false, 40) + 'const-wide v6, 0x7fffffffffffffffL\nmove-object v9, v10\ninvoke-virtual/range {v0 .. v9}, ' + owner + '->set(IJJJLandroid/app/PendingIntent;Landroid/os/WorkSource;)V\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\ninvoke-virtual {v8}, ' + probe + '->await()V\nconst/4 v9, 0\nconst-wide/16 v6, 0\n' +
		alarm_probe(false, 1) + alarm_time(false, 200) + 'invoke-virtual/range {v0 .. v10}, ' + owner + '->set(IJJJLandroid/app/AlarmManager$OnAlarmListener;Landroid/os/Handler;Landroid/os/WorkSource;)V\ninvoke-virtual {v8}, ' + probe + '->await()V\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->probe:' + probe + '\niget v12, v8, ' + probe + '->calls:I\nconst/4 v13, 1\nif-ne v12, v13, :bad\niget-object v8, v11, Lorg/vinix/service/AlarmReceiver;->operation:Landroid/app/PendingIntent;\ninvoke-virtual {v0, v8}, ' + owner + '->cancel(Landroid/app/PendingIntent;)V\n'
	return body.replace('invoke-virtual {v15, v11}, Landroid/content/Context;->unregisterReceiver', large_repeat + 'invoke-virtual {v15, v11}, Landroid/content/Context;->unregisterReceiver').replace('past-time pending-intent repeating"', 'past-time pending-intent repeating overflow"')
}

fn check_stage(expected int, next int) string {
	return 'const/4 v0, ${expected}\ninvoke-static {v0}, Lorg/vinix/service/App;->check(I)V\n' +
		'const/4 v0, ${next}\nsput v0, Lorg/vinix/service/App;->stage:I\n'
}

fn absent_hardware_checks() string {
	mut body := 'const-string v0, "contexthub"\ninvoke-virtual {p1, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/hardware/location/ContextHubManager;\nif-nez v0, :bad\n'
	body += 'const-string v0, "android.hardware.context_hub"\ninvoke-virtual {p1}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;\nmove-result-object v1\ninvoke-virtual {v1, v0}, Landroid/content/pm/PackageManager;->hasSystemFeature(Ljava/lang/String;)Z\nmove-result v0\nif-nez v0, :bad\n'
	body += 'const-string v0, "phone"\ninvoke-virtual {p1, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/telephony/TelephonyManager;\nif-eqz v0, :bad\n'
	for name in ['getSimCarrierId', 'getSimSpecificCarrierId', 'getCarrierIdFromSimMccMnc'] {
		body += 'invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->' + name + '()I\nmove-result v1\nconst/4 v2, -1\nif-ne v1, v2, :bad\n'
	}
	for name in ['getSimCarrierIdName', 'getSimSpecificCarrierIdName'] {
		body += 'invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->' + name + '()Ljava/lang/CharSequence;\nmove-result-object v1\nif-nez v1, :bad\n'
	}
	return body + 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "unavailable context hub and SIM carrier state"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn proxy_listener_checks() string {
	return 'new-instance v0, Lorg/vinix/service/ProxyListener;
invoke-direct {v0}, Lorg/vinix/service/ProxyListener;-><init>()V
new-instance v1, Landroid/os/Binder;
invoke-direct {v1}, Landroid/os/Binder;-><init>()V
const/4 v2, 7
const/4 v3, 1
invoke-interface {v0, v1, v2, v3}, Landroid/os/Binder$ProxyTransactListener;->onTransactStarted(Landroid/os/IBinder;II)Ljava/lang/Object;
move-result-object v4
if-ne v4, v0, :bad
iget v4, v0, Lorg/vinix/service/ProxyListener;->code:I
if-ne v4, v2, :bad
iget-object v4, v0, Lorg/vinix/service/ProxyListener;->binder:Landroid/os/IBinder;
if-ne v4, v1, :bad
invoke-interface {v0, v0}, Landroid/os/Binder$ProxyTransactListener;->onTransactEnded(Ljava/lang/Object;)V
iget-object v4, v0, Lorg/vinix/service/ProxyListener;->session:Ljava/lang/Object;
if-ne v4, v0, :bad
invoke-static {v0}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkBinder()V
iget v4, v0, Lorg/vinix/service/ProxyListener;->started:I
if-ne v4, v3, :bad
iget v4, v0, Lorg/vinix/service/ProxyListener;->ended:I
if-ne v4, v3, :bad
new-instance v1, Lorg/vinix/service/ProxyListener;
invoke-direct {v1}, Lorg/vinix/service/ProxyListener;-><init>()V
invoke-static {v1}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
const/4 v2, 0
invoke-static {v2}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
return-void
:bad
const/4 v0, 0
invoke-static {v0}, Landroid/os/Binder;->setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "proxy listener default overload and local Binder exclusion"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn proxy_listener_class(dir string) ! {
	os.write_file(dir + '/ProxyListener.smali', '.class public Lorg/vinix/service/ProxyListener;\n.super Ljava/lang/Object;\n' +
		'.implements Landroid/os/Binder$ProxyTransactListener;\n.field public started:I\n.field public ended:I\n.field public code:I\n' +
		'.field public binder:Landroid/os/IBinder;\n.field public session:Ljava/lang/Object;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public onTransactStarted(Landroid/os/IBinder;I)Ljava/lang/Object;', 'iget v0, p0, Lorg/vinix/service/ProxyListener;->started:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/ProxyListener;->started:I\niput p2, p0, Lorg/vinix/service/ProxyListener;->code:I\niput-object p1, p0, Lorg/vinix/service/ProxyListener;->binder:Landroid/os/IBinder;\nreturn-object p0') +
		method('public onTransactEnded(Ljava/lang/Object;)V', 'iget v0, p0, Lorg/vinix/service/ProxyListener;->ended:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/ProxyListener;->ended:I\niput-object p1, p0, Lorg/vinix/service/ProxyListener;->session:Ljava/lang/Object;\nreturn-void'))!
}

fn geofence_checks() string {
	return 'new-instance v0, Lorg/vinix/service/GeofenceProvider;
invoke-direct {v0}, Lorg/vinix/service/GeofenceProvider;-><init>()V
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v1
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v2
if-ne v1, v2, :bad
invoke-static {v1}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
invoke-interface {v2}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;
move-result-object v2
if-ne v1, v2, :bad
const/4 v2, 0
invoke-static {v2}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
if-nez v2, :bad
new-instance v2, Lorg/vinix/service/ForwardBinder;
invoke-direct {v2, v1}, Lorg/vinix/service/ForwardBinder;-><init>(Landroid/os/IBinder;)V
invoke-static {v2}, Landroid/location/IGeofenceProvider$Stub;->asInterface(Landroid/os/IBinder;)Landroid/location/IGeofenceProvider;
move-result-object v2
new-instance v3, Lorg/vinix/service/GeofenceBackend;
invoke-direct {v3}, Lorg/vinix/service/GeofenceBackend;-><init>()V
invoke-direct {p0, v3}, Lorg/vinix/service/Main;->checkGeofenceWire(Landroid/os/IBinder;)V
new-instance v4, Lorg/vinix/service/ForwardBinder;
invoke-direct {v4, v3}, Lorg/vinix/service/ForwardBinder;-><init>(Landroid/os/IBinder;)V
invoke-static {v4}, Landroid/hardware/location/IGeofenceHardware$Stub;->asInterface(Landroid/os/IBinder;)Landroid/hardware/location/IGeofenceHardware;
move-result-object v4
invoke-interface {v2, v4}, Landroid/location/IGeofenceProvider;->setGeofenceHardware(Landroid/hardware/location/IGeofenceHardware;)V
iget v4, v0, Lorg/vinix/service/GeofenceProvider;->calls:I
const/4 v5, 1
if-ne v4, v5, :bad
iget-object v4, v0, Lorg/vinix/service/GeofenceProvider;->hardware:Landroid/hardware/location/GeofenceHardware;
if-eqz v4, :bad
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
move-result-object v2
array-length v5, v2
const/4 v1, 2
if-ne v5, v1, :bad
const/4 v5, 0
aget v1, v2, v5
if-nez v1, :bad
const/4 v5, 1
aget v1, v2, v5
if-ne v1, v5, :bad
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
if-nez v1, :bad
const/16 v5, 99
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
const/4 v5, 2
if-ne v1, v5, :bad
const/4 v1, 1
iput v1, v3, Lorg/vinix/service/GeofenceBackend;->failure:I
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
move-result-object v1
array-length v1, v1
if-nez v1, :bad
const/4 v5, 0
invoke-virtual {v4, v5}, Landroid/hardware/location/GeofenceHardware;->getStatusOfMonitoringType(I)I
move-result v1
const/4 v5, 2
if-ne v1, v5, :bad
iput v5, v3, Lorg/vinix/service/GeofenceBackend;->failure:I
:security_start
invoke-virtual {v4}, Landroid/hardware/location/GeofenceHardware;->getMonitoringTypes()[I
:security_end
.catch Ljava/lang/SecurityException; {:security_start .. :security_end} :security
goto :bad
:security
move-exception v1
invoke-virtual {v0}, Lcom/android/location/provider/GeofenceProvider;->getBinder()Landroid/os/IBinder;
move-result-object v0
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const-string v2, "wrong.descriptor"
invoke-virtual {v1, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/4 v2, 1
const/4 v3, 0
const/4 v4, 0
:token_start
invoke-interface {v0, v2, v1, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:token_end
.catch Ljava/lang/SecurityException; {:token_start .. :token_end} :token
goto :bad
:token
move-exception v2
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
const/16 v2, 99
const/4 v1, 0
invoke-interface {v0, v2, v1, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v1
if-nez v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "geofence provider Binder and capability forwarding"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn geofence_classes(dir string) ! {
	geofence_callback_classes(dir)!
	os.write_file(dir + '/GeofenceProvider.smali', '.class public Lorg/vinix/service/GeofenceProvider;\n.super Lcom/android/location/provider/GeofenceProvider;\n' +
		'.field public calls:I\n.field public hardware:Landroid/hardware/location/GeofenceHardware;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Lcom/android/location/provider/GeofenceProvider;-><init>()V\nreturn-void') +
		method('public onGeofenceHardwareChange(Landroid/hardware/location/GeofenceHardware;)V', 'iget v0, p0, Lorg/vinix/service/GeofenceProvider;->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/service/GeofenceProvider;->calls:I\niput-object p1, p0, Lorg/vinix/service/GeofenceProvider;->hardware:Landroid/hardware/location/GeofenceHardware;\nreturn-void'))!
	os.write_file(dir + '/ForwardBinder.smali', '.class public Lorg/vinix/service/ForwardBinder;\n.super Landroid/os/Binder;\n.field private target:Landroid/os/IBinder;\n' +
		method('public constructor <init>(Landroid/os/IBinder;)V', 'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\niput-object p1, p0, Lorg/vinix/service/ForwardBinder;->target:Landroid/os/IBinder;\nreturn-void') +
		method('protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 'iget-object v0, p0, Lorg/vinix/service/ForwardBinder;->target:Landroid/os/IBinder;\ninvoke-interface {v0, p1, p2, p3, p4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0'))!
	os.write_file(dir + '/GeofenceBackend.smali', '.class public Lorg/vinix/service/GeofenceBackend;\n.super Landroid/hardware/location/IGeofenceHardware$Stub;\n.field public failure:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/hardware/location/IGeofenceHardware$Stub;-><init>()V\nreturn-void') +
		method('private checkFailure()V', 'iget v0, p0, Lorg/vinix/service/GeofenceBackend;->failure:I\nif-eqz v0, :ok\nconst/4 v1, 1\nif-ne v0, v1, :security\nnew-instance v0, Landroid/os/RemoteException;\ninvoke-direct {v0}, Landroid/os/RemoteException;-><init>()V\nthrow v0\n:security\nnew-instance v0, Ljava/lang/SecurityException;\ninvoke-direct {v0}, Ljava/lang/SecurityException;-><init>()V\nthrow v0\n:ok\nreturn-void') +
		method('public getMonitoringTypes()[I', 'invoke-direct {p0}, Lorg/vinix/service/GeofenceBackend;->checkFailure()V\nconst/4 v0, 2\nnew-array v0, v0, [I\nconst/4 v1, 1\naput v1, v0, v1\nreturn-object v0') +
		method('public getStatusOfMonitoringType(I)I', 'invoke-direct {p0}, Lorg/vinix/service/GeofenceBackend;->checkFailure()V\nconst/4 v0, 1\nif-ne p1, v0, :unsupported\nconst/4 v0, 0\nreturn v0\n:unsupported\nconst/4 v0, 2\nreturn v0'))!
}

fn geofence_callback_classes(dir string) ! {
	for name in ['GeofenceHardwareCallback', 'GeofenceHardwareMonitorCallback'] {
		os.write_file(dir + '/Default' + name + '.smali', '.class public Lorg/vinix/service/Default' + name + ';\n.super Landroid/hardware/location/' + name + ';\n' +
			method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/hardware/location/' + name + ';-><init>()V\nreturn-void'))!
	}
	os.write_file(dir + '/GeofenceCallback.smali', '.class public Lorg/vinix/service/GeofenceCallback;\n.super Lorg/vinix/service/DefaultGeofenceHardwareCallback;\n.field public id:I\n.field public status:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Lorg/vinix/service/DefaultGeofenceHardwareCallback;-><init>()V\nreturn-void') +
		method('public onGeofenceAdd(II)V', 'invoke-super {p0, p1, p2}, Landroid/hardware/location/GeofenceHardwareCallback;->onGeofenceAdd(II)V\niput p1, p0, Lorg/vinix/service/GeofenceCallback;->id:I\niput p2, p0, Lorg/vinix/service/GeofenceCallback;->status:I\nreturn-void'))!
}

fn geofence_callback_checks() string {
	mut body := 'new-instance v0, Lorg/vinix/service/DefaultGeofenceHardwareCallback;
invoke-direct {v0}, Lorg/vinix/service/DefaultGeofenceHardwareCallback;-><init>()V
const/16 v1, 37
const/4 v2, 4
new-instance v3, Landroid/location/Location;
const-string v7, "vinix-geofence"
invoke-direct {v3, v7}, Landroid/location/Location;-><init>(Ljava/lang/String;)V
const-wide v4, 0x100000001L
const/4 v6, 1
invoke-virtual/range {v0 .. v6}, Landroid/hardware/location/GeofenceHardwareCallback;->onGeofenceTransition(IILandroid/location/Location;JI)V
'
	for name in ['Add', 'Remove', 'Pause', 'Resume'] {
		body += 'invoke-virtual {v0, v1, v2}, Landroid/hardware/location/GeofenceHardwareCallback;->onGeofence' + name + '(II)V\n'
	}
	body += 'new-instance v0, Lorg/vinix/service/GeofenceCallback;
invoke-direct {v0}, Lorg/vinix/service/GeofenceCallback;-><init>()V
invoke-virtual {v0, v1, v2}, Landroid/hardware/location/GeofenceHardwareCallback;->onGeofenceAdd(II)V
iget v7, v0, Lorg/vinix/service/GeofenceCallback;->id:I
if-ne v7, v1, :bad
iget v7, v0, Lorg/vinix/service/GeofenceCallback;->status:I
if-ne v7, v2, :bad
new-instance v0, Lorg/vinix/service/DefaultGeofenceHardwareMonitorCallback;
invoke-direct {v0}, Lorg/vinix/service/DefaultGeofenceHardwareMonitorCallback;-><init>()V
invoke-virtual {v0, v1, v6, v3}, Landroid/hardware/location/GeofenceHardwareMonitorCallback;->onMonitoringSystemChange(IZLandroid/location/Location;)V
const/4 v7, 0
invoke-virtual {v0, v7}, Landroid/hardware/location/GeofenceHardwareMonitorCallback;->onMonitoringSystemChange(Landroid/hardware/location/GeofenceHardwareMonitorEvent;)V
invoke-direct {p0, v3}, Lorg/vinix/service/Main;->checkGeofenceEvent(Landroid/location/Location;)V
invoke-direct {p0, v7}, Lorg/vinix/service/Main;->checkGeofenceEvent(Landroid/location/Location;)V
const-string v0, "GEOFENCE-CALLBACK-PASS defaults override super event-wire null-location"
sget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v1, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "geofence callback inheritance and override dispatch"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return body
}

fn geofence_event_checks() string {
	owner := 'Landroid/hardware/location/GeofenceHardwareMonitorEvent;'
	mut body := 'new-instance v0, ' + owner + '\nconst/4 v1, 1\nconst/4 v2, 2\nconst/16 v3, 17\n' +
		'invoke-direct {v0, v1, v2, v3, p1}, ' + owner + '-><init>(IIILandroid/location/Location;)V\n'
	// Check the value object, then decode its wire fields without its own Creator.
	for index, name in ['MonitoringType', 'MonitoringStatus', 'SourceTechnologies'] {
		body += 'invoke-virtual {v0}, ' + owner + '->get' + name + '()I\nmove-result v4\nif-ne v4, v' + (index + 1).str() + ', :bad\n'
	}
	body += 'invoke-virtual {v0}, ' + owner + '->getLocation()Landroid/location/Location;\nmove-result-object v4\nif-ne v4, p1, :bad\n' +
		'invoke-virtual {v0}, ' + owner + '->describeContents()I\nmove-result v4\nif-nez v4, :bad\n' +
		'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v4\nconst/4 v5, 0\n' +
		'invoke-virtual {v0, v4, v5}, ' + owner + '->writeToParcel(Landroid/os/Parcel;I)V\ninvoke-virtual {v4, v5}, Landroid/os/Parcel;->setDataPosition(I)V\n'
	for index in 1 .. 4 {
		body += 'invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-ne v0, v' + index.str() + ', :bad\n'
	}
	body += 'const-class v0, Landroid/location/Location;\ninvoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;\nmove-result-object v0\n' +
		'invoke-virtual {v4, v0}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\nmove-result-object v0\ncheck-cast v0, Landroid/location/Location;\n' + geofence_location_check('written') +
		'invoke-virtual {v4}, Landroid/os/Parcel;->dataAvail()I\nmove-result v0\nif-nez v0, :bad\n' +
		'invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V\ninvoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v4\n'
	// Feed the Creator independently written Android wire data.
	for index in 1 .. 4 { body += 'invoke-virtual {v4, v' + index.str() + '}, Landroid/os/Parcel;->writeInt(I)V\n' }
	body += 'const/4 v5, 0\ninvoke-virtual {v4, p1, v5}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V\ninvoke-virtual {v4, v5}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
		'sget-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-interface {v0, v4}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + owner + '\n'
	for index, name in ['MonitoringType', 'MonitoringStatus', 'SourceTechnologies'] {
		body += 'invoke-virtual {v0}, ' + owner + '->get' + name + '()I\nmove-result v5\nif-ne v5, v' + (index + 1).str() + ', :bad\n'
	}
	body += 'invoke-virtual {v0}, ' + owner + '->getLocation()Landroid/location/Location;\nmove-result-object v0\n' + geofence_location_check('created') +
		'invoke-virtual {v4}, Landroid/os/Parcel;->dataAvail()I\nmove-result v0\nif-nez v0, :bad\ninvoke-virtual {v4}, Landroid/os/Parcel;->recycle()V\n' +
		'sget-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-interface {v0, v2}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;\nmove-result-object v0\ninstance-of v1, v0, [' + owner + '\nif-eqz v1, :bad\narray-length v1, v0\nif-ne v1, v2, :bad\n' +
		'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "geofence monitor event value and independent Parcel wire"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	return body
}

fn geofence_location_check(label string) string {
	return 'if-eqz p1, :null_' + label + '\nif-eqz v0, :bad\ninvoke-virtual {v0}, Landroid/location/Location;->getProvider()Ljava/lang/String;\nmove-result-object v0\nconst-string v5, "vinix-geofence"\ninvoke-virtual {v5, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\ngoto :done_' + label + '\n:null_' + label + '\nif-nez v0, :bad\n:done_' + label + '\n'
}

fn location_value_checks() string {
	owner := 'Landroid/location/Location;'
	// Fixed Android wire vectors, independent of the framework field generator.
	fields := [
		['Time', 'J', '0x100000001L', 'Long'],
		['ElapsedRealtimeNanos', 'J', '0x200000001L', 'Long'],
		['ElapsedRealtimeUncertaintyNanos', 'D', '0x4029000000000000L', 'Double'],
		['', 'I', '511', 'Int'],
		['Latitude', 'D', '0x4049c00000000000L', 'Double'],
		['Longitude', 'D', '-0x4040000000000000L', 'Double'],
		['Altitude', 'D', '0x4045200000000000L', 'Double'],
		['Speed', 'F', '0x40600000', 'Float'],
		['Bearing', 'F', '0x43af0000', 'Float'],
		['Accuracy', 'F', '0x40b00000', 'Float'],
		['VerticalAccuracyMeters', 'F', '0x40d00000', 'Float'],
		['SpeedAccuracyMetersPerSecond', 'F', '0x3f000000', 'Float'],
		['BearingAccuracyDegrees', 'F', '0x3fc00000', 'Float'],
	]
	presence := ['Altitude', 'Speed', 'Bearing', 'Accuracy', 'VerticalAccuracy', 'SpeedAccuracy', 'BearingAccuracy', 'ElapsedRealtimeUncertaintyNanos']
	mut body := 'new-instance v0, ' + owner + '\nconst-string v2, "test-provider"\ninvoke-direct {v0, v2}, ' + owner + '-><init>(Ljava/lang/String;)V\n'
	for name in presence { body += 'invoke-virtual {v0}, ' + owner + '->has' + name + '()Z\nmove-result v2\nif-nez v2, :bad\n' }
	for field in fields {
		if field[0] == '' { continue }
		wide := field[1] in ['J', 'D']
		body += (if wide { 'const-wide' } else { 'const' }) + ' v2, ' + field[2] + '\ninvoke-virtual {v0, v2' + if wide { ', v3' } else { '' } + '}, ' + owner + '->set' + field[0] + '(' + field[1] + ')V\n'
	}
	body += 'const v2, -0x3ee00000\ninvoke-virtual {v0, v2}, ' + owner + '->setBearing(F)V\nconst/4 v2, 1\ninvoke-virtual {v0, v2}, ' + owner + '->setIsFromMockProvider(Z)V\n' +
		'new-instance v7, Landroid/os/Bundle;\ninvoke-direct {v7}, Landroid/os/Bundle;-><init>()V\nconst-string v2, "key"\nconst-string v3, "initial"\ninvoke-virtual {v7, v2, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n' +
		'invoke-virtual {v0, v7}, ' + owner + '->setExtras(Landroid/os/Bundle;)V\nconst-string v3, "changed"\ninvoke-virtual {v7, v2, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n' +
		'new-instance v8, ' + owner + '\ninvoke-direct {v8, v0}, ' + owner + '-><init>(' + owner + ')V\n' +
		'invoke-virtual {v8}, ' + owner + '->getExtras()Landroid/os/Bundle;\nmove-result-object v7\ninvoke-virtual {v7, v2, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n' +
		'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\nconst/4 v2, 0\ninvoke-virtual {v0, v1, v2}, ' + owner + '->writeToParcel(Landroid/os/Parcel;I)V\ninvoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
		'invoke-virtual {v1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v2\nconst-string v3, "test-provider"\ninvoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v2\nif-eqz v2, :bad\n'
	for field in fields {
		wide := field[1] in ['J', 'D']
		body += 'invoke-virtual {v1}, Landroid/os/Parcel;->read' + field[3] + '()' + field[1] + '\nmove-result' + if wide { '-wide' } else { '' } + ' v2\n' +
			(if wide { 'const-wide' } else { 'const' }) + ' v4, ' + field[2] + '\n' + location_compare(field[1])
	}
	body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;\nmove-result-object v7\nconst-string v2, "key"\ninvoke-virtual {v7, v2}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v2\nconst-string v3, "initial"\ninvoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v2\nif-eqz v2, :bad\n' +
		'invoke-virtual {v1}, Landroid/os/Parcel;->dataAvail()I\nmove-result v2\nif-nez v2, :bad\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\ninvoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\n' +
		'const-string v2, "test-provider"\ninvoke-virtual {v1, v2}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
	for field in fields {
		wide := field[1] in ['J', 'D']
		body += (if wide { 'const-wide' } else { 'const' }) + ' v2, ' + field[2] + '\ninvoke-virtual {v1, v2' + if wide { ', v3' } else { '' } + '}, Landroid/os/Parcel;->write' + field[3] + '(' + field[1] + ')V\n'
	}
	body += 'const/4 v2, 0\ninvoke-virtual {v1, v2}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V\ninvoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
		'sget-object v2, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-interface {v2, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + owner + '\n'
	for field in fields {
		if field[0] == '' { continue }
		wide := field[1] in ['J', 'D']
		body += 'invoke-virtual {v0}, ' + owner + '->get' + field[0] + '()' + field[1] + '\nmove-result' + if wide { '-wide' } else { '' } + ' v2\n' +
			(if wide { 'const-wide' } else { 'const' }) + ' v4, ' + field[2] + '\n' + location_compare(field[1])
	}
	body += 'invoke-virtual {v0}, ' + owner + '->isFromMockProvider()Z\nmove-result v2\nif-eqz v2, :bad\ninvoke-virtual {v0}, ' + owner + '->getExtras()Landroid/os/Bundle;\nmove-result-object v2\nif-nez v2, :bad\n'
	for name in presence {
		body += 'invoke-virtual {v0}, ' + owner + '->has' + name + '()Z\nmove-result v2\nif-eqz v2, :bad\ninvoke-virtual {v0}, ' + owner + '->remove' + name + '()V\ninvoke-virtual {v0}, ' + owner + '->has' + name + '()Z\nmove-result v2\nif-nez v2, :bad\n'
	}
	body += 'invoke-virtual {v0}, ' + owner + '->reset()V\ninvoke-virtual {v0}, ' + owner + '->getProvider()Ljava/lang/String;\nmove-result-object v2\nif-nez v2, :bad\ninvoke-virtual {v0}, ' + owner + '->isFromMockProvider()Z\nmove-result v2\nif-nez v2, :bad\n' +
		'invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\nconst-string v0, "LOCATION-VALUE-PASS provider optional-fields copy extras bearing raw-wire creator reset"\nsget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v1, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n' +
		':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Location value semantics and independent Android wire vectors"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	return body
}

fn location_compare(kind string) string {
	return match kind {
		'D' { 'cmpl-double v6, v2, v4\nif-nez v6, :bad\n' }
		'J' { 'cmp-long v6, v2, v4\nif-nez v6, :bad\n' }
		'F' { 'cmpl-float v6, v2, v4\nif-nez v6, :bad\n' }
		else { 'if-ne v2, v4, :bad\n' }
	}
}

fn geofence_wire_checks() string {
	mut body := ''
	// Independent AIDL wire checks: IDs 3 and 4 follow the two HAL setters.
	for code in [3, 4] {
		body += 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n' +
			'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\n' +
			'const-string v2, "android.hardware.location.IGeofenceHardware"\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n'
		if code == 4 { body += 'const/4 v2, 1\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V\n' }
		body += 'const/4 v2, ' + code.str() + '\nconst/4 v3, 0\n' +
			'invoke-interface {p1, v2, v0, v1, v3}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v2\nif-eqz v2, :bad\n' +
			'invoke-virtual {v1}, Landroid/os/Parcel;->readException()V\n'
		if code == 3 {
			body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nconst/4 v3, 2\nif-ne v2, v3, :bad\n' +
				'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nif-nez v2, :bad\n' +
				'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nconst/4 v3, 1\nif-ne v2, v3, :bad\n'
		} else {
			body += 'invoke-virtual {v1}, Landroid/os/Parcel;->readInt()I\nmove-result v2\nif-nez v2, :bad\n'
		}
		body += 'invoke-virtual {v1}, Landroid/os/Parcel;->dataAvail()I\nmove-result v2\nif-nez v2, :bad\n' +
			'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\n'
	}
	return body + 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "geofence hardware AIDL wire"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn binder_checks() string {
	return 'new-instance v0, Lorg/vinix/service/LocalBinder;
invoke-direct {v0}, Lorg/vinix/service/LocalBinder;-><init>()V
const-string v1, "org.vinix.local"
invoke-interface {v0, v1}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v2
if-ne v0, v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->getInterfaceDescriptor()Ljava/lang/String;
move-result-object v2
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "different"
invoke-interface {v0, v2}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v2
if-nez v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->pingBinder()Z
move-result v2
if-eqz v2, :bad
invoke-interface {v0}, Landroid/os/IBinder;->isBinderAlive()Z
move-result v2
if-eqz v2, :bad
new-instance v2, Landroid/os/Binder;
invoke-direct {v2}, Landroid/os/Binder;-><init>()V
invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :bad
invoke-virtual {v0, v0}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const-string v3, "org.vinix.local"
invoke-virtual {v1, v3}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/4 v3, 7
invoke-virtual {v1, v3}, Landroid/os/Parcel;->writeInt(I)V
const/4 v3, 1
const/4 v4, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->dataPosition()I
move-result v3
if-nez v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->readException()V
invoke-virtual {v2}, Landroid/os/Parcel;->readInt()I
move-result v3
const/16 v4, 14
if-ne v3, v4, :bad
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const v3, 0x5f4e5446
const/4 v4, 0
const/4 v1, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v3
const-string v4, "org.vinix.local"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
const/4 v2, 0
const/16 v3, 99
const/4 v4, 0
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-nez v3, :bad
const/4 v3, 3
const/4 v4, 1
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 2
const/4 v4, 0
:exception_start
invoke-interface {v0, v3, v1, v2, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:exception_end
.catch Ljava/lang/IllegalStateException; {:exception_start .. :exception_end} :expected
goto :bad
:expected
move-exception v3
invoke-virtual {v3}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v3
const-string v4, "local failure"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
invoke-interface {v0, v1, v3}, Landroid/os/IBinder;->linkToDeath(Landroid/os/IBinder$DeathRecipient;I)V
invoke-interface {v0, v1, v3}, Landroid/os/IBinder;->unlinkToDeath(Landroid/os/IBinder$DeathRecipient;I)Z
move-result v3
if-eqz v3, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "local Binder ownership, identity, transaction dispatch and exception propagation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn parcel_checks() string {
	mut body := 'new-instance v0, Lorg/vinix/service/LocalBinder;
invoke-direct {v0}, Lorg/vinix/service/LocalBinder;-><init>()V
new-instance v1, Landroid/os/Binder;
invoke-direct {v1}, Landroid/os/Binder;-><init>()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const/16 v4, 123
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
invoke-virtual {v2, v1}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
const/4 v4, 0
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
:marshall_start
invoke-virtual {v2}, Landroid/os/Parcel;->marshall()[B
:marshall_end
.catch Ljava/lang/RuntimeException; {:marshall_start .. :marshall_end} :marshall_rejected
goto/16 :bad
:marshall_rejected
move-exception v4
const/16 v4, 99
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeInt(I)V
const/4 v4, 4
const/16 v5, 16
invoke-virtual {v3, v2, v4, v5}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
const/16 v4, 8
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
'
	for expected in ['v0', 'v0', 'v1', 'null'] {
		body += 'invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v4\n'
		body += if expected == 'null' { 'if-nez v4, :bad\n' } else { 'if-ne v4, ${expected}, :bad\n' }
	}
	body += 'const/16 v4, 8
const/16 v5, 8
invoke-virtual {v3, v3, v4, v5}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
const/16 v4, 24
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/16 v4, 9
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
const/4 v4, 0
invoke-virtual {v3, v4}, Landroid/os/Parcel;->writeByte(B)V
const/16 v4, 8
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/16 v4, 13
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataSize(I)V
const/16 v4, 32
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataSize(I)V
const/16 v4, 12
invoke-virtual {v3, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->marshall()[B
const/4 v4, 0
invoke-virtual {v2, v4}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v2, v4}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
const/4 v4, 4
const/4 v5, 0
invoke-interface {v0, v4, v2, v3, v5}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readException()V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-ne v4, v0, :bad
const/4 v4, 4
new-array v4, v4, [B
const/4 v5, 0
const/4 v1, 4
invoke-virtual {v2, v4, v5, v1}, Landroid/os/Parcel;->unmarshall([BII)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->marshall()[B
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Parcel Binder identity, copy offsets, self copy, overwrite, truncation, lifetime and callback round trip"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return body
}

fn typed_parcel_checks() string {
	mut body := 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\nnew-instance v1, Lorg/vinix/service/ParcelCreator;\ninvoke-direct {v1}, Lorg/vinix/service/ParcelCreator;-><init>()V\n'
	// Decode independently written SafeParcel-style markers, including a size
	// marker of 8 and a null between two objects. Check complete consumption.
	for reader in ['createTypedArray', 'readTypedArray', 'createTypedArrayList', 'readTypedList'] {
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\n'
		for value in [3, 8, 41, 7, 0, 1, 42, 9] {
			body += 'const/16 v4, ${value}\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->writeInt(I)V\n'
		}
		body += 'const/4 v4, 0\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\n'
		body += match reader {
			'createTypedArray' { 'invoke-virtual {v0, v1}, Landroid/os/Parcel;->createTypedArray(Landroid/os/Parcelable\$Creator;)[Ljava/lang/Object;\nmove-result-object v2\n' }
			'readTypedArray' { 'const/4 v4, 3\nnew-array v2, v4, [Lorg/vinix/service/ParcelValue;\ninvoke-virtual {v0, v2, v1}, Landroid/os/Parcel;->readTypedArray([Ljava/lang/Object;Landroid/os/Parcelable\$Creator;)V\n' }
			'createTypedArrayList' { 'invoke-virtual {v0, v1}, Landroid/os/Parcel;->createTypedArrayList(Landroid/os/Parcelable\$Creator;)Ljava/util/ArrayList;\nmove-result-object v2\n' }
			else { 'new-instance v2, Ljava/util/ArrayList;\ninvoke-direct {v2}, Ljava/util/ArrayList;-><init>()V\ninvoke-virtual {v0, v2, v1}, Landroid/os/Parcel;->readTypedList(Ljava/util/List;Landroid/os/Parcelable\$Creator;)V\n' }
		}
		if reader.ends_with('List') { body += 'invoke-interface {v2}, Ljava/util/List;->toArray()[Ljava/lang/Object;\nmove-result-object v2\n' }
		body += 'array-length v3, v2\nconst/4 v4, 3\nif-ne v3, v4, :bad\n'
		for index, value in [41, 0, 42] {
			body += 'const/4 v4, ${index}\naget-object v3, v2, v4\n'
			if value == 0 { body += 'if-nez v3, :bad\n' }
			else { body += 'check-cast v3, Lorg/vinix/service/ParcelValue;\niget v3, v3, Lorg/vinix/service/ParcelValue;->value:I\nconst/16 v4, ${value}\nif-ne v3, v4, :bad\n' }
		}
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I\nmove-result v3\nif-nez v3, :bad\n'
	}
	// Inspect writers with a raw int decoder, rather than round-tripping through
	// the reader under test. Also check Parcelable flags and null/empty arrays.
	for writer in ['writeTypedArray', 'writeTypedList'] {
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nconst/4 v4, 3\nnew-array v2, v4, [Lorg/vinix/service/ParcelValue;\n'
		for index, value in [41, 0, 42] {
			if value == 0 { continue }
			body += 'new-instance v3, Lorg/vinix/service/ParcelValue;\ninvoke-direct {v3}, Lorg/vinix/service/ParcelValue;-><init>()V\nconst/16 v4, ${value}\niput v4, v3, Lorg/vinix/service/ParcelValue;->value:I\nconst/4 v4, ${index}\naput-object v3, v2, v4\n'
		}
		if writer == 'writeTypedArray' { body += 'const/4 v4, 2\ninvoke-virtual {v0, v2, v4}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\n' }
		else { body += 'invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;\nmove-result-object v2\ninvoke-virtual {v0, v2}, Landroid/os/Parcel;->writeTypedList(Ljava/util/List;)V\n' }
		flags := if writer == 'writeTypedArray' { 2 } else { 0 }
		body += 'const/4 v4, 0\ninvoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\n'
		for value in [3, 1, 41, flags, 0, 1, 42, flags] {
			body += 'invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I\nmove-result v3\nconst/16 v4, ${value}\nif-ne v3, v4, :bad\n'
		}
		body += 'invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I\nmove-result v3\nif-nez v3, :bad\n'
		for size in [-1, 0] {
			body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nconst/4 v2, 0\nconst/4 v4, 0\n'
			if size == 0 {
				body += if writer == 'writeTypedArray' { 'new-array v2, v4, [Lorg/vinix/service/ParcelValue;\n' } else { 'new-instance v2, Ljava/util/ArrayList;\ninvoke-direct {v2}, Ljava/util/ArrayList;-><init>()V\n' }
			}
			body += if writer == 'writeTypedArray' { 'invoke-virtual {v0, v2, v4}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\n' } else { 'invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeTypedList(Ljava/util/List;)V\n' }
			body += 'invoke-virtual {v0, v4}, Landroid/os/Parcel;->setDataPosition(I)V\ninvoke-virtual {v0}, Landroid/os/Parcel;->readInt()I\nmove-result v3\nconst/4 v4, ${size}\nif-ne v3, v4, :bad\n'
		}
	}
	body += 'invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Parcel typed collection markers, nulls, payload and flags"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	return body
}

fn typed_parcel_classes(dir string) ! {
	os.write_file(dir + '/ParcelValue.smali', '.class public Lorg/vinix/service/ParcelValue;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public value:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public describeContents()I', 'const/4 v0, 0\nreturn v0') +
		method('public writeToParcel(Landroid/os/Parcel;I)V', 'iget v0, p0, Lorg/vinix/service/ParcelValue;->value:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {p1, p2}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void'))!
	os.write_file(dir + '/ParcelCreator.smali', '.class public Lorg/vinix/service/ParcelCreator;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [Lorg/vinix/service/ParcelValue;\nreturn-object v0') +
		method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, Lorg/vinix/service/ParcelValue;\ninvoke-direct {v0}, Lorg/vinix/service/ParcelValue;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v1\niput v1, v0, Lorg/vinix/service/ParcelValue;->value:I\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nreturn-object v0'))!
}

fn work_source_checks() string {
	mut body := 'new-instance v0, Landroid/os/WorkSource;
const/4 v1, 0
invoke-direct {v0, v1}, Landroid/os/WorkSource;-><init>(Landroid/os/WorkSource;)V
invoke-virtual {v0}, Landroid/os/WorkSource;->isEmpty()Z
move-result v1
if-eqz v1, :bad
const/16 v1, 42
const-string v2, "b"
invoke-virtual {v0, v1, v2}, Landroid/os/WorkSource;->add(ILjava/lang/String;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0, v1, v2}, Landroid/os/WorkSource;->add(ILjava/lang/String;)Z
move-result v3
if-nez v3, :bad
const-string v2, "a"
invoke-virtual {v0, v1, v2}, Landroid/os/WorkSource;->add(ILjava/lang/String;)Z
const/4 v1, 7
const-string v2, "c"
invoke-virtual {v0, v1, v2}, Landroid/os/WorkSource;->add(ILjava/lang/String;)Z
invoke-virtual {v0}, Landroid/os/WorkSource;->size()I
move-result v1
const/4 v2, 3
if-ne v1, v2, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/WorkSource;->getUid(I)I
move-result v1
const/4 v2, 7
if-ne v1, v2, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/os/WorkSource;->getName(I)Ljava/lang/String;
move-result-object v1
const-string v2, "a"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
:mixed
const/16 v1, 55
invoke-virtual {v0, v1}, Landroid/os/WorkSource;->add(I)Z
:mixed_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:mixed .. :mixed_end} :mixed_caught
:mixed_caught
move-exception v1
invoke-virtual {v0}, Landroid/os/WorkSource;->createWorkChain()Landroid/os/WorkSource$WorkChain;
move-result-object v1
const/16 v2, 100
const-string v3, "caller"
invoke-virtual {v1, v2, v3}, Landroid/os/WorkSource$WorkChain;->addNode(ILjava/lang/String;)Landroid/os/WorkSource$WorkChain;
move-result-object v2
if-ne v1, v2, :bad
const/16 v2, 101
const/4 v3, 0
invoke-virtual {v1, v2, v3}, Landroid/os/WorkSource$WorkChain;->addNode(ILjava/lang/String;)Landroid/os/WorkSource$WorkChain;
new-instance v2, Landroid/os/WorkSource;
invoke-direct {v2, v0}, Landroid/os/WorkSource;-><init>(Landroid/os/WorkSource;)V
invoke-virtual {v0, v2}, Landroid/os/WorkSource;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0}, Landroid/os/WorkSource;->hashCode()I
move-result v3
invoke-virtual {v2}, Landroid/os/WorkSource;->hashCode()I
move-result v4
if-ne v3, v4, :bad
const/16 v3, 102
const-string v4, "last"
invoke-virtual {v1, v3, v4}, Landroid/os/WorkSource$WorkChain;->addNode(ILjava/lang/String;)Landroid/os/WorkSource$WorkChain;
invoke-virtual {v0, v2}, Landroid/os/WorkSource;->equals(Ljava/lang/Object;)Z
move-result v3
if-nez v3, :bad
invoke-virtual {v0, v2}, Landroid/os/WorkSource;->diff(Landroid/os/WorkSource;)Z
move-result v3
if-nez v3, :bad
invoke-virtual {v2}, Landroid/os/WorkSource;->getWorkChains()Ljava/util/List;
move-result-object v1
const/4 v3, 0
invoke-interface {v1, v3}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/WorkSource$WorkChain;
invoke-virtual {v1}, Landroid/os/WorkSource$WorkChain;->getSize()I
move-result v3
const/4 v4, 2
if-ne v3, v4, :bad
invoke-virtual {v1}, Landroid/os/WorkSource$WorkChain;->getUids()[I
move-result-object v3
const/4 v4, 0
const/4 v5, 5
aput v5, v3, v4
invoke-virtual {v1}, Landroid/os/WorkSource$WorkChain;->getAttributionUid()I
move-result v3
const/16 v4, 100
if-ne v3, v4, :bad
invoke-virtual {v1}, Landroid/os/WorkSource$WorkChain;->getAttributionTag()Ljava/lang/String;
move-result-object v3
const-string v4, "caller"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-direct {p0, v2}, Lorg/vinix/service/Main;->checkWorkParcel(Landroid/os/WorkSource;)V
invoke-virtual {v2}, Landroid/os/WorkSource;->withoutNames()Landroid/os/WorkSource;
move-result-object v1
invoke-virtual {v1}, Landroid/os/WorkSource;->size()I
move-result v3
const/4 v4, 2
if-ne v3, v4, :bad
const/4 v3, 0
invoke-virtual {v1, v3}, Landroid/os/WorkSource;->getName(I)Ljava/lang/String;
move-result-object v3
if-nez v3, :bad
invoke-virtual {v0}, Landroid/os/WorkSource;->clear()V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkWorkParcel(Landroid/os/WorkSource;)V
invoke-virtual {v2}, Landroid/os/WorkSource;->size()I
move-result v3
const/4 v4, 3
if-ne v3, v4, :bad
invoke-virtual {v0, v2}, Landroid/os/WorkSource;->set(Landroid/os/WorkSource;)V
invoke-virtual {v0, v2}, Landroid/os/WorkSource;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
invoke-virtual {v0, v3}, Landroid/os/WorkSource;->set(Landroid/os/WorkSource;)V
invoke-virtual {v0}, Landroid/os/WorkSource;->isEmpty()Z
move-result v3
if-eqz v3, :bad
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkWorkParcel(Landroid/os/WorkSource;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "WorkSource sorted set, deep copy, chains and parcel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return body
}

fn work_parcel_checks() string {
	// Decode the writer with raw Parcel APIs before exercising the CREATOR.
	return 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/os/WorkSource;->writeToParcel(Landroid/os/Parcel;I)V
const/16 v2, 1234
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
invoke-virtual {p1}, Landroid/os/WorkSource;->size()I
move-result v2
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->createIntArray()[I
move-result-object v2
array-length v2, v2
if-lt v2, v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->createStringArray()[Ljava/lang/String;
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
if-lez v1, :sentinel
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v2
if-ne v1, v2, :bad
const-class v2, Landroid/os/WorkSource$WorkChain;
invoke-virtual {v2}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v2
:chain
invoke-virtual {v0, v2}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;
move-result-object v3
instance-of v3, v3, Landroid/os/WorkSource$WorkChain;
if-eqz v3, :bad
add-int/lit8 v1, v1, -1
if-nez v1, :chain
:sentinel
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
const/16 v2, 1234
if-ne v1, v2, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v1, Landroid/os/WorkSource;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v1, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v1
invoke-virtual {p1, v1}, Landroid/os/WorkSource;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 2
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V
const/4 v1, 3
new-array v3, v1, [I
const/4 v1, 0
const/4 v4, 7
aput v4, v3, v1
const/4 v1, 1
const/16 v4, 42
aput v4, v3, v1
const/4 v1, 2
const/16 v4, 99
aput v4, v3, v1
invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeIntArray([I)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeStringArray([Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v1, Landroid/os/WorkSource;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v1, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/WorkSource;
invoke-virtual {v1}, Landroid/os/WorkSource;->size()I
move-result v3
const/4 v4, 2
if-ne v3, v4, :bad
const/4 v3, 1
invoke-virtual {v1, v3}, Landroid/os/WorkSource;->get(I)I
move-result v3
const/16 v4, 42
if-ne v3, v4, :bad
const/4 v3, 0
invoke-virtual {v1, v3}, Landroid/os/WorkSource;->getName(I)Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "WorkSource independent Parcel decoder and complete consumption"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

// Reflection observes actual pool/connection lifetime independently of the
// parameter getters; public SQL verifies persistent and in-memory data.
fn sqlite_idle_checks() string {
 mut body := 'new-instance v0, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-direct {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;-><init>()V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;
move-result-object v1
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getIdleConnectionTimeout()J
move-result-wide v2
const-wide/16 v4, -1
cmp-long v1, v2, v4
if-nez v1, :bad
:negative
invoke-virtual {v0, v4, v5}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setIdleConnectionTimeout(J)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
:negative_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:negative .. :negative_end} :negative_caught
:negative_caught
move-exception v1
const-wide/16 v2, 0
invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setIdleConnectionTimeout(J)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
const-wide/16 v2, 200
invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setIdleConnectionTimeout(J)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
const/high16 v1, 0x10000000
invoke-virtual {v0, v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setOpenFlags(I)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;
move-result-object v1
const-wide v2, 0x7fffffffffffffffL
invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setIdleConnectionTimeout(J)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->toBuilder()Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
move-result-object v0
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;
move-result-object v1
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getIdleConnectionTimeout()J
move-result-wide v2
const-wide/16 v4, 200
cmp-long v0, v2, v4
if-nez v0, :bad
'
 for mode in ['file', 'memory', 'disabled', 'closed'] {
  body += if mode == 'memory' { 'const-string v0, ":memory:"\n' } else {
   'const-string v0, "idle-${mode}.db"\ninvoke-virtual {p0, v0}, Landroid/content/Context;->deleteDatabase(Ljava/lang/String;)Z\ninvoke-virtual {p0, v0}, Landroid/content/Context;->getDatabasePath(Ljava/lang/String;)Ljava/io/File;\nmove-result-object v0\ninvoke-virtual {v0}, Ljava/io/File;->getPath()Ljava/lang/String;\nmove-result-object v0\n'
  }
  if mode in ['disabled', 'closed'] {
   body += 'invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->toBuilder()Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;\nmove-result-object v1\nconst-wide v2, ' + if mode == 'closed' { '60000' } else { '0x7fffffffffffffffL' } + '\ninvoke-virtual {v1, v2, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setIdleConnectionTimeout(J)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;\ninvoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;\nmove-result-object v1\n'
  }
  body += 'invoke-static {v0, v1}, Landroid/database/sqlite/SQLiteDatabase;->openDatabase(Ljava/lang/String;Landroid/database/sqlite/SQLiteDatabase$OpenParams;)Landroid/database/sqlite/SQLiteDatabase;
move-result-object v0
const-string v2, "CREATE TABLE probe(value INTEGER)"
invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->beginTransaction()V
const-string v2, "INSERT INTO probe VALUES (42)"
invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
const-string v2, "mConnectionPoolLocked"
invoke-static {v0, v2}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
const-string v3, "mAcquiredConnections"
invoke-static {v2, v3}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v3
check-cast v3, Ljava/util/WeakHashMap;
invoke-virtual {v3}, Ljava/util/WeakHashMap;->keySet()Ljava/util/Set;
move-result-object v3
invoke-interface {v3}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v3
invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v3
const-wide/16 v4, 500
invoke-static {v4, v5}, Ljava/lang/Thread;->sleep(J)V
const-string v4, "mConnectionPtr"
invoke-static {v3, v4}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Ljava/lang/Long;
invoke-virtual {v4}, Ljava/lang/Long;->longValue()J
move-result-wide v4
invoke-static {v4, v5}, Ljava/lang/Long;->signum(J)I
move-result v4
if-eqz v4, :bad
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->setTransactionSuccessful()V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->endTransaction()V
'
  body += if mode == 'file' { 'invoke-static {v2}, Lorg/vinix/service/Main;->waitSQLiteIdle(Ljava/lang/Object;)V\n' } else { 'const-wide/16 v4, 500\ninvoke-static {v4, v5}, Ljava/lang/Thread;->sleep(J)V\n' }
  body += 'const-string v4, "mConnectionPtr"\ninvoke-static {v3, v4}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v4\ncheck-cast v4, Ljava/lang/Long;\ninvoke-virtual {v4}, Ljava/lang/Long;->longValue()J\nmove-result-wide v4\ninvoke-static {v4, v5}, Ljava/lang/Long;->signum(J)I
move-result v4\n' + if mode=='file' { 'if-nez v4, :bad\n' } else { 'if-eqz v4, :bad\n' }
  body += 'const-string v2, "SELECT value FROM probe"
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v2
invoke-interface {v2}, Landroid/database/Cursor;->moveToFirst()Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
invoke-interface {v2, v3}, Landroid/database/Cursor;->getInt(I)I
move-result v3
const/16 v4, 42
if-ne v3, v4, :bad
invoke-interface {v2}, Landroid/database/Cursor;->close()V
'
  if mode == 'closed' {
   body += 'const-string v2, "mConnectionPoolLocked"
invoke-static {v0, v2}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
const-string v3, "mAvailablePrimaryConnection"
invoke-static {v2, v3}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/database/sqlite/SQLiteConnection;
invoke-virtual {v3}, Landroid/database/sqlite/SQLiteConnection;->getConnectionId()I
move-result v3
const-string v4, "vinixIdleHandler"
invoke-static {v2, v4}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/os/Handler;
invoke-virtual {v4, v3}, Landroid/os/Handler;->hasMessages(I)Z
move-result v5
if-eqz v5, :bad
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->close()V
invoke-virtual {v4, v3}, Landroid/os/Handler;->hasMessages(I)Z
move-result v5
if-nez v5, :bad
'
  } else {
   body += 'invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->close()V\n'
  }

 }
 return body + 'const-string v0, "ServiceFixture"
const-string v1, "SQLITE-IDLE-PASS snapshot validation active-transaction eviction persistent-reopen in-memory disabled close-cancels"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "SQLite idle timeout must close unused disk connections and preserve active and in-memory connections"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn sqlite_params_checks() string {
	return 'new-instance v0, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-direct {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;-><init>()V
new-instance v3, Lorg/vinix/service/DatabaseCallbacks;
invoke-direct {v3}, Lorg/vinix/service/DatabaseCallbacks;-><init>()V
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setCursorFactory(Landroid/database/sqlite/SQLiteDatabase$CursorFactory;)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setErrorHandler(Landroid/database/DatabaseErrorHandler;)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
const v1, 0x10000010
invoke-virtual {v0, v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setOpenFlags(I)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
const/high16 v1, 0x20000000
invoke-virtual {v0, v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->addOpenFlags(I)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->isWriteAheadLoggingEnabled()Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0, v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->removeOpenFlags(I)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;
move-result-object v1
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getCursorFactory()Landroid/database/sqlite/SQLiteDatabase$CursorFactory;
move-result-object v2
if-ne v2, v3, :bad
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getErrorHandler()Landroid/database/DatabaseErrorHandler;
move-result-object v2
if-ne v2, v3, :bad
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setCursorFactory(Landroid/database/sqlite/SQLiteDatabase$CursorFactory;)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setErrorHandler(Landroid/database/DatabaseErrorHandler;)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
const/4 v2, 1
invoke-virtual {v0, v2}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setWriteAheadLoggingEnabled(Z)V
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getOpenFlags()I
move-result v2
const v3, 0x10000010
if-ne v2, v3, :bad
const-string v2, "open-params.db"
invoke-virtual {p0, v2}, Landroid/content/Context;->getDatabasePath(Ljava/lang/String;)Ljava/io/File;
move-result-object v2
invoke-virtual {v2}, Ljava/io/File;->delete()Z
invoke-static {v2, v1}, Landroid/database/sqlite/SQLiteDatabase;->openDatabase(Ljava/io/File;Landroid/database/sqlite/SQLiteDatabase$OpenParams;)Landroid/database/sqlite/SQLiteDatabase;
move-result-object v0
const-string v3, "CREATE TABLE probe(value INTEGER)"
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
const-string v3, "INSERT INTO probe VALUES (42)"
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->beginTransaction()V
const-string v3, "UPDATE probe SET value=99"
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->endTransaction()V
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->close()V
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->toBuilder()Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
move-result-object v0
const/16 v3, 17
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->setOpenFlags(I)Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;->build()Landroid/database/sqlite/SQLiteDatabase$OpenParams;
move-result-object v0
invoke-virtual {v2}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v3
invoke-static {v3, v0}, Landroid/database/sqlite/SQLiteDatabase;->openDatabase(Ljava/lang/String;Landroid/database/sqlite/SQLiteDatabase$OpenParams;)Landroid/database/sqlite/SQLiteDatabase;
move-result-object v0
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->isReadOnly()Z
move-result v3
if-eqz v3, :bad
const-string v3, "SELECT value FROM probe"
const/4 v4, 0
invoke-virtual {v0, v3, v4}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v3
invoke-interface {v3}, Landroid/database/Cursor;->moveToFirst()Z
move-result v4
if-eqz v4, :bad
const/4 v4, 0
invoke-interface {v3, v4}, Landroid/database/Cursor;->getInt(I)I
move-result v4
const/16 v5, 42
if-ne v4, v5, :bad
invoke-interface {v3}, Landroid/database/Cursor;->close()V
sget v3, Lorg/vinix/service/DatabaseCallbacks;->cursors:I
const/4 v4, 1
if-ne v3, v4, :bad
:readonly
const-string v3, "INSERT INTO probe VALUES (1)"
invoke-virtual {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
:readonly_end
goto :bad
.catch Landroid/database/sqlite/SQLiteException; {:readonly .. :readonly_end} :readonly_caught
:readonly_caught
move-exception v3
invoke-virtual {v0}, Landroid/database/sqlite/SQLiteDatabase;->close()V
invoke-virtual {v2}, Ljava/io/File;->delete()Z
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase$OpenParams;->getOpenFlags()I
move-result v1
const v2, 0x10000010
if-ne v1, v2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "SQLite parameter snapshots, persistent data, rollback and readonly opens"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn location_state_checks() string {
	mut body := 'const-string v0, "location"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/location/LocationManager;
invoke-virtual {v0}, Landroid/location/LocationManager;->isLocationEnabled()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/location/LocationManager;->getAllProviders()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->isEmpty()Z
move-result v1
if-eqz v1, :bad
new-instance v1, Landroid/location/Criteria;
invoke-direct {v1}, Landroid/location/Criteria;-><init>()V
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/location/LocationManager;->getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
'
	for name in ['gps', 'network', 'passive', 'xdgportal', 'missing'] {
		body += 'const-string v1, "' + name + '"\ninvoke-virtual {v0, v1}, Landroid/location/LocationManager;->isProviderEnabled(Ljava/lang/String;)Z\nmove-result v1\nif-nez v1, :bad\n'
	}
	return body + ':null_provider
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/location/LocationManager;->isProviderEnabled(Ljava/lang/String;)Z
:null_provider_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:null_provider .. :null_provider_end} :caught
:caught
move-exception v0
const-class v0, Landroid/app/PendingIntent$OnFinished;
invoke-virtual {v0}, Ljava/lang/Class;->isInterface()Z
move-result v1
if-eqz v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "location provider discovery and disabled state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn package_enumeration_checks() string {
	mut body := 'invoke-virtual {p1}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getInstalledApplications(I)Ljava/util/List;
move-result-object v1
new-instance v2, Ljava/util/HashSet;
invoke-direct {v2}, Ljava/util/HashSet;-><init>()V
invoke-interface {v1}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v1
:next
invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z
move-result v3
if-eqz v3, :done
invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/content/pm/ApplicationInfo;
iget-object v3, v3, Landroid/content/pm/ApplicationInfo;->packageName:Ljava/lang/String;
invoke-virtual {v2, v3}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
goto :next
:done
'
	for pkg in ['org.vinix.service.client', 'org.vinix.service.companion'] {
		body += 'const-string v3, "' + pkg + '"\ninvoke-virtual {v2, v3}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z\nmove-result v3\nif-eqz v3, :bad\n'
	}
	return body + 'const/4 v1, 4
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getInstalledPackages(I)Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v1
invoke-virtual {v2}, Ljava/util/HashSet;->size()I
move-result v2
if-ne v1, v2, :bad
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getPackagesForUid(I)[Ljava/lang/String;
move-result-object v1
if-eqz v1, :bad
array-length v1, v1
if-ne v1, v2, :bad
const v1, 0x7fffffff
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getPackagesForUid(I)[Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "installed application enumeration, deduplication and UID filtering"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn device_policy_checks() string {
	mut body := 'sget-object v0, Landroid/content/Context;->DEVICE_POLICY_SERVICE:Ljava/lang/String;
invoke-virtual {p1, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-eqz v0, :bad
check-cast v0, Landroid/app/admin/DevicePolicyManager;
const-class v1, Landroid/app/admin/DevicePolicyManager;
invoke-virtual {p1, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
if-ne v0, v1, :bad
const-string v1, "device_policy"
invoke-virtual {p1, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
if-ne v0, v1, :bad
'
	for signature in ['getActiveAdmins()Ljava/util/List;',
		'getDeviceOwnerComponentOnCallingUser()Landroid/content/ComponentName;',
		'getDeviceOwnerComponentOnAnyUser()Landroid/content/ComponentName;',
		'getProfileOwner()Landroid/content/ComponentName;'] {
		body += 'invoke-virtual {v0}, Landroid/app/admin/DevicePolicyManager;->' + signature + '\nmove-result-object v1\nif-nez v1, :bad\n'
	}
	body += 'invoke-virtual {v0}, Landroid/app/admin/DevicePolicyManager;->isDeviceManaged()Z\nmove-result v1\nif-nez v1, :bad\n'
	for signature in ['isProfileOwnerApp', 'isDeviceOwnerApp'] {
		for value in ['invoke-virtual {p1}, Landroid/content/Context;->getPackageName()Ljava/lang/String;\nmove-result-object v1', 'const-string v1, "missing.policy.package"', 'const/4 v1, 0'] {
			body += value + '\ninvoke-virtual {v0, v1}, Landroid/app/admin/DevicePolicyManager;->' + signature + '(Ljava/lang/String;)Z\nmove-result v2\nif-nez v2, :bad\n'
		}
	}
	body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "missing.policy.package"
const-string v3, "Admin"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/app/admin/DevicePolicyManager;->isAdminActive(Landroid/content/ComponentName;)Z
move-result v1
if-nez v1, :bad
const-string v0, "user"
invoke-virtual {p1, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
instance-of v0, v0, Landroid/os/UserManager;
if-eqz v0, :bad
const-string v0, "VinixMissingService"
invoke-virtual {p1, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "device policy lookup, caching and unmanaged guest state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return body
}

fn user_checks() string {
	return 'invoke-static {}, Landroid/os/Process;->myUid()I
move-result v0
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v0
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v1
if-ne v0, v1, :bad
invoke-static {}, Landroid/os/Binder;->getCallingUid()I
move-result v0
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v0
invoke-static {}, Landroid/os/UserHandle;->getCallingUserId()I
move-result v2
if-ne v0, v2, :bad
const-string v0, "user"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/UserManager;
invoke-virtual {v0}, Landroid/os/UserManager;->getUserProfiles()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v3
const/4 v4, 1
if-ne v3, v4, :bad
const/4 v3, 0
invoke-interface {v2, v3}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/os/UserHandle;
invoke-virtual {v3}, Landroid/os/UserHandle;->getIdentifier()I
move-result v3
if-ne v3, v1, :bad
invoke-interface {v2}, Ljava/util/List;->clear()V
invoke-virtual {v0}, Landroid/os/UserManager;->getUserProfiles()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v2
if-ne v2, v4, :bad
invoke-virtual {v0}, Landroid/os/UserManager;->isSystemUser()Z
move-result v0
if-nez v1, :secondary
if-eqz v0, :bad
goto :ids
:secondary
if-nez v0, :bad
:ids
new-instance v0, Landroid/os/UserHandle;
const/4 v1, 0
invoke-direct {v0, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-virtual {v0}, Landroid/os/UserHandle;->isOwner()Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/os/UserHandle;->isSystem()Z
move-result v1
if-eqz v1, :bad
new-instance v0, Landroid/os/UserHandle;
const/4 v1, 1
invoke-direct {v0, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-virtual {v0}, Landroid/os/UserHandle;->isOwner()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/UserHandle;->isSystem()Z
move-result v1
if-nez v1, :bad
new-instance v0, Landroid/os/UserHandle;
const/4 v1, -1
invoke-direct {v0, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-virtual {v0}, Landroid/os/UserHandle;->isOwner()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/UserHandle;->isSystem()Z
move-result v1
if-nez v1, :bad
const v0, 201234
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v1
const/4 v2, 2
if-ne v1, v2, :bad
invoke-static {v0}, Landroid/os/UserHandle;->getAppId(I)I
move-result v1
const/16 v2, 1234
if-ne v1, v2, :bad
const/4 v0, 2
invoke-static {v0, v2}, Landroid/os/UserHandle;->getUid(II)I
move-result v0
const v1, 201234
if-ne v0, v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Android user identity must derive from UID user ranges"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn priority_checks() string {
	return 'invoke-static {}, Landroid/os/Process;->myTid()I
move-result v0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
const/4 v2, 0
invoke-static {v2}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v1, v3, :bad
const/4 v2, -1
invoke-static {v2}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v2, v3, :bad
invoke-static {v0, v1}, Landroid/os/Process;->setThreadPriority(II)V
const/16 v2, 19
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
if-ne v2, v3, :bad
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
const v2, 0x7fffffff
:missing_start
invoke-static {v2}, Landroid/os/Process;->getThreadPriority(I)I
:missing_end
.catch Ljava/lang/IllegalArgumentException; {:missing_start .. :missing_end} :missing_ok
goto :bad
:missing_ok
move-exception v3
:set_missing_start
invoke-static {v2, v1}, Landroid/os/Process;->setThreadPriority(II)V
:set_missing_end
.catch Ljava/lang/IllegalArgumentException; {:set_missing_start .. :set_missing_end} :set_missing_ok
goto :bad
:set_missing_ok
move-exception v3
const/16 v2, 20
invoke-static {v2}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
const/16 v2, 19
if-ne v2, v3, :bad
const/16 v2, -21
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v3
const/16 v2, -20
if-ne v2, v3, :bad
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v2
if-ne v1, v2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "thread priority read, write, minus-one, missing TID and clamping"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn local_binder_fixture() string {
	return '.class public Lorg/vinix/service/LocalBinder;\n.super Landroid/os/Binder;\n.implements Landroid/os/IInterface;\n.field private caller:Ljava/lang/Thread;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/os/Binder;-><init>()V
const-string v0, "org.vinix.local"
invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iput-object v0, p0, Lorg/vinix/service/LocalBinder;->caller:Ljava/lang/Thread;
return-void') +
		method('public asBinder()Landroid/os/IBinder;', 'return-object p0') +
		method('protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 'invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, Lorg/vinix/service/LocalBinder;->caller:Ljava/lang/Thread;
if-ne v0, v1, :bad
const/4 v0, 1
if-eq p1, v0, :request
const/4 v0, 2
if-eq p1, v0, :exception
const/4 v0, 3
if-eq p1, v0, :oneway
const/4 v0, 4
if-eq p1, v0, :callback
invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
return v0
:request
const-string v0, "org.vinix.local"
invoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V
invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I
move-result v0
mul-int/lit8 v0, v0, 2
invoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V
invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeInt(I)V
const/4 v0, 1
return v0
:exception
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "local failure"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:callback
invoke-virtual {p2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p0, :bad
invoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V
invoke-virtual {p3, p0}, Landroid/os/Parcel;->writeStrongInterface(Landroid/os/IInterface;)V
const/4 v0, 1
return v0
:oneway
if-nez p3, :bad
const/4 v0, 1
if-ne p4, v0, :bad
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "local Binder caller thread and one-way arguments"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}

fn component_checks() string {
	mut body := 'invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;\nmove-result-object v0\n'
	// Check metadata only: named companion processes still share this ART VM.
	for name in ['client', 'companion'] {
		process := 'org.vinix.service.' + name + if name == 'companion' { ':worker' } else { '' }
		body += 'const-string v2, "org.vinix.service.' + name + '"
const-string v3, "' + process + '"
const/4 v4, 0
invoke-virtual {v0, v2, v4}, Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v4, v1, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
new-instance v4, Landroid/content/pm/ApplicationInfo;
invoke-direct {v4, v1}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
iget-object v4, v4, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
const/4 v4, 0
invoke-virtual {p0, v2, v4}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v5
invoke-virtual {v5}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v4, v1, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
'
	}
	for kind in ['Provider', 'Service'] {
		class := if kind == 'Provider' { 'Provider' } else { 'Worker' }
		for package_name in ['client', 'companion'] {
			app_process := 'org.vinix.service.' + package_name + if package_name == 'companion' { ':worker' } else { '' }
			component_process := if kind == 'Provider' { app_process } else if package_name == 'client' { 'org.vinix.service.global' } else { 'org.vinix.service.companion:service' }
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.service.' + package_name + '"
const-string v3, "org.vinix.service.' + class + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/16 v3, 0x80
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
move-result-object v1
iget-object v3, v1, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v3, v1, Landroid/content/pm/ComponentInfo;->processName:Ljava/lang/String;
const-string v4, "' + component_process + '"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v3, v1, Landroid/content/pm/ComponentInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget-object v3, v3, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
const-string v4, "' + app_process + '"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v1, v1, Landroid/content/pm/PackageItemInfo;->metaData:Landroid/os/Bundle;
if-eqz v1, :bad
const-string v2, "owner"
invoke-virtual {v1, v2}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "' + package_name + '"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
'
		}
		for index in 0 .. 2 {
			label := kind + index.str()
			package_name := if index == 0 { 'org.vinix.service.companion' } else { 'org.vinix.service.absent' }
			name := if index == 0 { 'org.vinix.service.Missing' } else { 'org.vinix.service.' + class }
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "' + package_name + '"
const-string v3, "' + name + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v3, 0
:try' + label + '
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
:end' + label + '
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:try' + label + ' .. :end' + label + '} :caught' + label + '
goto :bad
:caught' + label + '
move-exception v1
'
		}
	}
	return body + 'return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package-qualified component metadata and missing component rejection"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn directory_checks() string {
	mut body := ''
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getDataDir()Ljava/io/File;\nmove-result-object v0\n'
		for kind in ['custom', 'cache'] {
			call := if kind == 'custom' {
				'const-string v2, "fixture"\nconst/4 v3, 0\ninvoke-virtual {' + context + ', v2, v3}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;\n'
			} else {
				'invoke-virtual {' + context + '}, Landroid/content/Context;->getCacheDir()Ljava/io/File;\n'
			}
			name := if kind == 'custom' { 'app_fixture' } else { 'cache' }
			body += call + 'move-result-object v1
invoke-virtual {v1}, Ljava/io/File;->isDirectory()Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Ljava/io/File;->getParentFile()Ljava/io/File;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Ljava/io/File;->getName()Ljava/lang/String;
move-result-object v2
const-string v3, "' + name + '"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
' + call + 'move-result-object v2
invoke-virtual {v1, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
new-instance v2, Ljava/io/File;
const-string v3, "owner.bin"
invoke-direct {v2, v1, v3}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v3, Ljava/io/FileOutputStream;
invoke-direct {v3, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, ' + (49 + index).str() + '
invoke-virtual {v3, v4}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v3}, Ljava/io/FileOutputStream;->close()V
'
		}
	}
	// Reopen after both packages wrote the same relative names.
	for index, context in ['p0', 'p1'] {
		for kind in ['custom', 'cache'] {
			body += if kind == 'custom' {
				'const-string v0, "fixture"\nconst/4 v1, 0\ninvoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;\n'
			} else {
				'invoke-virtual {' + context + '}, Landroid/content/Context;->getCacheDir()Ljava/io/File;\n'
			}
			body += 'move-result-object v0
new-instance v1, Ljava/io/File;
const-string v2, "owner.bin"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Ljava/io/FileInputStream;
invoke-direct {v0, v1}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Ljava/io/FileInputStream;->read()I
move-result v1
invoke-virtual {v0}, Ljava/io/FileInputStream;->close()V
const/16 v2, ' + (49 + index).str() + '
if-ne v1, v2, :bad
'
		}
	}
	for index, mode in [1, 2] {
		body += 'const-string v0, "forbidden"\nconst/4 v1, ' + mode.str() + '
:mode_start_' + index.str() + '
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
:mode_end_' + index.str() + '
.catch Ljava/lang/SecurityException; {:mode_start_' + index.str() + ' .. :mode_end_' + index.str() + '} :mode_caught_' + index.str() + '
goto :bad
:mode_caught_' + index.str() + '
move-exception v0
'
	}
	return body + 'const-string v0, "../escape"
const/4 v1, 0
:name_start
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
:name_end
.catch Ljava/lang/IllegalArgumentException; {:name_start .. :name_end} :name_caught
goto :bad
:name_caught
move-exception v0
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "custom/cache directory layout, isolation or mode validation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn storage_checks() string {
	mut body := 'invoke-virtual {p1}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
iget-object v1, v0, Landroid/content/pm/ApplicationInfo;->splitNames:[Ljava/lang/String;
if-nez v1, :bad
new-instance v0, Landroid/content/pm/ApplicationInfo;
invoke-direct {v0}, Landroid/content/pm/ApplicationInfo;-><init>()V
const/4 v1, 1
new-array v1, v1, [Ljava/lang/String;
const/4 v2, 0
const-string v3, "feature"
aput-object v3, v1, v2
'
	for field in ['splitNames', 'splitSourceDirs', 'splitPublicSourceDirs'] {
		body += 'iput-object v1, v0, Landroid/content/pm/ApplicationInfo;->' + field + ':[Ljava/lang/String;\n'
	}
	body += 'new-instance v2, Landroid/content/pm/ApplicationInfo;
invoke-direct {v2, v0}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
'
	for field in ['splitNames', 'splitSourceDirs', 'splitPublicSourceDirs'] {
		body += 'iget-object v3, v2, Landroid/content/pm/ApplicationInfo;->' + field + ':[Ljava/lang/String;\nif-ne v1, v3, :bad\n'
	}
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v0
invoke-virtual {' + context + '}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v1, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
new-instance v2, Ljava/io/File;
invoke-direct {v2, v1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {' + context + '}, Landroid/content/Context;->getFilesDir()Ljava/io/File;
move-result-object v1
invoke-virtual {v1}, Ljava/io/File;->getParentFile()Ljava/io/File;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
new-instance v2, Ljava/io/File;
const-string v3, "same-name.bin"
invoke-direct {v2, v1, v3}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v3, Ljava/io/FileOutputStream;
invoke-direct {v3, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, ' + (49 + index).str() + '
invoke-virtual {v3, v4}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v3}, Ljava/io/FileOutputStream;->close()V
const-string v1, "same-name"
const/4 v2, 0
invoke-virtual {' + context + ', v1, v2}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v1
invoke-interface {v1}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
move-result-object v1
const-string v2, "owner"
invoke-interface {v1, v2, v4}, Landroid/content/SharedPreferences$Editor;->putInt(Ljava/lang/String;I)Landroid/content/SharedPreferences$Editor;
invoke-interface {v1}, Landroid/content/SharedPreferences$Editor;->commit()Z
move-result v1
if-eqz v1, :bad
'
	}
	body += 'invoke-virtual {p0}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
'
	for index, context in ['p0', 'p1'] {
		body += 'invoke-virtual {' + context + '}, Landroid/content/Context;->getFilesDir()Ljava/io/File;
move-result-object v0
new-instance v1, Ljava/io/File;
const-string v2, "same-name.bin"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Ljava/io/FileInputStream;
invoke-direct {v0, v1}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Ljava/io/FileInputStream;->read()I
move-result v1
invoke-virtual {v0}, Ljava/io/FileInputStream;->close()V
const/16 v2, ' + (49 + index).str() + '
if-ne v1, v2, :bad
const-string v0, "same-name"
const/4 v1, 0
invoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v3
invoke-virtual {' + context + ', v0, v1}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v0
if-ne v0, v3, :bad
invoke-virtual {' + context + '}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v0
const-string v1, "same-name"
const/4 v4, 0
invoke-virtual {v0, v1, v4}, Landroid/content/Context;->getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
move-result-object v0
if-ne v0, v3, :bad
const-string v1, "owner"
const/4 v4, -1
invoke-interface {v0, v1, v4}, Landroid/content/SharedPreferences;->getInt(Ljava/lang/String;I)I
move-result v1
if-ne v1, v2, :bad
'
	}
	return body + 'return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package-private data, files and preferences"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn importance_checks() string {
 return 'new-instance v0, Landroid/app/ActivityManager;
invoke-direct {v0}, Landroid/app/ActivityManager;-><init>()V
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->getUidImportance(I)I
move-result v2
const/16 v3, 100
if-ne v2, v3, :bad
const/4 v2, -1
invoke-virtual {v0, v2}, Landroid/app/ActivityManager;->getUidImportance(I)I
move-result v2
const/16 v3, 1000
if-ne v2, v3, :bad
new-instance v2, Landroid/app/ActivityManager$RunningAppProcessInfo;
invoke-direct {v2}, Landroid/app/ActivityManager$RunningAppProcessInfo;-><init>()V
invoke-static {v2}, Landroid/app/ActivityManager;->getMyMemoryState(Landroid/app/ActivityManager$RunningAppProcessInfo;)V
iget v3, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->uid:I
if-ne v1, v3, :bad
invoke-static {}, Landroid/os/Process;->myPid()I
move-result v3
iget v4, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->pid:I
if-ne v3, v4, :bad
iget v3, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->importance:I
const/16 v4, 100
if-ne v3, v4, :bad
iget-object v2, v2, Landroid/app/ActivityManager$RunningAppProcessInfo;->processName:Ljava/lang/String;
const-string v3, "org.vinix.service.client"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0}, Landroid/app/ActivityManager;->getRunningAppProcesses()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
new-instance v1, Lorg/vinix/service/UidListener;
invoke-direct {v1}, Lorg/vinix/service/UidListener;-><init>()V
const/16 v2, 200
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
:duplicate
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
:duplicate_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:duplicate .. :duplicate_end} :duplicated
:duplicated
move-exception v3
# Controlled threshold crossings; onCreate also checks the real WS transition.
const/16 v2, 200
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 300
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 400
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
const/16 v2, 100
invoke-static {v2}, Landroid/atl/VinixUidImportance;->update(I)V
iget-object v2, v1, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v3, 10
sget-object v5, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v2, v3, v4, v5}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v2
if-eqz v2, :bad
iget v2, v1, Lorg/vinix/service/UidListener;->calls:I
const/4 v3, 2
if-ne v2, v3, :bad
iget v2, v1, Lorg/vinix/service/UidListener;->failed:I
if-nez v2, :bad
new-instance v2, Landroid/app/ActivityManager;
invoke-direct {v2}, Landroid/app/ActivityManager;-><init>()V
:other
invoke-virtual {v2, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:other_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:other .. :other_end} :other_caught
:other_caught
move-exception v3
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:absent
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
:absent_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:absent .. :absent_end} :absent_caught
:absent_caught
move-exception v2
const/16 v2, 200
invoke-virtual {v0, v1, v2}, Landroid/app/ActivityManager;->addOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;I)V
invoke-virtual {v0, v1}, Landroid/app/ActivityManager;->removeOnUidImportanceListener(Landroid/app/ActivityManager$OnUidImportanceListener;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "UID importance state, threshold, thread or registration"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn importance_listener(dir string) ! {
 os.write_file(dir + '/UidListener.smali', '.class public Lorg/vinix/service/UidListener;\n.super Ljava/lang/Object;\n.implements Landroid/app/ActivityManager$OnUidImportanceListener;\n' +
  '.field public calls:I\n.field public failed:I\n.field public latch:Ljava/util/concurrent/CountDownLatch;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 2
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
return-void') +
  method('public onUidImportance(II)V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :bad
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v0
if-ne v0, p1, :bad
iget v0, p0, Lorg/vinix/service/UidListener;->calls:I
const/16 v1, 300
if-eqz v0, :expected
const/16 v1, 100
:expected
if-ne v1, p2, :bad
goto :done
:bad
const/4 v0, 1
iput v0, p0, Lorg/vinix/service/UidListener;->failed:I
:done
iget v0, p0, Lorg/vinix/service/UidListener;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/service/UidListener;->calls:I
iget-object v0, p0, Lorg/vinix/service/UidListener;->latch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void'))!
}

fn main() {
	if os.args.len != 8 {
		panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER AAPT2 FRAMEWORK_RES')
	}
	out, fixture, tools := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3])
	java, signer, aapt, resources := os.args[4], os.abs_path(os.args[5]), os.abs_path(os.args[6]), os.abs_path(os.args[7])
	for name in ['client', 'companion'] {
		os.mkdir_all(out + '/' + name + '/smali/org/vinix/service')!
	}
	companion := out + '/companion/smali/org/vinix/service/'
	os.write_file(companion + 'App.smali', '.class public Lorg/vinix/service/App;\n.super Landroid/app/Application;\n.field public static stage:I\n.field public static starts:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void') +
		method('public static check(I)V', '
sget v0, Lorg/vinix/service/App;->stage:I
if-eq v0, p0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion Application/provider/service startup order"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('protected attachBaseContext(Landroid/content/Context;)V', 'invoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V\n' + check_stage(0, 1) + 'return-void') +
		method('public onCreate()V', check_stage(2, 3) + 'return-void'))!
	provider := '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :unattached
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider context before attachment"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:unattached
return-void') +
		method('public onCreate()Z', check_stage(1, 2) + '
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "org.vinix.service.companion"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v1
const-string v3, "provider_owner"
const-string v4, "string"
invoke-virtual {v1, v3, v4, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/Context;->getString(I)Ljava/lang/String;
move-result-object v1
const-string v2, "companion resource"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/content/ContentProvider;->attachInfo(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V
const/4 v0, 1
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider owning package and resources"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	mut operations := ''
	for signature in [
		'query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;',
		'insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;',
		'getType(Landroid/net/Uri;)Ljava/lang/String;',
	] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn-object v0')
	}
	for signature in ['delete(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I',
		'update(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I'] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn v0')
	}
	os.write_file(companion + 'Provider.smali', provider + operations)!
	client := out + '/client/smali/org/vinix/service/'
	os.write_file(client + 'LocalBinder.smali', local_binder_fixture())!
	os.write_file(client + 'Provider.smali', '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V\nreturn-void') +
		method('public onCreate()Z', 'const/4 v0, 1\nreturn v0') + operations)!
	os.write_file(client + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 'const/4 v0, 0\nreturn-object v0'))!
	os.write_file(companion + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\n' + check_stage(3, 4) + 'return-void') +
		method('public onCreate()V', check_stage(4, 5) + '
invoke-virtual {p0}, Landroid/app/Service;->getApplication()Landroid/app/Application;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v1
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service Application context identity"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('public onStartCommand(Landroid/content/Intent;II)I', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/service/App;->starts:I
const/4 v0, 0
return v0') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
const/4 v1, 2
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service must start twice without recreating Application or providers"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
return-object v0'))!
	os.write_file(out + '/client/smali/org/vinix/service/Main.smali', '.class public Lorg/vinix/service/Main;\n.super Landroid/app/Activity;\n.implements Landroid/content/ServiceConnection;\n.implements Ljava/util/concurrent/Executor;\n.implements Ljava/lang/Runnable;\n' +
		'.field private label:Landroid/widget/TextView;\n.field private callbacks:I\n.field private worker:Landroid/os/Handler;\n' +
		'.field private priorityMain:I\n.field private priorityWorker:I\n.field private priorityOriginal:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		method('private checkComponents()V', component_checks()) +
		method('private checkAbsentHardware(Landroid/content/Context;)V', absent_hardware_checks()) +
		method('private checkBinder()V', binder_checks()) +
		method('private checkProxyListener()V', proxy_listener_checks()) +
		method('private checkParcel()V', parcel_checks()) +
		method('private checkTypedParcel()V', typed_parcel_checks()) +
		method('private checkGeofence()V', geofence_checks()) +
		'.method private checkGeofenceCallbacks()V\n.locals 10\n' + geofence_callback_checks() + '\n.end method\n' +
		method('private checkGeofenceEvent(Landroid/location/Location;)V', geofence_event_checks()) +
		'.method private checkLocationValue()V\n.locals 10\n' + location_value_checks() + '\n.end method\n' +
		method('private checkGeofenceWire(Landroid/os/IBinder;)V', geofence_wire_checks()) +
		method('private checkUser()V', user_checks()) +
		method('private checkDevicePolicy(Landroid/content/Context;)V', device_policy_checks()) +
		method('private checkWorkSource()V', work_source_checks()) +
		'.method private checkAlarms()V\n.locals 16\n' + alarm_checks() + '\n.end method\n' +
		method('private checkWorkParcel(Landroid/os/WorkSource;)V', work_parcel_checks()) +
		method('private checkSQLiteParams()V', sqlite_params_checks()) +
		method('private checkSQLiteIdle()V', sqlite_idle_checks()) +
		method('private static readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;', 'invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/AccessibleObject;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0') +
		method('private static waitSQLiteIdle(Ljava/lang/Object;)V', 'const/16 v2, 100
:poll
const-string v0, "mAvailablePrimaryConnection"
invoke-static {p0, v0}, Lorg/vinix/service/Main;->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-eqz v0, :done
const-wide/16 v0, 50
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
add-int/lit8 v2, v2, -1
if-nez v2, :poll
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Idle SQLite connection was not closed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') +
		method('private checkLocationState()V', location_state_checks()) +
		method('private checkPackageEnumeration(Landroid/content/Context;)V', package_enumeration_checks()) +
		method('private checkPriority()V', priority_checks()) +
		method('private checkImportance()V', importance_checks()) +
		method('private checkWorkerPriority()V', '
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriority()V
invoke-static {}, Landroid/os/Process;->myTid()I
move-result v0
iput v0, p0, Lorg/vinix/service/Main;->priorityWorker:I
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
iput v1, p0, Lorg/vinix/service/Main;->priorityOriginal:I
const/4 v1, 7
invoke-static {v1}, Landroid/os/Process;->setThreadPriority(I)V
return-void') +
		method('private checkPriorityIsolation()V', '
const/4 v0, 0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v0
iget v1, p0, Lorg/vinix/service/Main;->priorityMain:I
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/service/Main;->priorityWorker:I
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
const/4 v2, 7
if-ne v1, v2, :bad
const/16 v2, 12
invoke-static {v0, v2}, Landroid/os/Process;->setThreadPriority(II)V
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v1
if-ne v1, v2, :bad
iget v1, p0, Lorg/vinix/service/Main;->priorityOriginal:I
invoke-static {v0, v1}, Landroid/os/Process;->setThreadPriority(II)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "per-thread priority isolation and remote TID"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private checkStorage(Landroid/content/Context;)V', storage_checks()) +
		method('private checkDirectories(Landroid/content/Context;)V', directory_checks()) +
		method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkComponents()V
invoke-direct {p0, p0}, Lorg/vinix/service/Main;->checkAbsentHardware(Landroid/content/Context;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkProxyListener()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkParcel()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkTypedParcel()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkGeofence()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkGeofenceCallbacks()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkLocationValue()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkUser()V
invoke-direct {p0, p0}, Lorg/vinix/service/Main;->checkDevicePolicy(Landroid/content/Context;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkWorkSource()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkSQLiteParams()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkSQLiteIdle()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkLocationState()V
invoke-direct {p0, p0}, Lorg/vinix/service/Main;->checkPackageEnumeration(Landroid/content/Context;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkImportance()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriority()V
const/4 v0, 0
invoke-static {v0}, Landroid/os/Process;->getThreadPriority(I)I
move-result v0
iput v0, p0, Lorg/vinix/service/Main;->priorityMain:I
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Checking companion services"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const-string v0, "org.vinix.service.companion"
const/4 v1, 3
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v0
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkStorage(Landroid/content/Context;)V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkAbsentHardware(Landroid/content/Context;)V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkDirectories(Landroid/content/Context;)V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkDevicePolicy(Landroid/content/Context;)V
invoke-direct {p0, v0}, Lorg/vinix/service/Main;->checkPackageEnumeration(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/content/Context;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
const-string v1, "org.vinix.service.App"
invoke-virtual {v0, v1}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const-string v1, "stage"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->getInt(Ljava/lang/Object;)I
move-result v0
if-eqz v0, :lazy
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package context must not start companion Application"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:lazy
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
const/4 v1, 1
invoke-virtual {p0, v0, p0, v1}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
return-void') +
		method('public onServiceDisconnected(Landroid/content/ComponentName;)V', 'return-void') +
		method('public execute(Ljava/lang/Runnable;)V', '
iget-object v0, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
invoke-virtual {v0, p1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void') +
		method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', '
iget v2, p0, Lorg/vinix/service/Main;->callbacks:I
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-nez v2, :executor
if-ne v0, v1, :bad
goto :identity
:executor
if-eq v0, v1, :bad
invoke-direct {p0}, Lorg/vinix/service/Main;->checkWorkerPriority()V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkAlarms()V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "service-executor"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
:identity
if-eqz p2, :bad
invoke-virtual {p1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.service.companion"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
if-nez v2, :passed
const/4 v0, 1
iput v0, p0, Lorg/vinix/service/Main;->callbacks:I
new-instance v0, Landroid/os/HandlerThread;
const-string v1, "service-executor"
invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Landroid/os/Handler;
invoke-direct {v1, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v1, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {p0, v0, v1, p0, p0}, Landroid/content/Context;->bindService(Landroid/content/Intent;ILjava/util/concurrent/Executor;Landroid/content/ServiceConnection;)Z
move-result v0
if-eqz v0, :bad
return-void
:passed
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion service binding callback"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('public run()V', '
invoke-direct {p0}, Lorg/vinix/service/Main;->checkPriorityIsolation()V
iget-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Companion service startup passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SERVICE-FIXTURE-PASS lazy-package-context application provider service constructor repeated-start bind-main-thread provider-context provider-resources attach-once bind-executor-thread component-package component-metadata component-missing package-data package-files package-preferences split-info-copy local-binder-interface local-binder-identity local-binder-transact local-binder-exception user-identity system-user uid-ranges parcel-binder-identity parcel-binder-copy parcel-binder-lifetime parcel-binder-callback custom-directory cache-directory directory-isolation directory-mode directory-name thread-priority priority-minus-one priority-errors priority-isolation priority-remote-tid uid-importance uid-listener-threshold uid-listener-thread uid-listener-registration"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'))!
	importance_listener(out + '/client/smali/org/vinix/service')!
	typed_parcel_classes(out + '/client/smali/org/vinix/service')!
	geofence_classes(out + '/client/smali/org/vinix/service')!
	alarm_classes(out + '/client/smali/org/vinix/service')!
	proxy_listener_class(out + '/client/smali/org/vinix/service')!
	os.write_file(client + 'DatabaseCallbacks.smali', '.class public Lorg/vinix/service/DatabaseCallbacks;\n.super Ljava/lang/Object;\n.implements Landroid/database/sqlite/SQLiteDatabase$CursorFactory;\n.implements Landroid/database/DatabaseErrorHandler;\n.field public static cursors:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public newCursor(Landroid/database/sqlite/SQLiteDatabase;Landroid/database/sqlite/SQLiteCursorDriver;Ljava/lang/String;Landroid/database/sqlite/SQLiteQuery;)Landroid/database/Cursor;', 'sget v0, Lorg/vinix/service/DatabaseCallbacks;->cursors:I\nadd-int/lit8 v0, v0, 1\nsput v0, Lorg/vinix/service/DatabaseCallbacks;->cursors:I\nnew-instance v0, Landroid/database/sqlite/SQLiteCursor;\ninvoke-direct {v0, p2, p3, p4}, Landroid/database/sqlite/SQLiteCursor;-><init>(Landroid/database/sqlite/SQLiteCursorDriver;Ljava/lang/String;Landroid/database/sqlite/SQLiteQuery;)V\nreturn-object v0') +
		method('public onCorruption(Landroid/database/sqlite/SQLiteDatabase;)V', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "unexpected database corruption"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'))!
	for name in ['client', 'companion'] {
		dir := out + '/' + name
		os.mkdir_all(dir + '/res/values')!
		os.write_file(dir + '/res/values/strings.xml', '<resources><string name="provider_owner">' + name + ' resource</string></resources>')!
		checked([aapt, 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])
		service_process := if name == 'client' { 'org.vinix.service.global' } else { ':service' }
		components := '<service android:name="org.vinix.service.Worker" android:process="' + service_process + '" android:exported="true"><meta-data android:name="owner" android:value="' + name + '"/></service><provider android:name="org.vinix.service.Provider" android:authorities="fixture.service.' + name + '"><meta-data android:name="owner" android:value="' + name + '"/></provider>'
		application := if name == 'client' {
			'<application android:label="Service fixture"><activity android:name="org.vinix.service.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>' + components + '</application>'
		} else {
			'<application android:name="org.vinix.service.App" android:process=":worker" android:label="Companion fixture">' + components + '</application>'
		}
		os.write_file(dir + '/AndroidManifest.xml', '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.service.' + name + '" android:versionCode="1"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>' + application + '</manifest>')!
		checked([aapt, 'link', '-I', resources, dir + '/resources.zip', '--manifest', dir + '/AndroidManifest.xml', '-o',
			dir + '/unsigned.apk'])
		checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', dir + '/smali', '-o',
			dir + '/classes.dex'])
		checked(['zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
		checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
			'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
			dir + '/probe.apk', dir + '/unsigned.apk'])
	}
	println('SERVICE-FIXTURE-APKS ' + out)
}
