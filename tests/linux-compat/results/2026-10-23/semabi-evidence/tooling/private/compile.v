// Private probe and reference launcher compiler. Never builds kernels or guests.
import crypto.sha256
import json2
import os
import time

const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

struct CompileReceipt {
	architecture string
	context string = 'Private probe compile only; no semaphore kernel build or guest started'
	inputs map[string]string
	outputs map[string]string
	started string
	finished string
}

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }

fn execute(args []string, log string) ! {
	os.write_file(log + '.command.json', json2.encode(args, prettify: true) + '\n')!
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, output)!
	os.write_file(log + '.status', code.str() + '\n')!
	if code != 0 { return error('Command failed: ' + log + '\n' + output) }
}

fn main() {
	assert os.args.len == 3, 'Usage: compile arm|x86 FRESH_ATTEMPT_TAG'
	suffix := os.args[1]
	assert suffix in ['arm', 'x86']
	tag := os.args[2]
	assert tag.len > 0 && tag.bytes().all(it.is_alnum() || it in [`-`, `_`])
	state := area + '/states/compile-' + tag + '-' + suffix
	assert !os.exists(state), 'Refusing to overwrite a compile attempt'
	os.mkdir_all(state)!
	os.mkdir_all(area + '/tmp')!
	os.setenv('TMPDIR', area + '/tmp', true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	fixture := area + '/frozen-' + tag + '/semabifixture'
	serial := area + '/frozen-' + tag + '/serialcore'
	wrapper := area + '/frozen-' + tag + '/semabireferenceinit'
	if !os.exists(fixture) {
		os.mkdir_all(fixture)!
		os.mkdir_all(serial)!
		os.mkdir_all(wrapper)!
		for name in ['core.v'] {
			os.cp('/Users/alex/code/vinix/tests/linux-compat/semabifixture/' + name, fixture + '/' + name)!
		}
		os.cp(previous + '/frozen/serialcore/core.v', serial + '/core.v')!
		text := os.read_file(previous + '/reference-frozen/procnsreferenceinit/core.v')!
		os.write_file(wrapper + '/core.v', text.replace('procnsreferenceinit', 'semabireferenceinit').replace('PROCNS', 'SEMABI'))!
	}
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), compiler, previous + '/generate-module', previous + '/generate-module.v'] {
		inputs[path] = digest(path)
	}
	for dir in [fixture, serial, wrapper] {
		for name in os.ls(dir)! { inputs[dir + '/' + name] = digest(dir + '/' + name) }
	}
	cc := if suffix == 'arm' { os.find_abs_path_of_executable('clang')! } else { '/opt/homebrew/bin/x86_64-linux-musl-gcc' }
	inputs[cc] = digest(cc)
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	started := time.utc().str()
	mut flags := if suffix == 'arm' {
		[cc, '--gcc-install-dir=' + previous + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0',
			'--target=aarch64-linux-musl', '--sysroot=' + previous + '/sdk', '-static', '-pthread', '-O2',
			'-fno-stack-protector', '-Wall', '-Wextra', '-Werror']
	} else { [cc, '-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror'] }
	flags << ['-D_GNU_SOURCE', '-fno-strict-aliasing', '-I', fixture]
	for name, source in {'serial': serial, 'fixture': fixture, 'reference': wrapper} {
		execute([previous + '/generate-module', source, state + '/' + name + '.c', '--arch',
			if suffix == 'arm' { 'arm64' } else { 'amd64' }, '-d', 'nofloat'], state + '/generate-' + name + '.log')!
		mut command := flags.clone()
		command << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-c', state + '/' + name + '.c', '-o', state + '/' + name + '.o']
		execute(command, state + '/compile-' + name + '.log')!
	}
	for name, object in {'probe': 'fixture', 'reference-init': 'reference'} {
		mut command := []string{}
		for flag in flags { if suffix == 'arm' && flag == '-pthread' { continue }; command << flag }
		command << [state + '/serial.o', state + '/' + object + '.o']
		if suffix == 'arm' { command << ['-L' + previous + '/sdk/lib', '-fuse-ld=lld'] }
		command << ['-o', state + '/' + name]
		execute(command, state + '/link-' + name + '.log')!
	}
	for path, expected in inputs { assert digest(path) == expected, 'Compile input changed: ' + path }
	mut outputs := map[string]string{}
	for name in ['serial.c', 'serial.o', 'fixture.c', 'fixture.o', 'reference.c', 'reference.o', 'probe', 'reference-init'] {
		outputs[state + '/' + name] = digest(state + '/' + name)
	}
	os.write_file(state + '/receipt.json', json2.encode(CompileReceipt{
		architecture: suffix
		inputs: inputs
		outputs: outputs
		started: started
		finished: time.utc().str()
	}, prettify: true) + '\n')!
	os.write_file(state + '/status', '0\n')!
	println('Compile PASS: ' + state)
	println('probe SHA256 ' + outputs[state + '/probe'])
	println('reference-init SHA256 ' + outputs[state + '/reference-init'])
}
