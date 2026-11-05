// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

import json2
import os

pub fn pinned_text2(path string, sum string, maximum u64) !string {
	ordinary2(path, 'file')!
	if !hex2(sum, 64) || os.lstat(path)!.size > maximum || digest2(path)! != sum {
		return error('pinned ordinary text differs or exceeds its bound: ' + path)
	}
	text := os.read_file(path)!
	if digest2(path)! != sum { return error('pinned text changed while reading') }
	return text
}

// The complete historical capture is an identity source, never evidence that
// the failed producer completed. Only these immutable roles may be borrowed.
fn expected_roles2() map[string]Borrow2 {
	mut roles := map[string]Borrow2{}
	for name, path in {
		'sysroot': 'inputs/cross-sysroot'
		'gcc': 'inputs/cross-gcc'
		'vlib': 'inputs/vlib'
		'stdatomic': 'inputs/v-thirdparty/stdatomic'
		'kernel-evidence': 'inputs/kernel-evidence'
	} { roles[name] = Borrow2{root: 'capture', path: path, kind: 'directory'} }
	for name, path in {
		'kernel': 'inputs/kernel'
		'v': 'inputs/v'
		'host-cc': 'inputs/adapter-host-cc'
		'backend': 'inputs/cross-backend'
		'qemu': 'inputs/qemu'
		'firmware': 'inputs/firmware'
		'firmware-vars': 'inputs/firmware-vars'
		'cc1': 'inputs/cross-cc1'
		'collect2': 'inputs/cross-collect2'
		'as': 'inputs/cross-as'
		'ld': 'inputs/cross-ld'
		'lto-wrapper': 'inputs/cross-lto-wrapper'
		'lto-plugin': 'inputs/cross-lto-plugin'
	} { roles[name] = Borrow2{root: 'capture', path: path, kind: 'file'} }
	return roles
}

fn role_shape2(donor Donor2) ! {
	expected := expected_roles2()
	if donor.format != 2 || donor.profile != format2_profile || donor.roots.len != 2
		|| donor.roles.len != expected.len || donor.entries.len == 0 {
		return error('requires complete separate format-2 donor and fixed immutable roles')
	}
	for name, role in expected {
		actual := donor.roles[name] or { return error('missing immutable role: ' + name) }
		if actual.root != role.root || actual.path != role.path || actual.kind != role.kind {
			return error('immutable role geometry differs: ' + name)
		}
		path := leaf2(donor.roots[actual.root], actual.path, actual.kind)!
		if actual.kind == 'directory' {
			if actual.sha256 != '' { return error('directory identity is its complete inventory') }
		} else if !hex2(actual.sha256, 64) || digest2(path)! != actual.sha256 {
			return error('immutable role file differs: ' + name)
		}
		entries := donor.entries.filter(it.root == actual.root && it.path == actual.path)
		if entries.len != 1 || entries[0].kind != actual.kind || entries[0].sha256 != actual.sha256 {
			return error('immutable role is absent from complete donor manifest: ' + name)
		}
	}
}

pub fn load_donor2(plan Plan2, legacy LegacyPlan2) !Donor2 {
	text := pinned_text2(plan.donor_manifest_path, plan.donor_manifest_sha256, 32 << 20)!
	donor := json2.decode[Donor2](text)!
	if text != json2.encode(donor) + '\n' { return error('donor JSON must be exact typed encoding') }
	if donor.roots['capture'] != legacy.state_root
		|| donor.roots['store'] != os.dir(legacy.state_root) + '/audio-input-store' {
		return error('donor must describe complete original failed capture and its complete store')
	}
	for _, root in donor.roots {
		ordinary2(root, 'directory')!
		if under2(root, plan.donor_manifest_path) || !disjoint2(root, plan.state_root)
			|| !disjoint2(root, plan.source_root) {
			return error('donor manifest, mutable state and new source must be outside donor roots')
		}
	}
	verify_donor2(donor)!
	return donor
}

pub fn verify_donor2(donor Donor2) ! {
	role_shape2(donor)!
	actual := inventory2(donor.roots)!
	if actual != donor.entries { return error('complete donor input inventory differs') }
	closed_aliases2(actual, false)!
}

pub fn borrow_path2(donor Donor2, name string) !string {
	expected := expected_roles2()
	role := donor.roles[name] or { return error('unknown immutable role: ' + name) }
	shape := expected[name] or { return error('role is not in fixed immutable allowlist') }
	if role.root != shape.root || role.path != shape.path || role.kind != shape.kind {
		return error('immutable role geometry differs')
	}
	return leaf2(donor.roots[role.root], role.path, role.kind)!
}

// Read detached worktree identity without running git or accepting a ref name.
// The source inventory also binds the .git file. Git metadata is provenance;
// all build content is separately bound by the complete ordinary source tree.
fn detached_revision2(root string) !string {
	path := leaf2(root, '.git', 'file')!
	if os.lstat(path)!.size > 4096 { return error('invalid sparse worktree .git pointer') }
	text := os.read_file(path)!
	if !text.starts_with('gitdir: /') || !text.ends_with('\n') || text.count('\n') != 1 {
		return error('requires an ordinary detached sparse source worktree')
	}
	gitdir := text[8..text.len - 1]
	ordinary2(gitdir, 'directory')!
	head := leaf2(gitdir, 'HEAD', 'file')!
	if os.lstat(head)!.size != 41 { return error('source worktree HEAD must be detached') }
	value := os.read_file(head)!
	if !value.ends_with('\n') || !hex2(value[..40], 40) { return error('invalid detached source revision') }
	return value[..40]
}

pub fn load_source2(plan Plan2) !Source2 {
	text := pinned_text2(plan.source_manifest_path, plan.source_manifest_sha256, 16 << 20)!
	source := decode_source2(text)!
	if source.root != plan.source_root
		|| source.base_revision != plan.source_base_revision || under2(source.root, plan.source_manifest_path) {
		return error('source manifest is not the exact separately pinned fresh source closure')
	}
	verify_source2(source)!
	return source
}

fn decode_source2(text string) !Source2 {
	source := json2.decode[Source2](text, strict: true)!
	if text != json2.encode(source) + '\n' || source.format != 2 || source.profile != format2_profile
		|| source.content_contract != reviewed_source_contract2 || !hex2(source.base_revision, 40) {
		return error('source requires exact reviewed-content/base-provenance format-2 encoding')
	}
	return source
}

pub fn verify_source2(source Source2) ! {
	if source.format != 2 || source.profile != format2_profile
		|| source.content_contract != reviewed_source_contract2 || !hex2(source.base_revision, 40)
		|| source.entries.len == 0 || detached_revision2(source.root)! != source.base_revision {
		return error('reviewed source content contract or detached base provenance differs')
	}
	actual := inventory2({'source': source.root})!
	if actual != source.entries { return error('complete new source inventory differs') }
	closed_aliases2(actual, true)!
}
