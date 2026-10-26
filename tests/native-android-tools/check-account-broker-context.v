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
fn main() {
	assert os.args.len in [1,3], 'usage: check-account-broker-context [TOOLS JAVA]'
	binder := original('android/os/Binder','getCallingUid()I',true) +
		original('unused','getCallingPid()I',true).all_after('.super Ljava/lang/Object;\n')
	context := original('android/content/Context','checkCallingOrSelfPermission(Ljava/lang/String;)I',false) +
		original('unused','checkPermission(Ljava/lang/String;II)I',false).all_after('.super Ljava/lang/Object;\n')
	classes := androidtools.framework_account_broker_sources(binder,context)!
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
	if os.args.len == 3 {
		work := os.temp_dir() + '/vinix-account-scope-' + os.getpid().str()
		os.mkdir_all(work + '/smali/android/atl')!; os.mkdir_all(work + '/smali/android/content')!; os.mkdir_all(work + '/smali/android/os')!
		defer { os.rmdir_all(work) or {} }
		for name, source in classes { os.write_file(work + '/smali/' + name + '.smali',source)! }
		for name, source in androidtools.framework_account_broker_context_classes() { os.write_file(work + '/smali/' + name + '.smali',source)! }
		androidtools.framework_assemble(work + '/smali',work + '/classes.dex',os.real_path(os.args[1]),os.args[2])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-ACCOUNT-SCOPE-ASSEMBLY-PASS')
	}
	println('ANDROID-ACCOUNT-SCOPE-PASS original bodies -2 sentinel native fallback mutations=5')
}
