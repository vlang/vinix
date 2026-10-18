// SPDX-License-Identifier: ISC
module wifihost

import encoding.hex

// macOS evidence is a separate source from a successful Vinix chip probe.
// The kernel still verifies every manifest field against the real device.
pub struct MacWifi {
pub:
	revision         u8
	module_name      string
	vendor           string
	module_revision  string
	antenna          string
	board            string
	firmware_version string
	files            []string // Firmware, NVRAM, Regulatory, TxCap, relative to Apple's wifi directory.
}

fn property(text string, name string) !string {
	needle := '"' + name + '" = '
	lines := text.split_into_lines().filter(it.trim_left(' |\t').starts_with(needle))
	if lines.len != 1 { return error('Expected one macOS property: ' + name) }
	return lines[0].trim_space().all_after(needle)
}

fn quoted(value string) !string {
	if value.len < 2 || value[0] != `"` || value[value.len - 1] != `"` || value[1..value.len - 1].contains_any('"\\') {
		return error('Invalid macOS string')
	}
	return value[1..value.len - 1]
}

fn token(text string, key string) !string {
	values := text.fields().filter(it.starts_with(key + '='))
	if values.len != 1 { return error('Missing or ambiguous module token: ' + key) }
	value := values[0].all_after('=')
	if value == '' || value.len >= 16 || !value.bytes().all(it.is_alnum() || it == `.` || it == `-` || it == `_`) {
		return error('Invalid module token: ' + key)
	}
	return value
}

pub fn macos_wifi(model string, core string, tree string) !MacWifi {
	if model.trim_space() != 'MacBookAir10,1' || property(core, 'ChipSet')! != '4378' || property(core, 'FirmwareLoaded')! != 'Yes' {
		return error('Requires a running BCM4378 on the J313 M1 Air')
	}
	info := quoted(property(core, 'ModuleInfo')!)!
	if info.count("chip='") != 1 || info.count("module='") != 1 {
		return error('Ambiguous module identity')
	}
	silicon := info.all_after("chip='").all_before("'")
	revision := match silicon {
		's=B1' { u8(3) }
		's=B3' { u8(5) }
		else { return error('Unsupported BCM4378 silicon') }
	}
	mod := info.all_after("module='").all_before("'")
	module_name := token(mod, 'M')!
	vendor := token(mod, 'V')!
	module_revision := token(mod, 'm')!
	if property(tree, 'module-instance')! != '<"shikoku">' {
		return error('Unsupported Wi-Fi board')
	}
	antenna_data := property(tree, 'wifi-antenna-sku-info')!
	if antenna_data.len != 34 || !antenna_data.starts_with('<') || !antenna_data.ends_with('>') {
		return error('Invalid antenna data')
	}
	bytes := hex.decode(antenna_data[1..33])!
	end := bytes[8..].index(u8(0))
	if end <= 0 { return error('Unterminated antenna identity') }
	antenna := bytes[8..8 + end].bytestr()
	if !antenna.bytes().all(it.is_alnum()) { return error('Invalid antenna identity') }
	requests := property(core, 'RequestedFiles')!
	if requests.count('{') != 1 || requests.count('}') != 1 {
		return error('Ambiguous firmware selection')
	}
	mut files := []string{}
	for key in ['Firmware', 'NVRAM', 'Regulatory', 'TxCap'] {
		marker := '"' + key + '"="'
		if requests.count(marker) != 1 { return error('Missing requested file: ' + key) }
		path := requests.all_after(marker).all_before('"')
		if !path.starts_with('C-4378__' + silicon.replace('=', '-') + '/') || path.count('/') != 1 || path.contains('..') || !path.bytes().all(it.is_alnum() || it in [
			u8(`/`),
			`_`,
			`-`,
			`.`,
			`=`,
		]) {
			return error('Unsafe or mismatched requested file: ' + key)
		}
		files << path
	}
	// Confirm Apple's explicit selection belongs to the identity we will bind.
	if files[0].all_after('/') != 'shikoku.trx' || files[1].all_after('/') != 'P-shikoku-${antenna}_M-${module_name}_V-${vendor}__m-${module_revision}.txt' || files[2].all_after('/') != 'shikoku-${antenna}.clmb' || files[3].all_after('/') != 'shikoku-${antenna}.txcb' {
		return error('Requested files disagree with board/module/antenna')
	}
	return MacWifi{revision, module_name, vendor, module_revision, antenna, 'apple,shikoku', quoted(property(core, 'FirmwareVersion')!)!, files}
}

pub fn package_macos(a PackageOptions, identity MacWifi) ! {
	if identity.revision !in [u8(3), 5] || identity.board != 'apple,shikoku' {
		return error('Unsupported macOS identity')
	}
	mut manifest := []u8{len: 128}
	manifest[0] = identity.revision
	for i, value in [identity.module_name, identity.vendor, identity.module_revision, identity.antenna,
		identity.board] {
		width := if i == 4 { 32 } else { 16 }
		if value == '' || value.len >= width || value.bytes().any(it < 32 || it > 126) {
			return error('Invalid manifest identity')
		}
		offset := 8 + 16 * i
		copy(mut manifest[offset..offset + value.len], value.bytes())
	}
	if identity.files.len != 4 { return error('Missing macOS file selection') }
	package_files(a, manifest, identity.files.map('macOS:/usr/share/firmware/wifi/' + it))!
}
