// SPDX-License-Identifier: GPL-2.0-or-later
// Signed no-activity-monitor contract and virtual-dispatch ARM regression.
module main

import crypto.sha256
import json2
import os

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const worker_type = 'Lorg/vinix/bootstrap/Worker;'
const no_link_type = 'Lorg/vinix/bootstrap/NoLinkManager;'
const override_type = 'Lorg/vinix/bootstrap/OverrideManager;'
const manager_type = 'Landroid/net/ConnectivityManager;'
const active_signature = 'isDefaultNetworkActive()Z'
const pass_marker = 'DEFAULT-NETWORK-ACTIVE-PASS public-instance primitive-boolean no-monitor-active native-link-independent virtual-dispatch repeatable bounded-worker'
const fail_marker = 'DEFAULT-NETWORK-ACTIVE-FAIL'
const fixture_scope = 'Standalone aarch64 ConnectivityManager.isDefaultNetworkActive linkage and the Vinix no-activity-monitor policy. The actual Context connectivity service and a directly constructed framework ConnectivityManager return true. A fixture subclass makes both protected native link-state hooks throw, proving the inherited API does not poll those hooks. A separate false override is invoked through the framework receiver type to verify virtual dispatch. Sixteen repetitions run in each of two UI suites and one plain daemon-worker suite, with actual main-Looper and absent worker-Looper checks, bounded joins and cleanup preserving the primary failure. Reflection requires a public instance primitive-boolean method that is neither native nor final. No platform class stub, network mutation, callback registration, route or Internet assertion, radio power transition, GMS success or Maps rendering is supplied or inferred. ARM execution requires a separate receipt against the pinned SDK/native pair.'

struct CommandReceipt {
	argv []string
	status int
	output string
}

struct FixtureBuild {
	argv []string
	source_revision string
	inputs_sha256 map[string]string
	artifacts_sha256 map[string]string
	java_version string
	apk_sha256 string
	package_name string
	activity_name string
	pass_marker string
	fail_marker string
	scope string
}

fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn recorded(out string, name string, argv []string) !string {
	result := os.exec(argv)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{
		argv: argv, status: result.exit_code, output: result.output
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(name + ': ' + result.output) }
	return result.output
}

fn java_command(java string, args []string) []string {
	mut command := [java, '-Xmx256m', '-XX:ActiveProcessorCount=2']
	command << args
	return command
}

fn output_files(path string) ![]string {
	mut result := []string{}
	for name in os.ls(path)!.sorted() {
		item := path + '/' + name
		assert !os.is_link(item), 'unexpected output symlink'
		kind := os.lstat(item)!.get_filetype()
		if kind == .directory { result << output_files(item)! }
		else if kind == .regular { result << item }
		else { return error('unexpected output type: ' + item) }
	}
	return result
}

fn relative_files(path string) ![]string {
	return output_files(path)!.map(it.all_after(path + '/')).sorted()
}

fn regular_names(path string) ![]string {
	names := os.ls(path)!.sorted()
	for name in names {
		assert !os.is_link(path + '/' + name) && os.lstat(path + '/' + name)!.get_filetype() == .regular,
			'regular tool input required'
	}
	return names
}

fn manifest() string {
	return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1">' +
		'<uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/><application android:label="Default network activity fixture">' +
		'<activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
	mut source := ''
	for name in ['equal', 'same'] {
		types := if name == 'equal' { 'II' } else { 'Ljava/lang/Object;Ljava/lang/Object;' }
		source += method('private static ${name}(${types}Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
	}
	return source + method('private static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
if-eqz p0, :secondary
if-eq p0, p1, :primary
invoke-virtual {p0, p1}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:primary
return-object p0
:secondary
return-object p1') + method('private static arm()V', 3, '
const-string v0, "os.arch"
invoke-static {v0}, Ljava/lang/System;->getProperty(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "aarch64"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
const-string v2, "fixture must run in the actual aarch64 process"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {}, Landroid/os/Process;->is64Bit()Z
move-result v0
const-string v2, "fixture must run in the actual 64-bit process"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn shape_source() string {
	mut body := '
const-class v0, ${manager_type}
const-string v1, "isDefaultNetworkActive"
const/4 v2, 0
new-array v2, v2, [Ljava/lang/Class;
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;
move-result-object v1
const-class v2, ${manager_type}
const-string v4, "isDefaultNetworkActive must be declared on ConnectivityManager"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;
const-string v4, "isDefaultNetworkActive must return primitive boolean"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0'
	for name in ['isPublic', 'isStatic', 'isNative', 'isFinal'] {
		expected := if name == 'isPublic' { 1 } else { 0 }
		body += '
invoke-static {v0}, Ljava/lang/reflect/Modifier;->${name}(I)Z
move-result v1
const/4 v2, ${expected}
const-string v4, "isDefaultNetworkActive modifier ${name}"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V'
	}
	return method('private static shape()V', 5, body + '\nreturn-void')
}

fn suite_source() string {
	return method('private static nullReceiver()V', 2, '
const/4 v0, 0
:try_start
invoke-virtual {v0}, ${manager_type}->${active_signature}
move-result v0
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "instance API must reject a null receiver"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:null_receiver
move-exception v0
return-void
.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :null_receiver') +
		method('public static suite(${manager_type})V', 8, '
new-instance v0, ${manager_type}
invoke-direct {v0}, ${manager_type}-><init>()V
new-instance v1, ${no_link_type}
invoke-direct {v1}, ${no_link_type}-><init>()V
new-instance v2, ${override_type}
invoke-direct {v2}, ${override_type}-><init>()V
const/4 v3, 0
:repeat
invoke-virtual {p0}, ${manager_type}->${active_signature}
move-result v4
const/4 v5, 1
const-string v6, "actual Context service must report unmonitored activity active"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${manager_type}->${active_signature}
move-result v4
const-string v6, "direct framework instance must report unmonitored activity active"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, ${manager_type}->${active_signature}
move-result v4
const-string v6, "inherited activity API must not query native link-state hooks"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v2}, ${manager_type}->${active_signature}
move-result v4
const/4 v5, 0
const-string v6, "framework-typed call must dispatch to the false override"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
add-int/lit8 v3, v3, 1
const/16 v7, 16
if-lt v3, v7, :repeat
invoke-static {}, ${main_type}->nullReceiver()V
return-void')
}

fn manager_sources() map[string]string {
	mut no_link := '.class public final ${no_link_type}\n.super ${manager_type}\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${manager_type}-><init>()V\nreturn-void')
	for signature in ['nativeGetNetworkAvailable()Z', 'nativeGetNetworkState()I'] {
		no_link += method('protected ' + signature, 2, '
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "isDefaultNetworkActive must not poll native link state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	}
	return {
		'org/vinix/bootstrap/NoLinkManager.smali': no_link
		'org/vinix/bootstrap/OverrideManager.smali': '.class public final ${override_type}\n.super ${manager_type}\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${manager_type}-><init>()V\nreturn-void') +
			method('public ${active_signature}', 1, 'const/4 v0, 0\nreturn v0')
	}
}

fn worker_source() string {
	return '.class public final ${worker_type}\n.super Ljava/lang/Thread;\n' +
		'.field private final owner:Ljava/lang/Thread;\n.field private final manager:${manager_type}\n' +
		'.field public volatile failure:Ljava/lang/Throwable;\n.field public volatile done:Z\n' +
		method('public constructor <init>(Ljava/lang/Thread;${manager_type})V', 1, '
const-string v0, "default-network-active"
invoke-direct {p0, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/String;)V
iput-object p1, p0, ${worker_type}->owner:Ljava/lang/Thread;
iput-object p2, p0, ${worker_type}->manager:${manager_type}
return-void') + method('public run()V', 2, '
:try_start
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, ${worker_type}->owner:Ljava/lang/Thread;
if-ne v0, v1, :background
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "worker must run on a different actual thread"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:background
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
if-eqz v0, :plain
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "background activity query must have no Looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:plain
iget-object v0, p0, ${worker_type}->manager:${manager_type}
invoke-static {v0}, ${main_type}->suite(${manager_type})V
const/4 v0, 1
iput-boolean v0, p0, ${worker_type}->done:Z
:try_end
return-void
:failed
move-exception v0
iput-object v0, p0, ${worker_type}->failure:Ljava/lang/Throwable;
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn cleanup_source() string {
	return method('private static cleanup(${worker_type}Ljava/lang/Throwable;)V', 3, '
if-eqz p0, :result
:stop_start
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :stop_end
invoke-virtual {p0}, Ljava/lang/Thread;->interrupt()V
const-wide/16 v0, 1000
invoke-virtual {p0, v0, v1}, Ljava/lang/Thread;->join(J)V
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :stop_end
new-instance v0, Ljava/lang/AssertionError;
const-string v2, "daemon activity query must terminate within bounded cleanup"
invoke-direct {v0, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:stop_end
goto :result
:stop_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:result
if-eqz p1, :done
throw p1
:done
return-void
.catchall {:stop_start .. :stop_end} :stop_failed')
}

fn checks_source() string {
	return method('private static checks(Landroid/content/Context;)V', 8, '
const/4 v0, 0
:try_start
invoke-static {}, ${main_type}->arm()V
invoke-static {}, ${main_type}->shape()V
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v1
if-nez v1, :ui_looper
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "Activity checks must have the actual UI Looper"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:ui_looper
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
const-string v3, "Activity checks must run on the actual UI thread"
invoke-static {v1, v2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "connectivity"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
instance-of v2, v1, ${manager_type}
const/4 v3, 1
const-string v7, "actual Context must supply a ConnectivityManager"
invoke-static {v2, v3, v7}, ${main_type}->equal(IILjava/lang/String;)V
check-cast v1, ${manager_type}
invoke-static {v1}, ${main_type}->suite(${manager_type})V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v2
new-instance v3, ${worker_type}
invoke-direct {v3, v2, v1}, ${worker_type}-><init>(Ljava/lang/Thread;${manager_type})V
move-object v0, v3
const/4 v2, 1
invoke-virtual {v0, v2}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-static {v1}, ${main_type}->suite(${manager_type})V
const-wide/16 v4, 8000
invoke-virtual {v0, v4, v5}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z
move-result v2
const/4 v3, 0
const-string v7, "background activity query must finish within bounded join"
invoke-static {v2, v3, v7}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v2, v0, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v2, :worker_complete
throw v2
:worker_complete
iget-boolean v2, v0, ${worker_type}->done:Z
const/4 v3, 1
const-string v7, "worker must finish every activity assertion"
invoke-static {v2, v3, v7}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
const/4 v2, 0
invoke-static {v0, v2}, ${main_type}->cleanup(${worker_type}Ljava/lang/Throwable;)V
return-void
:failed
move-exception v2
invoke-static {v0, v2}, ${main_type}->cleanup(${worker_type}Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn fixture_sources() map[string]string {
	mut result := manager_sources()
	result['org/vinix/bootstrap/Worker.smali'] = worker_source()
	result['org/vinix/bootstrap/Main.smali'] = '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		helpers_source() + shape_source() + suite_source() + cleanup_source() + checks_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->checks(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Unmonitored network activity contract passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')
	return result
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/NoLinkManager.smali',
		'org/vinix/bootstrap/OverrideManager.smali', 'org/vinix/bootstrap/Worker.smali']
}

fn fixture_method(source string, signature string) string {
	methods := source.split('.method ').filter(it.all_before('\n').ends_with(' ' + signature))
	assert methods.len == 1, 'exactly one fixture method required: ' + signature
	assert methods[0].contains('.end method'), 'unterminated fixture method: ' + signature
	return methods[0].all_after('\n').all_before('.end method')
}

fn verify_source_references(name string, source string) {
	for forbidden in ['->setAccessible(', '->getDeclaredField(', 'Ljava/lang/System;->setProperty(',
		'->join()V', '->await()V', '->getActiveNetworkInfo(', '->getActiveNetwork(', '->getNetworkCapabilities(',
		'->registerNetworkCallback(', '->requestNetwork(', '->nativeGetNetworkState(', '->nativeGetNetworkAvailable(',
		'.class public final Landroid/'] {
		assert !source.contains(forbidden), 'no platform stubs, network mutation, link-state queries or unbounded waits: ' + forbidden
	}
	if name == 'org/vinix/bootstrap/NoLinkManager.smali' {
		assert source.starts_with('.class public final ${no_link_type}') && source.contains('.super ${manager_type}')
		for signature in ['nativeGetNetworkAvailable()Z', 'nativeGetNetworkState()I'] {
			body := fixture_method(source, signature)
			assert body.contains('Landroid/') == false && body.contains('Ljava/lang/AssertionError;') && body.contains('throw v0')
		}
		assert !source.contains('.method public ${active_signature}') && !source.contains('.method protected native ')
		return
	}
	if name == 'org/vinix/bootstrap/OverrideManager.smali' {
		assert source.starts_with('.class public final ${override_type}') && source.contains('.super ${manager_type}')
		body := fixture_method(source, active_signature)
		assert (body.contains('const/4 v0, 0\n') || body.contains('const/4 v0, 0x0\n')) && body.contains('return v0')
		assert source.contains('.method public ${active_signature}') && !source.contains('.method public static ')
		return
	}
	if name == 'org/vinix/bootstrap/Worker.smali' {
		assert source.starts_with('.class public final ${worker_type}') && source.contains('.super Ljava/lang/Thread;')
		for reference in ['Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;',
			'Landroid/os/Looper;->myLooper()Landroid/os/Looper;', '${main_type}->suite(${manager_type})V',
			'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '.catchall',
			'"background activity query must have no Looper"', '"worker must run on a different actual thread"'] {
			assert source.contains(reference), 'missing worker assertion: ' + reference
		}
		return
	}
	assert name == 'org/vinix/bootstrap/Main.smali' && source.starts_with('.class public final ${main_type}')
	for reference in ['.super Landroid/app/Activity;', '${manager_type}->${active_signature}', '"isDefaultNetworkActive"',
		'Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;',
		'Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;', 'Ljava/lang/reflect/Method;->getModifiers()I',
		'Ljava/lang/reflect/Modifier;->isPublic(I)Z', 'Ljava/lang/reflect/Modifier;->isStatic(I)Z',
		'Ljava/lang/reflect/Modifier;->isNative(I)Z', 'Ljava/lang/reflect/Modifier;->isFinal(I)Z',
		'Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;', '"connectivity"',
		'new-instance v0, ${manager_type}', 'new-instance v1, ${no_link_type}', 'new-instance v2, ${override_type}',
		'"actual Context service must report unmonitored activity active"',
		'"inherited activity API must not query native link-state hooks"',
		'"framework-typed call must dispatch to the false override"',
		'Landroid/os/Process;->is64Bit()Z', '"aarch64"', 'Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;',
		'Ljava/lang/Thread;->setDaemon(Z)V', 'Ljava/lang/Thread;->join(J)V', 'Ljava/lang/Thread;->interrupt()V',
		'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '->addSuppressed(',
		'"${pass_marker}"', '"${fail_marker}"'] {
		assert source.contains(reference), 'missing actual network-activity assertion: ' + reference
	}
	suite := fixture_method(source, 'suite(${manager_type})V')
	assert suite.count('->${active_signature}') == 4 && (suite.contains('add-int/lit8 v3, v3, 0x1') ||
		suite.contains('add-int/lit8 v3, v3, 1')), 'four virtual receiver roles and repeated calls required'
	assert suite.contains('const/16 v7, 16\n') || suite.contains('const/16 v7, 0x10\n'), 'exact sixteen-call loop bound required'
	assert suite.contains('if-lt v3, v7,') && suite.count('->nullReceiver()V') == 1
	assert fixture_method(source, 'nullReceiver()V').count('.catch Ljava/lang/NullPointerException;') == 1
	checks := fixture_method(source, 'checks(Landroid/content/Context;)V')
	assert checks.count('->suite(${manager_type})V') == 2
	assert checks.contains('const-wide/16 v4, 8000\n') || checks.contains('const-wide/16 v4, 0x1f40\n'), 'exact eight-second worker deadline required'
	cleanup := fixture_method(source, 'cleanup(${worker_type}Ljava/lang/Throwable;)V')
	assert cleanup.contains('const-wide/16 v0, 1000\n') || cleanup.contains('const-wide/16 v0, 0x3e8\n'), 'exact one-second cleanup deadline required'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	$if prod { panic('live assertions required') }
	out := os.abs_path(os.args[1])
	aapt, resources := os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(out) && !os.is_link(out), 'fresh output directory required'
	assert os.real_path(os.dir(out)) == os.dir(out), 'canonical output parent required'
	os.mkdir_all(out + '/commands')!
	os.mkdir(out + '/inputs')!
	source_root, executable := os.dir(os.real_path(@FILE)), os.real_path(os.executable())
	assert os.ls(source_root)!.filter(it.ends_with('.v')).sorted() == ['main.v'], 'exact one-file source closure required'
	assert !os.is_link(source_root + '/main.v') &&
		os.lstat(source_root + '/main.v')!.get_filetype() == .regular, 'regular fixture source required'
	keytool := os.dir(java) + '/keytool'
	zip := os.real_path(os.find_abs_path_of_executable('zip')!)
	unzip := os.real_path(os.find_abs_path_of_executable('unzip')!)
	mut inputs := map[string]string{}
	for path in [executable, source_root + '/main.v', aapt, resources, java, signer, keytool, zip, unzip] {
		assert os.is_file(path), 'missing input: ' + path
		inputs[path] = file_hash(path)!
	}
	os.cp(source_root + '/main.v', out + '/inputs/main.v')!
	os.cp(executable, out + '/inputs/generator')!
	assert file_hash(out + '/inputs/main.v')! == inputs[source_root + '/main.v']!
	assert file_hash(out + '/inputs/generator')! == inputs[executable]!
	tool_names := regular_names(tools)!
	for name in tool_names { inputs[tools + '/' + name] = file_hash(tools + '/' + name)! }
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(out + '/tools-membership.json', json2.encode(tool_names) + '\n')!
	classes := fixture_sources()
	expected := expected_classes()
	assert classes.keys().sorted() == expected, 'exact Activity/worker/two-manager closure required'
	for name in expected {
		assert name.ends_with('.smali') && !name.starts_with('/') && !name.contains_any('\\\r\n\x00')
		assert !name.split('/').any(it in ['', '.', '..']), 'safe fixture class path required'
		path := out + '/smali/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, classes[name])!
		verify_source_references(name, classes[name])
	}
	assert relative_files(out + '/smali')! == expected
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	revision := recorded(out, 'source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	java_version := recorded(out, 'java-version', java_command(java, ['-version']))!
	key := out + '/fixture.p12'
	recorded(out, 'keytool', [keytool, '-J-Xmx256m', '-J-XX:ActiveProcessorCount=2', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Default Network Activity Fixture',
		'-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	inputs[key] = file_hash(key)!
	recorded(out, 'link', [aapt, 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])!
	assembly := recorded(out, 'assemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex']))!
	assert assembly.trim_space() == '' && os.is_file(out + '/classes.dex'), 'fresh error-free DEX required'
	recorded(out, 'disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip-smali']))!
	reassembly := recorded(out, 'reassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', out + '/roundtrip-smali', '-o', out + '/roundtrip.dex']))!
	assert reassembly.trim_space() == '' && os.is_file(out + '/roundtrip.dex'), 'fresh roundtrip DEX required'
	recorded(out, 'second-disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', out + '/roundtrip.dex', '-o', out + '/roundtrip-checked-smali']))!
	for directory in ['roundtrip-smali', 'roundtrip-checked-smali'] {
		assert relative_files(out + '/' + directory)! == expected, 'roundtrip class closure differs'
		for name in expected { verify_source_references(name, os.read_file(out + '/' + directory + '/' + name)!) }
	}
	for name in expected {
		assert file_hash(out + '/roundtrip-smali/' + name)! == file_hash(out + '/roundtrip-checked-smali/' + name)!, 'unstable DEX roundtrip'
	}
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	apk := out + '/probe.apk'
	recorded(out, 'sign', java_command(java, ['-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk']))!
	verification := recorded(out, 'verify', java_command(java, ['-jar', signer, 'verify', '--verbose', apk]))!
	assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true')
	assert verification.split_into_lines().filter(it == 'Number of signers: 1').len == 1
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])!
	assert badging.contains("package: name='${package_name}'") && badging.contains("launchable-activity: name='${package_name}.Main'")
	assert badging.contains("minSdkVersion:'28'")
	manifest_tree := recorded(out, 'signed-manifest-tree', [aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'])!
	assert manifest_tree.contains('E: manifest') && manifest_tree.contains('E: application') &&
		manifest_tree.contains('E: activity'), 'complete signed manifest tree required'
	assert !manifest_tree.contains('E: uses-permission') && !manifest_tree.contains('E: uses-permission-sdk-23'),
		'fixture requests no network or other permission grant'
	entries := recorded(out, 'signed-membership', [unzip, '-Z1', apk])!.trim_space().split_into_lines()
	mut seen := map[string]bool{}
	for entry in entries {
		assert !seen[entry] && !entry.starts_with('/') && !entry.contains_any('\\\r\n\x00') && !entry.split('/').any(it in ['.', '..'])
		seen[entry] = true
	}
	assert entries.filter(it.ends_with('.dex')) == ['classes.dex']
	recorded(out, 'signed-dex-extract', [unzip, '-q', apk, 'classes.dex', '-d', out + '/signed-extracted'])!
	assert relative_files(out + '/signed-extracted')! == ['classes.dex']
	assert file_hash(out + '/signed-extracted/classes.dex')! == file_hash(out + '/classes.dex')!
	assert regular_names(tools)! == tool_names
	assert os.ls(source_root)!.filter(it.ends_with('.v')).sorted() == ['main.v']
	for path, before in inputs { assert file_hash(path)! == before, 'input changed: ' + path }
	mut artifacts := map[string]string{}
	for path in output_files(out)! { artifacts[path.all_after(out + '/')] = file_hash(path)! }
	receipt := FixtureBuild{
		argv: os.args.clone(), source_revision: revision, inputs_sha256: inputs, artifacts_sha256: artifacts,
		java_version: java_version.trim_space(), apk_sha256: file_hash(apk)!, package_name: package_name,
		activity_name: package_name + '.Main', pass_marker: pass_marker, fail_marker: fail_marker, scope: fixture_scope
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true) + '\n')!
	println('DEFAULT-NETWORK-ACTIVE-FIXTURE-APK ' + apk)
	println('DEFAULT-NETWORK-ACTIVE-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
