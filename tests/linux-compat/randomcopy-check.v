// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Evidence {
	architecture  string
	context       string
	base_commit   string
	artifacts     map[string]string
	source_inputs map[string]string
}

fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}
		state.checksum_into(mut result)
		return result.hex()
	}
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}

fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) {
		assert os.read_bytes(output)! == data
	} else {
		os.write_file_array(output, data)!
	}
}

fn git(tree string, args []string) !string {
	mut p := os.new_process('git')
	p.set_args(['-C', tree, ...args])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0, output
	return output.trim_space()
}

fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable())
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
	return output
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX RANDOMCOPY TOPOLOGY:'))
	assert rows_topology.len == 2
	mut seen_topology := map[string]bool{}
	for row in rows_topology {
		fields := row.fields()
		assert fields.len == 7 && fields[3] in ['ordinary=0', 'ordinary=1'] && fields[3] !in seen_topology
		seen_topology[fields[3]] = true
		assert fields[4] == if fields[3] == 'ordinary=0' { 'uid=0' } else { 'uid=1000' }
		assert fields[5] == if reference || arch == 'x86_64' { 'page=4096' } else { 'page=16384' }
		assert fields[6] == 'readiness=seeded'
	}
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX RANDOMCOPY ' + label))
		assert rows.len == 8
		mut seen := map[string]bool{}
		mut total := 0
		mut failures := 0
		for row in rows {
			fields := row.fields()
			assert fields.len == 7
			for index, prefix in {
				3: 'ordinary='
				4: 'kind='
				5: 'calls='
				6: 'failures='
			} {
				assert fields[index].starts_with(prefix)
			}
			ordinary := fields[3].all_after('=').int()
			kind := fields[4].all_after('=').int()
			assert ordinary in [0, 1] && kind in [0, 1, 2, 3]
			key := fields[3] + fields[4]
			assert key !in seen
			seen[key] = true
			n := fields[5].all_after('=').int()
			f := fields[6].all_after('=').int()
			assert n == [5472, 864, 6336, 1152]![kind]
			if phase == 'after' || kind != 0 {
				assert f == 0, row
			} else {
				// Prefixes below 256 expose EFAULT after output. Conservative
				// positive short results remain valid for larger prefixes.
				assert f == 4032, row
			}
			if label == 'CASES:' {
				cases[key] = fields[5] + fields[6]
			} else {
				assert cases[key] == fields[5] + fields[6]
			}
			total += n
			failures += f
		}
		assert total == 27648
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX RANDOMCOPY FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX RANDOMCOPY DETAIL:') && !log.contains('LINUX RANDOMCOPY FAIL:')
	} else {
		assert log.contains('LINUX RANDOMCOPY DETAIL:'), 'randomcopy baseline failure markers required'
		assert log.contains('LINUX RANDOMCOPY FAIL:') && !log.contains('LINUX RANDOMCOPY: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX RANDOMCOPY REFERENCE: PASS') && !log.contains('LINUX RANDOMCOPY STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX RANDOMCOPY: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX RANDOMCOPY SLAB:') || it.starts_with('LINUX RANDOMCOPY STORAGE:')) {
		fields := row.fields()
		assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int()
		assert ordinary in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'
			key := fields[3] + fields[4]
			assert key !in seen
			seen[key] = true
			slabs[ordinary]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0
			pages[ordinary]++
		}
	}
	for ordinary in 0 .. 2 {
		assert slabs[ordinary] == if phase == 'before' {
			0
		} else if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[ordinary] == if phase == 'before' { 0 } else { 1 }
	}
}

fn failure(log string, arch string) {
	assert log.contains('LINUX RANDOMCOPY DETAIL:'), 'randomcopy baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt': digest(state + '/receipt.json')
	}
	artifacts['aggregate'] = digest(state + '.log')
	for index, row in rows {
		entry := row.as_map()
		name := entry['name']!.str()
		assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 {
			1
		} else {
			0
		} && entry['detail']!.str() == ''
		for label, path in {
			'source': state + '/sources/' + name + 'fixture/core.v'
			'init':   state + '/' + name + '/init'
			'iso':    state + '/' + name + '/test.iso'
		} {
			hash := digest(path)
			key := if label == 'source' {
				'source_sha256'
			} else if label == 'init' {
				'init_sha256'
			} else {
				'iso_sha256'
			}
			assert hash == entry[key]!.str()
			artifacts[name + '_' + label] = hash
		}
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 {
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}

fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str())
	assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {
		'kernel':            state + '/linux'
		'probe':             state + '/probe'
		'wrapper_source':    state + '/source/randomcopyreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/randomcopy-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/randomcopyreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true)
	return artifacts
}

fn definition(source string, marker string) string {
	start := source.index(marker) or { panic('missing complete definition: ' + marker) }
	mut depth := 0
	mut entered := false
	for position in start .. source.len {
		if source[position] == `{` {
			depth++
			entered = true
		} else if source[position] == `}` {
			depth--
			if entered && depth == 0 { return source[start..position + 1] }
		}
	}
	panic('unclosed function definition')
}

fn check_source(area string, root string) ! {
	before := os.read_file(area + 'before-linux_common.v')!
	after := os.read_file(area + 'after-linux_common.v')!
	marker := 'fn syscall_linux_getrandom(_ voidptr, buf u64, count u64, flags u32)'
	old := definition(before, marker)
	new := definition(after, marker)
	unchanged := before.replace(old, '') == after.replace(new, '')
	assert unchanged, 'Only getrandom definition may change'
	old_copy := '\t\tif !usercopy.copy_to_user(buf + written, voidptr(&bounce[0]), chunk) {\n\t\t\t// Report the bytes that did land, as the manual page requires.'
	new_copy := '\t\tremaining := usercopy.raw_copy_to_user(buf + written, voidptr(&bounce[0]), chunk)\n\t\twritten += chunk - remaining\n\t\tif remaining != 0 {\n\t\t\t// Include a committed prefix within this chunk in the short result.'
	assert old.count(old_copy) == 1
	assert old.count('\t\twritten += chunk\n') == 1
	expected := old.replace(old_copy, new_copy).replace('\t\twritten += chunk\n', '')
	exact := new == expected
	assert exact, 'Only counted getrandom copy and short-result accumulation may change'
	assert digest(root + 'kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + 'before-' + suffix + '.c')!
	after := os.read_file(area + 'after-' + suffix + '.c')!
	marker := '\nmulti_return_u64_u64 table__syscall_linux_getrandom(void* _0, u64 buf, u64 count, u32 flags) {'
	old := definition(before, marker)
	new := definition(after, marker)
	helpers := '\nu64 usercopy__raw_copy_to_user(u64 destination, void* source, u64 length) {\n\treturn usercopy__raw_copy_user(source, destination, length, true, true);\n}\n\nu64 usercopy__raw_copy_user(void* kernel_address, u64 user_address, u64 length, bool to_user, bool allow_faults) {\n\tif (length == 0) {\n\t\treturn 0;\n\t}\n\tif ((kernel_address == NULL) || !usercopy__user_range(user_address, length)) {\n\t\treturn length;\n\t}\n\tproc__Process* process = (proc__current_thread())->process;\n\tif (process == NULL) {\n\t\treturn length;\n\t}\n\treturn usercopy__copy_pagemap_policy_remaining(process->pagemap, kernel_address, user_address, length, to_user, allow_faults, allow_faults);\n}\n'
	assert after.count(helpers) == 1 && !before.contains(helpers)
	mut stripped := after.replace(new, '').replace(helpers, '')
	for prototype in [
		'u64 usercopy__raw_copy_to_user(u64 destination, void* source, u64 length);\n',
		'u64 usercopy__raw_copy_user(void* kernel_address, u64 user_address, u64 length, bool to_user, bool allow_faults);\n',
	] {
		assert stripped.count(prototype) == 1 && !before.contains(prototype)
		stripped = stripped.replace(prototype, '')
	}
	unchanged := before.replace(old, '') == stripped
	assert unchanged, 'Whole production C differs outside getrandom and the two exact newly reachable existing raw-copy helpers'
	base := os.read_file(area + 'base.txt')!.trim_space()
	tree := area + 'kernel-' + suffix
	copy_source := os.read_file(tree + '/kernel/usercopy/usercopy.v')!
	assert copy_source.trim_space() == git(tree, ['show', base + ':kernel/usercopy/usercopy.v'])!
	assert digest(tree + '/kernel/usercopy/usercopy.v') == digest('/Users/alex/code/vinix/kernel/usercopy/usercopy.v')
	assert new.contains('usercopy__raw_copy_to_user') && new.contains('written += chunk - remaining')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert old.count(token) == new.count(token), suffix + token
	}
	assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn exploratory(area string, out string) ! {
	pins := object(area + 'exploratory-inputs.json')!
	assert pins.len == 62
	mut walked := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'reference'] {
			state := area + 'states/p1-' + phase + '-' + suffix
			for path in os.walk_ext(state, '') {
				if os.inode(path).typ != .regular { continue }
				assert path in pins && path !in walked
				walked[path] = true
			}
			assert state + '.log' in pins
			walked[state + '.log'] = true
			serial := state + if phase == 'before' {
				'/randomcopy/serial.log'
			} else {
				'/serial.log'
			}
			text := os.read_file(serial)!
			rows := text.split_into_lines().filter(it.starts_with('LINUX RANDOMCOPY FINAL:'))
			assert rows.len == 8
			for row in rows {
				fields := row.fields()
				assert fields.len == 7
				kind := fields[4].all_after('=').int()
				assert kind in [0, 1, 2, 3]
				assert fields[5] == 'calls=' + [5472, 864, 6336, 1152]![kind].str()
				expected := if kind != 0 {
					0
				} else if phase == 'before' {
					5472
				} else if suffix == 'arm' {
					3024
				} else {
					0
				}
				assert fields[6] == 'failures=' + expected.str()
			}
			if phase == 'reference' {
				value := object(state + '/receipt.json')!
				assert value['passed']!.bool() == (suffix == 'x86')
				assert value['finished']!.bool() && value['status']!.int() == 0
				if suffix == 'arm' {
					assert text.contains('count=19 result=1/0 expected=2/0')
					assert text.contains('Attempted to kill init! exitcode=0x00000100')
				}
			}
			for label, path in {
				'receipt.json':  state + '/receipt.json'
				'aggregate.log': state + '.log'
				'serial.log':    serial
			} {
				assert digest(out + 'randomcopy-exploratory-' + phase + '-' + suffix + '-' + label) == pins[path]!.str()
			}
		}
		for path in os.walk_ext(area + 'states/preflight1-randomcopy-' + suffix, '') {
			if os.inode(path).typ != .regular { continue }
			assert path in pins && path !in walked
			walked[path] = true
		}
		old_c := os.read_file(area + 'states/preflight1-randomcopy-' + suffix + '/fixture.c')!
		assert old_c.contains('result.ret == expected') && !old_c.contains('result.ret == wanted')
	}
	assert walked.len == pins.len
	for path, hash in pins {
		assert digest(path) == hash.str(), path
	}
	publish(area + 'exploratory-inputs.json', out + 'randomcopy-exploratory-inputs.json')!
	recovery := object(area + 'reference-recovery-inputs.json')!
	assert recovery.len == 4
	for suffix in ['arm', 'x86'] {
		original := area + 'states/p1-reference-' + suffix + '.log'
		refusal := area + 'reference-restart-refusal-' + suffix + '.log'
		assert recovery[original]!.str() == pins[original]!.str()
		assert digest(original) == recovery[original]!.str()
		assert os.read_file(refusal)!.trim_space() == 'state directory must be fresh'
		assert digest(refusal) == recovery[refusal]!.str()
		assert digest(out + 'randomcopy-reference-restart-refusal-' + suffix + '.log') == digest(refusal)
	}
	publish(area + 'reference-recovery-inputs.json', out + 'randomcopy-reference-recovery-inputs.json')!
}

fn round2(area string, out string) ! {
	pins := object(area + 'round2-inputs.json')!
	assert pins.len == 128
	mut walked := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after', 'reference'] {
			state := area + 'states/p2-' + phase + '-' + suffix
			for path in os.walk_ext(state, '') {
				if os.inode(path).typ != .regular { continue }
				assert path in pins && path !in walked
				walked[path] = true
			}
			assert state + '.log' in pins
			walked[state + '.log'] = true
			serial := state + if phase == 'reference' {
				'/serial.log'
			} else {
				'/randomcopy/serial.log'
			}
			rows := os.read_file(serial)!.split_into_lines().filter(it.starts_with('LINUX RANDOMCOPY FINAL:'))
			assert rows.len == 8
			for row in rows {
				fields := row.fields()
				assert fields.len == 7
				kind := fields[4].all_after('=').int()
				assert kind in [0, 1, 2, 3]
				assert fields[5] == 'calls=' + [5472, 864, 6336, 1152]![kind].str()
				failures := fields[6].all_after('=').int()
				if kind == 0 && phase == 'before' {
					assert failures >= 4032 && failures <= 5472
				} else {
					assert failures == if kind == 0 && phase == 'reference' && suffix == 'arm' {
						432
					} else {
						0
					}
				}
			}
			if phase == 'reference' {
				value := object(state + '/receipt.json')!
				assert value['passed']!.bool() == (suffix == 'x86')
				assert value['finished']!.bool() && value['status']!.int() == 0
			}
			for label, path in {
				'receipt.json':  state + '/receipt.json'
				'aggregate.log': state + '.log'
				'serial.log':    serial
			} {
				assert digest(out + 'randomcopy-round2-' + phase + '-' + suffix + '-' + label) == pins[path]!.str()
			}
		}
		for path in os.walk_ext(area + 'states/preflight2-randomcopy-' + suffix, '') {
			if os.inode(path).typ != .regular { continue }
			assert path in pins && path !in walked
			walked[path] = true
		}
		old_c := os.read_file(area + 'states/preflight2-randomcopy-' + suffix + '/fixture.c')!
		assert old_c.contains('result.ret == wanted') && old_c.contains('wanted > 0')
	}
	assert walked.len == pins.len
	for path, hash in pins {
		assert digest(path) == hash.str(), path
	}
	publish(area + 'round2-inputs.json', out + 'randomcopy-round2-inputs.json')!
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'randomcopy assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: randomcopy-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	exploratory(area, out)!
	round2(area, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'randomcopy assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p3-reference-arm/serial.log', 'aarch64'], 'randomcopy baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete generated production C differs only in getrandom plus the exact bodies/declarations of newly reachable existing raw_copy_to_user/raw_copy_user helpers; usercopy source matches frozen committed base. Exact counted raw-copy substitution and short-result accumulation; existing bounce lifetime and erasure unchanged; no compiler normalization or added allocation/free\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '010468874ce63a2caec7e469bfe37ec4fd866936'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	before_alloc := os.read_file(area + 'allocs-before.log')!
	after_alloc := os.read_file(area + 'allocs-after.log')!
	assert before_alloc == after_alloc, 'Allocation diagnostics must remain byte-identical'
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		assert before_alloc.split_into_lines().filter(it.starts_with(arch + ':')).len == 1
		assert before_alloc.contains(count + ' allocation sites (V exit 0)') && before_alloc.contains('NEW:')
	}
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-random-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/char/random.c'
	linux_source := os.read_file(area + 'linux-random-v6.12.c')!
	assert linux_source.contains('ret += copied;') && linux_source.contains('return ret ? ret : -EFAULT;') && linux_source.contains('SYSCALL_DEFINE3(getrandom, char __user *, ubuf, size_t, len, unsigned int, flags)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 72
	for path, hash in retained {
		assert path.starts_with(states + 'p3-before-') || path.starts_with(states + 'p3-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['randomcopy']
			} else {
				['randomcopy', 'runtime', 'randomflags']
			}
			for name in names {
				probe := states + 'p3-' + phase + '-' + suffix + '/' + name
				completed['Completed ' + probe + ': captured files byte-identical; disposable boot staging retired'] = true
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				mut count := 0
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ != .regular { continue }
					assert path in retained && path !in walked
					walked[path] = true
					count++
				}
				assert count == 9
			}
		}
	}
	assert walked.len == retained.len
	for row in os.read_file(area + 'watch.log')!.split_into_lines() {
		assert row in completed
		completed.delete(row)
	}
	assert completed.len == 0
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 64
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			assert before_inputs[path] == if path == 'kernel/syscall/table/linux_common.v' {
				digest(area + 'before-linux_common.v')
			} else {
				hash
			}
		}
		mut artifacts := {
			'compiler':                  digest(compiler_root + 'compiler/v')
			'compiler_inputs':           digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':             digest(root + 'kernel/syscall/table/linux_common.v')
			'kernel_source_before':      digest(area + 'before-linux_common.v')
			'usercopy_source':           digest(tree + 'kernel/usercopy/usercopy.v')
			'initial_scope_refusal':     digest(area + 'audit-producer-first.log')
			'initial_scope_status':      digest(area + 'audit-producer-first.log.status')
			'fixture_source':            digest(root + 'tests/linux-compat/randomcopyfixture/core.v')
			'audit_source':              digest(@FILE)
			'linux_primary_source':      digest(area + 'linux-random-v6.12.c')
			'linux_primary_pin':         digest(area + 'linux-source.sha256')
			'native_controller':         digest(area + 'run')
			'native_controller_source':  digest(root + 'tests/linux-compat/run.v')
			'reference_controller':      digest(area + 'reference')
			'watch_pins':                digest(area + 'watch-retained-inputs.json')
			'watch_log':                 digest(area + 'watch.log')
			'exploratory_pins':          digest(area + 'exploratory-inputs.json')
			'exploratory_producer':      digest(area + 'exploratory.v')
			'reference_recovery':        digest(area + 'reference-recovery-inputs.json')
			'reference_recovery_source': digest(area + 'reference-recovery.v')
			'round2_inputs':             digest(area + 'round2-inputs.json')
			'round2_producer_source':    digest(area + 'archive-round2.v')
		}
		for name in ['manage.v', 'manage', 'manage2.v', 'manage2', 'manage3.v', 'manage3', 'manage4.v',
			'manage4', 'watch3.v', 'watch3', 'preflight3.v', 'preflight3-jobs.v',
			'helper-preflight3-jobs.log', 'preflight3-arm.log', 'preflight3-x86.log',
			'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p3-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['randomcopy']
			} else {
				['randomcopy', 'runtime', 'randomflags']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['randomcopy_source', 'randomcopy_init', 'randomcopy_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/randomcopy/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + 'build-' + phase + '-' + suffix + '-detached.log'
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/randomcopy/serial.log'
				'build':     build
			} {
				publish(path, out + 'randomcopy-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'randomcopy' { continue }
					publish(state + '/' + name + '/serial.log', out + 'randomcopy-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		preflight := states + 'preflight3-randomcopy-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['randomcopy_c'] && digest(preflight + '/init') == identity['randomcopy_init']
		assert raw.count('alloca(') == 4
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p3-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['randomcopy_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'randomcopy-reference-' + arch + '-' + label + if label == 'receipt' {
				'.json'
			} else {
				'.log'
			})!
			artifacts['reference_' + label] = digest(path)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
			'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
			artifacts[name] = digest(area + name)
		}
		os.write_file(out + 'randomcopy-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context:       'Native seeded getrandom partial copy faults, 27648 root/UID1000 controls per architecture: positive bounded short counts for PROT_NONE/read-only/unmapped suffixes, 22 prefix lengths around32/64/128/256/512 and native-page boundaries, four suffix lengths, successful zero/short/exact transfers and first-byte EFAULT. Six valid flags, three raw register-word forms and genuine musl calls; guards outside accessible output prefixes and read-only sentinels, real random output for prefixes>=32. Originals fail8064 controls with EFAULT after output; corrected and identical-ELF Linux6.12.51 zero. Four explicit stack allocas, two flat warmed200-cycle partial/zero paths, four fresh production builds, three native cases per architecture, byte-identical allocation diagnostics, compiler and inventory pins and executing audit negatives. Only getrandom counted copying and byte accumulation change; bounce ownership and existing erasure policy stay unchanged. Entropy quality, unseeded blocking/interruption, canonical-range wrap policy, signal interruptions, huge valid transfers, glibc and translated/ELF32 paths remain unqualified.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log',
		'coverage-before-check.log', 'helper-preflight3-jobs.log'] {
		publish(area + name, out + 'randomcopy-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'randomcopy-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native randomcopy conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'randomcopy-audit.log')!
	println('Native randomcopy conformance audit: PASS')
}
