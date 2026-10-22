// SPDX-License-Identifier: GPL-2.0-or-later
module validationhost

import cachecli
import crypto.sha256
import gamehost
import hosttest
import json2
import os
import regex
import sourcecommand

const gpu_reference = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'

struct GpuDriver {
	root  string
	state string
mut:
	commands [][]string
}

fn allocation_calls(text string) []string {
	mut matches := []string{}
	mut position := 0
	for position < text.len {
		if !text[position].is_alnum() && text[position] != `_` {
			position++
			continue
		}
		begin := position
		for position < text.len && (text[position].is_alnum() || text[position] == `_`) {
			position++
		}
		name := text[begin..position]
		if name !in ['memdup', 'new_array_from_c_array', 'v_malloc', 'v_calloc', 'string__substr'] && !(name.len > 5 && name.ends_with('__str')) {
			continue
		}
		mut after := position
		for after < text.len && text[after].is_space() { after++ }
		if after < text.len && text[after] == `(` { matches << text[begin..after + 1] }
	}
	return matches
}

fn gpu_run(argv []string, environment map[string]string, output string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if output != '' {
		os.write_file(output + '.stdout', result.stdout)!
		os.write_file(output + '.stderr', result.stderr)!
	}
	if result.status != 0 {
		return error('Command failed (${result.status}): ' + argv.str() + '\n' + gamehost.decode_utf8((result.stdout + result.stderr).bytes()))
	}
	return result
}

fn (mut driver GpuDriver) command(argv []string) !sourcecommand.Output {
	driver.commands << argv
	return gpu_run(argv, os.environ(), '')!
}

pub fn exercise_gpu(root string, state string, headers string, compiler string) ! {
	base := hosttest.module_resolve(root)!
	destination := hosttest.module_resolve(state)!
	if destination == base || destination.starts_with(base + '/') {
		return error_with_code('Test artifacts and the frozen C reference must stay outside the checkout', 2)
	}
	gamehost.mkdir(destination)!
	mut driver := GpuDriver{ root: root, state: destination }
	mut references := map[string]json2.Any{}
	for name in ['gpu_present_egl.c', 'gpu_present.h'] {
		path := 'desktop/' + name
		data := gpu_run(['git', '-C', root, 'show', gpu_reference + ':' + path], os.environ(), '')!.stdout
		target := destination + '/' + name
		os.write_file(target, data)!
		blob := gpu_run(['git', '-C', root, 'rev-parse', gpu_reference + ':' + path], os.environ(), '')!.stdout.trim_space()
		references[path] = json2.Any({
			'commit':  json2.Any(gpu_reference)
			'blob':    json2.Any(blob)
			'sha256':  json2.Any(gamehost.digest(target)!)
			'bytes':   json2.Any(data.len)
			'recover': json2.Any(['git', 'show', gpu_reference + ':' + path].map(json2.Any(it)))
		})
	}
	core := destination + '/gpu-v.c'
	api := destination + '/gpu-api.h'
	fixture := destination + '/fixture-v.c'
	generator := root + '/build-support/compile-v-module'
	driver.command([generator, root + '/desktop/gpucore', core, '-d', 'gpu_presenter_enabled',
		'--header', api])!
	mut fixture_command := [generator, root + '/desktop/tools/tests/gpufixture', fixture]
	arm := os.user_os() == 'macos' && os.uname().machine == 'arm64'
	if os.user_os() == 'macos' { fixture_command << ['-d', 'fixture_native_display_int'] }
	if arm { fixture_command << ['-d', 'fixture_darwin_arm64'] }
	driver.command(fixture_command)!
	mut flags := [compiler, '-I', root + '/desktop', '-std=c11', '-O2', '-g', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-fsanitize-address-use-after-return=always',
		'-fno-omit-frame-pointer']
	if os.user_os() == 'macos' { flags << ['-arch', if arm { 'arm64' } else { 'x86_64' }] }
	if os.user_os() == 'macos' { flags << '-Wno-non-literal-null-conversion' }
	remaps := ['malloc', 'calloc', 'free', 'getenv', 'open', 'close', 'ioctl', 'stat', 'fstat'].map('-D' + it + '=gpf_' + it)
	driver.command([...flags, '-include', api, '-c', fixture, '-o', destination + '/fixture.o'])!
	mut objects := [destination + '/fixture.o']
	if arm {
		driver.command([compiler, '-c', root + '/desktop/tools/tests/gpufixture/ioctl_darwin_arm64.S',
			'-o', destination + '/ioctl.o'])!
		objects << destination + '/ioctl.o'
	}
	driver.command([...flags, '-idirafter', headers, ...remaps, '-DVINIX_GPU_PRESENTER_EXTERNAL',
		'-c', destination + '/gpu_present_egl.c', '-o', destination + '/gpu-c.o'])!
	driver.command([...flags, '-idirafter', headers, ...remaps, '-c', core, '-o',
		destination + '/gpu-v.o'])!
	mut environment := os.environ()
	leak_detection := if os.user_os() == 'macos' { 0 } else { 1 }
	environment['ASAN_OPTIONS'] = 'detect_leaks=${leak_detection}:halt_on_error=1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	mut outputs := map[string]sourcecommand.Output{}
	for variant in ['c', 'v'] {
		executable := destination + '/gpu-' + variant
		driver.command([...flags, ...objects, destination + '/gpu-' + variant + '.o', '-o', executable])!
		outputs[variant] = gpu_run([executable], environment, destination + '/run-' + variant)!
		if !outputs[variant].stdout.contains('GPU FIXTURE PASS 67 0\n') {
			return error('Fixture did not complete for ' + variant)
		}
	}
	for stream in ['stdout', 'stderr'] {
		before := if stream == 'stdout' { outputs['c'].stdout } else { outputs['c'].stderr }
		after := if stream == 'stdout' { outputs['v'].stdout } else { outputs['v'].stderr }
		if before != after {
			message := 'Presenter ' + stream + ' differs; compare ' + destination + '/run-c.' + stream + ' and run-v.' + stream
			os.write_file(destination + '/difference-' + stream + '.log', message + '\n')!
			return error(message)
		}
	}
	generated := os.read_file(core)!
	implicit := allocation_calls(generated)
	if implicit.len > 0 {
		return error('Implicit allocator or formatting call in presenter: ' + implicit.str())
	}
	mut stack := map[string]json2.Any{}
	for name, expression in {
		'config_attributes':     r'i32 config_attributes\[13\]'
		'surface_attributes':    r'i32 surface_attributes\[5\]'
		'context_attributes':    r'i32 context_attributes\[3\]'
		'retained_vertices':     r'float gpucore__presenter_vertices\[16\]'
		'shader_source_pointer': r'glShaderSource\(shader, 1, \(void\*\)\(&source\), NULL\)'
	} {
		mut pattern := regex.regex_opt(expression)!
		matches := pattern.find_all_str(generated)
		if matches.len == 0 { return error('Missing stack lifetime evidence: ' + name) }
		stack[name] = json2.Any(matches[0])
	}
	undefined := gpu_run(['nm', '-u', destination + '/gpu-v.o'], os.environ(), '')!.stdout
	os.write_file(destination + '/gpu-v-undefined.log', undefined)!
	cases := outputs['v'].stdout.count('CASE ')
	first_frames := outputs['v'].stderr.count('first frame begin')
	if cases != 67 || first_frames != 41 {
		return error('All cases must complete and each valid presenter must log its first frame once')
	}
	mut presenter_sources := map[string]json2.Any{}
	mut fixture_sources := map[string]json2.Any{}
	for path in gamehost.files(root + '/desktop/gpucore')! {
		if os.is_file(path) && (path.ends_with('.v') || path.ends_with('.h')) {
			presenter_sources[path[root.len + 1..]] = json2.Any(gamehost.digest(path)!)
		}
	}
	presenter_sources['desktop/gpu_egl_abi.h'] = json2.Any(gamehost.digest(root + '/desktop/gpu_egl_abi.h')!)
	for name in os.ls(root + '/desktop/tools/tests/gpufixture')! {
		path := root + '/desktop/tools/tests/gpufixture/' + name
		if os.is_file(path) {
			fixture_sources[path[root.len + 1..]] = json2.Any(gamehost.digest(path)!)
		}
	}
	compiler_version := gpu_run([compiler, '--version'], os.environ(), '')!.stdout.split_into_lines()[0]
	report := json2.Any({
		'reference':                 json2.Any(references)
		'presenter_sources':         json2.Any(presenter_sources)
		'fixture_sources':           json2.Any(fixture_sources)
		'compiler':                  json2.Any(compiler_version)
		'commands':                  json2.Any(driver.commands.map(json2.Any(it.map(json2.Any(it)))))
		'sanitizers':                json2.Any(['address', 'undefined'].map(json2.Any(it)))
		'use_after_return':          json2.Any('always')
		'lsan_enabled':              json2.Any(leak_detection != 0)
		'cases':                     json2.Any(cases)
		'first_frame_logs':          json2.Any(first_frames)
		'exact_stdout_sha256':       json2.Any(sha256.hexhash(outputs['v'].stdout))
		'exact_stderr_sha256':       json2.Any(sha256.hexhash(outputs['v'].stderr))
		'stack_evidence':            json2.Any(stack)
		'implicit_allocation_calls': json2.Any(implicit.map(json2.Any(it)))
		'result':                    json2.Any('PASS')
	})
	os.write_file(destination + '/validation.json', json2.encode(report, prettify: true) + '\n')!
	println('GPU presenter: ${cases} cases, exact C/V calls and pixels, ASan/UBSan PASS\nEvidence: ' + destination + '/validation.json')
}

pub fn gpu_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--state-dir', '--headers', '--cc'], [], [], 0, 0, 'Compare the V GPU presenter with its immutable C reference under sanitizers.\nUsage: test-gpu-present [--state-dir DIR --headers DIR --cc COMPILER]') or { return error_with_code(err.msg(), 2) }
	headers := hosttest.module_resolve(args.value('--headers', root + '/build-aarch64-userland/staging/usr/include'))!
	for relative in ['EGL/egl.h', 'EGL/eglext.h', 'GLES2/gl2.h'] {
		if !os.is_file(headers + '/' + relative) {
			return error_with_code('Missing upstream header ' + headers + '/' + relative, 2)
		}
	}
	temporary := '--state-dir' !in args.options
	state := if temporary {
		sourcecommand.temporary('vinix-gpu-fixture-')!
	} else {
		hosttest.module_resolve(args.value('--state-dir', ''))!
	}
	defer { if temporary { gamehost.remove(state) or {} } }
	exercise_gpu(root, state, headers, args.value('--cc', gamehost.env('CC', 'clang')))!
	return 0
}
