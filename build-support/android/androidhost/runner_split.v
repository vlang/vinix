module androidhost

import encoding.hex
import json2

pub struct MissingKey {
	key string
}

pub fn (e MissingKey) msg() string { return e.key }

pub fn (e MissingKey) code() int { return 0 }

fn split_type(value Value) string {
	return match value {
		[]Value { 'list' }
		map[string]Value { 'dict' }
		string { 'str' }
		bool { 'bool' }
		Number {
			if value.text.contains_any('.eE') { 'float' } else { 'int' }
		}
		json2.Null { 'NoneType' }
		else { 'int' }
	}
}

fn split_index(value Value, key string, kind string) !Value {
	if value is map[string]Value {
		return value[key] or { return MissingKey{key} }
	}
	if value is string { return error('TypeError: string indices must be integers') }
	if value is []Value {
		return error('TypeError: list indices must be integers or slices, not str')
	}
	actual_kind := if value is json2.Null && kind == 'float' { 'float' } else { split_type(value) }
	return error("TypeError: '${actual_kind}' object is not subscriptable")
}

fn split_quote(value string) string {
	if value == '' { return "''" }
	if value.bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-'.bytes()) {
		return value
	}
	return "'" + value.replace("'", '\'"\'"\'') + "'"
}

fn split_launch(index int, name string, splits []string, message string, options []string) Value {
	guest := '/opt/android-test/split-probe/'
	mut command := ['/usr/bin/run-android', guest + 'android-split-probe.apk', '-l',
		'org/vinix/tests/AndroidSplitApkProbe$BootstrapActivity', '-w', '128', '-h', '128']
	for file in splits {
		command << '--split-apk'
		command << guest + file
	}
	command << options
	label := 'launch-' + if index < 10 { '0' + index.str() } else { index.str() } + '-' + name
	return Value(map[string]Value{
		'name':     Value(label)
		'script':   Value('#!/bin/sh\n' + command.map(split_quote(it)).join(' ') + '\nsplit_status=$?\nprintf \'%s\\n\' "$split_status" >/tmp/android-split-status\nexit "$split_status"\n')
		'expected': Value(if message == '' { '0\n' } else { '1\n' })
		'error':    Value(message)
	})
}

pub fn split_probe_plan(cases Value, kind string, case_types []string) !Value {
	mut names := map[string]bool{
		'positive': true
	}
	mut files := map[string]bool{
		'android-split-probe.apk': true
		'config.arm64_v8a.apk':    true
		'test-cases.json':         true
	}
	mut launches := [split_launch(0, 'positive', ['config.arm64_v8a.apk'], '', []string{})]
	if cases !is []Value {
		if cases is string || cases is map[string]Value {
			if cases.text() != '' || cases.object().len > 0 {
				return error('TypeError: string indices must be integers')
			}
			return error('ValueError: Split fixture must include rejection cases')
		}
		actual_kind := if cases is json2.Null && kind == 'float' {
			'float'
		} else {
			split_type(cases)
		}
		return error("TypeError: '${actual_kind}' object is not iterable")
	}
	for index, case in cases as []Value {
		case_kind := if index < case_types.len { case_types[index] } else { '' }
		name := split_index(case, 'name', case_kind)!
		splits := split_index(case, 'splits', case_kind)!
		message := split_index(case, 'error', case_kind)!
		options := case.object()['options'] or { Value([]Value{}) }
		name_text := name.text()
		message_text := message.text()
		options_text := options.items().map(it.text())
		if name !is string || name_text == '' || !name_text.bytes().all(it in 'abcdefghijklmnopqrstuvwxyz0123456789-'.bytes()) || name_text in names {
			return error('ValueError: Invalid or repeated split fixture case name')
		}
		if splits !is []Value || splits.items().len == 0 || message !is string || message_text == '' || message_text.contains('\n') {
			return error('ValueError: Invalid split fixture rejection case')
		}
		if options !is []Value || options.items().any(it !is string) || options_text.any(it !in [
			'--install',
			'--install-internal',
		]) {
			return error('ValueError: Invalid split fixture launcher option')
		}
		for file in splits.items() {
			filename := file.text()
			if file !is string || filename.contains('/') || !filename.ends_with('.apk') {
				return error('ValueError: Split fixture archive must be a plain APK filename')
			}
		}
		names[name_text] = true
		for file in splits.items() { files[file.text()] = true }
		launches << split_launch(launches.len, name_text, splits.items().map(it.text()), message_text, options.items().map(it.text()))
	}
	if cases.items().len == 0 {
		return error('ValueError: Split fixture must include rejection cases')
	}
	mut sorted := files.keys()
	sorted.sort()
	return Value(map[string]Value{
		'files':    Value(sorted.map(Value(it)))
		'launches': Value(launches)
	})
}

// JSON's Unicode decoder rejects the lone surrogates accepted by CPython.
// Keep them as owned WTF-8 bytes until the compatibility binding writes text.
pub fn unpack_string_value(value Value) !Value {
	pair := value.items()
	if pair.len != 2 { return error('invalid string transport') }
	kind := pair[0].text()
	data := pair[1]
	return match kind {
		'string' { Value(hex.decode(data.text())!.bytestr()) }
		'list' {
			mut items := []Value{}
			for item in data.items() { items << unpack_string_value(item)! }
			Value(items)
		}
		'dict' {
			mut row := map[string]Value{}
			for entry in data.items() {
				fields := entry.items()
				if fields.len != 2 { return error('invalid dictionary transport') }
				row[unpack_string_value(fields[0])!.text()] = unpack_string_value(fields[1])!
			}
			Value(row)
		}
		'value' { data }
		else { return error('invalid string transport kind') }
	}
}

pub fn pack_string_value(value Value) Value {
	return match value {
		string { Value([Value('string'), Value(value.bytes().hex())]) }
		[]Value { Value([Value('list'), Value(value.map(pack_string_value(it)))]) }
		map[string]Value {
			mut items := []Value{}
			for key, item in value {
				items << Value([pack_string_value(Value(key)), pack_string_value(item)])
			}
			Value([Value('dict'), Value(items)])
		}
		else { Value([Value('value'), value]) }
	}
}
