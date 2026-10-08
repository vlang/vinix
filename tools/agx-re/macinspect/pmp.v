module macinspect

import traceanalysis as j
import encoding.utf8

pub struct PatchInput {
pub:
	tag        string
	name       string
	node       string
	derivation string
	checked    bool
}

pub const pmp_patchbay_inputs = [
	PatchInput{'BDID', 'board-id', 'chosen', 'value', true},
	PatchInput{'DVID', 'dram-vendor-id', 'chosen', 'value', true},
	PatchInput{'DCAP', 'dram-capacity', 'provider', 'value', false},
	PatchInput{'DCHD', 'dram-channel-disable', 'provider', 'value', false},
	PatchInput{'PMC_', 'pmc', 'pmgr', 'value', true},
	PatchInput{'PMCV', 'pmc-pmgr', 'pmgr', 'value & 1', true},
	PatchInput{'PMCB', 'pmc-pmgr', 'pmgr', '(value >> 3) & 1', true},
	PatchInput{'PMCX', 'pmc-msg-disabled', 'provider', 'value', false},
	PatchInput{'CVAR', 'soc-chip-variant', 'provider', 'value', false},
]

pub fn parse_pmp_patchbay_inputs(nodes map[string]Property) ![]j.Value {
	mut output := []j.Value{}
	for input in pmp_patchbay_inputs {
		node := get(nodes, input.node)
		if node.kind == .null {
			return error('patchbay input ${input.tag} has no ${input.node} node')
		}
		raw := get(node.fields, input.name)
		mut entry := map[string]j.Value{
			'tag':        j.Value(input.tag)
			'property':   j.Value(input.name)
			'node':       j.Value(input.node)
			'derivation': j.Value(input.derivation)
		}
		if raw.kind == .null {
			entry['present'] = j.Value(false)
			entry['value'] = number(0)
			entry['reason'] = j.Value('property absent')
		} else if raw.kind != .bytes || (input.checked && raw.bytes.len != 4) {
			entry['present'] = j.Value(false)
			entry['value'] = number(0)
			entry['reason'] = j.Value('rejected width')
		} else if raw.bytes.len < 4 {
			return error('patchbay input ${input.tag} is shorter than four bytes')
		} else {
			mut n := le(raw.bytes, 0, 4)
			if input.derivation == 'value & 1' {
				n &= 1
			} else if input.derivation == '(value >> 3) & 1' {
				n = (n >> 3) & 1
			}
			entry['present'] = j.Value(true)
			entry['value'] = number(n)
		}
		output << j.Value(entry)
	}
	return output
}

pub fn parse_pmp_nub(node map[string]Property, role string) !map[string]j.Value {
	expected := 'iop-${role.to_lower()}-nub'
	if text(node, 'IORegistryEntryName') != expected {
		return error('${role} nub plist is not ${expected}')
	}
	if text(node, 'IOObjectClass') != 'AppleA7IOPNub' {
		return error('${expected} has an unexpected IOObjectClass')
	}
	mut flags := map[string]j.Value{}
	for name in rtbuddy_firmware_source_properties {
		present := name in node
		flags[name] = j.Value(present)
		if present && (node[name].kind != .bytes || !eq(decode_uint(node[name], 32, name)!, number(1))) {
			return error('${expected} ${name} is not the expected flag')
		}
	}
	skip := 'running' in node || 'no-firmware-service' in node
	path := if skip {
		if 'pre-loaded' in node { 'preload' } else { 'service-firmware' }
	} else {
		'await-firmware-service'
	}
	return {
		'name':                  j.Value(expected)
		'role':                  j.Value(role)
		'properties':            j.Value(flags)
		'has_segment_ranges':    j.Value('segment-ranges' in node)
		'skip_firmware_service': j.Value(skip)
		'firmware_load_path':    j.Value(path)
	}
}

// Unicode 13.0.0 decimal digit blocks preserve the qualified Python baseline.
// Each ten-digit block includes one mathematical digit alphabet.
fn decimal_digit(r rune) int {
	for zero in [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6,
		0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
		0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50,
		0xabf0, 0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450,
		0x114d0, 0x11650, 0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60,
		0x16b50, 0x1d7ce, 0x1d7d8, 0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0] {
		if int(r) >= zero && int(r) < zero + 10 { return int(r) - zero }
	}
	return -1
}

fn decimal_suffix(text string) !u64 {
	if text == '' { return error('non-numeric') }
	mut output := u64(0)
	for r in text.runes() {
		digit := decimal_digit(r)
		if digit < 0 || !utf8.validate_str(r.str()) { return error('non-numeric') }
		if output <= 224 { output = output * 10 + u64(digit) }
	}
	return output
}

pub fn parse_pmp_endpoint_service(node map[string]Property) !map[string]j.Value {
	if text(node, 'IOObjectClass') != 'RTBuddyEndpointService' {
		return error('PMP endpoint service has an unexpected IOObjectClass')
	}
	p := get(node, 'IORegistryEntryName')
	if p.kind != .string { return error('PMP endpoint service is missing its registry name') }
	mut role := ''
	for candidate in ['PMP0', 'PMP1'] {
		if p.text.starts_with(candidate + 'Endpoint') {
			role = candidate
			break
		}
	}
	if role == '' { return error('PMP endpoint service has an unexpected registry name') }
	suffix := decimal_suffix(p.text[(role + 'Endpoint').len..]) or { return error('PMP endpoint service has a non-numeric suffix') }
	if suffix < 1 || suffix > 224 { return error('PMP endpoint service suffix is out of range') }
	return {
		'name':           j.Value(p.text)
		'class':          j.Value('RTBuddyEndpointService')
		'role':           j.Value(role)
		'service_suffix': number(suffix)
		'wire_endpoint':  number(suffix + 0x1f)
	}
}
