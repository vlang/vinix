// SPDX-License-Identifier: GPL-2.0-or-later
// Future execution requires an explicitly charged external fixture root.
module audiocontinue

import json2
import os
import time

fn inventory_cleanup2(path string) {
	if os.getenv('AUDIO_CONTINUATION_RETAIN_FIXTURES') != '1' { os.rmdir_all(path) or {} }
}

fn inventory_fixture2() !string {
	root := os.getenv('AUDIO_CONTINUATION_TEST_ROOT')
	ordinary2(root, 'directory')!
	path := root + '/inventory2-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(path, mode: 0o700)!
	return path
}

fn donor_fixture2(base string) !Donor2 {
	capture := base + '/capture'
	store := base + '/store'
	os.mkdir(capture)!
	os.mkdir(store)!
	mut roles := expected_roles2()
	for name, role in roles.clone() {
		path := capture + '/' + role.path
		os.mkdir_all(os.dir(path))!
		if role.kind == 'directory' {
			os.mkdir_all(path)!
			os.write_file(path + '/ordinary-fixture.h', 'immutable directory ' + name + '\n')!
		} else {
			os.write_file(path, 'immutable file ' + name + '\n')!
			sum := digest2(path)!
			os.link(path, store + '/' + sum)!
			roles[name] = Borrow2{root: role.root, path: role.path, kind: role.kind, sha256: sum}
		}
	}
	roots := {'capture': capture, 'store': store}
	return Donor2{roots: roots, entries: inventory2(roots)!, roles: roles}
}

fn donor_refuses2(donor Donor2) {
	mut refused := false
	verify_donor2(donor) or { refused = true }
	production_require2((refused), 'production assertion')
}

struct RootLinkWitness2 {
	root string
	before_nlink u64
	after_nlink u64
	before_inode u64
	after_inode u64
}

fn test_complete_donor_allows_only_fully_contained_historical_aliases() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	verify_donor2(donor) or { panic(err) }
	path := borrow_path2(donor, 'kernel') or { panic(err) }
	os.link(path, base + '/external-mutable-alias') or { panic(err) }
	// Even a newly captured manifest cannot admit a hard link outside its two
	// complete immutable roots.
	changed := Donor2{roots: donor.roots,
		entries: inventory2(donor.roots) or { panic(err) }, roles: donor.roles}
	donor_refuses2(changed)
}

fn test_complete_donor_rejects_missing_unknown_and_reassigned_entries() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	donor_refuses2(Donor2{roots: donor.roots, entries: donor.entries[..donor.entries.len - 1], roles: donor.roles})
	mut roles := donor.roles.clone()
	roles['kernel'] = donor.roles['v']
	donor_refuses2(Donor2{roots: donor.roots, entries: donor.entries, roles: roles})
	os.write_file(base + '/capture/unlisted', 'new unknown donor entry\n') or { panic(err) }
	donor_refuses2(donor)
}

fn test_inventory_refuses_symlinks_and_mutated_file_identity() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	path := borrow_path2(donor, 'kernel') or { panic(err) }
	os.write_file(path, 'changed immutable fixture\n') or { panic(err) }
	donor_refuses2(donor)
	os.symlink('inputs/kernel', base + '/capture/alias') or { panic(err) }
	mut refused := false
	inventory2(donor.roots) or { refused = true }
	production_require2((refused), 'production assertion')
}

fn test_fresh_owned_tree_keeps_independent_file_and_directory_metadata() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	out := base + '/fresh'
	os.mkdir(out) or { panic(err) }
	os.mkdir(out + '/nested') or { panic(err) }
	source := borrow_path2(donor, 'kernel') or { panic(err) }
	copy_new2(source, out + '/nested/output', donor) or { panic(err) }
	raw_before := os.lstat(out) or { panic(err) }
	before := capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }
	production_require2((before[0].nlink == 0 && before[0].size == 0 && before[0].mtime == 0 && before[0].ctime == 0), 'production assertion')
	production_require2((before[0].mode == raw_before.mode && before[0].uid == raw_before.uid), 'production assertion')
	production_require2((before[0].gid == raw_before.gid && before[0].dev == raw_before.dev), 'production assertion')
	production_require2((before[0].inode == raw_before.inode), 'production assertion')
	write_new2(out + '/preparation2.json', 'sole excluded regular receipt\n') or { panic(err) }
	raw_after := os.lstat(out) or { panic(err) }
	// Outside the captured fresh root: retain actual platform observations,
	// without requiring a particular filesystem's directory link behavior.
	write_new2(base + '/root-nlink-witness.json', json2.encode(RootLinkWitness2{
		root: out, before_nlink: u64(raw_before.nlink), after_nlink: u64(raw_after.nlink),
		before_inode: raw_before.inode, after_inode: raw_after.inode}) + '\n') or { panic(err) }
	production_require2((raw_after.dev == raw_before.dev && raw_after.inode == raw_before.inode), 'production assertion')
	production_require2(((capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }) == before), 'production assertion')
	write_new2(out + '/unexpected-file', 'an unrelated output is never excluded\n') or { panic(err) }
	production_require2(((capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }) != before), 'production assertion')
	os.rename(out + '/unexpected-file', base + '/unexpected-file-witness') or { panic(err) }
	os.mkdir(out + '/unexpected-empty-directory') or { panic(err) }
	production_require2(((capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }) != before), 'production assertion')
	os.rename(out + '/unexpected-empty-directory', base + '/unexpected-empty-directory-witness') or { panic(err) }
	mutated_mode := if raw_before.mode & 0o7777 == 0o700 { 0o750 } else { 0o700 }
	os.chmod(out, mutated_mode) or { panic(err) }
	changed_mode := capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }
	production_require2((changed_mode[0].mode == (os.lstat(out) or { panic(err) }).mode), 'production assertion')
	production_require2((changed_mode[0].mode != before[0].mode && changed_mode != before), 'production assertion')
	os.chmod(out, int(raw_before.mode & 0o7777)) or { panic(err) }
	production_require2(((capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }) == before), 'production assertion')
	os.rename(out, base + '/original-fresh') or { panic(err) }
	os.mkdir(out, mode: int(raw_before.mode & 0o7777)) or { panic(err) }
	replacement := capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }
	replacement_raw := os.lstat(out) or { panic(err) }
	production_require2((replacement[0].mode == before[0].mode && replacement[0].uid == before[0].uid), 'production assertion')
	production_require2((replacement[0].gid == before[0].gid && replacement[0].dev == replacement_raw.dev), 'production assertion')
	production_require2((replacement[0].inode == replacement_raw.inode), 'production assertion')
	production_require2((replacement[0].dev != before[0].dev || replacement[0].inode != before[0].inode), 'production assertion')
	production_require2((replacement[0] != before[0]), 'production assertion')
	// Preserve both directory identities; restore the original for the separate
	// ordinary-file hard-link refusal below.
	os.rename(out, base + '/replacement-root') or { panic(err) }
	os.rename(base + '/original-fresh', out) or { panic(err) }
	production_require2(((capture_owned2(out, ['preparation2.json'], donor) or { panic(err) }) == before), 'production assertion')
	os.link(out + '/nested/output', base + '/new-output-alias') or { panic(err) }
	mut refused := false
	capture_owned2(out, ['preparation2.json'], donor) or { refused = true }
	production_require2((refused), 'production assertion')
}

fn test_new_writer_refuses_existing_paths_and_symlink_parents() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	path := base + '/new'
	write_new2(path, 'first immutable output\n') or { panic(err) }
	mut refused := false
	write_new2(path, 'overwriting is forbidden\n') or { refused = true }
	production_require2((refused), 'production assertion')
	production_require2(((os.read_file(path) or { panic(err) }) == 'first immutable output\n'), 'production assertion')
	os.mkdir(base + '/ordinary') or { panic(err) }
	os.symlink('ordinary', base + '/alias') or { panic(err) }
	refused = false
	write_new2(base + '/alias/outside', 'must not follow alias\n') or { refused = true }
	production_require2((refused), 'production assertion')
}

fn test_manifest_version_defaults_do_not_admit_unknown_versions() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	for format in [0, 1, 3] {
		donor_refuses2(Donor2{format: format, roots: donor.roots, entries: donor.entries, roles: donor.roles})
	}
}

fn test_failure_observations_preserve_intact_store_and_partial_capture() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	os.symlink('inputs/kernel', base + '/capture/zz-damaged-link') or { panic(err) }
	actual := observe_roots2(donor.roots)
	production_require2((actual.errors['capture'] != ''), 'production assertion')
	production_require2(('store' !in actual.errors), 'production assertion')
	production_require2((actual.entries.any(it.root == 'capture' && it.path == 'inputs/kernel')), 'production assertion')
	production_require2((actual.entries.filter(it.root == 'store') == donor.entries.filter(it.root == 'store')), 'production assertion')
	mut refused := false
	inventory2(donor.roots) or { refused = true }
	production_require2((refused), 'production assertion')
}

fn test_missing_capture_does_not_suppress_complete_store_observation() {
	base := inventory_fixture2() or { panic(err) }
	defer { inventory_cleanup2(base) }
	donor := donor_fixture2(base) or { panic(err) }
	actual := observe_roots2({'capture': base + '/missing', 'store': donor.roots['store']})
	production_require2((actual.errors['capture'] != ''), 'production assertion')
	production_require2(('store' !in actual.errors), 'production assertion')
	production_require2((actual.entries == donor.entries.filter(it.root == 'store')), 'production assertion')
}
