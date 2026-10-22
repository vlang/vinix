import os
import envhelper
import guesthost
import crypto.sha256
import json2

fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { return []u8{}.hex() }).hex() }

fn git_commit(path string) string {
	mut p := os.new_process('git')
	p.set_args(['-C', path, 'rev-parse', 'HEAD'])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp().trim_space()
	p.wait()
	code := p.code
	p.close()
	return if code == 0 { output } else { 'unavailable; kernel binary pinned by SHA256' }
}

fn kernel_commit(path string) !string {
	for suffix in ['arm', 'x86'] {
		if path == envhelper.area + '/' + suffix + '-track/kernel' || path == envhelper.area + '/' + suffix + '-prod/kernel' {
			flavor := if path.contains('-track/') { 'track' } else { 'prod' }
			assert os.read_file(envhelper.area + '/build-' + suffix + '-' + flavor + '.log.status')!.trim_space() == '0'
			commit := git_commit(envhelper.area + '/kernel-' + suffix)
			assert commit == 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
			assert os.read_file(envhelper.area + '/build.v')!.contains(commit)
			return commit
		}
	}
	return git_commit(path)
}

struct Receipt {
	architecture string
	profile string
	kernel_directory string
	kernel_commit string
	source_sha256 string
	init_sha256 string
	kernel_sha256 string
	input_kernel_sha256 string
	input_kernel_sha256_after string
	serial_sha256 string
	manifest_sha256 string
	runner_sha256 string
	prebuilt string
	exit_code int
	detail string
}

fn main() {
	if os.args.len < 5 || os.args.len > 7 {
		eprintln('Usage: qualify arm|x86 KERNEL_DIRECTORY PROFILE FRESH_STATE_TAG [PREBUILT_INIT] [TIMEOUT_SECONDS]')
		exit(2)
	}
	suffix := os.args[1]
	assert suffix in ['arm', 'x86']
	arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
	kernel := os.real_path(os.args[2])
	profile := os.args[3]
	tag := os.args[4]
	assert tag != '' && tag.bytes().all(it.is_alnum() || it in [`-`, `_`, `.`]) && tag !in ['.', '..']
	state := envhelper.area + '/states/' + tag
	assert !os.exists(state), 'State already exists: ' + state
	envhelper.configure()
	envhelper.dependencies()!
	manifest_path := envhelper.area + '/source-manifest2.json'
	manifest := json2.decode[map[string]string](os.read_file(manifest_path)!)!
	for path, expected in manifest { assert hash(path) == expected, 'Frozen source changed: ' + path }
	prebuilt := if os.args.len > 5 { os.args[5] } else { '' }
	timeout := if os.args.len > 6 { os.args[6].int() } else { 1200 }
	assert timeout > 0
	source := state + '/sources/procnsfixture/core.v'
	os.mkdir_all(os.dir(source))!
	os.cp_all(envhelper.area + '/frozen2/procnsfixture', os.dir(source), false)!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	input_sha := hash(kernel + '/bin/vinix')
	kernel_sha := hash(state + '/kernel/bin/vinix')
	assert input_sha == kernel_sha
	mut detail := ''
	result := guesthost.guest(source, prebuilt, state, state + '/kernel', arch, ['LINUX PROCNS: PASS'], ['LINUX PROCNS FAIL'], false, true, timeout) or { detail = err.msg(); 2 }
	for path, expected in manifest {
		if hash(path) != expected { detail += '\nFrozen source changed while running: ' + path }
	}
	final_result := if detail == '' { result } else { 2 }
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		architecture: arch
		profile: profile
		kernel_directory: kernel
		kernel_commit: kernel_commit(kernel)!
		source_sha256: hash(source)
		init_sha256: hash(state + '/init')
		kernel_sha256: kernel_sha
		input_kernel_sha256: input_sha
		input_kernel_sha256_after: hash(kernel + '/bin/vinix')
		serial_sha256: hash(state + '/serial.log')
		manifest_sha256: hash(manifest_path)
		runner_sha256: hash(os.executable())
		prebuilt: prebuilt
		exit_code: final_result
		detail: detail
	}, prettify: true) + '\n')!
	println('Qualification result ' + final_result.str() + ': ' + state + '/receipt.json')
	exit(final_result)
}
