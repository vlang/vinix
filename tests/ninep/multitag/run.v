// Disposable host builds of the actual production facade, client and channel.
module main

import os
import crypto.rand

fn checked(v string, args []string) {
	mut p := os.new_process(v)
	p.set_args(args)
	p.run()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { exit(code) }
}

fn audit(path string, names []string) {
	generated := os.read_file(path) or { panic(err) }
	for name in names {
		mut found := false
		for line in generated.split_into_lines() {
			if line.starts_with('\t') || !line.ends_with(') {') || !line.replace('__', '_').contains(name + '(') { continue }
			body := generated.all_after(line + '\n').all_before('\n}\n')
			for alloc in ['memdup(', 'new_array', 'string__substr(', '_v_malloc(', 'HEAP(', 'heap('] {
				assert !body.contains(alloc), name + ': ' + alloc
			}
			found = true
			break
		}
		assert found, name
	}
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..', '..'))
	v := os.getenv_opt('V') or { @VEXE }
	work := root + '/../multitag-host-work-' + rand.bytes(8)!.hex()
	assert !os.exists(work), 'remove only this disposable work directory before rerunning'
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	facade := work + '/facade'
	os.cp_all(root + '/tests/ninep/protocol/fixture', facade, false)!
	os.write_file(facade + '/v.mod', "Module { name: 'multitag_facade' }")!
	os.mkdir_all(facade + '/fs/ninep')!
	for name in ['wire.v', 'options.v', 'client.v'] {
		os.cp(root + '/kernel/fs/ninep/' + name, facade + '/fs/ninep/' + name)!
	}
	os.mkdir_all(facade + '/stat')!
	os.cp(root + '/kernel/stat/stat.v', facade + '/stat/stat.v')!
	os.cp(root + '/kernel/fs/ninep.v', facade + '/fs/ninep.v')!
	os.cp(root + '/kernel/fs/network_mmap.v', facade + '/fs/network_mmap.v')!
	service := os.read_file(facade + '/dev/virtio_9p/virtio_9p.v')!
	for name in ['service_a', 'service_b'] {
		os.mkdir_all(facade + '/dev/' + name)!
		mut independent := service.replace('module virtio_9p', 'module ' + name)
		// V globals have process-wide names, even across modules.
		for global in ['channel', 'ninep_fixture_tx', 'ninep_fixture_rx', 'objects', 'fids', 'connected', 'calls', 'closes', 'setattr_mask', 'read_unit', 'read_failure', 'read_short', 'read_offset', 'positive_short'] {
			independent = independent.replace(global, name + '_' + global)
		}
		os.write_file(facade + '/dev/' + name + '/service.v', independent)!
	}
	os.cp(root + '/tests/ninep/multitag/transport.vfixture', facade + '/dev/virtio_9p/virtio_9p.v')!
	os.cp(root + '/tests/ninep/multitag/facade_test.v', facade + '/fs/multitag_test.v')!
	checked(v, ['-nocache', '-cc', 'clang', '-enable-globals', '-o', work + '/facade-check', facade + '/fs/multitag_test.v'])
	checked(work + '/facade-check', [])
	checked(v, ['-nocache', '-cc', 'clang', '-enable-globals', '-gc', 'none', '-manualfree', '-o', work + '/facade.c', facade + '/fs/multitag_test.v'])
	audit(work + '/facade.c', ['NinePResource_read', 'NinePResource_read_locked', 'NinePResource_write', 'NinePResource_write_locked', 'Client_read', 'Client_write', 'Client_call'])
	transport := work + '/transport'
	os.cp_all(root + '/tests/ninep/protocol/transport_fixture', transport, false)!
	os.write_file(transport + '/v.mod', "Module { name: 'multitag_channel' }")!
	os.mkdir_all(transport + '/klock')!
	os.cp(root + '/tests/ninep/protocol/fixture/klock/klock.v', transport + '/klock/klock.v')!
	for name in ['virtio_9p.v', 'queue.v'] {
		os.cp(root + '/kernel/dev/virtio_9p/' + name, transport + '/' + name)!
	}
	fixture := os.read_file(transport + '/transport.v')!
	// Distinct representable fake bus addresses, backed by real host memory.
	os.write_file(transport + '/transport.v', fixture.replace('virt: aligned, bus: aligned, bytes: bytes',
		'virt: aligned, bus: u64(0x100000) + ch.base * 0x100000 + if bytes == u64(buffer_bytes) * 2 { u64(0x40000) } else { u64(0) }, bytes: bytes')
		.replace('fn (mut _ Channel) alloc_dma(', 'fn (mut ch Channel) alloc_dma(')
		.replace('fn (mut ch Channel) locate(_ string) bool { return true }',
		"fn (mut ch Channel) locate(tag string) bool {\n ch.base = if tag == 'tag-a' { u64(1) } else if tag == 'tag-b' { u64(2) } else { return false }\n return !transport_claimed(0, ch.base)\n}"))!
	os.cp(root + '/tests/ninep/multitag/channel_test.v', transport + '/multitag_test.v')!
	checked(v, ['-nocache', '-cc', 'clang', '-enable-globals', '-o', work + '/channel-check', transport + '/multitag_test.v'])
	checked(work + '/channel-check', [])
	println('MULTITAG-HOST-PASS production facade/client/channel; 7 read/write generated C bodies allocation-free')
}
