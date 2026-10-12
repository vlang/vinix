// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import generators
import guesthost
import hosttest
import json2
import os
import sourcecommand
import time

pub struct MacOptions {
pub:
	host       string = '127.0.0.1'
	port       int
	user       string
	identity   string
	gcc        string = '/opt/local/bin/gcc-mp-14'
	guest_sdk  string
	host_sdk   string
	vm_config  string
	state      string
	iterations int = 200000
	samples    int = 7
	timeout    int = 3600
}

pub fn remote_prefix(remote string, gcc string, source_hash string, header_hash string) string {
	return 'set -e\ncd ' + hosttest.shell_quote(remote) + '\ntest "$(/usr/bin/shasum -a 256 bench.c | /usr/bin/awk \'{print $1}\')" = ' + source_hash + '\ntest "$(/usr/bin/shasum -a 256 bench-native-abi.h | /usr/bin/awk \'{print $1}\')" = ' + header_hash + '\necho ALLOC-COMPILE-BEGIN\n' + hosttest.shell_quote(gcc) + ' --version | head -n 1\nif ' + hosttest.shell_quote(gcc) + ' -dM -E - </dev/null | grep __clang__; then\n    echo ALLOC-FAIL stage=compiler-is-clang\n    exit 1\nfi\n'
}

pub fn remote_cleanup(remote string) string {
	return 'cd ' + hosttest.shell_quote(remote) + ' || exit 0\ntest -f run.pid || exit 0\nbench_pid=$(cat run.pid)\ncase "$bench_pid" in \'\'|*[!0-9]*) exit 1;; esac\ncase "$(ps -p "$bench_pid" -o command=)" in\n    ' + hosttest.shell_quote(remote + '/alloc-bench') + '\' \'*) kill "$bench_pid";;\nesac\n'
}

pub fn run_macos(options MacOptions) ! {
	mut config := hosttest.decode_json(os.read_file(options.vm_config)!)!.as_map().clone()
	for key in ['qemu_version', 'machine', 'accelerator', 'cpu', 'smp', 'memory_mb'] {
		if key !in config { return InputError{'VM configuration lacks ' + key} }
	}
	work := hosttest.work_dir(if options.state == '' { '.' } else { options.state }, 'vinix-macos-alloc-')!
	source := work + '/bench.c'
	generation := generators.generate_bench(source, 'amd64')!
	source_hash := generation['source_sha256']!.str()
	header_hash := generation['native_header_sha256']!.str()
	for key, value in {
		'source_sha256':        json2.Any(source_hash)
		'compile_flags':        json2.Any(benchmark_flags.map(json2.Any(it)))
		'iterations':           json2.Any(options.iterations)
		'samples':              json2.Any(options.samples)
		'v_generation':         json2.Any(generation)
		'native_header_sha256': json2.Any(header_hash)
	} {
		config[key] = value
	}
	config['build_method'] = if options.guest_sdk != '' {
		'guest GCC C-to-assembly; host Apple assembler/linker'
	} else {
		'guest GCC driver'
	}
	write_json(work + '/config.json', config)!
	destination := options.user + '@' + options.host
	identity := resolve(options.identity)!
	host_key_options := ['-o', 'UserKnownHostsFile=' + work + '/known_hosts', '-o',
		'StrictHostKeyChecking=accept-new']
	ssh := ['ssh', '-i', identity, '-p', options.port.str(), '-o', 'BatchMode=yes', '-o',
		'ConnectTimeout=15', ...host_key_options, destination]
	remote := '/tmp/vinix-alloc-bench-' + time.now().unix_nano().str()
	result := capture([...ssh, 'mkdir -m 700 ' + hosttest.shell_quote(remote)], os.environ(), 30)!
	if result.status != 0 {
		return error('remote directory creation failed: ' + result.stdout + result.stderr)
	}
	print(result.stdout)
	eprint(result.stderr)
	transfer := ['scp', '-i', identity, '-P', options.port.str(), '-o', 'BatchMode=yes',
		...host_key_options]
	copied := capture([...transfer, source, work + '/bench-native-abi.h',
		destination + ':' + remote + '/'], os.environ(), 60)!
	if copied.status != 0 {
		return error('remote source transfer failed: ' + copied.stdout + copied.stderr)
	}
	print(copied.stdout)
	eprint(copied.stderr)
	gcc := hosttest.shell_quote(options.gcc)
	prefix := remote_prefix(remote, options.gcc, source_hash, header_hash)
	run_command := 'echo $$ > run.pid\nexec ' + hosttest.shell_quote(remote + '/alloc-bench') + ' --label macos --iterations ' + options.iterations.str() + ' --samples ' + options.samples.str()
	log := work + '/serial.log'
	os.write_file(log, '')!
	mut command := ''
	if options.guest_sdk != '' {
		includes_result := capture([...ssh, gcc + ' -print-file-name=include'], os.environ(), 30)!
		if includes_result.status != 0 {
			return error('remote intrinsic header lookup failed: ' + includes_result.stdout + includes_result.stderr)
		}
		eprint(includes_result.stderr)
		includes := includes_result.stdout.trim_space()
		codegen := gcc + ' ' + hosttest.shell_join(benchmark_flags) + ' -mmacosx-version-min=10.15 -isysroot ' + hosttest.shell_quote(options.guest_sdk) + ' -nostdinc -isystem ' + hosttest.shell_quote(includes) + ' -isystem ' + hosttest.shell_quote(options.guest_sdk + '/usr/include') + ' -I . -S bench.c -o bench.s'
		config['guest_compile_command'] = codegen
		logged([...ssh, prefix + codegen], os.environ(), log, true, '', options.timeout)!
		assembly := capture([...transfer, destination + ':' + remote + '/bench.s', work + '/bench.s'], os.environ(), 60)!
		if assembly.status != 0 {
			return error('remote assembly transfer failed: ' + assembly.stdout + assembly.stderr)
		}
		print(assembly.stdout)
		eprint(assembly.stderr)
		link := ['xcrun', 'clang', '-target', 'x86_64-apple-macos10.15', '-isysroot',
			resolve(options.host_sdk)!, work + '/bench.s', '-o', work + '/alloc-bench']
		config['host_link_command'] = link.map(json2.Any(it))
		logged(link, os.environ(), log, true, '', 60)!
		binary := capture([...transfer, work + '/alloc-bench',
			destination + ':' + remote + '/alloc-bench'], os.environ(), 60)!
		if binary.status != 0 {
			return error('remote executable transfer failed: ' + binary.stdout + binary.stderr)
		}
		print(binary.stdout)
		eprint(binary.stderr)
		command = 'cd ' + hosttest.shell_quote(remote) + ' && chmod 755 alloc-bench && echo ALLOC-COMPILE-DONE && ' + run_command
	} else {
		codegen := gcc + ' ' + hosttest.shell_join(benchmark_flags) + ' -I . bench.c -o alloc-bench'
		config['guest_compile_command'] = codegen
		command = prefix + codegen + '\necho ALLOC-COMPILE-DONE\n' + run_command
	}
	write_json(work + '/config.json', config)!
	logged([...ssh, command], os.environ(), log, true, '', options.timeout) or {
		failure := err
		// Keep pending SIGINT/SIGTERM while allowing the bounded final SSH
		// exchange to retire only this unique remote executable's recorded PID.
		cleanup := sourcecommand.capture([...ssh, remote_cleanup(remote)], os.environ(), 30, 1024 * 1024, unsafe { nil }) or {
			eprintln('Remote cleanup failed; check ' + remote + '/run.pid before retrying.')
			return failure
		}
		if cleanup.status != 0 {
			eprintln('Remote cleanup failed; check ' + remote + '/run.pid before retrying.')
		}
		return failure
	}
	cachecli.checkpoint()!
	output := guesthost.replacement_text(os.read_bytes(log)!).replace('\r\n', '\n').replace('\r', '\n')
	if !output.contains('ALLOC-DONE') || output.contains('ALLOC-ERROR') || output.contains('ALLOC-FAIL') {
		return error('benchmark incomplete; see ' + log)
	}
	print(output)
}
