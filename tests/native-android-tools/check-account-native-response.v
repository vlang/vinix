// SPDX-License-Identifier: GPL-2.0-or-later
// ABI/DEX guard only. Native slot authentication and real authenticator delivery
// require the separate native account-service runtime checks.
module main

import androidtools
import os

fn validate_response(classes map[string]string) ! {
	name := 'android/atl/VinixAuthenticatorResponse'
	if classes.len != 1 || name !in classes {
		return error('unexpected native authenticator response class set')
	}
	source := classes[name]
	if !source.starts_with('.class public final L${name};\n' +
		'.super Landroid/accounts/IAccountAuthenticatorResponse\$Stub;\n') {
		return error('native response must be final and extend the Binder response stub')
	}
	if source.count('.field ') != 1 || !source.contains('\n.field private final session:J\n') {
		return error('native response must contain only its immutable opaque session number')
	}
	constructor := '.method public constructor <init>(J)V\n.locals 0\n' +
		'invoke-direct {p0}, Landroid/accounts/IAccountAuthenticatorResponse\$Stub;-><init>()V\n' +
		'iput-wide p1, p0, L${name};->session:J\nreturn-void\n.end method\n'
	if source.count('.method ') != 4 || source.count('.end method') != 4
		|| !source.contains(constructor) || source.count('invoke-') != 1
		|| source.count('iput-') != 1 {
		return error('unexpected native response constructor or Java callback body')
	}
	for signature in ['onResult(Landroid/os/Bundle;)V', 'onError(ILjava/lang/String;)V',
		'onRequestContinued()V'] {
		if source.count('.method public native ${signature}\n.end method\n') != 1 {
			return error('missing or non-instance native authenticator callback: ' + signature)
		}
	}
}

fn main() {
	assert os.args.len in [1, 3], 'usage: check-account-native-response [TOOLS JAVA]'
	classes := androidtools.framework_account_native_response_classes()
	assert androidtools.framework_account_native_response_class_names() == [
		'android/atl/VinixAuthenticatorResponse',
	]
	validate_response(classes)!
	name := 'android/atl/VinixAuthenticatorResponse'
	source := classes[name]
	mut rejected := 0
	for invalid in [
		source.replace('.class public final ', '.class public '),
		source.replace('.super Landroid/accounts/IAccountAuthenticatorResponse\$Stub;',
			'.super Ljava/lang/Object;'),
		source.replace('.field private final session:J', '.field public final session:J'),
		source.replace('.field private final session:J', '.field private session:J'),
		source + '.field private pointer:J\n',
		source.replace('<init>(J)V', '<init>(I)V'),
		source.replace('iput-wide p1, p0,', 'iput-wide p2, p0,'),
		source.replace('.method public native onResult', '.method public static native onResult'),
		source.replace('onError(ILjava/lang/String;)V', 'onError(JLjava/lang/String;)V'),
		source.replace('.method public native onRequestContinued()V\n.end method',
			'.method public onRequestContinued()V\n.locals 0\nreturn-void\n.end method'),
	] {
		assert invalid != source
		validate_response({
			name: invalid
		}) or {
			rejected++
			continue
		}
		panic('native response ABI guard accepted a negative mutation')
	}
	assert rejected == 10
	if os.args.len == 3 {
		work := os.join_path(os.temp_dir(), 'vinix-account-native-response-' + os.getpid().str())
		os.mkdir_all(work + '/smali/android/atl')!
		defer { os.rmdir_all(work) or {} }
		for class_name, text in classes {
			os.write_file(work + '/smali/' + class_name + '.smali', text)!
		}
		dex := work + '/classes.dex'
		androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
		assert os.read_bytes(dex)!.len > 112
		println('ANDROID-ACCOUNT-NATIVE-RESPONSE-ASSEMBLY-PASS one callback class produces DEX')
	}
	println('ANDROID-ACCOUNT-NATIVE-RESPONSE-SURFACE-PASS immutable session instance natives superclass constructor negative-mutations=${rejected}')
}
