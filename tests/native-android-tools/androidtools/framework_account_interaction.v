// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// These accessors inspect framework-owned fields only after an exact boot-class
// check. They expose no token reconstruction or response replacement operation.
pub fn framework_account_interaction_pending_accessor() string {
	return signature_method('public final vinixAccountActivityIntent()Landroid/content/Intent;',
		'invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v0\n' +
		'const-class v1, Landroid/app/PendingIntent;\nif-ne v0, v1, :invalid\n' +
		'iget-boolean v0, p0, Landroid/app/PendingIntent;->vinixCanceled:Z\nif-nez v0, :invalid\n' +
		'iget v0, p0, Landroid/app/PendingIntent;->type:I\nif-nez v0, :invalid\n' +
		'iget-object v0, p0, Landroid/app/PendingIntent;->intent:Landroid/content/Intent;\nreturn-object v0\n' +
		':invalid\nconst/4 v0, 0\nreturn-object v0')
}

pub fn framework_account_interaction_response_accessor() string {
	return signature_method('public final vinixMatchesResponse(Landroid/accounts/IAccountAuthenticatorResponse;)Z',
		'invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v0\n' +
		'const-class v1, Landroid/accounts/AccountAuthenticatorResponse;\nif-ne v0, v1, :invalid\n' +
		'if-eqz p1, :invalid\niget-object v0, p0, Landroid/accounts/AccountAuthenticatorResponse;->response:Landroid/accounts/IAccountAuthenticatorResponse;\n' +
		'if-ne v0, p1, :invalid\nconst/4 v0, 1\nreturn v0\n:invalid\nconst/4 v0, 0\nreturn v0')
}

// Account interaction extraction must never trigger Parcelable loading. Hold
// the same Bundle monitor as its lazy parcel reader through the map lookup.
pub fn framework_account_interaction_bundle_accessor() string {
	method := signature_method('public final declared-synchronized vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;',
		'invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v0\n' +
		'const-class v1, Landroid/os/Bundle;\nif-ne v0, v1, :invalid\n' +
		'invoke-virtual {p0}, Landroid/os/BaseBundle;->vinixIsParcelled()Z\nmove-result v0\nif-nez v0, :invalid\n' +
		'iget-object v0, p0, Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;\nif-eqz v0, :invalid\n' +
		'invoke-virtual {v0, p1}, Landroid/util/ArrayMap;->get(Ljava/lang/Object;)Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n' +
		':invalid\nconst/4 v0, 0\nreturn-object v0')
	return bundle_parcel_lock(method, '.method public final declared-synchronized vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;\n') or { panic(err) }
}

// GMS retains this whole graph in its own VM. JNI passes the exact registered
// callback object and root-selected package, then holds the returned Intent as
// a global reference. Only an opaque random handle and component metadata leave
// the process. Repeat extraction before launch to recheck cancellation/identity.
pub fn framework_account_interaction_classes() map[string]string {
	owner := 'Landroid/atl/VinixAccountInteraction;'
	mut source := '.class public final ${owner}\n.super Ljava/lang/Object;\n'
	source += signature_method('private static exact(Ljava/lang/Object;Ljava/lang/Class;)Z',
		'if-eqz p0, :invalid\ninvoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;\nmove-result-object v0\n' +
		'if-ne v0, p1, :invalid\nconst/4 v0, 1\nreturn v0\n:invalid\nconst/4 v0, 0\nreturn v0')
	mut body := 'if-eqz p1, :invalid\nif-eqz p2, :invalid\n'
	body += interaction_exact('p0', 'android/os/Bundle')
	body += 'const-string v1, "intent"\ninvoke-virtual {p0, v1}, Landroid/os/Bundle;->vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/content/Intent')
	body += 'check-cast v0, Landroid/content/Intent;\n' +
		'invoke-virtual {v0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;\nmove-result-object v1\n' +
		'invoke-virtual {p2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :invalid\n' +
		'invoke-virtual {v0}, Landroid/content/Intent;->getAction()Ljava/lang/String;\nmove-result-object v1\n' +
		'const-string v2, "com.google.android.gms.ui.UNPACKING_REDIRECT"\n' +
		'invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :invalid\n' +
		'invoke-virtual {v0}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/os/Bundle')
	body += 'check-cast v0, Landroid/os/Bundle;\nconst-string v1, "target"\n' +
		'invoke-virtual {v0, v1}, Landroid/os/Bundle;->vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/app/PendingIntent')
	body += 'check-cast v0, Landroid/app/PendingIntent;\n' +
		'invoke-virtual {v0}, Landroid/app/PendingIntent;->vinixAccountActivityIntent()Landroid/content/Intent;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/content/Intent')
	body += 'check-cast v0, Landroid/content/Intent;\nmove-object v3, v0\n' +
		'invoke-virtual {v3}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/content/ComponentName')
	body += 'check-cast v0, Landroid/content/ComponentName;\n' +
		'invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;\nmove-result-object v1\n' +
		'invoke-virtual {p2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :invalid\n' +
		'invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;\nmove-result-object v1\nif-eqz v1, :invalid\n' +
		'invoke-virtual {v1}, Ljava/lang/String;->length()I\nmove-result v1\nif-eqz v1, :invalid\n' +
		'invoke-virtual {v3}, Landroid/content/Intent;->getPackage()Ljava/lang/String;\nmove-result-object v1\nif-eqz v1, :package_ok\n' +
		'invoke-virtual {p2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :invalid\n:package_ok\n' +
		'invoke-virtual {v3}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/os/Bundle')
	body += 'check-cast v0, Landroid/os/Bundle;\nconst-string v1, "am_response"\n' +
		'invoke-virtual {v0, v1}, Landroid/os/Bundle;->vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\n'
	body += interaction_exact('v0', 'android/accounts/AccountAuthenticatorResponse')
	body += 'check-cast v0, Landroid/accounts/AccountAuthenticatorResponse;\n' +
		'invoke-virtual {v0, p1}, Landroid/accounts/AccountAuthenticatorResponse;->vinixMatchesResponse(Landroid/accounts/IAccountAuthenticatorResponse;)Z\n' +
		'move-result v0\nif-eqz v0, :invalid\nreturn-object v3\n:invalid\nconst/4 v0, 0\nreturn-object v0'
	source += signature_method('public static extract(Landroid/os/Bundle;Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)Landroid/content/Intent;', body)
	return {'android/atl/VinixAccountInteraction': source}
}

fn interaction_exact(register string, class_name string) string {
	return 'const-class v2, L${class_name};\n' +
		'invoke-static {${register}, v2}, Landroid/atl/VinixAccountInteraction;->exact(Ljava/lang/Object;Ljava/lang/Class;)Z\n' +
		'move-result v1\nif-eqz v1, :invalid\n'
}

fn framework_account_interaction(smali string) ! {
	for name, source in framework_account_interaction_classes() {
		path := smali + '/' + name + '.smali'
		if os.exists(path) { return error('account interaction helper already installed') }
		os.write_file(path, source)!
	}
}
