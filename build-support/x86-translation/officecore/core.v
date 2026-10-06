// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license in LICENSE.
// Licensing probes remain non-fatal and report no persisted licensing policy.
// All input pointers are borrowed synchronously; context1 has no owned object.
module officecore

#include "sppc-office-v-abi.h"
@[typedef]
struct C.vsppc_const_guid_p {}
@[typedef]
struct C.vsppc_const_wchar_p {}

const invalid_argument = i32(u32(0x80070057))
const value_not_found = i32(u32(0xc004f012))
const right_not_consumed = i32(u32(0xc004f014))
const not_implemented = i32(u32(0x80004001))

@[export: 'DllMain']
pub fn dll_main(instance voidptr, reason u32, reserved voidptr) i32 { return 1 }

@[export: 'SLLoadApplicationPolicies']
pub fn load_policies(application C.vsppc_const_guid_p, product C.vsppc_const_guid_p, flags u32, context &voidptr) i32 {
    unsafe {
        if voidptr(application) == nil || context == nil { return invalid_argument }
        *context = voidptr(usize(1))
        return 0
    }
}

@[export: 'SLGetApplicationPolicy']
pub fn get_policy(context voidptr, name C.vsppc_const_wchar_p, value_type &u32, size &u32, value &&u8) i32 {
    unsafe {
        if context == nil || voidptr(name) == nil || size == nil || value == nil { return invalid_argument }
        if value_type != nil { *value_type = 0 }
        *size = 0
        *value = nil
        return value_not_found
    }
}

@[export: 'SLUnloadApplicationPolicies']
pub fn unload_policies(context voidptr) i32 { return if context == unsafe { nil } { invalid_argument } else { i32(0) } }

@[export: 'SLOpen']
pub fn open(context &voidptr) i32 {
    unsafe { if context == nil { return invalid_argument }; *context = voidptr(usize(1)); return 0 }
}
@[export: 'SLClose']
pub fn close(context voidptr) i32 { return if context == unsafe { nil } { invalid_argument } else { i32(0) } }

@[export: 'SLGetLicensingStatusInformation']
pub fn licensing_status(context voidptr, application C.vsppc_const_guid_p, product C.vsppc_const_guid_p,
    name C.vsppc_const_wchar_p, count &u32, status &voidptr) i32 {
    unsafe {
        if count != nil { *count = 0 }
        if status != nil { *status = nil }
        return right_not_consumed
    }
}
