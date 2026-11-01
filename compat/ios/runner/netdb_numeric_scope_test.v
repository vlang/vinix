// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NetdbScopeBuffers {
	host_length     u32 = 126
	service_length  u32 = 30
	host_missing    bool
	service_missing bool
}

struct NetdbScopeOutput {
mut:
	result       i32
	error_number i32
	host         [128]u8
	service      [32]u8
}

// Deliberately unaligned Darwin sockaddr, surrounded by input canaries.
fn netdb_scope_address(ipv6 bool, scope u32) [32]u8 {
	mut bytes := [32]u8{init: 0xa5}
	length := if ipv6 { 28 } else { 16 }
	for i in 1 .. length + 1 { bytes[i] = 0 }
	bytes[1] = u8(length)
	bytes[2] = if ipv6 { 30 } else { 2 }
	bytes[3] = 1
	bytes[4] = 187 // Network-order port 443.
	if ipv6 {
		assert C.inet_pton(C.AF_INET6, c'fe80::1234', unsafe { &bytes[9] }) == 1
		unsafe { C.memcpy(&bytes[25], &scope, sizeof(scope)) }
	} else {
		assert C.inet_pton(C.AF_INET, c'127.0.0.1', unsafe { &bytes[5] }) == 1
	}
	return bytes
}

fn netdb_scope_query(address [32]u8, length u32, flags i32, buffers NetdbScopeBuffers) NetdbScopeOutput {
	mut input := address
	before := input
	mut output := NetdbScopeOutput{}
	for i in 0 .. output.host.len { output.host[i] = 0xa5 }
	for i in 0 .. output.service.len { output.service[i] = 0x5a }
	darwin_set_errno(177)
	output.result = darwin_getnameinfo(unsafe { &input[1] }, length,
		if buffers.host_missing { unsafe { nil } } else { unsafe { &char(&output.host[1]) } },
		buffers.host_length,
		if buffers.service_missing { unsafe { nil } } else { unsafe { &char(&output.service[1]) } },
		buffers.service_length, flags)
	output.error_number = unsafe { *C.ios_errno_address() }
	assert input == before
	return output
}

// Empty expected text means the complete buffer must remain untouched. Check
// every byte, including both canaries and the unused part of each output.
fn netdb_scope_bytes(actual []u8, expected string, canary u8) {
	for i, value in actual {
		wanted := if expected.len > 0 && i > 0 && i <= expected.len {
			expected[i - 1]
		} else if expected.len > 0 && i == expected.len + 1 {
			u8(0)
		} else {
			canary
		}
		assert value == wanted, 'output byte ${i}: ${value}, expected ${wanted}'
	}
}

fn netdb_scope_expect(output NetdbScopeOutput, result i32, host string, service string) {
	assert output.result == result
	assert output.error_number == 177
	netdb_scope_bytes(output.host[..], host, 0xa5)
	netdb_scope_bytes(output.service[..], service, 0x5a)
}

fn netdb_scope_native(address [32]u8) string {
	mut storage := [16]u64{}
	assert socket_address_in(unsafe { &address[1] }, 28, unsafe { &storage[0] })
	mut host := [128]char{}
	mut service := [32]char{}
	assert C.getnameinfo(unsafe { &storage[0] }, 28, unsafe { &host[0] }, 128,
		unsafe { &service[0] }, 32, i32(C.NI_NUMERICHOST | C.NI_NUMERICSERV)) == 0
	assert ctext(u64(unsafe { &service[0] })) == '443'
	return ctext(u64(unsafe { &host[0] })).clone()
}

fn test_netdb_numeric_scope() {
	mut interface_name := c'lo'
	$if macos {
		interface_name = c'lo0'
	}
	scope := C.if_nametoindex(interface_name)
	assert scope != 0
	address := netdb_scope_address(true, scope)
	default_host := netdb_scope_native(address)
	numeric_host := 'fe80::1234%${scope}'
	$if linux {
		// This proves the fixture actually distinguishes a named zone from a
		// numeric one, rather than passing because libc was already numeric.
		assert default_host == 'fe80::1234%lo'
		assert default_host != numeric_host
	}
	// All native lookups request numeric host and service: no DNS is used.
	netdb_scope_expect(netdb_scope_query(address, 28, 10, NetdbScopeBuffers{}), 0,
		default_host, '443')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{}), 0,
		numeric_host, '443')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_length:    u32(numeric_host.len + 1)
		service_length: 4
	}), 0, numeric_host, '443')
	// Darwin checks/copies host first. Host overflow touches neither output;
	// service overflow preserves the successful host and leaves service alone.
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_length: u32(numeric_host.len)
	}), 14, '', '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		service_length: 3
	}), 14, numeric_host, '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_length:    1
		service_length: 1
	}), 14, '', '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_length:    0
		service_length: 0
	}), 0, '', '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_missing: true
	}), 0, '', '443')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		service_missing: true
	}), 0, numeric_host, '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266, NetdbScopeBuffers{
		host_missing:    true
		service_missing: true
	}), 0, '', '')
	// Full sockaddr validation and flag validation precede the resolver and
	// numeric-scope read, preserving the caller's outputs and errno on error.
	netdb_scope_expect(netdb_scope_query(address, 27, 266, NetdbScopeBuffers{}), 5, '', '')
	netdb_scope_expect(netdb_scope_query(address, 28, 266 | 512, NetdbScopeBuffers{}), 3, '', '')
	netdb_scope_expect(netdb_scope_query(netdb_scope_address(true, 0), 28, 266,
		NetdbScopeBuffers{}), 0, 'fe80::1234', '443')
	netdb_scope_expect(netdb_scope_query(netdb_scope_address(true, ~u32(0)), 28, 266,
		NetdbScopeBuffers{}), 0, 'fe80::1234%4294967295', '443')
	netdb_scope_expect(netdb_scope_query(netdb_scope_address(false, scope), 16, 266,
		NetdbScopeBuffers{}), 0, '127.0.0.1', '443')
	println('IOS-NETDB-NUMERIC-SCOPE: real libc named/numeric IPv6 zones, IPv4, unaligned input, overflow order, canaries and errno passed without DNS')
}

fn test_netdb_numeric_scope_preserves_names() {
	for name in ['localhost', 'name%zone', 'not:an:ipv6:address',
		'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] {
		mut host := [1025]char{}
		unsafe { C.memcpy(&host[0], name.str, name.len) }
		before := host
		netdb_numeric_scope(mut host, 1)
		assert host == before
	}
	mut no_scope := [1025]char{}
	unchanged := 'fe80::1%lo'
	unsafe { C.memcpy(&no_scope[0], unchanged.str, unchanged.len) }
	before := no_scope
	netdb_numeric_scope(mut no_scope, 0)
	assert no_scope == before
	for original in ['fe80::1%lo', 'fe80::1%4294967295', 'fe80::1'] {
		mut scoped := [1025]char{init: 0x5a}
		unsafe { C.memcpy(&scoped[0], original.str, original.len) }
		scoped[original.len] = 0
		old_bytes := scoped
		netdb_numeric_scope(mut scoped, 7)
		expected := 'fe80::1%7'
		assert ctext(u64(unsafe { &scoped[0] })) == expected
		for i in expected.len + 1 .. scoped.len {
			assert scoped[i] == old_bytes[i]
		}
	}
	// Longest numeric IPv6 literal plus the largest scope still fits, without
	// touching any byte beyond the new terminator.
	literal := 'ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255'
	assert literal.len == 45
	mut host := [1025]char{init: 0x5a}
	unsafe { C.memcpy(&host[0], literal.str, literal.len) }
	host[literal.len] = 0
	netdb_numeric_scope(mut host, ~u32(0))
	expected := literal + '%4294967295'
	assert ctext(u64(unsafe { &host[0] })) == expected
	for i in expected.len + 1 .. host.len {
		assert host[i] == char(0x5a)
	}
	println('IOS-NETDB-SCOPE-NAMES: names, unchanged zero scope, suffix replacement, maximum IPv6 text and u32 scope passed')
}
