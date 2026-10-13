// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public NSStream/NSInputStream bytes stay opaque (8/136 bytes on this Mac).
// fields[0/1] own the input/error; descriptor and cursor belong to metadata.
fn ns_input_stream_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSInputStream' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic input stream superclass chain')
}

fn ns_input_stream_require_class(cls u64) {
	if cls == ios_runtime.names['NSStream'] { panic('iOS: abstract NSStream construction is not implemented') }
	if ns_input_stream_family(cls) && cls != ios_runtime.names['NSInputStream'] { panic('iOS: custom input stream subclass construction is not implemented') }
}

fn ns_input_stream_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.input_stream_owned || !header.input_stream_initialized { panic('iOS: input stream is not initialized') }
	return header
}

fn ns_input_stream_initialize(object u64, input u64, kind int) u64 {
	mut header := obj_header(object)
	if !header.input_stream_owned { panic('iOS: input stream initialization requires owned metadata') }
	if header.input_stream_initialized { panic('iOS: input stream reinitialization is not implemented') }
	if input == 0 { panic('iOS: input stream requires nonnil data or file path') }
	mut source := input
	if kind == 2 {
		if !objc_is_kind(input, ios_runtime.names['NSURL']) || obj_header(input).number == 1 { panic('iOS: input stream requires a file NSURL') }
		source = obj_header(input).fields[0]
	}
	if kind == 0 {
		if !objc_is_kind(source, ios_runtime.names['NSData']) { panic('iOS: input stream requires NSData') }
		header.fields[0] = cf_data_create(0, data_pointer(source), i64(data_length(source)))
	} else {
		path := ns_file_manager_path(source)
		header.fields[0] = owned_string(path)
	}
	header.input_stream_file = kind != 0
	header.input_stream_initialized = true
	return object
}

fn ns_input_stream_error(mut header ObjHeader, native i32) {
	domain := owned_string('NSPOSIXErrorDomain')
	header.fields[1] = ns_error_create(domain, i64(darwin_native_error(native)), 0)
	objc_release(domain)
	header.input_stream_status = 7
}

fn ns_input_stream_open(object u64) {
	mut header := ns_input_stream_state(object)
	if header.input_stream_status != 0 { return }
	if header.input_stream_file {
		header.input_stream_fd = C.open(obj_header(header.fields[0]).text, C.O_RDONLY)
		if header.input_stream_fd < 0 { native := unsafe { *C.ios_errno_address() }; ns_input_stream_error(mut header, native); return }
		mut fields := [20]u64{}
		if C.ios_stat_info(unsafe { nil }, i32(header.input_stream_fd), 2, unsafe { &fields[0] }) != 0 { native := unsafe { *C.ios_errno_address() }; ns_input_stream_error(mut header, native); return }
		header.input_stream_directory = fields[1] & 0xf000 == 0x4000
	}
	header.input_stream_status = 2
}

fn ns_input_stream_close(object u64) {
	mut header := ns_input_stream_state(object)
	if header.input_stream_fd >= 0 { descriptor := header.input_stream_fd; header.input_stream_fd = -1; C.close(descriptor) }
	if header.input_stream_status != 7 { header.input_stream_status = 6 }
}

fn ns_input_stream_dispose(mut header ObjHeader) {
	if !header.input_stream_owned { return }
	if header.input_stream_fd >= 0 { descriptor := header.input_stream_fd; header.input_stream_fd = -1; C.close(descriptor) }
	// Generic destruction releases both fields, including after an isa change.
}

fn ns_input_stream_read(object u64, buffer u64, length u64) i64 {
	mut header := ns_input_stream_state(object)
	if length > 0x7fffffffffffffff || (buffer == 0 && length != 0) { panic('iOS: invalid input stream read buffer') }
	if header.input_stream_status == 5 { return 0 }
	if header.input_stream_status != 2 { return -1 }
	// Vinix's directory read currently returns zero. Foundation file streams
	// report POSIX EISDIR instead; inspect the opened descriptor, not its path.
	if header.input_stream_directory { ns_input_stream_error(mut header, C.EISDIR); return -1 }
	if !header.input_stream_file {
		source := header.fields[0]
		remaining := data_length(source) - header.input_stream_position
		count := if length < remaining { length } else { remaining }
		if count != 0 { unsafe { C.memcpy(voidptr(buffer), voidptr(data_pointer(source) + header.input_stream_position), usize(count)) } }
		header.input_stream_position += count
		if header.input_stream_position == data_length(source) { header.input_stream_status = 5 }
		return i64(count)
	}
	for {
		count := C.read(header.input_stream_fd, unsafe { voidptr(buffer) }, usize(length))
		if count < 0 {
			native := unsafe { *C.ios_errno_address() }
			if native == C.EINTR { continue }
			ns_input_stream_error(mut header, native)
		} else if count == 0 { header.input_stream_status = 5 }
		return i64(count)
	}
}

fn ns_input_stream_available(object u64) bool {
	header := ns_input_stream_state(object)
	return header.input_stream_status == 2 && (header.input_stream_file || header.input_stream_position < data_length(header.fields[0]))
}

fn ns_input_stream_buffer(object u64, output u64, length u64) bool {
	mut header := ns_input_stream_state(object)
	// This Mac's CF-backed NSData stream does not offer a direct byte buffer.
	readable := header.input_stream_status == 2 || header.input_stream_status == 5
	if !readable && output != 0 { unsafe { *(&u64(output)) = 0 } }
	if length != 0 { unsafe { *(&u64(length)) = if readable { u64(0) } else { ~u64(0) } } }
	if readable && !header.input_stream_file && header.input_stream_position == data_length(header.fields[0]) { header.input_stream_status = 5 }
	return !readable
}

fn ns_input_stream_types(name string, meta bool, selector string) ?string {
	if name !in ['NSStream', 'NSInputStream']! { return none }
	if meta {
		if name != 'NSInputStream' { return none }
		return match selector {
			'alloc' { '@16@0:8' }
			'allocWithZone:' { '@24@0:8^{_NSZone=}16' }
			'inputStreamWithData:', 'inputStreamWithFileAtPath:', 'inputStreamWithURL:' { '@24@0:8@16' }
			else { return none }
		}
	}
	return match selector {
		'initWithData:', 'initWithFileAtPath:', 'initWithURL:' { if name != 'NSInputStream' { return none }; '@24@0:8@16' }
		'open', 'close' { 'v16@0:8' }
		'streamStatus' { 'Q16@0:8' }
		'_cfTypeID' { if name != 'NSInputStream' { return none }; 'Q16@0:8' }
		'streamError', 'delegate' { '@16@0:8' }
		'hasBytesAvailable' { if name != 'NSInputStream' { return none }; 'B16@0:8' }
		'read:maxLength:' { if name != 'NSInputStream' { return none }; 'q32@0:8*16Q24' }
		'getBuffer:length:' { if name != 'NSInputStream' { return none }; 'B32@0:8^*16^Q24' }
		'propertyForKey:' { '@24@0:8@16' }
		'setProperty:forKey:' { 'B32@0:8@16@24' }
		else { return none }
	}
}

fn ns_input_stream_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_input_stream_family(if meta { object } else { read64(object) }) && ns_input_stream_types('NSInputStream', meta, selector) != none
}

fn ns_input_stream_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_input_stream_family(if meta { object } else { read64(object) }) { return false }
	if selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'setDelegate:', 'scheduleInRunLoop:forMode:', 'removeFromRunLoop:forMode:', 'initWithCoder:', 'encodeWithCoder:']! { panic('iOS: input stream default construction, copying, delegates, scheduling and coding are not implemented') }
	if ns_input_stream_types('NSInputStream', meta, selector) == none { return false }
	if meta {
		if selector in ['alloc', 'allocWithZone:']! { frame.x[0] = objc_allocate(object); return true }
		kind := if selector == 'inputStreamWithData:' { 0 } else if selector == 'inputStreamWithURL:' { 2 } else { 1 }
		frame.x[0] = objc_autorelease(ns_input_stream_initialize(objc_allocate(object), frame.x[2], kind))
		return true
	}
	if selector.starts_with('initWith') {
		kind := if selector == 'initWithData:' { 0 } else if selector == 'initWithURL:' { 2 } else { 1 }
		frame.x[0] = ns_input_stream_initialize(object, frame.x[2], kind)
		return true
	}
	header := ns_input_stream_state(object)
	match selector {
		'open' { ns_input_stream_open(object) }
		'close' { ns_input_stream_close(object) }
		'read:maxLength:' { frame.x[0] = u64(ns_input_stream_read(object, frame.x[2], frame.x[3])) }
		'getBuffer:length:' { frame.x[0] = u64(ns_input_stream_buffer(object, frame.x[2], frame.x[3])) }
		'hasBytesAvailable' { frame.x[0] = u64(ns_input_stream_available(object)) }
		'streamStatus' { frame.x[0] = header.input_stream_status }
		'streamError' { frame.x[0] = header.fields[1] }
		'_cfTypeID' { frame.x[0] = ios_runtime.names['NSInputStream'] }
		'delegate' { frame.x[0] = 0 }
		else {
			key := if selector == 'propertyForKey:' { frame.x[2] } else { frame.x[3] }
			if key == 0 || !objc_is_kind(key, ios_runtime.names['NSString']) { panic('iOS: input stream property requires NSString') }
			if string_text(key) in ['NSStreamFileCurrentOffsetKey', 'kCFStreamPropertyFileCurrentOffset']! && header.input_stream_file { panic('iOS: input stream file seeking is not implemented') }
			frame.x[0] = 0
		}
	}
	return true
}
