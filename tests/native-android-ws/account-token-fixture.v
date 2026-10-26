// SPDX-License-Identifier: GPL-2.0-or-later
// ART behavior probe for token overloads. Synthetic result data is confined to
// a subclass; run with VINIX_ANDROID_ACCOUNT_SOCKET naming a nonexistent socket
// so the production AccountManager exercises immediate no-backend failure.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/bootstrap/Main;'
const probe = 'Lorg/vinix/bootstrap/TokenManagerProbe;'
const manager = 'Landroid/accounts/AccountManager;'
const future = 'Landroid/accounts/AccountManagerFuture;'
const pending = 'Landroid/atl/VinixAccountFuture;'
const activity = 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)${future}'
const boolean = 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)${future}'
const deprecated = 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)${future}'
const pass_marker = 'ACCOUNT-TOKEN-PASS null-validation boolean-options deprecated-null-options worker-blocking main-looper-guard notify-error unavailable-future callback-identity-handler'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "token contract: ${stage}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn probe_class() string {
	mut source := '.class public final ${probe}\n.super ${manager}\n.field public calls:I\n' +
		'.field public expectedAccount:Landroid/accounts/Account;\n.field public expectedOptions:Landroid/os/Bundle;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, ${manager}-><init>()V\nreturn-void', 0)
	source += method('public ' + activity, '
iget-object v0, p0, ${probe}->expectedAccount:Landroid/accounts/Account;
if-ne p1, v0, :bad
const-string v0, "fixture-token-type"
invoke-virtual {v0, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${probe}->expectedOptions:Landroid/os/Bundle;
if-ne p3, v0, :bad
if-nez p4, :bad
iget v0, p0, ${probe}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->calls:I
new-instance v0, ${pending}
const/4 v1, 1
invoke-direct {v0, p5, p6, v1}, ${pending}-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1}, Landroid/os/Bundle;-><init>()V
const-string v2, "authtoken"
const-string v3, "synthetic-fixture-result"
invoke-virtual {v1, v2, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${pending}->vinixResult(Landroid/os/Bundle;)V
return-object v0
' + failure('delegated account/type/options/activity'), 4)
	return source
}

fn result_check() string {
	return method('private static checkResult(${future})V', '
invoke-interface {p0}, ${future}->isDone()Z
move-result v0
if-eqz v0, :bad
invoke-interface {p0}, ${future}->getResult()Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/Bundle;
const-string v1, "authtoken"
invoke-virtual {v0, v1}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "synthetic-fixture-result"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + failure('future result'), 2)
}

fn error_check() string {
	return method('private static checkError(${future}Z)V', '
invoke-interface {p0}, ${future}->isDone()Z
move-result v0
if-eqz v0, :bad
:start
invoke-interface {p0}, ${future}->getResult()Ljava/lang/Object;
:end
goto :bad
.catch Landroid/accounts/AuthenticatorException; {:start .. :end} :caught
:caught
move-exception v0
if-eqz p1, :done
invoke-virtual {v0}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;
move-result-object v0
instance-of v0, v0, Ljava/lang/UnsupportedOperationException;
if-eqz v0, :bad
:done
return-void
' + failure('unavailable or notification error'), 2)
}

fn worker() string {
	mut body := '
iget-object v0, p0, ${owner}->probe:${probe}
iget-object v1, v0, ${probe}->expectedAccount:Landroid/accounts/Account;
const-string v2, "fixture-token-type"
new-instance v3, Landroid/os/Bundle;
invoke-direct {v3}, Landroid/os/Bundle;-><init>()V
iput-object v3, v0, ${probe}->expectedOptions:Landroid/os/Bundle;
const/4 v4, 0
move-object v5, p0
iget-object v6, p0, ${owner}->handler:Landroid/os/Handler;
invoke-virtual/range {v0 .. v6}, ${manager}->${boolean}
move-result-object v7
iput-object v7, p0, ${owner}->returned:${future}
invoke-static {v7}, ${owner}->checkResult(${future})V
const/4 v3, 0
iput-object v3, v0, ${probe}->expectedOptions:Landroid/os/Bundle;
# Deprecated API has no options argument, callback or Handler here.
const/4 v5, 0
const/4 v6, 0
invoke-virtual/range {v0 .. v5}, ${manager}->${deprecated}
move-result-object v7
invoke-static {v7}, ${owner}->checkResult(${future})V
invoke-virtual {v0, v1, v2, v4}, ${manager}->blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;
move-result-object v7
const-string v3, "synthetic-fixture-result"
invoke-virtual {v3, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget v3, v0, ${probe}->calls:I
const/4 v7, 3
if-ne v3, v7, :bad
# This separate production instance has no broker backend in this fixture.
new-instance v0, ${manager}
invoke-direct {v0}, ${manager}-><init>()V
const/4 v3, 0
invoke-virtual/range {v0 .. v6}, ${manager}->${activity}
move-result-object v7
const/4 v3, 0
invoke-static {v7, v3}, ${owner}->checkError(${future}Z)V
const/4 v4, 1
invoke-virtual/range {v0 .. v6}, ${manager}->${boolean}
move-result-object v7
invoke-static {v7, v4}, ${owner}->checkError(${future}Z)V
const/4 v4, 0
'
	for missing in [1, 2] {
		body += 'const/4 v3, 0\nmove-object v7, v${missing}\nconst/4 v${missing}, 0\n:null_${missing}_start\n' +
			'invoke-virtual/range {v0 .. v6}, ${manager}->${activity}\n:null_${missing}_end\ngoto :bad\n' +
			'.catch Ljava/lang/IllegalArgumentException; {:null_${missing}_start .. :null_${missing}_end} :null_${missing}_caught\n' +
			':null_${missing}_caught\nmove-exception v3\nmove-object v${missing}, v7\n'
	}
	body += 'iget-object v0, p0, ${owner}->finished:Ljava/util/concurrent/CountDownLatch;\ninvoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V\nreturn-void\n' + failure('worker flow')
	return method('public run()V', body, 8)
}

fn main_class() string {
	mut source := '.class public ${owner}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.implements Landroid/accounts/AccountManagerCallback;\n' +
		'.field private probe:${probe}\n.field private handler:Landroid/os/Handler;\n.field private returned:${future}\n.field private finished:Ljava/util/concurrent/CountDownLatch;\n.field private callbacks:I\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	source += result_check() + error_check() + worker()
	source += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eqz v0, :bad
if-ne v0, v1, :bad
new-instance v0, Landroid/os/Handler;
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v0, p0, ${owner}->handler:Landroid/os/Handler;
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, ${owner}->finished:Ljava/util/concurrent/CountDownLatch;
new-instance v0, ${probe}
invoke-direct {v0}, ${probe}-><init>()V
iput-object v0, p0, ${owner}->probe:${probe}
new-instance v1, Landroid/accounts/Account;
const-string v2, "synthetic-fixture-account"
const-string v3, "org.vinix.fixture.account"
invoke-direct {v1, v2, v3}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V
iput-object v1, v0, ${probe}->expectedAccount:Landroid/accounts/Account;
const-string v2, "fixture-token-type"
const/4 v3, 0
:main_start
invoke-virtual {v0, v1, v2, v3}, ${manager}->blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;
:main_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:main_start .. :main_end} :main_caught
:main_caught
move-exception v1
iget v0, v0, ${probe}->calls:I
if-nez v0, :bad
new-instance v0, Ljava/lang/Thread;
invoke-direct {v0, p0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
return-void
' + failure('main Looper guard'), 4)
	source += method('public run(${future})V', '
iget-object v0, p0, ${owner}->finished:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v1, 5
sget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${owner}->returned:${future}
if-ne p1, v0, :bad
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
iget-object v1, p0, ${owner}->handler:Landroid/os/Handler;
invoke-virtual {v1}, Landroid/os/Handler;->getLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
iget v0, p0, ${owner}->callbacks:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${owner}->callbacks:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-static {p1}, ${owner}->checkResult(${future})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
' + failure('callback identity or Handler'), 4)
	return source
}

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected output symlink') }
		if os.is_dir(path) {
			inventory(root, key, mut pins)!
		} else if os.is_file(path) {
			pins[key] = sha256.sum(os.read_bytes(path)!).hex()
		} else { return error('unexpected output file type') }
	}
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', main_class())!
	os.write_file(root + '/TokenManagerProbe.smali', probe_class())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	mut inputs := map[string]json2.Any{}
	for path in [@FILE, os.executable(), fixture + '/unsigned.apk', fixture + '/fixture.p12', java, signer] {
		inputs[os.real_path(path)] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
	}
	for directory in [tools, root] {
		for name in os.ls(directory)! {
			path := directory + '/' + name
			if os.is_file(path) { inputs[os.real_path(path)] = json2.Any(sha256.sum(os.read_bytes(path)!).hex()) }
		}
	}
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	java_version := os.exec([java, '-version'])
	assert java_version.exit_code == 0
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args)
		'source_revision': json2.Any(revision.output.trim_space())
		'java_version': json2.Any(java_version.output.trim_space())
		'inputs_sha256': json2.Any(inputs)
		'apk_sha256': json2.Any(sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
		'pass_marker': json2.Any(pass_marker)
		'scope': json2.Any('synthetic subclass tests public overload delegation; production instance tests no-backend failure; run with VINIX_ANDROID_ACCOUNT_SOCKET set to a nonexistent socket; no credentials/network; APK assembly is not ART execution')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('ACCOUNT-TOKEN-APK ' + out + '/probe.apk')
	println('ACCOUNT-TOKEN-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
	println('ACCOUNT-TOKEN-SEAL ' + sha256.sum(os.read_bytes(out + '/sha256.json')!).hex())
}
