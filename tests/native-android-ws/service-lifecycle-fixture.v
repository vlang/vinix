// SPDX-License-Identifier: GPL-2.0-or-later
// Signed ART regression for base Service callbacks under an unchanged disk policy.
module main

import crypto.sha256
import json2
import os

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const service_type = 'Lorg/vinix/bootstrap/ProbeService;'
const policy_type = 'Landroid/os/StrictMode$ThreadPolicy;'
const builder_type = 'Landroid/os/StrictMode$ThreadPolicy$Builder;'
const pass_marker = 'SERVICE-LIFECYCLE-PASS constructors attach-base-context create destroy no-disk-callback policy-identity duplicate-attach null-attach real-write-control restored-original'
const fail_marker = 'SERVICE-LIFECYCLE-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn service_source() string {
	mut text := '.class public final ${service_type}\n.super Landroid/app/Service;\n.field public phase:I\n'
	text += method('public constructor <init>()V', 2, '
invoke-direct {p0}, Landroid/app/Service;-><init>()V
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v0
if-nez v0, :bad
const/4 v0, 1
iput v0, p0, ${service_type}->phase:I
return-void
' + failure('Service constructor must retain a null base'))
	text += method('public attachBaseContext(Landroid/content/Context;)V', 2, '
invoke-super {p0, p1}, Landroid/app/Service;->attachBaseContext(Landroid/content/Context;)V
iget v0, p0, ${service_type}->phase:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v0
if-ne v0, p1, :bad
const/4 v0, 2
iput v0, p0, ${service_type}->phase:I
return-void
' + failure('Service attachment order or base state changed'))
	text += method('public onCreate()V', 2, '
invoke-super {p0}, Landroid/app/Service;->onCreate()V
iget v0, p0, ${service_type}->phase:I
const/4 v1, 2
if-ne v0, v1, :bad
const/4 v0, 3
iput v0, p0, ${service_type}->phase:I
return-void
' + failure('Service create order changed'))
	text += method('public onDestroy()V', 2, '
invoke-super {p0}, Landroid/app/Service;->onDestroy()V
iget v0, p0, ${service_type}->phase:I
const/4 v1, 3
if-ne v0, v1, :bad
const/4 v0, 4
iput v0, p0, ${service_type}->phase:I
return-void
' + failure('Service destroy order changed'))
	text += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 1,
		'const/4 v0, 0\nreturn-object v0')
	return text
}

fn policy_helpers() string {
	mut text := method('private assertPolicy(${policy_type})V', 2, '
invoke-static {}, Landroid/os/StrictMode;->getThreadPolicy()${policy_type}
move-result-object v0
if-ne v0, p1, :bad
return-void
' + failure('Service changed the exact caller policy'))
	text += method('private assertQuiet(${policy_type})V', 2, '
invoke-direct {p0, p1}, ${main_type}->assertPolicy(${policy_type})V
iget v0, p0, ${main_type}->writes:I
if-nez v0, :bad
iget v0, p0, ${main_type}->executions:I
if-nez v0, :bad
return-void
' + failure('Base Service lifecycle performed policy-visible disk I/O'))
	text += method('public execute(Ljava/lang/Runnable;)V', 1, '
iget v0, p0, ${main_type}->executions:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_type}->executions:I
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void')
	text += method('public onThreadViolation(Landroid/os/strictmode/Violation;)V', 2, '
instance-of v0, p1, Landroid/os/strictmode/DiskWriteViolation;
if-eqz v0, :bad
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iget-object v1, p0, ${main_type}->probeThread:Ljava/lang/Thread;
if-ne v0, v1, :bad
invoke-static {}, Landroid/os/StrictMode;->getThreadPolicy()${policy_type}
move-result-object v0
sget-object v1, ${policy_type}->LAX:${policy_type}
if-ne v0, v1, :bad
iget v0, p0, ${main_type}->writes:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_type}->writes:I
return-void
' + failure('Expected an inline typed disk callback under recursion guard'))
	return text
}

// Closing an already-created stream also happens on assertion/IO failure. The
// caller's outer catch restores its policy even if close itself throws.
fn write_control() string {
	return method('private writeControl(Ljava/io/File;)V', 4, '
new-instance v0, Ljava/io/FileOutputStream;
invoke-direct {v0, p1}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
:write_start
iget v1, p0, ${main_type}->writes:I
const/16 v2, 42
invoke-virtual {v0, v2}, Ljava/io/FileOutputStream;->write(I)V
iget v2, p0, ${main_type}->writes:I
if-le v2, v1, :bad
iget v1, p0, ${main_type}->executions:I
if-ne v1, v2, :bad
goto :write_end
:bad
new-instance v2, Ljava/lang/AssertionError;
const-string v3, "Real FileOutputStream.write no longer reports disk writes"
invoke-direct {v2, v3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v2
:write_end
invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
return-void
.catchall {:write_start .. :write_end} :write_failed
:write_failed
move-exception v1
invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
throw v1
')
}

fn test_source() string {
	return method('private test()V', 8, '
invoke-static {}, Landroid/os/StrictMode;->getThreadPolicy()${policy_type}
move-result-object v0
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v4
iput-object v4, p0, ${main_type}->probeThread:Ljava/lang/Thread;
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v4
new-instance v3, Ljava/io/File;
const-string v5, "service-lifecycle-write-control"
invoke-direct {v3, v4, v5}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v4, ${builder_type}
invoke-direct {v4}, ${builder_type}-><init>()V
invoke-virtual {v4}, ${builder_type}->detectDiskWrites()${builder_type}
invoke-virtual {v4, p0, p0}, ${builder_type}->penaltyListener(Ljava/util/concurrent/Executor;Landroid/os/StrictMode$OnThreadViolationListener;)${builder_type}
invoke-virtual {v4}, ${builder_type}->build()${policy_type}
move-result-object v1
:policy_start
invoke-static {v1}, Landroid/os/StrictMode;->setThreadPolicy(${policy_type})V
# Include Service, ContextWrapper and Context construction in the strict interval.
new-instance v2, ${service_type}
invoke-direct {v2}, ${service_type}-><init>()V
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
invoke-virtual {v2, p0}, ${service_type}->attachBaseContext(Landroid/content/Context;)V
invoke-virtual {v2}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v4
if-ne v4, p0, :bad
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
# A distinct second base must be rejected, rather than silently replacing state.
new-instance v6, ${service_type}
invoke-direct {v6}, ${service_type}-><init>()V
:duplicate_start
invoke-virtual {v2, v6}, ${service_type}->attachBaseContext(Landroid/content/Context;)V
:duplicate_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:duplicate_start .. :duplicate_end} :duplicate_rejected
:duplicate_rejected
move-exception v4
invoke-virtual {v2}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v4
if-ne v4, p0, :bad
iget v4, v2, ${service_type}->phase:I
const/4 v5, 2
if-ne v4, v5, :bad
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
# The runtime attachment bridge must still reject null before changing state.
const/4 v4, 0
:null_start
invoke-virtual {v6, v4}, Landroid/content/ContextWrapper;->atl_attach_base_context(Landroid/content/Context;)V
:null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_rejected
:null_rejected
move-exception v4
invoke-virtual {v6}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v4
if-nez v4, :bad
iget v4, v6, ${service_type}->phase:I
const/4 v5, 1
if-ne v4, v5, :bad
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
invoke-virtual {v2}, ${service_type}->onCreate()V
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
invoke-virtual {v2}, ${service_type}->onDestroy()V
invoke-direct {p0, v1}, ${main_type}->assertQuiet(${policy_type})V
iget v4, v2, ${service_type}->phase:I
const/4 v5, 4
if-ne v4, v5, :bad
invoke-direct {p0, v3}, ${main_type}->writeControl(Ljava/io/File;)V
invoke-direct {p0, v1}, ${main_type}->assertPolicy(${policy_type})V
goto :policy_end
:bad
new-instance v6, Ljava/lang/AssertionError;
const-string v7, "Service base state, attachment rejection or callback order changed"
invoke-direct {v6, v7}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v6
:policy_end
invoke-static {v0}, Landroid/os/StrictMode;->setThreadPolicy(${policy_type})V
invoke-direct {p0, v0}, ${main_type}->assertPolicy(${policy_type})V
invoke-virtual {v3}, Ljava/io/File;->delete()Z
return-void
.catchall {:policy_start .. :policy_end} :failed
:failed
move-exception v2
invoke-static {v0}, Landroid/os/StrictMode;->setThreadPolicy(${policy_type})V
throw v2')
}

fn main_source() string {
	mut text := '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		'.implements Ljava/util/concurrent/Executor;\n.implements Landroid/os/StrictMode$OnThreadViolationListener;\n' +
		'.field public writes:I\n.field public executions:I\n.field public probeThread:Ljava/lang/Thread;\n'
	text += method('public constructor <init>()V', 0,
		'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	text += policy_helpers() + write_control() + test_source()
	text += method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:test_start
invoke-direct {p0}, ${main_type}->test()V
:test_end
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Service lifecycle and unchanged StrictMode policy passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.catchall {:test_start .. :test_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')
	return text
}

struct CommandReceipt {
	argv   []string
	status int
	output string
}

struct FixtureBuild {
	argv             []string
	source_revision  string
	inputs_sha256    map[string]string
	artifacts_sha256 map[string]string
	java_version     string
	apk_sha256       string
	package_name     string
	activity_name    string
	pass_marker      string
	fail_marker      string
	scope            string
}

fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn recorded(out string, name string, argv []string) !string {
	result := os.exec(argv)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{
		argv: argv
		status: result.exit_code
		output: result.output
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
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		item := path + '/' + name
		if os.is_link(item) { return error('unexpected output symlink: ' + item) }
		kind := (os.lstat(item)!).get_filetype()
		if kind == .directory {
			result << output_files(item)!
		} else if kind == .regular {
			result << item
		} else {
			return error('unexpected output type: ' + item)
		}
	}
	return result
}

fn manifest() string {
	return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1">' +
		'<uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>' +
		'<application android:label="Service lifecycle policy fixture">' +
		'<activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	$if prod { panic('build the fixture generator without -prod so evidence assertions remain enabled') }
	out := os.abs_path(os.args[1])
	aapt, resources := os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	if os.exists(out) || os.is_link(out) { panic('fresh output directory required') }
	os.mkdir_all(out + '/commands')!
	os.mkdir(out + '/inputs')!
	source := os.real_path(@FILE)
	executable := os.real_path(os.executable())
	keytool := os.dir(java) + '/keytool'
	zip := os.real_path(os.find_abs_path_of_executable('zip')!)
	mut inputs := map[string]string{}
	for path in [source, executable, aapt, resources, java, signer, keytool, zip] {
		assert os.is_file(path), 'missing input: ' + path
		inputs[path] = file_hash(path)!
	}
	mut tool_names := os.ls(tools)!
	tool_names.sort()
	for name in tool_names {
		path := tools + '/' + name
		if os.is_file(path) { inputs[path] = file_hash(path)! }
	}
	os.cp(source, out + '/inputs/service-lifecycle-fixture.v')!
	os.cp(executable, out + '/inputs/generator')!
	assert file_hash(out + '/inputs/service-lifecycle-fixture.v')! == inputs[source]!
	assert file_hash(out + '/inputs/generator')! == inputs[executable]!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	dir := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(dir)!
	os.write_file(dir + '/Main.smali', main_source())!
	os.write_file(dir + '/ProbeService.smali', service_source())!
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	revision := recorded(out, 'source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	java_version := recorded(out, 'java-version', java_command(java, ['-version']))!
	key := out + '/fixture.p12'
	recorded(out, 'keytool', [keytool, '-J-Xmx256m', '-J-XX:ActiveProcessorCount=2', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname',
		'CN=Vinix Service Lifecycle Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	inputs[key] = file_hash(key)!
	recorded(out, 'link', [aapt, 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk'])!
	assembly := recorded(out, 'assemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex']))!
	assert assembly.trim_space() == '', 'unexpected assembly diagnostics: ' + assembly
	assert os.is_file(out + '/classes.dex'), 'assembler produced no DEX'
	recorded(out, 'disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip-smali']))!
	reassembly := recorded(out, 'reassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/roundtrip-smali', '-o', out + '/roundtrip.dex']))!
	assert reassembly.trim_space() == '', 'unexpected roundtrip assembly diagnostics: ' + reassembly
	assert os.is_file(out + '/roundtrip.dex'), 'roundtrip assembler produced no DEX'
	recorded(out, 'roundtrip-disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/roundtrip.dex', '-o', out + '/roundtrip-checked-smali']))!
	first := output_files(out + '/roundtrip-smali')!
	second := output_files(out + '/roundtrip-checked-smali')!
	assert first.len == 2 && second.len == first.len, 'roundtrip class membership changed'
	for path in first {
		name := path.all_after(out + '/roundtrip-smali/')
		assert os.is_file(out + '/roundtrip-checked-smali/' + name), 'roundtrip class missing: ' + name
		assert file_hash(path)! == file_hash(out + '/roundtrip-checked-smali/' + name)!, 'roundtrip changed class: ' + name
	}
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	apk := out + '/probe.apk'
	recorded(out, 'sign', java_command(java, ['-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk']))!
	verification := recorded(out, 'verify', java_command(java, ['-jar', signer, 'verify', '--verbose', apk]))!
	assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'APK v3 signature missing'
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])!
	assert badging.contains("package: name='${package_name}'"), 'wrong APK package'
	assert badging.contains("launchable-activity: name='${package_name}.Main'"), 'wrong launch activity'
	for path, before in inputs { assert file_hash(path)! == before, 'input changed during build: ' + path }
	mut artifacts := map[string]string{}
	for path in output_files(out)! { artifacts[path.all_after(out + '/')] = file_hash(path)! }
	receipt := FixtureBuild{
		argv: os.args.clone()
		source_revision: revision
		inputs_sha256: inputs
		artifacts_sha256: artifacts
		java_version: java_version.trim_space()
		apk_sha256: file_hash(apk)!
		package_name: package_name
		activity_name: package_name + '.Main'
		pass_marker: pass_marker
		fail_marker: fail_marker
		scope: 'Synthetic Service callbacks and unchanged caller disk policy; no Google services, credentials or authentication claim.'
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true) + '\n')!
	println('SERVICE-LIFECYCLE-FIXTURE-APK ' + apk)
	println('SERVICE-LIFECYCLE-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
