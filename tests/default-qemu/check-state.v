// SPDX-License-Identifier: GPL-2.0-or-later
// Check state allocation through the runner CLI without booting a guest.
import os
import rand

fn require_command(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args}: ${result.output}')
	}
}

fn check_state() ! {
	root := os.join_path(os.temp_dir(), 'vinix-qemu-state-' + rand.hex(8))
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	compiler := os.getenv_opt('V') or { 'v' }
	source := os.dir(@FILE)
	runner := os.join_path(root, 'runner')
	require_command([compiler, '-cc', 'cc', '-o', runner, os.join_path(source, 'run.v')])!
	os.setenv('VINIX_QEMU_X86_64', os.executable(), true)
	parent := os.join_path(root, 'out with spaces', 'qemu-amd64-default')
	mut states := []string{}
	// Two images per release invocation, followed by a rerun with the same OUT.
	for _ in 0 .. 2 {
		for name in ['first-amd64.iso', 'second-amd64.iso'] {
			iso := os.join_path(root, name)
			os.write_file(iso, 'fixture')!
			result := os.exec([runner, '--desktop', '--state-parent', iso, parent, 'unused-qmp'])
			assert result.exit_code == 1
			assert result.output.contains('FAIL: INPUT FAIL: state fixture reached QEMU')
			state := result.output.all_after('Default QEMU evidence: ').all_before('\n')
			assert os.dir(state) == parent
			assert state !in states
			assert os.read_file(state + '/booted-iso')! == iso
			assert os.read_file(state + '/command.txt')!.contains(iso)
			states << state
			// No subsequent invocation may delete or overwrite earlier evidence.
			for saved in states {
				assert os.read_file(saved + '/serial.log')! == 'INPUT FAIL: state fixture reached QEMU\n'
				assert os.is_file(saved + '/booted-iso')
			}
		}
	}
	// Explicit state paths retain the original refusal to overwrite evidence.
	iso := os.join_path(root, 'first-amd64.iso')
	explicit := os.join_path(root, 'explicit')
	first := os.exec([runner, '--desktop', iso, explicit, 'unused-qmp'])
	assert first.output.contains('FAIL: INPUT FAIL: state fixture reached QEMU')
	before := os.read_file(explicit + '/command.txt')!
	repeat := os.exec([runner, '--desktop', iso, explicit, 'unused-qmp'])
	assert repeat.exit_code == 1
	assert repeat.output.contains('state directory must be new: ' + explicit)
	assert os.read_file(explicit + '/command.txt')! == before
	println('PASS: two images, repeated output directory, preserved evidence and explicit-state refusal')
}

fn main() {
	// The same V executable stands in for QEMU and terminates the runner's
	// desktop wait immediately after recording the actual launch arguments.
	if os.args.len > 1 && os.args[1] == '-m' {
		serial := os.args[os.args.index('-serial') + 1].all_after('file:')
		iso := os.args[os.args.index('-cdrom') + 1]
		os.write_file(os.dir(serial) + '/booted-iso', iso) or { panic(err) }
		os.write_file(serial, 'INPUT FAIL: state fixture reached QEMU\n') or { panic(err) }
		return
	}
	check_state() or {
		eprintln(err)
		exit(1)
	}
}
