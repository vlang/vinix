import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn run(binary string, log string, status string) ! {
	mut process := os.new_process(binary)
	process.set_work_folder(root)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp() + process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(log, output)!
	os.write_file(status, '${code}\n')!
	print(output)
	assert code == 0, '${binary}: status ${code}'
}

fn main() {
	for name in ['publication-map.json', 'perf-publication-inputs.json', 'desktop-publication-inputs.json', 'x86-regressions-publication-inputs.json', 'queue-publication-inputs.json', 'queue-perf-publication-inputs.json', 'queue-desktop-publication-inputs.json'] {
		assert os.is_file(area + '/' + name), 'Pending publication map: ' + name
	}
	pins := json2.decode[map[string]string](os.read_file(area + '/source-manifest3.json')!)!
	for path in [root + '/tests/linux-compat/procns-check.v', area + '/procns-check'] {
		assert sha256.sum(os.read_bytes(path)!).hex() == pins[path]!, path
	}
	run(area + '/publication-preflight', area + '/final-publication-preflight.log', area + '/final-publication-preflight.status')!
	run(area + '/publish', area + '/final-publish.log', area + '/final-publish.status')!
	out := root + '/tests/linux-compat/results/2026-10-22/'
	run(area + '/procns-check', out + 'procns-check.log', out + 'procns-check.status')!
}
