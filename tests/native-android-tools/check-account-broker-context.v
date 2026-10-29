// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os

fn original(name string, signature string, static_method bool) string {
	return '.class public L${name};\n.super Ljava/lang/Object;\n.method public ' +
		(if static_method { 'static ' } else { '' }) + signature + '\n.locals 1\nconst/4 v0, -1\nreturn v0\n.end method\n'
}
fn validate(source string, wrappers int) ! {
	for expected in ['const/4 v1, -2\nif-eq v0, v1, :fallback\nreturn v0',
		'.catch Ljava/lang/UnsatisfiedLinkError; {:query_start .. :query_end} :unavailable',
		':unavailable\nmove-exception v0\n:fallback\n'] {
		if source.count(expected) != wrappers { return error('missing scoped fallback') }
	}
	if source.count('const/4 v0, -1\nreturn v0') != 2 {
		return error('original permission behavior was lost')
	}
	if source.contains('const/4 v0, 0\nreturn v0') { return error('unconditional permission grant') }
}

fn method(source string, signature string) !string {
	mut found := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if found != '' { return error('duplicate method ' + signature) }
		end := block.index('.end method') or { return error('unterminated method') }
		found = '.method ' + block[..end + '.end method'.len]
	}
	if found == '' { return error('missing method ' + signature) }
	return found
}

fn identity_original(signature string, body string) string {
	return '.method public static ' + signature + '\n' + body + '\n.end method\n'
}

fn validate_identity(source string, clear_body string, restore_body string) ! {
	clear := method(source, 'clearCallingIdentity()J')!
	restore := method(source, 'restoreCallingIdentity(J)V')!
	for body in [clear, restore] {
		if body.count('.catch') != 1
			|| body.count('.catch Ljava/lang/UnsatisfiedLinkError; {:query_start .. :query_end} :unavailable') != 1
			|| body.count(':unavailable\nmove-exception v0\n:fallback\n') != 1 {
			return error('identity native fallback must catch only ULE at the query')
		}
	}
	for required in ['.locals 4\n:query_start\n',
		'invoke-static {}, Landroid/atl/VinixAccountBrokerContext;->clearCallingIdentity()J\nmove-result-wide v0\n:query_end\n',
		'const-wide/16 v2, 0\ncmp-long v2, v0, v2\nif-eqz v2, :fallback\nreturn-wide v0\n',
		':fallback\ninvoke-static {}, Landroid/os/Binder;->vinixOriginalClearCallingIdentity()J\nmove-result-wide v0\nreturn-wide v0'] {
		if !clear.contains(required) { return error('clear identity wide-token or zero-sentinel contract differs') }
	}
	for required in ['.locals 1\n:query_start\n',
		'invoke-static {p0, p1}, Landroid/atl/VinixAccountBrokerContext;->restoreCallingIdentity(J)Z\nmove-result v0\n:query_end\nif-eqz v0, :fallback\nreturn-void\n',
		':fallback\ninvoke-static {p0, p1}, Landroid/os/Binder;->vinixOriginalRestoreCallingIdentity(J)V\nreturn-void'] {
		if !restore.contains(required) { return error('restore identity handled/fallback or wide-argument contract differs') }
	}
	if method(source, 'vinixOriginalClearCallingIdentity()J')! != '.method private static vinixOriginalClearCallingIdentity()J\n' + clear_body + '\n.end method'
		|| method(source, 'vinixOriginalRestoreCallingIdentity(J)V')! != '.method private static vinixOriginalRestoreCallingIdentity(J)V\n' + restore_body + '\n.end method' {
		return error('original identity implementation body changed')
	}
}

fn nested_identity_probe() string {
	return '.class public final Lorg/vinix/IdentityProbe;\n.super Ljava/lang/Object;\n' +
		'.method public static nested()V\n.locals 4\n' +
		'invoke-static {}, Landroid/os/Binder;->clearCallingIdentity()J\nmove-result-wide v0\n' +
		'invoke-static {}, Landroid/os/Binder;->clearCallingIdentity()J\nmove-result-wide v2\n' +
		'invoke-static {v2, v3}, Landroid/os/Binder;->restoreCallingIdentity(J)V\n' +
		'invoke-static {v0, v1}, Landroid/os/Binder;->restoreCallingIdentity(J)V\nreturn-void\n.end method\n'
}

fn main() {
	assert os.args.len in [1,3,4], 'usage: check-account-broker-context [TOOLS JAVA [FRESH_OUTPUT]]'
	clear_body := '.locals 2\nconst-wide/16 v0, 0x1234\nreturn-wide v0'
	restore_body := '.locals 1\ninvoke-static {p0, p1}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;\nmove-result-object v0\nreturn-void'
	binder := original('android/os/Binder','getCallingUid()I',true) +
		original('unused','getCallingPid()I',true).all_after('.super Ljava/lang/Object;\n') +
		identity_original('clearCallingIdentity()J', clear_body) + identity_original('restoreCallingIdentity(J)V', restore_body)
	context := original('android/content/Context','checkCallingOrSelfPermission(Ljava/lang/String;)I',false) +
		original('unused','checkPermission(Ljava/lang/String;II)I',false).all_after('.super Ljava/lang/Object;\n')
	mut classes := androidtools.framework_account_broker_sources(binder,context)!
	validate(classes['android/os/Binder'],2)!
	validate(classes['android/content/Context'],3)!
	assert classes['android/os/Binder'].contains('invoke-static {}, Landroid/os/Binder;->vinixOriginalCallingUid()I')
	assert classes['android/content/Context'].contains('invoke-direct {p0, p1, p2, p3}, Landroid/content/Context;->vinixOriginalPermission(Ljava/lang/String;II)I')
	mut rejected := 0
	for invalid in [binder.replace('getCallingUid()I','missing()I'), binder + binder.all_after('.super Ljava/lang/Object;\n'), classes['android/os/Binder']] {
		androidtools.framework_account_broker_sources(invalid,context) or { rejected++; continue }
		panic('invalid or repeated wrapper accepted')
	}
	for invalid in [classes['android/content/Context'].replace('if-eq v0, v1, :fallback','if-ne v0, v1, :fallback'),
		classes['android/content/Context'].replace('const/4 v0, -1','const/4 v0, 0')] {
		validate(invalid,3) or { rejected++; continue }
		panic('unsafe fallback mutation accepted')
	}
	assert rejected == 5
	legacy_binder := classes['android/os/Binder']
	identity_binder := androidtools.framework_account_broker_identity(legacy_binder)!
	validate_identity(identity_binder, clear_body, restore_body)!
	for signature in ['getCallingUid()I', 'getCallingPid()I', 'vinixOriginalCallingUid()I', 'vinixOriginalCallingPid()I'] {
		assert method(legacy_binder, signature)! == method(identity_binder, signature)!, 'unrelated Binder body changed'
	}
	mut identity_rejected := 0
	for invalid in [legacy_binder.replace('clearCallingIdentity()J', 'missingIdentity()J'),
		legacy_binder.replace('restoreCallingIdentity(J)V', 'missingRestore(J)V'),
		legacy_binder.replace('Landroid/os/Binder;', 'Lwrong/Binder;'),
		legacy_binder + identity_original('clearCallingIdentity()J', clear_body),
		legacy_binder.replace('.method public static clearCallingIdentity()J\n' + clear_body, '.method public static native clearCallingIdentity()J'),
		identity_binder] {
		androidtools.framework_account_broker_identity(invalid) or { identity_rejected++; continue }
		panic('invalid or repeated identity wrapper accepted')
	}
	for invalid in [identity_binder.replace('if-eqz v2, :fallback', 'if-nez v2, :fallback'),
		identity_binder.replace('.catch Ljava/lang/UnsatisfiedLinkError;', '.catch Ljava/lang/Throwable; {:query_start .. :query_end} :unavailable\n.catch Ljava/lang/UnsatisfiedLinkError;'),
		identity_binder.replace('->clearCallingIdentity()J\nmove-result-wide v0', '->clearCallingIdentity()J\nmove-result v0'),
		identity_binder.replace('->restoreCallingIdentity(J)Z\nmove-result v0', '->restoreCallingIdentity(J)V\nmove-result v0'),
		identity_binder.replace('invoke-static {p0, p1}, Landroid/atl/VinixAccountBrokerContext;->restoreCallingIdentity', 'invoke-static {p0}, Landroid/atl/VinixAccountBrokerContext;->restoreCallingIdentity'),
		identity_binder.replace('->vinixOriginalRestoreCallingIdentity(J)V', '->vinixOriginalRestoreCallingIdentity(I)V'),
		identity_binder.replace('const-wide/16 v0, 0x1234', 'const-wide/16 v0, 0x0')] {
		validate_identity(invalid, clear_body, restore_body) or { identity_rejected++; continue }
		panic('unsafe identity fallback mutation accepted')
	}
	assert identity_rejected == 13
	native_classes := androidtools.framework_account_broker_context_classes()
	old_natives := native_classes['android/atl/VinixAccountBrokerContext']
	assert old_natives.count('.method public static native ') == 4, 'historical native factory changed'
	natives := androidtools.framework_account_broker_identity_context(old_natives)!
	assert natives.count('.method public static native ') == 6
	for signature in ['clearCallingIdentity()J', 'restoreCallingIdentity(J)Z'] {
		assert natives.count('.method public static native ' + signature + '\n.end method') == 1
	}
	added_natives := androidtools.framework_account_broker_identity_context(old_natives)!
	assert added_natives.starts_with(old_natives) && added_natives == natives, 'broker context changed outside two appended declarations'
	for signature in ['callingUid()I','callingPid()I','callingPermission(Ljava/lang/String;)I','checkPermission(Ljava/lang/String;II)I'] {
		assert method(added_natives, signature)! == method(old_natives, signature)!, 'original broker context native changed'
	}
	mut native_rejected := 0
	for invalid in [natives, old_natives.replace('Landroid/atl/VinixAccountBrokerContext;', 'Lwrong/Context;'),
		old_natives.replace('callingUid()I', 'missingUid()I'),
		old_natives.replace('callingPid()I', 'callingUid()I')] {
		androidtools.framework_account_broker_identity_context(invalid) or { native_rejected++; continue }
		panic('invalid or repeated identity natives accepted')
	}
	assert native_rejected == 4
	classes['android/os/Binder'] = identity_binder
	classes['org/vinix/IdentityProbe'] = nested_identity_probe()
	work := if os.args.len == 4 { os.abs_path(os.args[3]) } else { os.temp_dir() + '/vinix-account-scope-' + os.getpid().str() }
	assert !os.exists(work) && !os.is_link(work), 'output must be fresh'
	defer { if os.args.len != 4 { os.rmdir_all(work) or {} } }
	os.mkdir_all(work + '/integration/android/content')!; os.mkdir_all(work + '/integration/android/os')!
	os.write_file(work + '/integration/android/os/Binder.smali', binder)!
	os.write_file(work + '/integration/android/content/Context.smali', context)!
	androidtools.framework_account_broker_context(work + '/integration')!
	integrated_binder := os.read_file(work + '/integration/android/os/Binder.smali')!
	assert integrated_binder == identity_binder, 'filesystem entrypoint omitted or changed Binder wrappers'
	validate_identity(integrated_binder, clear_body, restore_body)!
	assert os.read_file(work + '/integration/android/content/Context.smali')! == classes['android/content/Context']
	assert os.read_file(work + '/integration/android/atl/VinixAccountBrokerContext.smali')! == natives,
		'filesystem entrypoint omitted identity natives'
	println('ANDROID-ACCOUNT-SCOPE-INTEGRATION-PASS historical-factory4 generic-entrypoint6 identity-wrappers')
	if os.args.len >= 3 {
		os.mkdir_all(work + '/smali/android/atl')!; os.mkdir_all(work + '/smali/android/content')!; os.mkdir_all(work + '/smali/android/os')!
		os.mkdir_all(work + '/smali/org/vinix')!
		for name, source in classes { os.write_file(work + '/smali/' + name + '.smali',source)! }
		os.write_file(work + '/smali/android/atl/VinixAccountBrokerContext.smali', natives)!
		androidtools.framework_assemble(work + '/smali',work + '/classes.dex',os.real_path(os.args[1]),os.args[2])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-ACCOUNT-SCOPE-ASSEMBLY-PASS integer identity-wide nested-clear-restore-ABI')
	}
	println('ANDROID-ACCOUNT-SCOPE-PASS original bodies -2 sentinel native fallback mutations=5 identity-zero-sentinel nested-wide-ABI identity-mutations=13 context-mutations=4')
}
