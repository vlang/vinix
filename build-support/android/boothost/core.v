module boothost

import androidhost as ah
import encoding.hex
import json2
import os

pub struct BindingError {
pub:
	value map[string]ah.Value
}

pub fn (e BindingError) msg() string { return ah.field(e.value, 'message').text() }

pub fn (e BindingError) code() int { return 0 }

pub struct PolicyError {
pub:
	kind    string
	message string
}

pub fn (e PolicyError) msg() string { return e.message }

pub fn (e PolicyError) code() int { return 0 }

pub struct PayloadError {
pub:
	message string
	cause   map[string]ah.Value
}

pub fn (e PayloadError) msg() string { return e.message }

pub fn (e PayloadError) code() int { return 0 }

fn fail(message string) IError { return PolicyError{'RuntimeError', message} }

fn key(row map[string]ah.Value, name string) !ah.Value {
	return row[name] or { return PolicyError{'KeyError', name} }
}

fn text(row map[string]ah.Value, name string) string { return ah.field(row, name).text() }

fn strings(values []string) ah.Value { return ah.Value(values.map(ah.Value(it))) }

fn callback(operation string, arguments map[string]ah.Value) !ah.Value {
	println(ah.encode(pack(ah.Value({
		'callback':  ah.Value(operation)
		'arguments': ah.Value(arguments)
	}))))
	packed := json2.decode[ah.Value](os.get_raw_line(), strict: true)!
	row := unpack(packed)!.object()
	if 'error' in row { return BindingError{ah.field(row, 'error').object()} }
	return key(row, 'value')!
}

fn path(method string, name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('path', {
		'path':      ah.Value(name)
		'method':    ah.Value(method)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn join(parent string, child string) !string {
	return callback('join', {
		'parent': ah.Value(parent)
		'child':  ah.Value(child)
	})!.text()
}

fn close(id ah.Value) ! {
	callback('close', {
		'id': id
	})!
}

fn names(id ah.Value) ![]string {
	return callback('zip_names', {
		'id': id
	})!.items().map(it.text())
}

fn zip_open(name string, mode string, compression int) !ah.Value {
	return callback('zip_open', {
		'path':        ah.Value(name)
		'mode':        ah.Value(mode)
		'compression': ah.Value(compression)
	})!
}

fn zip_read(id ah.Value, name string) !string {
	return callback('zip_read', {
		'id':   id
		'name': ah.Value(name)
	})!.text()
}

fn digest(name string) !string { return ah.digest(name)! }

pub fn failure(err IError) map[string]ah.Value {
	if err is BindingError { return err.value }
	if err is PolicyError {
		return {
			'kind':    ah.Value(err.kind)
			'message': ah.Value(err.message)
		}
	}
	if err is PayloadError {
		return {
			'kind':    ah.Value('RuntimeError')
			'message': ah.Value(err.message)
			'cause':   ah.Value(err.cause)
		}
	}
	decoded := json2.decode[ah.Value](ah.error_json(err), strict: true) or { ah.Value(map[string]ah.Value{}) }
	row := decoded.object()
	return row
}

struct Engine {
	constants map[string]ah.Value
	source    string
	support   string
}

fn (e Engine) c(name string) ah.Value { return ah.field(e.constants, name) }

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	if text(row, 'operation') == 'constants' { return ah.Value(constants()) }
	e := Engine{ah.field(row, 'constants').object(), text(row, 'source'), text(row, 'support')}
	a := ah.field(row, 'arguments').object()
	return match text(row, 'operation') {
		'download' { ah.Value(e.download(ah.field(a, 'record').object(), text(a, 'directory'))!) }
		'extract_member' {
			e.extract_member(text(a, 'archive'), text(a, 'name'), text(a, 'output'))!
			ah.Value(json2.null)
		}
		'jar_info' {
			info := e.jar_info(text(a, 'path'))!
			ah.Value([strings(info.classes), ah.Value(info.callsites)])
		}
		'class_subset' {
			e.class_subset(text(a, 'raw'), ah.field(a, 'names').items().map(it.text()), text(a, 'output'))!
			ah.Value(json2.null)
		}
		'package_jar' {
			e.package_jar(text(a, 'original'), text(a, 'directory'), text(a, 'output'))!
			ah.Value(json2.null)
		}
		'validate_provenance' {
			e.validate_provenance(text(a, 'root'), ah.field(a, 'manifest'), ah.field(a, 'payloads'))!
			ah.Value(json2.null)
		}
		'prepare' {
			result := e.prepare(text(a, 'build_dir'), text(a, 'java'))!
			ah.Value([ah.Value(result.jars), ah.Value(result.manifest)])
		}
		'stage' { ah.Value(e.stage(text(a, 'build_dir'), text(a, 'overlay'), text(a, 'java'))!) }
		'build_probe' {
			e.build_probe(text(a, 'build_dir'), text(a, 'output'), text(a, 'java'), text(a, 'javac'))!
			ah.Value(json2.null)
		}
		'cache_identity' { ah.Value(e.cache_identity()!) }
		'main' {
			build := path('resolve', text(a, 'build_dir'), [], {})!.text()
			overlay := path('resolve', text(a, 'overlay'), [], {})!.text()
			manifest := e.stage(build, overlay, text(a, 'java'))!
			if ah.field(a, 'output') !is json2.Null {
				probe_build := path('resolve', text(a, 'build_dir'), [], {})!.text()
				output := path('resolve', text(a, 'output'), [], {})!.text()
				e.build_probe(probe_build, output, text(a, 'java'), text(a, 'javac'))!
			}
			libraries := ah.field(ah.field(manifest, 'bootclasspath').object(), 'files').items().map(text(it.object(), 'path'))
			callback('print', {
				'data': ah.Value('Desugared ART boot libraries; ' + libraries.join(', '))
			})!
			ah.Value(0)
		}
		else { return fail('unknown bootclasspath operation ' + text(row, 'operation')) }
	}
}

fn (e Engine) download(record map[string]ah.Value, directory string) !string {
	target := join(directory, key(record, 'filename')!.text())!
	if !(path('exists', target, [], {})! as bool) {
		suffix := path('suffix', target, [], {})!.text()
		temporary := path('with_suffix', target, [ah.Value(suffix + '.part')], {})!.text()
		e.download_file(record, target, temporary) or {
			path('unlink', temporary, [], {
				'missing_ok': ah.Value(true)
			})!
			return err
		}
		path('unlink', temporary, [], {
			'missing_ok': ah.Value(true)
		})!
	}
	if !(path('is_file', target, [], {})! as bool) || path('is_symlink', target, [], {})! as bool {
		return fail('bootclasspath input checksum mismatch: ' + path('name', target, [], {})!.text())
	}
	if digest(target)! != key(record, 'sha256')!.text() {
		return fail('bootclasspath input checksum mismatch: ' + path('name', target, [], {})!.text())
	}
	return target
}

fn (e Engine) download_file(record map[string]ah.Value, target string, temporary string) ! {
	callback('run', {
		'arguments': strings(['curl', '--fail', '--location', '--silent', '--show-error', '--retry',
			'3', '--output', temporary, key(record, 'url')!.text()])
	})!
	if digest(temporary)! != key(record, 'sha256')!.text() {
		return fail('bootclasspath input checksum mismatch: ' + path('name', target, [], {})!.text())
	}
	path('replace', temporary, [ah.Value(target)], {})!
}

fn (e Engine) extract_member(archive string, name string, output string) ! {
	id := callback('tar_open', {
		'path': ah.Value(archive)
	})!
	e.tar_member(id, name, output) or {
		close(id)!
		return err
	}
	close(id)!
}

fn (e Engine) tar_member(id ah.Value, name string, output string) ! {
	for {
		member := callback('tar_next', {
			'id': id
		})!
		if member is json2.Null { break }
		row := member.object()
		if text(row, 'name') != name { continue }
		if !(ah.field(row, 'regular') as bool) {
			return fail('bootclasspath input is not a regular file: ' + name)
		}
		if !(callback('tar_copy', {
			'id':   id
			'path': ah.Value(output)
		})! as bool) {
			return fail('bootclasspath input has no contents: ' + name)
		}
		return
	}
	return fail('bootclasspath input is missing ' + name)
}

struct DexInfo {
	classes   []string
	callsites u64
}

fn (e Engine) jar_info(name string) !DexInfo {
	id := zip_open(name, 'r', 0)!
	result := e.jar_contents(id, name) or {
		close(id)!
		return err
	}
	close(id)!
	return result
}

fn (e Engine) jar_contents(id ah.Value, name string) !DexInfo {
	mut classes := []string{}
	mut callsites := u64(0)
	for item in names(id)! {
		if !item.ends_with('.dex') { continue }
		found := ah.dex_info(hex.decode(zip_read(id, item)!)!)!
		if found.classes.any(it in classes) {
			return fail('duplicate classes across bootclasspath DEX files: ' + name)
		}
		classes << found.classes
		callsites += found.callsites
	}
	if classes.len == 0 { return fail('bootclasspath JAR has no DEX classes: ' + name) }
	classes.sort()
	return DexInfo{classes, callsites}
}

fn (e Engine) class_subset(raw string, requested []string, output string) ! {
	source := zip_open(raw, 'r', 0)!
	e.subset_output(source, requested, output) or {
		close(source)!
		return err
	}
	close(source)!
}

fn (e Engine) subset_output(source ah.Value, requested []string, output string) ! {
	target := zip_open(output, 'w', 0)!
	e.subset_contents(source, target, requested) or {
		close(target)!
		return err
	}
	close(target)!
}

fn (e Engine) subset_contents(source ah.Value, target ah.Value, requested []string) ! {
	available := names(source)!
	mut items := requested.clone()
	items.sort()
	missing := items.filter(it !in available)
	if missing.len > 0 { return fail('pinned bootclasspath class input is missing ' + missing[0]) }
	for name in items {
		callback('zip_write', {
			'id':   target
			'name': ah.Value(name)
			'data': ah.Value(zip_read(source, name)!)
		})!
	}
}

fn (e Engine) package_jar(original string, directory string, output string) ! {
	source := zip_open(original, 'r', 0)!
	mut payload := e.resources(source) or {
		close(source)!
		return err
	}
	close(source)!
	mut files := callback('glob', {
		'path':    ah.Value(directory)
		'pattern': ah.Value('*.dex')
	})!.items().map(it.text())
	files.sort()
	for name in files {
		payload[path('name', name, [], {})!.text()] = callback('read_bytes', {
			'path': ah.Value(name)
		})!.text()
	}
	if 'classes.dex' !in payload { return fail('D8 did not produce classes.dex') }
	target := zip_open(output, 'w', 8)!
	e.package_contents(target, payload) or {
		close(target)!
		return err
	}
	close(target)!
}

fn (e Engine) resources(source ah.Value) !map[string]string {
	mut payload := map[string]string{}
	for name in names(source)! {
		if !name.ends_with('.dex') { payload[name] = zip_read(source, name)! }
	}
	return payload
}

fn (e Engine) package_contents(target ah.Value, payload map[string]string) ! {
	mut sorted := payload.keys()
	sorted.sort()
	for name in sorted {
		callback('zip_write', {
			'id':            target
			'name':          ah.Value(name)
			'data':          ah.Value(payload[name])
			'deterministic': ah.Value(true)
		})!
	}
}
