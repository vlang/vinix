import os
import time

fn main() {
	out := 'tests/android/results/2026-10-23/maps-action-provider/resume245/'
	assert !os.exists(out + 'processes.txt'), 'Process capture is immutable'
	pid := os.read_file('build/android-maps/attempt245/google-maps/qemu.pid')!.trim_space()
	assert pid.len > 0 && pid.bytes().all(it.is_digit())
	result := os.exec(['ps', '-o', 'pid,ppid,lstart,etime,command', '-p',
		'98852,99069,99070,99712,' + pid])
	assert result.exit_code == 0, result.output
	assert result.output.contains('qemu-system-aarch64')
	os.write_file(out + 'processes.txt', time.utc().str() + ' UTC\n' + result.output)!
	os.cp(@FILE, out + 'capture245-pids.v')!
	println(result.output)
	proof := os.exec(['build/android-maps/suite245-resume', '--self-test'])
	assert proof.exit_code == 0, proof.output
	os.write_file(out + 'classification-self-test.log', proof.output)!
}
