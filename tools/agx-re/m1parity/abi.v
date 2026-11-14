// SPDX-License-Identifier: GPL-2.0-or-later
module m1parity

struct Field {
	name      string
	type_name string
	offset    u64
}

struct Layout {
	size   u64
	fields []Field
}

fn aggregate(source string, marker string) !string {
	start := source.index(marker + ' {') or { return error('missing declaration: ${marker}') }
	if _ := source.index_after(marker + ' {', start + marker.len + 2) {
		return error('duplicate declaration: ${marker}')
	}
	begin := start + marker.len + 2
	end := source.index_after('}', begin) or { return error('unterminated declaration: ${marker}') }
	body := source[begin..end]
	if body.contains('{') { return error('nested declaration not supported: ${marker}') }
	return body
}

fn scalar_size(name string) !u64 {
	return match name {
		'u16', '__u16' { u64(2) }
		'u32', '__u32' { u64(4) }
		'u64', '__u64' { u64(8) }
		else { return error('unsupported ABI scalar: ${name}') }
	}
}

fn layout(source string, name string, c bool) !Layout {
	clean := uncomment(source, false)!
	marker := if c { 'struct ${name}' } else { 'pub struct ${name}' }
	body := aggregate(clean, marker)!
	start := clean.index(marker + ' {') or { return error('missing declaration: ${marker}') }
	if !c && clean[..start].trim_space().all_after_last('\n').starts_with('@[') {
		return error('structure attributes require explicit layout support: ${name}')
	}
	if c {
		end := start + marker.len + 2 + body.len
		if !clean[end + 1..].trim_left(' \t\r\n').starts_with(';') {
			return error('structure attributes require explicit layout support: ${name}')
		}
	}
	mut fields := []Field{}
	mut offset := u64(0)
	mut alignment := u64(1)
	lines := if c { body.split(';') } else { body.split_into_lines() }
	for raw in lines {
		line := raw.trim_space()
		if line == '' || (!c && line in ['pub:', 'pub mut:', 'mut:']) { continue }
		words := line.fields()
		if words.len != 2 { return error('${name}: unsupported field: ${line}') }
		field := if c { words[1] } else { words[0] }
		type_name := if c { words[0] } else { words[1] }
		if !identifier(field) { return error('${name}: unsupported field name: ${field}') }
		if fields.any(it.name == field) { return error('${name}: duplicate field: ${field}') }
		width := scalar_size(type_name)!
		offset = (offset + width - 1) & ~(width - 1)
		fields << Field{ name: field, type_name: type_name.trim_left('_'), offset: offset }
		offset += width
		if alignment < width { alignment = width }
	}
	if fields.len == 0 { return error('empty structure: ${name}') }
	return Layout{ size: (offset + alignment - 1) & ~(alignment - 1), fields: fields }
}

fn describe(value Layout) string {
	return '${value.size} bytes: ' + value.fields.map('${it.name}:${it.type_name}@${it.offset}').join(', ')
}

pub struct Comparison {
pub:
	area      string
	vinix     string
	reference string
	matches   bool
}

fn number(area string, local u64, reference u64) Comparison {
	return Comparison{ area: area, vinix: local.str(), reference: reference.str(), matches: local == reference }
}

// This compares selected declared ABI facts. Equal facts never imply whole
// driver equivalence; missing/unsupported declarations are audit errors.
pub fn compare_abi(local string, reference string, submission string, file string) ![]Comparison {
	mut checks := []Comparison{}
	base := expression(declaration(local, 'drm_asahi_base', false)!, map[string]u64{}, 0)!
	constants := {
		'drm_asahi_base': base
	}
	ids := enum_values(reference, 'drm_asahi_ioctl_id')!
	for suffix in ['get_params', 'get_time', 'vm_create', 'vm_destroy', 'gem_create', 'gem_mmap_offset',
		'gem_bind_object', 'queue_create', 'queue_destroy', 'submit'] {
		id := ids['DRM_ASAHI_' + suffix.to_upper()] or { return error('missing reference ioctl ${suffix}') }
		checks << number('DRM command number: ${suffix}',
			expression(declaration(local, 'drm_asahi_' + suffix, false)!, constants, 0)!, 0x40 + id)
	}
	checks << number('no-barrier sentinel', expression(declaration(local, 'asahi_barrier_none', false)!, constants, 0)!,
		define_value(reference, 'DRM_ASAHI_BARRIER_NONE')!)
	checks << number('maximum hardware commands per submission',
		expression(declaration(submission, 'max_commands', false)!, constants, 0)!,
		expression(declaration(file, 'MAX_COMMANDS_PER_SUBMISSION', true)!, map[string]u64{}, 0)!)
	flags := enum_values(reference, 'drm_asahi_bind_flags')!
	for suffix in ['read', 'write'] {
		value := flags['DRM_ASAHI_BIND_' + suffix.to_upper()] or { return error('missing reference bind flag') }
		checks << number('VM bind ${suffix} flag', expression(declaration(local, 'asahi_bind_' + suffix, false)!, constants, 0)!, value)
	}
	for names in [['DrmAsahiGetParams', 'drm_asahi_get_params'],
		['DrmAsahiSubmit', 'drm_asahi_submit'], ['DrmAsahiGemBind', 'drm_asahi_vm_bind']] {
		left := layout(local, names[0], false)!
		right := layout(reference, names[1], true)!
		checks << Comparison{
			area:      'declared ABI fields: ${names[0]} / ${names[1]}'
			vinix:     describe(left)
			reference: describe(right)
			matches:   left == right
		}
	}
	return checks
}
