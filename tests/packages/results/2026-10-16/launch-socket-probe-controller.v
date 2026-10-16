module main
import hwhost
import os
fn main() {
	status := hwhost.run_suite(hwhost.Suite{ name: 'package-socket-probe', guest: 'build/package-socket-work/probe',
		scenarios: [hwhost.Scenario{ name: 'package-socket-probe', arches: ['aarch64', 'x86_64'],
			required: ['HWTEST START package-socket-probe', 'HWTEST PASS package-socket-probe'], ending: .poweroff, timeout: 300 }] }, os.args[1..], @FILE)
	exit(status)
}
