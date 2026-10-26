// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ns_data_url_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSData' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic data superclass chain')
}

fn ns_data_url_types(name string, meta bool, selector string) ?string {
	if name == 'NSData' && meta && selector == 'dataWithContentsOfURL:' { return '@24@0:8@16' }
	return none
}

fn ns_data_url_selector(object u64, selector string) bool {
	return object in ios_runtime.classes && ns_data_url_family(object)
		&& ns_data_url_types('NSData', true, selector) != none
}

fn ns_data_url_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !ns_data_url_selector(object, selector) { return false }
	url := frame.x[2]
	if url == 0 || !objc_is_kind(url, ios_runtime.names['NSURL']) { panic('iOS: data loading requires NSURL') }
	if obj_header(url).number == 1 {
		frame.x[0] = data_http_load(url, object)
		return true
	}
	frame.x[0] = url_file_load(url, object, unsafe { nil }, unsafe { nil })
	return true
}
