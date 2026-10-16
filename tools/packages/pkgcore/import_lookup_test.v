// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn C.mkfifo(&char, u32) int

struct ImportLookupCase {
	name string
	path string
	diagnostic string
	kind u32 = 0o100000
}

fn import_lookup_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-import-lookup-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/usr/lib/deep')!
	os.mkdir(work + '/root/opt')!
	os.write_file(work + '/root/usr/lib/data', 'guest bytes')!
	os.chmod(work + '/root/usr/lib/data', 0o755)!
	os.write_file(work + '/outside', 'host bytes')!
	for name, target in {
		'absolute': '/usr/lib/data', 'relative': '../usr/lib/data',
		'intermediate': '/usr/lib/deep', 'parent': 'intermediate/../data',
		'root': '/', 'escape': '../../outside', 'cycle-a': 'cycle-b', 'cycle-b': 'cycle-a',
		'backslash': 'usr\\lib\\data', 'control': 'usr/lib/\ndata'
	} { os.symlink(target, work + '/root/opt/' + name)! }
	for index in 0 .. 40 {
		os.symlink(if index == 39 { '/usr/lib/data' } else { 'link-' + (index + 1).str() }, work + '/root/link-' + index.str())!
	}
	os.symlink('link-0', work + '/root/excessive')!
	assert C.mkfifo((work + '/root/pipe').str, 0o600) == 0
	return work
}

fn import_lookup_cases() []ImportLookupCase {
	return [
		ImportLookupCase{ name: 'ordinary', path: 'usr/lib/data' },
		ImportLookupCase{ name: 'directory', path: 'usr/lib', kind: 0o040000 },
		ImportLookupCase{ name: 'absolute-link', path: 'opt/absolute' },
		ImportLookupCase{ name: 'relative-parent-link', path: 'opt/relative' },
		ImportLookupCase{ name: 'parent-after-link', path: 'opt/parent' },
		ImportLookupCase{ name: 'parent-component', path: 'usr/lib/../lib/data' },
		ImportLookupCase{ name: 'empty-dot-components', path: '/usr//lib/./data' },
		ImportLookupCase{ name: 'forty-links', path: 'link-0' },
		ImportLookupCase{ name: 'nonblocking-fifo', path: 'pipe', kind: 0o010000 },
		ImportLookupCase{ name: 'missing', path: 'usr/lib/missing', diagnostic: 'cannot open prepared guest path' },
		ImportLookupCase{ name: 'not-directory', path: 'usr/lib/data/child', diagnostic: 'cannot open prepared guest path' },
		ImportLookupCase{ name: 'trailing-file-slash', path: 'usr/lib/data/', diagnostic: 'cannot open prepared guest path' },
		ImportLookupCase{ name: 'root-link', path: 'opt/root', diagnostic: 'resolves to its source root' },
		ImportLookupCase{ name: 'root-parent', path: 'usr/..', diagnostic: 'resolves to its source root' },
		ImportLookupCase{ name: 'escape', path: 'opt/escape', diagnostic: 'escapes its source root' },
		ImportLookupCase{ name: 'cycle', path: 'opt/cycle-a', diagnostic: 'cycle or excessive link depth' },
		ImportLookupCase{ name: 'forty-one-links', path: 'excessive', diagnostic: 'cycle or excessive link depth' },
		ImportLookupCase{ name: 'backslash', path: 'opt/backslash', diagnostic: 'unsafe or oversized guest symlink target' },
		ImportLookupCase{ name: 'control', path: 'opt/control', diagnostic: 'unsafe or oversized guest symlink target' },
		ImportLookupCase{ name: 'oversized', path: 'x'.repeat(4097), diagnostic: 'unsafe or oversized guest symlink target' },
	]
}

fn import_lookup_attempt(root int, item ImportLookupCase) {
	if node := import_node(root, item.path) {
		defer { C.close(node.fd) }
		assert item.diagnostic == '' && node.mode & 0o170000 == item.kind
		if item.kind == 0o100000 {
			assert node.bytes == 11 && node.mode & 0o111 == 0o111
			mut bytes := [11]u8{}
			assert C.read(node.fd, unsafe { &bytes[0] }, usize(bytes.len)) == bytes.len
			assert unsafe { tos(&bytes[0], bytes.len) } == 'guest bytes'
		}
	} else {
		message := err.msg()
		assert item.diagnostic != '' && message.contains(item.diagnostic), message
		unsafe { message.free(); err.free() }
	}
}

fn import_lookup_fds() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn test_prepared_lookup_retires_owned_paths_and_borrowed_prefixes_on_success_and_refusal() {
	work := import_lookup_work()!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	cases := import_lookup_cases()
	defer { for item in cases { unsafe { item.path.free() } }; unsafe { (&array(&cases)).free() } }
	before := import_lookup_fds()
	for item in cases {
		import_lookup_attempt(root, item)
		mut maximum := u64(0); mut allocations := u32(0)
		cycles := if '--import-lookup-baseline' in os.args { 4 } else { $if track_heap ? { 128 } $else { 8 } }
		for _ in 0 .. cycles {
			$if track_heap ? { C.vinix_heap_begin() }
			import_lookup_attempt(root, item)
			$if track_heap ? {
				kept := C.vinix_heap_end(); records := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if records > allocations { allocations = records }
			}
		}
		assert import_lookup_fds() == before
		label := 'IMPORT LOOKUP case=' + item.name
		$if track_heap ? {
			println(label + ' retained=' + maximum.str() + ' allocations=' + allocations.str())
			if '--import-lookup-baseline' !in os.args { assert maximum == 0 && allocations == 0 }
		} $else { println(label + ' functional-cycles=' + cycles.str() + ' PASS') }
	}
	assert os.read_file(work + '/outside')! == 'host bytes'
	println('IMPORT LOOKUP ordinary/guest-alias/parent/40-link/FIFO paths and late refusals retire scratch and descriptors PASS')
}

fn test_prepared_lookup_returned_descriptors_survive_retired_inputs_and_host_root_replacement() {
	work := import_lookup_work()!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work + '/root', 'test')!
	defer { C.close(root) }
	path := 'opt/parent'.clone()
	node := import_node(root, path)!
	unsafe { path.free() }
	defer { C.close(node.fd) }
	os.rename(work + '/root', work + '/retained')!
	os.mkdir_all(work + '/root/usr/lib')!
	os.write_file(work + '/root/usr/lib/data', 'host bytes!')!
	rechecked := recheck_import_node(root, 'opt/parent', node)!
	defer { C.close(rechecked) }
	assert node.bytes == 11
	mut bytes := [11]u8{}
	assert C.read(node.fd, unsafe { &bytes[0] }, usize(bytes.len)) == bytes.len
	assert unsafe { tos(&bytes[0], bytes.len) } == 'guest bytes'
	assert C.read(rechecked, unsafe { &bytes[0] }, usize(bytes.len)) == bytes.len
	assert unsafe { tos(&bytes[0], bytes.len) } == 'guest bytes'
	println('IMPORT LOOKUP independent descriptors survive retired source text, path scratch and host namespace replacement PASS')
}

fn import_lookup_recheck(root int, source string, node ImportNode, refused bool) {
	if fd := recheck_import_node(root, source, node) { C.close(fd); assert !refused }
	else {
		message := err.msg()
		assert refused && message != ''
		unsafe { message.free(); err.free() }
	}
}

fn test_prepared_lookup_rechecks_retire_complete_and_refused_resolution_scratch() {
	for fault in ['', 'directory', 'alias', 'execute', 'size', 'replacement', 'missing', 'closed-root']! {
		work := import_lookup_work()!
		defer { os.rmdir_all(work) or {} }
		root := capture_prepared_root(work + '/root', 'test')!
		defer { C.close(root) }
		source := if fault == 'directory' { 'usr/lib' } else if fault == 'alias' { 'opt/parent' } else { 'usr/lib/data' }
		node := import_node(root, source)!
		defer { C.close(node.fd) }
		path := work + '/root/usr/lib/data'
		match fault {
			'execute' { os.chmod(path, 0o644)! }
			'size' { os.truncate(path, 3)! }
			'replacement' { os.rename(path, path + '.saved')!; os.write_file(path, 'guest bytes')!; os.chmod(path, 0o755)! }
			'missing' { os.rm(path)! }
			else {}
		}
		lookup_root := if fault == 'closed-root' { -1 } else { root }
		refused := fault !in ['', 'directory', 'alias']
		import_lookup_recheck(lookup_root, source, node, refused)
		before := import_lookup_fds()
		mut maximum := u64(0); mut allocations := u32(0)
		cycles := $if track_heap ? { 128 } $else { 8 }
		for _ in 0 .. cycles {
			$if track_heap ? { C.vinix_heap_begin() }
			import_lookup_recheck(lookup_root, source, node, refused)
			$if track_heap ? {
				kept := C.vinix_heap_end(); records := C.vinix_heap_count()
				if kept > maximum { maximum = kept }; if records > allocations { allocations = records }
			}
		}
		assert import_lookup_fds() == before
		label := 'IMPORT RECHECK fault=' + if fault == '' { 'none' } else { fault }
		$if track_heap ? {
			println(label + ' retained=' + maximum.str() + ' allocations=' + allocations.str())
			assert maximum == 0 && allocations == 0
		} $else { println(label + ' functional-cycles=' + cycles.str() + ' PASS') }
	}
	println('IMPORT LOOKUP source rechecks retire complete and refused identity/size/execute/namespace scratch PASS')
}

fn test_prepared_lookup_restart_paths_keep_exact_bounds_and_own_their_bytes() {
	for relative in [false, true]! {
		prefix := ['usr', 'lib']
		target := if relative { 'x'.repeat(4088) } else { '/' + 'x'.repeat(4095) }
		parts := ['ignored']
		result := import_restart(prefix, target, parts, 1)!
		unsafe { target.free() }
		assert result.len == 4096
		assert result.starts_with(if relative { 'usr/lib/' } else { '/' }) && result.ends_with('xxx')
		unsafe { result.free(); (&array(&prefix)).free(); (&array(&parts)).free() }
	}
	for target in ['/' + 'x'.repeat(4096), 'x'.repeat(4089)] {
		defer { unsafe { target.free() } }
		mut refused := false
		import_restart(['usr', 'lib'], target, [], 0) or { refused = err.msg().contains('oversized') }
		assert refused
	}
	assert import_restart(['usr', 'lib'], '../deep', ['alias', 'tail', ''], 1)! == 'usr/lib/../deep/tail/'
	assert import_restart(['usr'], '', ['..', 'lib', 'data'], 1)! == 'usr/lib/data'
	println('IMPORT LOOKUP owned restart paths preserve parent/suffix order and exact 4096-byte boundary before allocation PASS')
}
