// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn checked(args []string) ! {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.run()
	child.wait()
	code := child.code
	child.close()
	if code != 0 { return error('command failed: ${args} (${code})') }
}

fn main() {
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.join_path(os.temp_dir(), 'vinix-resource-stat-${os.getpid()}')
	for name in ['resource', 'stat', 'time', 'errno', 'klock', 'event/eventstruct'] {
		os.mkdir_all(work + '/' + name)!
	}
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'resource_stat_probe' }")!
	os.cp(root + '/kernel/resource/stat.v', work + '/resource/stat.v')!
	os.cp(root + '/kernel/stat/stat.v', work + '/stat/stat.v')!
	os.write_file(work + '/time/time.v', 'module time\npub struct TimeSpec { pub mut: tv_sec i64 tv_nsec i64 }\n')!
	os.write_file(work + '/klock/klock.v', 'module klock\npub struct Lock {}\n')!
	os.write_file(work + '/event/eventstruct/event.v', 'module eventstruct\npub struct Event {}\n')!
	os.write_file(work + '/errno/errno.v', 'module errno\n@[has_globals]\n__global ( current = u64(0) )\npub const err = ~u64(0)\npub fn set(value u64) { current = value }\npub fn get() u64 { return current }\n')!
	contract := os.read_file(root + '/kernel/resource/resource.v')!.all_after('pub interface Resource {').all_before('\n}')
	os.write_file(work + '/resource/contract.v', 'module resource\nimport stat\nimport klock\nimport event.eventstruct\n#flag -Dvinix_stack_alloc=__builtin_alloca\nfn C.vinix_stack_alloc(usize) voidptr\npub interface Resource {${contract}\n}\n')!
	cache := os.read_file(root + '/kernel/resource/cache.v')!
	mut lifetime := 'module resource\nimport katomic\n'
	for name in ['retain_resource', 'release_resource'] {
		anchor := 'pub fn ${name}('
		lifetime += anchor + cache.all_after(anchor).all_before('\n}') + '\n}\n'
	}
	os.mkdir_all(work + '/katomic')!
	os.write_file(work + '/katomic/katomic.v', 'module katomic\npub fn inc(mut value &int) int { unsafe { *value += 1; return *value } }\n')!
	os.write_file(work + '/resource/lifetime.v', lifetime)!
	copy_source := os.read_file(root + '/kernel/fs/stat.v')!
	os.write_file(work + '/copy.v', copy_source.replace('module fs', 'module main'))!
	os.cp(root + '/tests/resource-stat/main.vfixture', work + '/main.v')!
	compiler := os.getenv_opt('V') or { @VEXE }
	cc := os.getenv_opt('CC') or { 'clang' }
	flags := ['-nocache', '-cc', cc, '-enable-globals', '-gc', 'none', '-manualfree']
	checked([compiler, ...flags, '-o', work + '/probe', work])!
	checked([work + '/probe'])!
	checked([compiler, ...flags, '-o', work + '/probe.c', work])!
	generated := os.read_file(work + '/probe.c')!
	for name in ['resource__snapshot_stat', 'main__stat_resource', 'main__stat_path_resource'] {
		aliases := if name.starts_with('main__') { [name, name.all_after('main__')] } else { [name] }
		mut found := false
		for line in generated.split_into_lines() {
			if !aliases.any(line.contains(it + '(')) || !line.ends_with(' {') || line.starts_with('\t') { continue }
			body := generated.all_after(line + '\n').all_before('\n}')
			for allocation in ['HEAP(', 'memdup(', '_v_malloc(', 'calloc('] {
				assert !body.contains(allocation), 'unexpected allocation in ${name}'
			}
			found = true
			break
		}
		assert found, 'missing generated definition for ${name}'
	}
	println('Stat snapshot dispatch: no generated heap allocation')
}
