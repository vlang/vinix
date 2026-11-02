// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/app/usage/UsageStatsManager.smali'
const signature = 'isAppInactive(Ljava/lang/String;)Z'
const expected = '.method public isAppInactive(Ljava/lang/String;)Z\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method'

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

fn verify(before string, after string) ! {
	old, changed := methods(before)!, methods(after)!
	if old.keys() != ['<init>()V'] || changed.len != 2 || signature !in changed
		|| norm(changed[signature]) != expected || changed['<init>()V'] != old['<init>()V']
		|| norm(after.replace(changed[signature], '')) != norm(before) {
		return error('one exact public instance disabled-policy query with retained constructor/metadata required')
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
			verify(before, os.read_file(work + '/' + directory + '/' + target)!)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('USAGE-INACTIVE-ROUNDTRIP-PASS one-class retained-constructor disabled-policy-query stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_usage_inactive_source(before)!
	verify(before, after)!
	assert after == before + '\n' + expected + '\n'
	invalids := [after,
		before.replace('.class public Landroid/app/usage/UsageStatsManager;', '.class public final Landroid/app/usage/UsageStatsManager;'),
		before + '\n.class public Landroid/app/usage/UsageStatsManager;\n',
		before.replace('.super Ljava/lang/Object;', '.super Landroid/view/View;'),
		before + '\n.super Ljava/lang/Object;\n',
		before + '\n.field private fakeHistory:Ljava/util/Map;\n',
		before + '\n.implements Ljava/lang/Runnable;\n', before + '\n.end method\n',
		before + '\n.method\tpublic unrelated()V\n.end method\n', before.replace('.end method', ''),
		before + '\n' + (methods(before)!)['<init>()V'],
		before.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'return-void')]
	for invalid in invalids {
		assert invalid != before
		os.write_file(path, invalid)!
		mut rejected := false
		androidtools.framework_usage_inactive(work + '/proof') or { rejected = true }
		assert rejected && os.read_file(path)! == invalid, 'refusal must precede writes'
	}
	for broken in [
		after.replace(expected, expected.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		after.replace(expected, expected.replace('.method public ', '.method public static ')),
		after.replace(expected, expected.replace('return v0', 'return-object v0')),
		after + '\n.field private fakeHistory:Ljava/util/Map;\n',
		after.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'return-void'),
	] {
		mut rejected := false
		verify(before, broken) or { rejected = true }
		assert rejected, 'changed policy result, API shape or state escaped oracle'
	}
	os.write_file(path, before)!
	androidtools.framework_usage_inactive(work + '/proof')!
	assert os.read_file(path)! == after
	println('USAGE-INACTIVE-SOURCE-PASS refusals=' + invalids.len.str() + ' semantic-controls=5 retained-constructor public-instance-query disabled-AppStandby')
}
