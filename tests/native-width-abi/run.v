import crypto.sha256
import os

fn main() {
	if os.args.len != 3 {
		eprintln('usage: v run tests/native-width-abi/run.v /path/to/v /external/fresh-state-dir')
		exit(1)
	}
	compiler := os.real_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert os.is_file(compiler), compiler
	assert !os.exists(state), 'state directory must be fresh: ${state}'
	os.mkdir_all(state)!
	fixture := os.dir(@FILE)
	root := os.real_path(os.join_path(fixture, '..', '..'))
	os.write_file(os.join_path(state, 'v.mod'), "Module { name: 'vinix_native_width_abi' }\n")!
	os.cp(os.join_path(fixture, 'native-abi.h'), os.join_path(state, 'native-abi.h'))!
	os.cp(os.join_path(fixture, 'probe.vv'), os.join_path(state, 'main.v'))!
	mut hashes := []string{}
	for relative in ['kernel/lib/stubs/memory.v', 'kernel/krandom/erase.v'] {
		source := os.read_file(os.join_path(root, relative))!
		hashes << '${sha256.hexhash(source)}  ${relative}'
		mut copied := source.replace('module stubs', 'module main').replace('module krandom',
			'module main')
		if relative.ends_with('/memory.v') {
			// This probe exercises the four memory primitives. The same file's
			// unrelated atoi export would interpose on the host C runtime.
			marker := "\n@[export: 'atoi']"
			assert copied.contains(marker)
			copied = copied.all_before(marker) + '\n'
		}
		// Keep production bodies intact. Rename only exported symbols so the
		// host process keeps its libc memory primitives during the test.
		for name in ['memcpy', 'memset', 'memmove', 'memcmp'] {
			copied = copied.replace("@[export: '${name}']", "@[export: 'vinix_probe_${name}']")
		}
		copied = copied.replace("@[export: 'vinix_explicit_bzero']", "@[export: 'vinix_probe_erase']")
		os.write_file(os.join_path(state, os.file_name(relative)), copied)!
	}
	os.write_file(os.join_path(state, 'source-sha256.txt'), hashes.join('\n') + '\n')!
	// Older compilers resolve their standard library from a nearby V checkout.
	// Do not borrow the runner's checkout when comparing compiler versions.
	os.chdir(os.dir(compiler))!
	version := os.exec([compiler, '-version'])
	os.write_file(os.join_path(state, 'compiler.txt'), version.output)!
	assert version.exit_code == 0, version.output
	program := os.join_path(state, 'probe')
	build := os.exec([compiler, '-new-compiler', '-no-retry-compilation', '-nocache', '-prod',
		'-gc', 'none', '-cc', 'cc', '-o', program, state])
	os.write_file(os.join_path(state, 'build.log'), build.output)!
	assert build.exit_code == 0, build.output
	run := os.exec([program])
	os.write_file(os.join_path(state, 'run.log'), run.output)!
	assert run.exit_code == 0, run.output
	print(version.output)
	print(run.output)
}
