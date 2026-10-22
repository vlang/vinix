import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const oldarea = '/Users/alex/.cache/vinix-linux-compat/procns-20261016'
const base = 'f3a29a7aa558d0325d5602f39f503d3449e5b56f'

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn git(path string, args []string) string {
	mut p := os.new_process('git')
	p.set_args(['-C', path, ...args])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp().trim_space()
	p.wait()
	assert p.code == 0, output
	p.close()
	return output
}

struct KernelInput {
	architecture string
	profile string
	kernel_path string
	kernel_sha256 string
	blob_path string
	blob_sha256 string
	build_log_path string
	build_log_sha256 string
	build_status_path string
	build_status_sha256 string
	build_status int
	build_phase string
	worktree_path string
	worktree_head string
}

struct Inputs {
	baseline_commit string
	base_path string
	base_sha256 string
	controller_path string
	controller_sha256 string
	audit_base_path string
	audit_base_head string
	audit_base_tracked_status string
	kernels map[string]KernelInput
}

fn main() {
	assert os.read_file(oldarea + '/base.txt')!.trim_space() == base
	audit := oldarea + '/audit-base'
	assert git(audit, ['rev-parse', 'HEAD']) == base
	assert git(audit, ['status', '--short', '--untracked-files=no']) == ''
	mut kernels := map[string]KernelInput{}
	for suffix in ['arm', 'x86'] {
		label := if suffix == 'arm' { 'before-arm-track-mp' } else { 'before-x86-track' }
		kernel := oldarea + '/' + label + '/kernel/bin/vinix'
		blob := oldarea + '/' + label + '/blob.c'
		log := oldarea + '/build-' + label + '.log'
		status := log + '.status'
		assert os.read_file(status)!.trim_space() == '0'
		tree := if suffix == 'arm' { audit } else { oldarea + '/kernel-x86' }
		assert git(tree, ['rev-parse', 'HEAD']) == base
		kernels[suffix] = KernelInput{
			architecture: if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
			profile: 'baseline-track'
			kernel_path: kernel
			kernel_sha256: digest(kernel)
			blob_path: blob
			blob_sha256: digest(blob)
			build_log_path: log
			build_log_sha256: digest(log)
			build_status_path: status
			build_status_sha256: digest(status)
			build_status: 0
			build_phase: if suffix == 'arm' { 'smpbase' } else { 'build x86 before track' }
			worktree_path: tree
			worktree_head: base
		}
	}
	os.write_file(area + '/baseline-inputs.json', json2.encode(Inputs{
		baseline_commit: base
		base_path: oldarea + '/base.txt'
		base_sha256: digest(oldarea + '/base.txt')
		controller_path: oldarea + '/manage.v'
		controller_sha256: digest(oldarea + '/manage.v')
		audit_base_path: audit
		audit_base_head: base
		audit_base_tracked_status: ''
		kernels: kernels
	}, prettify: true) + '\n')!
	println('Baseline input evidence: ' + area + '/baseline-inputs.json')
}
