// SPDX-License-Identifier: GPL-2.0-or-later
module main

// swift_willThrow is a returning debugger notification, not an unwind or ARC
// operation. Swift passes the context in x20 and the borrowed error in x21.
// The default native behavior (no debugger handler) leaves both untouched;
// an ordinary C leaf preserves these callee-saved registers without a thunk.
// The separate _swift_willThrow handler variable and handler-installation SPI
// are not exported by this runtime.
// https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/ErrorObjectCommon.cpp
fn swift_will_throw() {}
