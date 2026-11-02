// SPDX-License-Identifier: GPL-2.0-or-later
// Source/ABI checks; the signed ARM fixture exercises both real service calls.
module main

import androidtools
import os

const targets = ['/android/app/admin/DevicePolicyManager.smali', '/android/os/UserManager.smali']
const entries = [
	'\n.method public getDeviceOwner()Ljava/lang/String;\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return-object v0\n.end method\n',
	'\n.method public isManagedProfile()Z\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return v0\n.end method\n',
]
const descriptors = ['Landroid/app/admin/DevicePolicyManager;', 'Landroid/os/UserManager;']
const signatures = ['getDeviceOwner()Ljava/lang/String;', 'isManagedProfile()Z']
const original_methods = [9, 10]

fn verify(before string, after string, index int) ! {
	if after != before + entries[index] {
		return error('only the exact unmanaged query may be appended: ' + targets[index])
	}
}

fn patch(original string, index int) !string {
	return if index == 0 {
		androidtools.framework_device_owner_source(original)!
	} else {
		androidtools.framework_managed_profile_source(original)!
	}
}

fn files(root string) ![]string {
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.regular { result << path }
			.directory { result << files(path)! }
			else { return error('unexpected output type: ' + path) }
		}
	}
	return result.sorted()
}

fn directory_case(root string, originals []string, expected []string, rejected bool) ! {
	assert !os.exists(root) && !os.is_link(root), 'fresh directory case required'
	for index, target in targets {
		os.mkdir_all(os.dir(root + target))!
		os.write_file(root + target, originals[index])!
	}
	mut failed := false
	androidtools.framework_unmanaged_queries(root) or { failed = true }
	assert failed == rejected, 'unexpected directory transform result'
	for index, target in targets {
		assert os.read_file(root + target)! == expected[index], 'directory transform changed unexpected bytes'
	}
	assert files(root)! == targets.map(root + it).sorted(), 'directory transform added or removed files'
}

fn refused(work string, number int, originals []string, index int, candidate string) ! {
	mut rejected := false
	patch(candidate, index) or { rejected = true }
	assert rejected, 'malformed or repeated source accepted: ' + number.str()
	mut inputs := originals.clone()
	inputs[index] = candidate
	directory_case(work + '/refused-' + number.str(), inputs, inputs, true)!
}

fn roundtrip(work string) ! {
	mut retained := 0
	for index, target in targets {
		before := os.read_file(work + '/baseline-roundtrip' + target)!
		after := os.read_file(work + '/patched-roundtrip' + target)!
		added := entries[index].trim_space()
		assert before.split_into_lines().filter(it.trim_space().starts_with('.method ')).len == original_methods[index]
		assert after.count(added) == 1, 'unmanaged query body changed in DEX'
		assert before.split_into_lines().filter(it.trim_space() != '') ==
			after.replace(added, '').split_into_lines().filter(it.trim_space() != ''), 'retained service members changed in DEX'
		assert after == os.read_file(work + '/second-roundtrip' + target)!, 'second DEX roundtrip unstable'
		retained += original_methods[index]
	}
	assert retained == 19
	for directory in ['baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
		assert files(work + '/' + directory)! == targets.map(work + '/' + directory + it).sorted(), 'exact two-class DEX membership required'
	}
	println('UNMANAGED-QUERIES-ROUNDTRIP-PASS two-Java-APIs nineteen-retained-methods no-fields stable-second-DEX')
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		roundtrip(work)!
		return
	}
	mut originals := []string{}
	mut patched := []string{}
	for index, target in targets {
		old := os.read_file(work + '/baseline' + target)!
		assert old.split_into_lines().filter(it.trim_space().starts_with('.method ')).len == original_methods[index]
		originals << old
		transformed := patch(old, index)!
		verify(old, transformed, index)!
		patched << transformed
	}
	directory_case(work + '/directory-valid', originals, patched, false)!
	mut refusals := 0
	mut controls := 0
	for index, old in originals {
		mut invalid := [old.replace('.class public ', '.class public final '),
			old.replace(descriptors[index], 'Lwrong/Service;'),
			old + '\n.class public ' + descriptors[index] + '\n',
			old + '\n.class\tpublic ' + descriptors[index] + '\n',
			old.replace('.super Ljava/lang/Object;', '.super Lwrong/Parent;'),
			old + '\n.super Ljava/lang/Object;\n', old + '\n.super\tLjava/lang/Object;\n',
			old + '\n.field private unexpected:I\n', old + '\n\t.field private unexpected:I\n',
			old + '\n.field\tprivate unexpected:I\n', old + '\n.implements Lwrong/Interface;\n',
			old + '\n.implements\tLwrong/Interface;\n', old + '\n.end method\n',
			old + '\n.end\tmethod\n', patched[index],
			old + '\n.method\tpublic unexpected()V\n.end method\n']
		for block in old.split('.method ')[1..] {
			body := '.method ' + block.all_before('.end method') + '.end method'
			invalid << old.replace(body, '')
			invalid << old + '\n' + body + '\n'
			invalid << old.replace(body, body.replace('.method public ', '.method private '))
			invalid << old.replace(body, body.replace('.end method', ''))
		}
		for header in ['private ' + signatures[index], 'public static ' + signatures[index],
			'public native ' + signatures[index], 'public ' + signatures[index].all_before(')') + ')I'] {
			invalid << old + '\n.method ' + header + '\n.end method\n'
		}
		for candidate in invalid {
			refused(work, refusals, originals, index, candidate)!
			refusals++
		}
		entry := entries[index]
		for broken in [
			patched[index].replace(entry, entry.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
			patched[index].replace(entry, entry.replace('const/4 v0, 0x0', 'const-string v0, "unexpected.owner"')),
			patched[index].replace(entry, '\n.method public native ' + signatures[index] + '\n.end method\n'),
			patched[index].replace(entry, entry.replace('.method public ', '.method public static ')),
			patched[index].replace(entry, entry.replace('.method public ', '.method private ')),
			patched[index].replace(entry, entry.replace('return-object v0', 'return-void').replace('return v0', 'return-void')),
			patched[index] + '\n.field private policy:I\n',
			patched[index].replace('.method public constructor <init>()V', '.method private constructor <init>()V'),
		] {
			mut rejected := false
			verify(old, broken, index) or { rejected = true }
			assert rejected, 'semantic/ABI mutation passed source oracle'
			controls++
		}
	}
	// A valid first class must also remain unchanged if the second is absent.
	missing := work + '/missing-second'
	os.mkdir_all(os.dir(missing + targets[0]))!
	os.write_file(missing + targets[0], originals[0])!
	mut rejected := false
	androidtools.framework_unmanaged_queries(missing) or { rejected = true }
	assert rejected && os.read_file(missing + targets[0])! == originals[0]
	assert files(missing)! == [missing + targets[0]], 'missing-input refusal wrote files'
	for index, target in targets {
		assert !os.exists(work + '/patched' + target), 'fresh patched output required'
		os.mkdir_all(os.dir(work + '/patched' + target))!
		os.write_file(work + '/patched' + target, patched[index])!
	}
	assert files(work + '/patched')! == targets.map(work + '/patched' + it).sorted()
	println('UNMANAGED-QUERIES-SOURCE-PASS two-Java-APIs nineteen-retained-methods schema-before-writes refusals=' +
		refusals.str() + ' negative-controls=' + controls.str())
}
