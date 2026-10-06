// Exercise actual ATL objects and the selected androidfw provider.
module atlconfiguration

#include "atl-configuration-v-abi.h"
struct C.AssetManager {}
struct C.ResTable_config {
 size u32
 density u16
 orientation u8
 screenWidthDp u16
 screenHeightDp u16
 smallestScreenWidthDp u16
 sdkVersion u16
 screenLayout u8
 inputFlags u8
 language [2]char
 country [2]char
}
fn C.AssetManager_new() &C.AssetManager
fn C.AssetManager_lock(&C.AssetManager)
fn C.AssetManager_setConfiguration(&C.AssetManager, &C.ResTable_config)
fn C.AssetManager_unlock(&C.AssetManager)
fn C.AConfiguration_new() voidptr
fn C.AConfiguration_delete(voidptr)
fn C.AConfiguration_fromAssetManager(voidptr, &C.AssetManager)
fn C.AConfiguration_copy(voidptr, voidptr)
fn C.AConfiguration_diff(voidptr, voidptr) i32
fn C.AConfiguration_match(voidptr, voidptr) i32
fn C.AConfiguration_getDensity(voidptr) i32
fn C.AConfiguration_getScreenWidthDp(voidptr) i32
fn C.AConfiguration_getScreenHeightDp(voidptr) i32
fn C.AConfiguration_getSmallestScreenWidthDp(voidptr) i32
fn C.AConfiguration_getSdkVersion(voidptr) i32
fn C.AConfiguration_getScreenSize(voidptr) i32
fn C.AConfiguration_getNavHidden(voidptr) i32
fn C.AConfiguration_getLanguage(voidptr, &char)
fn C.AConfiguration_getCountry(voidptr, &char)
fn C.AConfiguration_setOrientation(voidptr, i32)
fn C.assert(bool)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.puts(&char) i32

@[export: 'main']
pub fn run() i32 {
 unsafe {
  manager := C.AssetManager_new()
  first := C.AConfiguration_new()
  second := C.AConfiguration_new()
  C.assert(manager != nil && first != nil && second != nil)
  mut config := C.ResTable_config{
   size: u32(sizeof(C.ResTable_config))
   density: 160
   orientation: 2
   screenWidthDp: 800
   screenHeightDp: 600
   smallestScreenWidthDp: 600
   sdkVersion: 34
   screenLayout: 3
   inputFlags: 2 << 2
   language: [char(`e`), char(`n`)]!
   country: [char(`G`), char(`B`)]!
  }
  C.AssetManager_lock(manager)
  C.AssetManager_setConfiguration(manager, &config)
  C.AssetManager_unlock(manager)
  C.AConfiguration_fromAssetManager(first, manager)
  C.assert(C.AConfiguration_getDensity(first) == 160)
  C.assert(C.AConfiguration_getScreenWidthDp(first) == 800)
  C.assert(C.AConfiguration_getScreenHeightDp(first) == 600)
  C.assert(C.AConfiguration_getSmallestScreenWidthDp(first) == 600)
  C.assert(C.AConfiguration_getSdkVersion(first) == 34)
  C.assert(C.AConfiguration_getScreenSize(first) == 3 && C.AConfiguration_getNavHidden(first) == 2)
  mut language := [2]char{}
  mut country := [2]char{}
  C.AConfiguration_getLanguage(first, &language[0])
  C.AConfiguration_getCountry(first, &country[0])
  C.assert(C.memcmp(&language[0], c'en', 2) == 0 && C.memcmp(&country[0], c'GB', 2) == 0)
  config.screenWidthDp = 1024
  config.screenHeightDp = 768
  config.density = 240
  C.AssetManager_lock(manager)
  C.AssetManager_setConfiguration(manager, &config)
  C.AssetManager_unlock(manager)
  C.AConfiguration_fromAssetManager(second, manager)
  C.assert(C.AConfiguration_getScreenWidthDp(first) == 800)
  C.assert(C.AConfiguration_getScreenWidthDp(second) == 1024)
  C.assert(C.AConfiguration_getScreenHeightDp(second) == 768 && C.AConfiguration_getDensity(second) == 240)
  C.assert(C.AConfiguration_diff(first, second) != 0)
  C.AConfiguration_copy(first, second)
  C.assert(C.AConfiguration_diff(first, second) == 0 && C.AConfiguration_match(first, second) != 0)
  C.AConfiguration_setOrientation(first, 1)
  C.assert(C.AConfiguration_match(first, second) == 0)
  C.AConfiguration_delete(first)
  C.AConfiguration_delete(second)
  C.puts(c'ATL-CONFIGURATION-PASS snapshot=asset-manager owned-copy=verified matching=androidfw')
  return 0
 }
}
