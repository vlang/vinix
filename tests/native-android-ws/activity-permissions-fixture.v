// SPDX-License-Identifier: GPL-2.0-or-later
// Emit permission probes for the combined child-order/permissions APK326.
module main

import crypto.sha256
import json2
import os

const probe = 'Lorg/vinix/bootstrap/PermissionProbe;'
const main_activity = 'Lorg/vinix/bootstrap/Main;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-PERMISSIONS-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn equal(actual string, expected string, label string) string {
	return 'const-string v6, "${label}"\ninvoke-static {${actual}, ${expected}, v6}, ${probe}->equal(IILjava/lang/String;)V\n'
}

fn text(actual string, expected string, label string) string {
	return 'const-string v6, "${label}"\ninvoke-static {${actual}, ${expected}, v6}, ${probe}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn helpers() string {
	mut s := method('public static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 1)
	s += method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 0)
	s += method('private static text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', '
if-eqz p0, :bad
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
:bad
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 1)
	s += method('private static mainThread()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
if-nez v0, :ok
:bad
const-string v0, "permission callback requires live main Looper"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void', 2)
	return s
}

fn environment() string {
	return method('private static environment()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :location
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
const-string v0, "trace variables must be absent"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:location
const-string v0, "ATL_UGLY_ENABLE_LOCATION"
invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
if-eqz v0, :good
const-string v0, "location override must be absent"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-PASS') + 'return-void', 3)
}

fn check_first() string {
	mut b := '
if-eqz p0, :bad
if-eqz p1, :bad
array-length v1, p0
const/4 v2, 4
' + equal('v1', 'v2', 'permission names preserve length') + '
array-length v1, p1
' + equal('v1', 'v2', 'grant results parallel permissions') + '
sget-object v1, ${probe}->input:[Ljava/lang/String;
if-ne p0, v1, :snapshot
:bad
const-string v0, "permission arrays must be non-null snapshots"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:snapshot
const/4 v2, 0
aget-object v1, v1, v2
const-string v2, "android.permission.ACCESS_FINE_LOCATION"
' + text('v1', 'v2', 'caller mutation took effect')
	for i, permission in ['WRITE_EXTERNAL_STORAGE', 'ACCESS_FINE_LOCATION', 'READ_EXTERNAL_STORAGE',
		'ACCESS_COARSE_LOCATION'] {
		b += '\nconst/4 v3, ${i}\naget-object v1, p0, v3\nconst-string v2, "android.permission.${permission}"\n' +
			text('v1', 'v2', 'original permission ${i} survives caller mutation') +
			'aget v1, p1, v3\nconst/4 v2, ${if i % 2 == 0 { '0' } else { '-1' }}\n' +
			equal('v1', 'v2', 'existing PM decision ${i} retained')
	}
	b += '\nreturn-void'
	return method('private static checkFirst([Ljava/lang/String;[I)V', b, 7)
}

fn start() string {
	mut b := '
invoke-static {}, ${probe}->environment()V
invoke-static {}, ${probe}->mainThread()V
sput-object p0, ${probe}->owner:Landroid/app/Activity;
const/4 v0, 4
new-array v3, v0, [Ljava/lang/String;
sput-object v3, ${probe}->input:[Ljava/lang/String;
'
	for i, permission in ['WRITE_EXTERNAL_STORAGE', 'ACCESS_FINE_LOCATION', 'READ_EXTERNAL_STORAGE',
		'ACCESS_COARSE_LOCATION'] {
		b += 'const/4 v0, ${i}\nconst-string v1, "android.permission.${permission}"\naput-object v1, v3, v0\ninvoke-virtual {p0, v1}, Landroid/app/Activity;->checkSelfPermission(Ljava/lang/String;)I\nmove-result v1\nconst/4 v2, ${if i % 2 == 0 {
			'0'
		} else {
			'-1'
		}}\n' + equal('v1', 'v2', 'existing PM policy ${i}')
	}
	b += marker('POLICY-PASS') + marker('CALL') + '
const/16 v0, 0x1234
invoke-virtual {p0, v3, v0}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
sget v1, ${probe}->normalCount:I
const/4 v2, 0
' + equal('v1', 'v2', 'normal callback must not be inline') + '
const-string v1, "android.permission.ACCESS_FINE_LOCATION"
const/4 v0, 0
aput-object v1, v3, v0
const/4 v0, 1
sput-boolean v0, ${probe}->returned:Z
sput-boolean v0, ${probe}->inlineOverlap:Z
const/4 v1, 0
const/16 v2, 0x2345
invoke-virtual {p0, v1, v2}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
const/4 v0, 0
sput-boolean v0, ${probe}->inlineOverlap:Z
new-instance v3, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-direct {v3, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v4, Lorg/vinix/bootstrap/PermissionCompletion;
invoke-direct {v4}, Lorg/vinix/bootstrap/PermissionCompletion;-><init>()V
const-wide/16 v0, 2000
invoke-virtual {v3, v4, v0, v1}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v1
const/4 v2, 1
' + equal('v1', 'v2', 'deadline must be scheduled') + 'return-void'
	return method('public static start(Landroid/app/Activity;)V', b, 7)
}

fn result() string {
	return method('public static result(I[Ljava/lang/String;[I)V', '
invoke-static {}, ${probe}->mainThread()V
const/16 v0, 0x1234
if-ne p0, v0, :second
invoke-static {p1, p2}, ${probe}->first([Ljava/lang/String;[I)V
return-void
:second
const/16 v0, 0x3456
if-ne p0, v0, :overlap
invoke-static {p1, p2}, ${probe}->second([Ljava/lang/String;[I)V
return-void
:overlap
sget v0, ${probe}->overlapCount:I
if-eqz v0, :code0
const/4 v1, 1
if-eq v0, v1, :code1
const/4 v1, 2
if-eq v0, v1, :code2
goto :bad
:code0
const/16 v1, 0x2345
goto :arrays
:code1
const/16 v1, 0x4567
goto :arrays
:code2
const/16 v1, 0x5678
:arrays
if-ne p0, v1, :bad
if-eqz p1, :bad
if-eqz p2, :bad
array-length v1, p1
if-nez v1, :bad
array-length v1, p2
if-nez v1, :bad
sget-boolean v1, ${probe}->inlineOverlap:Z
if-eqz v1, :bad
add-int/lit8 v0, v0, 1
sput v0, ${probe}->overlapCount:I
return-void
:bad
const-string v0, "overlap must cancel immediately with matching code and empty arrays"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void', 3)
}

fn invalid() string {
	return method('private static invalid(Landroid/app/Activity;I)V', '
const/4 v0, 0
const/16 v1, 0x72
const-string v2, "permission cannot be null or empty"
if-eqz p1, :call
const/4 v3, 1
if-ne p1, v3, :negative
const/4 v0, 0
new-array v0, v0, [Ljava/lang/String;
goto :call
:negative
const/4 v1, -1
const-string v2, "requestCode should be >= 0"
:call
:try_start
invoke-virtual {p0, v0, v1}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
:try_end
const-string v0, "invalid permission request did not throw"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:caught
move-exception v0
invoke-virtual {v0}, Ljava/lang/IllegalArgumentException;->getMessage()Ljava/lang/String;
move-result-object v1
const-string v0, "AOSP validation order and message"
invoke-static {v1, v2, v0}, ${probe}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
return-void
.catch Ljava/lang/IllegalArgumentException; {:try_start .. :try_end} :caught', 4)
}

fn first() string {
	return method('private static first([Ljava/lang/String;[I)V', '
sget v1, ${probe}->normalCount:I
const/4 v2, 0
' + equal('v1', 'v2', 'first normal callback occurs once') + '
sget-boolean v1, ${probe}->returned:Z
const/4 v2, 1
' + equal('v1', 'v2', 'normal callback follows request return') + '
sget-boolean v1, ${probe}->inReentrant:Z
const/4 v2, 0
' + equal('v1', 'v2', 'first callback not during reentrant request') + '
invoke-static {p0, p1}, ${probe}->checkFirst([Ljava/lang/String;[I)V
sput-object p1, ${probe}->firstResults:[I
const/4 v0, 1
sput v0, ${probe}->normalCount:I
sget v1, ${probe}->overlapCount:I
const/4 v2, 1
' + equal('v1', 'v2', 'first overlap cancellation delivered') + marker('RESULTS-PASS') +
		marker('SNAPSHOT-PASS') + marker('MAIN-ASYNC-PASS') + '
new-instance v3, Lorg/vinix/bootstrap/PermissionBaseActivity;
invoke-direct {v3}, Lorg/vinix/bootstrap/PermissionBaseActivity;-><init>()V
const/4 v0, 0
new-array v1, v0, [Ljava/lang/String;
new-array v2, v0, [I
invoke-virtual {v3, v0, v1, v2}, Lorg/vinix/bootstrap/PermissionBaseActivity;->onRequestPermissionsResult(I[Ljava/lang/String;[I)V
' + marker('BASE-PASS') + '
sget-object v3, ${probe}->owner:Landroid/app/Activity;
const/4 v0, 0
invoke-static {v3, v0}, ${probe}->invalid(Landroid/app/Activity;I)V
const/4 v0, 1
invoke-static {v3, v0}, ${probe}->invalid(Landroid/app/Activity;I)V
const/4 v0, 2
invoke-static {v3, v0}, ${probe}->invalid(Landroid/app/Activity;I)V
new-array v4, v0, [Ljava/lang/String;
const/4 v0, 0
const-string v1, "android.permission.ACCESS_COARSE_LOCATION"
aput-object v1, v4, v0
const/4 v0, 1
const-string v1, "android.permission.WRITE_EXTERNAL_STORAGE"
aput-object v1, v4, v0
sput-boolean v0, ${probe}->inReentrant:Z
const/16 v0, 0x3456
invoke-virtual {v3, v4, v0}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
sget v1, ${probe}->normalCount:I
const/4 v2, 1
' + equal('v1', 'v2', 'reentrant request queues its result') + '
const/4 v0, 0
sput-boolean v0, ${probe}->inReentrant:Z
const/4 v0, 2
invoke-static {v3, v0}, ${probe}->invalid(Landroid/app/Activity;I)V
const/4 v0, 1
sput-boolean v0, ${probe}->inlineOverlap:Z
const/4 v1, 0
const/16 v2, 0x4567
invoke-virtual {v3, v1, v2}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
const/4 v0, 0
new-array v1, v0, [Ljava/lang/String;
const/16 v2, 0x5678
invoke-virtual {v3, v1, v2}, Landroid/app/Activity;->requestPermissions([Ljava/lang/String;I)V
const/4 v0, 0
sput-boolean v0, ${probe}->inlineOverlap:Z
const/16 v1, 77
aput v1, p1, v0
' + marker('VALIDATION-PASS') + 'return-void', 7)
}

fn second() string {
	mut b := '
sget v1, ${probe}->normalCount:I
const/4 v2, 1
' + equal('v1', 'v2', 'second normal callback follows first') + '
sget-boolean v1, ${probe}->inReentrant:Z
const/4 v2, 0
' + equal('v1', 'v2', 'reentrant callback is asynchronous') + '
if-eqz p0, :bad
if-eqz p1, :bad
sget-object v0, ${probe}->firstResults:[I
if-ne p1, v0, :arrays
:bad
const-string v0, "second request needs independent non-null arrays"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:arrays
array-length v1, p0
const/4 v2, 2
' + equal('v1', 'v2', 'second names length') + '
array-length v1, p1
' + equal('v1', 'v2', 'second results length')
	for i, permission in ['ACCESS_COARSE_LOCATION', 'WRITE_EXTERNAL_STORAGE'] {
		b += '\nconst/4 v3, ${i}\naget-object v1, p0, v3\nconst-string v2, "android.permission.${permission}"\n' + text('v1', 'v2', 'second permission ${i} preserves order') + 'aget v1, p1, v3\nconst/4 v2, ${if i == 0 {
			'-1'
		} else {
			'0'
		}}\n' + equal('v1', 'v2', 'second PM result ${i} independent of first array mutation')
	}
	b += '
sget v1, ${probe}->overlapCount:I
const/4 v2, 3
' + equal('v1', 'v2', 'all overlap cancellations delivered once') + '
const/4 v0, 2
sput v0, ${probe}->normalCount:I
' + marker('REENTRANT-PASS') + marker('OVERLAP-PASS') + '
sget-boolean v0, ${main_activity}->childPassed:Z
if-nez v0, :child_good
const-string v0, "child drawing order group did not pass"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:child_good
const/4 v0, 1
sput-boolean v0, ${probe}->complete:Z
' + marker('PASS') + '
invoke-static {}, ${main_activity}->fixturePassed()V
return-void'
	return method('private static second([Ljava/lang/String;[I)V', b, 7)
}

fn deadline() string {
	return method('public static deadline()V', '
sget-boolean v0, ${probe}->complete:Z
if-nez v0, :done
sget v0, ${probe}->normalCount:I
if-nez v0, :partial
' + marker('NO-CALLBACK') + '
const-string v0, "requestPermissions did not deliver callback"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:partial
const-string v0, "permission callbacks did not complete"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:done
return-void', 2)
}

fn main() {
	if os.args.len != 2 { panic('usage: activity-permissions-fixture FRESH_OUTPUT') }
	out := os.abs_path(os.args[1])
	assert !os.exists(out), 'output must be fresh: ${out}'
	root := os.join_path(out, 'org', 'vinix', 'bootstrap')
	os.mkdir_all(root) or { panic(err) }
	mut body := '.class public final ${probe}\n.super Ljava/lang/Object;\n'
	for field in ['owner:Landroid/app/Activity;', 'input:[Ljava/lang/String;', 'firstResults:[I',
		'normalCount:I', 'overlapCount:I', 'returned:Z', 'inReentrant:Z', 'inlineOverlap:Z',
		'complete:Z'] {
		body += '.field private static ${field}\n'
	}
	body += helpers() + environment() + check_first() + start() + result() + invalid() + first() + second() + deadline()
	base := '.class public final Lorg/vinix/bootstrap/PermissionBaseActivity;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	completion := '.class public final Lorg/vinix/bootstrap/PermissionCompletion;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0) + method('public run()V', '
:try_start
invoke-static {}, ${probe}->deadline()V
:try_end
return-void
:assertion
move-exception v0
invoke-virtual {v0}, Ljava/lang/AssertionError;->printStackTrace()V
const/4 v1, 1
invoke-static {v1}, Ljava/lang/System;->exit(I)V
throw v0
.catch Ljava/lang/AssertionError; {:try_start .. :try_end} :assertion', 2)
	mut hashes := map[string]string{}
	for name, source in {
		'PermissionProbe.smali':        body
		'PermissionBaseActivity.smali': base
		'PermissionCompletion.smali':   completion
	} {
		os.write_file(os.join_path(root, name), source) or { panic(err) }
		hashes['org/vinix/bootstrap/${name}'] = sha256.hexhash(source)
	}
	os.write_file(os.join_path(out, 'sources.json'), json2.encode(hashes) + '\n') or { panic(err) }
	println('PERMISSION-FIXTURE-EMITTED ${out}')
}
