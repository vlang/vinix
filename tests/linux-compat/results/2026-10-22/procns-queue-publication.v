import json2
import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	mut audit := os.new_process(area + '/audit-queue-attribution')
	audit.set_redirect_stdio_merged()
	audit.run()
	output := audit.stdout_slurp()
	audit.wait()
	os.write_file(area + '/audit-queue-attribution.log', output)!
	os.write_file(area + '/audit-queue-attribution.status', audit.code.str() + '\n')!
	assert audit.code == 0, output
	audit.close()
	mut old := json2.decode[map[string]string](os.read_file(area + '/publication-map.json')!)!
	old['x86-original-queue-growth.log'] = area + '/states/final3-after-x86/serial.log'
	old['x86-original-queue-growth.json'] = area + '/states/final3-after-x86/receipt.json'
	old['final3-after-x86'] = area + '/states/final3-after-x86'
	old['final3-before-x86'] = area + '/states/final3-before-x86'
	mut flat_old := map[string]string{}
	for name, path in old {
		if os.is_dir(path) {
			for file in ['receipt.json', 'serial.log', 'inputs.json', 'fixture.o.compiler.json', 'init.compiler.json'] {
				if os.is_file(path + '/' + file) { flat_old[name + '.' + file] = path + '/' + file }
			}
		} else { flat_old[name] = path }
	}
	os.write_file(area + '/publication-map.json', json2.encode(flat_old, prettify: true) + '\n')!
	mut inputs := {'queue-attribution.json': area + '/queue-attribution.json', 'queue-attribution-audit.v': area + '/audit-queue-attribution.v', 'queue-kind2-fixture.v': area + '/diagnostic-kind2b/procnsfixture/core.v', 'queue-kind2-controller.v': area + '/run-kind2.v', 'queue-kind2-watch.v': area + '/watch-kind2.v', 'queue-qmp-helper.v': area + '/qmp-queue.v', 'queue-qmp-initial-helper': area + '/qmp-queue', 'queue-qmp-metadata-helper': area + '/qmp-queue-next', 'queue-kind2-diagnostic': area + '/states/diagnostic-kind2b-after-x86', 'queue-kind2-initial-compile-failure': area + '/states/diagnostic-kind2-after-x86', 'queue-kind2-initial-fixture.v': area + '/diagnostic-kind2/procnsfixture/core.v', 'queue-seal-third.v': area + '/seal-third.v', 'queue-build-controller.v': area + '/queue-fix-build.v'}
	inputs['audit-queue-attribution.v'] = area + '/audit-queue-attribution.v'
	inputs['audit-queue-attribution.log'] = area + '/audit-queue-attribution.log'
	inputs['audit-queue-attribution.status'] = area + '/audit-queue-attribution.status'
	for name in ['native-dedup.v', 'native-dedup.log', 'native-dedup-records.json'] { inputs[name] = area + '/' + name }
	for name in ['queue-fix-q2.v', 'queue-fix-review.v'] { inputs[name] = area + '/' + name }
	for name in ['select-queue-runs.v', 'summarize.v', 'queue-publication.v'] { inputs[name] = area + '/' + name }
	inputs['queue-host-snapshot.v'] = area + '/queue-host-snapshot.v'
	for name in os.ls(area + '/queue-fix')! {
		if (name.starts_with('q2-') || name == 'queue-commit.txt') && os.is_file(area + '/queue-fix/' + name) { inputs['queue-' + name] = area + '/queue-fix/' + name }
	}
	for name in os.ls(area)! {
		if (name.starts_with('queue-sample-') || name.starts_with('qmp-queue-') || name.starts_with('queue-host-snapshot-')) && name.ends_with('.json') {
			inputs[name] = area + '/' + name
		}
	}
	for arch in ['arm', 'x86'] {
		for name in ['source-' + arch + '.diff', 'committed-' + arch + '.log', 'committed-' + arch + '.status', 'clean-' + arch + '.log', 'clean-' + arch + '.status', 'head-' + arch + '.log', 'head-' + arch + '.status'] {
			inputs['queue-' + name] = area + '/queue-fix/' + name
		}
		for flavor in ['track', 'prod'] {
			name := 'inputs-' + arch + '-' + flavor + '.sha256'
			if os.exists(area + '/queue-fix/' + name) { inputs['queue-' + name] = area + '/queue-fix/' + name }
		}
	}
	mut flat := map[string]string{}
	for name, path in inputs {
		if os.is_dir(path) {
			for file in ['receipt.json', 'serial.log', 'inputs.json', 'fixture.o.compiler.json', 'init.compiler.json'] {
				if os.is_file(path + '/' + file) { flat[name + '.' + file] = path + '/' + file }
			}
		} else { flat[name] = path }
	}
	os.write_file(area + '/queue-publication-inputs.json', json2.encode(flat, prettify: true) + '\n')!
	println('Updated historical attempts and queue diagnosis publication map; selection unchanged')
}
