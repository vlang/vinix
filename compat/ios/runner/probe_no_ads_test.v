// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

fn test_probe_no_ads_binding_is_explicit_and_scoped() {
	objc_start()
	library := '/System/Library/Frameworks/StoreKit.framework/StoreKit'
	symbol := '_OBJC_CLASS_$_SKAdNetwork'
	for auditing in [false, true]! {
		modules_start(macho.Image{}, macho.Layout{}, 1, '/probe', auditing)
		assert !module_runtime.probe_no_ads
		if _ := module_bind_symbol(library, symbol) { assert false }
		module_runtime.probe_no_ads = true
		if auditing {
			if _ := module_bind_symbol(library, symbol) { assert false }
		} else {
			assert module_bind_symbol(library, symbol)! == 0
			// Nil Objective-C class messaging has the expected zero result.
			assert unsafe { ProbeNilSend(voidptr(C.ios_objc_msgsend))(0, u64(c'class')) } == 0
		}
		// The diagnostic must not change audits, dlsym, metaclasses or libraries.
		if _ := module_symbol(0, library, symbol) { assert false }
		if _ := runtime_symbol(library, symbol) { assert false }
		for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib', '<flat lookup>', '<weak lookup>']! {
			if _ := module_bind_symbol(wrong, symbol) { assert false, wrong }
		}
		for wrong in ['_OBJC_METACLASS_$_SKAdNetwork', '_OBJC_CLASS_$_AnotherMissingClass']! {
			if _ := module_bind_symbol(library, wrong) { assert false, wrong }
		}
		assert module_bind_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSObject')! == ios_runtime.names['NSObject']
		module_runtime.probe_no_ads = false
		if _ := module_bind_symbol(library, symbol) { assert false }
		modules_stop()
		assert module_runtime == unsafe { nil }
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-NO-ADS-PROBE: exact opt-in binding, nil messaging, strict audit/dynamic lookup, unrelated imports and runtime reset PASS')
}

type ProbeNilSend = fn (u64, u64) u64
