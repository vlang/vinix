// SPDX-License-Identifier: GPL-2.0-or-later
// Host arithmetic/ownership and real PE receipt qualification; no GUI execution.
module main

import crypto.sha256
import json2
import os

struct Input {
	kind string
	target string
	sha256 string
}

struct Run {
	name string
	compile_exit int
	run_exit int
	expected string
}

struct Receipt {
	format int = 1
	scope string = 'host calculator arithmetic and fixed-buffer V ownership; real AMD64 PE32+ build/receipt admission; no Windows/Wine GUI execution, publisher trust or hermetic build claim'
	inputs map[string]Input
	outputs map[string]string
	runs []Run
	pe_directory string
	pe_proof_sha256 string
	pe_executable_sha256 string
	pe_generated_c_sha256 string
}

struct Summary {
	format int = 1
	scope string = 'host tests and local real PE receipt admission only; graphical window/input/close under Wine remain unqualified'
	proof_sha256 string
	input_inventory_sha256 string
	input_count int
	sources map[string]string
	tools map[string]string
	outputs map[string]string
	runs []Run
	pe_directory string
	pe_proof_sha256 string
	pe_executable_sha256 string
	pe_generated_c_sha256 string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: 32}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	for {
		n := file.read(mut buffer) or {
			if file.eof() { unsafe { err.free() }; break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn inventory(path string, selected bool, depth int, mut inputs map[string]Input) ! {
	if depth > 256 || inputs.len > 100000 { return error('calculator host inventory exceeds its bound') }
	if os.is_link(path) {
		resolved := os.real_path(path)
		defer { unsafe { resolved.free() } }
		inputs[path] = Input{kind: 'symlink', target: os.readlink(path)!, sha256: if os.is_file(resolved) { digest(resolved)! } else { '' }}
	} else if os.is_dir(path) {
		inputs[path] = Input{kind: 'directory'}
		names := os.ls(path)!
		defer { unsafe { names.free() } }
		for name in names { inventory(path + '/' + name, selected, depth + 1, mut inputs)! }
	} else if !selected || path.ends_with('.v') {
		if !os.is_file(path) { return error('calculator host input is not an ordinary file') }
		inputs[path] = Input{kind: 'file', sha256: digest(path)!}
	}
}

fn capture(v string, cc string, root string, pe string, producer string) !map[string]Input {
	mut inputs := map[string]Input{}
	for module_name in ['wineadapter', 'pkgprotocol', 'appsdk']! {
		inventory(root + '/tools/packages/' + module_name, true, 0, mut inputs)!
	}
	for name in ['vlib', 'thirdparty']! { inventory(os.dir(v) + '/' + name, false, 0, mut inputs)! }
	for path in [v, cc, '/usr/bin/ld', os.executable(), @FILE, producer,
		root + '/tests/packages/wine-calculator/program.v',
		root + '/tests/packages/wine-calculator/program_test.v',
		root + '/tests/packages/wine-calculator/v.mod',
		root + '/desktop/tools/tests/heap_tracker.h', pe + '/proof.json'] {
		inputs[path] = Input{kind: 'file', sha256: digest(path)!}
	}
	return inputs
}

fn same(before map[string]Input, after map[string]Input) ! {
	if before.len != after.len { return error('calculator host input set changed') }
	for path, value in before {
		defer { unsafe { path.free() } }
		other := after[path] or { return error('calculator host input disappeared') }
		if value != other { return error('calculator host input changed: ' + path) }
	}
}

fn freeze(root string, destination string, inputs map[string]Input) ! {
	for path, input in inputs {
		defer { unsafe { path.free() } }
		if input.kind != 'file' || !path.starts_with(root + '/') { continue }
		relative := path[root.len + 1..]
		if !relative.starts_with('tools/packages/') && !relative.starts_with('tests/packages/wine-calculator/') && relative != 'desktop/tools/tests/heap_tracker.h' { continue }
		target := destination + '/' + relative
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if digest(target)! != input.sha256 { return error('calculator frozen input copy differs') }
	}
	os.write_file(destination + '/v.mod', "Module { name: 'calculator_check' }\n")!
}

fn invoke(argv []string, log string) !int {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	return child.code
}

fn check() ! {
	$if !prod { return error('compile the source-capturing calculator driver with -prod; checks use explicit errors') }
	if os.args.len != 7 { return error('usage: wine-calculator-check V CLANG WORKTREE NEW_OUTPUT REAL_PE_DIRECTORY PRODUCER_SOURCE') }
	v := os.real_path(os.args[1]); cc := os.real_path(os.args[2]); root := os.real_path(os.args[3])
	out := os.abs_path(os.args[4]); pe := os.real_path(os.args[5]); producer := os.real_path(os.args[6])
	if os.exists(out) { return error('calculator qualification requires a new output directory') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-calculator-check.v').to_string()) { return error('calculator driver source differs from compiled bytes') }
	inputs := capture(v, cc, root, pe, producer)!
	os.mkdir_all(out)!; os.chmod(out, 0o700)!
	os.write_file(out + '/inputs-before-build.json', json2.encode(inputs) + '\n')!
	mut runs := []Run{}
	for name in ['normal', 'prod', 'sanitized', 'disabled-addition']! {
		directory := out + '/' + name; frozen := directory + '/source'
		freeze(root, frozen, inputs)!
		if name == 'disabled-addition' {
			path := frozen + '/tests/packages/wine-calculator/program.v'
			original := os.read_file(path)!
			guard := '`+` { left + right }'
			if original.count(guard) != 1 { return error('calculator addition mutation site differs') }
			os.write_file(path, original.replace(guard, '`+` { left - right }'))!
		}
		mut argv := [v, '-backend', 'c', '-cc', cc, '-nocache', '-gc', 'none', '-manualfree',
			'-d', 'track_heap', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-keepc',
			'-path', frozen + '|@vlib|@vmodules']
		if name in ['prod', 'disabled-addition']! { argv << '-prod' }
		if name == 'sanitized' { argv << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', directory + '/check', frozen + '/tests/packages/wine-calculator/program_test.v']
		code := invoke(argv, directory + '/compile.log')!
		if code != 0 { return error('calculator test compilation failed: ' + name) }
		run_code := invoke([directory + '/check'], directory + '/run.log')!
		log := os.read_file(directory + '/run.log')!
		if name == 'disabled-addition' {
			if run_code == 0 || !log.contains('V panic: calculator result ') { return error('calculator prod arithmetic mutation was not caught') }
		} else {
			if run_code != 0 { return error('calculator test execution failed: ' + name) }
			for marker in [
				'WIN64 CALCULATOR arithmetic, clear, chained operators and input replacement PASS',
				'WIN64 CALCULATOR fixed input bound, terminator, unknown button and reset PASS',
				'WIN64 CALCULATOR largest/smallest finite, exponent, fractional and overflow formatting PASS',
				'WIN64 CALCULATOR 10000 arithmetic/clear button cycles retain zero tracked V bytes PASS',
			]! { if log.count(marker) != 1 { return error('calculator success marker differs: ' + name) } }
			if log.contains('AddressSanitizer') || log.contains('runtime error:') { return error('calculator sanitizer diagnostic') }
		}
		runs << Run{name: name, compile_exit: code, run_exit: run_code,
			expected: if name == 'disabled-addition' { 'prod explicit arithmetic check must reject changed addition' } else { 'all four tests; 10000 repeated cycles retain zero tracked V bytes/records' }}
	}
	source := 'module main\nimport json2\nimport os\nimport tools.packages.wineadapter\nfn main() { check() or { eprintln(err); exit(1) } }\nfn check() ! {\n mut proof := wineadapter.admit_local_pe_proof(os.args[1], os.args[2], os.args[3])!\n defer { proof.close() }\n if proof.artifacts.len < 15 { return error("calculator PE artifact inventory incomplete") }\n os.write_file(os.args[4], json2.encode(proof.artifacts) + "\\n")!\n println("CALCULATOR REAL LOCAL PE RECEIPT ADMISSION PASS")\n}\n'
	os.write_file(out + '/real-admit.v', source)!
	argv := [v, '-backend', 'c', '-cc', cc, '-nocache', '-prod', '-gc', 'none', '-manualfree', '-keepc',
		'-path', out + '/prod/source|@vlib|@vmodules', '-o', out + '/real-admit', out + '/real-admit.v']
	if invoke(argv, out + '/real-compile.log')! != 0 { return error('calculator real PE admission compilation failed') }
	if invoke([out + '/real-admit', pe, root + '/tests/packages/wine-calculator/program.v', producer, out + '/real-artifacts.json'], out + '/real-run.log')! != 0 { return error('calculator real PE receipt admission failed') }
	runs << Run{name: 'real-producer-receipt', compile_exit: 0, run_exit: 0, expected: 'admit actual AMD64 PE32+ producer receipt and retain all ordinary-file input/output pins; never execute PE'}
	after := capture(v, cc, root, pe, producer)!
	same(inputs, after)!
	os.write_file(out + '/inputs-verified.json', json2.encode(after) + '\n')!
	mut outputs := map[string]string{}
	for path in os.walk_ext(out, '') { if os.is_file(path) { outputs[path[out.len + 1..]] = digest(path)! } }
	os.write_file(out + '/proof.json', json2.encode(Receipt{inputs: inputs, outputs: outputs, runs: runs,
		pe_directory: pe, pe_proof_sha256: digest(pe + '/proof.json')!,
		pe_executable_sha256: digest(pe + '/program.exe')!, pe_generated_c_sha256: digest(pe + '/program.c')!}) + '\n')!
	mut sources := map[string]string{}; mut tools := map[string]string{}; mut retained := map[string]string{}
	for path, input in inputs {
		defer { unsafe { path.free() } }
		if input.kind != 'file' { continue }
		if path.starts_with(root + '/') { sources[path[root.len + 1..]] = input.sha256
		} else if path in [v, cc, '/usr/bin/ld', os.executable(), @FILE, producer] { tools[path] = input.sha256 }
	}
	for path, value in outputs {
		defer { unsafe { path.free() } }
		if !path.contains('/source/') { retained[path] = value }
	}
	os.write_file(out + '/summary.json', json2.encode(Summary{proof_sha256: digest(out + '/proof.json')!,
		input_inventory_sha256: digest(out + '/inputs-before-build.json')!, input_count: inputs.len,
		sources: sources, tools: tools, outputs: retained, runs: runs, pe_directory: pe,
		pe_proof_sha256: digest(pe + '/proof.json')!, pe_executable_sha256: digest(pe + '/program.exe')!,
		pe_generated_c_sha256: digest(pe + '/program.c')!}) + '\n')!
	println('CALCULATOR normal+prod+ASan/UBSan 10000 zero-retention cycles, prod mutation refusal and real PE admission PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
