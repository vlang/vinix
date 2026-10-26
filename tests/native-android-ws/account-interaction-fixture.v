// SPDX-License-Identifier: GPL-2.0-or-later
// ART probe for an exact, origin-local authenticator Intent graph. No account,
// credentials or network dispatch: this APK only inspects synthetic objects.
module main

import crypto.sha256
import json2
import os

const main_type = 'Lorg/vinix/bootstrap/Main;'
const record_type = 'Lorg/vinix/bootstrap/InteractionResponse;'
const response_type = 'Landroid/accounts/IAccountAuthenticatorResponse;'
const wrapper_type = 'Landroid/accounts/AccountAuthenticatorResponse;'
const intent_type = 'Landroid/content/Intent;'
const pending_type = 'Landroid/app/PendingIntent;'
const helper_type = 'Landroid/atl/VinixAccountInteraction;'
const trap_type = 'Lorg/vinix/bootstrap/InteractionTrapIntent;'
const poison_type = 'Lorg/vinix/bootstrap/InteractionPoison;'
const creator_type = 'Lorg/vinix/bootstrap/InteractionPoisonCreator;'
const origin_package = 'com.google.android.gms'
const pass_marker = 'ACCOUNT-INTERACTION-PASS exact-intent response-identity callback-preserved target-package cancellation service broadcast subclass lazy-top lazy-outer lazy-inner creator-not-called'

struct FixtureBuild {
	argv            []string
	source_revision string
	inputs_sha256   map[string]string
	java_version    string
	apk_sha256      string
	pass_marker     string
	scope           string
}

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "account interaction: ' +
		stage + '"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn recording_response() string {
	stub := 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
	return '.class public ${record_type}\n.super ${stub}\n.field public continued:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, ${stub}-><init>()V\nreturn-void', 0) +
		method('public onResult(Landroid/os/Bundle;)V', 'return-void', 0) +
		method('public onError(ILjava/lang/String;)V', 'return-void', 0) +
		method('public onRequestContinued()V', 'iget v0, p0, ${record_type}->continued:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${record_type}->continued:I\nreturn-void', 1)
}

fn trap_intent() string {
	mut text := '.class public ${trap_type}\n.super ${intent_type}\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, ${intent_type}-><init>()V\nreturn-void', 0)
	for signature in ['getPackage()Ljava/lang/String;', 'getAction()Ljava/lang/String;', 'getExtras()Landroid/os/Bundle;'] {
		text += method('public ' + signature, 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "subclass method executed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 2)
	}
	return text
}

fn response_subclass() string {
	owner := 'Lorg/vinix/bootstrap/InteractionResponseSubclass;'
	return '.class public ${owner}\n.super ${wrapper_type}\n' +
		method('public constructor <init>(${response_type})V', 'invoke-direct {p0, p1}, ${wrapper_type}-><init>(${response_type})V\nreturn-void', 0)
}

fn poison_classes() map[string]string {
	mut value := '.class public ${poison_type}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
		'.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n'
	value += method('static constructor <clinit>()V', 'new-instance v0, ${creator_type}\ninvoke-direct {v0}, ${creator_type}-><init>()V\nsput-object v0, ${poison_type}->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void', 1)
	value += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0)
	value += method('public describeContents()I', 'const/4 v0, 0\nreturn v0', 1)
	value += method('public writeToParcel(Landroid/os/Parcel;I)V', 'const/4 v0, 7\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void', 1)
	mut creator := '.class public ${creator_type}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n.field public static calls:I\n'
	creator += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0)
	creator += method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'sget v0, ${creator_type}->calls:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${creator_type}->calls:I\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "lazy Bundle ran app Parcelable creator"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 2)
	creator += method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [${poison_type}\nreturn-object v0', 1)
	return {'InteractionPoison': value, 'InteractionPoisonCreator': creator}
}

// Modes 0/1/2 create activity/service/broadcast PIs. Mode 3 puts a subclass
// Intent behind an activity PI, exercising rejection before virtual methods.
fn graph_builder() string {
	return method('private static graph(Landroid/content/Context;${response_type}I)Landroid/os/Bundle;', '
const/4 v0, 3
if-ne p2, v0, :ordinary
new-instance v3, ${trap_type}
invoke-direct {v3}, ${trap_type}-><init>()V
goto :target
:ordinary
new-instance v3, ${intent_type}
invoke-direct {v3}, ${intent_type}-><init>()V
:target
sput-object v3, ${main_type}->target:${intent_type}
new-instance v0, Landroid/content/ComponentName;
const-string v1, "${origin_package}"
const-string v2, "com.google.android.gms.auth.uiflows.addaccount.AccountIntroActivity"
invoke-direct {v0, v1, v2}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v3, v0}, ${intent_type}->setComponent(Landroid/content/ComponentName;)${intent_type}
const-string v0, "com.google.android.accounts.AccountIntro"
invoke-virtual {v3, v0}, ${intent_type}->setAction(Ljava/lang/String;)${intent_type}
new-instance v0, ${wrapper_type}
invoke-direct {v0, p1}, ${wrapper_type}-><init>(${response_type})V
const-string v1, "am_response"
invoke-virtual {v3, v1, v0}, ${intent_type}->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)${intent_type}
const/4 v0, 0
const/4 v1, 1
if-eq p2, v1, :service
const/4 v1, 2
if-eq p2, v1, :broadcast
invoke-static {p0, v0, v3, v0}, ${pending_type}->getActivity(Landroid/content/Context;I${intent_type}I)${pending_type}
move-result-object v4
goto :pending
:service
invoke-static {p0, v0, v3, v0}, ${pending_type}->getService(Landroid/content/Context;I${intent_type}I)${pending_type}
move-result-object v4
goto :pending
:broadcast
invoke-static {p0, v0, v3, v0}, ${pending_type}->getBroadcast(Landroid/content/Context;I${intent_type}I)${pending_type}
move-result-object v4
:pending
sput-object v4, ${main_type}->pending:${pending_type}
new-instance v3, ${intent_type}
const-string v0, "com.google.android.gms.ui.UNPACKING_REDIRECT"
invoke-direct {v3, v0}, ${intent_type}-><init>(Ljava/lang/String;)V
const-string v0, "${origin_package}"
invoke-virtual {v3, v0}, ${intent_type}->setPackage(Ljava/lang/String;)${intent_type}
const-string v0, "target"
invoke-virtual {v3, v0, v4}, ${intent_type}->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)${intent_type}
sput-object v3, ${main_type}->outer:${intent_type}
new-instance v4, Landroid/os/Bundle;
invoke-direct {v4}, Landroid/os/Bundle;-><init>()V
const-string v0, "intent"
invoke-virtual {v4, v0, v3}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
return-object v4', 5)
}

fn extract_graph() string {
	return method('private static extract(Landroid/os/Bundle;${response_type})${intent_type}', 'const-string v0, "${origin_package}"\ninvoke-static {p0, p1, v0}, ${helper_type}->extract(Landroid/os/Bundle;${response_type}Ljava/lang/String;)${intent_type}\nmove-result-object v0\nreturn-object v0', 1) +
		method('private static rejected(Landroid/os/Bundle;${response_type})V', 'invoke-static {p0, p1}, ${main_type}->extract(Landroid/os/Bundle;${response_type})${intent_type}\nmove-result-object v0\nif-nez v0, :bad\nreturn-void\n' + failure('accepted an invalid graph'), 2)
}

fn fresh_graph() string {
	return 'const/4 v0, 0\ninvoke-static {p0, p1, v0}, ${main_type}->graph(Landroid/content/Context;${response_type}I)Landroid/os/Bundle;\nmove-result-object v2\n'
}

fn reject_graph() string {
	return 'invoke-static {v2, p1}, ${main_type}->rejected(Landroid/os/Bundle;${response_type})V\n'
}

fn positive_and_identity() string {
	mut body := fresh_graph() + '
invoke-static {v2, p1}, ${main_type}->extract(Landroid/os/Bundle;${response_type})${intent_type}
move-result-object v0
sget-object v1, ${main_type}->target:${intent_type}
if-ne v0, v1, :bad
const-string v1, "am_response"
invoke-virtual {v0, v1}, ${intent_type}->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v0
check-cast v0, ${wrapper_type}
invoke-virtual {v0}, ${wrapper_type}->onRequestContinued()V
iget v0, p1, ${record_type}->continued:I
const/4 v1, 1
if-ne v0, v1, :bad
# A matching explicit package is allowed, as is the original null package.
sget-object v0, ${main_type}->target:${intent_type}
const-string v1, "${origin_package}"
invoke-virtual {v0, v1}, ${intent_type}->setPackage(Ljava/lang/String;)${intent_type}
invoke-static {v2, p1}, ${main_type}->extract(Landroid/os/Bundle;${response_type})${intent_type}
move-result-object v1
if-ne v0, v1, :bad
new-instance v0, ${record_type}
invoke-direct {v0}, ${record_type}-><init>()V
invoke-static {v2, v0}, ${main_type}->rejected(Landroid/os/Bundle;${response_type})V
const/4 v0, 0
invoke-static {v2, v0}, ${main_type}->rejected(Landroid/os/Bundle;${response_type})V
invoke-static {v0, p1}, ${main_type}->rejected(Landroid/os/Bundle;${response_type})V
const-string v0, "org.vinix.foreign"
invoke-static {v2, p1, v0}, ${helper_type}->extract(Landroid/os/Bundle;${response_type}Ljava/lang/String;)${intent_type}
move-result-object v0
if-nez v0, :bad
const/4 v0, 0
invoke-static {v2, p1, v0}, ${helper_type}->extract(Landroid/os/Bundle;${response_type}Ljava/lang/String;)${intent_type}
move-result-object v0
if-nez v0, :bad
# Even the same underlying Binder through a distinct callback object fails.
new-instance v0, Landroid/accounts/IAccountAuthenticatorResponse$Stub$Proxy;
invoke-direct {v0, p1}, Landroid/accounts/IAccountAuthenticatorResponse$Stub$Proxy;-><init>(Landroid/os/IBinder;)V
invoke-static {v2, v0}, ${main_type}->rejected(Landroid/os/Bundle;${response_type})V
return-void
' + failure('exact original Intent, retained callback or exact response identity')
	return method('private static positive(Landroid/content/Context;${record_type})V', body, 3)
}

fn target_negatives() string {
	mut body := ''
	for pair in [['outer', 'setAction', 'wrong.action'], ['outer', 'setPackage', 'org.vinix.foreign'],
		['target', 'setPackage', 'org.vinix.foreign']] {
		body += fresh_graph() + 'sget-object v0, ${main_type}->${pair[0]}:${intent_type}\nconst-string v1, "${pair[2]}"\n' +
			'invoke-virtual {v0, v1}, ${intent_type}->${pair[1]}(Ljava/lang/String;)${intent_type}\n' + reject_graph()
	}
	for pair in [['org.vinix.foreign', 'org.vinix.foreign.Target'], [origin_package, '']] {
		body += fresh_graph() + 'new-instance v0, Landroid/content/ComponentName;\nconst-string v1, "${pair[0]}"\nconst-string v3, "${pair[1]}"\n' +
			'invoke-direct {v0, v1, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V\n' +
			'sget-object v1, ${main_type}->target:${intent_type}\ninvoke-virtual {v1, v0}, ${intent_type}->setComponent(Landroid/content/ComponentName;)${intent_type}\n' + reject_graph()
	}
	body += fresh_graph() + 'sget-object v0, ${main_type}->target:${intent_type}\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${intent_type}->setComponent(Landroid/content/ComponentName;)${intent_type}\n' + reject_graph()
	body += fresh_graph() + 'sget-object v0, ${main_type}->target:${intent_type}\nconst-string v1, "am_response"\ninvoke-virtual {v0, v1}, ${intent_type}->removeExtra(Ljava/lang/String;)V\n' + reject_graph()
	return method('private static targets(Landroid/content/Context;${record_type})V', body + 'return-void', 4)
}

fn pending_and_subclasses() string {
	mut body := fresh_graph() + 'sget-object v0, ${main_type}->pending:${pending_type}\ninvoke-virtual {v0}, ${pending_type}->cancel()V\n' + reject_graph()
	for mode in [1, 2, 3] {
		body += 'const/4 v0, ${mode}\ninvoke-static {p0, p1, v0}, ${main_type}->graph(Landroid/content/Context;${response_type}I)Landroid/os/Bundle;\nmove-result-object v2\n' + reject_graph()
	}
	body += fresh_graph() + 'new-instance v0, ${trap_type}\ninvoke-direct {v0}, ${trap_type}-><init>()V\nconst-string v1, "intent"\ninvoke-virtual {v2, v1, v0}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V\n' + reject_graph()
	body += fresh_graph() + 'new-instance v0, Lorg/vinix/bootstrap/InteractionResponseSubclass;\ninvoke-direct {v0, p1}, Lorg/vinix/bootstrap/InteractionResponseSubclass;-><init>(${response_type})V\nsget-object v1, ${main_type}->target:${intent_type}\nconst-string v3, "am_response"\ninvoke-virtual {v1, v3, v0}, ${intent_type}->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)${intent_type}\n' + reject_graph()
	return method('private static pendingAndSubclasses(Landroid/content/Context;${record_type})V', body + 'return-void', 4)
}

fn lazy_bundle() string {
	return method('private static lazy(Ljava/lang/String;)Landroid/os/Bundle;', '
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
new-instance v1, ${poison_type}
invoke-direct {v1}, ${poison_type}-><init>()V
invoke-virtual {v0, p0, v1}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
invoke-virtual {v1, v0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
const/4 v0, 0
invoke-virtual {v1, v0}, Landroid/os/Parcel;->setDataPosition(I)V
const-class v0, ${poison_type}
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
invoke-virtual {v1, v0}, Landroid/os/Parcel;->readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v0
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
return-object v0', 2)
}

fn lazy_negatives() string {
	mut body := 'const-string v0, "intent"\ninvoke-static {v0}, ${main_type}->lazy(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v2\n' + reject_graph()
	for pair in [['outer', 'target'], ['target', 'am_response']] {
		body += fresh_graph() + 'const-string v0, "${pair[1]}"\ninvoke-static {v0}, ${main_type}->lazy(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v0\n' +
			'sget-object v1, ${main_type}->${pair[0]}:${intent_type}\ninvoke-virtual {v1, v0}, ${intent_type}->replaceExtras(Landroid/os/Bundle;)${intent_type}\n' + reject_graph()
	}
	body += 'sget v0, ${creator_type}->calls:I\nif-nez v0, :bad\nreturn-void\n' + failure('lazy Bundle invoked a Parcelable creator')
	return method('private static lazyNegatives(Landroid/content/Context;${record_type})V', body, 3)
}

fn main_class() string {
	mut text := '.class public ${main_type}\n.super Landroid/app/Activity;\n' +
		'.field private static target:${intent_type}\n.field private static outer:${intent_type}\n.field private static pending:${pending_type}\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += graph_builder() + extract_graph() + positive_and_identity() + target_negatives() + pending_and_subclasses() + lazy_bundle() + lazy_negatives()
	mut body := 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v2, ${record_type}\ninvoke-direct {v2}, ${record_type}-><init>()V\n'
	for name in ['positive', 'targets', 'pendingAndSubclasses', 'lazyNegatives'] {
		body += 'invoke-static {p0, v2}, ${main_type}->${name}(Landroid/content/Context;${record_type})V\n'
	}
	body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${pass_marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	text += method('public onCreate(Landroid/os/Bundle;)V', body, 3)
	return text
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	mut classes := poison_classes()
	classes['Main'] = main_class()
	classes['InteractionResponse'] = recording_response()
	classes['InteractionTrapIntent'] = trap_intent()
	classes['InteractionResponseSubclass'] = response_subclass()
	for name, source in classes { os.write_file(root + '/' + name + '.smali', source)! }
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), fixture + '/unsigned.apk', fixture + '/fixture.p12', java, signer] {
		inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex()
	}
	for directory in [tools, root] {
		for name in os.ls(directory)! {
			path := directory + '/' + name
			if os.is_file(path) { inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex() }
		}
	}
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	java_version := os.exec([java, '-version'])
	assert java_version.exit_code == 0
	os.write_file(out + '/build.json', json2.encode(FixtureBuild{
		argv: os.args
		source_revision: revision.output.trim_space()
		inputs_sha256: inputs
		java_version: java_version.output.trim_space()
		apk_sha256: sha256.sum(os.read_bytes(out + '/probe.apk')!).hex()
		pass_marker: pass_marker
		scope: 'synthetic origin-local graph inspection only; no account, network or credential dispatch; APK assembly is not ART execution'
	}, prettify: true) + '\n')!
	println('ACCOUNT-INTERACTION-APK ' + out + '/probe.apk')
	println('ACCOUNT-INTERACTION-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
