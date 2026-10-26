// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// The session is an opaque request number, never a pointer or bearer capability.
// Native callbacks must match both it and this exact registered global object
// against a live trusted slot before accepting an authenticator response.
pub fn framework_account_native_response_class_names() []string {
	return ['android/atl/VinixAuthenticatorResponse']
}

pub fn framework_account_native_response_classes() map[string]string {
	name := framework_account_native_response_class_names()[0]
	type_name := 'L' + name + ';'
	stub := 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
	mut source := '.class public final ${type_name}\n.super ${stub}\n' +
		'.field private final session:J\n'
	source += '\n.method public constructor <init>(J)V\n.locals 0\n' +
		'invoke-direct {p0}, ${stub}-><init>()V\n' +
		'iput-wide p1, p0, ${type_name}->session:J\nreturn-void\n.end method\n'
	for signature in ['onResult(Landroid/os/Bundle;)V', 'onError(ILjava/lang/String;)V',
		'onRequestContinued()V'] {
		source += '\n.method public native ${signature}\n.end method\n'
	}
	return {
		name: source
	}
}
