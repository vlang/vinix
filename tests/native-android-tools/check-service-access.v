// SPDX-License-Identifier: GPL-2.0-or-later
// Host validation of explicit Context service routing. The signed multi-APK
// service-access fixture is the separate ART behavioral probe.
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		assert name !in result, name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn rejected(source string, label string) {
	if _ := androidtools.framework_service_access_sources(source) {
		panic('accepted malformed service routing: ' + label)
	}
}

fn position(source string, needle string) int {
	return source.index(needle) or { panic('missing instruction: ' + needle) }
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'usage: check-service-access BASE_SMALI [TOOLS JAVA]'
	assert androidtools.framework_service_access_class_names() == ['android/app/ContextImpl']
	source := os.read_file(os.args[1] + '/android/app/ContextImpl.smali')!
	patched := androidtools.framework_service_access_sources(source)!
	before := methods(source)
	after := methods(patched)
	bind_signature := 'bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z'
	start_signature := 'startService(Landroid/content/Intent;)Landroid/content/ComponentName;'
	helper_signature := 'vinixGetServiceTarget(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;'
	for name, body in before {
		assert name in after, name
		if name in [bind_signature, start_signature] {
			assert after[name] != body, name
		} else {
			assert after[name] == body, name
		}
	}
	assert after.len == before.len + 1 && helper_signature in after
	helper := after[helper_signature]
	assert position(helper, '->vinixGetActivityApplication(') < position(helper, '->services:')
	for declaration in ['Landroid/content/pm/ApplicationInfo;->enabled:Z',
		'Landroid/content/pm/ComponentInfo;->enabled:Z',
		'Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;',
		'Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;',
		'Landroid/content/pm/ComponentInfo;->exported:Z',
		'Landroid/content/pm/ServiceInfo;->permission:Ljava/lang/String;'] {
		assert position(helper, declaration) < position(helper, '\n:allowed\n'), declaration
	}
	assert !helper.contains('->requestedPermissions:')
	assert !helper.contains('->startOrBindService(') && !helper.contains('->vinixEnsureApplicationStarted(')
	assert !helper.contains('->setComponent(') && !helper.contains('->getClassLoader(')
	assert helper.contains('if-nez v7, :allowed\niget-boolean v7, v6, Landroid/content/pm/ComponentInfo;->exported:Z')
	assert helper.contains('new-instance v0, Ljava/lang/SecurityException;')
	bind := after[bind_signature]
	assert position(bind, '->vinixGetServiceTarget(') < position(bind, '->register(')
	assert position(bind, 'if-eqz v0, :missing') < position(bind, '->register(')
	assert position(bind, 'if-nez p2, :lookup') < position(bind, '->vinixGetServiceTarget(')
	start := after[start_signature]
	legacy := position(start, '    :vinix_explicit_service_legacy\n')
	assert position(start, '->vinixGetServiceTarget(') < legacy
	assert position(start, '    :vinix_explicit_service_missing\n') < legacy
	assert position(start, '->nativeStartExternalService(') > legacy
	assert position(start, '->registerReceiver(') > legacy
	// All original implicit behavior survives byte-for-byte after the guard.
	assert start[legacy + '    :vinix_explicit_service_legacy\n'.len..] == before[start_signature].all_after('    .registers 6\n')
	// The shared package resolver itself gates cached apps by the actual owner.
	_, manager, _ := androidtools.framework_companion_activity_sources(
		os.read_file(os.args[1] + '/android/app/Activity.smali')!,
		os.read_file(os.args[1] + '/android/atl/ATLLoadedAppManager.smali')!,
		os.read_file(os.args[1] + '/android/app/Activity$2.smali')!)!
	lookup := methods(manager)['vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']
	assert position(lookup, '->vinixActivityPackageVisible(') < position(lookup, '->peekAppFromPackageName(')

	rejected(source.replace('.class public final Landroid/app/ContextImpl;', '.class public Landroid/app/Other;'), 'wrong class')
	rejected(source.replace('.super Landroid/content/Context;', '.super Ljava/lang/Object;'), 'wrong superclass')
	rejected(source + '\n.class public Landroid/app/Extra;\n', 'duplicate class')
	rejected(source + '\n.field public atl_loaded_app:Landroid/atl/ATLLoadedApp;\n', 'duplicate owner')
	rejected(source.replace('.field private final atl_loaded_app:Landroid/atl/ATLLoadedApp;', ''), 'missing owner')
	for name in [bind_signature, start_signature,
		'atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;'] {
		rejected(source.replace(' ' + name + '\n', ' missing' + name + '\n'), 'missing ' + name)
		rejected(source + '\n' + before[name], 'duplicate ' + name)
	}
	rejected(source + '\n.method public unfinished()V\n', 'unbalanced method')
	rejected(source + '\n.method public vinixGetServiceTarget()V\n.locals 0\nreturn-void\n.end method\n', 'helper overload')
	rejected(source.replace('Landroid/atl/VinixServiceBinding;->register(', 'Landroid/atl/VinixServiceBinding;->missing('), 'binding registration drift')
	rejected(source.replace('->nativeStartExternalService(', '->missingExternalService('), 'external fallback drift')
	rejected(source.replace(before[start_signature], before[start_signature].replace('    .registers 6\n', '    .registers 7\n')), 'start registers drift')
	rejected(patched, 'reapplied patch')
	println('ANDROID-SERVICE-ACCESS-TRANSFORM-PASS explicit manifest/access checks, owner visibility before cache, no protected permission bypass, preserved implicit paths and malformed-input rejection')
	if os.args.len == 4 {
		work := os.join_path(os.temp_dir(), 'vinix-service-access-' + os.getpid().str())
		os.mkdir_all(work + '/smali/android/app')!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/smali/android/app/ContextImpl.smali', patched)!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-SERVICE-ACCESS-ASSEMBLY-PASS sole changed ContextImpl class produces DEX')
	}
}
