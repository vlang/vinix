// SPDX-License-Identifier: GPL-2.0-or-later
// Independent licensing ABI golden checks: every output/null combination.
@[translated]
module fixture
#include "office-test-abi.h"
#include <stdio.h>
fn C.DllMain(voidptr, u32, voidptr) i32
fn C.SLLoadApplicationPolicies(voidptr, voidptr, u32, &voidptr) i32
fn C.SLGetApplicationPolicy(voidptr, voidptr, &u32, &u32, &&u8) i32
fn C.SLUnloadApplicationPolicies(voidptr) i32
fn C.SLOpen(&voidptr) i32
fn C.SLClose(voidptr) i32
fn C.SLGetLicensingStatusInformation(voidptr, voidptr, voidptr, voidptr, &u32, &voidptr) i32
fn C.puts(&char) i32
fn C.abort()
fn C.printf(&char, ...voidptr) i32
fn C.fflush(voidptr) i32
__global check_count i32
fn check(valid bool) {
 check_count++
 if !valid { C.printf(c'Office ABI assertion %d failed\n', check_count); C.fflush(unsafe { nil }); C.abort() }
}
fn C.SLActivateProduct() i32
fn C.SLConsumeRight() i32
fn C.SLDepositOfflineConfirmationId() i32
fn C.SLDepositTokenActivationResponse() i32
fn C.SLFreeTokenActivationCertificates() i32
fn C.SLFreeTokenActivationGrants() i32
fn C.SLGenerateOfflineInstallationId() i32
fn C.SLGenerateTokenActivationChallenge() i32
fn C.SLGetAuthenticationResult() i32
fn C.SLGetInstalledProductKeyIds() i32
fn C.SLGetPKeyId() i32
fn C.SLGetPKeyInformation() i32
fn C.SLGetPolicyInformation() i32
fn C.SLGetProductSkuInformation() i32
fn C.SLGetSLIDList() i32
fn C.SLGetServiceInformation() i32
fn C.SLGetTokenActivationCertificates() i32
fn C.SLGetTokenActivationGrants() i32
fn C.SLInstallLicense() i32
fn C.SLInstallProofOfPurchase() i32
fn C.SLPersistApplicationPolicies() i32
fn C.SLPersistRTSPayloadOverride() i32
fn C.SLRegisterPlugin() i32
fn C.SLSetAuthenticationData() i32
fn C.SLSignTokenActivationChallenge() i32
fn C.SLUninstallLicense() i32
fn C.SLUninstallProofOfPurchase() i32

@[export: 'main']
pub fn main_entry() i32 {
 unsafe {
  C.puts(c'OFFICE LICENSING ABI BEGIN')
  C.fflush(nil)
  invalid := i32(u32(0x80070057))
  absent := i32(u32(0xc004f012))
  rights := i32(u32(0xc004f014))
  unimplemented := i32(u32(0x80004001))
  high := voidptr(usize(0x123456789abcdef0))
  mut guid := [16]u8{}
  mut name := [2]u16{init: u16(65)}
  for iteration := 0; iteration < 1024; iteration++ {
   check(C.DllMain(high, u32(iteration), high) == 1)
   for mask := u32(0); mask < 4; mask++ {
    mut context := high
    app := if mask & 1 != 0 { voidptr(&guid[0]) } else { nil }
    out := if mask & 2 != 0 { usize(&context) } else { usize(0) }
    result := C.SLLoadApplicationPolicies(app, high, u32(0xffffffff), &voidptr(out))
    check(result == if mask == 3 { i32(0) } else { invalid })
    check(context == if mask == 3 { voidptr(usize(1)) } else { high })
   }
   mut context := high
   check(C.SLOpen(nil) == invalid)
   check(C.SLOpen(&context) == 0 && context == voidptr(usize(1)))
   check(C.SLClose(nil) == invalid && C.SLClose(high) == 0)
   check(C.SLUnloadApplicationPolicies(nil) == invalid && C.SLUnloadApplicationPolicies(high) == 0)
   for mask := u32(0); mask < 32; mask++ {
    mut value_type := u32(0xaabbccdd)
    mut size := u32(0x99887766)
    mut value := &u8(high)
    ctx := if mask & 1 != 0 { high } else { nil }
    nm := if mask & 2 != 0 { voidptr(&name[0]) } else { nil }
    sz := if mask & 4 != 0 { &size } else { nil }
    val := if mask & 8 != 0 { usize(&value) } else { usize(0) }
    typ := if mask & 16 != 0 { &value_type } else { nil }
    valid := mask & 15 == 15
    check(C.SLGetApplicationPolicy(ctx, nm, typ, sz, &&u8(val)) == if valid { absent } else { invalid })
    check(value_type == if valid && typ != nil { u32(0) } else { u32(0xaabbccdd) })
    check(size == if valid { u32(0) } else { u32(0x99887766) })
    check(voidptr(value) == if valid { nil } else { high })
   }
   for mask := u32(0); mask < 4; mask++ {
    mut count := u32(0x44556677)
    mut status := high
    cnt := if mask & 1 != 0 { &count } else { nil }
    out := if mask & 2 != 0 { usize(&status) } else { usize(0) }
    check(C.SLGetLicensingStatusInformation(nil, high, nil, high, cnt, &voidptr(out)) == rights)
    check(count == if cnt != nil { u32(0) } else { u32(0x44556677) })
    check(status == if out != 0 { nil } else { high })
   }
   check(C.SLActivateProduct() == unimplemented)
   check(C.SLConsumeRight() == unimplemented)
   check(C.SLDepositOfflineConfirmationId() == unimplemented)
   check(C.SLDepositTokenActivationResponse() == unimplemented)
   check(C.SLFreeTokenActivationCertificates() == unimplemented)
   check(C.SLFreeTokenActivationGrants() == unimplemented)
   check(C.SLGenerateOfflineInstallationId() == unimplemented)
   check(C.SLGenerateTokenActivationChallenge() == unimplemented)
   check(C.SLGetAuthenticationResult() == unimplemented)
   check(C.SLGetInstalledProductKeyIds() == unimplemented)
   check(C.SLGetPKeyId() == unimplemented)
   check(C.SLGetPKeyInformation() == unimplemented)
   check(C.SLGetPolicyInformation() == unimplemented)
   check(C.SLGetProductSkuInformation() == unimplemented)
   check(C.SLGetSLIDList() == unimplemented)
   check(C.SLGetServiceInformation() == unimplemented)
   check(C.SLGetTokenActivationCertificates() == unimplemented)
   check(C.SLGetTokenActivationGrants() == unimplemented)
   check(C.SLInstallLicense() == unimplemented)
   check(C.SLInstallProofOfPurchase() == unimplemented)
   check(C.SLPersistApplicationPolicies() == unimplemented)
   check(C.SLPersistRTSPayloadOverride() == unimplemented)
   check(C.SLRegisterPlugin() == unimplemented)
   check(C.SLSetAuthenticationData() == unimplemented)
   check(C.SLSignTokenActivationChallenge() == unimplemented)
   check(C.SLUninstallLicense() == unimplemented)
   check(C.SLUninstallProofOfPurchase() == unimplemented)
  }
  C.puts(c'OFFICE LICENSING ABI PASS: 1024 rounds, 33 APIs, 40 null/output combinations')
  $if office_native ? {
   return 73
  } $else {
   return 0
  }
 }
}
