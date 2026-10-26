// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic authenticator base API checks; never registers a real account.
module main

import crypto.sha256
import json2
import os

const main_type = 'Lorg/vinix/bootstrap/Main;'
const core_type = 'Lorg/vinix/bootstrap/CoreAuthenticator;'
const full_type = 'Lorg/vinix/bootstrap/FullAuthenticator;'
const context_type = 'Lorg/vinix/bootstrap/PermissionContext;'
const reply_type = 'Lorg/vinix/bootstrap/RecordingReply;'
const base_type = 'Landroid/accounts/AbstractAccountAuthenticator;'
const wrapper_type = 'Landroid/accounts/AccountAuthenticatorResponse;'
const request_type = 'Landroid/accounts/IAccountAuthenticator;'
const response_type = 'Landroid/accounts/IAccountAuthenticatorResponse;'
const pass_marker = 'AUTHENTICATOR-BASE-PASS fourteen-dispatch permission-denied-before-dispatch result error-mapping async-null label default-removal default-cloning default-sessions suggested-false no-account-registration'

struct Request {
	name string
	args []string
}

// Independent transport oracle: the seven core abstract methods appear first.
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

fn method(signature string, body string, locals int) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn wire_signature(request Request) string {
	return request.name + '(' + response_type + request.args.map(arg_type(it)).join('') + ')V'
}

fn base_signature(request Request) string {
	return if request.name == 'getAuthTokenLabel' {
		'getAuthTokenLabel(Ljava/lang/String;)Ljava/lang/String;'
	} else {
		request.name + '(' + wrapper_type + request.args.map(arg_type(it)).join('') + ')Landroid/os/Bundle;'
	}
}

fn failure(stage string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "authenticator base: ${stage}"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn equal_string(register string, expected string) string {
	return 'const-string v0, "${expected}"\ninvoke-virtual {v0, ${register}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\n'
}

fn permission_context() string {
	mut text := '.class public ${context_type}\n.super Landroid/content/ContextWrapper;\n.field public allowed:Z\n.field public checks:I\n'
	text += method('public constructor <init>()V', 'const/4 v0, 0\ninvoke-direct {p0, v0}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\nreturn-void', 1)
	text += method('public checkCallingOrSelfPermission(Ljava/lang/String;)I', equal_string('p1', 'android.permission.ACCOUNT_MANAGER') +
		'iget v0, p0, ${context_type}->checks:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${context_type}->checks:I\n' +
		'iget-boolean v0, p0, ${context_type}->allowed:Z\nif-eqz v0, :denied\nconst/4 v0, 0\nreturn v0\n:denied\nconst/4 v0, -1\nreturn v0\n' + failure('exact permission checked'), 2)
	return text
}

fn recording_reply() string {
	mut text := '.class public ${reply_type}\n.super Landroid/accounts/IAccountAuthenticatorResponse$Stub;\n' +
		'.field public volatile results:I\n.field public volatile errors:I\n.field public volatile continued:I\n' +
		'.field public volatile result:Landroid/os/Bundle;\n.field public resultThread:Ljava/lang/Thread;\n.field public volatile code:I\n.field public volatile message:Ljava/lang/String;\n.field public failError:Z\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/accounts/IAccountAuthenticatorResponse$Stub;-><init>()V\nreturn-void', 0)
	text += method('public onResult(Landroid/os/Bundle;)V', 'invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;\nmove-result-object v0\niput-object v0, p0, ${reply_type}->resultThread:Ljava/lang/Thread;\niput-object p1, p0, ${reply_type}->result:Landroid/os/Bundle;\niget v0, p0, ${reply_type}->results:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${reply_type}->results:I\nreturn-void', 1)
	text += method('public onError(ILjava/lang/String;)V', 'iget-boolean v0, p0, ${reply_type}->failError:Z\nif-eqz v0, :record\nnew-instance v0, Landroid/os/RemoteException;\ninvoke-direct {v0}, Landroid/os/RemoteException;-><init>()V\nthrow v0\n:record\niput p1, p0, ${reply_type}->code:I\niput-object p2, p0, ${reply_type}->message:Ljava/lang/String;\niget v0, p0, ${reply_type}->errors:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${reply_type}->errors:I\nreturn-void', 1)
	text += method('public onRequestContinued()V', 'iget v0, p0, ${reply_type}->continued:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${reply_type}->continued:I\nreturn-void', 1)
	text += method('public reset()V', 'const/4 v0, 0\niput v0, p0, ${reply_type}->results:I\niput v0, p0, ${reply_type}->errors:I\niput v0, p0, ${reply_type}->continued:I\niput v0, p0, ${reply_type}->code:I\niput-object v0, p0, ${reply_type}->result:Landroid/os/Bundle;\niput-object v0, p0, ${reply_type}->resultThread:Ljava/lang/Thread;\niput-object v0, p0, ${reply_type}->message:Ljava/lang/String;\nreturn-void', 1)
	return text
}

fn authenticator(full bool) string {
	cls := if full { full_type } else { core_type }
	super_type := if full { core_type } else { base_type }
	mut text := '.class public ${cls}\n.super ${super_type}\n'
	if !full {
		text += '.field public calls:I\n.field public slot:I\n.field public mode:I\n.field public lastBundle:Landroid/os/Bundle;\n.field public lastAccount:Landroid/accounts/Account;\n'
	}
	text += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, ${super_type}-><init>(Landroid/content/Context;)V\nreturn-void', 0)
	if !full { text += answer_method() }
	for i, request in requests() {
		if full == (i < 7) { continue }
		mut body := ''
		for j, kind in request.args {
			param := 'p${j + if request.name == 'getAuthTokenLabel' { 1 } else { 2 }}'
			if i == 4 && kind == 'bundle' {
				// Mode eight independently checks the base's null-options update quirk.
				body += 'iget v0, p0, ${core_type}->mode:I\nconst/16 v1, 8\nif-ne v0, v1, :nonnull_options\nif-nez ${param}, :bad\niput-object ${param}, p0, ${core_type}->lastBundle:Landroid/os/Bundle;\ngoto :options_checked\n:nonnull_options\n'
			}
			body += 'if-eqz ${param}, :bad\n'
			match kind {
				'string' { body += equal_string(param, 'argument-${i + 1}-${j}') }
				'account' {
					body += 'iput-object ${param}, p0, ${core_type}->lastAccount:Landroid/accounts/Account;\niget-object v2, ${param}, Landroid/accounts/Account;->name:Ljava/lang/String;\n' + equal_string('v2', 'synthetic-account')
				}
				'bundle' {
					body += 'iput-object ${param}, p0, ${core_type}->lastBundle:Landroid/os/Bundle;\nconst-string v0, "request"\ninvoke-virtual {${param}, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v2\n' + equal_string('v2', 'request-sentinel')
				}
				'features' {
					body += 'array-length v0, ${param}\nconst/4 v1, 2\nif-ne v0, v1, :bad\nconst/4 v0, 0\naget-object v2, ${param}, v0\n' + equal_string('v2', 'feature-left') + 'const/4 v0, 1\naget-object v2, ${param}, v0\nif-nez v2, :bad\n'
				}
				else { panic(kind) }
			}
			if i == 4 && kind == 'bundle' { body += ':options_checked\n' }
		}
		body += 'const/16 v0, ${i + 1}\n'
		if request.name == 'getAuthTokenLabel' {
			body += 'const/4 v1, 0\ninvoke-virtual {p0, v1, v0}, ${core_type}->answer(${wrapper_type}I)Landroid/os/Bundle;\n' +
				'iget v0, p0, ${core_type}->mode:I\nconst/4 v1, 1\nif-eq v0, v1, :null\nconst-string v0, "label-sentinel"\nreturn-object v0\n:null\nconst/4 v0, 0\nreturn-object v0\n'
		} else {
			body += 'invoke-virtual {p0, p1, v0}, ${core_type}->answer(${wrapper_type}I)Landroid/os/Bundle;\nmove-result-object v0\nreturn-object v0\n'
		}
		text += method('public ' + base_signature(request), body + failure('slot ${i + 1} arguments'), 3)
	}
	return text
}

fn answer_method() string {
	mut body := 'iget v0, p0, ${core_type}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${core_type}->calls:I\niput p2, p0, ${core_type}->slot:I\n' +
		'iget v0, p0, ${core_type}->mode:I\nconst/4 v1, 1\nif-eq v0, v1, :null\n'
	for i, exception in ['Landroid/accounts/NetworkErrorException;',
		'Ljava/lang/UnsupportedOperationException;', 'Ljava/lang/IllegalArgumentException;',
		'Ljava/lang/IllegalStateException;'] {
		body += 'const/4 v1, ${i + 2}\nif-eq v0, v1, :throw_${i}\n'
	}
	body += 'const/4 v1, 7\nif-eq v0, v1, :throw_error\n'
	body += 'new-instance v2, Landroid/os/Bundle;\ninvoke-direct {v2}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "answer"\nconst-string v3, "result-sentinel"\ninvoke-virtual {v2, v1, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nconst/4 v1, 6\nif-ne v0, v1, :result\n' +
		'invoke-virtual {p1}, ${wrapper_type}->onRequestContinued()V\ninvoke-virtual {p1, v2}, ${wrapper_type}->onResult(Landroid/os/Bundle;)V\n:null\nconst/4 v0, 0\nreturn-object v0\n:result\nreturn-object v2\n'
	for i, exception in ['Landroid/accounts/NetworkErrorException;',
		'Ljava/lang/UnsupportedOperationException;', 'Ljava/lang/IllegalArgumentException;',
		'Ljava/lang/IllegalStateException;'] {
		body += ':throw_${i}\nnew-instance v0, ${exception}\nconst-string v1, "synthetic-error"\ninvoke-direct {v0, v1}, ${exception}-><init>(Ljava/lang/String;)V\nthrow v0\n'
	}
	body += ':throw_error\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "synthetic-error"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
	return method('public answer(${wrapper_type}I)Landroid/os/Bundle;', body, 4)
}

fn sends() string {
	mut text := ''
	for i, request in requests() {
		mut body := 'move-object v0, p0\nmove-object v1, p1\n'
		for j, kind in request.args {
			register := 'v${j + 2}'
			if kind == 'string' {
				body += 'const-string ${register}, "argument-${i + 1}-${j}"\n'
			} else {
				body += 'invoke-static {}, ${main_type}->${kind}()${arg_type(kind)}\nmove-result-object ${register}\n'
			}
		}
		body += 'invoke-interface/range {v0 .. v${request.args.len + 1}}, ${request_type}->${wire_signature(request)}\nreturn-void'
		text += method('private static send${i + 1}(${request_type}${response_type})V', body, 6)
	}
	return text
}

fn main_class() string {
	mut text := '.class public ${main_type}\n.super Landroid/app/Activity;\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += method('private static account()Landroid/accounts/Account;', 'new-instance v0, Landroid/accounts/Account;\nconst-string v1, "synthetic-account"\nconst-string v2, "org.vinix.synthetic"\ninvoke-direct {v0, v1, v2}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V\nreturn-object v0', 3)
	text += method('private static bundle()Landroid/os/Bundle;', 'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "request"\nconst-string v2, "request-sentinel"\ninvoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nreturn-object v0', 3)
	text += method('private static features()[Ljava/lang/String;', 'const-string v0, "feature-left"\nconst/4 v1, 0\nfilled-new-array {v0, v1}, [Ljava/lang/String;\nmove-result-object v0\nreturn-object v0', 2)
	text += sends()
	text += dispatch_probe()
	text += wait_probe()
	text += defaults_probe()
	text += method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\n' +
		'invoke-static {}, ${main_type}->dispatch()V\ninvoke-static {}, ${main_type}->defaults()V\n' +
		'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${pass_marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n' +
		'new-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Authenticator base contract passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void', 2)
	return text
}

fn dispatch_probe() string {
	mut body := 'new-instance v2, ${context_type}\ninvoke-direct {v2}, ${context_type}-><init>()V\nnew-instance v3, ${full_type}\ninvoke-direct {v3, v2}, ${full_type}-><init>(Landroid/content/Context;)V\nnew-instance v5, ${reply_type}\ninvoke-direct {v5}, ${reply_type}-><init>()V\n' +
		'invoke-virtual {v3}, ${base_type}->getIBinder()Landroid/os/IBinder;\nmove-result-object v4\ninvoke-virtual {v3}, ${base_type}->getIBinder()Landroid/os/IBinder;\nmove-result-object v0\nif-ne v0, v4, :bad\n' +
		'invoke-static {v4}, Landroid/accounts/IAccountAuthenticator$Stub;->asInterface(Landroid/os/IBinder;)${request_type}\nmove-result-object v4\n'
	for i, _ in requests() {
		body += ':denied_start_${i}\ninvoke-static {v4, v5}, ${main_type}->send${i + 1}(${request_type}${response_type})V\n:denied_end_${i}\ngoto :bad\n' +
			'.catch Ljava/lang/SecurityException; {:denied_start_${i} .. :denied_end_${i}} :denied_${i}\n:denied_${i}\nmove-exception v0\n'
	}
	body += 'iget v0, v3, ${core_type}->calls:I\nif-nez v0, :bad\niget v0, v5, ${reply_type}->errors:I\nif-nez v0, :bad\niget v0, v5, ${reply_type}->results:I\nif-nez v0, :bad\niget v0, v2, ${context_type}->checks:I\nconst/16 v1, 14\nif-ne v0, v1, :bad\nconst/4 v0, 1\niput-boolean v0, v2, ${context_type}->allowed:Z\n'
	for mode in 0 .. 7 {
		for i, request in requests() {
			if mode == 6 && request.name == 'getAuthTokenLabel' { continue }
			body += 'invoke-virtual {v5}, ${reply_type}->reset()V\nconst/4 v0, ${mode}\niput v0, v3, ${core_type}->mode:I\n' +
				'invoke-static {v4, v5}, ${main_type}->send${i + 1}(${request_type}${response_type})V\niget v0, v3, ${core_type}->slot:I\nconst/16 v1, ${i + 1}\nif-ne v0, v1, :bad\n'
			if mode >= 2 && mode <= 5 {
				code := [3, 6, 7, 1][mode - 2]
				body += 'iget v0, v5, ${reply_type}->results:I\nif-nez v0, :bad\niget v0, v5, ${reply_type}->errors:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\niget v0, v5, ${reply_type}->code:I\nconst/4 v1, ${code}\nif-ne v0, v1, :bad\niget-object v6, v5, ${reply_type}->message:Ljava/lang/String;\n' +
					equal_string('v6', if mode == 2 {
						'synthetic-error'
					} else {
						request.name + if mode == 5 { ' failed' } else { ' not supported' }
					})
			} else if mode == 1 && request.name != 'getAuthTokenLabel' {
				body += 'iget v0, v5, ${reply_type}->results:I\nif-nez v0, :bad\niget v0, v5, ${reply_type}->errors:I\n'
				body += if request.name == 'addAccount' {
					'const/4 v1, 1\nif-ne v0, v1, :bad\niget v0, v5, ${reply_type}->code:I\nconst/4 v1, 5\nif-ne v0, v1, :bad\niget-object v6, v5, ${reply_type}->message:Ljava/lang/String;\n' + equal_string('v6', 'null bundle returned')
				} else {
					'if-nez v0, :bad\n'
				}
			} else {
				body += 'iget v0, v5, ${reply_type}->errors:I\n'
				body += if mode == 6 && request.name == 'addAccount' {
					'const/4 v1, 1\nif-ne v0, v1, :bad\niget v0, v5, ${reply_type}->code:I\nconst/4 v1, 5\nif-ne v0, v1, :bad\niget-object v6, v5, ${reply_type}->message:Ljava/lang/String;\n' + equal_string('v6', 'null bundle returned')
				} else {
					'if-nez v0, :bad\n'
				}
				body += 'iget v0, v5, ${reply_type}->results:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\niget-object v6, v5, ${reply_type}->result:Landroid/os/Bundle;\nif-eqz v6, :bad\n'
				key := if request.name == 'getAuthTokenLabel' {
					'authTokenLabelKey'
				} else {
					'answer'
				}
				body += 'const-string v0, "${key}"\ninvoke-virtual {v6, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n'
				if mode == 1 {
					body += 'if-nez v1, :bad\n'
				} else {
					body += equal_string('v1', if request.name == 'getAuthTokenLabel' {
						'label-sentinel'
					} else {
						'result-sentinel'
					})
				}
				if request.name == 'getAuthTokenLabel' {
					body += 'const-string v0, "authTokenLabelKey"\ninvoke-virtual {v6, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v0\nif-eqz v0, :bad\n'
				}
			}
			body += 'iget v0, v5, ${reply_type}->continued:I\nconst/4 v1, ${if mode == 6 {
				1
			} else {
				0
			}}\nif-ne v0, v1, :bad\n'
		}
	}
	body += 'iget v0, v3, ${core_type}->calls:I\nconst/16 v1, 97\nif-ne v0, v1, :bad\niget v0, v2, ${context_type}->checks:I\nconst/16 v1, 111\nif-ne v0, v1, :bad\n'
	body += 'invoke-virtual {v5}, ${reply_type}->reset()V\nconst/4 v0, 1\niput-boolean v0, v5, ${reply_type}->failError:Z\nconst/4 v0, 3\niput v0, v3, ${core_type}->mode:I\n:remote_start\ninvoke-static {v4, v5}, ${main_type}->send1(${request_type}${response_type})V\n:remote_end\ngoto :bad\n.catch Landroid/os/RemoteException; {:remote_start .. :remote_end} :remote_failed\n:remote_failed\nmove-exception v0\nconst/4 v0, 0\niput-boolean v0, v5, ${reply_type}->failError:Z\nconst/4 v0, 7\niput v0, v3, ${core_type}->mode:I\n:error_start\ninvoke-static {v4, v5}, ${main_type}->send1(${request_type}${response_type})V\n:error_end\ngoto :bad\n.catch Ljava/lang/AssertionError; {:error_start .. :error_end} :error_failed\n:error_failed\nmove-exception v0\niget v0, v5, ${reply_type}->errors:I\nif-nez v0, :bad\niget v0, v5, ${reply_type}->results:I\nif-nez v0, :bad\nreturn-void\n' + failure('fourteen dispatch, permission, null, result and exceptions')
	return method('private static dispatch()V', body, 7)
}

fn defaults_probe() string {
	mut body := 'new-instance v2, ${context_type}\ninvoke-direct {v2}, ${context_type}-><init>()V\nconst/4 v0, 1\niput-boolean v0, v2, ${context_type}->allowed:Z\nnew-instance v3, ${core_type}\ninvoke-direct {v3, v2}, ${core_type}-><init>(Landroid/content/Context;)V\nnew-instance v4, ${reply_type}\ninvoke-direct {v4}, ${reply_type}-><init>()V\nnew-instance v5, ${wrapper_type}\ninvoke-direct {v5, v4}, ${wrapper_type}-><init>(${response_type})V\ninvoke-static {}, ${main_type}->account()Landroid/accounts/Account;\nmove-result-object v6\n' +
		'invoke-virtual {v3, v5, v6}, ${base_type}->getAccountRemovalAllowed(${wrapper_type}Landroid/accounts/Account;)Landroid/os/Bundle;\nmove-result-object v7\n'
	body += boolean_bundle('v7', true)
	body += 'iget v0, v4, ${reply_type}->results:I\nif-nez v0, :bad\niget v0, v4, ${reply_type}->errors:I\nif-nez v0, :bad\n'
	for request in ['getAccountCredentialsForCloning', 'addAccountFromCredentials'] {
		body += 'invoke-virtual {v4}, ${reply_type}->reset()V\n'
		body += if request == 'addAccountFromCredentials' {
			'invoke-static {}, ${main_type}->bundle()Landroid/os/Bundle;\nmove-result-object v7\ninvoke-virtual {v3, v5, v6, v7}, ${base_type}->${request}(${wrapper_type}Landroid/accounts/Account;Landroid/os/Bundle;)Landroid/os/Bundle;\n'
		} else {
			'invoke-virtual {v3, v5, v6}, ${base_type}->${request}(${wrapper_type}Landroid/accounts/Account;)Landroid/os/Bundle;\n'
		}
		body += 'move-result-object v0\nif-nez v0, :bad\ninvoke-static {v4}, ${main_type}->awaitResult(${reply_type})V\niget-object v7, v4, ${reply_type}->result:Landroid/os/Bundle;\n' + boolean_bundle('v7', false)
	}
	body += 'invoke-virtual {v4}, ${reply_type}->reset()V\nconst-string v7, "suggestion-status"\ninvoke-virtual {v3, v5, v6, v7}, ${base_type}->isCredentialsUpdateSuggested(${wrapper_type}Landroid/accounts/Account;Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v7\n' + boolean_bundle('v7', false) +
		'iget v0, v4, ${reply_type}->results:I\nif-nez v0, :bad\niget v0, v4, ${reply_type}->errors:I\nif-nez v0, :bad\n'
	body += 'iget v0, v3, ${core_type}->calls:I\nif-nez v0, :bad\n'
	body += add_session_probe()
	body += update_session_probe()
	body += invalid_session_probe()
	body += null_options_probe()
	body += 'return-void\n' + failure('default removal, clone, suggested and session contracts')
	return method('private static defaults()V', body, 12)
}

fn boolean_bundle(register string, expected bool) string {
	return 'if-eqz ${register}, :bad\nconst-string v0, "booleanResult"\ninvoke-virtual {${register}, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v0\nif-eqz v0, :bad\nconst-string v0, "booleanResult"\ninvoke-virtual {${register}, v0}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z\nmove-result v0\nconst/4 v1, ${if expected {
		1
	} else {
		0
	}}\nif-ne v0, v1, :bad\n'
}

fn wait_probe() string {
	return method('private static awaitResult(${reply_type})V', 'const/16 v2, 300\n:wait\niget v0, p0, ${reply_type}->results:I\nif-nez v0, :ready\niget v0, p0, ${reply_type}->errors:I\nif-nez v0, :bad\nconst-wide/16 v0, 10\ninvoke-static {v0, v1}, Landroid/os/SystemClock;->sleep(J)V\nadd-int/lit8 v2, v2, -1\nif-gtz v2, :wait\ngoto :bad\n:ready\nconst/4 v1, 1\nif-ne v0, v1, :bad\niget v0, p0, ${reply_type}->errors:I\nif-nez v0, :bad\niget-object v0, p0, ${reply_type}->resultThread:Ljava/lang/Thread;\nif-eqz v0, :bad\ninvoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;\nmove-result-object v1\nif-eq v0, v1, :bad\nreturn-void\n' + failure('bounded asynchronous result exactly once on another thread'), 3)
}

fn no_internal_keys(register string) string {
	mut body := ''
	for key in ['android.accounts.AbstractAccountAuthenticato.KEY_AUTH_TOKEN_TYPE',
		'android.accounts.AbstractAccountAuthenticator.KEY_REQUIRED_FEATURES',
		'android.accounts.AbstractAccountAuthenticator.KEY_OPTIONS',
		'android.accounts.AbstractAccountAuthenticator.KEY_ACCOUNT'] {
		body += 'const-string v0, "${key}"\ninvoke-virtual {${register}, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v0\nif-nez v0, :bad\n'
	}
	return body
}

fn add_session_probe() string {
	return 'invoke-virtual {v4}, ${reply_type}->reset()V\nconst-string v7, "argument-1-0"\nconst-string v8, "argument-1-1"\ninvoke-static {}, ${main_type}->features()[Ljava/lang/String;\nmove-result-object v9\ninvoke-static {}, ${main_type}->bundle()Landroid/os/Bundle;\nmove-result-object v10\n' +
		'move-object v0, v3\nmove-object v1, v5\nmove-object v2, v7\nmove-object v11, v3\nmove-object v3, v8\nmove-object v8, v4\nmove-object v4, v9\nmove-object v9, v5\nmove-object v5, v10\n' +
		'invoke-virtual/range {v0 .. v5}, ${base_type}->startAddAccountSession(${wrapper_type}Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v0\nmove-object v3, v11\nmove-object v4, v8\nmove-object v5, v9\nif-nez v0, :bad\ninvoke-static {v4}, ${main_type}->awaitResult(${reply_type})V\n' +
		'iget-object v7, v4, ${reply_type}->result:Landroid/os/Bundle;\nconst-string v0, "accountSessionBundle"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\n' +
		'const-string v0, "android.accounts.AbstractAccountAuthenticato.KEY_AUTH_TOKEN_TYPE"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' + equal_string('v1', 'argument-1-1') +
		'const-string v0, "android.accounts.AbstractAccountAuthenticator.KEY_REQUIRED_FEATURES"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getStringArray(Ljava/lang/String;)[Ljava/lang/String;\nmove-result-object v8\nif-eqz v8, :bad\narray-length v0, v8\nconst/4 v1, 2\nif-ne v0, v1, :bad\nconst/4 v0, 0\naget-object v1, v8, v0\n' + equal_string('v1', 'feature-left') + 'const/4 v0, 1\naget-object v1, v8, v0\nif-nez v1, :bad\n' +
		'const-string v0, "android.accounts.AbstractAccountAuthenticator.KEY_OPTIONS"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v1\nif-ne v1, v10, :bad\n' +
		'const-string v0, "merged-extra"\nconst-string v1, "merged-value"\ninvoke-virtual {v7, v0, v1}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nconst-string v8, "argument-1-0"\ninvoke-virtual {v3, v5, v8, v7}, ${base_type}->finishSession(${wrapper_type}Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\niget v0, v3, ${core_type}->slot:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\niget-object v7, v3, ${core_type}->lastBundle:Landroid/os/Bundle;\nconst-string v0, "merged-extra"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' + equal_string('v1', 'merged-value') +
		'if-ne v7, v10, :bad\n' + no_internal_keys('v7')
}

fn update_session_probe() string {
	return 'invoke-virtual {v4}, ${reply_type}->reset()V\nconst-string v7, "argument-5-1"\ninvoke-static {}, ${main_type}->bundle()Landroid/os/Bundle;\nmove-result-object v8\ninvoke-virtual {v3, v5, v6, v7, v8}, ${base_type}->startUpdateCredentialsSession(${wrapper_type}Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v0\nif-nez v0, :bad\ninvoke-static {v4}, ${main_type}->awaitResult(${reply_type})V\n' +
		'iget-object v7, v4, ${reply_type}->result:Landroid/os/Bundle;\nconst-string v0, "accountSessionBundle"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\nconst-string v0, "android.accounts.AbstractAccountAuthenticator.KEY_ACCOUNT"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;\nmove-result-object v1\nif-ne v1, v6, :bad\n' +
		'const-string v0, "merged-extra"\nconst-string v1, "merged-value"\ninvoke-virtual {v7, v0, v1}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nconst-string v9, "synthetic-type"\ninvoke-virtual {v3, v5, v9, v7}, ${base_type}->finishSession(${wrapper_type}Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\niget v0, v3, ${core_type}->slot:I\nconst/4 v1, 5\nif-ne v0, v1, :bad\n' +
		'iget-object v0, v3, ${core_type}->lastAccount:Landroid/accounts/Account;\nif-ne v0, v6, :bad\niget-object v0, v3, ${core_type}->lastBundle:Landroid/os/Bundle;\nif-ne v0, v8, :bad\nconst-string v0, "merged-extra"\ninvoke-virtual {v8, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' + equal_string('v1', 'merged-value') + no_internal_keys('v8') +
		'iget v0, v3, ${core_type}->calls:I\nconst/4 v1, 2\nif-ne v0, v1, :bad\n'
}

fn invalid_session_probe() string {
	mut body := 'invoke-virtual {v4}, ${reply_type}->reset()V\n'
	for i in 0 .. 2 {
		body += if i == 0 {
			'const-string v7, ""\ninvoke-static {}, ${main_type}->bundle()Landroid/os/Bundle;\nmove-result-object v8\n'
		} else {
			'const-string v7, "synthetic-type"\nconst/4 v8, 0\n'
		}
		body += 'invoke-virtual {v3, v5, v7, v8}, ${base_type}->finishSession(${wrapper_type}Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\nconst-string v0, "errorCode"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getInt(Ljava/lang/String;)I\nmove-result v0\nconst/4 v1, 7\nif-ne v0, v1, :bad\n'
	}
	body += 'iget v0, v4, ${reply_type}->results:I\nif-nez v0, :bad\nconst-string v7, "synthetic-type"\ninvoke-static {}, ${main_type}->bundle()Landroid/os/Bundle;\nmove-result-object v8\ninvoke-virtual {v3, v5, v7, v8}, ${base_type}->finishSession(${wrapper_type}Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v7\niget-object v0, v4, ${reply_type}->result:Landroid/os/Bundle;\nif-ne v0, v7, :bad\niget v0, v4, ${reply_type}->results:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\nconst-string v0, "errorCode"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getInt(Ljava/lang/String;)I\nmove-result v0\nconst/4 v1, 6\nif-ne v0, v1, :bad\niget v0, v3, ${core_type}->calls:I\nconst/4 v1, 2\nif-ne v0, v1, :bad\n'
	return body
}

fn null_options_probe() string {
	return 'invoke-virtual {v4}, ${reply_type}->reset()V\nconst/16 v0, 8\niput v0, v3, ${core_type}->mode:I\nconst-string v7, "argument-5-1"\nconst/4 v8, 0\ninvoke-virtual {v3, v5, v6, v7, v8}, ${base_type}->startUpdateCredentialsSession(${wrapper_type}Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v0\nif-nez v0, :bad\ninvoke-static {v4}, ${main_type}->awaitResult(${reply_type})V\niget-object v7, v4, ${reply_type}->result:Landroid/os/Bundle;\nconst-string v0, "accountSessionBundle"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\nconst-string v0, "android.accounts.AbstractAccountAuthenticator.KEY_OPTIONS"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v0\nif-eqz v0, :bad\nconst-string v0, "android.accounts.AbstractAccountAuthenticator.KEY_OPTIONS"\ninvoke-virtual {v7, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v0\nif-nez v0, :bad\nconst-string v0, "merged-extra"\nconst-string v1, "merged-value"\ninvoke-virtual {v7, v0, v1}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nconst-string v9, "synthetic-type"\ninvoke-virtual {v3, v5, v9, v7}, ${base_type}->finishSession(${wrapper_type}Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v7\nif-eqz v7, :bad\niget v0, v3, ${core_type}->slot:I\nconst/4 v1, 5\nif-ne v0, v1, :bad\niget-object v0, v3, ${core_type}->lastBundle:Landroid/os/Bundle;\nif-nez v0, :bad\niget v0, v3, ${core_type}->calls:I\nconst/4 v1, 3\nif-ne v0, v1, :bad\n'
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
	if os.exists(out) || os.is_link(out) { panic('fresh output directory required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	for name, source in {
		'Main':              main_class()
		'CoreAuthenticator': authenticator(false)
		'FullAuthenticator': authenticator(true)
		'PermissionContext': permission_context()
		'RecordingReply':    recording_reply()
	} {
		os.write_file(root + '/' + name + '.smali', source)!
	}
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali',
		'-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	checked([java, '-jar', signer, 'verify', out + '/probe.apk'])
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), fixture + '/unsigned.apk', fixture + '/fixture.p12', java,
		signer] {
		inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex()
	}
	for directory in [tools, root] {
		for name in os.ls(directory)! {
			path := directory + '/' + name
			if os.is_file(path) {
				inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex()
			}
		}
	}
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	java_version := os.exec([java, '-version'])
	assert java_version.exit_code == 0
	os.write_file(out + '/build.json', json2.encode(FixtureBuild{os.args, revision.output.trim_space(), inputs, java_version.output.trim_space(), sha256.sum(os.read_bytes(out + '/probe.apk')!).hex(), pass_marker},
		prettify: true
	) + '\n')!
	println('AUTHENTICATOR-BASE-APK ' + out + '/probe.apk')
	println('AUTHENTICATOR-BASE-APK-SHA256 ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
