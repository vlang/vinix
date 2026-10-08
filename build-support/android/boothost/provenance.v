module boothost

import androidhost as ah
import json2
import math.big
import math.bits
import strconv

fn integer_spelling(value ah.Value) ?string {
	return match value {
		ah.Number {
			if value.text.contains_any('.eE') || value.text in ['nan', 'inf', '-inf'] {
				return none
			}
			value.text
		}
		int, i64, u64 { value.str() }
		else { none }
	}
}

fn integer_compare(value ah.Value, expected u64) ?int {
	spelling := integer_spelling(value) or { return none }
	negative := spelling.starts_with('-')
	magnitude := big.integer_from_string(if negative { spelling[1..] } else { spelling }) or { return none }
	number := if negative { big.zero_int - magnitude } else { magnitude }
	target := big.integer_from_string(expected.str()) or { return none }
	return if number < target {
		-1
	} else if number > target {
		1
	} else {
		0
	}
}

fn numeric(value ah.Value) ?f64 {
	return match value {
		ah.Number { strconv.atof64(value.text) or { return none } }
		int, i64, u64 { f64(value) }
		bool {
			if value { f64(1) } else { f64(0) }
		}
		else { none }
	}
}

fn signed_big(text string) !big.Integer {
	if text.starts_with('-') { return big.zero_int - big.integer_from_string(text[1..])! }
	return big.integer_from_string(text)!
}

fn equality_integer(value ah.Value) ?big.Integer {
	if value is bool { return big.integer_from_int(if value { 1 } else { 0 }) }
	spelling := integer_spelling(value) or { return none }
	return signed_big(spelling) or { return none }
}

fn equal_integer_float(integer big.Integer, float f64) bool {
	raw := bits.f64_bits(float)
	exponent := int((raw >> 52) & 0x7ff)
	mantissa := raw & 0xfffffffffffff
	if exponent == 0x7ff { return false }
	if exponent == 0 && mantissa == 0 { return integer == big.zero_int }
	if exponent < 1023 { return false }
	shift := exponent - 1023 - 52
	significand := mantissa | (u64(1) << 52)
	magnitude := if shift < 0 {
		if shift < -52 || significand & ((u64(1) << -shift) - 1) != 0 { return false }
		big.integer_from_u64(significand >> -shift)
	} else {
		big.integer_from_u64(significand).left_shift(u32(shift))
	}
	number := if raw >> 63 != 0 { big.zero_int - magnitude } else { magnitude }
	return integer == number
}

// Python receipt equality accepts numerically equal booleans/floats for the
// original-source fields, then applies strict integer type checks separately.
fn equal(a ah.Value, b ah.Value) bool {
	if a is map[string]ah.Value && b is map[string]ah.Value {
		if a.len != b.len { return false }
		for name, value in a {
			if name !in b || !equal(value, b[name] or { return false }) { return false }
		}
		return true
	}
	if a is []ah.Value && b is []ah.Value {
		if a.len != b.len { return false }
		for index, value in a { if !equal(value, b[index]) { return false } }
		return true
	}
	if a is string && b is string { return a == b }
	if a is json2.Null && b is json2.Null { return true }
	if av := equality_integer(a) {
		if bv := equality_integer(b) { return av == bv }
		return equal_integer_float(av, numeric(b) or { return false })
	}
	if bv := equality_integer(b) { return equal_integer_float(bv, numeric(a) or { return false }) }
	return (numeric(a) or { return false }) == (numeric(b) or { return false })
}

fn is_lower_hash(value ah.Value) bool {
	if value !is string { return false }
	return value.len == 64 && value.bytes().all(it in '0123456789abcdef'.bytes())
}

fn type_name(value ah.Value) string {
	return match value {
		json2.Null { 'NoneType' }
		bool { 'bool' }
		[]ah.Value { 'list' }
		map[string]ah.Value { 'dict' }
		string { 'str' }
		ah.Number {
			if value.text.contains_any('.eE') || value.text in ['nan', 'inf', '-inf'] {
				'float'
			} else {
				'int'
			}
		}
		int, i64, u64 { 'int' }
	}
}

fn payload_records(payloads ah.Value) !map[string]ah.Value {
	mut records := map[string]ah.Value{}
	if payloads is json2.Null { return records }
	if payloads is string && payloads.len == 0 { return records }
	if payloads is map[string]ah.Value && payloads.len == 0 { return records }
	if payloads is string || payloads is map[string]ah.Value {
		return PolicyError{'TypeError', 'string indices must be integers'}
	}
	if payloads !is []ah.Value {
		return PolicyError{'TypeError', "'" + type_name(payloads) + "' object is not iterable"}
	}
	for value in payloads.items() {
		if value is string { return PolicyError{'TypeError', 'string indices must be integers'} }
		if value is []ah.Value {
			return PolicyError{'TypeError', 'list indices must be integers or slices, not str'}
		}
		if value !is map[string]ah.Value {
			return PolicyError{'TypeError', "'" + type_name(value) + "' object is not subscriptable"}
		}
		name := key(value.object(), 'path')!
		if name is []ah.Value || name is map[string]ah.Value {
			return PolicyError{'TypeError', "unhashable type: '" + type_name(name) + "'"}
		}
		records[name.text()] = value
	}
	return records
}

fn (e Engine) validate_provenance(root string, manifest ah.Value, payloads ah.Value) ! {
	row := manifest.object()
	if manifest !is map[string]ah.Value || (integer_compare(ah.field(row, 'format'), 1) or { -1 }) != 0
		|| !equal(ah.field(row, 'inputs'), e.c('INPUTS')) || !equal(ah.field(row, 'compiler_arguments'), e.c('COMPILER_ARGUMENTS'))
		|| ah.field(row, 'compiler') !is string || !text(row, 'compiler').starts_with('D8 8.3.37 (build ') {
		return fail('bootclasspath provenance does not match the pinned compiler and inputs')
	}
	if !is_lower_hash(ah.field(row, 'input_key')) {
		return fail('bootclasspath provenance has an invalid input key')
	}
	files := ah.field(row, 'files')
	if files !is []ah.Value || files.items().len != e.c('BOOT_JARS').items().len {
		return fail('bootclasspath provenance must contain both Java boot libraries')
	}
	records := payload_records(payloads)!
	mut seen := []string{}
	allowed := e.c('BOOT_JARS').items().map(e.c('BOOT_DIRECTORY').text() + '/' + it.text())
	for value in files.items() {
		if value !is map[string]ah.Value {
			return fail('bootclasspath file receipt must be an object')
		}
		record := value.object()
		name := ah.field(record, 'path')
		if name !is string || name.text() !in allowed || name.text() in seen {
			return fail('bootclasspath provenance has an unexpected or duplicate library')
		}
		name_text := name.text()
		seen << name_text
		basename := path('name', name_text, [], {})!.text()
		original := key(e.c('BOOT_ORIGINAL').object(), basename)!.object()
		for field, expected in original {
			if !equal(ah.field(record, field), expected) {
				return fail('bootclasspath provenance has a different source library: ' + name_text)
			}
		}
		for field in ['size', 'classes_before', 'classes_after', 'bootstrap_callsites_before',
			'bootstrap_callsites_after'] {
			if integer_spelling(ah.field(record, field)) == none {
				return fail('bootclasspath provenance lost classes or retained bootstrap calls: ' + name_text)
			}
		}
		before := integer_spelling(key(record, 'classes_before')!) or { return fail('invalid class count') }
		after := integer_spelling(key(record, 'classes_after')!) or { return fail('invalid class count') }
		if (integer_compare(key(record, 'size')!, 0) or { -1 }) < 0
			|| (integer_compare(key(record, 'bootstrap_callsites_after')!, 0) or { -1 }) != 0
			|| signed_big(after)! < signed_big(before)! {
			return fail('bootclasspath provenance lost classes or retained bootstrap calls: ' + name_text)
		}
		if payloads !is json2.Null {
			if name_text !in records {
				return fail('bootclasspath receipt does not match the ART payload: ' + name_text)
			}
			for field in ['sha256', 'size'] {
				if !equal(ah.field((records[name_text] or { ah.Value(json2.null) }).object(), field), ah.field(record, field)) {
					return fail('bootclasspath receipt does not match the ART payload: ' + name_text)
				}
			}
		}
		target := join(root, name_text)!
		mut parent := root
		if path('is_symlink', parent, [], {})! as bool {
			return fail('bootclasspath payload must not use symlinks: ' + name_text)
		}
		for part in path('parts', name_text, [], {})!.items() {
			parent = join(parent, part.text())!
			if path('is_symlink', parent, [], {})! as bool {
				return fail('bootclasspath payload must not use symlinks: ' + name_text)
			}
		}
		if !(path('is_file', target, [], {})! as bool) {
			return fail('bootclasspath payload checksum mismatch: ' + name_text)
		}
		size := callback('stat', {
			'path': ah.Value(target)
		})!
		if !equal(size, key(record, 'size')!) {
			return fail('bootclasspath payload checksum mismatch: ' + name_text)
		}
		if digest(target)! != ah.field(record, 'sha256').text() {
			return fail('bootclasspath payload checksum mismatch: ' + name_text)
		}
		info := e.jar_info(target) or {
			if err is BindingError && text(err.value, 'kind') in ['ValueError', 'UnicodeError',
				'UnicodeDecodeError', 'BadZipFile'] {
				return PayloadError{'invalid bootclasspath payload: ' + name_text, failure(err)}
			}
			if err is ah.AsciiError || err.msg().starts_with('ValueError: ') {
				return PayloadError{'invalid bootclasspath payload: ' + name_text, failure(err)}
			}
			return err
		}
		if (integer_compare(key(record, 'classes_after')!, u64(info.classes.len)) or { -1 }) != 0 || info.callsites != 0 {
			return fail('bootclasspath DEX does not match its compiler receipt: ' + name_text)
		}
	}
}
