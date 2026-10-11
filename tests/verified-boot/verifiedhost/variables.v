// SPDX-License-Identifier: GPL-2.0-or-later
// Offline EDK II authenticated variable-store editor, for private QEMU fixtures.
// Layout authority: MdeModulePkg/Include/Guid/VariableFormat.h and
// MdePkg/Include/Guid/ImageAuthentication.h in upstream EDK II.
module verifiedhost

import bundlehost as bh
import encoding.hex
import os
import time

fn guid(value string) []u8 { return hex.decode(value) or { panic(err) } }

fn word32(data []u8, offset int) !u32 {
	if offset < 0 || offset > data.len - 4 { return error('Truncated firmware variable store') }
	return u32(data[offset]) | (u32(data[offset + 1]) << 8) | (u32(data[offset + 2]) << 16) | (u32(data[offset + 3]) << 24)
}

fn aligned(value int) int { return (value + 3) & ~3 }

struct Variable {
	name   string
	vendor []u8
	bytes  []u8
}

fn variable(name string, vendor []u8, payload []u8, attributes u32) Variable {
	mut encoded := []u8{}
	for byte in name.bytes() { encoded << [byte, u8(0)] }
	encoded << [u8(0), 0]
	mut data := []u8{len: 60}
	put16(mut data, 0, 0x55aa)
	data[2] = 0x3f
	put32(mut data, 4, attributes)
	if attributes & 0x20 != 0 {
		now := time.utc()
		put16(mut data, 16, u16(now.year))
		data[18] = u8(now.month)
		data[19] = u8(now.day)
		data[20] = u8(now.hour)
		data[21] = u8(now.minute)
		data[22] = u8(now.second)
	}
	put32(mut data, 36, u32(encoded.len))
	put32(mut data, 40, u32(payload.len))
	for i, b in vendor { data[44 + i] = b }
	data << encoded
	data << payload
	for data.len % 4 != 0 { data << u8(0xff) }
	return Variable{name, vendor, data}
}

fn variable_name(data []u8) !string {
	if data.len < 2 || data.len % 2 != 0 || data[data.len - 2..] != [u8(0), 0] {
		return error('Invalid firmware variable name')
	}
	// Existing UTF-16 names are compared by their raw bytes below; retain non-ASCII names.
	mut name := ''
	for i := 0; i < data.len - 2; i += 2 {
		if data[i + 1] != 0 || data[i] == 0 { return '' }
		name += data[i].ascii_str()
	}
	return name
}

pub fn enroll_variables(template string, certificate string, output string) ! {
	if os.real_path(template) == os.real_path(output) {
		return error('Firmware template and output must differ')
	}
	if os.exists(output) || os.is_link(output) {
		return error('Firmware variable output already exists')
	}
	if os.file_size(template) > 256 * 1024 * 1024 { return error('Firmware template is too large') }
	mut data := os.read_bytes(template)!
	if data.len < 28 { return error('Truncated firmware variable store') }
	signature := guid('782cf3aa7b949a43a1802e144ec37792')
	mut stores := []int{}
	for position in 0 .. data.len - 28 {
		if data[position] == signature[0] && data[position..position + 16] == signature && data[position + 20] == 0x5a && data[position + 21] == 0xfe {
			stores << position
		}
	}
	if stores.len != 1 {
		return error('Expected exactly one healthy EDK II authenticated variable store')
	}
	start := stores[0]
	size := u64(word32(data, start + 16)!)
	if size < 28 || size > u64(data.len - start) {
		return error('Invalid firmware variable-store extent')
	}
	end := start + int(size)
	mut current := aligned(start + 28)
	mut variables := []Variable{}
	for current < end {
		if data[current..end].all(it == 0xff) { break }
		if current > end - 60 || data[current..current + 2] != [u8(0xaa), 0x55] {
			return error('Invalid firmware variable header')
		}
		names := u64(word32(data, current + 36)!)
		bytes := u64(word32(data, current + 40)!)
		total := u64(60) + names + bytes
		if names < 2 || names % 2 != 0 || total > u64(end - current) {
			return error('Invalid firmware variable extent')
		}
		next := aligned(current + int(total))
		if next > end { return error('Invalid firmware variable padding') }
		if data[current + 2] in [u8(0x3f), 0x3e] {
			name := variable_name(data[current + 60..current + 60 + int(names)])!
			vendor := data[current + 44..current + 60].clone()
			// Last live record wins after garbage collection.
			variables = variables.filter(!(it.name == name && it.vendor == vendor && name != ''))
			mut record := data[current..next].clone()
			record[2] = 0x3f
			variables << Variable{name, vendor, record}
		}
		current = next
	}
	der := bh.temporary(os.dir(output), '.vinix-firmware-')!
	defer { bh.retire(der) }
	bh.quiet(['openssl', 'x509', '-in', certificate, '-outform', 'DER', '-out',
		der + '/certificate.der'])!
	cert := os.read_bytes(der + '/certificate.der')!
	if cert.len < 32 || cert.len > 65536 || cert[0] != 0x30 {
		return error('Invalid DER certificate for firmware trust anchor')
	}
	mut list := []u8{len: 28}
	for i, b in guid('a159c0a5e494a74a87b5ab155c2bf072') { list[i] = b }
	put32(mut list, 16, u32(44 + cert.len))
	put32(mut list, 24, u32(16 + cert.len))
	list << guid('e796b3d4d6cd484aa2d1d62a4c6e02ce')
	list << cert
	global := guid('61dfe48bca93d211aa0d00e098032b8c')
	database := guid('cbb219d73a3d9645a3bcdad00e67656f')
	secure := guid('c70ba3f008af564599c4001009c93a44')
	custom := guid('0cec76c028709943a07271ee5c448b9f')
	additions := [variable('PK', global, list, 0x27), variable('KEK', global, list, 0x27),
		variable('db', database, list, 0x27), variable('SecureBootEnable', secure, [u8(1)], 3),
		variable('CustomMode', custom, [u8(0)], 3)]
	variables = variables.filter(!((it.vendor == global && it.name in ['PK', 'KEK', 'SecureBoot',
		'SetupMode', 'AuditMode', 'DeployedMode']) || (it.vendor == database && it.name in [
		'db',
		'dbx',
		'dbt',
	]) || (it.vendor == secure && it.name == 'SecureBootEnable') || (it.vendor == custom && it.name == 'CustomMode')))
	variables << additions
	mut replacement := []u8{}
	for entry in variables { replacement << entry.bytes }
	begin := aligned(start + 28)
	if replacement.len > end - begin {
		return error('Temporary firmware trust anchor exceeds variable-store capacity')
	}
	for i in begin .. end { data[i] = 0xff }
	for i, b in replacement { data[begin + i] = b }
	os.write_file_array(output, data)!
	os.chmod(output, 0o600)!
}
