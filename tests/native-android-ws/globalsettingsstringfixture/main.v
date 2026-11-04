// SPDX-License-Identifier: GPL-2.0-or-later
// Source-only draft: narrow signed Global.putString ARM regression.
module main

import crypto.sha256
import json2
import os

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const resolver_type = 'Lorg/vinix/bootstrap/SettingsResolver;'
const worker_type = 'Lorg/vinix/bootstrap/Worker;'
const global_type = 'Landroid/provider/Settings$Global;'
const resolver_base = 'Landroid/content/ContentResolver;'
const values_type = 'Landroid/content/ContentValues;'
const uri_type = 'Landroid/net/Uri;'
const put_signature = 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
const pass_marker = 'GLOBAL-SETTINGS-STRING-PASS public-static virtual-insert global-uri fresh-values exact-null-empty-unicode-Strings one-call provider-result SQLException narrow-exception-identity null-resolver bounded-worker'
const fail_marker = 'GLOBAL-SETTINGS-STRING-FAIL'
const fixture_scope = 'Standalone aarch64 public static Settings.Global.putString linkage and actual virtual ContentResolver.insert delegation. Each suite uses an independent recording resolver to check exact Global.CONTENT_URI identity, exactly one call, fresh ContentValues with exactly two explicit name/value entries, original nullable String objects, empty and Unicode strings and repeated keys. Arbitrary nonnull URI produces true; null URI and SQLException produce false; SecurityException, NullPointerException and IllegalArgumentException propagate by identity. A null resolver throws NPE. The same suite runs on the UI thread and a plain daemon worker without a Looper, with bounded join and cleanup preserving primary failure. No SettingsProvider, persistence, write grant, moved-key routing, getter behavior, Google success or Maps rendering is supplied or inferred. ARM execution requires a separate receipt against the pinned SDK/native pair.'

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
		'<uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/><application android:label="Global String fixture">' +
		'<activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
	mut source := ''
	for name, branch in {'equal': 'if-eq', 'same': 'if-eq', 'different': 'if-ne'} {
		types := if name == 'equal' { 'II' } else { 'Ljava/lang/Object;Ljava/lang/Object;' }
		source += method('private static ${name}(${types}Ljava/lang/String;)V', 1, '
${branch} p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
	}
	return source + method('private static text(Ljava/lang/Object;Ljava/lang/String;)V', 2, '
if-eqz p1, :null_expected
instance-of v0, p0, Ljava/lang/String;
if-eqz v0, :bad
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
:null_expected
if-nez p0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "exact String or explicit null entry required"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
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
	return method('private static shape()V', 5, '
const-class v0, ${global_type}
const-string v1, "putString"
const/4 v2, 3
new-array v2, v2, [Ljava/lang/Class;
const-class v3, ${resolver_base}
const/4 v4, 0
aput-object v3, v2, v4
const-class v3, Ljava/lang/String;
const/4 v4, 1
aput-object v3, v2, v4
const/4 v4, 2
aput-object v3, v2, v4
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;
move-result-object v1
const-class v2, ${global_type}
const-string v4, "putString must be declared on Global"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;
const-string v4, "Global.putString must return primitive boolean"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "Global.putString must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const-string v4, "Global.putString must be static"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

// Check every call, including throwing calls, against its prior values object.
fn observed_source() string {
	return method('private static observed(${resolver_type}Ljava/lang/String;Ljava/lang/String;I${values_type})V', 5, '
iget v0, p0, ${resolver_type}->calls:I
const-string v1, "exactly one virtual insert required"
invoke-static {v0, p3, v1}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v0, p0, ${resolver_type}->uri:${uri_type}
sget-object v1, ${global_type}->CONTENT_URI:${uri_type}
const-string v2, "insert must receive actual Global.CONTENT_URI object"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, ${uri_type}->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "content://settings/global"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
iget-object v0, p0, ${resolver_type}->values:${values_type}
const-string v1, "each call must allocate fresh ContentValues"
invoke-static {v0, p4, v1}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, ${values_type}->size()I
move-result v1
const/4 v2, 2
const-string v3, "exactly name and value entries required"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const-string v1, "name"
invoke-virtual {v0, v1}, ${values_type}->containsKey(Ljava/lang/String;)Z
move-result v2
const/4 v3, 1
const-string v4, "explicit name key required even for null name"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v1}, ${values_type}->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
invoke-static {v2, p1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v4, "exact caller String name or null must be forwarded"
invoke-static {v2, p1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1}, ${values_type}->containsKey(Ljava/lang/String;)Z
move-result v2
const-string v4, "explicit value key required even for null value"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v1}, ${values_type}->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
invoke-static {v2, p2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v4, "exact caller String value or null must be forwarded"
invoke-static {v2, p2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn write_source() string {
	return method('private static write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V', 4, '
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
iget-object v1, p0, ${resolver_type}->values:${values_type}
invoke-static {p0, p1, p2}, ${global_type}->${put_signature}
move-result v2
const-string v3, "provider URI result or SQLException outcome"
invoke-static {v2, p3, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0, p1, p2, v0, v1}, ${main_type}->observed(${resolver_type}Ljava/lang/String;Ljava/lang/String;I${values_type})V
return-void')
}

fn propagation_source() string {
	return method('private static rejects(${resolver_type}Ljava/lang/RuntimeException;)V', 6, '
iput-object p1, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
iget-object v1, p0, ${resolver_type}->values:${values_type}
const-string v2, "exception-control"
const-string v3, "unchanged-exception-identity"
:try_start
invoke-static {p0, v2, v3}, ${global_type}->${put_signature}
:try_end
new-instance v4, Ljava/lang/AssertionError;
const-string v5, "non-SQL exception must propagate"
invoke-direct {v4, v5}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v4
:caught
move-exception v4
const-string v5, "non-SQL exception identity must remain unchanged"
invoke-static {v4, p1, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0, v2, v3, v0, v1}, ${main_type}->observed(${resolver_type}Ljava/lang/String;Ljava/lang/String;I${values_type})V
const/4 v4, 0
iput-object v4, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
return-void
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught') + method('private static nullResolver()V', 4, '
const/4 v0, 0
const-string v1, "null-resolver"
const-string v2, "must-throw"
:try_start
invoke-static {v0, v1, v2}, ${global_type}->${put_signature}
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "null resolver must throw NPE"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:caught
move-exception v3
return-void
.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :caught')
}

fn suite_source() string {
	mut body := '
new-instance v0, ${resolver_type}
invoke-direct {v0}, ${resolver_type}-><init>()V
const-string v1, "content://fixture/arbitrary/accepted?not=settings"
invoke-static {v1}, ${uri_type}->parse(Ljava/lang/String;)${uri_type}
move-result-object v4
iput-object v4, v0, ${resolver_type}->resultUri:${uri_type}
const/4 v3, 1
'
	for pair in [
		['"phenotype-configuration"', '"initial-value"'],
		['"phenotype-configuration"', ''], ['', '"null-name-value"'], ['', ''], ['""', '""'],
		['"ключ-🗺"', '"café / 東京 / 😀 / é"'],
		['"punctuation / ? = &"', '"value with spaces / ? = &"'],
		['"phenotype-configuration"', '"replacement-without-persistence"'],
	] {
		for index, register in ['v1', 'v2'] {
			body += if pair[index] == '' { 'const/4 ${register}, 0\n' } else { 'const-string ${register}, ${pair[index]}\n' }
		}
		body += 'invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V\n'
	}
	body += 'new-instance v1, Ljava/lang/String;
const-string v5, "non-interned-name"
invoke-direct {v1, v5}, Ljava/lang/String;-><init>(Ljava/lang/String;)V
new-instance v2, Ljava/lang/String;
const-string v5, "non-interned-value"
invoke-direct {v2, v5}, Ljava/lang/String;-><init>(Ljava/lang/String;)V
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
const/4 v3, 0
iput-object v3, v0, ${resolver_type}->resultUri:${uri_type}
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
iput-object v4, v0, ${resolver_type}->resultUri:${uri_type}
new-instance v5, Landroid/database/SQLException;
invoke-direct {v5}, Landroid/database/SQLException;-><init>()V
iput-object v5, v0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
'
	for exception_type in ['SecurityException', 'NullPointerException', 'IllegalArgumentException'] {
		body += 'new-instance v5, Ljava/lang/${exception_type};\ninvoke-direct {v5}, Ljava/lang/${exception_type};-><init>()V\n' +
			'invoke-static {v0, v5}, ${main_type}->rejects(${resolver_type}Ljava/lang/RuntimeException;)V\n'
	}
	body += 'const-string v1, "after-exceptions"
const-string v2, "successful-recovery"
const/4 v3, 1
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
iget v1, v0, ${resolver_type}->calls:I
const/16 v2, 15
const-string v3, "all fifteen recording resolver calls must execute"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {}, ${main_type}->nullResolver()V
return-void'
	return method('public static suite()V', 6, body)
}

fn resolver_source() string {
	return '.class public final ${resolver_type}\n.super ${resolver_base}\n' +
		'.field public calls:I\n.field public uri:${uri_type}\n.field public values:${values_type}\n' +
		'.field public resultUri:${uri_type}\n.field public failure:Ljava/lang/RuntimeException;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${resolver_base}-><init>()V\nreturn-void') +
		method('public insert(${uri_type}${values_type})${uri_type}', 1, '
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${resolver_type}->calls:I
iput-object p1, p0, ${resolver_type}->uri:${uri_type}
iput-object p2, p0, ${resolver_type}->values:${values_type}
iget-object v0, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
if-eqz v0, :result
throw v0
:result
iget-object v0, p0, ${resolver_type}->resultUri:${uri_type}
return-object v0')
}

fn worker_source() string {
	return '.class public final ${worker_type}\n.super Ljava/lang/Thread;\n' +
		'.field private final owner:Ljava/lang/Thread;\n.field public volatile failure:Ljava/lang/Throwable;\n.field public volatile done:Z\n' +
		method('public constructor <init>(Ljava/lang/Thread;)V', 1, '
const-string v0, "global-settings-string"
invoke-direct {p0, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/String;)V
iput-object p1, p0, ${worker_type}->owner:Ljava/lang/Thread;
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
const-string v1, "background string writer must have no Looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:plain
invoke-static {}, ${main_type}->suite()V
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
const-string v2, "daemon string writer must terminate within bounded cleanup"
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
	return method('private static checks()V', 7, '
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
invoke-static {}, ${main_type}->suite()V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v1
new-instance v2, ${worker_type}
invoke-direct {v2, v1}, ${worker_type}-><init>(Ljava/lang/Thread;)V
move-object v0, v2
const/4 v2, 1
invoke-virtual {v0, v2}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-static {}, ${main_type}->suite()V
const-wide/16 v4, 8000
invoke-virtual {v0, v4, v5}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z
move-result v2
const/4 v3, 0
const-string v6, "background string writes must finish within bounded join"
invoke-static {v2, v3, v6}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v2, v0, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v2, :worker_complete
throw v2
:worker_complete
iget-boolean v2, v0, ${worker_type}->done:Z
const/4 v3, 1
const-string v6, "worker must finish every String-write assertion"
invoke-static {v2, v3, v6}, ${main_type}->equal(IILjava/lang/String;)V
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
	return {
		'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
			helpers_source() + shape_source() + observed_source() + write_source() + propagation_source() +
			suite_source() + cleanup_source() + checks_source() + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->checks()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Global String-write delegation passed"
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
		'org/vinix/bootstrap/SettingsResolver.smali': resolver_source()
		'org/vinix/bootstrap/Worker.smali': worker_source()
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/SettingsResolver.smali', 'org/vinix/bootstrap/Worker.smali']
}

fn fixture_method(source string, signature string) string {
	methods := source.split('.method ').filter(it.all_before('\n').ends_with(' ' + signature))
	assert methods.len == 1, 'exactly one fixture method required: ' + signature
	assert methods[0].contains('.end method'), 'unterminated fixture method: ' + signature
	return methods[0].all_after('\n').all_before('.end method')
}

fn verify_source_references(name string, source string) {
	assert !source.contains('->setAccessible(') && !source.contains('->getDeclaredField(') &&
		!source.contains('Ljava/lang/System;->setProperty(') && !source.contains('->join()V') &&
		!source.contains('->await()V') && !source.contains('${global_type}->getString(') &&
		!source.contains('->getContentResolver(') && !source.contains('Landroid/content/ContentProvider;') &&
		!source.contains('.class public final Landroid/'), 'no platform stubs, real-provider writes or unbounded waits'
	if name == 'org/vinix/bootstrap/SettingsResolver.smali' {
		assert source.starts_with('.class public final ${resolver_type}') && source.contains('.super ${resolver_base}')
		insert := fixture_method(source, 'insert(${uri_type}${values_type})${uri_type}')
		for reference in ['${resolver_type}->calls:I', '${resolver_type}->uri:${uri_type}',
			'${resolver_type}->values:${values_type}', '${resolver_type}->failure:Ljava/lang/RuntimeException;',
			'${resolver_type}->resultUri:${uri_type}', 'throw v0', 'return-object v0'] {
			assert insert.contains(reference), 'missing resolver observation: ' + reference
		}
		assert insert.count('add-int/lit8') == 1
		return
	}
	if name == 'org/vinix/bootstrap/Worker.smali' {
		assert source.starts_with('.class public final ${worker_type}') && source.contains('.super Ljava/lang/Thread;')
		for reference in ['Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;',
			'Landroid/os/Looper;->myLooper()Landroid/os/Looper;', '${main_type}->suite()V',
			'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '.catchall',
			'"background string writer must have no Looper"', '"worker must run on a different actual thread"'] {
			assert source.contains(reference), 'missing worker assertion: ' + reference
		}
		return
	}
	assert name == 'org/vinix/bootstrap/Main.smali' && source.starts_with('.class public final ${main_type}')
	for reference in ['.super Landroid/app/Activity;', '${global_type}->${put_signature}',
		'"putString"', 'Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;',
		'Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;', 'Ljava/lang/reflect/Method;->getModifiers()I',
		'${global_type}->CONTENT_URI:${uri_type}', '"content://settings/global"',
		'${values_type}->containsKey(Ljava/lang/String;)Z', '${values_type}->get(Ljava/lang/String;)Ljava/lang/Object;',
		'"each call must allocate fresh ContentValues"', '"exact caller String name or null must be forwarded"',
		'"exact caller String value or null must be forwarded"', '"content://fixture/arbitrary/accepted?not=settings"',
		'Ljava/lang/String;-><init>(Ljava/lang/String;)V',
		'Landroid/database/SQLException;', 'Ljava/lang/SecurityException;', 'Ljava/lang/NullPointerException;',
		'Ljava/lang/IllegalArgumentException;', '${main_type}->nullResolver()V',
		'Landroid/os/Process;->is64Bit()Z', '"aarch64"', 'Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;',
		'Ljava/lang/Thread;->setDaemon(Z)V', 'Ljava/lang/Thread;->join(J)V', 'Ljava/lang/Thread;->interrupt()V',
		'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '->addSuppressed(',
		'"${pass_marker}"', '"${fail_marker}"'] {
		assert source.contains(reference), 'missing actual Global String-write assertion: ' + reference
	}
	assert source.contains('"ключ-🗺"') || source.to_lower().contains('"\\u043a\\u043b\\u044e\\u0447-\\ud83d\\uddfa"'),
		'Unicode name control missing'
	assert source.contains('"café / 東京 / 😀 / é"') ||
		source.to_lower().contains('"caf\\u00e9 / \\u6771\\u4eac / \\ud83d\\ude00 / e\\u0301"'),
		'Unicode value control missing'
	suite := fixture_method(source, 'suite()V')
	assert suite.count('->write(') == 12 && suite.count('->rejects(') == 3, 'all fifteen calls required per suite'
	assert suite.count('new-instance v0, ${resolver_type}') == 1, 'independent resolver per suite required'
	assert fixture_method(source, 'write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V').count('->${put_signature}') == 1
	assert fixture_method(source, 'rejects(${resolver_type}Ljava/lang/RuntimeException;)V').count('.catch Ljava/lang/RuntimeException;') == 1
	assert fixture_method(source, 'nullResolver()V').count('.catch Ljava/lang/NullPointerException;') == 1
	assert fixture_method(source, 'checks()V').count('->suite()V') == 2
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
	assert classes.keys().sorted() == expected, 'exact Activity/resolver/worker closure required'
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
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Global String Fixture',
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
	println('GLOBAL-SETTINGS-STRING-FIXTURE-APK ' + apk)
	println('GLOBAL-SETTINGS-STRING-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
