// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const target = 'android/view/autofill/AutofillManager.smali'
const signature = 'getAutofillServiceComponentName()Landroid/content/ComponentName;'
const getter = '.method public getAutofillServiceComponentName()Landroid/content/ComponentName;\n.registers 2\nconst/4 v0, 0x0\nreturn-object v0\n.end method'

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
	if old.len != 7 || changed.len != 8 || signature in old
		|| signature !in changed || norm(changed[signature]) != getter {
		return error('one exact public instance null component query required')
	}
	for name, body in old {
		if name !in changed || norm(body) != norm(changed[name]) {
			return error('retained AutofillManager method changed')
		}
	}
	if raw {
		if after != before + '\n' + getter + '\n' {
			return error('only appended query may change raw source')
		}
	} else if norm(after.replace(changed[signature], '')) != norm(before) {
		return error('AutofillManager metadata changed')
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
		println('AUTOFILL-SERVICE-ROUNDTRIP-PASS one-class retained-seven-methods null-component stable-second-DEX')
		return
	}
	path := work + '/proof/' + target
	before := os.read_file(path)!
	after := androidtools.framework_autofill_service_source(before)!
	verify(before, after, true)!
	invalids := [after,
		before.replace('.class public Landroid/view/autofill/AutofillManager;', '.class public Lwrong/AutofillManager;'),
		before + '\n.class public Landroid/view/autofill/AutofillManager;\n',
		before.replace('.super Ljava/lang/Object;', '.super Landroid/view/View;'),
		before + '\n.super Ljava/lang/Object;\n', before + '\n.end method\n',
		before + '\n.method\tpublic unrelated()V\n.end method\n',
		before + '\n.method public getAutofillServiceComponentName()Ljava/lang/Object;\n.registers 2\nconst/4 v0, 0\nreturn-object v0\n.end method\n',
		before.replace('.end method', ''), before + '\n' + (methods(before)!)['<init>()V']]
	for invalid in invalids {
		assert invalid != before
		mut rejected := false
		androidtools.framework_autofill_service_source(invalid) or { rejected = true }
		assert rejected, 'malformed or repeated query accepted'
	}
	for broken in [
		after.replace(getter, getter.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		after.replace(getter, getter.replace('.method public ', '.method public static ')),
		after.replace(getter, getter.replace('return-object', 'return')),
		after + '\n.field private fakeProvider:Landroid/content/ComponentName;\n',
		after.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'return-void'),
	] {
		mut rejected := false
		verify(before, broken, true) or { rejected = true }
		assert rejected, 'output semantic control escaped oracle'
	}
	os.write_file(path, after)!
	println('AUTOFILL-SERVICE-SOURCE-PASS refusals=10 semantic-controls=5 retained-seven-methods exact-null-query')
}
