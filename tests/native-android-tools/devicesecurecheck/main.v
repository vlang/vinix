// SPDX-License-Identifier: GPL-2.0-or-later
// Source/ABI checks; the signed ARM fixture exercises the real service query.
module main

import androidtools
import os

const entry = '\n.method public isDeviceSecure()Z\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return v0\n.end method\n'
const target = '/android/app/KeyguardManager.smali'

fn verify(before string, after string) ! {
	if after != before + entry {
		return error('only the unconfigured-device query may be appended')
	}
}

fn refused(work string, number int, invalid string) ! {
	root := work + '/refused-' + number.str()
	os.mkdir_all(os.dir(root + target))!
	os.write_file(root + target, invalid)!
	mut rejected := false
	androidtools.framework_device_secure(root) or { rejected = true }
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
		added := entry.trim_space()
		assert after.count(added) == 1, 'query body changed in DEX'
		assert before.split_into_lines().filter(it.trim_space() != '') == after.replace(added, '').split_into_lines().filter(it.trim_space() != ''), 'retained KeyguardManager members changed'
		assert after == os.read_file(work + '/second-roundtrip' + target)!, 'second DEX roundtrip unstable'
		println('DEVICE-SECURE-ROUNDTRIP-PASS one-Java-API four-retained-methods stable-second-DEX')
		return
	}
	old := os.read_file(work + '/baseline' + target)!
	patched := androidtools.framework_device_secure_source(old)!
	verify(old, patched)!
	mut invalid := [old.replace('.class public ', '.class public final '),
		old.replace('Landroid/app/KeyguardManager;', 'Lwrong/KeyguardManager;'),
		old + '\n.class public Landroid/app/KeyguardManager;\n',
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
	for header in ['private isDeviceSecure()Z', 'public static isDeviceSecure()Z',
		'public native isDeviceSecure()Z', 'public isDeviceSecure()I'] {
		invalid << old + '\n.method ' + header + '\n.end method\n'
	}
	for index, candidate in invalid { refused(work, index, candidate)! }
	mut controls := 0
	for broken in [
		patched.replace(entry, entry.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
		patched.replace(entry, '\n.method public native isDeviceSecure()Z\n.end method\n'),
		patched.replace(entry, entry.replace('public isDeviceSecure', 'public static isDeviceSecure')),
		patched.replace(entry, entry.replace('const/4 v0, 0x0', 'invoke-virtual {p0}, Landroid/app/KeyguardManager;->isKeyguardSecure()Z\n    move-result v0')),
		patched.replace('public isKeyguardSecure()Z', 'private isKeyguardSecure()Z'),
		patched + '\n.field private credential:I\n',
	] {
		mut rejected := false
		verify(old, broken) or { rejected = true }
		assert rejected, 'semantic/ABI mutation passed source oracle'
		controls++
	}
	os.write_file(work + '/patched' + target, patched)!
	println('DEVICE-SECURE-SOURCE-PASS refusals=' + invalid.len.str() + ' negative-controls=' + controls.str())
}
