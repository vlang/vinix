// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

pub struct CatalogSource {
pub:
	id string // directory namespace under the prepared roots
	catalog string // existing reviewed catalog lock
}

pub struct CompositionSource {
pub:
	id string
	catalog_sha256 string // canonical input lock, independent of host filename
}

pub struct CompositionInfo {
pub:
	format int = 1
	directory string
	catalog string
	catalog_sha256 string
	architectures []string
	package_count int
	sources []CompositionSource
}

struct CompositionRecord {
	format int = 1
	catalog_sha256 string
	architectures []string
	package_count int
	sources []CompositionSource
}

// Compose only complete, pinned catalogs. The sources remain in independent
// directory namespaces: neither payload bytes nor consumer trust are changed.
pub fn compose_catalog(sources []CatalogSource, destination string) !CompositionInfo {
	return compose_catalog_with(sources, destination, CatalogOptions{})
}

fn compose_catalog_with(sources []CatalogSource, destination string, options CatalogOptions) !CompositionInfo {
	return compose_catalog_selected(sources, destination, '', options)
}

// Explicitly select one host from complete reviewed inputs. Validate every
// input before selecting variants and retain its full digest in provenance.
pub fn compose_catalog_for(architecture string, sources []CatalogSource, destination string) !CompositionInfo {
	return compose_catalog_for_with(architecture, sources, destination, CatalogOptions{})
}

fn compose_catalog_for_with(architecture string, sources []CatalogSource, destination string, options CatalogOptions) !CompositionInfo {
	if architecture !in ['aarch64', 'x86_64'] { return error('catalog composition target must be aarch64 or x86_64') }
	return compose_catalog_selected(sources, destination, architecture, options)
}

fn compose_catalog_selected(sources []CatalogSource, destination string, architecture string, options CatalogOptions) !CompositionInfo {
	if sources.len == 0 || sources.len > 64 { return error('catalog composition requires between 1 and 64 named catalogs') }
	mut ordered := sources.clone()
	ordered.sort(a.id < b.id)
	mut architectures := []string{}
	mut imports := []CatalogImport{}
	mut records := []CompositionSource{}
	mut previous := ''
	for source in ordered {
		if !identifier(source.id) || source.id == previous { return error('catalog composition requires distinct valid profile IDs') }
		previous = source.id
		input := catalog_recipe(read_metadata(source.catalog)!)!
		if architecture == '' {
			if architectures.len == 0 { architectures = input.architectures.clone() }
			if architectures != input.architectures { return error('composed catalogs must cover the same architectures: ${source.id}') }
		} else {
			if architecture !in input.architectures { return error('catalog profile ${source.id} does not support requested architecture ${architecture}') }
			if architectures.len == 0 { architectures << architecture }
		}
		for item in input.packages {
			if architecture != '' && item.recipe.manifest.architecture !in [architecture, 'all'] { continue }
			if imports.len == 4096 { return error('composed catalog exceeds the 4096 package limit') }
			imports << CatalogImport{ source: source.id + '/' + item.source, recipe: item.recipe }
		}
		records << CompositionSource{ id: source.id, catalog_sha256: index_digest(json2.encode(input) + '\n') }
	}
	// This checks duplicate package identities, complete target coverage and
	// runtime closures again, including any conflict introduced by composition.
	merged := catalog_recipe(json2.encode(CatalogRecipe{ format: 1, architectures: architectures, packages: imports }))!
	text := json2.encode(merged) + '\n'
	if text.len > max_metadata { return error('composed catalog exceeds metadata limit') }
	digest := index_digest(text)
	provenance := json2.encode(CompositionRecord{ catalog_sha256: digest, architectures: architectures,
		package_count: merged.packages.len, sources: records }) + '\n'
	target := export_target(destination, 'catalog composition')!
	parent := os.dir(target)
	disk_check(options.available_space(parent)!, u64(text.len + provenance.len) + 4 * 1024 * 1024, 64 * 1024 * 1024)!
	stage := export_stage(parent, '.vinix-composition')!
	mut published := false
	defer { if !published { os.rmdir_all(stage) or {} } }
	options.checkpoint('created', stage)!
	atomic_write(stage + '/catalog.json', text)!
	atomic_write(stage + '/composition.json', provenance)!
	sync_directory(stage)!
	options.checkpoint('ready', stage)!
	if read_metadata(stage + '/catalog.json')! != text || read_metadata(stage + '/composition.json')! != provenance {
		return error('catalog composition changed before publication')
	}
	publish_new_directory(stage, target, 'catalog composition')!
	published = true
	sync_directory(parent) or { return error('catalog composition published at ${target}, but its directory flush failed: ${err}') }
	return CompositionInfo{ directory: target, catalog: target + '/catalog.json', catalog_sha256: digest,
		architectures: architectures, package_count: merged.packages.len, sources: records }
}
