// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct AbiNSError {
mut:
	isa       u64
	reserved  u64
	code      i64
	domain    u64
	user_info u64
}

fn json_null() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.null_object == 0 {
		ios_runtime.null_object = objc_allocate(ios_runtime.names['NSNull'])
		ios_runtime.framework_objects << ios_runtime.null_object
	}
	return ios_runtime.null_object
}

fn ns_error_create(domain u64, code i64, info u64) u64 {
	if !objc_is_kind(domain, ios_runtime.names['NSString']) {
		panic('iOS: NSError requires a string domain')
	}
	if info != 0 && !objc_is_kind(info, ios_runtime.names['NSDictionary']) {
		panic('iOS: NSError userInfo must be a dictionary')
	}
	object := objc_allocate(ios_runtime.names['NSError'])
	mut record := unsafe { &AbiNSError(object) }
	record.code = code
	record.domain = owned_string(string_text(domain))
	record.user_info = objc_allocate(ios_runtime.names['NSDictionary'])
	if info != 0 {
		source := obj_header(info)
		mut target := obj_header(record.user_info)
		for i, key in source.keys {
			if !objc_is_kind(key, ios_runtime.names['NSString']) {
				panic('iOS: NSError userInfo keys must be strings')
			}
			target.keys << owned_string(string_text(key))
			array_append(mut target, source.items[i])
		}
	}
	return object
}

fn ns_error_dispose(object u64) {
	if !objc_is_kind(object, ios_runtime.names['NSError']) { return }
	mut record := unsafe { &AbiNSError(object) }
	objc_release(record.domain)
	objc_release(record.user_info)
	record.domain = 0
	record.user_info = 0
}

fn json_error(output u64, reason string) {
	if output == 0 { return }
	domain := owned_string('NSCocoaErrorDomain')
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	key := owned_string('NSDebugDescription')
	detail := owned_string(reason)
	mut header := obj_header(info)
	header.keys << objc_retain(key)
	array_append(mut header, detail)
	object := ns_error_create(domain, 3840, info)
	objc_release(domain)
	objc_release(info)
	objc_release(key)
	objc_release(detail)
	unsafe { *(&u64(output)) = objc_autorelease(object) }
}

fn json_builtin_types(name string, meta bool, selector string) ?string {
	if meta && name == 'NSJSONSerialization' {
		return match selector {
			'JSONObjectWithData:options:error:', 'dataWithJSONObject:options:error:' {
				'@40@0:8@16Q24^@32'
			}
			'isValidJSONObject:' { 'B24@0:8@16' }
			else { return none }
		}
	}
	if name == 'NSNull' && meta && selector == 'null' { return '@16@0:8' }
	if name == 'NSError' && !meta {
		return match selector {
			'code' { 'q16@0:8' }
			'domain', 'userInfo', 'localizedDescription', 'description' { '@16@0:8' }
			else { return none }
		}
	}
	if name == 'NSError' && meta && selector == 'errorWithDomain:code:userInfo:' {
		return '@40@0:8@16q24@32'
	}
	return none
}

fn json_selector(object u64, selector string) bool {
	info := ios_runtime.classes[objc_class(object)] or { return false }
	if _ := json_builtin_types(info.name, object in ios_runtime.classes, selector) { return true }
	return false
}

fn json_operation(read bool, object u64, options u64) !u64 {
	if read { return json_read(object, options)! }
	return json_write(object, options)!
}

fn json_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object == ios_runtime.names['NSNull'] && selector == 'null' {
		frame.x[0] = json_null()
		return true
	}
	if object == ios_runtime.names['NSError'] && selector == 'errorWithDomain:code:userInfo:' {
		frame.x[0] = objc_autorelease(ns_error_create(frame.x[2], i64(frame.x[3]), frame.x[4]))
		return true
	}
	if object == ios_runtime.names['NSJSONSerialization'] {
		match selector {
			'isValidJSONObject:' { frame.x[0] = u64(json_valid(frame.x[2])) }
			'JSONObjectWithData:options:error:', 'dataWithJSONObject:options:error:' {
				result := json_operation(selector.starts_with('JSONObject'), frame.x[2], frame.x[3]) or {
					json_error(frame.x[4], err.msg())
					frame.x[0] = 0
					return true
				}
				// Foundation leaves a preexisting error output untouched on success.
				frame.x[0] = objc_autorelease(result)
			}
			else { return false }
		}
		return true
	}
	if object in ios_runtime.classes || !objc_is_kind(object, ios_runtime.names['NSError']) {
		return false
	}
	record := unsafe { &AbiNSError(object) }
	match selector {
		'code' { frame.x[0] = u64(record.code) }
		'domain' { frame.x[0] = record.domain }
		'userInfo' { frame.x[0] = record.user_info }
		'description' { frame.x[0] = objc_autorelease(ns_error_description(object) or { panic(err) }) }
		'localizedDescription' {
			mut header := obj_header(object)
			if header.fields[0] == 0 {
				if record.user_info != 0 {
					for i, key in obj_header(record.user_info).keys {
						if string_text(key) == 'NSLocalizedDescription' && objc_is_kind(obj_header(record.user_info).items[i], ios_runtime.names['NSString']) {
							header.fields[0] = objc_retain(obj_header(record.user_info).items[i])
							break
						}
					}
				}
				if header.fields[0] == 0 {
					domain := string_text(record.domain)
					if domain == 'NSCocoaErrorDomain' && record.code == 3840 {
						header.fields[0] = owned_string('The data couldn’t be read because it isn’t in the correct format.')
					} else {
						mut code := [32]u8{}
						C.snprintf(unsafe { &char(&code[0]) }, code.len, c'%lld', record.code)
						text := 'The operation couldn’t be completed. (' + (if domain == 'NSCocoaErrorDomain' {
							'Cocoa'
						} else {
							domain
						}) + ' error ' + ctext(u64(unsafe { &code[0] })) + '.)'
						header.fields[0] = owned_string(text)
						unsafe { text.free() }
					}
				}
			}
			frame.x[0] = header.fields[0]
		}
		else { return false }
	}
	return true
}
