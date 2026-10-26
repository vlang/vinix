// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Installed Foundation has a 48-byte NSObject subclass. Private native ivars
// stay opaque; owning argument snapshots live in existing object metadata.
fn ns_process_info_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSProcessInfo' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic process info superclass chain')
}

fn ns_process_info_start(arguments []string) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.process_arguments != 0 || ios_runtime.process_info != 0 { panic('iOS: process arguments must be configured before process info queries') }
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	header.process_arguments_array = true
	for argument in arguments {
		text := owned_string(argument)
		array_append(mut header, text)
		objc_release(text)
	}
	ios_runtime.process_arguments = array
}

fn ns_process_info_default() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.process_info == 0 { ios_runtime.process_info = objc_allocate(ios_runtime.names['NSProcessInfo']) }
	return ios_runtime.process_info
}

fn ns_process_info_arguments(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := obj_header(object)
	if header.fields[0] == 0 {
		array := objc_allocate(ios_runtime.names['NSArray'])
		mut snapshot := obj_header(array)
		snapshot.process_arguments_array = true
		if ios_runtime.process_arguments != 0 {
			for argument in obj_header(ios_runtime.process_arguments).items { array_append(mut snapshot, argument) }
		}
		header.fields[0] = array
	}
	return header.fields[0]
}

fn ns_process_info_at_least(requested IosOperatingSystemVersion) bool {
	actual := ios_operating_system_version()
	if actual.major != requested.major { return actual.major > requested.major }
	if actual.minor != requested.minor { return actual.minor > requested.minor }
	return actual.patch >= requested.patch
}

fn ns_process_info_physical_memory() u64 {
	mut value := u64(0)
	mut length := usize(8)
	if sysctl_read_hardware(.memory, &value, &length, unsafe { nil }, 0) != 0 {
		panic('iOS: cannot query physical memory')
	}
	return value
}

fn ns_process_info_types(name string, meta bool, selector string) ?string {
	if name != 'NSProcessInfo' { return none }
	if meta {
		return match selector {
			'processInfo', 'alloc' { '@16@0:8' }
			'allocWithZone:' { '@24@0:8^{_NSZone=}16' }
			else { return none }
		}
	}
	return match selector {
		'init', 'arguments' { '@16@0:8' }
		'operatingSystemVersion' { '{?=qqq}16@0:8' }
		'physicalMemory' { 'Q16@0:8' }
		'isOperatingSystemAtLeastVersion:' { 'B40@0:8{?=qqq}16' }
		'isiOSAppOnMac', 'isMacCatalystApp' { 'B16@0:8' }
		else { return none }
	}
}

fn ns_process_info_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_process_info_family(if meta { object } else { read64(object) }) && ns_process_info_types('NSProcessInfo', meta, selector) != none
}

fn ns_process_info_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_process_info_family(if meta { object } else { read64(object) }) { return false }
	if !meta && selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { panic('iOS: process info copies are not implemented') }
	if ns_process_info_types('NSProcessInfo', meta, selector) == none { return false }
	if meta {
		frame.x[0] = if selector == 'processInfo' { ns_process_info_default() } else { objc_allocate(object) }
		return true
	}
	match selector {
		'init' {}
		'arguments' { frame.x[0] = ns_process_info_arguments(object) }
		'physicalMemory' { frame.x[0] = ns_process_info_physical_memory() }
		'operatingSystemVersion' {
			if frame.x[8] == 0 { panic('iOS: process info version requires an indirect result buffer') }
			// Darwin ARM64 returns this 24-byte aggregate through x8.
			unsafe { *(&IosOperatingSystemVersion(frame.x[8])) = ios_operating_system_version() }
		}
		'isOperatingSystemAtLeastVersion:' {
			// AAPCS64 passes aggregates larger than 16 bytes indirectly in x2.
			if frame.x[2] == 0 { panic('iOS: process info comparison requires an indirect version argument') }
			frame.x[0] = u64(ns_process_info_at_least(unsafe { *(&IosOperatingSystemVersion(frame.x[2])) }))
		}
		'isiOSAppOnMac', 'isMacCatalystApp' { frame.x[0] = 0 }
		else { return false }
	}
	return true
}
