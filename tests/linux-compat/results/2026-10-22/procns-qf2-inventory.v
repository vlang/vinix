import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn run(program string, args []string, label string) !int {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(area + '/' + label + '.log', output)!
	os.write_file(area + '/' + label + '.status', '${code}\n')!
	return code
}

fn groups(log string) map[string]int {
	mut counts := map[string]int{}
	for line in log.split_into_lines() {
		parts := line.split(':')
		if parts.len < 3 || parts[1] == '' || !parts[1].bytes().all(it.is_digit()) { continue }
		key := parts[0] + ' ' + line.all_after(':').all_after(':').all_after(' ')
		counts[key]++
	}
	return counts
}

fn main() {
	base := area + '/kernel-arm'
	candidate := area + '/queue-fix/kernel-arm'
	copy_tool := area + '/qf2-copy-sources'
	assert !os.exists(area + '/qf2-allocs-candidate.log')
	assert run(compiler, ['-o', copy_tool, candidate + '/tests/kernel-allocs/copy_sources.v'], 'qf2-copy-compile')! == 0
	os.setenv('V', compiler, true)
	os.setenv('VINIX_KERNEL_ALLOCS_COPY_TOOL', copy_tool, true)
	for label, tree in {'baseline': base, 'candidate': candidate} {
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', tree, true)
		status := run(candidate + '/tests/kernel-allocs/run.sh', [], 'qf2-allocs-' + label)!
		assert status == 1, 'unexpected inventory status: ' + label + ' ' + status.str()
	}
	before_text := os.read_file(area + '/qf2-allocs-baseline.log')!
	after_text := os.read_file(area + '/qf2-allocs-candidate.log')!
	before, after := groups(before_text), groups(after_text)
	mut output := ['Both complete allocation inventories exited 1 against existing allowance excesses.']
	for text in [before_text, after_text] {
		for arch in ['aarch64', 'x86_64'] {
			rows := text.split_into_lines().filter(it.starts_with(arch + ':'))
			assert rows.len == 1 && rows[0].contains('V exit 0') && !rows[0].contains('0 source files')
			output << rows[0]
		}
	}
	assert before.len > 0 && before.len == after.len
	for key, count in after { assert key in before && before[key] == count, 'new or changed allocation group: ' + key }
	before_excess := before_text.split_into_lines().filter(it.starts_with('NEW:'))
	after_excess := after_text.split_into_lines().filter(it.starts_with('NEW:'))
	assert before_excess == after_excess, 'allowance excess groups changed'
	output << 'PASS: identical per-file/kind counts and identical existing allowance excesses; no new allocation group.'
	os.write_file(area + '/qf2-allocs-comparison.log', output.join('\n') + '\n')!
	os.write_file(area + '/qf2-allocs-comparison.status', '0\n')!
	mut pins := []string{}
	for path in [base + '/kernel/fs/removed.v', candidate + '/kernel/fs/removed.v', base + '/tests/kernel-allocs/allowed.txt', candidate + '/tests/kernel-allocs/allowed.txt', candidate + '/tests/kernel-allocs/run.sh', candidate + '/tests/kernel-allocs/copy_sources.v', candidate + '/tests/kernel-allocs/copycore/core.v', copy_tool, compiler, area + '/qf2-inventory.v', os.executable(), area + '/qf2-allocs-baseline.log', area + '/qf2-allocs-candidate.log', area + '/qf2-allocs-comparison.log'] {
		pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path
	}
	os.write_file(area + '/qf2-allocs-inputs.sha256', pins.join('\n') + '\n')!
	println(output.join('\n'))
}
