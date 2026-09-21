// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module pmp

// ApplePMPv2 endpoint message codec.
//
// Every PMP endpoint message is one 64-bit word. Bits 55:52 carry a message
// class and bits 51:48 a class-specific subtype. This is the wire encoding
// only: it holds no driver state and performs no access.

// ApplePMPv2::messageHandler extracts the class with `ubfx x8, x1, #52, #4`.
const class_shift = u32(52)
const class_field_mask = u64(0xf)
const subtype_shift = u32(48)
const subtype_field_mask = u64(0xf)
const class_memory = u32(1)
const class_power = u32(2)
const class_registry_first = u32(3)
const class_registry_count = u32(2)
// ApplePMPv2::pingGated builds `(2 << 52) | (timestamp & 0xffffffff)`.
const ping_timestamp_mask = u64(0xffffffff)
// handlePMMessage accepts only subtype 1 and panics on anything else.
const ping_completion_subtype = u32(1)
// RTBuddy numbers application endpoints from 0x20, but names their services
// from 0x1f, so PMP0Endpoint1 is wire endpoint 32 rather than 1.
const first_app_endpoint = u32(0x20)
const service_suffix_bias = u32(0x1f)

pub enum MessageClass {
	// ApplePMPv2 treats a class outside 1..4 as fatal rather than ignorable,
	// so an unrecognized word is reported instead of silently dropped.
	unknown
	memory
	power
	registry
}

pub fn message_class(word u64) u32 {
	return u32((word >> class_shift) & class_field_mask)
}

pub fn message_subtype(word u64) u32 {
	return u32((word >> subtype_shift) & subtype_field_mask)
}

// Classes 3 and 4 are both registry traffic; the handler tests `class - 3 < 2`
// rather than comparing them separately.
pub fn classify(word u64) MessageClass {
	class := message_class(word)
	if class - class_registry_first < class_registry_count {
		return .registry
	}
	if class == class_power {
		return .power
	}
	if class == class_memory {
		return .memory
	}
	return .unknown
}

// A ping request is a power-class word carrying the low 32 bits of the host
// timestamp, with a zero subtype. The upper timestamp bits are deliberately
// discarded rather than allowed to collide with the class field.
pub fn encode_ping_request(timestamp u64) u64 {
	return (u64(class_power) << class_shift) | (timestamp & ping_timestamp_mask)
}

// The confirmation is the same class with subtype 1. A power word with any
// other subtype is not a completion and must not be treated as one.
pub fn is_ping_completion(word u64) bool {
	return classify(word) == .power && message_subtype(word) == ping_completion_subtype
}

// Translate a service name suffix, as published in the IORegistry, into the
// RTKit wire endpoint it addresses.
pub fn wire_endpoint(service_suffix u32) ?u32 {
	if service_suffix == 0 {
		return none
	}
	wire := service_suffix + service_suffix_bias
	if wire < first_app_endpoint || wire > 0xff {
		return none
	}
	return wire
}

pub fn service_suffix(wire u32) ?u32 {
	if wire < first_app_endpoint || wire > 0xff {
		return none
	}
	return wire - service_suffix_bias
}

// Exercise the codec against the values recovered from the UUID-pinned
// ApplePMP binary. This is pure arithmetic; it maps nothing and sends nothing.
pub fn validate_pmp_message_codec() bool {
	// pingGated's exact word: class 2 in bits 55:52, timestamp in bits 31:0.
	request := encode_ping_request(0x1234_5678_9abc_def0)
	if request != 0x0020_0000_9abc_def0 {
		return false
	}
	if message_class(request) != class_power || message_subtype(request) != 0 {
		return false
	}
	if is_ping_completion(request) {
		return false
	}
	completion := (u64(class_power) << class_shift) | (u64(ping_completion_subtype) << subtype_shift)
	if !is_ping_completion(completion) {
		return false
	}
	// A power word with a different subtype is not a completion.
	other := (u64(class_power) << class_shift) | (u64(2) << subtype_shift)
	if is_ping_completion(other) {
		return false
	}
	if classify(u64(class_memory) << class_shift) != .memory
		|| classify(u64(class_power) << class_shift) != .power
		|| classify(u64(3) << class_shift) != .registry
		|| classify(u64(4) << class_shift) != .registry {
		return false
	}
	// Everything outside 1..4 is unknown, including zero and the top class.
	for class in [u32(0), 5, 6, 15] {
		if classify(u64(class) << class_shift) != .unknown {
			return false
		}
	}
	// PMP0Endpoint1 is wire endpoint 32; the bias is 0x1f, not 0x20.
	if wire_endpoint(1) or { return false } != first_app_endpoint {
		return false
	}
	if service_suffix(first_app_endpoint) or { return false } != 1 {
		return false
	}
	if _ := wire_endpoint(0) {
		return false
	}
	if _ := service_suffix(first_app_endpoint - 1) {
		return false
	}
	return service_suffix(0xff) or { return false } == 0xff - service_suffix_bias
}
