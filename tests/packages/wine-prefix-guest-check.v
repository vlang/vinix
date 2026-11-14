// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import plainiso

fn run() ! {
	if os.args.len != 6 { return error('usage: CHECK NEW_WORK ARCH KERNEL COMPILED_CLI COMPILED_GUEST') }
	work := os.abs_path(os.args[1])
	arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh work directory and supported architecture required') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	host := hwhost.find_host(root, arch, '')!
	os.mkdir_all(work + '/extras/usr/bin')!
	os.cp(os.args[4], work + '/extras/usr/bin/vinix-package')!
	os.chmod(work + '/extras/usr/bin/vinix-package', 0o755)!
	boot_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'wine-prefix-cli', arches: [arch], ending: .running,
		required: ['WINE PREFIX REFUSALS PASS competing managed launch; personal DLL preserved; retry',
			'WINE PREFIX UPGRADE PASS signed generation change; review; retarget refusal; old links and private data preserved',
			'WINE PREFIX MIGRATION PASS signed runtime retarget; added link; repeat; public review; private data',
			'WINE PREFIX OWNER DEATH PASS partial retarget; live lease and guard; SIGKILL release; admitted resume',
			'WINE PREFIX MIGRATE CLI PASS public writer SIGKILL; public resume; repeat; admitted verification',
			'WINE PREFIX STAGE CLI PASS personal file; directory; foreign link preserved; authenticated stage resumed first',
			'WINE PREFIX ROLLBACK REFUSAL PASS removed builtin; all public commands; bindings and private data preserved',
			'WINE PREFIX ROLLBACK RECOVERY PASS explicit obsolete-link cleanup; restored payload; public migration; repeat',
			'WINE PREFIX CLI PASS ordinary signed installed review; exclusive addition; repeat; private data', 'HWTEST PASS wine-prefix-cli fixture'],
		forbidden: ['HWTEST FAIL', 'Kernel panic']}, hwhost.Run{kernel: os.args[3], guest: os.args[5],
		extras: work + '/extras', state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	if !outcome.passed || outcome.interrupted { return error('prefix CLI guest failed: ' + outcome.reason) }
	println('Wine installed-prefix CLI guest PASS ' + arch)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
