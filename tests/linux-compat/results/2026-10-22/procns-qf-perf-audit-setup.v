import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn main() {
	for name in ['results', 'drag'] {
		original := os.read_file(area + '/verify-perf-' + name + '.v')!
		modified := original.replace('perf-small-ops', 'qf-perf-compat-ops')
			.replace('perf-compat-desktop', 'qf-perf-compat-desktop')
			.replace('perf-drag-', 'qf-perf-drag-')
			.replace('ARM ', 'Queue-fix ARM ')
		source := area + '/qf-verify-perf-' + name + '.v'
		assert !os.exists(source)
		os.write_file(source, modified)!
		mut process := os.new_process(compiler)
		process.set_args(['-o', area + '/qf-verify-perf-' + name, source])
		process.set_redirect_stdio_merged()
		process.run()
		output := process.stdout_slurp()
		process.wait()
		code := process.code
		process.close()
		os.write_file(area + '/qf-perf-audit-compile-' + name + '.log', output)!
		os.write_file(area + '/qf-perf-audit-compile-' + name + '.status', '${code}\n')!
		assert code == 0, output
	}
	println('Prepared strict queue-fix raw-result auditors with unchanged assertions')
}
