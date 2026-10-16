// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
}

fn composition_owned_fixture(count int, fault string) !(string, []CatalogSource) {
	work := os.real_path(os.temp_dir()) + '/vinix-composition-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work)!
	mut sources := []CatalogSource{cap: 2}
	for profile in ['alpha', 'beta']! {
		mut imports := []CatalogImport{cap: count * 2 + 1}
		for architecture in ['aarch64', 'x86_64']! {
			if fault == 'missing-host' && profile == 'beta' && architecture == 'x86_64' { continue }
			for i in 0 .. count {
				digits := i.str(); defer { unsafe { digits.free() } }
				id := (if fault == 'duplicate' && profile == 'beta' { 'alpha' } else { profile }) + '-item-' + digits
				imports << CatalogImport{ source: if fault == 'depth' { 'a/b/c/d/e/f/g/' + architecture } else { architecture }, recipe: RootRecipe{
					manifest: Package{ id: id, name: id.clone(), description: 'd'.repeat(2048), version: '1.0.0', architecture: architecture,
						kind: 'native', entrypoint: 'bin/app', license: 'MIT', permissions: ['files'], associations: ['text/plain'],
						dependencies: [Dependency{ id: profile + '-notice' }],
						files: [Payload{ path: 'bin/app', sha256: 'a'.repeat(64), bytes: 1, executable: true }] },
					entries: [RootEntry{ source: 'bin/app', path: 'bin/app' }] } }
			}
		}
		imports << CatalogImport{ source: 'shared', recipe: RootRecipe{
			manifest: Package{ id: profile + '-notice', name: 'Notice', version: '1.0.0', architecture: 'all', kind: 'data',
				license: 'Fixture-EULA', proprietary: true, firmware: true,
				files: [Payload{ path: 'NOTICE', sha256: 'b'.repeat(64), bytes: 1 }] }, entries: [RootEntry{ source: 'NOTICE', path: 'NOTICE' }] } }
		recipe := CatalogRecipe{ format: 1, architectures: if fault == 'missing-host' && profile == 'beta' { ['aarch64'] } else { ['aarch64', 'x86_64'] }, packages: imports }
		encoded := json2.encode(recipe)
		defer { close_decoded_catalog(recipe); unsafe { encoded.free() } }
		path := work + '/' + profile + '.json'
		os.write_file(path, if fault == 'schema' && profile == 'beta' { encoded.replace_once('"format":1', '"format":1,"unknown":true') } else { encoded })!
		sources << CatalogSource{ id: if fault == 'profile' && profile == 'beta' { '../beta'.clone() } else { profile.clone() }, catalog: path }
	}
	return work, sources
}

fn close_composition_sources(sources []CatalogSource) {
	unsafe { for source in sources { source.id.free(); source.catalog.free() }; (&array(&sources)).free() }
}

fn composition_owned_probe(sources []CatalogSource, architecture string) ! {
	mut plan := prepare_composition(sources, architecture)!
	defer { plan.close() }
}

fn composition_probe_once(sources []CatalogSource, architecture string, refused bool) {
	if _ := composition_owned_probe(sources, architecture) { assert !refused }
	else { message := err.msg(); unsafe { message.free(); err.free() }; assert refused }
}

struct CompositionProbeCase { fault string architecture string }

fn test_composition_planning_retires_inputs_results_and_refusal_scratch() {
	for count in [1, 32]! {
		for selection in [CompositionProbeCase{}, CompositionProbeCase{ architecture: 'aarch64' }, CompositionProbeCase{ architecture: 'x86_64' },
			CompositionProbeCase{ fault: 'schema', architecture: 'aarch64' }, CompositionProbeCase{ fault: 'duplicate', architecture: 'aarch64' },
			CompositionProbeCase{ fault: 'missing-host', architecture: 'x86_64' }, CompositionProbeCase{ fault: 'depth', architecture: 'aarch64' },
			CompositionProbeCase{ fault: 'profile', architecture: 'aarch64' }] {
			fault := selection.fault
			work, sources := composition_owned_fixture(count, fault)!
			defer { os.rmdir_all(work) or {}; close_composition_sources(sources); unsafe { work.free() } }
			architecture := selection.architecture
			composition_probe_once(sources, architecture, fault != '')
			mut maximum := u64(0); mut records := u32(0)
			cycles := $if track_heap ? { 128 } $else { 4 }
			for _ in 0 .. cycles {
				$if track_heap ? { C.vinix_heap_begin() }
				composition_probe_once(sources, architecture, fault != '')
				$if track_heap ? {
					kept := C.vinix_heap_end(); allocations := C.vinix_heap_count()
					if kept > maximum { maximum = kept }; if allocations > records { records = allocations }
				}
			}
			label := 'COMPOSITION OWNERSHIP variants-per-host=' + count.str() + ' target=' + if architecture == '' { 'both' } else { architecture } + ' fault=' + if fault == '' { 'none' } else { fault }
			$if track_heap ? {
				println(label + ' retained=' + maximum.str() + ' allocations=' + records.str())
				assert maximum == 0 && records == 0
			} $else { println(label + ' functional-cycles=' + cycles.str() + ' PASS') }
		}
	}
	println('COMPOSITION OWNERSHIP strict/selected planning and late metadata/identity/host/depth/profile refusals retire owned scratch PASS')
}

fn test_composition_plan_and_public_result_survive_retired_source_arguments_and_other_owners() {
	work, sources := composition_owned_fixture(32, '')!
	defer { os.rmdir_all(work) or {}; unsafe { work.free() } }
	mut plan := prepare_composition(sources, 'aarch64')!
	mut second := prepare_composition(sources, 'aarch64')!
	mut info := composition_result(plan.info, '/review/composed')
	catalog_digest := index_digest(plan.text)
	provenance_digest := index_digest(plan.provenance)
	defer { unsafe { catalog_digest.free(); provenance_digest.free() } }
	assert catalog_digest == '7cefe79d434695991a6fe7526d0aa45c91af7e5a90cb94921a8b06525aee24dd'
	assert provenance_digest == '89376c4a33384af4e6b7149b5f9b57ceb37dd8606b05336f98158249edb084f6'
	golden := os.getenv('VINIX_COMPOSITION_GOLDEN')
	if golden != '' {
		assert plan.text == os.read_file(golden + '/alpha.json-aarch64-catalog.json')!
		assert plan.provenance == os.read_file(golden + '/alpha.json-aarch64-composition.json')!
	}
	close_composition_sources(sources)
	assert plan.text == second.text && plan.provenance == second.provenance
	plan.close(); plan.close()
	assert second.info.architectures == ['aarch64'] && second.info.sources.map(it.id) == ['alpha', 'beta']
	assert second.info.package_count == 66 && second.info.sources.all(it.catalog_sha256.len == 64)
	decoded := catalog_recipe(second.text)!
	assert decoded.packages.len == 66 && decoded.packages.filter(it.recipe.manifest.kind == 'data').all(it.recipe.manifest.firmware && it.recipe.manifest.proprietary)
	close_decoded_catalog(decoded)
	second.close()
	assert info.directory == '/review/composed' && info.catalog == '/review/composed/catalog.json'
	assert info.architectures == ['aarch64'] && info.sources.map(it.id) == ['alpha', 'beta'] && info.catalog_sha256.len == 64
	info.close(); info.close()
	assert info.directory == '' && info.catalog_sha256 == '' && info.sources.len == 0 && info.architectures.len == 0
	println('COMPOSITION OWNERSHIP independent plans and closeable replies survive retired inputs; canonical bytes, disclosures and idempotent close PASS')
}
