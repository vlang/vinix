// Compile without -prod; deliberate failures prove the verdict oracle executes.
import crypto.sha256
import json2
import os
import strconv

struct Evidence {
	architecture string
	context string
	base_commit string
	artifacts map[string]string
	source_inputs map[string]string
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) { assert os.read_bytes(output)! == data }
	else { os.write_file_array(output, data)! }
}
fn git(tree string, args []string) !string {
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0
	return output.trim_space()
}
fn body(text string, signature string) string {
	assert text.contains(signature)
	return text.all_after(signature).all_before('\n}\n')
}
fn allocation_counts(path string) !map[string]int {
	mut counts := map[string]int{}
	for line in os.read_file(path)!.split_into_lines() {
		location := line.all_before(' ').split(':')
		if location.len != 3 { continue }
		strconv.atoi(location[1]) or { continue }
		strconv.atoi(location[2]) or { continue }
		counts[location[0] + ' ' + line.all_after(' ')]++
	}
	return counts
}
fn check_alloc(text string, wanted int) {
	for method in 0 .. 2 { for ordinary in 0 .. 2 {
		prefix := 'LINUX SECCOMPALLOC CASE: method=' + method.str() + ' ordinary=' + ordinary.str()
			+ ' allocation=' + wanted.str() + ' mode=2 nnp=' + ordinary.str() + ' big_pages='
		lines := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
		assert lines.len == 1, 'missing verified allocation marker'
		assert lines[0].trim_space().ends_with(' PASS')
		pages := lines[0].all_after('big_pages=').all_before(' PASS').split('/')
		assert pages.len == 2
		before := strconv.atoi(pages[0]) or { panic('invalid before page count') }
		after := strconv.atoi(pages[1]) or { panic('invalid after page count') }
		assert before == after
	} }
}
fn control(arguments []string, expected string) {
	mut p := os.new_process(os.executable()); p.set_args(arguments); p.set_redirect_stdio(); p.run()
	message := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !message.contains(expected) { panic('audit assertions must execute and reject incorrect allocation modes') }
}
fn main() {
	if '--negative-control' in os.args { assert false, 'receipt audit failure must be fatal'; return }
	if '--negative-allocation' in os.args { check_alloc(os.read_file(os.args[2])!, 12); return }
	control(['--negative-control'], 'receipt audit failure must be fatal')
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-seccomp-alloc-1012/'
	control(['--negative-allocation', area + 'after-final-arm.log'], 'missing verified allocation marker')
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 60
	own := 'kernel/syscall/table/container.v'
	for path, hash in inputs { if !path.starts_with('kernel/') || path == own { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	before_counts := allocation_counts(area + 'allocs-before.log')!
	after_counts := allocation_counts(area + 'allocs-after.log')!
	assert before_counts.len > 100 && before_counts == after_counts
	for label in ['before', 'after'] {
		text := os.read_file(area + 'allocs-' + label + '.log')!
		assert text.contains('406 allocation sites (V exit 0)') && text.contains('297 allocation sites (V exit 0)')
		assert text.contains('NEW: ') && !text.contains('ERROR: ')
		publish(area + 'allocs-' + label + '.log', out + 'seccompalloc-allocs-' + label + '.log')!
	}
	retention := json2.decode[json2.Any](os.read_file(area + 'perf-retention-final.json')!)!.as_array()
	ops := retention.filter(it.as_map()['report']!.str() == 'PERF-OPS')
	churn := retention.filter(it.as_map()['report']!.str() == 'PERF-CHURN')
	assert ops.len == 36 && churn.len == 4
	for row in ops { assert row.as_map()['bytes_per_op']!.str() == '0' && row.as_map()['count']!.str() == '200' }
	for row in churn { assert row.as_map()['per_run_bytes']!.str() == '0' && row.as_map()['runs']!.str() == '300' }
	for phase in ['before', 'after'] {
		assert json2.decode[json2.Any](os.read_file(area + 'perf-desktop-' + phase + '-final.json')!)!.as_array().len == 0
		text := os.read_file(area + 'perf-desktop-' + phase + '-final.log')!
		assert text.contains('the desktop was not ready after 1s')
		assert text.contains('3 of 3 measurements missing')
	}
	desktop := object(area + 'desktop-input.json')!
	assert desktop['sha256']!.str() == digest(area + 'desktop')
	for input, output in {
		'perf-retention-final.json': 'retention-aarch64.json'
		'perf-retention-final.log': 'retention-aarch64.log'
		'perf-desktop-before-final.json': 'desktop-before-aarch64.json'
		'perf-desktop-before-final.log': 'desktop-before-aarch64.log'
		'perf-desktop-after-final.json': 'desktop-after-aarch64.json'
		'perf-desktop-after-final.log': 'desktop-after-aarch64.log'
		'desktop-input.json': 'desktop-input.json'
	} { publish(area + input, out + 'seccompalloc-' + output)! }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		mut artifacts := map[string]string{}
		for profile in ['', 'fail-'] {
			tree := area + 'kernel-' + profile + suffix + '/'
			assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'a11caa1b'
			assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == own
			for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
			generated := os.read_file(tree + 'kernel/obj/blob.c')!
			install := body(generated, 'multi_return_u64_u64 table__seccomp_install(u64 prog, u32 flags) {')
			assert install.contains('u64 header[2];') && !install.contains('memdup(')
			assert install.contains('Array instructions = array_new(\tsizeof(proc__SockFilter), 0, 0)')
			assert install.contains('instructions.data = buffer;') && install.contains('instructions.flags = 4;')
			assert install.contains('instructions.len = length;') && install.contains('instructions.cap = length;')
			assert install.count('array__free(&instructions)') == 3
			allocation := install.index('table__seccomp_instruction_allocation') or { panic('missing allocation') }
			nil_guard := install.index('if (buffer == NULL)') or { panic('missing nil guard') }
			array_header := install.index('Array instructions =') or { panic('missing array header') }
			program_copy := install.last_index('usercopy__copy_from_user') or { panic('missing program copy') }
			assert allocation < nil_guard && nil_guard < array_header && array_header < program_copy
			assert install[nil_guard..array_header].contains('errno__enomem')
			helper := body(generated, 'void* table__seccomp_instruction_allocation(u64 bytes) {')
			assert helper.contains('return memory__malloc_packed_fallible(bytes);')
			assert helper.contains('4095') == (profile == 'fail-')
			assert helper.contains('return NULL;') == (profile == 'fail-')
			free_body := body(generated, 'void array__free(array* a) {')
			assert free_body.contains('if ((a->flags & 16) != 0)') && free_body.contains('v_free(mblock_ptr);')
			assert generated.contains('if (len == 0 && cap == 0) return (array)')
			artifacts[profile + 'kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
			artifacts[profile + 'kernel'] = digest(tree + 'kernel/bin/vinix')
		}
		for phase in ['before', 'after', 'fault'] {
			state := area + phase + '-final-' + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'before' { assert receipt['kernel_sha256']!.str() == object(out + 'seccompinstall-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			else { assert receipt['kernel_sha256']!.str() == artifacts[if phase == 'fault' { 'fail-kernel' } else { 'kernel' }] }
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else if phase == 'fault' { 2 } else { 8 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == 0
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init')
				assert item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'seccompalloc' {
					fixture := os.read_file(state + '/' + name + '/fixture.c')!
					for allocation in ['memdup(', 'v_fixed_index', 'malloc(', 'array_new('] { assert !fixture.contains(allocation) }
					assert fixture.contains('sscanf(') && fixture.contains('large - - %lu')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			assert names == if phase == 'before' { ['seccompalloc'] }
				else if phase == 'fault' { ['seccompalloc', 'seccompthread'] }
				else { ['seccompalloc', 'seccompinstall', 'seccompthread', 'seccompkill', 'seccomp', 'nnpthread', 'seccompquery', 'runtime'] }
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION') && !text.contains('LINUX SECCOMPALLOC DETAIL')
			check_alloc(text, if phase == 'fault' { 12 } else { 0 })
			for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
			if phase != 'before' { for cycle in 0 .. 2 { for size in [32, 64, 96, 128] {
				prefix := 'LINUX SECCOMPTHREAD SLAB: cycle=' + cycle.str() + ' size=' + size.str() + ' '
				lines := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
				assert lines.len >= 1 && lines.all(it.trim_space().ends_with('delta=0'))
			} } }
			label := 'seccompalloc-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
		}
		artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'host-tests.log')
		artifacts['audit'] = digest(@FILE)
		if arch == 'aarch64' {
			for path in ['perf-retention-final.json', 'perf-retention-final.log',
				'perf-desktop-before-final.json', 'perf-desktop-before-final.log',
				'perf-desktop-after-final.json', 'perf-desktop-after-final.log', 'desktop-input.json'] {
				artifacts[path] = digest(area + path)
			}
			artifacts['desktop'] = digest(area + 'desktop')
			artifacts['performance_controller'] = digest('/tmp/vinix-seccomp-1012/perf')
		}
		record := Evidence{arch, 'Native musl ELF64 raw instruction ownership: ordinary baseline/production success versus separately built allocator-nil injection, exact ENOMEM before instruction copy, unchanged mode/NNP and subsequent small-filter service; 256 rejected large-buffer copies per credential/interface retain flat big-allocation page counts, and3200-filter retirement cohorts retain flat32/64/96/128 classes. Test injection is absent from production. Global physical OOM/recovery remains unqualified', 'a11caa1b', artifacts, inputs}
		os.write_file(out + 'seccompalloc-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'seccompalloc-host-tests.log')!
	println('Native seccomp fallible buffer ownership, allocator-nil controls and retention evidence: verified')
}
