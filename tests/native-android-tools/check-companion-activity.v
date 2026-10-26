// SPDX-License-Identifier: GPL-2.0-or-later
// Validate the isolated three-class patch against a disassembled framework.
// The signed companion-activity fixture exercises semantics on ART.
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		declaration := block.all_before('\n')
		name := declaration.all_after_last(' ')
		assert name !in result, name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn rejected(activity string, manager string, task string, label string) {
	if _, _, _ := androidtools.framework_companion_activity_sources(activity, manager, task) {
		panic('accepted malformed routing input: ' + label)
	}
}

fn replace_once(source string, needle string, replacement string) string {
	assert source.count(needle) == 1, needle
	return source.replace(needle, replacement)
}

fn position(source string, needle string) int {
	return source.index(needle) or { panic('missing instruction: ' + needle) }
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'usage: check-companion-activity BASE_SMALI [TOOLS JAVA]'
	names := androidtools.framework_companion_activity_class_names()
	assert names == ['android/app/Activity', 'android/atl/ATLLoadedAppManager', 'android/app/Activity$2']
	mut old := []string{}
	for name in names { old << os.read_file(os.args[1] + '/' + name + '.smali')! }
	activity, manager, task := androidtools.framework_companion_activity_sources(old[0], old[1], old[2])!
	changed := [activity, manager, task]
	allowed := [
		['startActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V',
			'setResult(ILandroid/content/Intent;)V', 'finish()V',
			'getCallingPackage()Ljava/lang/String;'],
		[]string{},
		['run()V'],
	]
	for i, source in old {
		before := methods(source)
		after := methods(changed[i])
		for name, body in before {
			assert name in after, name
			if name in allowed[i] {
				assert body != after[name], name
			} else {
				assert body == after[name], name
			}
		}
	}
	assert activity.contains('invoke-direct {v3, p1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V')
	assert activity.contains('invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;')
	assert 'vinixRecreateActivity(Landroid/app/Activity;J)Landroid/app/Activity;' in methods(activity)
	create := methods(activity)['vinixCreateActivity(Landroid/app/Activity;Landroid/content/Intent;J)Landroid/app/Activity;']
	startup := position(create, '->vinixEnsureApplicationStarted()V')
	for guard in ['->enabled:Z', '->exported:Z', '->permission:Ljava/lang/String;'] {
		assert position(create, guard) < startup, guard
	}
	result := methods(activity)['setResult(ILandroid/content/Intent;)V']
	assert !result.contains('->onActivityResult(')
	assert result.contains('->vinixResultCode:I') && result.contains('->vinixResultData:Landroid/content/Intent;')
	finish := methods(activity)['finish()V']
	assert finish.contains('->finishing:Z') && finish.contains('->getMainLooper()Landroid/os/Looper;')
	assert finish.contains('->post(Ljava/lang/Runnable;)Z') && !finish.contains('->onActivityResult(')
	delivery := methods(activity)['vinixDispatchActivityResult()V']
	assert delivery.count('->onActivityResult(') == 1
	assert position(delivery, '->vinixResultDelivered:Z') < position(delivery, '->onActivityResult(')
	assert position(task, '->vinixDispatchActivityResult()V') < position(task, '->access$000(')
	lookup := methods(manager)['vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']
	assert position(lookup, '->vinixActivityPackageVisible(') < position(lookup, '->peekAppFromPackageName(')
	assert !methods(activity)['startActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V'].contains('Landroid/util/Slog;')
	assert !create.contains('Landroid/util/Slog;')

	// Fail closed on absent/duplicate/malformed methods and fields, incorrect
	// class identities, existing helper overloads and changed extraction anchors.
	rejected(replace_once(old[0], '.class public Landroid/app/Activity;', '.class public Landroid/app/Other;'), old[1], old[2], 'wrong Activity class')
	rejected(old[0], replace_once(old[1], '.super Ljava/lang/Object;', '.super Landroid/app/Activity;'), old[2], 'wrong manager superclass')
	rejected(old[0], old[1], old[2] + '\n.class Landroid/app/Extra;\n', 'duplicate class')
	for signature in allowed[0] {
		rejected(old[0].replace(' ' + signature + '\n', ' missing' + signature + '\n'), old[1], old[2], 'missing ' + signature)
		rejected(old[0] + '\n' + methods(old[0])[signature], old[1], old[2], 'duplicate ' + signature)
	}
	rejected(old[0] + '\n.method public unfinished()V\n', old[1], old[2], 'unterminated method')
	rejected(old[0] + '\n.field public resultRequestCode:I\n', old[1], old[2], 'duplicate result field')
	rejected(old[0], old[1] + '\n.field public always_visible_packages:Ljava/util/HashSet;\n', old[2], 'duplicate policy field')
	rejected(old[0], old[1], old[2] + '\n.field public this$0:Landroid/app/Activity;\n', 'duplicate finish owner field')
	rejected(replace_once(old[0], '.field private finishing:Z', ''), old[1], old[2], 'missing finishing field')
	rejected(old[0] + '\n.method public vinixRecreateActivity()V\n.locals 0\nreturn-void\n.end method\n', old[1], old[2], 'helper overload')
	rejected(old[0] + '\n.field public vinixResultOther:I\n', old[1], old[2], 'reserved result field')
	rejected(replace_once(old[0], '    :cond_62\n', '    :changed_62\n'), old[1], old[2], 'implicit fallback changed')
	rejected(old[0].replace(':goto_57', ':changed_goto'), old[1], old[2], 'implicit fallback return changed')
	rejected(old[0], old[1].replace('    :cond_10\n', '    :changed_10\n'), old[2], 'loader anchor changed')
	rejected(old[0], old[1] + '\n' + methods(old[1])['loadApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;'], old[2], 'duplicate loader')
	rejected(old[0], old[1], replace_once(old[2], '    const-wide/16 v4, 0x0', '    const-wide/16 v4, 0x1'), 'finish anchor changed')
	rejected(old[0], old[1], old[2] + '\n' + methods(old[2])['run()V'], 'duplicate finish runnable')
	rejected(activity, manager, task, 'patch reapplied')
	println('ANDROID-COMPANION-ACTIVITY-TRANSFORM-PASS exact class scope, preserved methods, visibility-before-cache, guarded startup, cached results, actual-class recreation and malformed-input rejection')
	if os.args.len == 4 {
		work := os.join_path(os.temp_dir(), 'vinix-companion-activity-' + os.getpid().str())
		os.mkdir_all(work + '/smali/android/app')!
		os.mkdir_all(work + '/smali/android/atl')!
		defer { os.rmdir_all(work) or {} }
		for i, name in names { os.write_file(work + '/smali/' + name + '.smali', changed[i])! }
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-COMPANION-ACTIVITY-ASSEMBLY-PASS all three changed classes produce DEX')
	}
}
