// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/app/admin/DevicePolicyManager.smali'
const signature = 'getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I'
const getter = '.method public getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method'

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

fn verify(before string, after string, raw bool) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != 10 || changed.len != 11 || signature in old
		|| signature !in changed || norm(changed[signature]) != getter {
		return error('one exact public instance zero feature-mask query required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) {
			return error('retained DevicePolicyManager method changed')
		}
	}
	if raw {
		if after != before + '\n' + getter + '\n' {
			return error('only appended query may change raw source')
		}
	} else if norm(after.replace(changed[signature], '')) != norm(before) {
		return error('DevicePolicyManager metadata changed')
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
			verify(before, os.read_file(work + '/' + directory + '/' + target)!, false)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('KEYGUARD-POLICY-ROUNDTRIP-PASS one-class retained-ten-methods zero-mask stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_keyguard_policy_source(before)!
	verify(before, after, true)!
	invalids := [after,
		before.replace('.class public Landroid/app/admin/DevicePolicyManager;', '.class public Lwrong/DevicePolicyManager;'),
		before + '\n.class public Landroid/app/admin/DevicePolicyManager;\n',
		before.replace('.super Ljava/lang/Object;', '.super Landroid/view/View;'),
		before + '\n.super Ljava/lang/Object;\n', before + '\n.end method\n',
		before + '\n.method\tpublic unrelated()V\n.end method\n',
		before + '\n.field private policy:I\n', before + '\n.implements Ljava/lang/Runnable;\n',
		before.replace('.end method', ''), before + '\n' + (methods(before)!)['<init>()V'],
		before.replace('.method public getDeviceOwner()', '.method private getDeviceOwner()')]
	for invalid in invalids {
		assert invalid != before
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_keyguard_policy(work + '/proof') or { rejected = true }
		assert rejected && os.read_file(path)! == invalid, 'refusal must precede writes'
	}
	for broken in [
		after.replace(getter, getter.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		after.replace(getter, getter.replace('.method public ', '.method public static ')),
		after.replace(getter, getter.replace('return v0', 'return-object v0')),
		after + '\n.field private fakePolicy:I\n',
		after.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'return-void'),
	] {
		mut rejected := false
		verify(before, broken, true) or { rejected = true }
		assert rejected, 'output semantic control escaped oracle'
	}
	os.write_file(path, before)!
	androidtools.framework_keyguard_policy(work + '/proof')!
	assert os.read_file(path)! == after
	println('KEYGUARD-POLICY-SOURCE-PASS refusals=' + invalids.len.str() + ' semantic-controls=5 retained-ten-methods exact-zero-mask')
}
