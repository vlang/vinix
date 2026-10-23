import os

const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const root = '/Users/alex/code/vinix'
const bundle = root + '/tests/linux-compat/results/2026-10-23/prioquery-evidence'

fn main() {
	assert !os.exists(area + '/published-first')
	os.rename(bundle, area + '/published-first')!
	for path in [area + '/report.md', root + '/docs/linux-posix-qualification.md'] {
		mut text := os.read_file(path)!
		text = text.replace('Its nine negative controls', 'Its eleven negative controls')
		text += '\nThe first evidence audit rejected duplicate suffix matches for the frozen\nsource and build worktree. The corrected checker selects the architecture\nworktree explicitly and tests both ambiguity and missing-path refusals.\nThe failed audit is retained alongside the successful retry.\n'
		os.write_file(path, text)!
	}
	mut source := os.read_file(area + '/publish.v')!
	source = source.replace('"prepare-retry.v",', '"prepare-retry.v", "revise-publication.v",')
	os.write_file(area + '/publish-second.v', source)!
	mut finalizer := os.read_file(area + '/finalize.v')!
	finalizer = finalizer.replace('evidence-audit-first', 'evidence-audit-second')
	finalizer = finalizer.replace('publish-first', 'publish-second')
	finalizer = finalizer.replace('evidence-controls-third', 'evidence-controls-fifth')
	finalizer = finalizer.replace("area + '/evidence'", "area + '/evidence-fifth'")
	os.write_file(area + '/finalize-second.v', finalizer)!
}
