// SPDX-License-Identifier: GPL-2.0-or-later
// Real ART probe for modeled Intent value parceling; no network or credentials.
module main

import crypto.sha256
import json2
import os

const main_type = 'Lorg/vinix/bootstrap/Main;'
const record_type = 'Lorg/vinix/bootstrap/RecordingResponse;'
const stub_type = 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
const intent_type = 'Landroid/content/Intent;'
const pass_marker = 'INTENT-PARCEL-PASS values categories selector component source-bounds response-binder bundle cursor typed-array null-clear atomic-read unsupported malformed clip-rejected'

struct FixtureBuild {
	argv []string
	source_revision string
	inputs_sha256 map[string]string
	java_version string
	apk_sha256 string
	pass_marker string
}

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Intent parcel: ' +
		stage + '"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn recording_response() string {
	return '.class public ' + record_type + '\n.super ' + stub_type + '\n.field public continued:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, ${stub_type}-><init>()V\nreturn-void', 0) +
		method('public onResult(Landroid/os/Bundle;)V', 'return-void', 0) +
		method('public onError(ILjava/lang/String;)V', 'return-void', 0) +
		method('public onRequestContinued()V', 'iget v0, p0, ${record_type}->continued:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${record_type}->continued:I\nreturn-void', 1)
}

fn full_intent() string {
	mut body := 'new-instance v0, ${intent_type}\nconst-string v1, "org.vinix.AUTHENTICATE"\n' +
		'invoke-direct {v0, v1}, ${intent_type}-><init>(Ljava/lang/String;)V\n'
	for pair in [['setIdentifier', 'parcel-request-identifier'], ['addCategory', 'org.vinix.CATEGORY_ONE'],
		['addCategory', 'org.vinix.CATEGORY_TWO']] {
		body += 'const-string v1, "${pair[1]}"\ninvoke-virtual {v0, v1}, ${intent_type}->${pair[0]}(Ljava/lang/String;)${intent_type}\n'
	}
	body += '
const-string v1, "https://example.invalid/signin?challenge=opaque%20value#fragment"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
const-string v2, "application/vnd.vinix.challenge"
invoke-virtual {v0, v1, v2}, ${intent_type}->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)${intent_type}
const v1, 0x14000001
invoke-virtual {v0, v1}, ${intent_type}->setFlags(I)${intent_type}
new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.bootstrap"
const-string v3, "org.vinix.bootstrap.Main"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${intent_type}->setComponent(Landroid/content/ComponentName;)${intent_type}
new-instance v1, Landroid/graphics/Rect;
const/4 v2, -0x1
const/4 v3, 0x2
const/16 v4, 300
const/16 v5, 400
invoke-direct {v1, v2, v3, v4, v5}, Landroid/graphics/Rect;-><init>(IIII)V
invoke-virtual {v0, v1}, ${intent_type}->setSourceBounds(Landroid/graphics/Rect;)V
new-instance v1, ${intent_type}
const-string v2, "org.vinix.SELECT"
invoke-direct {v1, v2}, ${intent_type}-><init>(Ljava/lang/String;)V
const-string v2, "org.vinix.selector"
invoke-virtual {v1, v2}, ${intent_type}->setPackage(Ljava/lang/String;)${intent_type}
const-string v2, "selector-extra"
const-string v3, "selector-payload"
invoke-virtual {v1, v2, v3}, ${intent_type}->putExtra(Ljava/lang/String;Ljava/lang/String;)${intent_type}
invoke-virtual {v0, v1}, ${intent_type}->setSelector(${intent_type})V
const-string v1, "challenge"
const-string v2, "response-roundtrip"
invoke-virtual {v0, v1, v2}, ${intent_type}->putExtra(Ljava/lang/String;Ljava/lang/String;)${intent_type}
new-instance v1, Landroid/accounts/AccountAuthenticatorResponse;
invoke-direct {v1, p0}, Landroid/accounts/AccountAuthenticatorResponse;-><init>(Landroid/accounts/IAccountAuthenticatorResponse;)V
const-string v2, "response"
invoke-virtual {v0, v2, v1}, ${intent_type}->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)${intent_type}
return-object v0'
	return method('private static full(${record_type})${intent_type}', body, 6)
}

// All expected values are literal API-visible expectations, independent of the
// provider's storage names and the codec's read implementation.
fn assert_string(receiver string, signature string, expected string) string {
	return 'invoke-virtual {${receiver}}, ${intent_type}->${signature}\nmove-result-object v0\n' +
		'const-string v1, "${expected}"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\n'
}

fn values() string {
	mut body := ''
	for pair in [['getAction()Ljava/lang/String;', 'org.vinix.AUTHENTICATE'],
		['getType()Ljava/lang/String;', 'application/vnd.vinix.challenge'],
		['getIdentifier()Ljava/lang/String;', 'parcel-request-identifier'],
		['getDataString()Ljava/lang/String;', 'https://example.invalid/signin?challenge=opaque%20value#fragment']] {
		body += assert_string('p0', pair[0], pair[1])
	}
	body += 'invoke-virtual {p0}, ${intent_type}->getFlags()I\nmove-result v0\nconst v1, 0x14000001\nif-ne v0, v1, :bad\n'
	for category in ['org.vinix.CATEGORY_ONE', 'org.vinix.CATEGORY_TWO'] {
		body += 'const-string v0, "${category}"\ninvoke-virtual {p0, v0}, ${intent_type}->hasCategory(Ljava/lang/String;)Z\nmove-result v0\nif-eqz v0, :bad\n'
	}
	body += 'invoke-virtual {p0}, ${intent_type}->getCategories()Ljava/util/Set;\nmove-result-object v0\ninvoke-interface {v0}, Ljava/util/Set;->size()I\nmove-result v0\nconst/4 v1, 2\nif-ne v0, v1, :bad\n' +
		'invoke-virtual {p0}, ${intent_type}->getComponent()Landroid/content/ComponentName;\nmove-result-object v2\nif-eqz v2, :bad\n'
	for pair in [['getPackageName', 'org.vinix.bootstrap'], ['getClassName', 'org.vinix.bootstrap.Main']] {
		body += 'invoke-virtual {v2}, Landroid/content/ComponentName;->${pair[0]}()Ljava/lang/String;\nmove-result-object v0\nconst-string v1, "${pair[1]}"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\n'
	}
	body += 'invoke-virtual {p0}, ${intent_type}->getSourceBounds()Landroid/graphics/Rect;\nmove-result-object v2\nif-eqz v2, :bad\n'
	for pair in [['left', '-1'], ['top', '2'], ['right', '300'], ['bottom', '400']] {
		body += 'iget v0, v2, Landroid/graphics/Rect;->${pair[0]}:I\nconst/16 v1, ${pair[1]}\nif-ne v0, v1, :bad\n'
	}
	body += 'invoke-virtual {p0}, ${intent_type}->getSelector()${intent_type}\nmove-result-object v2\nif-eqz v2, :bad\n'
	body += assert_string('v2', 'getAction()Ljava/lang/String;', 'org.vinix.SELECT')
	body += assert_string('v2', 'getPackage()Ljava/lang/String;', 'org.vinix.selector')
	body += '
const-string v0, "selector-extra"
invoke-virtual {v2, v0}, ${intent_type}->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "selector-payload"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, ${intent_type}->getPackage()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, ${intent_type}->getClipData()Landroid/content/ClipData;
move-result-object v0
if-nez v0, :bad
const-string v0, "challenge"
invoke-virtual {p0, v0}, ${intent_type}->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "response-roundtrip"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "response"
invoke-virtual {p0, v0}, ${intent_type}->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v0
check-cast v0, Landroid/accounts/AccountAuthenticatorResponse;
invoke-virtual {v0}, Landroid/accounts/AccountAuthenticatorResponse;->onRequestContinued()V
iget v0, p1, ${record_type}->continued:I
const/4 v1, 1
if-ne v0, v1, :bad
return-void
' + failure('API-visible values and response Binder')
	return method('private static values(${intent_type}${record_type})V', body, 3)
}

fn roundtrip() string {
	return method('private static roundtrip(${record_type})V', '
invoke-static {p0}, ${main_type}->full(${record_type})${intent_type}
move-result-object v2
new-instance v3, Landroid/os/Bundle;
invoke-direct {v3}, Landroid/os/Bundle;-><init>()V
const-string v0, "intent"
invoke-virtual {v3, v0, v2}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
invoke-virtual {v4, v3}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
const v0, 0x34567812
invoke-virtual {v4, v0}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v4}, Landroid/os/Parcel;->dataPosition()I
move-result v5
const/4 v0, 0
invoke-virtual {v4, v0}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v4}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;
move-result-object v3
const-string v0, "intent"
invoke-virtual {v3, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v3
check-cast v3, ${intent_type}
if-eq v3, v2, :bad
if-eqz v3, :bad
invoke-static {v3, p0}, ${main_type}->values(${intent_type}${record_type})V
invoke-virtual {v4}, Landroid/os/Parcel;->readInt()I
move-result v0
const v1, 0x34567812
if-ne v0, v1, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->dataPosition()I
move-result v0
if-ne v0, v5, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->dataSize()I
move-result v0
if-ne v0, v5, :bad
invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V
sget-object v0, ${intent_type}->CREATOR:Landroid/os/Parcelable\$Creator;
const/4 v1, 2
invoke-interface {v0, v1}, Landroid/os/Parcelable\$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v0
instance-of v2, v0, [Landroid/content/Intent;
if-eqz v2, :bad
array-length v0, v0
if-ne v0, v1, :bad
return-void
' + failure('Bundle parcel cursor, object separation, typed creator array'), 6)
}

fn null_clear() string {
	mut body := '
invoke-static {p0}, ${main_type}->full(${record_type})${intent_type}
move-result-object v2
const-string v0, "stale.package"
invoke-virtual {v2, v0}, ${intent_type}->setPackage(Ljava/lang/String;)${intent_type}
const-string v0, "stale-label"
const-string v1, "stale clip"
invoke-static {v0, v1}, Landroid/content/ClipData;->newPlainText(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;
move-result-object v0
invoke-virtual {v2, v0}, ${intent_type}->setClipData(Landroid/content/ClipData;)V
new-instance v3, ${intent_type}
invoke-direct {v3}, ${intent_type}-><init>()V
const/4 v0, 0
invoke-virtual {v3, v0}, ${intent_type}->replaceExtras(Landroid/os/Bundle;)${intent_type}
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
invoke-virtual {v3, v4, v0}, ${intent_type}->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v4, v0}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v2, v4}, ${intent_type}->readFromParcel(Landroid/os/Parcel;)V
invoke-virtual {v4}, Landroid/os/Parcel;->dataPosition()I
move-result v0
invoke-virtual {v4}, Landroid/os/Parcel;->dataSize()I
move-result v1
if-ne v0, v1, :bad
'
	for signature in ['getAction()Ljava/lang/String;', 'getData()Landroid/net/Uri;',
		'getType()Ljava/lang/String;', 'getIdentifier()Ljava/lang/String;', 'getPackage()Ljava/lang/String;',
		'getComponent()Landroid/content/ComponentName;', 'getSourceBounds()Landroid/graphics/Rect;',
		'getCategories()Ljava/util/Set;', 'getSelector()${intent_type}',
		'getClipData()Landroid/content/ClipData;', 'getExtras()Landroid/os/Bundle;'] {
		body += 'invoke-virtual {v2}, ${intent_type}->${signature}\nmove-result-object v0\nif-nez v0, :bad\n'
	}
	body += 'invoke-virtual {v2}, ${intent_type}->getFlags()I\nmove-result v0\nif-nez v0, :bad\ninvoke-virtual {v4}, Landroid/os/Parcel;->recycle()V\nreturn-void\n' + failure('null values replace stale fields')
	return method('private static nullClear(${record_type})V', body, 5)
}

fn wire_string(value string) string {
	load := if value == '' { 'const/4 v0, 0' } else { 'const-string v0, "' + value + '"' }
	return load + '\ninvoke-virtual {v2, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
}

fn wire_int(value int) string {
	return 'const v0, ${value}\ninvoke-virtual {v2, v0}, Landroid/os/Parcel;->writeInt(I)V\n'
}

// Invalid wire states are authored directly rather than using the provider.
// Each case must throw and leave the receiving Intent unchanged.
fn reject_case(kind int) string {
	mut body := 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v2\n'
	body += wire_string('replacement-action')
	body += wire_int(if kind == 0 { 2 } else if kind == 1 { 1 } else { 0 })
	if kind == 1 { body += wire_string('') }
	body += wire_string('') + wire_string('') + wire_int(0) + wire_int(if kind == 2 { 1 } else { 0 })
	body += wire_string('') + wire_string(if kind == 9 { 'org.vinix.bootstrap' } else { '' })
	if kind == 9 { body += wire_string('') }
	body += wire_int(if kind == 3 { 2 } else { 0 })
	body += wire_int(if kind == 4 { -1 } else if kind in [10, 11] { 2 } else { 0 })
	if kind in [10, 11] {
		body += wire_string('duplicate-category') + wire_string(if kind == 10 { 'duplicate-category' } else { '' })
	}
	body += wire_int(if kind == 5 { 2 } else { 0 }) + wire_int(if kind == 6 { 1 } else { 0 })
	body += wire_int(if kind == 7 { 0 } else { -2 })
	body += 'const/4 v0, 0\ninvoke-virtual {v2, v0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V\n'
	body += wire_int(if kind == 8 { 1 } else { 0 })
	body += '
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v4, ${record_type}
invoke-direct {v4}, ${record_type}-><init>()V
invoke-static {v4}, ${main_type}->full(${record_type})${intent_type}
move-result-object v3
:read_start
invoke-virtual {v3, v2}, ${intent_type}->readFromParcel(Landroid/os/Parcel;)V
:read_end
goto :bad
.catch Landroid/os/BadParcelableException; {:read_start .. :read_end} :rejected
:rejected
move-exception v0
invoke-static {v3, v4}, ${main_type}->values(${intent_type}${record_type})V
'
	body += 'invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V\nreturn-void\n' + failure('invalid wire case ${kind}, atomic read')
	return method('private static reject${kind}()V', body, 5)
}

fn clip_rejected() string {
	return method('private static clipRejected()V', '
new-instance v2, ${intent_type}
invoke-direct {v2}, ${intent_type}-><init>()V
const-string v0, "label"
const-string v1, "fixture content"
invoke-static {v0, v1}, Landroid/content/ClipData;->newPlainText(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;
move-result-object v0
invoke-virtual {v2, v0}, ${intent_type}->setClipData(Landroid/content/ClipData;)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const/4 v0, 0
:write_start
invoke-virtual {v2, v3, v0}, ${intent_type}->writeToParcel(Landroid/os/Parcel;I)V
:write_end
goto :bad
.catch Ljava/lang/UnsupportedOperationException; {:write_start .. :write_end} :rejected
:rejected
move-exception v0
invoke-virtual {v3}, Landroid/os/Parcel;->dataPosition()I
move-result v0
if-nez v0, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->dataSize()I
move-result v0
if-nez v0, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
return-void
' + failure('ClipData must reject before writing'), 4)
}

fn main_class() string {
	mut text := '.class public ' + main_type + '\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		full_intent() + values() + roundtrip() + null_clear() + clip_rejected()
	mut run := 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\n' +
		'new-instance v2, ${record_type}\ninvoke-direct {v2}, ${record_type}-><init>()V\n' +
		'invoke-static {v2}, ${main_type}->roundtrip(${record_type})V\n' +
		'invoke-static {v2}, ${main_type}->nullClear(${record_type})V\n' +
		'invoke-static {}, ${main_type}->clipRejected()V\n'
	for kind in 0 .. 12 {
		text += reject_case(kind)
		run += 'invoke-static {}, ${main_type}->reject${kind}()V\n'
	}
	run += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${pass_marker}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n' +
		'new-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\n' +
		'const-string v1, "Intent parcel contract passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n' +
		'invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void'
	text += method('public onCreate(Landroid/os/Bundle;)V', run, 3)
	return text
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	if os.exists(out) || os.is_link(out) { panic('fresh fixture output required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', main_class())!
	os.write_file(root + '/RecordingResponse.smali', recording_response())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	os.cp(@FILE, out + '/fixture-source.v')!
	os.cp(os.executable(), out + '/fixture-builder')!
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
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
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
	}, prettify: true) + '\n')!
	println('INTENT-PARCEL-APK ' + out + '/probe.apk')
	println('INTENT-PARCEL-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
