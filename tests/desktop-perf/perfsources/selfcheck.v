// SPDX-License-Identifier: GPL-2.0-or-later
module perfsources

import os

fn C.truncate(&char, i64) i32

fn refuses(source string, destination string, selected []string) ! {
	stage(source, destination, selected) or { return }
	return error('invalid source snapshot accepted')
}

fn changed(receipt Receipt) ! {
	verify(receipt) or { return }
	return error('changed source snapshot accepted')
}

fn save_refuses(receipt Receipt, path string) ! {
	save(receipt, path) or { return }
	return error('existing source receipt overwritten')
}

pub fn selfcheck(state_arg string) ! {
	require(!os.exists(state_arg) && !os.is_link(state_arg), 'fresh source control state required')!
	os.mkdir_all(state_arg + '/source/pkg')!
	state := os.real_path(state_arg)
	os.mkdir_all(state + '/source/shared/nested')!
	source := state + '/source'
	os.write_file(source + '/pkg/main.v', 'module main\n')!
	os.write_file(source + '/shared/nested/value.v', 'module value\n')!
	os.write_file(source + '/unselected.v', 'do not stage this\n')!
	os.write_file(source + '/pkg/output.bin', 'excluded build output\n')!
	os.write_file(source + '/pkg/a.bin', 'forced source link target\n')!
	os.symlink('a.bin', source + '/pkg/z.h')!
	$if macos {
		link := source + '/pkg/z.h'
		require(unsafe { C.lchmod(&char(link.str), 0o711) } == 0, 'source link fixture mode failed')!
	}
	os.symlink('../shared', source + '/pkg/dependency')!
	os.symlink('../pkg', source + '/shared/back')!
	os.chmod(source + '/pkg/main.v', 0o640)!
	os.chmod(source + '/shared/nested', 0o550)!
	destination := state + '/staged'
	receipt := stage(source, destination, ['pkg'])!
	save(receipt, state + '/receipt.json')!
	verify(receipt)!
	require(!os.exists(destination + '/unselected.v') && !os.exists(destination + '/pkg/output.bin'),
		'unselected source or build output copied')!
	require(os.read_file(destination + '/pkg/dependency/nested/value.v')! == 'module value\n'
		&& os.readlink(destination + '/shared/back')! == '../pkg', 'module-link closure incomplete')!
	// A seed behind an internal parent alias still has one physical copy.
	alias := stage(source, state + '/alias-seed', ['pkg/dependency/nested/value.v'])!
	verify(alias)!
	refuses(source, destination, ['pkg'])!
	refuses(source, source + '/inside', ['pkg'])!
	refuses(source, state, ['pkg'])!
	refuses(source, state + '/missing', ['missing'])!
	refuses(source, state + '/traversal', ['../source/pkg'])!
	save_refuses(receipt, state + '/receipt.json')!
	save_refuses(receipt, source + '/forbidden.json')!
	save_refuses(receipt, destination + '/forbidden.json')!
	os.write_file(source + '/pkg/main.v', 'changed\n')!; changed(receipt)!
	os.write_file(source + '/pkg/main.v', 'module main\n')!
	os.chmod(source + '/pkg/main.v', 0o640)!
	os.write_file(source + '/pkg/added.v', 'module added\n')!; changed(receipt)!
	os.rm(source + '/pkg/added.v')!
	os.write_file(destination + '/pkg/main.v', 'changed\n')!; changed(receipt)!
	os.write_file(destination + '/pkg/main.v', 'module main\n')!
	os.chmod(destination + '/pkg/main.v', 0o640)!
	os.write_file(destination + '/unexpected.bin', 'extra\n')!; changed(receipt)!
	os.rm(destination + '/unexpected.bin')!
	os.chmod(destination, int(receipt.entries[0].mode ^ 0o100))!; changed(receipt)!
	os.chmod(destination, int(receipt.entries[0].mode))!
	os.rm(destination + '/pkg/dependency')!; os.symlink('../pkg', destination + '/pkg/dependency')!
	changed(receipt)!
	os.rm(destination + '/pkg/dependency')!; os.symlink('../shared', destination + '/pkg/dependency')!
	verify(receipt)!
	os.write_file(state + '/outside.v', 'outside\n')!
	os.symlink('../../outside.v', source + '/pkg/escape.v')!
	refuses(source, state + '/escape', ['pkg'])!; os.rm(source + '/pkg/escape.v')!
	os.symlink(source + '/pkg/main.v', source + '/pkg/absolute.v')!
	refuses(source, state + '/absolute', ['pkg'])!; os.rm(source + '/pkg/absolute.v')!
	os.symlink('missing.v', source + '/pkg/dangling.v')!
	refuses(source, state + '/dangling', ['pkg'])!; os.rm(source + '/pkg/dangling.v')!
	large := source + '/pkg/too-large.v'
	os.write_file(large, '')!
	require(unsafe { C.truncate(&char(large.str), 5 * 1024 * 1024 + 1) } == 0, 'oversized source fixture failed')!
	refuses(source, state + '/oversized', ['pkg'])!; os.rm(large)!
	verify(receipt)!
	os.write_file(state + '/result', 'PASS source selection, internal link closure, modes, alias seeds, changed/additional source and destination, overlap/freshness/escape/dangling refusals\n')!
	println('PERF SOURCE snapshot controls PASS')
}
