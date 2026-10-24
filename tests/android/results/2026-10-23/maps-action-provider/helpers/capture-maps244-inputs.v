import os
import time

fn main() {
	b := 'build/android-maps/'
	out := 'tests/android/results/2026-10-23/maps-action-provider/'
	assert !os.exists(out + 'inputs.json')
	mut ready := false
	for _ in 0 .. 300 {
		if os.exists(b + 'attempt244/google-maps/qmp.sock') {
			ready = true
			break
		}
		time.sleep(2 * time.second)
	}
	assert ready, 'Maps244 runtime module did not reach QEMU launch'
	for action in ['inputs', 'validate'] {
		path := if action == 'inputs' { out + 'retain.v' } else { out + 'validate.v' }
		r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', 'run', path, 'inputs'])
		os.write_file(b + 'capture-maps244-' + action + '.log', r.output)!
		print(r.output)
		assert r.exit_code == 0, r.output
	}
}
