// SPDX-License-Identifier: GPL-2.0-or-later
// No-provider location contracts, including two real main-queue callback drains.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/LocationProviderProbe;'
const manager = 'Landroid/location/LocationManager;'
const callback = 'Lorg/vinix/bootstrap/RecordingGnssCallback;'
const listener = 'Lorg/vinix/bootstrap/RecordingLocationListener;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-LOCATION-PROVIDER-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn zero(actual string, label string) string {
	return 'const-string v4, "${label}"\ninvoke-static {${actual}, v4}, ${probe}->zero(ILjava/lang/String;)V\n'
}

fn nonzero(actual string, label string) string {
	return 'const-string v4, "${label}"\ninvoke-static {${actual}, v4}, ${probe}->nonzero(ILjava/lang/String;)V\n'
}

fn null_value(actual string, label string) string {
	return 'const-string v4, "${label}"\ninvoke-static {${actual}, v4}, ${probe}->nullValue(Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn exception_test(name string, body string, exception string, label string, locals int) string {
	return method('private static ${name}(${manager})V', ':try_start\n' + body +
		'\n:try_end\ngoto :bad\n.catch ${exception} {:try_start .. :try_end} :caught\n' +
		':caught\nmove-exception v0\nreturn-void\n:bad\nconst-string v0, "${label}"\n' +
		'invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\nreturn-void', locals)
}

fn helpers() string {
	mut s := method('public static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 1)
	s += method('private static zero(ILjava/lang/String;)V', '
if-eqz p0, :ok
invoke-static {p1}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static nonzero(ILjava/lang/String;)V', '
if-nez p0, :ok
invoke-static {p1}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static nullValue(Ljava/lang/Object;Ljava/lang/String;)V', '
if-eqz p0, :ok
invoke-static {p1}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static mainThread()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
if-nez v0, :ok
:bad
const-string v0, "probe must execute on the live main Looper"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 2)
	s += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :good
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
const-string v0, "trace variables must be absent"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-PASS') + 'return-void', 3)
	// Inject entries into the legacy set to verify release without clearing an
	// unrelated listener. Rejected requests must never populate this set.
	s += method('private static legacyListeners()Ljava/util/Set;', '
const-class v0, ${manager}
const-string v1, "listeners"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/AccessibleObject;->setAccessible(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/util/Set;
return-object v0', 2)
	return s
}

fn discovery() string {
	mut b := '
invoke-virtual {p0}, ${manager}->isLocationEnabled()Z
move-result v0
' + zero('v0', 'no providers means location disabled') + '
invoke-virtual {p0}, ${manager}->getAllProviders()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v0
' + zero('v0', 'no providers advertised')
	for enabled in [0, 1] {
		b += '\nconst/4 v1, ${enabled}\ninvoke-virtual {p0, v1}, ${manager}->getProviders(Z)Ljava/util/List;\nmove-result-object v0\n' +
			'invoke-interface {v0}, Ljava/util/List;->size()I\nmove-result v0\n' +
			zero('v0', 'filtered provider list stays empty') +
			'new-instance v2, Landroid/location/Criteria;\ninvoke-direct {v2}, Landroid/location/Criteria;-><init>()V\n' +
			'invoke-virtual {p0, v2, v1}, ${manager}->getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;\nmove-result-object v0\n' +
			null_value('v0', 'valid criteria cannot select absent provider')
	}
	for name in ['gps', 'network', 'passive', 'xdgportal', 'missing-provider', ''] {
		b += '\nconst-string v1, "${name}"\ninvoke-virtual {p0, v1}, ${manager}->isProviderEnabled(Ljava/lang/String;)Z\nmove-result v0\n' +
			zero('v0', 'absent provider disabled: ${name}') +
			'invoke-virtual {p0, v1}, ${manager}->getLastKnownLocation(Ljava/lang/String;)Landroid/location/Location;\nmove-result-object v0\n' +
			null_value('v0', 'absent provider has no last location: ${name}')
	}
	b += 'invoke-static {p0}, ${probe}->nullEnabled(${manager})V\n' +
		'invoke-static {p0}, ${probe}->nullLastKnown(${manager})V\n' +
		'invoke-static {p0}, ${probe}->nullCriteriaDisabled(${manager})V\n' +
		'invoke-static {p0}, ${probe}->nullCriteriaEnabled(${manager})V\n' +
		marker('DISCOVERY-PASS') + 'return-void'
	mut s := method('private static discovery(${manager})V', b, 5)
	s += exception_test('nullEnabled', 'const/4 v0, 0\ninvoke-virtual {p0, v0}, ${manager}->isProviderEnabled(Ljava/lang/String;)Z',
		'Ljava/lang/IllegalArgumentException;', 'null provider must be rejected by isProviderEnabled', 1)
	s += exception_test('nullLastKnown', 'const/4 v0, 0\ninvoke-virtual {p0, v0}, ${manager}->getLastKnownLocation(Ljava/lang/String;)Landroid/location/Location;',
		'Ljava/lang/IllegalArgumentException;', 'null provider must be rejected by getLastKnownLocation', 1)
	for name, flag in {
		'nullCriteriaDisabled': 0
		'nullCriteriaEnabled':  1
	} {
		s += exception_test(name, 'const/4 v0, 0\nconst/4 v1, ${flag}\ninvoke-virtual {p0, v0, v1}, ${manager}->getBestProvider(Landroid/location/Criteria;Z)Ljava/lang/String;',
			'Ljava/lang/IllegalArgumentException;', 'null criteria must be rejected by getBestProvider', 2)
	}
	return s
}

fn requests() string {
	mut s := method('private static rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V', '
move-object v0, p0
move-object v1, p1
const-wide/16 v2, 0
const/4 v4, 0
move-object v5, p2
:try_start
invoke-virtual/range {v0 .. v5}, ${manager}->requestLocationUpdates(Ljava/lang/String;JFLandroid/location/LocationListener;)V
:try_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:try_start .. :try_end} :caught
:caught
move-exception v0
invoke-static {}, ${probe}->legacyListeners()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->size()I
move-result v0
if-nez v0, :retained
return-void
:retained
const-string v0, "rejected request retained a listener"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:bad
const-string v0, "absent provider or null listener request must throw IllegalArgumentException"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void', 6)
	mut b := '
invoke-static {}, ${probe}->legacyListeners()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->size()I
move-result v0
' + zero('v0', 'fresh location listener registry must be empty') + '
new-instance v2, ${listener}
invoke-direct {v2}, ${listener}-><init>()V
'
	for name in ['gps', 'network', 'passive', 'xdgportal', 'missing-provider', ''] {
		b += 'const-string v1, "${name}"\ninvoke-static {p0, v1, v2}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V\n'
	}
	b += 'const/4 v1, 0\ninvoke-static {p0, v1, v2}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V\n' +
		'const-string v1, "gps"\nconst/4 v2, 0\ninvoke-static {p0, v1, v2}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V\n' +
		'const/4 v1, 0\ninvoke-static {p0, v1, v2}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V\n' +
		'invoke-static {}, ${probe}->runWorker()V\n' +
		marker('REQUESTS-PASS') + 'return-void'
	s += method('private static requests(${manager})V', b, 5)
	return s
}

fn removal() string {
	b := '
invoke-static {}, ${probe}->legacyListeners()Ljava/util/Set;
move-result-object v1
new-instance v2, ${listener}
invoke-direct {v2}, ${listener}-><init>()V
new-instance v3, ${listener}
invoke-direct {v3}, ${listener}-><init>()V
invoke-interface {v1, v2}, Ljava/util/Set;->add(Ljava/lang/Object;)Z
move-result v0
' + nonzero('v0', 'first injected listener must be distinct') + '
invoke-interface {v1, v3}, Ljava/util/Set;->add(Ljava/lang/Object;)Z
move-result v0
' + nonzero('v0', 'second injected listener must be distinct') + '
invoke-virtual {p0, v2}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V
invoke-interface {v1, v2}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z
move-result v0
' + zero('v0', 'removeUpdates must release retained listener') + '
invoke-interface {v1, v3}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z
move-result v0
' + nonzero('v0', 'removal must preserve other retained listener') + '
invoke-interface {v1}, Ljava/util/Set;->size()I
move-result v0
const/4 v4, 1
if-eq v0, v4, :one_left
const-string v0, "exactly one retained listener must remain"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:one_left
invoke-virtual {p0, v2}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V
invoke-interface {v1, v3}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z
move-result v0
' + nonzero('v0', 'repeated removal must preserve other listener') + '
invoke-virtual {p0, v3}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V
invoke-virtual {p0, v3}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V
invoke-interface {v1}, Ljava/util/Set;->size()I
move-result v0
' + zero('v0', 'all retained listeners must be released') + '
new-instance v0, ${listener}
invoke-direct {v0}, ${listener}-><init>()V
invoke-virtual {p0, v0}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V
invoke-static {p0}, ${probe}->nullRemove(${manager})V
' + marker('REMOVAL-PASS') + 'return-void'
	return method('private static removal(${manager})V', b, 5) +
		exception_test('nullRemove', 'const/4 v0, 0\ninvoke-virtual {p0, v0}, ${manager}->removeUpdates(Landroid/location/LocationListener;)V',
			'Ljava/lang/IllegalArgumentException;', 'null listener removal must throw IllegalArgumentException', 1)
}

fn commands() string {
	mut b := 'const/4 v2, 0\nconst/4 v3, 0\n'
	for name in ['gps', 'network', 'passive', 'xdgportal', 'missing-provider', ''] {
		b += 'const-string v1, "${name}"\ninvoke-virtual {p0, v1, v2, v3}, ${manager}->sendExtraCommand(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Z\nmove-result v0\n' +
			nonzero('v0', 'nonnull provider command retains compatibility return value')
	}
	b += 'const-string v1, "gps"\nconst-string v2, "delete_aiding_data"\nnew-instance v3, Landroid/os/Bundle;\ninvoke-direct {v3}, Landroid/os/Bundle;-><init>()V\n' +
		'const-string v0, "unchanged"\nconst-string v4, "sentinel"\ninvoke-virtual {v3, v0, v4}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n' +
		'invoke-virtual {p0, v1, v2, v3}, ${manager}->sendExtraCommand(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Z\nmove-result v0\n' +
		nonzero('v0', 'populated command retains compatibility return value') +
		'const-string v1, "unchanged"\ninvoke-virtual {v3, v1}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\n' +
		'const-string v1, "sentinel"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\n' +
		nonzero('v0', 'absent provider must preserve command bundle sentinel') +
		'invoke-virtual {v3}, Landroid/os/Bundle;->size()I\nmove-result v0\nconst/4 v1, 1\nif-eq v0, v1, :bundle_unchanged\n' +
		'const-string v0, "absent provider must not add or remove command bundle values"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\n:bundle_unchanged\n' +
		'invoke-static {p0}, ${probe}->nullCommandProvider(${manager})V\n' +
		marker('COMMANDS-PASS') + 'return-void'
	return method('private static commands(${manager})V', b, 5) +
		exception_test('nullCommandProvider', 'const/4 v0, 0\ninvoke-virtual {p0, v0, v0, v0}, ${manager}->sendExtraCommand(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Z',
			'Ljava/lang/NullPointerException;', 'null command provider must throw NullPointerException', 1)
}

fn worker() string {
	mut s := method('public static worker()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
' + null_value('v0', 'fresh worker must have no Looper') + '
sget-object v0, ${probe}->manager:${manager}
new-instance v1, ${callback}
invoke-direct {v1}, ${callback}-><init>()V
const/4 v2, 0
:gnss_try
invoke-virtual {v0, v1, v2}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
:gnss_end
goto :bad_gnss
.catch Ljava/lang/NullPointerException; {:gnss_try .. :gnss_end} :gnss_caught
:gnss_caught
move-exception v0
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
const-class v1, Ljava/lang/NullPointerException;
if-ne v0, v1, :bad_gnss
sget-object v0, ${probe}->manager:${manager}
new-instance v1, ${callback}
invoke-direct {v1}, ${callback}-><init>()V
sget-object v2, ${probe}->handler:Landroid/os/Handler;
invoke-virtual {v0, v1, v2}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v0
' + zero('v0', 'SDK29 supplied handler permits no-Looper GNSS attempt but absent provider rejects it') + '
sget-object v0, ${probe}->manager:${manager}
const-string v1, "gps"
const-wide/16 v2, 0
const/4 v4, 0
new-instance v5, ${listener}
invoke-direct {v5}, ${listener}-><init>()V
:request_try
invoke-virtual/range {v0 .. v5}, ${manager}->requestLocationUpdates(Ljava/lang/String;JFLandroid/location/LocationListener;)V
:request_end
goto :bad_request
.catch Ljava/lang/RuntimeException; {:request_try .. :request_end} :request_caught
:request_caught
move-exception v0
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
const-class v1, Ljava/lang/RuntimeException;
if-ne v0, v1, :bad_request
sget-object v0, ${probe}->manager:${manager}
const/4 v1, 0
invoke-static {v0, v1, v5}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V
const-string v1, "gps"
const/4 v2, 0
invoke-static {v0, v1, v2}, ${probe}->rejected(${manager}Ljava/lang/String;Landroid/location/LocationListener;)V
invoke-static {}, ${probe}->legacyListeners()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->size()I
move-result v0
' + zero('v0', 'no-Looper request must not retain listener') + '
const/4 v0, 1
sput-boolean v0, ${probe}->workerDone:Z
return-void
:bad_gnss
const-string v0, "null-handler GNSS registration without Looper must throw exact NullPointerException"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:bad_request
const-string v0, "valid listener request without Looper must throw exact RuntimeException"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void', 6)
	s += method('private static runWorker()V', '
new-instance v0, Lorg/vinix/bootstrap/NoLooperWorker;
invoke-direct {v0}, Lorg/vinix/bootstrap/NoLooperWorker;-><init>()V
new-instance v1, Ljava/lang/Thread;
const-string v2, "location-no-looper"
invoke-direct {v1, v0, v2}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
const-wide/16 v2, 5000
invoke-virtual {v1, v2, v3}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v1}, Ljava/lang/Thread;->isAlive()Z
move-result v0
' + zero('v0', 'no-Looper worker must finish within five seconds') + '
sget-boolean v0, ${probe}->workerDone:Z
' + nonzero('v0', 'no-Looper worker must complete all exception checks') + '
return-void', 5)
	return s
}

fn asynchronous() string {
	mut s := method('private static registrationResults()V', '
sget-boolean v0, ${probe}->handlerResult:Z
' + zero('v0', 'SDK29 absent GNSS provider cannot register supplied-handler callback') + '
sget-boolean v0, ${probe}->repeatedResult:Z
' + zero('v0', 'SDK29 absent GNSS provider cannot register repeated callback') + '
sget-boolean v0, ${probe}->nullHandlerResult:Z
' + zero('v0', 'SDK29 absent GNSS provider cannot register current-Looper callback') + '
sget-boolean v0, ${probe}->nullCallbackResult:Z
' + zero('v0', 'SDK29 absent GNSS provider cannot register null callback') + '
sget-boolean v0, ${probe}->nullArgumentsResult:Z
' + zero('v0', 'SDK29 absent GNSS provider cannot register null callback and handler') + '
return-void', 5)
	s += method('public static sentinel()V', '
invoke-static {}, ${probe}->mainThread()V
sget v0, ${probe}->sentinelCount:I
add-int/lit8 v0, v0, 1
sput v0, ${probe}->sentinelCount:I
return-void', 1)
	s += method('private static schedule(Ljava/lang/Runnable;)V', '
sget v4, ${probe}->sentinelCount:I
new-instance v0, Lorg/vinix/bootstrap/QueueSentinel;
invoke-direct {v0}, Lorg/vinix/bootstrap/QueueSentinel;-><init>()V
sget-object v5, ${probe}->handler:Landroid/os/Handler;
invoke-virtual {v5, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
const-string v1, "main queue sentinel was rejected"
invoke-static {v0, v1}, ${probe}->nonzero(ILjava/lang/String;)V
sget v0, ${probe}->sentinelCount:I
if-eq v0, v4, :queued
const-string v0, "Handler.post dispatched inline"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:queued
const-wide/16 v0, 200
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v2
add-long/2addr v2, v0
sput-wide v2, ${probe}->completeDue:J
invoke-virtual {v5, p0, v0, v1}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
const-string v1, "delayed no-callback check was rejected"
invoke-static {v0, v1}, ${probe}->nonzero(ILjava/lang/String;)V
return-void', 6)
	s += method('private static gate(I)V', '
invoke-static {}, ${probe}->mainThread()V
sget-boolean v0, ${probe}->completed:Z
' + zero('v0', 'queue gate must precede completion') + '
sget v0, ${probe}->sentinelCount:I
if-eq v0, p0, :sentinel_ran
const-string v0, "main queue sentinel must precede each delayed gate exactly once"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:sentinel_ran
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
sget-wide v2, ${probe}->completeDue:J
cmp-long v0, v0, v2
if-gez v0, :due
const-string v0, "asynchronous callback observation delay was skipped"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:due
sget v0, ${probe}->gnssEvents:I
' + zero('v0', 'absent GNSS provider delivered a callback') + '
sget v0, ${probe}->locationEvents:I
' + zero('v0', 'rejected requests delivered a location callback') + '
return-void', 5)
	s += method('public static phaseGate()V', '
const/4 v0, 1
invoke-static {v0}, ${probe}->gate(I)V
sget-object v2, ${probe}->manager:${manager}
invoke-static {v2}, ${probe}->discovery(${manager})V
invoke-static {v2}, ${probe}->requests(${manager})V
invoke-static {v2}, ${probe}->removal(${manager})V
invoke-static {v2}, ${probe}->commands(${manager})V
sget-object v0, ${probe}->active:${callback}
invoke-virtual {v2, v0}, ${manager}->unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V
invoke-virtual {v2, v0}, ${manager}->unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V
sget-object v0, ${probe}->removed:${callback}
invoke-virtual {v2, v0}, ${manager}->unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V
const/4 v0, 0
sget-object v1, ${probe}->handler:Landroid/os/Handler;
invoke-virtual {v2, v0, v1}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v1
sput-boolean v1, ${probe}->nullCallbackResult:Z
invoke-virtual {v2, v0, v0}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v1
sput-boolean v1, ${probe}->nullArgumentsResult:Z
invoke-virtual {v2, v0}, ${manager}->unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V
new-instance v0, Lorg/vinix/bootstrap/DelayedComplete;
invoke-direct {v0}, Lorg/vinix/bootstrap/DelayedComplete;-><init>()V
invoke-static {v0}, ${probe}->schedule(Ljava/lang/Runnable;)V
return-void', 3)
	s += method('public static complete()V', '
const/4 v0, 2
invoke-static {v0}, ${probe}->gate(I)V
invoke-static {}, ${probe}->registrationResults()V
const/4 v0, 1
sput-boolean v0, ${probe}->completed:Z
sget-object v0, ${probe}->view:Landroid/widget/TextView;
const-string v1, "No-provider location fixture passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
' + marker('ASYNC-PASS') + marker('PASS') + '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 2)
	return s
}

fn begin() string {
	b := '
invoke-static {}, ${probe}->traceAbsent()V
invoke-static {}, ${probe}->mainThread()V
sget v0, Landroid/os/Build$VERSION;->SDK_INT:I
invoke-static {v0}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;
move-result-object v2
const-string v1, "BOOTSTRAP-LOCATION-PROVIDER-SDK-"
invoke-virtual {v1, v2}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
sget-object v2, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v2, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/16 v1, 29
if-eq v0, v1, :sdk29
const-string v0, "location fixture requires actual SDK_INT 29"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:sdk29
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Checking no-provider location contracts"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
sput-object v0, ${probe}->view:Landroid/widget/TextView;
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const-string v0, "location"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
check-cast v2, ${manager}
sput-object v2, ${probe}->manager:${manager}
if-nez v2, :manager_ready
const-string v0, "location manager service missing"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:manager_ready
new-instance v5, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-direct {v5, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
sput-object v5, ${probe}->handler:Landroid/os/Handler;
new-instance v3, ${callback}
invoke-direct {v3}, ${callback}-><init>()V
sput-object v3, ${probe}->active:${callback}
' + marker('CALL') + '
invoke-virtual {v2, v3, v5}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v0
sput-boolean v0, ${probe}->handlerResult:Z
invoke-virtual {v2, v3, v5}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v0
sput-boolean v0, ${probe}->repeatedResult:Z
new-instance v4, ${callback}
invoke-direct {v4}, ${callback}-><init>()V
sput-object v4, ${probe}->removed:${callback}
const/4 v1, 0
invoke-virtual {v2, v4, v1}, ${manager}->registerGnssStatusCallback(Landroid/location/GnssStatus$Callback;Landroid/os/Handler;)Z
move-result v0
sput-boolean v0, ${probe}->nullHandlerResult:Z
invoke-virtual {v2, v4}, ${manager}->unregisterGnssStatusCallback(Landroid/location/GnssStatus$Callback;)V
new-instance v0, Lorg/vinix/bootstrap/PhaseGate;
invoke-direct {v0}, Lorg/vinix/bootstrap/PhaseGate;-><init>()V
invoke-static {v0}, ${probe}->schedule(Ljava/lang/Runnable;)V
return-void'
	return method('public static begin(Landroid/app/Activity;)V', b, 6)
}

fn probe_class() string {
	return '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		'.field public static gnssEvents:I\n.field public static locationEvents:I\n' +
		'.field private static sentinelCount:I\n.field private static completed:Z\n.field private static completeDue:J\n' +
		'.field private static view:Landroid/widget/TextView;\n.field private static manager:${manager}\n' +
		'.field private static handler:Landroid/os/Handler;\n.field private static active:${callback}\n.field private static removed:${callback}\n' +
		'.field private static handlerResult:Z\n.field private static repeatedResult:Z\n.field private static nullHandlerResult:Z\n' +
		'.field private static nullCallbackResult:Z\n.field private static nullArgumentsResult:Z\n' +
		'.field private static volatile workerDone:Z\n' +
		helpers() + discovery() + requests() + removal() + commands() + worker() + asynchronous() + begin()
}

fn recording_classes() map[string]string {
	mut gnss := '.class public ${callback}\n.super Landroid/location/GnssStatus$Callback;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/location/GnssStatus$Callback;-><init>()V\nreturn-void', 0)
	for signature in ['onStarted()V', 'onStopped()V', 'onFirstFix(I)V',
		'onSatelliteStatusChanged(Landroid/location/GnssStatus;)V'] {
		gnss += method('public ' + signature, 'sget v0, ${probe}->gnssEvents:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${probe}->gnssEvents:I\nreturn-void', 1)
	}
	mut location := '.class public ${listener}\n.super Ljava/lang/Object;\n.implements Landroid/location/LocationListener;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0)
	for signature in ['onLocationChanged(Landroid/location/Location;)V',
		'onStatusChanged(Ljava/lang/String;ILandroid/os/Bundle;)V',
		'onProviderEnabled(Ljava/lang/String;)V', 'onProviderDisabled(Ljava/lang/String;)V'] {
		location += method('public ' + signature, 'sget v0, ${probe}->locationEvents:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${probe}->locationEvents:I\nreturn-void', 1)
	}
	mut classes := {
		'RecordingGnssCallback':     gnss
		'RecordingLocationListener': location
	}
	for name, target in {
		'QueueSentinel':   'sentinel'
		'PhaseGate':       'phaseGate'
		'DelayedComplete': 'complete'
		'NoLooperWorker':  'worker'
	} {
		classes[name] = '.class public Lorg/vinix/bootstrap/${name};\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
			method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0) +
			method('public run()V', ':try_start\ninvoke-static {}, ${probe}->${target}()V\n:try_end\nreturn-void\n' +
				'.catchall {:try_start .. :try_end} :failed\n:failed\nmove-exception v0\n' +
				'invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V\nconst/4 v1, 1\n' +
				'invoke-static {v1}, Ljava/lang/System;->exit(I)V\nthrow v0', 2)
	}
	return classes
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\ninvoke-static {p0}, ${probe}->begin(Landroid/app/Activity;)V\nreturn-void', 0)
}

fn file_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({
		'argv':             json2.Any(args)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	}, prettify: true) + '\n')!
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">No-provider location fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/><uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/><uses-permission android:name="android.permission.ACCESS_LOCATION_EXTRA_COMMANDS"/><application android:label="No-provider location fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/LocationProviderProbe.smali', probe_class())!
	for name, value in recording_classes() {
		os.write_file(root + '/${name}.smali', value)!
	}
	tools := os.getenv('LOCATION_PROVIDER_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' {
		os.abs_path('build/android-native-ws/aapt2')
	} else {
		tools + '/aapt2'
	}
	signer := if tools == '' {
		os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar')
	} else {
		tools + '/apksigner.jar'
	}
	framework := if tools == '' {
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	} else {
		tools + '/framework-res.apk'
	}
	smali := if tools == '' {
		os.abs_path('build/android-framework/tools')
	} else {
		tools + '/smali'
	}
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] {
		pins[path] = file_hash(path)!
	}
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! }
	}
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali',
		'-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix no-provider location fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('LOCATION-PROVIDER-APK ' + file_hash(out + '/probe.apk')!)
}
