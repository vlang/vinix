// SPDX-License-Identifier: GPL-2.0-or-later
// Vinix has no SystemConfiguration proxy service. An explicit inherited
// VINIX_IOS_HTTP_PROXY=http://host[:port] supplies the HTTP configuration;
// absent configuration returns NULL, as CFNetwork's API contract permits.
module main

struct IOSHttpProxy {
	host string // Borrowed only until the owned dictionary has been constructed.
	port int
}

fn cfnetwork_parse_proxy(text string) ?IOSHttpProxy {
	if text.len > 512 || !text.starts_with('http://') { return none }
	mut end := text.len
	if end > 7 && text[end - 1] == `/` { end-- }
	mut colon := end
	for i in 7 .. end {
		if text[i] == `:` { if colon != end { return none }; colon = i }
	}
	if colon == 7 || colon - 7 > 253 { return none }
	mut label := 0
	for i in 7 .. colon {
		byte := text[i]
		if byte == `.` {
			if label == 0 || text[i - 1] == `-` { return none }
			label = 0
		} else {
			if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) ||
				(byte >= `0` && byte <= `9`) || byte == `-`) || (label == 0 && byte == `-`) { return none }
			label++
			if label > 63 { return none }
		}
	}
	if text[colon - 1] == `-` { return none }
	mut port := 80
	if colon < end {
		if colon + 1 == end { return none }
		port = 0
		for i in colon + 1 .. end {
			byte := text[i]
			if byte < `0` || byte > `9` { return none }
			port = port * 10 + int(byte - `0`)
			if port > 65535 { return none }
		}
		if port == 0 { return none }
	}
	return IOSHttpProxy{ host: unsafe { tos(text.str + 7, colon - 7) }, port: port }
}

fn cfnetwork_copy_proxy_settings() u64 {
	text := C.getenv(c'VINIX_IOS_HTTP_PROXY')
	if text == unsafe { nil } || unsafe { text[0] } == 0 { return 0 }
	mut length := 0
	for length < 513 && unsafe { text[length] } != 0 { length++ }
	proxy := cfnetwork_parse_proxy(unsafe { tos(&u8(text), length) }) or {
		// Do not silently turn an unsupported/invalid requested proxy into a
		// direct connection, or include credentials/configuration in this error.
		panic('iOS: HTTP proxy configuration is invalid or unsupported')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	dictionary := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	host := owned_string(proxy.host)
	port := objc_allocate(ios_runtime.names['NSNumber'])
	mut port_header := obj_header(port)
	port_header.number = proxy.port
	enabled := objc_allocate(ios_runtime.names['NSNumber'])
	mut enabled_header := obj_header(enabled)
	enabled_header.number = 1
	cfnetwork_proxy_field(dictionary, '_kCFNetworkProxiesHTTPEnable', enabled)
	cfnetwork_proxy_field(dictionary, '_kCFNetworkProxiesHTTPPort', port)
	cfnetwork_proxy_field(dictionary, '_kCFNetworkProxiesHTTPProxy', host)
	objc_release(host)
	objc_release(port)
	objc_release(enabled)
	objc_set_class(dictionary, ios_runtime.names['NSDictionary'])
	return dictionary
}

fn cfnetwork_proxy_field(dictionary u64, symbol string, value u64) {
	key := cfnetwork_symbol(symbol) or { panic('iOS: missing HTTP proxy key') }
	cf_dictionary_set(dictionary, read64(key), value)
}

fn cfnetwork_symbol(symbol string) ?u64 {
	if symbol == '_CFNetworkCopySystemProxySettings' { return u64(unsafe { voidptr(cfnetwork_copy_proxy_settings) }) }
	value := match symbol {
		'_kCFNetworkProxiesHTTPEnable' { 'HTTPEnable' }
		'_kCFNetworkProxiesHTTPPort' { 'HTTPPort' }
		'_kCFNetworkProxiesHTTPProxy' { 'HTTPProxy' }
		else { return none }
	}
	return framework_string_constant(symbol, value)
}
