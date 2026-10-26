// SPDX-License-Identifier: GPL-2.0-or-later
// ART behavior probes. Main uses a synthetic subclass and a nonexistent broker.
// Optional cache Service/Client use the selected authenticator's real SQLite
// cache and broker with fixture values. Neither probe uses Google credentials.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/bootstrap/Main;'
const probe = 'Lorg/vinix/bootstrap/TokenManagerProbe;'
const manager = 'Landroid/accounts/AccountManager;'
const future = 'Landroid/accounts/AccountManagerFuture;'
const pending = 'Landroid/atl/VinixAccountFuture;'
const cache_service = 'Lorg/vinix/bootstrap/TokenCacheService;'
const cache_client = 'Lorg/vinix/bootstrap/TokenCacheClient;'
const descriptions = 'Lorg/vinix/bootstrap/AuthenticatorDescriptionProbe;'
const description = 'Landroid/accounts/AuthenticatorDescription;'
const descriptions_pass = 'ACCOUNT-AUTHENTICATORS-PASS'
const cache_type = 'org.vinix.fixture.account'
const cache_ready = 'ACCOUNT-TOKEN-CACHE-READY owner null-empty exact-invalidation password-clear'
const cache_pass = 'ACCOUNT-TOKEN-CACHE-PASS broker-invalidation exact-multiaccount preserved-other-value'
const cache_persist = 'ACCOUNT-TOKEN-CACHE-PERSIST-PASS cleared-token preserved-other-value'
const cache_client_pass = 'ACCOUNT-TOKEN-CACHE-CLIENT-PASS owner-denied null-type null-token synchronous-broker-ack'
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

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${value}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\ninvoke-virtual {v0}, Ljava/io/PrintStream;->flush()V\n'
}

fn cache_accounts() string {
	return 'new-instance v1, Landroid/accounts/Account;\nconst-string v3, "cache-first"\nconst-string v4, "${cache_type}"\ninvoke-direct {v1, v3, v4}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V\nnew-instance v2, Landroid/accounts/Account;\nconst-string v3, "cache-second"\ninvoke-direct {v2, v3, v4}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn cache_set(account string, key string, value ?string) string {
	return 'const-string v3, "${key}"\n' + if text := value { 'const-string v4, "${text}"\n' } else { 'const/4 v4, 0\n' } +
		'invoke-virtual {v0, ${account}, v3, v4}, ${manager}->setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn cache_expect(account string, key string, value ?string) string {
	mut body := 'const-string v3, "${key}"\ninvoke-virtual {v0, ${account}, v3}, ${manager}->peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v5\n'
	if text := value {
		body += 'const-string v4, "${text}"\ninvoke-virtual {v4, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v5\nif-eqz v5, :bad\n'
	} else { body += 'if-nez v5, :bad\n' }
	return body
}

fn cache_service_class() string {
	mut source := '.class public final ${cache_service}\n.super Landroid/app/Service;\n.implements Ljava/lang/Runnable;\n.field private handler:Landroid/os/Handler;\n.field private attempts:I\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void', 0)
	mut create := 'invoke-super {p0}, Landroid/app/Service;->onCreate()V\ninvoke-static {p0}, ${manager}->get(Landroid/content/Context;)${manager}\nmove-result-object v0\n' + cache_accounts()
	create += 'const/4 v3, 0\ninvoke-virtual {v0, v1, v3, v3}, ${manager}->addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z\nmove-result v5\nif-nez v5, :fresh\nconst-string v3, "cache-phase"\ninvoke-virtual {v0, v1, v3}, ${manager}->getUserData(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v5\nconst-string v4, "complete"\ninvoke-virtual {v4, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v5\nif-eqz v5, :bad\n' + cache_expect('v1', 'broker', none) + cache_expect('v2', 'broker', none) + cache_expect('v2', 'keep', 'different-fixture-value') + marker(cache_persist) + 'return-void\n:fresh\n'
	create += 'const/4 v3, 0\ninvoke-virtual {v0, v2, v3, v3}, ${manager}->addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z\nmove-result v5\nif-eqz v5, :bad\n'
	// Null account and token type must fail before any database mutation.
	for index in 0 .. 4 {
		create += 'const-string v3, "null-check"\nconst/4 v4, 0\n:null_cache_${index}_start\n'
		create += match index {
			0 { 'invoke-virtual {v0, v4, v3}, ${manager}->peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\n' }
			1 { 'invoke-virtual {v0, v1, v4}, ${manager}->peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\n' }
			2 { 'invoke-virtual {v0, v4, v3, v4}, ${manager}->setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V\n' }
			else { 'invoke-virtual {v0, v1, v4, v3}, ${manager}->setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V\n' }
		}
		create += ':null_cache_${index}_end\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:null_cache_${index}_start .. :null_cache_${index}_end} :null_cache_${index}_caught\n:null_cache_${index}_caught\nmove-exception v5\n'
	}
	create += cache_set('v1', 'nullable', 'fixture-value') + cache_expect('v1', 'nullable', 'fixture-value') + cache_set('v1', 'nullable', none) + cache_expect('v1', 'nullable', none)
	create += cache_set('v1', 'empty', '') + cache_set('v2', 'empty', '') + cache_set('v2', 'keep', 'different-fixture-value')
	create += 'const-string v3, "${cache_type}"\nconst/4 v4, 0\ninvoke-virtual {v0, v3, v4}, ${manager}->invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V\n' + cache_expect('v1', 'empty', '')
	create += 'const-string v3, "${cache_type}"\nconst-string v4, ""\ninvoke-virtual {v0, v3, v4}, ${manager}->invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V\n' + cache_expect('v1', 'empty', none) + cache_expect('v2', 'empty', none) + cache_expect('v2', 'keep', 'different-fixture-value')
	for operation in ['setPassword', 'clearPassword'] {
		create += cache_set('v1', 'password-cleared', 'fixture-value')
		create += if operation == 'setPassword' { 'const-string v3, "fixture-password"\ninvoke-virtual {v0, v1, v3}, ${manager}->setPassword(Landroid/accounts/Account;Ljava/lang/String;)V\n' } else { 'invoke-virtual {v0, v1}, ${manager}->clearPassword(Landroid/accounts/Account;)V\n' }
		create += 'invoke-virtual {v0, v1}, ${manager}->getPassword(Landroid/accounts/Account;)Ljava/lang/String;\nmove-result-object v5\n'
		create += if operation == 'setPassword' { 'const-string v4, "fixture-password"\ninvoke-virtual {v4, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v5\nif-eqz v5, :bad\n' } else { 'if-nez v5, :bad\n' }
		create += cache_expect('v1', 'password-cleared', none) + cache_expect('v2', 'keep', 'different-fixture-value')
	}
	create += cache_set('v1', 'broker', 'broker-fixture-value') + cache_set('v2', 'broker', 'broker-fixture-value')
	create += 'new-instance v6, Landroid/os/Handler;\ninvoke-direct {v6}, Landroid/os/Handler;-><init>()V\niput-object v6, p0, ${cache_service}->handler:Landroid/os/Handler;\n' + marker(cache_ready)
	create += 'iget-object v6, p0, ${cache_service}->handler:Landroid/os/Handler;\nconst-wide/16 v3, 100\ninvoke-virtual {v6, p0, v3, v4}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z\nreturn-void\n' + failure('cache owner/null/empty/password')
	source += method('public onCreate()V', create, 7)
	source += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 'new-instance v0, Landroid/os/Binder;\ninvoke-direct {v0}, Landroid/os/Binder;-><init>()V\nconst/4 v1, 0\nconst-string v2, "org.vinix.bootstrap.TokenCacheService"\ninvoke-virtual {v0, v1, v2}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-object v0', 3)
	mut run := 'invoke-static {p0}, ${manager}->get(Landroid/content/Context;)${manager}\nmove-result-object v0\n' + cache_accounts()
	run += 'const-string v3, "broker"\ninvoke-virtual {v0, v1, v3}, ${manager}->peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v5\nif-nez v5, :waiting\n' + cache_expect('v2', 'broker', none) + cache_expect('v2', 'keep', 'different-fixture-value')
	run += 'const-string v3, "cache-phase"\nconst-string v4, "complete"\ninvoke-virtual {v0, v1, v3, v4}, ${manager}->setUserData(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V\n' + marker(cache_pass) + 'return-void\n:waiting\niget v5, p0, ${cache_service}->attempts:I\nadd-int/lit8 v5, v5, 1\niput v5, p0, ${cache_service}->attempts:I\nconst/16 v6, 600\nif-ge v5, v6, :bad\niget-object v6, p0, ${cache_service}->handler:Landroid/os/Handler;\nconst-wide/16 v3, 100\ninvoke-virtual {v6, p0, v3, v4}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z\nreturn-void\n' + failure('cache broker completion deadline')
	source += method('public run()V', run, 7)
	return source
}

// The value probes execute through the production class on ART, including the
// erased Parcelable.Creator interface. v8/v9 are scratch, v10/v11 retain values.
fn description_construct(kind string, package_name string, custom bool, full bool) string {
	custom_value := if custom { '1' } else { '0' }
	return 'new-instance v0, ${description}\nconst-string v1, "${kind}"\nconst-string v2, "${package_name}"\n' +
		'const v3, -0x1\nconst v4, -0x7fffffff\nconst v5, 0x12345678\nconst v6, 0x7\n' +
		if full { 'const/4 v7, ${custom_value}\ninvoke-direct/range {v0 .. v7}, ${description}-><init>(Ljava/lang/String;Ljava/lang/String;IIIIZ)V\n' }
		else { 'invoke-direct/range {v0 .. v6}, ${description}-><init>(Ljava/lang/String;Ljava/lang/String;IIII)V\n' }
}

fn description_expect(register string, kind string, package_name ?string, custom bool, key bool) string {
	mut body := 'iget-object v8, ${register}, ${description}->type:Ljava/lang/String;\nconst-string v9, "${kind}"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n'
	body += 'iget-object v8, ${register}, ${description}->packageName:Ljava/lang/String;\n'
	body += if text := package_name { 'const-string v9, "${text}"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n' } else { 'if-nez v8, :bad\n' }
	for i, name in ['labelId', 'iconId', 'smallIconId', 'accountPreferencesId'] {
		value := if key { '0x0' } else { ['-0x1', '-0x7fffffff', '0x12345678', '0x7'][i] }
		body += 'iget v8, ${register}, ${description}->${name}:I\nconst v9, ${value}\nif-ne v8, v9, :bad\n'
	}
	body += 'iget-boolean v8, ${register}, ${description}->customTokens:Z\n' + if custom { 'const/4 v9, 1\nif-ne v8, v9, :bad\n' } else { 'if-nez v8, :bad\n' }
	return body
}

fn description_values() string {
	mut body := description_construct('fixture-value', 'fixture.package', true, true) + 'move-object v10, v0\n' + description_expect('v10', 'fixture-value', 'fixture.package', true, false)
	body += 'invoke-virtual {v10}, ${description}->describeContents()I\nmove-result v8\nif-nez v8, :bad\n' +
		'invoke-virtual {v10}, ${description}->toString()Ljava/lang/String;\nmove-result-object v8\nconst-string v9, "AuthenticatorDescription {type=fixture-value}"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n'
	body += description_construct('fixture-value', 'other.package', false, false) + 'move-object v11, v0\n' +
		'invoke-virtual {v10, v11}, ${description}->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n' +
		'invoke-virtual {v10}, ${description}->hashCode()I\nmove-result v8\ninvoke-virtual {v11}, ${description}->hashCode()I\nmove-result v9\nif-ne v8, v9, :bad\n'
	for value in ['v10', 'null', 'string', 'different'] {
		body += match value {
			'v10' { 'move-object v11, v10\n' }
			'null' { 'const/4 v11, 0\n' }
			'string' { 'const-string v11, "fixture-value"\n' }
			else { 'const-string v8, "different"\ninvoke-static {v8}, ${description}->newKey(Ljava/lang/String;)${description}\nmove-result-object v11\n' }
		}
		body += 'invoke-virtual {v10, v11}, ${description}->equals(Ljava/lang/Object;)Z\nmove-result v8\n' + if value == 'v10' { 'if-eqz v8, :bad\n' } else { 'if-nez v8, :bad\n' }
	}
	body += 'const-string v8, "fixture-value"\ninvoke-static {v8}, ${description}->newKey(Ljava/lang/String;)${description}\nmove-result-object v11\n' + description_expect('v11', 'fixture-value', none, false, true) +
		'invoke-virtual {v10, v11}, ${description}->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n'
	body += description_construct('', '', false, false) + description_expect('v0', '', '', false, false)
	body += description_construct('', '', false, true) + description_expect('v0', '', '', false, false) + 'return-void\n' + failure('authenticator value constructors/identity')
	return method('private static values()V', body, 12)
}

fn description_invalid() string {
	mut body := ''
	for i in 0 .. 5 {
		body += 'const-string v1, "fixture-value"\nconst-string v2, "fixture.package"\nconst/4 v3, 0\nconst/4 v4, 0\nconst/4 v5, 0\nconst/4 v6, 0\nconst/4 v7, 0\n'
		if i < 4 {
			missing := if i % 2 == 0 { 'v1' } else { 'v2' }
			body += 'const/4 ${missing}, 0\nnew-instance v0, ${description}\n:null_${i}_start\n' +
				if i < 2 { 'invoke-direct/range {v0 .. v7}, ${description}-><init>(Ljava/lang/String;Ljava/lang/String;IIIIZ)V\n' } else { 'invoke-direct/range {v0 .. v6}, ${description}-><init>(Ljava/lang/String;Ljava/lang/String;IIII)V\n' }
		} else {
			body += 'const/4 v1, 0\n:null_${i}_start\ninvoke-static {v1}, ${description}->newKey(Ljava/lang/String;)${description}\n'
		}
		message := if i < 4 && i % 2 == 1 { 'packageName cannot be null' } else { 'type cannot be null' }
		body += ':null_${i}_end\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:null_${i}_start .. :null_${i}_end} :null_${i}_caught\n:null_${i}_caught\nmove-exception v8\ninvoke-virtual {v8}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;\nmove-result-object v8\nconst-string v9, "${message}"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n'
	}
	return method('private static invalid()V', body + 'return-void\n' + failure('authenticator null validation'), 10)
}

fn description_parcels() string {
	mut body := description_construct('fixture-value', 'fixture.package', true, true) + 'move-object v10, v0\n'
	for i in 0 .. 4 {
		if i == 1 { body += 'const-string v8, "fixture-key"\ninvoke-static {v8}, ${description}->newKey(Ljava/lang/String;)${description}\nmove-result-object v10\n' }
		body += 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v11\n'
		if i < 2 {
			body += 'const/4 v8, 0\ninvoke-virtual {v10, v11, v8}, ${description}->writeToParcel(Landroid/os/Parcel;I)V\n'
		} else {
			for text in ['raw-type', 'raw.package'] { body += 'const-string v8, "${text}"\ninvoke-virtual {v11, v8}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' }
			for value in ['-0x1', '-0x7fffffff', '0x12345678', '0x7'] { body += 'const v8, ${value}\ninvoke-virtual {v11, v8}, Landroid/os/Parcel;->writeInt(I)V\n' }
			value := if i == 2 { '0x2' } else { '-0x1' }
			body += 'const/4 v8, ${value}\ninvoke-virtual {v11, v8}, Landroid/os/Parcel;->writeByte(B)V\n'
		}
		body += 'const/4 v8, 0\ninvoke-virtual {v11, v8}, Landroid/os/Parcel;->setDataPosition(I)V\nsget-object v9, ${description}->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-interface {v9, v11}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ${description}\n'
		body += if i == 0 { description_expect('v0', 'fixture-value', 'fixture.package', true, false) }
			else if i == 1 { description_expect('v0', 'fixture-key', none, false, true) }
			else { description_expect('v0', 'raw-type', 'raw.package', false, false) }
		body += 'invoke-virtual {v11}, Landroid/os/Parcel;->recycle()V\n'
	}
	body += 'sget-object v9, ${description}->CREATOR:Landroid/os/Parcelable$Creator;\nconst/4 v8, 2\ninvoke-interface {v9, v8}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;\nmove-result-object v0\ninstance-of v8, v0, [${description}\nif-eqz v8, :bad\narray-length v8, v0\nconst/4 v9, 2\nif-ne v8, v9, :bad\nconst/4 v8, 0\naget-object v9, v0, v8\nif-nez v9, :bad\nconst/4 v8, 1\naget-object v9, v0, v8\nif-nez v9, :bad\n' +
		'sget-object v9, ${description}->CREATOR:Landroid/os/Parcelable$Creator;\nconst/4 v8, -1\n:negative_array_start\ninvoke-interface {v9, v8}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;\n:negative_array_end\ngoto :bad\n.catch Ljava/lang/NegativeArraySizeException; {:negative_array_start .. :negative_array_end} :negative_array_caught\n:negative_array_caught\nmove-exception v8\nreturn-void\n' + failure('authenticator Parcelable order/creator bridges')
	return method('private static parcels()V', body, 12)
}

fn description_registry() string {
	body := 'invoke-static {p0}, ${manager}->get(Landroid/content/Context;)${manager}\nmove-result-object v0\ninvoke-virtual {v0}, ${manager}->getAuthenticatorTypes()[${description}\nmove-result-object v1\nif-eqz v1, :bad\nconst/4 v2, 0\nconst/4 v3, 0\nconst/4 v4, 0\n:next\narray-length v8, v1\nif-ge v2, v8, :found\naget-object v5, v1, v2\nif-eqz v5, :bad\niget-object v8, v5, ${description}->type:Ljava/lang/String;\nconst-string v9, "${cache_type}"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :advance\nadd-int/lit8 v3, v3, 1\nmove-object v4, v5\n:advance\nadd-int/lit8 v2, v2, 1\ngoto :next\n:found\nconst/4 v8, 1\nif-ne v3, v8, :bad\n' +
		'iget-object v8, v4, ${description}->packageName:Ljava/lang/String;\nconst-string v9, "org.vinix.bootstrap"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\n' +
		'iget-boolean v8, v4, ${description}->customTokens:Z\nconst/4 v9, 1\nif-ne v8, v9, :bad\niget v8, v4, ${description}->accountPreferencesId:I\nif-nez v8, :bad\n' +
		'iget v8, v4, ${description}->iconId:I\nif-eqz v8, :bad\niget v9, v4, ${description}->smallIconId:I\nif-ne v8, v9, :bad\n' +
		'iget v8, v4, ${description}->labelId:I\nif-eqz v8, :bad\ninvoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;\nmove-result-object v9\ninvoke-virtual {v9, v8}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;\nmove-result-object v8\nconst-string v9, "Account token fixture"\ninvoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v8\nif-eqz v8, :bad\nreturn-void\n' + failure('authenticated authenticator metadata/resources')
	return method('private static registry(Landroid/content/Context;)V', body, 10)
}

fn descriptions_class() string {
	return '.class public final ${descriptions}\n.super Ljava/lang/Object;\n' + description_values() + description_invalid() + description_parcels() + description_registry() +
		method('public static run(Landroid/content/Context;)V', 'invoke-static {}, ${descriptions}->values()V\ninvoke-static {}, ${descriptions}->invalid()V\ninvoke-static {}, ${descriptions}->parcels()V\ninvoke-static {p0}, ${descriptions}->registry(Landroid/content/Context;)V\n' + marker(descriptions_pass) + 'return-void', 2)
}

fn cache_client_class() string {
	mut source := '.class public final ${cache_client}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	source += method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Ljava/lang/Thread;\ninvoke-direct {v0, p0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V\ninvoke-virtual {v0}, Ljava/lang/Thread;->start()V\nreturn-void', 1)
	mut run := 'invoke-static {p0}, ${descriptions}->run(Landroid/content/Context;)V\ninvoke-static {p0}, ${manager}->get(Landroid/content/Context;)${manager}\nmove-result-object v0\n' + cache_accounts()
	for index in 0 .. 2 {
		run += 'const-string v3, "broker"\nconst-string v4, "forbidden-write"\n:owner_${index}_start\n'
		run += if index == 0 { 'invoke-virtual {v0, v1, v3}, ${manager}->peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;\n' } else { 'invoke-virtual {v0, v1, v3, v4}, ${manager}->setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V\n' }
		run += ':owner_${index}_end\ngoto :bad\n.catch Ljava/lang/SecurityException; {:owner_${index}_start .. :owner_${index}_end} :owner_${index}_caught\n:owner_${index}_caught\nmove-exception v5\n'
	}
	run += 'const/4 v3, 0\nconst/4 v4, 0\n:null_kind_start\ninvoke-virtual {v0, v3, v4}, ${manager}->invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V\n:null_kind_end\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:null_kind_start .. :null_kind_end} :null_kind_caught\n:null_kind_caught\nmove-exception v5\nconst-string v3, "${cache_type}"\ninvoke-virtual {v0, v3, v4}, ${manager}->invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V\nconst-string v4, "broker-fixture-value"\ninvoke-virtual {v0, v3, v4}, ${manager}->invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V\n' + marker(cache_client_pass) + 'return-void\n' + failure('cache client owner/null/broker')
	source += method('public run()V', run, 6)
	return source
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

fn recorded(out string, name string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + name + '.json', json2.encode({
		'argv': json2.Any(args)
		'exit_code': json2.Any(r.exit_code)
		'output': json2.Any(r.output)
	}, prettify: true) + '\n') or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
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
	// Assemble generated probes without rebuilding or signing an APK. The
	// retained output is source/DEX evidence only, never an ART success claim.
	if os.args.len == 5 && os.args[1] == '--smali-check' {
		out := os.abs_path(os.args[2])
		assert !os.exists(out), 'fresh output required'
		os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
		os.mkdir_all(out + '/commands')!
		for name, source in {'Main': main_class(), 'TokenManagerProbe': probe_class(),
			'TokenCacheService': cache_service_class(), 'TokenCacheClient': cache_client_class(),
			'AuthenticatorDescriptionProbe': descriptions_class()} {
			os.write_file(out + '/smali/org/vinix/bootstrap/' + name + '.smali', source)!
		}
		tools, java := os.real_path(os.args[3]), os.real_path(os.args[4])
		mut inputs := map[string]string{}
		for path in [@FILE, os.executable(), java] { inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex() }
		for name in os.ls(tools)! {
			if name.ends_with('.jar') { inputs[tools + '/' + name] = sha256.sum(os.read_bytes(tools + '/' + name)!).hex() }
		}
		os.write_file(out + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
		diagnostics := recorded(out, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex'])
		assert diagnostics.trim_space() == '', diagnostics
		recorded(out, 'disassemble', [java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip'])
		assert os.read_file(out + '/roundtrip/org/vinix/bootstrap/AuthenticatorDescriptionProbe.smali')!.contains('getAuthenticatorTypes()')
		os.cp(@FILE, out + '/builder.v')!
		os.cp(os.executable(), out + '/builder')!
		for path, pin in inputs { assert sha256.sum(os.read_bytes(path)!).hex() == pin, 'input changed: ' + path }
		mut pins := map[string]string{}
		inventory(out, '', mut pins)!
		os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
		println('ACCOUNT-TOKEN-SMALI-PASS source generation and DEX roundtrip; ART not executed')
		return
	}
	if os.args.len !in [6, 8] { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER [AAPT2 FRAMEWORK_RES]') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/commands')!
	os.write_file(root + '/Main.smali', main_class())!
	os.write_file(root + '/TokenManagerProbe.smali', probe_class())!
	os.write_file(root + '/TokenCacheService.smali', cache_service_class())!
	os.write_file(root + '/TokenCacheClient.smali', cache_client_class())!
	os.write_file(root + '/AuthenticatorDescriptionProbe.smali', descriptions_class())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	assembly := recorded(out, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
	if assembly.trim_space() != '' { panic('unexpected assembler diagnostics: ' + assembly) }
	assert os.is_file(dex)
	if os.args.len == 8 {
		aapt, resources := os.real_path(os.args[6]), os.real_path(os.args[7])
		original := os.read_file(fixture + '/AndroidManifest.xml')!
		if original.count('</application>') != 1 { panic('fixture application manifest anchor') }
		components := '<service android:name="org.vinix.bootstrap.TokenCacheService" android:permission="android.permission.BIND_ACCOUNT_AUTHENTICATOR" android:enabled="true" android:exported="true"><intent-filter><action android:name="android.accounts.AccountAuthenticator"/><action android:name="org.vinix.bootstrap.TOKEN_CACHE"/></intent-filter><meta-data android:name="android.accounts.AccountAuthenticator" android:resource="@xml/token_authenticator"/></service><activity android:name="org.vinix.bootstrap.TokenCacheClient" android:exported="true"/>'
		os.write_file(out + '/AndroidManifest.xml', original.replace('</application>', components + '</application>'))!
		os.mkdir_all(out + '/res/values')!
		os.write_file(out + '/res/values/values.xml', '<resources><string name="fixture_name">Account token fixture</string></resources>')!
		os.mkdir_all(out + '/res/xml')!
		os.write_file(out + '/res/xml/token_authenticator.xml', '<account-authenticator xmlns:android="http://schemas.android.com/apk/res/android" android:accountType="${cache_type}" android:label="@string/fixture_name" android:icon="@drawable/fixture_account" android:smallIcon="@drawable/fixture_account" android:customTokens="true"/>')!
		os.mkdir_all(out + '/res/drawable')!
		os.write_file(out + '/res/drawable/fixture_account.xml', '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle"><solid android:color="#123456"/><size android:width="24dp" android:height="24dp"/></shape>')!
		recorded(out, 'compile-resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])
		recorded(out, 'link-resources', [aapt, 'link', '-I', resources, out + '/resources.zip', '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	} else { os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')! }
	recorded(out, 'zip', ['zip', '-q', '-j', out + '/unsigned.apk', dex])
	recorded(out, 'sign', [java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	verification := recorded(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])
	if !verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true') { panic('APK v3 signature verification missing') }
	mut inputs := map[string]json2.Any{}
	for path in [@FILE, os.executable(), fixture + '/unsigned.apk', fixture + '/fixture.p12', java, signer] {
		inputs[os.real_path(path)] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
	}
	if os.args.len == 8 {
		for path in [fixture + '/AndroidManifest.xml', os.args[6], os.args[7]] {
			inputs[os.real_path(path)] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
		}
		manifest_dump := recorded(out, 'manifest', [os.real_path(os.args[6]), 'dump', 'xmltree', out + '/probe.apk', '--file', 'AndroidManifest.xml'])
		for component in ['org.vinix.bootstrap.TokenCacheService', 'org.vinix.bootstrap.TokenCacheClient', 'org.vinix.bootstrap.TOKEN_CACHE', 'android.accounts.AccountAuthenticator', 'android.permission.BIND_ACCOUNT_AUTHENTICATOR'] {
			if !manifest_dump.contains(component) { panic('compiled manifest missing ' + component) }
		}
		authenticator_dump := recorded(out, 'authenticator-xml', [os.real_path(os.args[6]), 'dump', 'xmltree', out + '/probe.apk', '--file', 'res/xml/token_authenticator.xml'])
		for value in ['account-authenticator', cache_type, 'customTokens', 'smallIcon'] {
			if !authenticator_dump.contains(value) { panic('compiled authenticator XML missing ' + value) }
		}
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
		'cache_service': json2.Any('org.vinix.bootstrap.TokenCacheService')
		'cache_client': json2.Any('org.vinix.bootstrap.TokenCacheClient')
		'cache_action': json2.Any('org.vinix.bootstrap.TOKEN_CACHE')
		'cache_account_type': json2.Any(cache_type)
		'authenticator_action': json2.Any('android.accounts.AccountAuthenticator')
		'authenticator_marker': json2.Any(descriptions_pass)
		'cache_markers': json2.Any([cache_ready, descriptions_pass, cache_client_pass, cache_pass, cache_persist])
		'cache_manifest': json2.Any(os.args.len == 8)
		'scope': json2.Any('Main: synthetic subclass overloads and production no-backend errors, nonexistent socket required. Optional TokenCacheService: selected authenticator with authenticated root channel and fresh data directory; real JNI/SQLite fixture cache values only. TokenCacheClient: normal app using real broker socket after service READY. Restart service with same data directory for persistence marker. No Google credentials/network; APK assembly is not ART execution.')
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
