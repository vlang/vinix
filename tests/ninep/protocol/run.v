// SPDX-License-Identifier: GPL-2.0-or-later
// Host checks compile the actual production parsers/client and queue policy.
module main

import os

fn run(compiler string, args []string) {
	mut child := os.new_process(compiler)
	child.set_args(args)
	child.run()
	child.wait()
	code := child.code
	child.close()
	if code != 0 { exit(code) }
}

fn audit_no_allocations(path string, names []string) {
	generated := os.read_file(path) or { panic(err) }
	for name in names {
		mut found := false
		for line in generated.split_into_lines() {
			if !line.replace('__', '_').contains(name + '(') || !line.ends_with(') {') || line.starts_with('	') {
				continue
			}
			body := generated.all_after(line + '\n').all_before('\n}\n')
			for allocation in ['memdup(', 'new_array', 'string__substr(', '_v_malloc(', 'HEAP(',
				'heap('] {
				assert !body.contains(allocation), name + ' allocates: ' + allocation
			}
			found = true
			break
		}
		assert found, 'missing generated C definition: ' + name
	}
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..', '..'))
	scratch := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	work := os.join_path(scratch, 'vinix-ninep-protocol-${os.getpid()}')
	os.mkdir_all(work + '/ninep')!
	os.mkdir_all(work + '/virtio_9p')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'ninep_host_checks' }")!
	for name in ['wire.v', 'options.v', 'client.v'] {
		os.cp(root + '/kernel/fs/ninep/' + name, work + '/ninep/' + name)!
	}
	os.cp(root + '/tests/ninep/protocol/wire_test.v', work + '/ninep/wire_test.v')!
	os.cp(root + '/tests/ninep/protocol/client_test.v', work + '/ninep/client_test.v')!
	os.cp(root + '/kernel/dev/virtio_9p/queue.v', work + '/virtio_9p/queue.v')!
	os.cp(root + '/tests/ninep/protocol/queue_test.v', work + '/virtio_9p/queue_test.v')!
	compiler := os.getenv_opt('V') or { @VEXE }
	os.setenv('VEXE', compiler, true)
	run(compiler, ['-nocache', '-cc', 'clang', '-enable-globals', 'test', work + '/ninep'])
	run(compiler, ['-nocache', '-cc', 'clang', 'test', work + '/virtio_9p'])
	os.mkdir_all(work + '/facade')!
	os.cp_all(root + '/tests/ninep/protocol/fixture', work + '/facade', false)!
	os.write_file(work + '/facade/v.mod', "Module { name: 'ninep_facade_fixture' }")!
	os.mkdir_all(work + '/facade/fs/ninep')!
	for name in ['wire.v', 'options.v', 'client.v'] {
		os.cp(root + '/kernel/fs/ninep/' + name, work + '/facade/fs/ninep/' + name)!
	}
	os.cp(root + '/kernel/stat/stat.v', work + '/facade/stat/stat.v')!
	os.cp(root + '/kernel/fs/ninep.v', work + '/facade/fs/ninep.v')!
	os.cp(root + '/tests/ninep/protocol/facade_test.v', work + '/facade/fs/facade_test.v')!
	run(compiler, ['-nocache', '-cc', 'clang', '-enable-globals', 'test', work + '/facade/fs'])
	run(compiler, ['-nocache', '-cc', 'clang', '-enable-globals', '-gc', 'none', '-manualfree',
		'-o', work + '/facade.c', work + '/facade/fs/facade_test.v'])
	audit_no_allocations(work + '/facade.c', ['ninep_resource', 'NinePResource_refresh_locked',
		'NinePResource_read', 'NinePResource_write_locked', 'NinePResource_write', 'NinePResource_grow',
		'NinePResource_persist_metadata', 'NinePResource_open', 'NinePResource_snapshot_permissions',
		'Client_read', 'Client_write', 'Client_call', 'Client_walk', 'Client_clunk', 'Client_getattr',
		'parse_attr', 'next_entry', 'parse_options'])
	os.mkdir_all(work + '/transport')!
	os.cp_all(root + '/tests/ninep/protocol/transport_fixture', work + '/transport', false)!
	os.write_file(work + '/transport/v.mod', "Module { name: 'ninep_transport_fixture' }")!
	os.cp(root + '/tests/ninep/protocol/fixture/klock/klock.v', work + '/transport/klock/klock.v')!
	for name in ['virtio_9p.v', 'queue.v'] {
		os.cp(root + '/kernel/dev/virtio_9p/' + name, work + '/transport/' + name)!
	}
	os.cp(root + '/tests/ninep/protocol/transport_test.v', work + '/transport/transport_test.v')!
	run(compiler, ['-nocache', '-cc', 'clang', '-enable-globals', 'test', work + '/transport'])
	// The numeric import failure is recorded in NOTES.md; the replacement
	// module path is proven here by compiling a real consumer.
	os.write_file(work + '/main.v', 'module main\nimport ninep\nfn main() { assert ninep.max_msize == 65536 }\n')!
	run(compiler, ['-cc', 'clang', 'run', work + '/main.v'])
	println('9P production protocol/client and split-ring policy host checks PASS')
}
