// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import encoding.hex
import json2
import os

fn field_text(row map[string]ah.Value, name string) string { return ah.field(row, name).text() }

fn binding_arguments(row map[string]ah.Value) ![]ah.Value {
	mut result := []ah.Value{}
	if 'arguments' in row {
		for descriptor in ah.field(row, 'arguments').items() {
			pair := descriptor.items()
			if pair.len != 2 { return error('invalid native binding argument') }
			kind := pair[0].text()
			result << if kind == 'json' { json2.decode[ah.Value](pair[1].text(), strict: true)! } else { pair[1] }
		}
	} else {
		result << ah.field(row, 'paths').items()
		result << ah.field(row, 'values').items()
	}
	return result
}

pub fn binding_request(row map[string]ah.Value) !ah.Value {
	kind := if 'module' in row { field_text(row, 'module') } else { 'art' }
	operation := field_text(row, 'operation')
	if kind == 'zip' {
		path := field_text(row, 'path')
		if operation == 'write' {
			mut writer := ah.archive_writer(path)!
			defer { writer.close() or {} }
			for entry in ah.field(row, 'entries').items() {
				pair := entry.items()
				writer.add(ah.ArchiveItem{name: pair[0].text(), data: hex.decode(pair[1].text())!})!
			}
			writer.close()!
			return ah.Value(json2.null)
		}
		archive := ah.open_archive(path)!
		mut files := map[string]ah.Value{}
		for name in ah.field(row, 'names').items() { files[name.text()] = archive.read(name.text())!.hex() }
		return ah.Value({'names': ah.Value(archive.names().map(ah.Value(it))), 'files': ah.Value(files)})
	}
	if 'attributes' in row {
		constants := if kind == 'boot' { boothost.constants() } else if kind == 'musl' { musl_constants() } else if kind == 'builder' { {'ROOT': ah.Value(root()), 'SUPPORT': ah.Value(root() + '/build-support/android'), 'LOCK': ah.Value(root() + '/build-support/android/packages.lock.json'), 'MIRROR': ah.Value(mirror), 'REPOSITORIES': ah.Value(repositories.map(ah.Value(it))), 'ROOT_PACKAGES': ah.Value(root_packages.map(ah.Value(it))), 'CALCULATOR': calculator_metadata(), 'PREFIX': ah.Value(runtime_prefix), 'ARCHITECTURE': ah.Value('aarch64'), 'REQUIRED': ah.Value(required_runtime_files.map(ah.Value(it)))} } else { ah.runtime_constants(root() + '/build-support/android') }
		mut selected := map[string]ah.Value{}
		for value in ah.field(row, 'attributes').items() { selected[value.text()] = constants[value.text()] or { return error('unknown native attribute: ' + value.text()) } }
		return ah.Value(selected)
	}
	a := binding_arguments(row)!
	if kind == 'builder' {
		if 'patches' in row { return error('native builder fixtures use typed V StageHooks') }
		match operation {
			'sha256' { return ah.Value(ah.digest(a[0].text())!) }
			'download' { return ah.Value(package_download(a[0].text(), a[1].text(), if a.len > 2 { a[2].text() } else { '' })!) }
			'make_lock' { return make_package_lock(a[0].text(), a[1].text())! }
			'fetch_package' { return ah.Value(fetch_one(a[0], a[1].text(), a[2])!) }
			'extract_apk' { extract_apk(a[0].text(), a[1].text())! }
			'materialize_library_links' { materialize_library_links(a[0].text())! }
			'relocate_configuration' { relocate_configuration(a[0].text())! }
			'calculator_apk' { return ah.Value(calculator_apk(a[0].text())!) }
			'stage' {
				mut values := map[string]ah.Value{}
				for key, value in a[0].object() { pair := value.items(); values[key] = if pair.len == 2 { pair[1] } else { value } }
				options := RuntimeOptions{build_dir: field_text(values, 'build_dir'), art_runtime: field_text(values, 'art_runtime'), bionic_runtime: field_text(values, 'bionic_runtime'), atl_runtime: field_text(values, 'atl_runtime'), with_calculator: ah.field(values, 'with_calculator') is bool && ah.field(values, 'with_calculator') as bool}
				return ah.Value(stage_runtime(options, a[1], a[2].text())!)
			}
			else { return error('unknown native builder operation: ' + operation) }
		}
		return ah.Value(json2.null)
	}
	if kind == 'boot' {
		match operation {
			'dex_info' { info := ah.dex_info(hex.decode(a[0].text())!)!; return ah.Value([ah.Value(info.classes.map(ah.Value(it))), ah.Value(info.callsites)]) }
			'jar_info' { info := jar_info(a[0].text())!; return ah.Value([ah.Value(info.classes.map(ah.Value(it))), ah.Value(info.callsites)]) }
			'class_subset' { class_subset(a[0].text(), a[1].items().map(it.text()), a[2].text())! }
			'package_jar' { package_boot_jar(a[0].text(), a[1].text(), a[2].text())! }
			'extract_member' { extract_member(a[0].text(), a[1].text(), a[2].text())! }
			'download' { return ah.Value(boot_download(a[0], a[1].text())!) }
			'digest' { return ah.Value(ah.digest(a[0].text())!) }
			'validate_provenance' { validate_boot_provenance(a[0].text(), a[1], if a.len > 2 { a[2] } else { ah.Value(json2.null) })! }
			'cache_identity' { return boot_cache_identity()! }
			'prepare' { prepared := prepare_boot(a[0].text(), if a.len > 1 { a[1].text() } else { 'java' })!; return ah.Value([ah.Value(prepared.jars), prepared.manifest]) }
			'stage' { return stage_boot(a[0].text(), a[1].text(), if a.len > 2 { a[2].text() } else { 'java' })! }
			'build_probe' { build_boot_probe(a[0].text(), a[1].text(), if a.len > 2 { a[2].text() } else { 'java' }, if a.len > 3 { a[3].text() } else { 'javac' })! }
			else { return error('unknown native bootclasspath operation: ' + operation) }
		}
		return ah.Value(json2.null)
	}
	if kind == 'musl' {
		c := musl_constants()
		overrides := ah.field(row, 'overrides').object()
		musl := (overrides['MUSL'] or { c['MUSL']! }).text()
		patch := (overrides['PATCH'] or { c['PATCH']! }).text()
		return match operation {
			'digest' { ah.Value(ah.digest(a[0].text())!) }
			'source_patches' { musl_source_patches(musl, patch)! }
			'read_manifest' { read_musl(a[0].text(), musl, patch)! }
			else { return error('unknown native musl receipt operation: ' + operation) }
		}
	}
	if kind == 'shutil' {
		if operation == 'copy2' {
			destination := if os.is_dir(a[1].text()) { a[1].text() + '/' + os.file_name(a[0].text()) } else { a[1].text() }
			copy_tree(a[0].text(), destination, false)!
		} else if operation == 'copytree' { copy_tree(a[0].text(), a[1].text(), false)! }
		else { return error('unknown native copy operation') }
		return ah.Value(a[1].text())
	}
	if kind != 'art' { return error('unknown native Android binding module: ' + kind) }
	match operation {
		'read_manifest', 'read_bionic_manifest', 'read_atl_manifest', '_read_manifest' {
			selected := if operation == 'read_atl_manifest' || (operation == '_read_manifest' && a.len > 2 && a[2] is bool && a[2] as bool) { 'atl' } else if operation == 'read_bionic_manifest' || (operation == '_read_manifest' && a.len > 1 && a[1] is bool && a[1] as bool) { 'bionic' } else { 'art' }
			return if operation == '_read_manifest' { read_overlay(a[0].text(), selected)! } else { read_runtime(a[0].text(), selected)! }
		}
		'apply', 'apply_bionic', 'apply_atl' { return apply_runtime(a[0].text(), a[1].text(), a[2], if operation == 'apply_atl' { 'atl' } else if operation == 'apply_bionic' { 'bionic' } else { 'art' })! }
		'validate_atl_art_pair' { validate_art_pair(a[0], a[1])! }
		'_digest' { return ah.Value(ah.digest(a[0].text())!) }
		'_regular' { ah.regular(a[0].text())! }
		'_relative' { return ah.Value(ah.relative(a[0])!) }
		'_inside' { return ah.Value(ah.inside(a[0].text(), a[1].text())!) }
		'_elf' { ah.check_elf(a[0].text(), a.len > 1 && a[1] is bool && a[1] as bool)! }
		'configuration_probe_digest' { return ah.Value(ah.configuration_probe_digest(root() + '/build-support/android')!) }
		'dex_adapter_digest' { return ah.Value(ah.dex_adapter_digest(root() + '/build-support/android')!) }
		else { return error('unknown native ART operation: ' + operation) }
	}
	return ah.Value(json2.null)
}

pub fn binding_cli(encoded string) !int {
	request := json2.decode[ah.Value](encoded, strict: true)!.object()
	result := binding_request(request) or {
		mut kind := 'RuntimeError'
		mut message := err.msg()
		if err is ah.FileError || err.code() in [2, 13, 20, 21, 22, 40] {
			kind = match err.code() { 2 { 'FileNotFoundError' } 13 { 'PermissionError' } 20 { 'NotADirectoryError' } 21 { 'IsADirectoryError' } else { 'OSError' } }
		} else if err is ah.ZipError { kind = 'BadZipFile' }
		else if err.msg().starts_with('ValueError: ') { kind = 'ValueError'; message = message[12..] }
		println(ah.encode(ah.Value({'kind': ah.Value(kind), 'message': ah.Value(message), 'errno': if kind.ends_with('Error') && err.code() != 0 { ah.Value(err.code()) } else { ah.Value(json2.null) }, 'run_calls': ah.Value(0)})))
		return 0
	}
	println(ah.encode(ah.Value({'result': result, 'run_calls': ah.Value(0)})))
	return 0
}
