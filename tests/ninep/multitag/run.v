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
	cc := os.getenv_opt('CC') or { 'clang' }
	os.setenv('VEXE', v, true)
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
	os.cp(root + '/kernel/resource/open.v', facade + '/resource/open.v')!
	service := os.read_file(facade + '/dev/virtio_9p/virtio_9p.v')!
	for name in ['service_a', 'service_b'] {
		os.mkdir_all(facade + '/dev/' + name)!
		mut independent := service.replace('module virtio_9p', 'module ' + name)
		// V globals have process-wide names, even across modules.
		for global in ['channel', 'ninep_fixture_tx', 'ninep_fixture_rx', 'objects', 'fids', 'fid_modes', 'connected', 'calls', 'closes', 'setattr_mask', 'deny_open', 'create_race', 'read_unit', 'read_failure', 'read_short', 'read_offset', 'positive_short'] {
			independent = independent.replace(global, name + '_' + global)
		}
		os.write_file(facade + '/dev/' + name + '/service.v', independent)!
	}
	os.cp(root + '/tests/ninep/multitag/transport.vfixture', facade + '/dev/virtio_9p/virtio_9p.v')!
	os.cp(root + '/tests/ninep/multitag/facade_test.v', facade + '/fs/multitag_test.v')!
	checked(v, ['-nocache', '-cc', cc, '-enable-globals', '-o', work + '/facade-check', facade + '/fs/multitag_test.v'])
	checked(work + '/facade-check', [])
	checked(v, ['-nocache', '-cc', cc, '-enable-globals', '-gc', 'none', '-manualfree', '-o', work + '/facade.c', facade + '/fs/multitag_test.v'])
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
	// Share the mapped-DMA fixture, changing only its exported device tags.
	one_tag := "if tag == 'share' { u64(1) } else { u64(0) }"
	assert fixture.contains(one_tag)
	os.write_file(transport + '/transport.v', fixture.replace(one_tag,
		"if tag == 'tag-a' { u64(1) } else if tag == 'tag-b' { u64(2) } else { u64(0) }"))!
	os.cp(root + '/tests/ninep/multitag/channel_test.v', transport + '/multitag_test.v')!
	checked(v, ['-nocache', '-cc', cc, '-enable-globals', '-o', work + '/channel-check', transport + '/multitag_test.v'])
	checked(work + '/channel-check', [])
	println('MULTITAG-HOST-PASS production facade/client/channel; 7 read/write generated C bodies allocation-free')
}
