// SPDX-License-Identifier: GPL-2.0-or-later
// ART contract probe for the authenticator callback Binder and Parcelable surface.
module main

import crypto.sha256
import json2
import os

const main_type = 'Lorg/vinix/bootstrap/Main;'
const record_type = 'Lorg/vinix/bootstrap/RecordingResponse;'
const remote_type = 'Lorg/vinix/bootstrap/RemoteResponse;'
const response_type = 'Landroid/accounts/IAccountAuthenticatorResponse;'
const stub_type = 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
const wrapper_type = 'Landroid/accounts/AccountAuthenticatorResponse;'
const pass_marker = 'AUTHENTICATOR-RESPONSE-PASS local proxy oneway descriptor null-bundle intent error parcelable remote-exception runtime-exception parcel-cleanup'

struct FixtureBuild {
	argv            []string
	source_revision string
	inputs_sha256   map[string]string
	java_version    string
	apk_sha256      string
	pass_marker     string
}

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "authenticator response: ' +
		stage + '"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn recording_response() string {
	mut text := '.class public ' + record_type + '\n.super ' + stub_type + '\n' +
		'.field public results:I\n.field public continued:I\n.field public errors:I\n' +
		'.field public result:Landroid/os/Bundle;\n.field public code:I\n.field public message:Ljava/lang/String;\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, ${stub_type}-><init>()V\nreturn-void', 0)
	text += method('public onResult(Landroid/os/Bundle;)V', '
iget v0, p0, ${record_type}->results:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${record_type}->results:I
iput-object p1, p0, ${record_type}->result:Landroid/os/Bundle;
return-void', 1)
	text += method('public onRequestContinued()V', '
iget v0, p0, ${record_type}->continued:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${record_type}->continued:I
return-void', 1)
	text += method('public onError(ILjava/lang/String;)V', '
iget v0, p0, ${record_type}->errors:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${record_type}->errors:I
iput p1, p0, ${record_type}->code:I
iput-object p2, p0, ${record_type}->message:Ljava/lang/String;
return-void', 1)
	return text
}

fn remote_response() string {
	mut text := '.class public ' + remote_type + '\n.super Landroid/os/Binder;\n' +
		'.field public target:Landroid/os/IBinder;\n.field public request:Landroid/os/Parcel;\n' +
		'.field public code:I\n.field public mode:I\n.field public transactions:I\n'
	text += method('public constructor <init>(Landroid/os/IBinder;)V', '
invoke-direct {p0}, Landroid/os/Binder;-><init>()V
iput-object p1, p0, ${remote_type}->target:Landroid/os/IBinder;
return-void', 0)
	text += method('public queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;', 'const/4 v0, 0\nreturn-object v0', 1)
	text += method('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', '
# Capture the actual proxy request before dispatch; retain it to check finally/recycle.
iput-object p2, p0, ${remote_type}->request:Landroid/os/Parcel;
iput p1, p0, ${remote_type}->code:I
iget v0, p0, ${remote_type}->transactions:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${remote_type}->transactions:I
const/4 v0, 1
if-ne p4, v0, :bad
if-nez p3, :bad
invoke-virtual {p2}, Landroid/os/Parcel;->dataSize()I
move-result v0
if-lez v0, :bad
iget v0, p0, ${remote_type}->mode:I
const/4 v1, 1
if-eq v0, v1, :remote_failure
const/4 v1, 2
if-eq v0, v1, :runtime_failure
iget-object v0, p0, ${remote_type}->target:Landroid/os/IBinder;
invoke-interface {v0, p1, p2, p3, p4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
return v0
:remote_failure
new-instance v0, Landroid/os/RemoteException;
invoke-direct {v0}, Landroid/os/RemoteException;-><init>()V
throw v0
:runtime_failure
new-instance v0, Ljava/lang/IllegalStateException;
invoke-direct {v0}, Ljava/lang/IllegalStateException;-><init>()V
throw v0
' + failure('oneway flags, null reply, nonempty request'), 2)
	return text
}

fn main_class() string {
	mut text := '.class public ' + main_type + '\n.super Landroid/app/Activity;\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += method('private static recycled(${remote_type}I)V', '
iget v0, p0, ${remote_type}->code:I
if-ne v0, p1, :bad
iget-object v0, p0, ${remote_type}->request:Landroid/os/Parcel;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->dataSize()I
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v1
if-nez v1, :bad
return-void
' + failure('proxy parcel cleanup and transaction code'), 2)
	text += method('private static local(${record_type})V', '
const/4 v0, 0
invoke-static {v0}, ${stub_type}->asInterface(Landroid/os/IBinder;)${response_type}
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, ${record_type}->asBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p0, :bad
invoke-static {v0}, ${stub_type}->asInterface(Landroid/os/IBinder;)${response_type}
move-result-object v0
if-ne v0, p0, :bad
const-string v0, "android.accounts.IAccountAuthenticatorResponse"
invoke-virtual {p0, v0}, ${record_type}->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v0
if-ne v0, p0, :bad
const-string v0, "wrong.descriptor"
invoke-virtual {p0, v0}, ${record_type}->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v0
if-nez v0, :bad
return-void
' + failure('local interface identity and null binder'), 2)
	text += method('private static descriptors(${record_type})V', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const v0, 0x5f4e5446
const/4 v1, 0
invoke-virtual {p0, v0, v2, v3, v1}, ${record_type}->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v3}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
const-string v1, "android.accounts.IAccountAuthenticatorResponse"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
# A malformed caller must be rejected before the callback runs.
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const-string v0, "wrong.descriptor"
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/os/Parcel;->writeInt(I)V
const/4 v1, 1
:wrong_start
invoke-virtual {p0, v1, v2, v0, v1}, ${record_type}->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:wrong_end
goto :bad
.catch Ljava/lang/SecurityException; {:wrong_start .. :wrong_end} :wrong_rejected
:wrong_rejected
move-exception v0
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
iget v0, p0, ${record_type}->results:I
if-nez v0, :bad
return-void
' + failure('descriptor query and token rejection'), 4)
	text += method('private static payload()Landroid/os/Bundle;', '
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
new-instance v1, Landroid/content/Intent;
const-string v2, "org.vinix.AUTHENTICATE"
invoke-direct {v1, v2}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v2, "challenge"
const-string v3, "response-roundtrip"
invoke-virtual {v1, v2, v3}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
new-instance v2, Landroid/content/ComponentName;
const-string v3, "org.vinix.bootstrap"
const-string v4, "org.vinix.bootstrap.Main"
invoke-direct {v2, v3, v4}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v1, v2}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;
const-string v2, "intent"
invoke-virtual {v0, v2, v1}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
const-string v1, "errorCode"
const/4 v2, 7
invoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putInt(Ljava/lang/String;I)V
const-string v1, "errorMessage"
const-string v2, "intent-needed"
invoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
return-object v0', 5)
	text += method('private static payloadResult(${record_type}Landroid/os/Bundle;)V', '
iget-object v2, p0, ${record_type}->result:Landroid/os/Bundle;
if-eqz v2, :bad
if-eq v2, p1, :bad
const-string v0, "errorCode"
invoke-virtual {v2, v0}, Landroid/os/Bundle;->getInt(Ljava/lang/String;)I
move-result v0
const/4 v1, 7
if-ne v0, v1, :bad
const-string v0, "errorMessage"
invoke-virtual {v2, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "intent-needed"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "intent"
invoke-virtual {v2, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v2
check-cast v2, Landroid/content/Intent;
if-eqz v2, :bad
invoke-virtual {v2}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.AUTHENTICATE"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "challenge"
invoke-virtual {v2, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "response-roundtrip"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v2}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v2
invoke-virtual {v2}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.bootstrap"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v2}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.bootstrap.Main"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + failure('Bundle intent and error payload roundtrip'), 3)
	text += method('private static proxy(${record_type}${remote_type}${response_type})V', '
if-eq p0, p2, :bad
invoke-interface {p2}, ${response_type}->asBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p1, :bad
const/4 v0, 0
invoke-interface {p2, v0}, ${response_type}->onResult(Landroid/os/Bundle;)V
const/4 v0, 1
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
iget v0, p0, ${record_type}->results:I
const/4 v1, 1
if-ne v0, v1, :bad
iget-object v0, p0, ${record_type}->result:Landroid/os/Bundle;
if-nez v0, :bad
invoke-static {}, ${main_type}->payload()Landroid/os/Bundle;
move-result-object v2
invoke-interface {p2, v2}, ${response_type}->onResult(Landroid/os/Bundle;)V
const/4 v0, 1
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
invoke-static {p0, v2}, ${main_type}->payloadResult(${record_type}Landroid/os/Bundle;)V
iget v0, p0, ${record_type}->results:I
const/4 v1, 2
if-ne v0, v1, :bad
invoke-interface {p2}, ${response_type}->onRequestContinued()V
const/4 v0, 2
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
iget v0, p0, ${record_type}->continued:I
const/4 v1, 1
if-ne v0, v1, :bad
const/4 v0, 7
const/4 v1, 0
invoke-interface {p2, v0, v1}, ${response_type}->onError(ILjava/lang/String;)V
const/4 v0, 3
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
iget v0, p0, ${record_type}->code:I
const/4 v1, 7
if-ne v0, v1, :bad
iget-object v0, p0, ${record_type}->message:Ljava/lang/String;
if-nez v0, :bad
iget v0, p0, ${record_type}->errors:I
const/4 v1, 1
if-ne v0, v1, :bad
return-void
' + failure('forced proxy callback delivery'), 3)
	text += method('private static parcelable(${record_type}${remote_type}${response_type})V', '
new-instance v2, ${wrapper_type}
invoke-direct {v2, p2}, ${wrapper_type}-><init>(${response_type})V
invoke-virtual {v2}, ${wrapper_type}->describeContents()I
move-result v0
if-nez v0, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const/4 v0, 0
invoke-virtual {v2, v3, v0}, ${wrapper_type}->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v3, v0}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v1
if-ne v1, p1, :bad
invoke-virtual {v3, v0}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v4, ${wrapper_type}->CREATOR:Landroid/os/Parcelable\$Creator;
invoke-interface {v4, v3}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v2
check-cast v2, ${wrapper_type}
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
const/4 v0, 3
invoke-interface {v4, v0}, Landroid/os/Parcelable\$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v1
check-cast v1, [Landroid/accounts/AccountAuthenticatorResponse;
array-length v0, v1
const/4 v4, 3
if-ne v0, v4, :bad
const/4 v0, 0
aget-object v0, v1, v0
if-nez v0, :bad
invoke-static {}, ${main_type}->payload()Landroid/os/Bundle;
move-result-object v3
invoke-virtual {v2, v3}, ${wrapper_type}->onResult(Landroid/os/Bundle;)V
const/4 v0, 1
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
invoke-static {p0, v3}, ${main_type}->payloadResult(${record_type}Landroid/os/Bundle;)V
invoke-virtual {v2}, ${wrapper_type}->onRequestContinued()V
const/4 v0, 2
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
const/4 v0, 5
const-string v1, "retry-authentication"
invoke-virtual {v2, v0, v1}, ${wrapper_type}->onError(ILjava/lang/String;)V
const/4 v0, 3
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
iget v0, p0, ${record_type}->results:I
const/4 v1, 3
if-ne v0, v1, :bad
iget v0, p0, ${record_type}->continued:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, p0, ${record_type}->errors:I
if-ne v0, v1, :bad
iget v0, p0, ${record_type}->code:I
const/4 v1, 5
if-ne v0, v1, :bad
iget-object v0, p0, ${record_type}->message:Ljava/lang/String;
const-string v1, "retry-authentication"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + failure('Parcelable callback binder, typed array, delivery'), 5)
	text += method('private static exceptions(${record_type}${remote_type}${response_type})V', '
new-instance v2, ${wrapper_type}
invoke-direct {v2, p2}, ${wrapper_type}-><init>(${response_type})V
const/4 v0, 1
iput v0, p1, ${remote_type}->mode:I
# Direct proxy must expose the transport failure and still recycle its request.
:direct_start
invoke-interface {p2}, ${response_type}->onRequestContinued()V
:direct_end
goto :bad
.catch Landroid/os/RemoteException; {:direct_start .. :direct_end} :direct_failed
:direct_failed
move-exception v0
const/4 v0, 2
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
# The Parcelable facade swallows only transport exceptions on all three methods.
const/4 v0, 0
invoke-virtual {v2, v0}, ${wrapper_type}->onResult(Landroid/os/Bundle;)V
const/4 v0, 1
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
invoke-virtual {v2}, ${wrapper_type}->onRequestContinued()V
const/4 v0, 2
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
const/4 v0, 7
const/4 v1, 0
invoke-virtual {v2, v0, v1}, ${wrapper_type}->onError(ILjava/lang/String;)V
const/4 v0, 3
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
const/4 v0, 2
iput v0, p1, ${remote_type}->mode:I
const/4 v0, 0
:runtime_start
invoke-virtual {v2, v0}, ${wrapper_type}->onResult(Landroid/os/Bundle;)V
:runtime_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:runtime_start .. :runtime_end} :runtime_failed
:runtime_failed
move-exception v0
const/4 v0, 1
invoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V
iget v0, p0, ${record_type}->results:I
const/4 v1, 3
if-ne v0, v1, :bad
iget v0, p0, ${record_type}->continued:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, p0, ${record_type}->errors:I
if-ne v0, v1, :bad
iget v0, p1, ${remote_type}->transactions:I
const/16 v1, 12
if-ne v0, v1, :bad
return-void
' + failure('transport failure swallowing and runtime exception propagation'), 3)
	text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v2, ${record_type}
invoke-direct {v2}, ${record_type}-><init>()V
invoke-static {v2}, ${main_type}->local(${record_type})V
invoke-static {v2}, ${main_type}->descriptors(${record_type})V
new-instance v3, ${remote_type}
invoke-direct {v3, v2}, ${remote_type}-><init>(Landroid/os/IBinder;)V
invoke-static {v3}, ${stub_type}->asInterface(Landroid/os/IBinder;)${response_type}
move-result-object v4
invoke-static {v2, v3, v4}, ${main_type}->proxy(${record_type}${remote_type}${response_type})V
invoke-static {v2, v3, v4}, ${main_type}->parcelable(${record_type}${remote_type}${response_type})V
invoke-static {v2, v3, v4}, ${main_type}->exceptions(${record_type}${remote_type}${response_type})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Authenticator response contract passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void', 5)
	return text
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', main_class())!
	os.write_file(root + '/RecordingResponse.smali', recording_response())!
	os.write_file(root + '/RemoteResponse.smali', remote_response())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
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
	println('AUTHENTICATOR-RESPONSE-APK ' + out + '/probe.apk')
	println('AUTHENTICATOR-RESPONSE-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
