// SPDX-License-Identifier: GPL-2.0-or-later
module boottest

import androidhost as ah

fn elf(arch string, pins string) !string {
	mut f := Frame{ pins: pins }
	return elf_body(mut f, arch) or {
		cause := err
		f.pin_failure()!
		return cause
	}
}

fn elf_body(mut f Frame, arch string) !string {
	data := invoke_target(constant('bytearray')!, [v(ah.Value(64))!], {})!
	f.named('data', data)!
	set_slice(data, v(ah.Value(0))!, v(ah.Value(6))!, b('7f454c460201')!)!
	discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<H'))!, o(data), v(ah.Value(18))!,
		o(item(item(constant('boot.ARCHES')!, o(arch))!, v(ah.Value(1))!)!)], {})!)!
	return data
}

fn pe(arch string, pins string) !string {
	mut f := Frame{ pins: pins }
	return pe_body(mut f, arch) or {
		cause := err
		f.pin_failure()!
		return cause
	}
}

fn pe_body(mut f Frame, arch string) !string {
	data := invoke_target(constant('bytearray')!, [v(ah.Value(2048))!], {})!
	f.named('data', data)!
	set_slice(data, v(ah.Value(0))!, v(ah.Value(2))!, b('4d5a')!)!
	discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<I'))!, o(data),
		v(ah.Value(0x3c))!, v(ah.Value(128))!], {})!)!
	set_slice(data, v(ah.Value(128))!, v(ah.Value(132))!, b('50450000')!)!
	discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<HH'))!, o(data),
		v(ah.Value(132))!, o(item(item(constant('boot.ARCHES')!, o(arch))!, v(ah.Value(0))!)!),
		v(ah.Value(1))!], {})!)!
	for row in [[148, 240]!, [152, 0x20b]!, [220, 10]!] {
		discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<H'))!, o(data),
			v(ah.Value(row[0]))!, v(ah.Value(row[1]))!], {})!)!
	}
	discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<I'))!, o(data), v(ah.Value(260))!,
		v(ah.Value(16))!], {})!)!
	discard(invoke_target(constant('struct.pack_into')!, [v(ah.Value('<II'))!, o(data),
		v(ah.Value(408))!, v(ah.Value(1024))!, v(ah.Value(512))!], {})!)!
	marker := constant('boot.CONFIG_MARKER')!
	len_target := constant('len')!
	bound_object := constant('boot.CONFIG_MARKER')!
	bound := invoke_target(len_target, [o(bound_object)], {})!
	release([bound_object])!
	end := invoke_target(constant('operator.add')!, [v(ah.Value(512))!, o(bound)], {})!
	release([bound])!
	set_slice(data, v(ah.Value(512))!, o(end), o(marker))!
	release([marker, end])!
	field_len_target := constant('len')!
	field_object := constant('boot.CONFIG_MARKER')!
	field_length := invoke_target(field_len_target, [o(field_object)], {})!
	release([field_object])!
	field := invoke_target(constant('operator.add')!, [v(ah.Value(512))!, o(field_length)], {})!
	release([field_length])!
	f.named('field', field)!
	set_slice(data, o(field), o(add(field, v(ah.Value(128))!)!), b('3030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030')!)!
	equality := invoke_target(constant('operator.eq')!, [o(arch), o(pe_value(0)!)], {})!
	equal := callback('function', {
		'name': ah.Value('builtins.bool')
		'call': ah.Value(true)
		'args': ah.Value([o(equality)])
		'data': ah.Value(true)
	}) or {
		release([equality])!
		return err
	}
	release([equality])!
	truth := equal as bool
	name := if truth { pe_value(1)! } else { arch }
	label := formatted_string([pe_value(2)!, format_value(name)!, pe_value(3)!])!
	encoded := invoke_target(member(label, 'encode')!, [], {})!
	release([label])!
	f.named('label', encoded)!
	set_slice(data, v(ah.Value(800))!, o(invoke_target(constant('operator.add')!, [
		v(ah.Value(800))!,
		o(length(encoded)!),
	], {})!), o(encoded))!
	return data
}

fn pe_value(index int) !string {
	return item(constant('_PE_VALUES')!, v(ah.Value(index))!)!
}
