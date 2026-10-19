// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__builtin_trap()

// A representable's primitive Body is Never. Its extension getter must fail,
// even though makeUIView/updateUIView can be valid entry points. Report a
// fixed diagnostic without reflecting on caller metadata or reading Swift
// self, witnesses or x8. Native generic type-name/crash annotations are absent.
@[noreturn]
fn swiftui_body_failure() {
	text := 'iOS: SwiftUI UIViewRepresentable.body must not be called (Body is Never)\n'
	swift_fatal_write(u64(text.str), u64(text.len))
	for { C.__builtin_trap() }
}

fn swiftui_body_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI19UIViewRepresentablePAAE4bodys5NeverOvg' { return none }
	return u64(unsafe { voidptr(swiftui_body_failure) })
}
