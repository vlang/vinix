// SPDX-License-Identifier: GPL-2.0-or-later
module coreboot

import hosttest
import os

pub fn remove(path string) ! { hosttest.remove_work_dir(path)! }

pub fn translated(script string, root string, package_server string) !string {
	assignment := 'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"'
	package := 'python3 "$SCRIPT_DIR/tools/qemu-package-store.py"'
	venus := 'python3 "$SCRIPT_DIR/build-support/venus/prepare-qemu.py"'
	check := 'if ! command -v python3 >/dev/null 2>&1; then\n    echo "ERROR: python3 is required for QEMU package persistence" >&2\n    exit 1\nfi'
	for original in [assignment, package, venus, check] { if script.count(original) != 1 { return error('frozen boot adapter input differs') } }
	mut result := script.replace(assignment, 'SCRIPT_DIR=' + hosttest.shell_quote(root))
	result = result.replace(check, 'if [ ! -x ' + hosttest.shell_quote(package_server) + ' ]; then\n    echo "ERROR: native package server is missing" >&2\n    exit 1\nfi')
	result = result.replace(package, hosttest.shell_quote(package_server))
	result = result.replace(venus, hosttest.shell_quote(hosttest.root() + '/build-support/venus/prepare-qemu'))
	if result.contains('python3') { return error('frozen boot script still needs a native replacement') }
	return result
}

pub fn legacy(root string, package_server string) !(string, string) {
	if package_server == '' || !os.is_executable(package_server) { return error('native package server is missing') }
	data := os.read_file(root + '/run-aarch64.sh')!
	contents := translated(data, root, package_server)!
	work := hosttest.work_dir('', 'vinix-core-legacy')!
	path := work + '/run-aarch64.sh'
	os.write_file(path, contents) or { remove(work) or {}; return err }
	os.chmod(path, 0o755) or { remove(work) or {}; return err }
	return path, work
}
