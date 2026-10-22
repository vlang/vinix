// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Interface versions accepted by this package-tool executable. This is not an
// inventory of installed runtimes, publisher trust, policy or target ABI proof.
// Format 1 has exactly these five fields; new interface versions may be added
// to the sorted lists without changing the response schema.
pub struct Capabilities {
pub:
	format int = 1
	package_formats []int
	application_sdks []int
	native_window_protocols []int
	deployment_formats []int
}

fn capability_versions(values []int) bool {
	if values.len == 0 || values.len > 32 { return false }
	mut previous := 0
	for value in values {
		if value <= previous || value > 65535 { return false }
		previous = value
	}
	return true
}

pub fn (value &Capabilities) validate() ! {
	if value.format != 1 || !capability_versions(value.package_formats)
		|| !capability_versions(value.application_sdks) || !capability_versions(value.native_window_protocols)
		|| !capability_versions(value.deployment_formats) {
		return error('invalid package-tool capabilities')
	}
}

// A zero window protocol means no native window interface is requested.
// Membership is exact, never inferred from a maximum version or version range.
// Call on a decoded/validated response; admission of the actual signed package
// still belongs to the service.
pub fn (value &Capabilities) supports_package(package_format int, sdk int, window_protocol int) bool {
	return value.format == 1 && package_format > 0 && sdk > 0 && window_protocol >= 0
		&& package_format in value.package_formats && sdk in value.application_sdks
		&& (window_protocol == 0 || window_protocol in value.native_window_protocols)
}

// Only returned/decoded values own their arrays. close is repeatable.
pub fn (mut value Capabilities) close() {
	unsafe {
		value.package_formats.free(); value.application_sdks.free()
		value.native_window_protocols.free(); value.deployment_formats.free()
	}
	value = Capabilities{}
}

const capabilities_keys = ['format', 'package_formats', 'application_sdks', 'native_window_protocols', 'deployment_formats']

fn (mut reader MetadataReader) capability_versions() ![]int {
	reader.expect(`[`)!
	mut values := []int{cap: 32}
	mut accepted := false
	defer { if !accepted { unsafe { values.free() } } }
	mut first := true
	for reader.next(first, `]`)! {
		first = false
		if values.len == 32 { return error('capability version count exceeds its bound') }
		value := int(reader.unsigned(65535)!)
		if value == 0 || (values.len != 0 && value <= values.last()) {
			return error('capability versions must be positive, unique and sorted')
		}
		values << value
	}
	if values.len == 0 { return error('capability versions cannot be empty') }
	accepted = true
	return values
}

// The input is borrowed. Success owns four arrays, independently of the input.
// Unknown/duplicate keys, unknown schema formats and noncanonical numbers are
// refused. Future interface version numbers are retained, not implicitly used.
pub fn decode_capabilities(text string) !Capabilities {
	if text.len > 4096 { return error('package-tool capabilities exceed their bound') }
	// Mutating reader calls promote a local value with the current compiler;
	// make its ownership explicit, including errors before the first field.
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut value := Capabilities{}
	mut accepted := false
	defer { if !accepted { value.close() } }
	mut seen := u16(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(capabilities_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { value = Capabilities{ ...value, format: int(reader.unsigned(1)!) } }
			1 { value = Capabilities{ ...value, package_formats: reader.capability_versions()! } }
			2 { value = Capabilities{ ...value, application_sdks: reader.capability_versions()! } }
			3 { value = Capabilities{ ...value, native_window_protocols: reader.capability_versions()! } }
			4 { value = Capabilities{ ...value, deployment_formats: reader.capability_versions()! } }
			else {}
		}
	}
	reader.spaces()
	if seen != 31 || reader.position != text.len { return error('incomplete or trailing package-tool capabilities') }
	value.validate()!
	accepted = true
	return value
}
