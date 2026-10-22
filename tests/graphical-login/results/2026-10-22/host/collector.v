import crypto.sha256
import json2
import os

struct HostReceipt {
	scope string
	greeter string
	manager string
	channel string
	proof string
	artifacts map[string]string
	source_sha256 map[string]string
	compiler string
}

fn digest(path string) !string {
	data := os.read_bytes(path)!
	return sha256.hexhash(unsafe { tos(data.data, data.len) })
}

fn main() {
	shared := '/Users/alex/code/vinix'
	root := shared + '/build/graphical-login-worktree'
	out := root + '/tests/graphical-login/results/2026-10-22'
	for arch, short in {'aarch64': 'arm', 'x86_64': 'x86'} {
		os.cp(shared + '/build/graphical-login-evidence-' + short + '-10/controls.json', out + '/' + arch + '.controls.json')!
	}
	host := out + '/host'
	if os.exists(host) { panic('host record already exists') }
	os.mkdir(host, mode: 0o700)!
	mut artifacts := map[string]string{}
	for log in ['graphical-login-greeter-host-registration.log', 'graphical-login-manager-final.log',
		'graphical-login-manager-negative.log', 'graphical-login-channel-host-3.log', 'graphical-login-proof-test.log',
		'graphical-login-desktop-aarch64-5.log', 'graphical-login-desktop-x86_64-5.log'] {
		os.cp(shared + '/build/' + log, host + '/' + log)!
		artifacts[log] = digest(host + '/' + log)!
	}
	mut sources := map[string]string{}
	for path in ['desktop/tools/test-greeter.v', 'desktop/tools/tests/greeter_test.v',
		'desktop/greeter.v', 'desktop/login_session.v', 'desktop/input.v', 'desktop/keyboard_events.v',
		'tools/accounts/sessioncore/manager.v', 'tools/accounts/sessioncore/secret.c.v',
		'tools/accounts/loginchannel/channel.v', 'tools/accounts/loginchannel/channel_test.v',
		'tests/graphical-login/secret-check.v', 'tests/graphical-login/secret-fixture.v.txt',
		'tests/graphical-login/loginproof/proof.v', 'tests/graphical-login/loginproof/proof_test.v'] {
		sources[path] = digest(root + '/' + path)!
	}
	os.cp(@FILE, host + '/collector.v')!
	artifacts['collector.v'] = digest(host + '/collector.v')!
	os.write_file(host + '/checks.json', json2.encode(HostReceipt{
		scope: 'Logs from completed host commands with observed exit 0, collected after native admission. Generated native C/ELF and full captured inventories are in each architecture receipt; these host logs do not independently prove compiler provenance.'
		greeter: 'Actual UI/state tests with ASan/UBSan, bounded masked fields, deletion wipe, failures and compact scenes; desktop/tools/test-greeter.v with VINIX_GREETER_SANITIZE=1.'
		manager: 'Actual extracted production preparation/attendance, fork snapshot, parent wipe before long attendance, real blocking child reap; secret-check.v --sanitize. Old WNOHANG replacement fails the assertion and is accepted only as a negative control.'
		channel: 'Host root-peer/refusal and repeated inherited lookup tracked-allocation checks; native channel receipts independently cover actual pre-drop socketpair credentials on both target kernels.'
		proof: 'Known SHA256 vectors/chunked input, unsafe path refusal, exact ordered serial success/missing/duplicate/reorder/panic tests.'
		artifacts: artifacts
		source_sha256: sources
		compiler: digest(shared + '/build/package-https-runtime-work/toolchain/v')!
	}))!
	// Only obsolete prototypes owned by this agent. Final native/desktop/account
	// and channel inputs, and all other sessions' evidence, remain available.
	for name in ['graphical-login-desktop-aarch64-4', 'graphical-login-desktop-x86_64-4',
		'graphical-login-native-arm-9', 'graphical-login-channel-arm-3', 'graphical-login-channel-x86-3'] {
		os.rmdir_all(shared + '/build/' + name)!
		println('Removed owned obsolete prototype: ' + name)
	}
}
