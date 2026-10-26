// SPDX-License-Identifier: GPL-2.0-or-later
// ART probe for the authenticator request wire ABI. No authenticator is registered.
module main

import crypto.sha256
import json2
import os

const main_type = 'Lorg/vinix/bootstrap/Main;'
const record_type = 'Lorg/vinix/bootstrap/RecordingAuthenticator;'
const remote_type = 'Lorg/vinix/bootstrap/RemoteAuthenticator;'
const reply_type = 'Lorg/vinix/bootstrap/RecordingReply;'
const request_type = 'Landroid/accounts/IAccountAuthenticator;'
const stub_type = 'Landroid/accounts/IAccountAuthenticator\$Stub;'
const response_type = 'Landroid/accounts/IAccountAuthenticatorResponse;'
const descriptor = 'android.accounts.IAccountAuthenticator'
const pass_marker = 'AUTHENTICATOR-REQUEST-PASS account-parcel fourteen-local fourteen-proxy typed-values typed-nulls response-binder oneway descriptor unknown trailing-data remote-exception runtime-exception parcel-cleanup'

// Keep this independent of the framework provider: parameter ordering is part
// of the test oracle, including adjacent strings with distinct sentinel values.
struct Request {
	name string
	args []string
}

fn requests() []Request {
	return [
		Request{'addAccount', ['string', 'string', 'features', 'bundle']},
		Request{'confirmCredentials', ['account', 'bundle']},
		Request{'getAuthToken', ['account', 'string', 'bundle']},
		Request{'getAuthTokenLabel', ['string']},
		Request{'updateCredentials', ['account', 'string', 'bundle']},
		Request{'editProperties', ['string']},
		Request{'hasFeatures', ['account', 'features']},
		Request{'getAccountRemovalAllowed', ['account']},
		Request{'getAccountCredentialsForCloning', ['account']},
		Request{'addAccountFromCredentials', ['account', 'bundle']},
		Request{'startAddAccountSession', ['string', 'string', 'features', 'bundle']},
		Request{'startUpdateCredentialsSession', ['account', 'string', 'bundle']},
		Request{'finishSession', ['string', 'bundle']},
		Request{'isCredentialsUpdateSuggested', ['account', 'string']},
	]
}

fn arg_type(kind string) string {
	return match kind {
		'string' { 'Ljava/lang/String;' }
		'features' { '[Ljava/lang/String;' }
		'account' { 'Landroid/accounts/Account;' }
		'bundle' { 'Landroid/os/Bundle;' }
		else { panic(kind) }
	}
}

fn signature(request Request) string {
	return request.name + '(' + response_type + request.args.map(arg_type(it)).join('') + ')V'
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "authenticator request: ' +
		stage + '"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn string_check(register string, expected string) string {
	return 'const-string v0, "${expected}"\ninvoke-virtual {v0, ${register}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n' +
		'move-result v0\nif-eqz v0, :bad\n'
}

fn recording_authenticator() string {
	mut text := '.class public ${record_type}\n.super ${stub_type}\n' +
		'.field public mode:I\n.field public calls:I\n.field public code:I\n.field public reply:Landroid/os/IBinder;\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, ${stub_type}-><init>()V\nreturn-void', 0)
	for i, request in requests() {
		code := i + 1
		mut body := 'iget v0, p0, ${record_type}->mode:I\nif-eqz v0, :nulls\nif-eqz p1, :bad\n' +
			'invoke-interface {p1}, ${response_type}->asBinder()Landroid/os/IBinder;\nmove-result-object v0\n' +
			'iget-object v1, p0, ${record_type}->reply:Landroid/os/IBinder;\nif-ne v0, v1, :bad\n'
		for j, kind in request.args {
			param := 'p' + (j + 2).str()
			body += 'if-eqz ${param}, :bad\n'
			match kind {
				'string' { body += string_check(param, 'slot-${code}-arg-${j}') }
				'account' {
					body += 'iget-object v2, ${param}, Landroid/accounts/Account;->name:Ljava/lang/String;\n' + string_check('v2', 'fixture-account') +
						'iget-object v2, ${param}, Landroid/accounts/Account;->type:Ljava/lang/String;\n' + string_check('v2', 'org.vinix.synthetic') +
						'invoke-virtual {${param}}, Landroid/accounts/Account;->getAccessId()Ljava/lang/String;\nmove-result-object v2\n' + string_check('v2', 'fixture-access')
				}
				'bundle' {
					body += 'const-string v0, "request"\ninvoke-virtual {${param}, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\n' +
						'move-result-object v2\n' + string_check('v2', 'bundle-sentinel')
				}
				'features' {
					body += 'array-length v0, ${param}\nconst/4 v1, 3\nif-ne v0, v1, :bad\n' +
						'const/4 v0, 0\naget-object v2, ${param}, v0\n' + string_check('v2', 'feature-left') +
						'const/4 v0, 1\naget-object v2, ${param}, v0\nif-nez v2, :bad\n' +
						'const/4 v0, 2\naget-object v2, ${param}, v0\n' + string_check('v2', 'feature-right')
				}
				else { panic(kind) }
			}
		}
		body += 'invoke-interface {p1}, ${response_type}->onRequestContinued()V\ngoto :accepted\n:nulls\nif-nez p1, :bad\n'
		for j, _ in request.args { body += 'if-nez p${j + 2}, :bad\n' }
		body += ':accepted\nconst/16 v0, ${code}\niput v0, p0, ${record_type}->code:I\n' +
			'iget v0, p0, ${record_type}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${record_type}->calls:I\nreturn-void\n' + failure('slot ${code} arguments')
		text += method('public ' + signature(request), body, 3)
	}
	return text
}

fn recording_reply() string {
	mut text := '.class public ${reply_type}\n.super Landroid/accounts/IAccountAuthenticatorResponse\$Stub;\n.field public calls:I\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/accounts/IAccountAuthenticatorResponse\$Stub;-><init>()V\nreturn-void', 0)
	text += method('public onRequestContinued()V', 'iget v0, p0, ${reply_type}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${reply_type}->calls:I\nreturn-void', 1)
	for sig in ['onResult(Landroid/os/Bundle;)V', 'onError(ILjava/lang/String;)V'] {
		text += method('public ' + sig, 'goto :bad\n' + failure('unexpected response callback'), 2)
	}
	return text
}

fn remote_authenticator() string {
	mut text := '.class public ${remote_type}\n.super Landroid/os/Binder;\n' +
		'.field public target:Landroid/os/IBinder;\n.field public request:Landroid/os/Parcel;\n' +
		'.field public code:I\n.field public mode:I\n.field public transactions:I\n'
	text += method('public constructor <init>(Landroid/os/IBinder;)V', 'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\niput-object p1, p0, ${remote_type}->target:Landroid/os/IBinder;\nreturn-void', 0)
	text += method('public queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;', 'const/4 v0, 0\nreturn-object v0', 1)
	text += method('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', '
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
const/4 v1, 3
if-ne v0, v1, :forward
# Append a word after an otherwise well-formed request.
invoke-virtual {p2}, Landroid/os/Parcel;->dataSize()I
move-result v0
invoke-virtual {p2, v0}, Landroid/os/Parcel;->setDataPosition(I)V
const/16 v0, 99
invoke-virtual {p2, v0}, Landroid/os/Parcel;->writeInt(I)V
const/4 v0, 0
invoke-virtual {p2, v0}, Landroid/os/Parcel;->setDataPosition(I)V
:forward
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
' + failure('oneway flags, null reply, nonempty parcel'), 2)
	return text
}

fn main_class() string {
	mut text := '.class public ${main_type}\n.super Landroid/app/Activity;\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += method('private static account()Landroid/accounts/Account;', 'new-instance v0, Landroid/accounts/Account;\nconst-string v1, "fixture-account"\nconst-string v2, "org.vinix.synthetic"\nconst-string v3, "fixture-access"\ninvoke-direct {v0, v1, v2, v3}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\nreturn-object v0', 4)
	text += method('private static bundle()Landroid/os/Bundle;', 'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "request"\nconst-string v2, "bundle-sentinel"\ninvoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nreturn-object v0', 3)
	text += method('private static features()[Ljava/lang/String;', 'const-string v0, "feature-left"\nconst/4 v1, 0\nconst-string v2, "feature-right"\nfilled-new-array {v0, v1, v2}, [Ljava/lang/String;\nmove-result-object v0\nreturn-object v0', 3)
	for i, request in requests() {
		mut body := 'move-object v0, p0\nmove-object v1, p1\nif-eqz p2, :nulls\n'
		for j, kind in request.args {
			register := 'v' + (j + 2).str()
			if kind == 'string' { body += 'const-string ${register}, "slot-${i + 1}-arg-${j}"\n' }
			else {
				body += 'invoke-static {}, ${main_type}->${kind}()${arg_type(kind)}\nmove-result-object ${register}\n'
			}
		}
		body += 'goto :send\n:nulls\nconst/4 v1, 0\n'
		for j, _ in request.args { body += 'const/4 v${j + 2}, 0\n' }
		body += ':send\ninvoke-interface/range {v0 .. v${request.args.len + 1}}, ${request_type}->${signature(request)}\nreturn-void'
		text += method('private static send${i + 1}(${request_type}${response_type}I)V', body, 7)
	}
	text += method('private static recycled(${remote_type}I)V', 'iget v0, p0, ${remote_type}->code:I\nif-ne v0, p1, :bad\niget-object v0, p0, ${remote_type}->request:Landroid/os/Parcel;\nif-eqz v0, :bad\ninvoke-virtual {v0}, Landroid/os/Parcel;->dataSize()I\nmove-result v1\nif-nez v1, :bad\ninvoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I\nmove-result v1\nif-nez v1, :bad\nreturn-void\n' + failure('proxy parcel cleanup and slot'), 2)
	mut body := 'iput p4, p0, ${record_type}->mode:I\niget v2, p0, ${record_type}->calls:I\n'
	for i, _ in requests() {
		body += 'invoke-static {p2, p3, p4}, ${main_type}->send${i + 1}(${request_type}${response_type}I)V\n' +
			'iget v0, p0, ${record_type}->calls:I\nadd-int/lit8 v1, v2, ${i + 1}\nif-ne v0, v1, :bad\n' +
			'iget v0, p0, ${record_type}->code:I\nconst/16 v1, ${i + 1}\nif-ne v0, v1, :bad\n' +
			'if-eqz p1, :next_${i}\ninvoke-static {p1, v1}, ${main_type}->recycled(${remote_type}I)V\n:next_${i}\n'
	}
	text += method('private static round(${record_type}${remote_type}${request_type}${response_type}I)V', body + 'return-void\n' + failure('all fourteen requests deliver exactly once'), 3)
	text += descriptor_probe()
	text += exception_probe()
	text += account_probe()
	text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, ${main_type}->accountParcel()V
new-instance v2, ${record_type}
invoke-direct {v2}, ${record_type}-><init>()V
new-instance v5, ${reply_type}
invoke-direct {v5}, ${reply_type}-><init>()V
iput-object v5, v2, ${record_type}->reply:Landroid/os/IBinder;
invoke-static {v2}, ${main_type}->descriptors(${record_type})V
new-instance v3, ${remote_type}
invoke-direct {v3, v2}, ${remote_type}-><init>(Landroid/os/IBinder;)V
invoke-static {v3}, ${stub_type}->asInterface(Landroid/os/IBinder;)${request_type}
move-result-object v4
if-eq v4, v2, :bad
invoke-interface {v4}, ${request_type}->asBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, v3, :bad
const/4 v6, 1
const/4 v7, 0
invoke-static {v2, v7, v2, v5, v6}, ${main_type}->round(${record_type}${remote_type}${request_type}${response_type}I)V
invoke-static {v2, v7, v2, v5, v7}, ${main_type}->round(${record_type}${remote_type}${request_type}${response_type}I)V
invoke-static {v2, v3, v4, v5, v6}, ${main_type}->round(${record_type}${remote_type}${request_type}${response_type}I)V
invoke-static {v2, v3, v4, v5, v7}, ${main_type}->round(${record_type}${remote_type}${request_type}${response_type}I)V
iget v0, v5, ${reply_type}->calls:I
const/16 v1, 28
if-ne v0, v1, :bad
invoke-static {v2, v3, v4}, ${main_type}->exceptions(${record_type}${remote_type}${request_type})V
iget v0, v2, ${record_type}->calls:I
const/16 v1, 56
if-ne v0, v1, :bad
iget v0, v3, ${remote_type}->transactions:I
const/16 v1, 70
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Authenticator request contract passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
' + failure('response binder, total deliveries and total proxy transactions'), 8)
	return text
}

fn descriptor_probe() string {
	mut body := '
const/4 v0, 0
invoke-static {v0}, ${stub_type}->asInterface(Landroid/os/IBinder;)${request_type}
move-result-object v0
if-nez v0, :bad
invoke-static {p0}, ${stub_type}->asInterface(Landroid/os/IBinder;)${request_type}
move-result-object v0
if-ne v0, p0, :bad
invoke-virtual {p0}, ${record_type}->asBinder()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p0, :bad
const-string v0, "${descriptor}"
invoke-virtual {p0, v0}, ${record_type}->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v0
if-ne v0, p0, :bad
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
move-result-object v1
' + string_check('v1', descriptor) + '
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const v0, 0x7fffffff
const/4 v1, 0
const/4 v3, 1
invoke-virtual {p0, v0, v2, v1, v3}, ${record_type}->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
if-nez v0, :bad
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
'
	for i, _ in requests() {
		body += 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v2\n' +
			'const-string v0, "wrong.descriptor"\ninvoke-virtual {v2, v0}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n' +
			'const/16 v0, ${i + 1}\nconst/4 v1, 0\nconst/4 v3, 1\n:wrong_start_${i}\n' +
			'invoke-virtual {p0, v0, v2, v1, v3}, ${record_type}->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n:wrong_end_${i}\ngoto :bad\n' +
			'.catch Ljava/lang/SecurityException; {:wrong_start_${i} .. :wrong_end_${i}} :wrong_rejected_${i}\n:wrong_rejected_${i}\nmove-exception v0\n' +
			'invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V\n'
	}
	body += 'iget v0, p0, ${record_type}->calls:I\nif-nez v0, :bad\nreturn-void\n' + failure('local binder, descriptor, unknown slot and fourteen wrong tokens')
	return method('private static descriptors(${record_type})V', body, 4)
}

fn exception_probe() string {
	mut body := 'const/4 v0, 0\niput v0, p0, ${record_type}->mode:I\n'
	for mode in 1 .. 4 {
		exception := match mode { 1 { 'Landroid/os/RemoteException;' } 2 { 'Ljava/lang/IllegalStateException;' } else { 'Landroid/os/BadParcelableException;' } }
		body += 'const/4 v0, ${mode}\niput v0, p1, ${remote_type}->mode:I\n'
		for i, _ in requests() {
			body += 'const/4 v0, 0\n:failed_start_${mode}_${i}\n' +
				'invoke-static {p2, v0, v0}, ${main_type}->send${i + 1}(${request_type}${response_type}I)V\n:failed_end_${mode}_${i}\ngoto :bad\n' +
				'.catch ${exception} {:failed_start_${mode}_${i} .. :failed_end_${mode}_${i}} :failed_${mode}_${i}\n:failed_${mode}_${i}\nmove-exception v0\n' +
				'const/16 v0, ${i + 1}\ninvoke-static {p1, v0}, ${main_type}->recycled(${remote_type}I)V\n'
		}
	}
	body += 'return-void\n' + failure('fourteen transport failures, runtime failures and trailing payloads')
	return method('private static exceptions(${record_type}${remote_type}${request_type})V', body, 2)
}

fn account_probe() string {
	mut body := '
invoke-static {}, ${main_type}->account()Landroid/accounts/Account;
move-result-object v2
invoke-virtual {v2}, Landroid/accounts/Account;->describeContents()I
move-result v0
if-nez v0, :bad
new-instance v3, Landroid/accounts/Account;
const-string v0, "different-access"
invoke-direct {v3, v2, v0}, Landroid/accounts/Account;-><init>(Landroid/accounts/Account;Ljava/lang/String;)V
invoke-virtual {v3, v2}, Landroid/accounts/Account;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v2}, Landroid/accounts/Account;->hashCode()I
move-result v0
invoke-virtual {v3}, Landroid/accounts/Account;->hashCode()I
move-result v1
if-ne v0, v1, :bad
invoke-virtual {v3}, Landroid/accounts/Account;->getAccessId()Ljava/lang/String;
move-result-object v1
' + string_check('v1', 'different-access') + '
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/accounts/Account;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
const-string v0, "fixture-account"
invoke-virtual {v2, v0}, Landroid/accounts/Account;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
new-instance v3, Landroid/accounts/Account;
const-string v0, "other-account"
const-string v1, "org.vinix.synthetic"
invoke-direct {v3, v0, v1}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v3}, Landroid/accounts/Account;->getAccessId()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
invoke-virtual {v2, v3}, Landroid/accounts/Account;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v3
const/4 v0, 0
invoke-virtual {v2, v3, v0}, Landroid/accounts/Account;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v3, v0}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v3}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v1
' + string_check('v1', 'fixture-account') + '
invoke-virtual {v3}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v1
' + string_check('v1', 'org.vinix.synthetic') + '
invoke-virtual {v3}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v1
' + string_check('v1', 'fixture-access') + '
invoke-virtual {v3}, Landroid/os/Parcel;->dataAvail()I
move-result v0
if-nez v0, :bad
const/4 v0, 0
invoke-virtual {v3, v0}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v4, Landroid/accounts/Account;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v4, v3}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v5
check-cast v5, Landroid/accounts/Account;
if-eq v5, v2, :bad
invoke-virtual {v5, v2}, Landroid/accounts/Account;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v5}, Landroid/accounts/Account;->getAccessId()Ljava/lang/String;
move-result-object v1
' + string_check('v1', 'fixture-access') + '
invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V
const/4 v0, 2
invoke-interface {v4, v0}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v3
check-cast v3, [Landroid/accounts/Account;
array-length v0, v3
const/4 v1, 2
if-ne v0, v1, :bad
const/4 v0, 0
aget-object v0, v3, v0
if-nez v0, :bad
'
	for i in 0 .. 4 {
		name := if i == 0 { 'const/4 v0, 0\n' } else if i == 1 { 'const-string v0, ""\n' } else { 'const-string v0, "fixture-account"\n' }
		type_name := if i == 2 { 'const/4 v1, 0\n' } else if i == 3 { 'const-string v1, ""\n' } else { 'const-string v1, "org.vinix.synthetic"\n' }
		body += name + type_name + 'new-instance v2, Landroid/accounts/Account;\n:constructor_start_${i}\n' +
			'invoke-direct {v2, v0, v1}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V\n:constructor_end_${i}\ngoto :bad\n' +
			'.catch Ljava/lang/IllegalArgumentException; {:constructor_start_${i} .. :constructor_end_${i}} :constructor_rejected_${i}\n:constructor_rejected_${i}\nmove-exception v0\n' +
			'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v3\n' + name + type_name +
			'invoke-virtual {v3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
			'invoke-virtual {v3, v1}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0\n' +
			'invoke-virtual {v3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
			'invoke-virtual {v3, v0}, Landroid/os/Parcel;->setDataPosition(I)V\n:parcel_start_${i}\n' +
			'invoke-interface {v4, v3}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\n:parcel_end_${i}\ngoto :bad\n' +
			'.catch Landroid/os/BadParcelableException; {:parcel_start_${i} .. :parcel_end_${i}} :parcel_rejected_${i}\n:parcel_rejected_${i}\nmove-exception v0\n' +
			'invoke-virtual {v3}, Landroid/os/Parcel;->recycle()V\n'
	}
	body += 'return-void\n' + failure('Account parcel order, access ID, equality, arrays and invalid values')
	return method('private static accountParcel()V', body, 6)
}

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

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', main_class())!
	os.write_file(root + '/RecordingAuthenticator.smali', recording_authenticator())!
	os.write_file(root + '/RemoteAuthenticator.smali', remote_authenticator())!
	os.write_file(root + '/RecordingReply.smali', recording_reply())!
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
	println('AUTHENTICATOR-REQUEST-APK ' + out + '/probe.apk')
	println('AUTHENTICATOR-REQUEST-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
