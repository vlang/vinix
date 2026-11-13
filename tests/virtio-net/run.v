// Compile production policy/queues against a mock transport; no QEMU required.
module main

import os

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	work := os.join_path(os.temp_dir(), 'vinix-virtio-net-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	for source in ['kernel/dev/virtio_net/policy.v', 'kernel/dev/virtio_net/virtio_net.v',
		'tests/virtio-net/fixture/policy_test.v', 'tests/virtio-net/fixture/queue_test.v',
		'tests/virtio-net/fixture/transport.v'] {
		os.cp(os.join_path(root, source), os.join_path(work, os.file_name(source))) or {
			panic(err)
		}
	}
	for name in ['dma', 'katomic', 'klock', 'socket'] {
		os.cp_all(os.join_path(root, 'tests/virtio-net/fixture', name), os.join_path(work, name),
			false) or { panic(err) }
	}
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'virtio_net_fixture' }") or {
		panic(err)
	}
	mut compiler := os.getenv('V')
	if compiler == '' { compiler = @VEXE }
	mut process := os.new_process(compiler)
	process.set_args(['-enable-globals', '-cc', 'cc', 'test', work])
	process.run()
	process.wait()
	code := process.code
	process.close()
	os.rmdir_all(work) or {}
	if code != 0 { exit(code) }
}
