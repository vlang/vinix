// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

type ConfigurationMessage = fn (u64, u64, u64, u64, u64) u64
type ConfigurationDoubleGet = fn (u64, u64) f64
type ConfigurationDoubleSet = fn (u64, u64, f64)
struct ConfigurationApi { native bool send u64 cls u64 strings u64 mutable_strings u64 dictionaries u64 arrays u64 }
fn (api ConfigurationApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return objc_selector(name)
}
fn (api ConfigurationApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { ConfigurationMessage(voidptr(api.send))(object, api.selector(name), a, b, 0) }
}
fn (api ConfigurationApi) get_double(object u64, name &char) f64 {
	return unsafe { ConfigurationDoubleGet(voidptr(api.send))(object, api.selector(name)) }
}
fn (api ConfigurationApi) set_double(object u64, name &char, value f64) {
	unsafe { ConfigurationDoubleSet(voidptr(api.send))(object, api.selector(name), value) }
}
fn (api ConfigurationApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0) }
fn (api ConfigurationApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0)) }
fn (api ConfigurationApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api ConfigurationApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api ConfigurationApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn configuration_runtime_api() ConfigurationApi {
	return ConfigurationApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSURLSessionConfiguration'], strings: ios_runtime.names['NSString'], mutable_strings: ios_runtime.names['NSMutableString'], dictionaries: ios_runtime.names['NSMutableDictionary'], arrays: ios_runtime.names['NSMutableArray']}
}

fn configuration_shared_base(api ConfigurationApi) {
	for construction in [c'alloc', c'new']! {
		pool := api.pool(); object := api.message(api.cls, construction, 0, 0)
		assert object != 0 && api.message(object, c'class', 0, 0) == api.cls
		assert read32(object + 8) == 6 && api.message(object, c'HTTPMaximumConnectionsPerHost', 0, 0) == 6
		for index, expected in [u32(6), 4, 2, 4, 0, 1]! { assert read32(object + 8 + u64(index * 4)) == expected }
		for index, expected in [f64(30), 1, 120, 120]! { assert unsafe { *(&f64(voidptr(object + 32 + u64(index * 8)))) } == expected }
		for getter in [c'identifier', c'sharedContainerIdentifier', c'connectionProxyDictionary', c'HTTPAdditionalHeaders', c'protocolClasses', c'requestCachePolicy', c'networkServiceType', c'HTTPCookieAcceptPolicy', c'multipathServiceType', c'TLSMinimumSupportedProtocol', c'TLSMaximumSupportedProtocol', c'allowsCellularAccess', c'allowsExpensiveNetworkAccess', c'allowsConstrainedNetworkAccess', c'waitsForConnectivity', c'isDiscretionary', c'sessionSendsLaunchEvents', c'HTTPShouldUsePipelining', c'HTTPShouldSetCookies', c'requiresDNSSECValidation']! {
			assert api.message(object, getter, 0, 0) == 0
		}
		assert api.get_double(object, c'timeoutIntervalForRequest') == 0.0 && api.get_double(object, c'timeoutIntervalForResource') == 0.0
		assert api.message(object, c'init', 0, 0) == object && api.message(object, c'init', 0, 0) == object
		api.release(object); api.drain(pool)
	}
}

fn configuration_shared_scalars(api ConfigurationApi) {
	pool := api.pool(); object := api.message(api.cls, c'new', 0, 0)
	for pair in [[c'requestCachePolicy', c'setRequestCachePolicy:']!, [c'networkServiceType', c'setNetworkServiceType:']!, [c'HTTPCookieAcceptPolicy', c'setHTTPCookieAcceptPolicy:']!, [c'multipathServiceType', c'setMultipathServiceType:']!]! {
		for value in [u64(0), 1, 13, 1099511627776, 0xfffffffffffffff9]! {
			api.message(object, pair[1], value, 0); assert api.message(object, pair[0], 0, 0) == value
		}
	}
	for pair in [[c'TLSMinimumSupportedProtocol', c'setTLSMinimumSupportedProtocol:']!, [c'TLSMaximumSupportedProtocol', c'setTLSMaximumSupportedProtocol:']!]! {
		for value in [u64(0), 1, 13, 1099511627776, 0xfffffff9]! {
			api.message(object, pair[1], value, 0); assert api.message(object, pair[0], 0, 0) == u64(u32(value))
		}
	}
	for value in [i64(-7), 0, 1, 13, 64, 1099511627776]! {
		api.message(object, c'setHTTPMaximumConnectionsPerHost:', u64(value), 0)
		assert api.message(object, c'HTTPMaximumConnectionsPerHost', 0, 0) == u64(i64(i32(value)))
		assert i32(read32(object + 8)) == i32(value)
	}
	for pair in [[c'allowsCellularAccess', c'setAllowsCellularAccess:']!, [c'allowsExpensiveNetworkAccess', c'setAllowsExpensiveNetworkAccess:']!, [c'allowsConstrainedNetworkAccess', c'setAllowsConstrainedNetworkAccess:']!, [c'waitsForConnectivity', c'setWaitsForConnectivity:']!, [c'isDiscretionary', c'setDiscretionary:']!, [c'sessionSendsLaunchEvents', c'setSessionSendsLaunchEvents:']!, [c'HTTPShouldUsePipelining', c'setHTTPShouldUsePipelining:']!, [c'HTTPShouldSetCookies', c'setHTTPShouldSetCookies:']!, [c'requiresDNSSECValidation', c'setRequiresDNSSECValidation:']!]! {
		for value in [u64(0), 1]! { api.message(object, pair[1], value, 0); assert api.message(object, pair[0], 0, 0) == value }
	}
	for pair in [[c'timeoutIntervalForRequest', c'setTimeoutIntervalForRequest:']!, [c'timeoutIntervalForResource', c'setTimeoutIntervalForResource:']!]! {
		for value in [f64(-1.5), 0.0, 17.25]! { api.set_double(object, pair[1], value); assert api.get_double(object, pair[0]) == value }
	}
	assert api.message(object, c'init', 0, 0) == object
	assert api.message(object, c'requestCachePolicy', 0, 0) == 0xfffffffffffffff9
	assert api.get_double(object, c'timeoutIntervalForRequest') == 17.25
	for selector in [c'copy', c'copyWithZone:']! {
		copied := api.message(object, selector, 0, 0)
		assert copied != object && api.message(copied, c'class', 0, 0) == api.cls
		assert api.message(copied, c'requestCachePolicy', 0, 0) == 0xfffffffffffffff9
		assert api.get_double(copied, c'timeoutIntervalForResource') == 17.25
		api.message(copied, c'setRequestCachePolicy:', 3, 0)
		assert api.message(object, c'requestCachePolicy', 0, 0) == 0xfffffffffffffff9
		api.release(copied)
	}
	api.release(object); api.drain(pool)
}

fn configuration_shared_objects(api ConfigurationApi) {
	pool := api.pool(); object := api.message(api.cls, c'new', 0, 0)
	for pair in [[c'identifier', c'setIdentifier:']!, [c'sharedContainerIdentifier', c'setSharedContainerIdentifier:']!]! {
		source := api.message(api.message(api.mutable_strings, c'alloc', 0, 0), c'initWithUTF8String:', u64(c'long immutable configuration snapshot😀'), 0)
		api.message(object, pair[1], source, 0); stored := api.message(object, pair[0], 0, 0)
		assert stored != source && api.text(stored) == 'long immutable configuration snapshot😀'
		api.message(source, c'setString:', api.string(c'changed source'), 0)
		assert api.text(api.message(object, pair[0], 0, 0)) == 'long immutable configuration snapshot😀'
		api.message(object, pair[1], stored, 0); api.release(source)
	}
	for pair in [[c'HTTPAdditionalHeaders', c'setHTTPAdditionalHeaders:']!, [c'connectionProxyDictionary', c'setConnectionProxyDictionary:']!, [c'protocolClasses', c'setProtocolClasses:']!]! {
		is_array := pair[0] == c'protocolClasses'
		source := api.message(if is_array { api.arrays } else { api.dictionaries }, c'new', 0, 0)
		if is_array { api.message(source, c'addObject:', api.strings, 0) }
		else { api.message(source, c'setObject:forKey:', api.string(c'value'), api.string(c'key')) }
		api.message(object, pair[1], source, 0); stored := api.message(object, pair[0], 0, 0)
		assert stored != source && api.message(stored, c'count', 0, 0) == 1
		api.message(source, c'removeAllObjects', 0, 0)
		assert api.message(stored, c'count', 0, 0) == 1
		api.message(object, pair[1], stored, 0); api.release(source)
	}
	for selector in [c'copy', c'copyWithZone:']! {
		copied := api.message(object, selector, 0, 0)
		for getter in [c'identifier', c'sharedContainerIdentifier', c'HTTPAdditionalHeaders', c'connectionProxyDictionary', c'protocolClasses']! {
			assert api.message(copied, getter, 0, 0) == api.message(object, getter, 0, 0)
		}
		api.message(copied, c'setIdentifier:', 0, 0)
		assert api.message(copied, c'identifier', 0, 0) == 0 && api.message(object, c'identifier', 0, 0) != 0
		api.release(copied)
	}
	retained := api.message(object, c'copy', 0, 0)
	api.release(object); api.drain(pool)
	after := api.pool()
	assert api.text(api.message(retained, c'identifier', 0, 0)) == 'long immutable configuration snapshot😀'
	assert api.message(api.message(retained, c'HTTPAdditionalHeaders', 0, 0), c'count', 0, 0) == 1
	api.release(retained); api.drain(after)
}

fn configuration_shared_defaults(api ConfigurationApi) {
	pool := api.pool()
	object := api.message(api.cls, c'defaultSessionConfiguration', 0, 0)
	other := api.message(api.cls, c'defaultSessionConfiguration', 0, 0)
	assert object != 0 && other != 0 && object != other
	assert api.message(object, c'class', 0, 0) == api.cls
	for name, expected in {'HTTPMaximumConnectionsPerHost': u64(6), 'allowsCellularAccess': 1,
		'allowsExpensiveNetworkAccess': 1, 'allowsConstrainedNetworkAccess': 1,
		'HTTPShouldSetCookies': 1, 'HTTPCookieAcceptPolicy': 2, 'TLSMinimumSupportedProtocol': 8,
		'TLSMaximumSupportedProtocol': 0, 'requestCachePolicy': 0, 'networkServiceType': 0,
		'waitsForConnectivity': 0, 'isDiscretionary': 0, 'sessionSendsLaunchEvents': 0,
		'HTTPShouldUsePipelining': 0, 'requiresDNSSECValidation': 0, 'multipathServiceType': 0,
		'identifier': 0, 'sharedContainerIdentifier': 0, 'HTTPAdditionalHeaders': 0,
		'connectionProxyDictionary': 0} {
		assert api.message(object, name.str, 0, 0) == expected, name
	}
	assert api.get_double(object, c'timeoutIntervalForRequest') == 60.0
	assert api.get_double(object, c'timeoutIntervalForResource') == 604800.0
	assert api.message(object, c'init', 0, 0) == object
	assert api.get_double(object, c'timeoutIntervalForRequest') == 60.0
	api.message(object, c'setAllowsCellularAccess:', 0, 0)
	api.set_double(object, c'setTimeoutIntervalForRequest:', 17.25)
	assert api.message(other, c'allowsCellularAccess', 0, 0) == 1
	assert api.get_double(other, c'timeoutIntervalForRequest') == 60.0
	// Explicit protocols replace the unresolved built-in transport profile.
	protocols := api.message(api.arrays, c'new', 0, 0)
	api.message(protocols, c'addObject:', api.strings, 0)
	api.message(object, c'setProtocolClasses:', protocols, 0)
	api.message(protocols, c'removeAllObjects', 0, 0); api.release(protocols)
	assert api.message(api.message(object, c'protocolClasses', 0, 0), c'count', 0, 0) == 1
	copy := api.message(object, c'copy', 0, 0)
	api.message(object, c'setProtocolClasses:', 0, 0)
	assert api.message(object, c'protocolClasses', 0, 0) == 0
	assert api.message(api.message(copy, c'protocolClasses', 0, 0), c'count', 0, 0) == 1
	api.drain(pool)
	after := api.pool()
	assert api.get_double(copy, c'timeoutIntervalForRequest') == 17.25
	assert api.message(copy, c'allowsCellularAccess', 0, 0) == 0
	assert api.message(api.message(copy, c'protocolClasses', 0, 0), c'count', 0, 0) == 1
	api.release(copy); api.drain(after)
}

fn configuration_defaults_worker(api ConfigurationApi) {
	for _ in 0 .. 16 { configuration_shared_defaults(api) }
}

fn configuration_encoding_cases(api ConfigurationApi) {
	for getter, encoding in {'identifier': '@', 'sharedContainerIdentifier': '@', 'connectionProxyDictionary': '@', 'HTTPAdditionalHeaders': '@', 'protocolClasses': '@', 'requestCachePolicy': 'Q', 'networkServiceType': 'Q', 'HTTPCookieAcceptPolicy': 'Q', 'multipathServiceType': 'q', 'HTTPMaximumConnectionsPerHost': 'q', 'TLSMinimumSupportedProtocol': 'i', 'TLSMaximumSupportedProtocol': 'i', 'timeoutIntervalForRequest': 'd', 'timeoutIntervalForResource': 'd', 'allowsCellularAccess': 'B', 'allowsExpensiveNetworkAccess': 'B', 'allowsConstrainedNetworkAccess': 'B', 'waitsForConnectivity': 'B', 'isDiscretionary': 'B', 'sessionSendsLaunchEvents': 'B', 'HTTPShouldUsePipelining': 'B', 'HTTPShouldSetCookies': 'B', 'requiresDNSSECValidation': 'B'} {
		setter := if getter == 'isDiscretionary' { 'setDiscretionary:' } else { 'set' + getter[0].ascii_str().to_upper() + getter[1..] + ':' }
		for name, expected in {getter: encoding + '16@0:8', setter: 'v' + (if encoding in ['B', 'i']! { '20' } else { '24' }) + '@0:8' + encoding + '16'} {
			mut actual := ''
			$if macos { if api.native { method := C.class_getInstanceMethod(unsafe { voidptr(api.cls) }, C.sel_registerName(name.str)); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
			if !api.native { method := objc_instance_method(api.cls, u64(name.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == expected, name + ': ' + actual + ' != ' + expected
		}
	}
}

fn test_url_session_configuration_native() {
	$if macos {
		api := ConfigurationApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSURLSessionConfiguration')), strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString')), dictionaries: u64(C.objc_getClass(c'NSMutableDictionary')), arrays: u64(C.objc_getClass(c'NSMutableArray'))}
		size := C.class_getInstanceSize(unsafe { voidptr(api.cls) })
		// Installed Foundation versions differ in private trailing storage. The
		// shared raw-record checks use only the measured common prefix; public
		// property/copy comparisons below still run against both native profiles.
		assert size in [usize(552), 560]! && C.class_getSuperclass(unsafe { voidptr(api.cls) }) == C.objc_getClass(c'NSObject')
		for name, offset in {'_limits': isize(8), '_identifier': 160, '_protocolClasses': 232, '_multipathServiceType': if size == 552 { 536 } else { 544 }} {
			ivar := C.class_getInstanceVariable(unsafe { voidptr(api.cls) }, name.str)
			assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == offset
		}
		configuration_encoding_cases(api); configuration_shared_base(api); configuration_shared_scalars(api); configuration_shared_objects(api)
		configuration_shared_defaults(api)
		println('IOS-SESSION-CONFIGURATION-NATIVE: base allocation and preserved init, typed settings, signed connection truncation, TLS widths, copied properties, independent configuration snapshots and copied owners after pool drainage')
		println('IOS-SESSION-DEFAULTS-NATIVE: fresh defaults, preserved init, mutation, protocol replacement and independent copies after pool drainage PASS')
	}
}

__global configuration_callback_api = ConfigurationApi{}
__global configuration_callback_source = u64(0)
__global configuration_callback_mode = 0
__global configuration_constructor_weak = u64(0)
fn configuration_constructor_worker() {
	api := configuration_callback_api
	pool := api.pool()
	api.message(configuration_callback_source, c'setIdentifier:', api.string(c'changed during copy allocation'), 0)
	api.message(configuration_callback_source, c'setRequestCachePolicy:', 99, 0)
	api.release(configuration_callback_source)
	api.drain(pool)
}
fn configuration_constructor(object u64, selector &char) u64 {
	if configuration_callback_mode == 0 { return object }
	api := configuration_callback_api
	mode := configuration_callback_mode; configuration_callback_mode = 0
	property := owned_string('constructor destination owner')
	api.message(object, c'setIdentifier:', property, 0); api.release(property)
	objc_store_weak(unsafe { &configuration_constructor_weak }, read64(object + 160))
	if mode == 1 { worker := spawn configuration_constructor_worker(); worker.wait(); return object }
	return 0
}
fn configuration_copy_worker() {
	api := configuration_callback_api
	assert api.message(configuration_callback_source, c'requestCachePolicy', 0, 0) == 17
	api.release(configuration_callback_source)
}
fn configuration_property_copy(object u64, selector &char) u64 {
	worker := spawn configuration_copy_worker(); worker.wait()
	return owned_string(string_text(object))
}
fn configuration_bad_property_copy(object u64, selector &char) u64 { return objc_new(ios_runtime.names['NSObject']) }
fn configuration_nil_property_copy(object u64, selector &char) u64 { return 0 }
fn configuration_runtime_callbacks(api ConfigurationApi) {
	configuration_callback_api = api
	pool := api.pool()
	assert objc_add_method(api.cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(configuration_constructor) }), c'@16@0:8')
	configuration_callback_source = api.message(api.cls, c'new', 0, 0)
	api.message(configuration_callback_source, c'setIdentifier:', api.string(c'snapshot before allocation'), 0)
	api.message(configuration_callback_source, c'setRequestCachePolicy:', 17, 0)
	mut source_weak := u64(0); objc_store_weak(unsafe { &source_weak }, configuration_callback_source)
	configuration_callback_mode = 1
	copied := api.message(configuration_callback_source, c'copy', 0, 0)
	assert copied != 0 && source_weak == 0 && configuration_constructor_weak == 0
	assert api.text(api.message(copied, c'identifier', 0, 0)) == 'snapshot before allocation'
	assert api.message(copied, c'requestCachePolicy', 0, 0) == 17
	api.release(copied); objc_destroy_weak(unsafe { &source_weak }); objc_destroy_weak(unsafe { &configuration_constructor_weak })
	configuration_callback_source = api.message(api.cls, c'new', 0, 0)
	api.message(configuration_callback_source, c'setIdentifier:', api.string(c'failed snapshot owner'), 0)
	configuration_callback_mode = 2
	assert api.message(configuration_callback_source, c'copy', 0, 0) == 0 && configuration_constructor_weak == 0
	api.release(configuration_callback_source); objc_destroy_weak(unsafe { &configuration_constructor_weak })
	configuration_callback_mode = 2
	assert api.message(api.cls, c'new', 0, 0) == 0 && configuration_constructor_weak == 0
	objc_destroy_weak(unsafe { &configuration_constructor_weak })
	configuration_callback_mode = 2
	assert api.message(api.cls, c'defaultSessionConfiguration', 0, 0) == 0 && configuration_constructor_weak == 0
	objc_destroy_weak(unsafe { &configuration_constructor_weak })
	custom := objc_allocate_class(api.strings, c'VinixConfigurationCopyString', 0)
	assert objc_add_method(custom, u64(c'copy'), u64(unsafe { voidptr(configuration_property_copy) }), c'@16@0:8'); objc_register_class(custom)
	property := owned_string('property copy callback')
	assert objc_set_class(property, custom) == api.strings
	configuration_callback_source = api.message(api.cls, c'new', 0, 0)
	api.message(configuration_callback_source, c'setRequestCachePolicy:', 17, 0)
	mut receiver_weak := u64(0); objc_store_weak(unsafe { &receiver_weak }, configuration_callback_source)
	// The custom copy drops the caller's last receiver owner and reads it from
	// another thread; the setter must pin it and invoke copy outside its lock.
	api.message(configuration_callback_source, c'setIdentifier:', property, 0)
	assert receiver_weak == 0
	objc_destroy_weak(unsafe { &receiver_weak }); api.release(property)
	configuration_callback_source = 0; api.drain(pool)
}

fn test_url_session_configuration_runtime() {
	for _ in 0 .. 2 {
		objc_start(); api := configuration_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSURLSessionConfiguration')! == api.cls
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSURLSessionConfiguration')! == read64(api.cls)
		assert objc_class_size(api.cls) == 560 && objc_class_parent(api.cls) == ios_runtime.names['NSObject']
		assert ios_runtime.classes[api.cls].ivars.len == 131
		for i, name in ['_identifier', '_requestCachePolicy', '_timeoutIntervalForRequest', '_sharedContainerIdentifier', '_HTTPAdditionalHeaders', '_protocolClasses', '_multipathServiceType']! {
			ivar := objc_find_ivar(api.cls, unsafe { &char(name.str) }); assert ivar != 0
			assert objc_ivar_offset(ivar) == [i64(160), 168, 176, 200, 224, 232, 544]![i]
			assert ctext(u64(objc_ivar_types(ivar))) == ['@"NSString"', 'Q', 'd', '@"NSString"', '@"NSDictionary"', '@"NSArray"', 'q']![i]
		}
		configuration_encoding_cases(api); configuration_shared_base(api); configuration_shared_scalars(api); configuration_shared_objects(api)
		factory_method := objc_class_method(api.cls, u64(c'defaultSessionConfiguration'))
		assert factory_method != 0 && ctext(u64(objc_method_types(factory_method))) == '@16@0:8'
		configuration_shared_defaults(api)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn configuration_defaults_worker(api) }
		workers.wait()
		pool_defaults := api.pool()
		mut factory_weak := u64(0)
		objc_store_weak(unsafe { &factory_weak }, api.message(api.cls, c'defaultSessionConfiguration', 0, 0))
		assert factory_weak != 0
		api.drain(pool_defaults); assert factory_weak == 0
		objc_destroy_weak(unsafe { &factory_weak })
		assert ios_runtime.live == 0
		configuration_runtime_callbacks(api); assert ios_runtime.live == 0
		mut guarded := [72]u64{}; guarded[0] = 0x1122334455667788; guarded[71] = 0x8877665544332211
		object := objc_construct_instance(api.cls, u64(unsafe { &guarded[1] }))
		assert read32(object + 8) == 6 && api.message(object, c'init', 0, 0) == object
		pool := api.pool(); source := api.message(api.mutable_strings, c'new', 0, 0)
		api.message(source, c'appendString:', api.string(c'caller-owned configuration'), 0)
		api.message(object, c'setIdentifier:', source, 0); api.release(source)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, api.message(object, c'identifier', 0, 0)); api.drain(pool)
		assert weak != 0 && objc_destruct_instance(object) == object && weak == 0 && read64(object + 160) == 0
		objc_destroy_weak(unsafe { &weak }); assert guarded[0] == 0x1122334455667788 && guarded[71] == 0x8877665544332211
		for _ in 0 .. 64 {
			inner := api.pool(); replaced := api.message(api.cls, c'new', 0, 0)
			api.message(replaced, c'setIdentifier:', api.string(c'configuration isa replacement'), 0)
			assert objc_set_class(replaced, ios_runtime.names['NSObject']) == api.cls
			api.release(replaced); api.drain(inner)
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		// Shutdown owns the final configuration and its copied property.
		last := objc_autorelease(api.message(api.cls, c'new', 0, 0))
		api.message(last, c'setIdentifier:', api.string(c'configuration shutdown'), 0)
		objc_stop(); assert ios_runtime.live == 0
	}
	println('IOS-SESSION-CONFIGURATION: typed settings and metadata, copied properties and snapshots, guarded caller storage,64 isa replacements and two drained runtimes')
	println('IOS-SESSION-DEFAULTS: fresh settings, explicit protocol replacement, copies across pool drainage, nil constructor, eight workers and two drained runtimes PASS')
}

fn test_url_session_configuration_rejections() {
	objc_start(); api := configuration_runtime_api()
	for mode in ['default-protocols', 'copied-default-protocols', 'default-subclass', 'ephemeral', 'background', 'cookie', 'cookie-set', 'credential', 'credential-set', 'cache', 'cache-set', 'tls-version', 'idle', 'proxies', 'mutable', 'coding', 'description', 'hash', 'equal', 'string-type', 'dictionary-type', 'array-type', 'bad-copy', 'nil-copy', 'large', 'raw', 'subclass', 'caller-subclass', 'spoof', 'nan', 'infinite']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := api.message(api.cls, c'new', 0, 0)
			match mode {
				'default-protocols', 'copied-default-protocols' {
					defaults := api.message(api.cls, c'defaultSessionConfiguration', 0, 0)
					api.message(if mode == 'default-protocols' { defaults } else { api.message(defaults, c'copy', 0, 0) }, c'protocolClasses', 0, 0)
				}
				'default-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedDefaultConfigurationSubclass', 0); objc_register_class(sub)
					api.message(sub, c'defaultSessionConfiguration', 0, 0)
				}
				'ephemeral' { api.message(api.cls, c'ephemeralSessionConfiguration', 0, 0) }
				'background' { api.message(api.cls, c'backgroundSessionConfigurationWithIdentifier:', api.string(c'background'), 0) }
				'cookie' { api.message(object, c'HTTPCookieStorage', 0, 0) }
				'cookie-set' { api.message(object, c'setHTTPCookieStorage:', 0, 0) }
				'credential' { api.message(object, c'URLCredentialStorage', 0, 0) }
				'credential-set' { api.message(object, c'setURLCredentialStorage:', 0, 0) }
				'cache' { api.message(object, c'URLCache', 0, 0) }
				'cache-set' { api.message(object, c'setURLCache:', 0, 0) }
				'tls-version' { api.message(object, c'TLSMinimumSupportedProtocolVersion', 0, 0) }
				'idle' { api.message(object, c'shouldUseExtendedBackgroundIdleMode', 0, 0) }
				'proxies' { api.message(object, c'proxyConfigurations', 0, 0) }
				'mutable' { api.message(object, c'mutableCopy', 0, 0) }
				'coding' { api.message(object, c'initWithCoder:', 0, 0) }
				'description' { api.message(object, c'description', 0, 0) }
				'hash' { api.message(object, c'hash', 0, 0) }
				'equal' { api.message(object, c'isEqual:', object, 0) }
				'string-type' { api.message(object, c'setIdentifier:', api.message(ios_runtime.names['NSObject'], c'new', 0, 0), 0) }
				'dictionary-type' { api.message(object, c'setHTTPAdditionalHeaders:', api.string(c'not a dictionary'), 0) }
				'array-type' { api.message(object, c'setProtocolClasses:', api.string(c'not an array'), 0) }
				'bad-copy', 'nil-copy' {
					custom := objc_allocate_class(api.strings, c'VinixConfigurationBadCopyString', 0)
					implementation := if mode == 'bad-copy' { u64(unsafe { voidptr(configuration_bad_property_copy) }) } else { u64(unsafe { voidptr(configuration_nil_property_copy) }) }
					assert objc_add_method(custom, u64(c'copy'), implementation, c'@16@0:8'); objc_register_class(custom)
					api.message(object, c'setIdentifier:', objc_new(custom), 0)
				}
				'large', 'raw' {
					values := api.message(api.arrays, c'new', 0, 0)
					if mode == 'raw' { obj_header(values).cf_raw_values = true }
					else { for _ in 0 .. 1025 { api.message(values, c'addObject:', api.strings, 0) } }
					api.message(object, c'setProtocolClasses:', values, 0)
				}
				'subclass', 'caller-subclass' {
					sub := objc_allocate_class(api.cls, c'VinixUnsupportedConfigurationSubclass', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { mut storage := [70]u64{}; objc_construct_instance(sub, u64(unsafe { &storage[0] })) }
				}
				'spoof' {
					spoof_class := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixConfigurationSpoof', 0)
					assert objc_add_ivar(spoof_class, c'bytes', 552, 3, c'[552C]'); objc_register_class(spoof_class)
					spoof := objc_new(spoof_class); objc_set_class(spoof, api.cls)
					api.message(spoof, c'requestCachePolicy', 0, 0)
				}
				else { bits := if mode == 'nan' { u64(0x7ff8000000000000) } else { u64(0x7ff0000000000000) }; api.set_double(object, c'setTimeoutIntervalForRequest:', unsafe { *(&f64(voidptr(&bits))) }) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'string-type', 'dictionary-type', 'array-type', 'bad-copy' { 'configuration property has the wrong object type' }
			'nil-copy' { 'configuration property copy returned nil' }
			'large', 'raw' { 'configuration collections require at most 1024 owned objects' }
			'subclass', 'caller-subclass', 'default-subclass' { 'custom session configuration subclass construction is not implemented' }
			'default-protocols', 'copied-default-protocols' { 'default session protocol classes are not implemented' }
			'spoof' { 'session configuration requires live base configuration storage' }
			'nan', 'infinite' { 'configuration timeouts require finite values' }
			else { 'configuration factories, stores, coding and this property are not implemented' }
		}
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
		if mode in ['ephemeral', 'background', 'cookie', 'cookie-set', 'credential', 'credential-set', 'cache', 'cache-set', 'tls-version', 'idle', 'proxies', 'mutable', 'coding', 'description', 'hash', 'equal']! {
			selector := match mode {
				'ephemeral' { 'ephemeralSessionConfiguration' }
				'background' { 'backgroundSessionConfigurationWithIdentifier:' }
				'cookie' { 'HTTPCookieStorage' }
				'cookie-set' { 'setHTTPCookieStorage:' }
				'credential' { 'URLCredentialStorage' }
				'credential-set' { 'setURLCredentialStorage:' }
				'cache' { 'URLCache' }
				'cache-set' { 'setURLCache:' }
				'tls-version' { 'TLSMinimumSupportedProtocolVersion' }
				'idle' { 'shouldUseExtendedBackgroundIdleMode' }
				'proxies' { 'proxyConfigurations' }
				'mutable' { 'mutableCopy' }
				'coding' { 'initWithCoder:' }
				'description' { 'description' }
				'hash' { 'hash' }
				else { 'isEqual:' }
			}
			assert output.contains(reason + ': ' + selector + '\n'), output
		}
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-SESSION-CONFIGURATION-REJECT:31 factory, unresolved protocols, storage, modern TLS, idle, proxy, copy, coding, type, nil copy, collection, subclass, spoof and nonfinite cases fail explicitly')
}
