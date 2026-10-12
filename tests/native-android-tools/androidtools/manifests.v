// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import encoding.xml
import hosttest
import json2
import os

fn read_value(path string) !ah.Value {
	contents := os.read_file(path)!
	hosttest.module_decode_utf8(contents)!
	return json2.decode[ah.Value](contents, strict: true)!
}

fn inspect_jar(path string) !ah.DexInfo {
	info := jar_info(path)!
	return ah.DexInfo{classes: info.classes, callsites: info.callsites}
}

pub fn validate_boot_provenance(root string, manifest ah.Value, payloads ah.Value) ! {
	boothost.validate_native_provenance(root, manifest, payloads, inspect_jar)!
}

pub fn read_runtime(overlay string, kind string) !ah.Value {
	manifest := read_overlay(overlay, kind)!
	if kind == 'atl' && os.exists(overlay + '/art-runtime-manifest.json') { validate_art_pair(read_overlay(overlay, 'art')!, manifest)! }
	return manifest
}

pub fn read_overlay(overlay string, kind string) !ah.Value {
	if kind !in ['art', 'bionic', 'atl'] { return error('unknown Android overlay kind') }
	bionic := kind == 'bionic'
	atl := kind == 'atl'
	path := ah.manifest_path(overlay, bionic, atl)!
	manifest := read_value(path) or { return error('invalid ' + if atl { 'ATL' } else if bionic { 'Bionic' } else { 'ART' } + ' runtime manifest: ' + path) }
	validate_overlay(overlay, manifest, kind)!
	return manifest
}

fn first_font(root xml.XMLNode) ?xml.XMLNode {
	for family in root.children {
		if family is xml.XMLNode && family.name == 'family' && (family.attributes['xmlns'] or { '' }) == '' {
			for font in family.children {
				if font is xml.XMLNode && font.name == 'font' && (font.attributes['xmlns'] or { '' }) == '' { return font }
			}
		}
	}
	return none
}

pub fn validate_fonts(path string) ! {
	fonts := xml.XMLDocument.from_file(path) or { return error('ATL framework resources or Android font map are invalid') }
	if fonts.root.name != 'familyset' || (fonts.root.attributes['xmlns'] or { '' }) != '' { return error('ATL Android font map is incomplete') }
	font := first_font(fonts.root) or { return error('ATL Android font map is incomplete') }
	mut text := ''
	for content in font.children {
		if content is string { text += content }
		else if content is xml.XMLCData { text += content.text }
		else if content is xml.XMLNode { break }
	}
	if boothost.unicode_strip(text) == '' { return error('ATL Android font map is incomplete') }
}

pub fn validate_overlay(overlay string, manifest ah.Value, kind string) ! {
	bionic := kind == 'bionic'
	atl := kind == 'atl'
	seen := ah.validate_runtime(overlay, root() + '/build-support/android', manifest, bionic, atl)!
	if bionic { ah.validate_bionic_aliases(manifest, seen)! }
	if kind == 'art' && 'bootclasspath' in manifest.object() {
		validate_boot_provenance(overlay, ah.field(manifest.object(), 'bootclasspath'), ah.field(manifest.object(), 'files'))!
	}
	if atl {
		ah.validate_atl_metadata(root() + '/build-support/android', manifest, seen)!
		mut records := map[string]ah.Value{}
		for record in ah.field(manifest.object(), 'files').items() { records[ah.field(record.object(), 'path').text()] = record }
		for name in seen {
			if !name.ends_with('.jar') { continue }
			info := jar_info(ah.inside(overlay, ah.relative(ah.Value(name))!)!) or {
				if err is ah.ZipError || err.msg().starts_with('ValueError: ') || err.msg().starts_with('Unicode') { return error('ATL runtime has an invalid framework DEX JAR: ' + name) }
				return err
			}
			ah.validate_atl_dex_receipt(name, records[name]!, u64(info.classes.len), info.callsites)!
		}
		resources := ah.open_archive(overlay + '/usr/lib/java/dex/android_translation_layer/framework-res.apk') or { return error('ATL framework resources or Android font map are invalid') }
		if 'AndroidManifest.xml' !in resources.names() || 'resources.arsc' !in resources.names() { return error('ATL framework resources APK is incomplete') }
		validate_fonts(overlay + '/usr/share/atl/system/etc/fonts.xml')!
	}
}

pub fn apply_runtime(overlay string, runtime string, manifest ah.Value, kind string) !ah.Value {
	if !boothost.receipt_equal(read_overlay(overlay, kind)!, manifest) { return error('ART runtime manifest changed between verification and installation') }
	ah.install_runtime(overlay, runtime, manifest, kind == 'bionic', kind == 'atl')!
	return manifest
}

pub fn validate_art_pair(art ah.Value, atl ah.Value) ! {
	mut records := map[string]ah.Value{}
	for record in ah.field(art.object(), 'files').items() { records[ah.field(record.object(), 'path').text()] = record }
	for manifest in [art, atl] {
		if !boothost.receipt_equal(ah.field(manifest.object(), 'androidfw_configuration_api'), ah.Value(1)) { return error('ATL\'s androidfw header and linked provider differ from the selected ART; rebuild ATL') }
	}
	if !boothost.receipt_equal(ah.field(atl.object(), 'androidfw_patch_sha256'), ah.field(art.object(), 'patch_sha256')) { return error('ATL\'s androidfw header and linked provider differ from the selected ART; rebuild ATL') }
	for key, name in {'androidfw_header_sha256': 'usr/include/androidfw/androidfw_c_api.h', 'androidfw_library_sha256': 'usr/lib/art/libandroidfw.so'} {
		if !boothost.receipt_equal(ah.field(atl.object(), key), ah.field((records[name] or { ah.Value(json2.null) }).object(), 'sha256')) { return error('ATL\'s androidfw header and linked provider differ from the selected ART; rebuild ATL') }
	}
}
