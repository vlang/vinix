// SPDX-License-Identifier: GPL-2.0-only
module initcore

fn C.vinix_init_power_signal(i32)
fn C.vinix_init_child_signal(i32)
fn C.vinit_signal_restorer()

// Register the exported C wrappers, whose addresses differ from the V bodies.
@[export: 'vinit_power_callback']
pub fn power_callback() voidptr {
	return voidptr(C.vinix_init_power_signal)
}

@[export: 'vinit_child_callback']
pub fn child_callback() voidptr {
	return voidptr(C.vinix_init_child_signal)
}

fn host_signal_restorer() {}

@[export: 'vinit_restorer']
pub fn restorer() voidptr {
	$if init_host ? {
		return voidptr(host_signal_restorer)
	} $else {
		return voidptr(C.vinit_signal_restorer)
	}
}

@[export: 'vinit_wifi_enabled']
pub fn wifi_enabled() i32 {
	$if init_wifi_bundle ? { return 1 } $else { return 0 }
}

@[export: 'vinit_echo_enabled']
pub fn echo_enabled() i32 {
	$if init_busybox_echo_test ? { return 1 } $else { return 0 }
}
