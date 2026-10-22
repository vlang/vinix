import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const old = '/Users/alex/.cache/vinix-linux-compat/procns-20261016'
const out = root + '/tests/linux-compat/results/2026-10-22'

struct Evidence {
	kernel_commit string = 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
	candidate_commit string
	integration_commit string
	baseline_commit string = 'f3a29a7aa558d0325d5602f39f503d3449e5b56f'
	files map[string]string
	source_inputs map[string]string
	retained_inputs map[string]string
}

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn publish(path string, name string, mut files map[string]string) {
	data := os.read_bytes(path) or { panic(err) }
	destination := out + '/procns-' + name
	if os.exists(destination) { assert (os.read_bytes(destination) or { panic(err) }) == data } else { os.write_file_array(destination, data) or { panic(err) } }
	files['procns-' + name] = sha256.sum(data).hex()
}

fn main() {
	os.mkdir_all(out)!
	mut files := map[string]string{}
	mut retained := map[string]string{}
	selected := json2.decode[map[string]string](os.read_file(area + '/selected-runs.json')!)!
	for suffix in ['arm', 'x86'] {
		for file in ['fixture.c', 'fixture.o.compiler.json', 'init.compiler.json', 'serial.c', 'serial.o.compiler.json'] {
			publish(area + '/states/build-init2-' + suffix + '/' + file, suffix + '-' + file, mut files)
		}
		for phase in ['before', 'after', 'reference'] {
			state := selected[suffix + '-' + phase] or { panic('Missing selected run') }
			publish(state + '/serial.log', suffix + '-' + phase + '.log', mut files)
			publish(state + '/receipt.json', suffix + '-' + phase + '.json', mut files)
			for file in ['init', 'kernel/bin/vinix', 'fixture.c'] {
				path := state + '/' + file
				if os.is_file(path) { retained[path] = digest(path) }
			}
		}
		for flavor in ['track', 'prod'] {
			publish(area + '/build-' + suffix + '-' + flavor + '.log', 'build-' + suffix + '-' + flavor + '.log', mut files)
			publish(area + '/build-' + suffix + '-' + flavor + '.log.status', 'build-' + suffix + '-' + flavor + '.status', mut files)
			for file in ['kernel/bin/vinix', 'blob.c'] {
				path := area + '/' + suffix + '-' + flavor + '/' + file
				retained[path] = digest(path)
			}
		}
	}
	for name in ['allocs.log', 'allocs.log.status', 'allocs-base.log', 'allocs-base.log.status', 'allocs-comparison.log', 'lifetime-review.md', 'generated-review-inputs.sha256', 'generated-review-arm-excerpts.c', 'generated-review-x86-excerpts.c', 'generated-review-comparison.log', 'generated-review.v', 'baseline-inputs.json', 'baseline-inputs.v', 'source-manifest.json', 'source-manifest2.json', 'reference-source-manifest.json', 'selected-runs.json', 'qualification-summary.json', 'qualification-summary.md', 'build.v', 'qualify.v', 'qualify2.v', 'reference.v', 'compile-init.v', 'compile-init2.v', 'publish.v', 'compare-allocs.v'] {
		publish(area + '/' + name, name, mut files)
	}
	for name in ['base.txt', 'manage.v', 'build-before-arm-track-mp.log', 'build-before-arm-track-mp.log.status', 'build-before-x86-track.log', 'build-before-x86-track.log.status'] {
		publish(old + '/' + name, 'baseline-' + name, mut files)
	}
	for phase in ['arm', 'x86'] {
		state := area + '/' + if phase == 'arm' { 'ra' } else { 'x86-regressions-final' }
		publish(state + '/receipt.json', phase + '-regressions.json', mut files)
		for name in ['runtime', 'namespace', 'readlinkempty', 'proctask', 'procpid', 'cloneipc'] {
			path := if phase == 'arm' { state + '/' + name + '/serial.log' } else { state + '/' + name + '-serial.log' }
			publish(path, phase + '-regression-' + name + '.log', mut files)
		}
		publish(area + '/regressions-' + phase + '/runtime/serial.log', phase + '-initial-compressed-boot.log', mut files)
		publish(area + '/regressions-' + phase + '-plain/receipt.json', phase + '-initial-long-path-regressions.json', mut files)
		publish(area + '/regressions-' + phase + '-plain/readlinkempty/serial.log', phase + '-initial-long-path-readlinkempty.log', mut files)
		for initial in ['before', 'after', 'reference'] {
			first := area + '/states/final-' + initial + '-' + phase
			publish(first + '/serial.log', phase + '-initial-' + initial + '.log', mut files)
			publish(first + '/receipt.json', phase + '-initial-' + initial + '.json', mut files)
		}
	}
	publish(area + '/states/diagnostic-reference-x86/serial.log', 'x86-reference-errno-diagnostic.log', mut files)
	publish(area + '/states/diagnostic-reference-x86/receipt.json', 'x86-reference-errno-diagnostic.json', mut files)
	publish(area + '/frozen/procnsfixture/core.v', 'initial-fixture.v', mut files)
	publish(area + '/diagnostic/procnsfixture/core.v', 'errno-diagnostic-fixture.v', mut files)
	for name, path in {
		'initial-x86-retention.log': old + '/states/qualify-after-x86-track/serial.log'
		'initial-x86-proctask.log': old + '/states/regression-x86/proctask/serial.log'
	} { publish(path, name, mut files) }
	for name in ['source-manifest3.json', 'queue-candidate-inputs.json', 'qualify3.v', 'integration-commit.txt'] {
		publish(area + '/' + name, name, mut files)
	}
	for name in ['final-audit.v', 'publication-preflight.v', 'final-publication-preflight.log', 'final-publication-preflight.status'] {
		publish(area + '/' + name, name, mut files)
	}
	publish(area + '/queue-fix/commit.txt', 'queue-commit.txt', mut files)
	for suffix in ['arm', 'x86'] {
		for flavor in ['track', 'prod'] {
			publish(area + '/queue-fix/build-' + suffix + '-' + flavor + '.log', 'queue-build-' + suffix + '-' + flavor + '.log', mut files)
			publish(area + '/queue-fix/build-' + suffix + '-' + flavor + '.log.status', 'queue-build-' + suffix + '-' + flavor + '.status', mut files)
		}
	}
	for map_name in ['publication-map.json', 'perf-publication-inputs.json', 'desktop-publication-inputs.json', 'x86-regressions-publication-inputs.json', 'queue-publication-inputs.json', 'queue-perf-publication-inputs.json', 'queue-desktop-publication-inputs.json'] {
		publication := json2.decode[map[string]string](os.read_file(area + '/' + map_name)!)!
		for name, path in publication {
			assert name != '' && !name.contains('/') && !name.contains('..')
			publish(path, name, mut files)
		}
		publish(area + '/' + map_name, map_name, mut files)
	}
	mut inputs := map[string]string{}
	for path in ['kernel/fs/procfs.v', 'kernel/fs/namespaces.v', 'kernel/fs/vfs.v', 'kernel/fs/removed.v', 'tests/linux-compat/procnsfixture/core.v', 'tests/linux-compat/procnsreferenceinit/core.v', 'tests/linux-compat/procns-reference.v', 'tests/linux-compat/procns-check.v', 'tests/linux-compat/run.v'] {
		inputs[path] = digest(root + '/' + path)
	}
	for path in ['/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', area + '/qualify', area + '/qualify2', area + '/qualify3', area + '/reference', area + '/arm-cc', area + '/sdk/usr/lib/libc.a', '/opt/homebrew/bin/x86_64-linux-musl-gcc'] { retained[path] = digest(path) }
	os.write_file(out + '/procns-evidence.json', json2.encode(Evidence{candidate_commit: os.read_file(area + '/queue-fix/commit.txt')!.trim_space(), integration_commit: os.read_file(area + '/integration-commit.txt')!.trim_space(), files: files, source_inputs: inputs, retained_inputs: retained}, prettify: true) + '\n')!
	println('Published ${files.len} procns evidence files')
}
