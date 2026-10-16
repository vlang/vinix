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

// Retire this result's owned metadata; published files are independent.
pub fn (mut info CompositionInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
		for source in info.sources { source.id.free(); source.catalog_sha256.free() }
		(&array(&info.sources)).free()
	}
	info = CompositionInfo{}
}

struct CompositionPlan {
	text string
	provenance string
mut:
	info CompositionInfo
}

fn (mut plan CompositionPlan) close() {
	unsafe { plan.text.free(); plan.provenance.free() }
	plan.info.close()
	plan = CompositionPlan{}
}

fn composition_append(mut bytes []u8, text string) {
	unsafe { bytes.push_many(text.str, text.len) }
}

fn composition_result(info CompositionInfo, directory string) CompositionInfo {
	mut sources := []CompositionSource{cap: info.sources.len}
	for source in info.sources { sources << CompositionSource{ id: source.id.clone(), catalog_sha256: source.catalog_sha256.clone() } }
	return CompositionInfo{ directory: directory.clone(), catalog: directory + '/catalog.json',
		catalog_sha256: info.catalog_sha256.clone(), architectures: review_strings(info.architectures), package_count: info.package_count, sources: sources }
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

// Each decoded source is retired before reading the next. Only selected JSON
// bytes, bounded by the output metadata limit, and owned provenance survive.
fn prepare_composition(sources []CatalogSource, architecture string) !CompositionPlan {
	if sources.len == 0 || sources.len > 64 { return error('catalog composition requires between 1 and 64 named catalogs') }
	mut ordered := sources.clone()
	defer { unsafe { (&array(&ordered)).free() } }
	ordered.sort(a.id < b.id)
	mut architectures := []string{}
	mut records := []CompositionSource{cap: ordered.len}
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut text := ''
	mut provenance := ''
	mut digest := ''
	mut accepted := false
	defer {
		if !accepted {
			mut retired := CompositionPlan{ text: text, provenance: provenance,
				info: CompositionInfo{ catalog_sha256: digest, architectures: architectures, sources: records } }
			retired.close()
		}
	}
	mut count := 0
	mut previous := ''
	for index, source in ordered {
		if !identifier(source.id) || source.id == previous { return error('catalog composition requires distinct valid profile IDs') }
		previous = source.id
		input_text := read_metadata(source.catalog)!
		defer { unsafe { input_text.free() } }
		input := catalog_recipe(input_text)!
		defer { close_decoded_catalog(input) }
		if architecture == '' {
			if architectures.len == 0 { architectures = review_strings(input.architectures) }
			if architectures != input.architectures { return error('composed catalogs must cover the same architectures: ${source.id}') }
		} else {
			if architecture !in input.architectures { return error('catalog profile ${source.id} does not support requested architecture ${architecture}') }
			if architectures.len == 0 { architectures << architecture.clone() }
		}
		if index == 0 {
			composition_append(mut bytes, '{"format":1,"architectures":')
			json2.encode_append(architectures, mut bytes)
			composition_append(mut bytes, ',"packages":[')
		}
		for item in input.packages {
			if architecture != '' && item.recipe.manifest.architecture !in [architecture, 'all'] { continue }
			if count == 4096 { return error('composed catalog exceeds the 4096 package limit') }
			if count > 0 { bytes << `,` }
			prefix := source.id + '/' + item.source
			defer { unsafe { prefix.free() } }
			json2.encode_append(CatalogImport{ source: prefix, recipe: item.recipe }, mut bytes)
			if bytes.len > max_metadata { return error('composed catalog exceeds metadata limit') }
			count++
		}
		canonical := publisher_json(input)
		defer { unsafe { canonical.free() } }
		records << CompositionSource{ id: source.id.clone(), catalog_sha256: index_digest(canonical) }
	}
	composition_append(mut bytes, ']}')
	// This checks duplicate package identities, complete target coverage and
	// runtime closures again, including any conflict introduced by composition.
	merged := catalog_recipe(unsafe { tos(&u8(bytes.data), bytes.len) })!
	defer { close_decoded_catalog(merged) }
	text = publisher_json(merged)
	if text.len > max_metadata { return error('composed catalog exceeds metadata limit') }
	digest = index_digest(text)
	provenance = publisher_json(CompositionRecord{ catalog_sha256: digest, architectures: architectures, package_count: merged.packages.len, sources: records })
	accepted = true
	return CompositionPlan{ text: text, provenance: provenance,
		info: CompositionInfo{ catalog_sha256: digest, architectures: architectures, package_count: merged.packages.len, sources: records } }
}

fn compose_catalog_selected(sources []CatalogSource, destination string, architecture string, options CatalogOptions) !CompositionInfo {
	mut plan := prepare_composition(sources, architecture)!
	defer { plan.close() }
	target := export_target(destination, 'catalog composition')!
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	disk_check(options.available_space(parent)!, u64(plan.text.len + plan.provenance.len) + 4 * 1024 * 1024, 64 * 1024 * 1024)!
	stage := export_stage(parent, '.vinix-composition')!
	catalog_path := stage + '/catalog.json'
	provenance_path := stage + '/composition.json'
	defer { unsafe { stage.free(); catalog_path.free(); provenance_path.free() } }
	mut published := false
	defer { if !published { os.rmdir_all(stage) or {} } }
	options.checkpoint('created', stage)!
	atomic_write(catalog_path, plan.text)!
	atomic_write(provenance_path, plan.provenance)!
	sync_directory(stage)!
	options.checkpoint('ready', stage)!
	staged_text := read_metadata(catalog_path)!
	defer { unsafe { staged_text.free() } }
	staged_provenance := read_metadata(provenance_path)!
	defer { unsafe { staged_provenance.free() } }
	if staged_text != plan.text || staged_provenance != plan.provenance {
		return error('catalog composition changed before publication')
	}
	publish_new_directory(stage, target, 'catalog composition')!
	published = true
	sync_directory(parent) or { return error('catalog composition published at ${target}, but its directory flush failed: ${err}') }
	return composition_result(plan.info, target)
}
