// SPDX-License-Identifier: GPL-2.0-or-later
// ABI/source checks; physical framebuffer behavior belongs to the native tests.
module main

import androidtools
import os

const entry = '\n.method public native getStableDisplaySize()Landroid/graphics/Point;\n.end method\n'
const target = '/android/hardware/display/DisplayManager.smali'

fn verify(before string, after string) ! {
	if after != before + entry { return error('only one public native API may be appended') }
}

fn refused(work string, number int, invalid string) ! {
	root := work + '/refused-' + number.str()
	os.mkdir_all(os.dir(root + target))!
	os.write_file(root + target, invalid)!
	mut rejected := false
	androidtools.framework_stable_display(root) or { rejected = true }
	assert rejected, 'malformed or repeated application accepted'
	assert os.read_file(root + target)! == invalid, 'refusal wrote input'
	assert os.walk_ext(root, '.smali') == [root + target], 'refusal added files'
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip' + target)!
		after := os.read_file(work + '/patched-roundtrip' + target)!
		added := '.method public native getStableDisplaySize()Landroid/graphics/Point;\n.end method\n'
		assert after.count(added) == 1
		assert before.split_into_lines().filter(it.trim_space() != '') == after.replace(added, '').split_into_lines().filter(it.trim_space() != ''), 'canonical DisplayManager retained members changed'
		for kind in ['android/view/Display', 'android/graphics/Point'] {
			assert os.read_file(work + '/baseline-roundtrip/' + kind + '.smali')! == os.read_file(work + '/patched-roundtrip/' + kind + '.smali')!, 'display dependency changed'
		}
		for path in os.walk_ext(work + '/patched-roundtrip', '.smali') {
			assert os.read_file(path)! == os.read_file(work + '/second-roundtrip/' + path.all_after(work + '/patched-roundtrip/'))!, 'second DEX roundtrip unstable'
		}
		println('STABLE-DISPLAY-ROUNDTRIP-PASS one-native-API retained-five-methods dependencies-unchanged stable-second-DEX')
		return
	}
	old := os.read_file(work + '/baseline' + target)!
	patched := androidtools.framework_stable_display_source(old)!
	verify(old, patched)!
	mut invalid := [old.replace('.class public final ', '.class public '),
		old.replace('Landroid/hardware/display/DisplayManager;', 'Lwrong/DisplayManager;'),
		old + '\n.class public final Landroid/hardware/display/DisplayManager;\n',
		old.replace('.super Ljava/lang/Object;', '.super Lwrong/Parent;'),
		old + '\n.super Ljava/lang/Object;\n', old + '\n.field private unexpected:I\n',
		old + '\n\t.field private unexpected:I\n', old + '\n.end method\n', patched]
	for block in old.split('.method ')[1..] {
		body := '.method ' + block.all_before('.end method') + '.end method'
		invalid << old.replace(body, '')
		invalid << old + '\n' + body + '\n'
		invalid << old.replace(body, body.replace('.method public ', '.method private '))
		invalid << old.replace(body, body.replace('.end method', ''))
	}
	for header in ['public getStableDisplaySize()Landroid/graphics/Point;',
		'private native getStableDisplaySize()Landroid/graphics/Point;',
		'public static native getStableDisplaySize()Landroid/graphics/Point;',
		'public native getStableDisplaySize()I'] {
		invalid << old + '\n.method ' + header + '\n.end method\n'
	}
	for index, candidate in invalid { refused(work, index, candidate)! }
	mut controls := 0
	for broken in [
		patched.replace('public native getStableDisplaySize', 'public getStableDisplaySize'),
		patched.replace('getStableDisplaySize()Landroid/graphics/Point;', 'getStableDisplaySize()I'),
		patched.replace('public getDisplay(I)', 'private getDisplay(I)'),
		patched + '\n.field private snapshot:I\n',
	] {
		mut rejected := false
		verify(old, broken) or { rejected = true }
		assert rejected, 'ABI mutation passed source oracle'
		controls++
	}
	os.write_file(work + '/patched' + target, patched)!
	println('STABLE-DISPLAY-SOURCE-PASS refusals=' + invalid.len.str() + ' negative-ABI-controls=' + controls.str())
}
