// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const context = 'android/content/Context.smali'
const loaded = 'android/atl/ATLLoadedApp.smali'
const policy = 'android/atl/VinixBroadcastPolicy.smali'
const ctor = '<init>(Landroid/content/res/Resources;Ljava/lang/ClassLoader;Landroid/content/pm/PackageParser$Package;)V'
const overload = 'sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V'
const query = 'vinixHasBroadcastPermission(Ljava/lang/String;)Z'
const snapshot = 'snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;'
const send = 'send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V'
const field = '.field private final vinixBroadcastPermissions:Ljava/util/Set;'
const anchor = 'iput-object p3, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;'
const insert = 'invoke-static {p3}, Landroid/atl/VinixBroadcastPolicy;->snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;\nmove-result-object v0\niput-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;'
const expected_overload = '.method public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V\n.registers 3\ninvoke-static {p0, p1, p2}, Landroid/atl/VinixBroadcastPolicy;->send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V\nreturn-void\n.end method'
const expected_query = '.method public final vinixHasBroadcastPermission(Ljava/lang/String;)Z\n.registers 3\niget-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;\ninvoke-interface {v0, p1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n.end method'
const expected_send = '.method public static send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V\n.registers 4\ninvoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\nif-eqz p2, :deliver\ninvoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;\nmove-result-object v0\ninvoke-virtual {v0, p2}, Landroid/atl/ATLLoadedApp;->vinixHasBroadcastPermission(Ljava/lang/String;)Z\nmove-result v0\nif-nez v0, :deliver\nreturn-void\n:deliver\ninvoke-virtual {p0, p1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V\nreturn-void\n.end method'

fn norm(text string) string {
	return text.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(text string) !map[string]string {
	mut result := map[string]string{}
	for block in text.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn metadata(text string) !string {
	mut result := text
	for _, body in methods(text)! { result = result.replace(body, '') }
	return norm(result)
}

fn labels(text string) string {
	lines := norm(text).split_into_lines()
	mut mapping := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
			// Conditional and goto aliases can name the same instruction.
			mapping[line] = ':instruction_' + position.str()
		} else {
			position++
		}
	}
	mut result := []string{}
	for line in lines {
		if line in mapping {
			continue
		}
		last := line.fields().last()
		if (line.starts_with('if-') || line.starts_with('goto')) && last in mapping {
			result << line[..line.len - last.len] + mapping[last]
		} else {
			result << line
		}
	}
	return result.join('\n')
}

fn verify_context(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if changed.len != old.len + 1 || overload in old || overload !in changed
		|| norm(changed[overload]) != expected_overload || metadata(before)! != metadata(after)! {
		return error('exact additive Java Context overload required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) {
			return error('retained Context method changed')
		}
	}
}

fn verify_loaded(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if changed.len != old.len + 1 || query in old || query !in changed
		|| norm(changed[query]) != expected_query || metadata(after)!.count(field) != 1
		|| metadata(after)!.replace('\n' + field, '') != metadata(before)! {
		return error('one private final snapshot and public final boolean accessor required')
	}
	for name, body in old {
		expected := if name == ctor {
			norm(body).replace(anchor, anchor + '\n' + insert)
		} else {
			norm(body)
		}
		if name !in changed || norm(changed[name]) != expected {
			return error('constructor hook or retained loaded-app method differs')
		}
	}
}

fn verify_policy(source string) ! {
	parts := methods(source)!
	if parts.keys().sorted() != [snapshot, send].sorted()
		|| metadata(source)! != '.class public final Landroid/atl/VinixBroadcastPolicy;\n.super Ljava/lang/Object;'
		|| labels(parts[send]) != labels(expected_send) {
		return error('fieldless process-primary gate and ordered null-intent validation required')
	}
	body := norm(parts[snapshot])
	// Independent security predicates bind every grant precondition. ARM tests
	// exercise their behavior with real signed declarations and metadata edits.
	for required in [
		'.method public static ' + snapshot + '\n.registers 12',
		'if-eqz p0, :freeze',
		'iget-object v1, p0, Landroid/content/pm/PackageParser$Package;->vinixSigningInfo:Landroid/content/pm/SigningInfo;\nif-eqz v1, :freeze',
		'invoke-virtual {v1}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;\nmove-result-object v1\nif-eqz v1, :freeze\narray-length v2, v1\nif-lez v2, :freeze',
		'aget-object v4, v1, v3\nif-eqz v4, :freeze',
		'iget-object v3, p0, Landroid/content/pm/PackageParser$Package;->requestedPermissions:Ljava/util/ArrayList;\nif-eqz v3, :freeze',
		'invoke-virtual {v5, v8}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z\nmove-result v1\nif-nez v1, :unique\ninvoke-virtual {v0, v8}, Ljava/util/HashSet;->remove(Ljava/lang/Object;)Z\ngoto :next',
		'iget-boolean v1, v6, Landroid/content/pm/PackageParser$Permission;->tree:Z\nif-nez v1, :next',
		'iget-object v9, v7, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;\ninvoke-virtual {v2, v9}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :next',
		'iget v9, v7, Landroid/content/pm/PermissionInfo;->protectionLevel:I\nand-int/lit8 v9, v9, 0xf\nconst/4 v1, 0x2\nif-ne v9, v1, :next',
		'invoke-virtual {v3, v8}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :next\ninvoke-virtual {v0, v8}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z',
		':freeze\ninvoke-static {v0}, Ljava/util/Collections;->unmodifiableSet(Ljava/util/Set;)Ljava/util/Set;\nmove-result-object v0\nreturn-object v0\n.end method',
	] {
		if !body.contains(required) { return error('missing authority predicate: ' + required) }
	}
	if body.count('invoke-virtual {v0, v8}, Ljava/util/HashSet;->add(') != 1
		|| body.count('return-object ') != 1 || body.contains('iput') || body.contains('sput')
		|| source.contains('getPackageManager(') || source.contains('checkPermission(')
		|| source.contains('checkSelfPermission(') || source.contains('com.google.') {
		return error('unproven authority or mutable process-global grant forbidden')
	}
}

fn expect_rejected(before_context string, before_loaded string, root string) ! {
	mut rejected := false
	androidtools.framework_broadcast_permission(root) or { rejected = true }
	assert rejected && os.read_file(root + '/' + context)! == before_context
		&& os.read_file(root + '/' + loaded)! == before_loaded, 'refusal must precede writes'
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	assert labels(':first\n:alias\nnop\ngoto :first') == labels(':only\nnop\ngoto :only')
	assert labels(':first\nnop\n:second\ngoto :first') != labels(':first\nnop\n:second\ngoto :second')
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 3
			verify_context(os.read_file(work + '/baseline-roundtrip/' + context)!, os.read_file(work + '/' + directory + '/' + context)!)!
			verify_loaded(os.read_file(work + '/baseline-roundtrip/' + loaded)!, os.read_file(work + '/' + directory + '/' + loaded)!)!
			for name, body in methods(os.read_file(work + '/proof/' + policy)!)! {
				canonical := (methods(os.read_file(work + '/' + directory + '/' + policy)!)!)[name]
				assert labels(body) == labels(canonical), 'helper instructions/branch targets changed through DEX'
			}
		}
		for target in [context, loaded, policy] {
			assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!, 'unstable second DEX'
		}
		println('BROADCAST-PERMISSION-ROUNDTRIP-PASS two-to-three-classes retained-members exact-constructor-hook helper-branch-identity stable-second-DEX')
		return
	}
	root := work + '/proof'
	before_context, before_loaded := os.read_file(root + '/' + context)!, os.read_file(root + '/' + loaded)!
	changed_context := androidtools.framework_broadcast_permission_context_source(before_context)!
	changed_loaded := androidtools.framework_broadcast_permission_loaded_source(before_loaded)!
	classes := androidtools.framework_broadcast_permission_classes()
	assert classes.keys() == [policy.all_before_last('.smali')]
	helper := classes.values()[0]
	verify_context(before_context, changed_context)!
	verify_loaded(before_loaded, changed_loaded)!
	verify_policy(helper)!
	for invalid in [changed_context,
		before_context.replace('.class public abstract Landroid/content/Context;', '.class public Landroid/content/Context;'),
		before_context + '\n.class public abstract Landroid/content/Context;\n',
		before_context.replace('.method public native sendBroadcast(Landroid/content/Intent;)V', '.method public sendBroadcast(Landroid/content/Intent;)V'),
		before_context + '\n.end method\n'] {
		assert invalid != before_context
		os.write_file(root + '/' + context, invalid)!
		expect_rejected(invalid, before_loaded, root)!
	}
	os.write_file(root + '/' + context, before_context)!
	for invalid in [changed_loaded,
		before_loaded.replace('.class public final Landroid/atl/ATLLoadedApp;', '.class public Landroid/atl/ATLLoadedApp;'),
		before_loaded + '\n.super Ljava/lang/Object;\n',
		before_loaded.replace('    .registers 6\n', '    .registers 7\n'),
		before_loaded.replace('    ' + anchor, '    # missing pkg anchor'),
		before_loaded.replace('    if-nez v2, :cond_5a', '    if-eqz v2, :cond_5a')] {
		assert invalid != before_loaded
		os.write_file(root + '/' + loaded, invalid)!
		expect_rejected(before_context, invalid, root)!
	}
	os.write_file(root + '/' + loaded, before_loaded)!
	for broken in [helper.replace('if-eqz v1, :freeze', 'if-nez v1, :freeze'),
		helper.replace('const/4 v1, 0x2', 'const/4 v1, 0x0'),
		helper.replace('if-nez v1, :next', 'if-eqz v1, :next'),
		helper.replace('->unmodifiableSet(', '->singleton('),
		helper.replace('->remove(Ljava/lang/Object;)Z', '->contains(Ljava/lang/Object;)Z'),
		helper.replace('invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;', 'nop'),
		helper.replace('->getPrimaryApplication()', '->getSystemApplication()'),
		helper.replace('if-nez v0, :deliver', 'if-eqz v0, :deliver')] {
		mut rejected := false
		verify_policy(broken) or { rejected = true }
		assert rejected, 'broken authority predicate escaped independent oracle'
	}
	for broken in [
		changed_loaded.replace(field, field.replace('private final', 'public')),
		changed_loaded.replace('invoke-static {p3}, Landroid/atl/VinixBroadcastPolicy;->snapshot(', 'invoke-static {p0}, Landroid/atl/VinixBroadcastPolicy;->snapshot('),
	] {
		mut rejected := false
		verify_loaded(before_loaded, broken) or { rejected = true }
		assert rejected
	}
	mut rejected_context := false
	verify_context(before_context, changed_context.replace('{p0, p1, p2}', '{p0, p2, p1}')) or { rejected_context = true }
	assert rejected_context
	os.mkdir_all(os.dir(root + '/' + policy))!
	os.write_file(root + '/' + policy, 'collision')!
	expect_rejected(before_context, before_loaded, root)!
	assert os.read_file(root + '/' + policy)! == 'collision'
	os.rm(root + '/' + policy)!
	os.mkdir(root + '/' + policy)!
	expect_rejected(before_context, before_loaded, root)!
	os.rmdir(root + '/' + policy)!
	os.symlink('absent-broadcast-policy', root + '/' + policy)!
	expect_rejected(before_context, before_loaded, root)!
	assert os.readlink(root + '/' + policy)! == 'absent-broadcast-policy'
	os.rm(root + '/' + policy)!
	androidtools.framework_broadcast_permission(root)!
	assert os.read_file(root + '/' + context)! == changed_context && os.read_file(root + '/' + loaded)! == changed_loaded
	assert os.read_file(root + '/' + policy)! == helper && os.walk_ext(root, '.smali').len == 3
	println('BROADCAST-PERMISSION-SOURCE-PASS refusals=14 semantic-controls=11 retained-members immutable-instance-snapshot primary-only-gate validation-before-writes')
}
