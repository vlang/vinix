// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

import fixturehost
import hosttest
import os

struct DescriptorOwner {
	number i32
	owner  i32
	flags  i32
}

fn restore(owners []DescriptorOwner) {
	for owner in owners {
		assert C.dup2(owner.owner, owner.number) == owner.number
		assert C.fcntl(owner.number, C.F_SETFD, owner.flags) == 0
	}
}

fn test_native_capture_descriptor_states_text_errors_and_retirement() {
	probe := os.getenv('VINIX_VMX_PROBE')
	if probe == '' { return }
	work := hosttest.work_dir('', 'vinix-vmx-process-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := join(work, 'snapshot')
	c := Config{ caller: if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }, env: os.environ() }
	mut owners := []DescriptorOwner{}
	for number in 0 .. 3 {
		owner := C.fcntl(i32(number), C.F_DUPFD_CLOEXEC, 30)
		assert owner >= 30
		owners << DescriptorOwner{i32(number), owner, C.fcntl(i32(number), C.F_GETFD)}
	}
	defer {
		restore(owners)
		for owner in owners { C.close(owner.owner) }
	}
	for input in 0 .. 3 {
		for output in 0 .. 3 {
			for error_stream in 0 .. 3 {
				restore(owners)
				states := [input, output, error_stream]
				for number, state in states {
					if state == 1 { C.close(i32(number)) }
					if state == 2 {
						assert C.fcntl(i32(number), C.F_SETFD, C.FD_CLOEXEC) == 0
					}
				}
				before := [0, 1, 2].map(C.fcntl(i32(it), C.F_GETFD).str())
				expected := states.map(if it == 0 { '0' } else { '-1' })
				c.inherited([probe, path, 'inherited'])!
				assert os.read_file(path)! == expected.join(',') + '\n'
				assert [0, 1, 2].map(C.fcntl(i32(it), C.F_GETFD).str()) == before
				mut captured := expected.clone()
				captured[1] = '0'
				assert c.text_command([probe, path, 'capture'])! == 'capture\nreply\n'
				assert os.read_file(path)! == captured.join(',') + '\n'
				assert [0, 1, 2].map(C.fcntl(i32(it), C.F_GETFD).str()) == before
			}
		}
	}
	restore(owners)
	before := os.ls('/dev/fd')!.sorted()
	for _ in 0 .. 100 {
		assert c.text_command([probe, path, 'capture'])! == 'capture\nreply\n'
	}
	mut failed := false
	c.text_command([probe, path, 'failure']) or {
		assert err is fixturehost.CommandError
		if err is fixturehost.CommandError {
			assert err.status == 37 && err.output == 'capture\nreply\n' && !err.binary_output
		}
		failed = true
	}
	assert failed
	mut decoded := false
	c.text_command([probe, path, 'invalid']) or {
		assert err.msg().contains('Invalid UTF-8')
		decoded = true
	}
	assert decoded, 'command failure hid its invalid UTF-8 output'
	assert os.ls('/dev/fd')!.sorted() == before
}
