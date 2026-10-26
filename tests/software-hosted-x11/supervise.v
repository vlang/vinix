module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const source_root = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree'
const suite = source_root + '/tests/software-hosted-x11'
const supplement = '/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'

fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn bindings() !map[string]string {
	mut expected := {
		state + '/run-native06.v': '2161a5cfc3c936f30372cb65557a1c4cd1542317be338abbafe05c902fb8fa7d'
		state + '/run-native06': '924ee617447341825754ca01b9f7580c7e5e5c50f85eb1569aa70e633820ee68'
		state + '/run-evidence06.v': 'e6a4b84faccddf673a79a89905b80ca0c837af9cf6058bb23f1a775bd6d8c5d9'
		state + '/run-evidence06': 'b419dea8ac587dd974728b781e09f9147f484b80d276024eb6077835fe4a00f1'
		state + '/tools-06/check': '204c34fcd734af70e818fd578f19222859a671de00dddece4da154231b38fb77'
		state + '/tools-06/retain': '8c33a98130f2d8eb7799de3641760690cfe03f3b41badf556f90bf91c42a7be7'
		state + '/tools-06/evidence-check': 'b04fafb039b5818869b970cdc1c9f03a4b4ccf04e7baa4006cac0b12792d7c33'
		state + '/host-build-06/pins.json': '14f9e6296142c0fb636938049d1d46cd73d977295be98ea6b6cd1a7765635a38'
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		'/opt/homebrew/opt/llvm/bin/clang': '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		'/opt/homebrew/opt/llvm/bin/llvm-readelf': '9ff1c0f23cd0809ff80e33cdf2ccbf11868027977f3b574d0388c3e2e8618a3c'
		'/opt/homebrew/bin/qemu-system-x86_64': '25afcb2986e4a0f2c567de17273f55de3c99792b78a07c99e923bb62024c088f'
		'/opt/homebrew/bin/qemu-system-aarch64': '45d74da57beb9be259ca3d6996e5c70d4ab14326ea59c3db3e80308859d91a3e'
		'/bin/df': 'f57b43da7cc2f701db5ebad1b78ae9a30f10f9a102b2a83b0707031e69367e8a'
		'/bin/cp': '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
		'/usr/bin/tar': '9ab7f0793033dc9dc4809d83d695118801bd687cbacda59a0cbbf151ba25dc2b'
		'/opt/homebrew/bin/ld.lld': '745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b'
		'/opt/homebrew/bin/xorriso': 'd217ca8e759699dcaf36953822bd508f13587c57a890d2c1a71b19f6d0e8da86'
		'/opt/homebrew/bin/mformat': 'e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6'
		'/opt/homebrew/bin/mmd': 'e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6'
		'/opt/homebrew/bin/mcopy': 'e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6'
		suite + '/check.v': '7690dd77af1f8e9abd051d1cb79823a2a880bb2940f44dc1c1a3cea708d2b37d'
		suite + '/retain.v': '9a8d5aa7eb271a0818a9fe0c75bf3ace0a00caad3e5fc4d27fcce0732195a3ca'
		suite + '/evidence-check.v': 'd2d95972e9ea71c0421769a32a6d277f3baa83e9312dbb4ff91872e8c52dd274'
	}
	for path, data in {
		suite + '/supervise.v': $embed_file('supervise.v').to_string()
		suite + '/nativeguard/guard.v': $embed_file('nativeguard/guard.v').to_string()
		suite + '/diagnostics/recoveryguard/recoveryguard.v': $embed_file('diagnostics/recoveryguard/recoveryguard.v').to_string()
		source_root + '/tests/hardware-platform/hwhost/process.v': $embed_file('../hardware-platform/hwhost/process.v').to_string()
		source_root + '/tests/hardware-platform/hwhost/host.v': $embed_file('../hardware-platform/hwhost/host.v').to_string()
		source_root + '/tests/hardware-platform/hwhost/boot.v': $embed_file('../hardware-platform/hwhost/boot.v').to_string()
		source_root + '/tests/hardware-platform/plainiso/iso.v': $embed_file('../hardware-platform/plainiso/iso.v').to_string()
		os.dir(compiler) + '/vlib/os/process_nix.c.v': $embed_file('/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/vlib/os/process_nix.c.v').to_string()
		os.dir(compiler) + '/vlib/os/execute_capture_nix.h': $embed_file('/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/vlib/os/execute_capture_nix.h').to_string()
	} { expected[path] = sha256.hexhash(data) }
	for path, wanted in expected { if sha(path)! != wanted { return error('fixed inherited-group profile changed: ' + path) } }
	expected[os.executable()] = sha(os.executable())!
	return expected
}

fn run() ! {
	$if prod {} $else { return error('compile supervisor with -prod') }
	if os.args.len != 2 || os.args[1] !in ['--native-x86_64', '--native-aarch64', '--controls-x86_64', '--controls-aarch64'] {
		return error('requires one exact native06 architecture/mode; arbitrary commands refused')
	}
	pins := bindings()!
	controls := os.args[1].starts_with('--controls-')
	arch := os.args[1].all_after(if controls { '--controls-' } else { '--native-' })
	native := state + '/native-' + arch + '-06'
	output := if controls { state + '/controls-' + arch + '-06' } else { native }
	guard := state + '/native06-supervision-' + arch + if controls { '-controls' } else { '-native' }
	mut paths := [output, guard]
	for suffix in ['.argv.json', '.environment.json', '.runner.json', '.controller.log', '.controller-exit.json', '.log', '.exit.json'] {
		paths << output + suffix
	}
	for path in paths { if os.exists(path) || os.is_link(path) { return error('requires completely new output scope: ' + path) } }
	if controls {
		// Per-architecture cap includes the original native evidence retained
		// beside the controls, as well as both supervisors' observations.
		paths << native
		paths << state + '/native06-supervision-' + arch + '-native'
		paths << state + '/native06-supervision-' + arch + '-native.admission-df.log'
		paths << state + '/native06-supervision-' + arch + '-native.admission-df.log.cleanup.json'
		paths << state + '/native06-supervision-' + arch + '-native.admission-df.log.barrier.json'
		paths << state + '/native06-supervision-' + arch + '-native.admission-df.log.barrier-cleanup.json'
		for suffix in ['.argv.json', '.environment.json', '.runner.json', '.controller.log', '.controller-exit.json'] { paths << native + suffix }
	}
	// Frozen foreground tools inherit only this environment. The wrappers add
	// their exact VINIX_ROOT/V/Limine values; temporary writes stay in the cap.
	for name, _ in os.environ() { os.unsetenv(name) }
	environment := {
		'HOME': '/Users/alex'
		'USER': 'alex'
		'LOGNAME': 'alex'
		'LANG': 'en_US.UTF-8'
		'TERM': 'dumb'
		'TMPDIR': guard + '/scratch'
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
		'CLANG': '/opt/homebrew/opt/llvm/bin/clang'
		'READELF': '/opt/homebrew/opt/llvm/bin/llvm-readelf'
		'VINIX_QEMU_X86_64': '/opt/homebrew/bin/qemu-system-x86_64'
		'VINIX_QEMU_AARCH64': '/opt/homebrew/bin/qemu-system-aarch64'
	}
	for name, value in environment { os.setenv(name, value, true) }
	for name, expected_path in {'df': '/bin/df', 'cp': '/bin/cp', 'tar': '/usr/bin/tar',
		'ld.lld': '/opt/homebrew/bin/ld.lld', 'xorriso': '/opt/homebrew/bin/xorriso',
		'mformat': '/opt/homebrew/bin/mformat', 'mmd': '/opt/homebrew/bin/mmd', 'mcopy': '/opt/homebrew/bin/mcopy'} {
		if os.find_abs_path_of_executable(name)! != expected_path { return error('fixed foreground tool path differs: ' + name) }
	}
	args := if controls { [state + '/run-evidence06', native, output] }
		else { [state + '/run-native06', arch, supplement + '/restored-stage-' + arch + '/root', output] }
	// Keep final source/result/df receipts inside the per-architecture1GiB cap.
	namespace_cap := u64(1) << 30
	receipt_reserve := u64(8) << 20
	limits := nativeguard.Limits{start_bytes: u64(2202010) * 1024, floor_bytes: u64(1) << 30,
		cap_bytes: namespace_cap - receipt_reserve, wall_ms: if controls { 20 * 60 * 1000 } else { 30 * 60 * 1000 }}
	// Admission before creating the guard directory uses the separately cleaned
	// helper; its log and typed cleanup remain as a sibling inside the cap.
	admission_log := guard + '.admission-df.log'
	if os.exists(admission_log) || os.is_link(admission_log) { return error('admission log already exists') }
	for suffix in ['', '.cleanup.json', '.barrier.json', '.barrier-cleanup.json'] {
		if os.exists(admission_log + suffix) || os.is_link(admission_log + suffix) { return error('admission sibling already exists') }
		paths << admission_log + suffix
	}
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(state, admission_log)!
	if admission.available < limits.start_bytes { return error('fresh actual df below2.1GiB admission') }
	os.mkdir(guard)!
	os.mkdir(guard + '/scratch')!
	os.write_file(guard + '/admission.json', json2.encode(admission))!
	os.write_file(guard + '/argv.json', json2.encode(args))!
	os.write_file(guard + '/environment.json', json2.encode(environment))!
	os.write_file(guard + '/pins-before.json', json2.encode(pins))!
	result := nativeguard.supervise(args, source_root, state, paths, guard + '/output.log', guard + '/df', limits) or {
		os.write_file(guard + '/supervisor-error.json', json2.encode({'error': recoveryguard.bounded_message(err.msg())}))!
		return err
	}
	mut changed := []string{}
	for path, wanted in pins { if (sha(path) or { '' }) != wanted { changed << path } }
	result_text := json2.encode(result)
	pins_text := json2.encode({'changed': json2.encode(changed), 'pins': json2.encode(pins)})
	if u64(result_text.len) > receipt_reserve - (u64(256) << 10) || pins_text.len > 65536 {
		return error('final receipt exceeds reserved namespace budget')
	}
	os.write_file(guard + '/result.json', result_text)!
	os.write_file(guard + '/pins-after.json', pins_text)!
	if result.reason != '' || result.cleanup.exit_code != 0 || changed.len != 0 {
		return error('native06 supervised attempt refused; complete failed scope retained')
	}
	final_df := nativeguard.actual_df(state, guard + '/receipt-df.log')!
	final_allocation := nativeguard.allocated(paths, os.lstat(state)!.dev)!
	os.write_file(guard + '/final-budget.json', json2.encode({'allocated_bytes_before_final_receipt': final_allocation.str(),
		'actual_df_available_bytes': final_df.available.str(), 'namespace_cap_bytes': namespace_cap.str()}))!
	if final_df.available < limits.floor_bytes || nativeguard.allocated(paths, os.lstat(state)!.dev)! > namespace_cap {
		return error('final receipts exceed namespace cap or shared df floor')
	}
	println('PASS bounded native06 host supervisor: ' + os.args[1])
}

fn main() { run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }
