// SPDX-License-Identifier: GPL-2.0-or-later
// Replace only the kernel in a fresh diagnostic stage; never launch a guest.
module main

import crypto.sha256
import json2
import modulestream
import os
import time

#include <signal.h>
#include <CommonCrypto/CommonDigest.h>

fn C.kill(int, int) int
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const baseline_sha = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const maps_baseline_sha = '08b0a9c6d0eaf109a5027eac802cb5add897e7612aac85528a08fdba794b3f5e'
const protected_base = '/Users/alex/.local/state/vinix/android/maps-account-r5'
const protected_base_seal = '9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca'
const protected_boot_sha = 'a37afb3aaaaac0261562df47b6f213bf0ef47eaaa9165d721cb4e097ce35ed70'
const protected_framework_seal = '67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938'
const protected_native_seal = 'a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20'
const controller_base = '/Users/alex/.local/state/vinix/android/maps-startup-r1'
const controller_base_seal = 'f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332'
const controller_boot_sha = '24999d2743f4c86196b39113b68062908a698945864c2ca551dff4f0578677c6'
const controller_root = '/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-27-r6'
const controller_seal = '1b8e4555a67eae4c3b1c109f3d94064c96eba65dd3fd3c88d72649b5fdbc9106'
const controller_pin = '894e57f0eaf773777b3107100068edf1f9b57b427b565756767c576a0de8c6b6'
const retained_controller_seal = '5a46182682b5f3c9bf47478ab0fcfc9f9dd40f8aeee589851765df8458776773'
const service_query_base = '/Users/alex/.local/state/vinix/android/maps-controller-r1'
const service_query_base_seal = '3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a'
const service_query_boot_sha = '0b8ba1493633c38b599dd368b437da31b5ef2bc421cd7d77c1b5e3960250cd58'
const service_query_framework = '/Users/alex/.local/state/vinix/android/combined-account-webview-service-query-framework-2026-10-27-r1'
const service_query_framework_seal = '12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559'
const service_query_jar = '74892a013cb72fdaef39852325a3fa46db217fbcd3a4f11fcba4cc7272b2a50b'
const service_query_dex = 'c453e3b480a6dbd0295a46b2a29f5ada5f7d0f7ee8c2bc07b5b9a76355d43e5e'
const service_query_build = 'ba4e01cfe7aa4433795de93ee0142f0fcf2501c30b07635b9ef7ab166caf2a83'
const service_query_jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const service_query_dex_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'
const service_query_headless = 'opt/vinix-headless-service'
const service_query_deployment = 'opt/vinix-maps-account/build.json'
const controller_memory_base = '/Users/alex/.local/state/vinix/android/maps-service-query-r1'
const controller_memory_base_seal = '4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b'
const controller_memory_boot_sha = 'cd244cb944409f0e1446de7987951a63a8e13721abd90f7dcbb7a81a567c3efc'
const controller_memory_root = '/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-27-r7'
const controller_memory_seal = '680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890'
const controller_memory_pin = '9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c'
const direct_boot_base = '/Users/alex/.local/state/vinix/android/maps-controller-memory-r1'
const direct_boot_base_seal = '944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21'
const direct_boot_boot_sha = 'b534f94cede89e250f710d367fae062bd1c71c6024dabd85c5aa2444aa010b00'
const direct_boot_memory_overlay = '6fbaafd334d0008b548df7557b65aa6cf99ae08be7fa584ed46789657ac51b13'
const direct_boot_framework = '/Users/alex/.local/state/vinix/android/combined-account-webview-direct-boot-framework-2026-10-27-r1'
const direct_boot_framework_seal = 'a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552'
const direct_boot_jar = 'bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d'
const direct_boot_dex = '3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213'
const direct_boot_build = '017232d7cef0527e639c3689cca3cc87502746aaa9608760d6bb7f362cbbd2f4'
const context_storage_base = '/Users/alex/.local/state/vinix/android/maps-direct-boot-r1'
const context_storage_base_seal = 'fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285'
const context_storage_boot_sha = 'b66d6c7d6666d492edc6a93af84a7b258d277196273e4270691fc8349ecd7ab8'
const context_storage_direct_boot_overlay = '33c2c38893f72f389601666dc8039c8855c935c91e20c9b8dc04816a6142ae56'
const context_storage_framework = '/Users/alex/.local/state/vinix/android/combined-account-webview-credential-storage-framework-2026-10-27-r1'
const context_storage_framework_seal = 'cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691'
const context_storage_jar = '9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352'
const context_storage_dex = 'b96a441b6eca36e0a6fa7a6da01d9e4508136e64ec0f0f3850cf15e2d90ff132'
const context_storage_build = '486dfea3930686a5b846e2782f759e7ab7a4f55f320a603a145a471b18cabe3e'
const broadcast_result_base = '/Users/alex/.local/state/vinix/android/maps-context-storage-r1'
const broadcast_result_base_seal = '6296bcff89e1a6555c803b0ee94f435cbae1f01c37ce97451080612a95fdde2c'
const broadcast_result_boot_sha = '0bc1652062a78d3878c4404b6be907cf76c1215268798025d925c3f8a946eceb'
const broadcast_result_context_overlay = 'a524dcda373cf0ff6b688991924e3c2faaa33a998c4e2ec54596fdbb34df6fc2'
const broadcast_result_framework = '/Users/alex/.local/state/vinix/android/combined-account-webview-broadcast-result-framework-2026-10-27-r1'
const broadcast_result_framework_seal = '21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046'
const broadcast_result_jar = '5dfba8c7e0006f6c84510d72b8fde84706bcb7f3489b3620cd340ec0361d8564'
const broadcast_result_dex = '5305155d203c856a1828596d06c48ba130fbf9a373dec6b558a3fc4e53bdac11'
const broadcast_result_build = '280b6de249825cfc773e16e12c933d18a6013a4ac8b7e9a0cbbc9e7f1cdbc1e1'
const onboarding_trace_base = '/Users/alex/.local/state/vinix/android/maps-broadcast-result-r2'
const onboarding_trace_base_seal = '98522d60a7627927b7ee6b861db502b6574e3d6ab14fdecb09e2da38b2f441de'
const onboarding_trace_boot_sha = '6478b77c6be52c835254b351472d26e632fb1a4dc2d9cca6e2c41677f893345c'
const onboarding_trace_base_overlay = '497626f8ce4fe4c7571177a8394d0697cae33a390ef41ac49131ef6eaa8be9b4'
const onboarding_trace_controller = '/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-27-r8'
const onboarding_trace_controller_seal = 'c2c08ed987052e5170f9b90cd4af7f9de6fcb4e98684def4dc5e28f058409b4f'
const onboarding_trace_controller_pin = 'e15e14d135de930f29caf6b8708adc83390c3e12fdb37d368edb6d5cb1899bcf'
const native_onboarding_trace_base = '/Users/alex/.local/state/vinix/android/maps-onboarding-trace-r2'
const native_onboarding_trace_base_seal = 'de315f3f5f0120efbd1368a47e11db945aa9212160fc7e1ff351e522e9435be5'
const native_onboarding_trace_boot_sha = '962a9983c22099485fdb8e7e07105e2bcc2c14a33c2dd6a0fef1cc16b33ad070'
const native_onboarding_trace_base_overlay = '09e96149189b7b171ed67098eac52b8759e18d09b58e49130494dd672ce267fe'
const native_onboarding_trace_root = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-onboarding-r5'
// Replace only with the complete reviewed producer's sealed output pins.
const native_onboarding_trace_seal = '05baf5d011337d54aab26f6cc3c535f801221d51aceb966ebc9442d88b5fd6b8'
const native_onboarding_trace_pin = 'efcf0a270d2116245558b35811a2a2b714f8348c90c5e1bdb9aaf91ae278f65c'
const native_onboarding_trace_build = '3ed2de875f39583ac86b83ebeeca027185757cbce396a29556cff48b679d1b04'
const native_onboarding_trace_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const native_onboarding_trace_retained_pin = '82e4bdb907a300634b304b37339b2e9a836f6f1a61d01a369d0f5aa707fddca7'
const native_onboarding_trace_retained_build = '08ea36ea9bfcc4406ece5a80250a3c91b1833851035a783c8339d75c1904391b'
const native_onboarding_trace_retained_guest = '67296ef608b18e6ec328ccead8bf8811393db0e9adbafb56920f71150b60db74'
const onboarding_framework_base = '/Users/alex/.local/state/vinix/android/maps-native-onboarding-trace-r3'
const onboarding_framework_base_seal = '96b90172e338080ff50bf0e1188bdefc1f50e61fe3ad654593dfbac4d918d741'
const onboarding_framework_boot_sha = 'f90cb8b87b0fa2e4f34af9fe2f23026fbd2d029ac35481a735eeff507cdb3cd9'
const onboarding_framework_base_overlay = '4ed7f924fcd7f89ead5ee8fca3138985947ee7ce1fe598cfcedab93c311cf1e3'
const onboarding_framework_root = '/Users/alex/.local/state/vinix/android/combined-account-webview-onboarding-framework-2026-10-27-r1'
// Replace only with the complete reviewed two-class framework producer's pins.
const onboarding_framework_seal = 'bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42'
const onboarding_framework_jar = 'e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd'
const onboarding_framework_dex = '12e4ad659e61941f0f37ea46dbe1bae8b97bc4ca874bbeaa4841e8832d2cc854'
const onboarding_framework_build = '8ec80f25e35edd176ae333fd78d5e5503ba3f83eac3bf4d7191eacf33120ac60'
const onboarding_framework_retained_guest = '42f1a0b03cb62737d452d99088ac510937b5d2ecf7eeba233a493e29877bcf60'
const native_heartbeat_base = '/Users/alex/.local/state/vinix/android/maps-onboarding-framework-r1'
const native_heartbeat_base_seal = 'fcba5511b0cc2d305ee6e3ba48081bf6bc40fd6117cd91abc691fb2fd7ad01cf'
const native_heartbeat_boot_sha = '1b4200adb788f79fe0d1ad0a5e810aaf29feda65dc26cc32c7983169c38f132f'
const native_heartbeat_base_overlay = '0869585fb09e02af998d687c6ba92cb8beae4e5cbd27d4be58303ff95339b877'
const native_heartbeat_root = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-heartbeat-r1'
// Fail closed until the complete reviewed heartbeat producer supplies all three pins.
const native_heartbeat_seal = '6619a4cd8dcc7e30aa43120494b874f230d1e9b8ee5c5b756e25fcf5e5148eae'
const native_heartbeat_pin = '3ac3ec1a026a409ec52b7973d9dcc4593bd5d266fc2c6e77fc5d5c1a88e439d9'
const native_heartbeat_build = 'ac77be848928c47ea5371a6f6532152d00c3ee8470e8f911d5748b61fa50c1f6'
const native_heartbeat_retained_guest = 'a65ebf4db1d99782bbdfeb685726c5dd687e429f0ec454bf61e9d6f447472cce'
const browser_poll_base = '/Users/alex/.local/state/vinix/android/maps-native-heartbeat-r1'
const browser_poll_base_seal = '70ea9f41ad045541066dec75a1ddcdc1e44efefd8d35ffb2e4414a77e2235b32'
const browser_poll_boot_sha = '1132263943c035e095ac4eef5b46d8507e026087fd14f2268e39ed384d41f5bb'
const browser_poll_base_overlay = '196680d5b936eae53408abb33145c9cbfc57f6b4eeb55e5810647d74e3b4651b'
const browser_poll_path = 'opt/vinix-android-aarch64/usr/lib/libvinix-android-browser.so'
const browser_poll_retained_seal = 'af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3'
const browser_poll_retained_pin = 'ad55dfd4d1e7fd11e092ef75bada71eb4c176845451b80dc023eb98c20a2935b'
// Complete strict browser producer and exact source-delta audit passed.
const browser_poll_root = '/Users/alex/.local/state/vinix/android/current-browser-build-2026-10-27-poll-r1'
const browser_poll_seal = 'fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62'
const browser_poll_pin = '16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a'
const account_pump_base = '/Users/alex/.local/state/vinix/android/maps-browser-poll-r3'
const account_pump_base_seal = 'f27b08e45994fb2e9cf2c2aac695e73c62f17e0b4785fdb310cbebb1f54ac297'
const account_pump_boot_sha = '8dbdf03669e6ed7545c172095112bc3e3008ad3a08d341ce389fe718158f6434'
const account_pump_base_overlay = '12d307eb52c908fbf38cb1cf94fda7c202a2caa8869a1f6c8762ccc2cc6d035b'
const account_pump_root = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-28-account-pump-r1'
// Complete strict native producer and exact account service source-delta audit passed.
const account_pump_seal = 'a6a7f207b07083726b9708eea2c67290bcf8baced755651c50bdc205cd7097cd'
const account_pump_pin = 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
const account_pump_build = '2802af6636568126359765ac00d09b0771f0b4d22a09c45db55dfe21ba557924'
const account_pump_source_pin = '0fd27e8edece566671eb824b537858938478300ca16c3572a9aa64bf102cebea'
const application_restrictions_base = '/Users/alex/.local/state/vinix/android/maps-account-pump-r2'
const application_restrictions_base_seal = 'd432d4cf4fa1522b07cb2b7ada498a32d375d44cf7830e50858681fcf118035c'
const application_restrictions_boot_sha = 'c03e92d18d4dc4e321ed8e48010a47fac92efbc486c88f61bd14f1b354b61d41'
const application_restrictions_base_overlay = 'f3386cd853826fffe8fb83b667cda5a7f75211bd4e99db2f33f925e0b2944f5b'
const application_restrictions_root = '/Users/alex/.local/state/vinix/android/combined-account-webview-application-restrictions-framework-2026-10-28-r1'
const application_restrictions_seal = '8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15'
const application_restrictions_jar = 'd4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32'
const application_restrictions_dex = '45c25a081702f299ae3f8a883347d624cae6ab4bda3b5f2538be89421cdf32ab'
const application_restrictions_build = 'a2a31c49975032e4051a2cb9a737d5bdd31a57e7472bafc60411f723c2ebea3a'
const application_restrictions_retained_guest = 'b22889a7279f5d1f3523e6968a0ee6d107ffaab2c43bd80080b44b633ba29450'
const account_handoff_base = '/Users/alex/.local/state/vinix/android/maps-application-restrictions-r2'
const account_handoff_base_seal = 'd8507cb61499306398adecaae7fb9e1fe34ac9f1ccc9c9e42f1232b29c49623a'
const account_handoff_boot_sha = 'c86cb354f7c0afe99ec78e563a7dd9281cf85f01316178e6956402ae14ac5d9a'
const account_handoff_base_overlay = '9ae52763b10d642e2e035df244039c352dd25ef63d21a38b1eeb0ab7fd430143'
const account_handoff_retained_deployment = '14b1907be12ce988a4c5b36e449aa690843035966c4545543bcb1b9b327b67c8'
const account_handoff_retained_broker = 'b674064be8d3635ee7433bef2c1894fa5fe045674ed0e98cf7d3215adca66a4d'
const account_handoff_broker_root = '/Users/alex/.local/state/vinix/android/current-account-broker-build-2026-10-28-handoff-r1'
const account_handoff_controller_root = '/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-28-handoff-r2'
// Bind the complete reviewed successor producers and their deployed executables.
const account_handoff_broker_seal = 'b06d4aadb661eb1ba13ac07e9033d88db1db731d54d2b1685df6dba1e69cd8f6'
const account_handoff_broker_pin = '9f0b8ac37881ab8377e70793609882fb9b07f681b8a79264fc7f95435d8b2823'
const account_handoff_controller_seal = '1cf0e472fb977e705204f06fcad806f0c1ea16d213d469d0174c658c27fb041d'
const account_handoff_controller_pin = '0253f16da634ffef92e1efa2b3102d1ad91af15d1f521081f60e920e78affc6b'
const account_handoff_broker_path = 'opt/vinix-android-aarch64/usr/bin/native-account-broker'
const auth_exception_base = '/Users/alex/.local/state/vinix/android/maps-account-handoff-r5'
const auth_exception_base_seal = '256b9c62ad2c6c83668cac756697941c8cdba6e6eae9a31543016d6f85b90e7a'
const auth_exception_boot_sha = 'bd0cd42b8fb7f4684b9ca71efa5936ae7ef691d81a170421d452001eb8d4f9e4'
const auth_exception_base_overlay = '95d9a625dba2af22b32e5c61e844af97dd34809e35d04ddacd9accca07bf3c47'
const auth_exception_retained_deployment = '90e0de9745c0a4326dae72d7f2aa1e3e662f11c70dad33dda50f0fcfb170fedf'
const auth_exception_framework = '/Users/alex/.local/state/vinix/android/combined-account-webview-auth-exception-framework-2026-10-29-r1'
const auth_exception_framework_seal = '4aa0c09e05c0d4fe3180a909648ebb344881ec1d2d6e60bba5d959148d93a284'
const auth_exception_jar = '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
const auth_exception_dex = '6cf2173aedc5adbf187aed5db4c37a8a95a413cc35343272cd45c88f2734d615'
const auth_exception_build = '51b78458f8da4c0d6598cf3856327111cc3094a489af7ac7e56470bd59dec225'
const auth_worker_base = '/Users/alex/.local/state/vinix/android/maps-auth-exception-r1'
const auth_worker_base_seal = 'b8b214ffc061366718511b4d293077e8901d797884e884ebaad84f346d5341e1'
const auth_worker_boot_sha = '648886cef0035cba445c1f8d74fd85a647228781457fa919e4ad543d73db59c5'
const auth_worker_base_overlay = '6b643c0fa9ea98abd0fe55219915406b04df9b2b101e47b73908f3f292515bac'
const auth_worker_retained_deployment = 'f24a0194fcba6f9ea314f979124e5144341c331cf2b1b01a20eba4c20bba65aa'
const auth_worker_root = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-29-auth-worker-r1'
// Complete reviewed native producer and its exact implementation delta.
const auth_worker_seal = '048602ab4aa188111bad295a5af9d1b47c6cceee0fd82f0eb73858689b22a921'
const auth_worker_pin = '0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136'
const auth_worker_build = '3e7d063ed01484a91ae9ef02bb78b648168dc815700a28522adf88d622aed2d9'
const auth_worker_service_source = '7369030274a40f2c9b4abafbd854c61fe9f48b29152dd0de7e78dce1df56bae6'
const auth_worker_added_source = 'db0f426089da7b3397662a1dcf93a1de37aa32979e4edfa746a63b01855a1c5c'
const source = $embed_file(@FILE).to_string()

struct Profile {
	name         string
	baseline_sha string
	overlay      string
	modules      []string
}

fn browser_profile() Profile {
	return Profile{'browser-probe', baseline_sha, 'browser-probe.tar', []string{}}
}

fn maps_profile() Profile {
	return Profile{'maps-account', maps_baseline_sha, 'maps-account.tar', [
		'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar',
		'maps350-diagnostics.tar', 'maps372-diagnostics.tar', 'headless-service.tar',
	]}
}

fn protected_maps_profile() Profile {
	mut modules := maps_profile().modules.clone()
	modules << 'maps-account.tar'
	return Profile{'protected-storage-maps', protected_boot_sha,
		'protected-storage-diagnostic.tar', modules}
}

fn controller_profile() Profile {
	mut modules := protected_maps_profile().modules.clone()
	modules << 'protected-storage-diagnostic.tar'
	return Profile{'maps-controller', controller_boot_sha, 'maps-controller-diagnostic.tar', modules}
}

fn service_query_profile() Profile {
	mut modules := controller_profile().modules.clone()
	modules << 'maps-controller-diagnostic.tar'
	return Profile{'maps-service-query', service_query_boot_sha, 'maps-service-query-diagnostic.tar', modules}
}

fn controller_memory_profile() Profile {
	mut modules := service_query_profile().modules.clone()
	modules << 'maps-service-query-diagnostic.tar'
	return Profile{'maps-controller-memory', controller_memory_boot_sha,
		'maps-controller-memory-diagnostic.tar', modules}
}

fn controller_memory_modules() map[string]string {
	mut modules := service_query_modules()
	modules['maps-service-query-diagnostic.tar'] = 'beab8be6e214199a1e7a509bc386943b31ccf45f89cc8580b94666a3b42fe5a0'
	return modules
}

fn controller_memory_fields() map[string]string {
	return {
		'kind': 'vinix-maps-controller-memory-diagnostic-v1'
		'base_root': controller_memory_base
		'base_manifest_sha256': controller_memory_base_seal
		'controller_build_root': controller_memory_root
		'controller_manifest_sha256': controller_memory_seal
		'controller_sha256': controller_memory_pin
		'retained_controller_manifest_sha256': controller_seal
		'framework_manifest_sha256': service_query_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn controller_memory_inputs() map[string]string {
	mut inputs := service_query_inputs()
	inputs[controller_memory_base + '/sha256.json'] = controller_memory_base_seal
	inputs[controller_memory_root + '/sha256.json'] = controller_memory_seal
	return inputs
}

fn controller_memory_delta() map[string]string {
	return {
		'/opt/vinix-maps-account/bin/maps-account-guest': controller_memory_pin
		'/usr/bin/run-android-calculator': controller_memory_pin
	}
}

fn verify_controller_memory_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('controller memory deployment input delta absent') }
	top_delta := receipt['deployment_top_level_delta'] or { return error('controller memory deployment top delta absent') }
	if input_delta != json2.decode[json2.Any](json2.encode(controller_memory_delta()))!
		|| top_delta != json2.decode[json2.Any](json2.encode(['inputs_sha256']))! {
		return error('controller memory deployment delta differs')
	}
	inventory := receipt['overlay_inventory'] or { return error('controller memory overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := controller_memory_delta().keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe controller memory overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) {
				return error('controller memory regular allowlist differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected controller memory overlay inode')
		}
	}
	if regulars.len != 3 { return error('exact three controller memory files required') }
	for path, pin in controller_memory_delta() {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('controller memory aliases differ from exact executable')
		}
	}
}

// A separate three-file successor preserves the service-query framework and all
// ten original modules. Its prior controller remains a complete sealed input.
fn verify_controller_memory_receipt(receipt map[string]json2.Any, stage Stage) ! {
	if !digest_valid(controller_memory_seal) || !digest_valid(controller_memory_pin)
		|| controller_memory_seal == controller_seal || controller_memory_pin == controller_pin {
		return error('sealed new controller memory producer pins required')
	}
	for name, expected in controller_memory_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('controller memory receipt differs: ' + name)
		}
	}
	for path, pin in controller_memory_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('controller memory input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != controller_memory_modules()
		|| stage.preserved_modules_sha256 != controller_memory_modules() {
		return error('controller memory original ten module pins differ')
	}
	verify_controller_memory_overlay(receipt)!
}

fn controller_memory_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_controller_memory_receipt(receipt, stage)!
	path := controller_memory_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != controller_memory_base_seal {
		return error('controller memory original service-query manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != controller_memory_boot_sha {
		return error('controller memory original boot inventory differs')
	}
	return controller_memory_base + '/boot.img'
}

fn direct_boot_profile() Profile {
	mut modules := controller_memory_profile().modules.clone()
	modules << 'maps-controller-memory-diagnostic.tar'
	return Profile{'maps-direct-boot', direct_boot_boot_sha, 'maps-direct-boot-diagnostic.tar', modules}
}

fn direct_boot_modules() map[string]string {
	mut modules := controller_memory_modules()
	modules['maps-controller-memory-diagnostic.tar'] = direct_boot_memory_overlay
	return modules
}

fn direct_boot_fields() map[string]string {
	return {
		'kind': 'vinix-maps-direct-boot-diagnostic-v1'
		'base_root': direct_boot_base
		'base_manifest_sha256': direct_boot_base_seal
		'controller_build_root': controller_memory_root
		'controller_manifest_sha256': controller_memory_seal
		'controller_sha256': controller_memory_pin
		'framework_build_root': direct_boot_framework
		'framework_manifest_sha256': direct_boot_framework_seal
		'framework_jar_sha256': direct_boot_jar
		'framework_dex_sha256': direct_boot_dex
		'retained_framework_manifest_sha256': service_query_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn direct_boot_inputs() map[string]string {
	mut inputs := controller_memory_inputs()
	inputs[direct_boot_base + '/sha256.json'] = direct_boot_base_seal
	inputs[direct_boot_framework + '/sha256.json'] = direct_boot_framework_seal
	return inputs
}

fn direct_boot_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: direct_boot_jar
		'/' + service_query_dex_path: direct_boot_dex
		'/' + service_query_headless + '/framework-build.json': direct_boot_build
		'/' + service_query_headless + '/framework-sha256.json': direct_boot_framework_seal
	}
}

fn verify_direct_boot_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('direct-boot deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := direct_boot_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('direct-boot headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == '11920c8c77da858898ef2dfaca45ecf70f32d41b8884d41c450f6691f7e16292' {
		return error('invalid or retained direct-boot headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('direct-boot five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: direct_boot_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('direct-boot receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('direct-boot overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe direct-boot overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) {
				return error('direct-boot regular allowlist differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected direct-boot overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six direct-boot files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('direct-boot declared input differs from overlay inventory')
		}
	}
}

fn verify_direct_boot_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [direct_boot_base_seal, direct_boot_boot_sha, direct_boot_memory_overlay,
		direct_boot_framework_seal, direct_boot_jar, direct_boot_dex, direct_boot_build] {
		if !digest_valid(pin) { return error('sealed direct-boot base and framework pins required') }
	}
	for name, expected in direct_boot_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('direct-boot receipt differs: ' + name)
		}
	}
	for path, pin in direct_boot_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('direct-boot input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != direct_boot_modules()
		|| stage.preserved_modules_sha256 != direct_boot_modules() {
		return error('direct-boot original eleven module pins differ')
	}
	verify_direct_boot_overlay(receipt)!
}

fn direct_boot_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_direct_boot_receipt(receipt, stage)!
	path := direct_boot_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != direct_boot_base_seal {
		return error('direct-boot original memory-stage manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != direct_boot_boot_sha {
		return error('direct-boot original boot inventory differs')
	}
	return direct_boot_base + '/boot.img'
}

fn context_storage_profile() Profile {
	mut modules := direct_boot_profile().modules.clone()
	modules << 'maps-direct-boot-diagnostic.tar'
	return Profile{'maps-context-storage', context_storage_boot_sha, 'maps-context-storage-diagnostic.tar', modules}
}

fn context_storage_modules() map[string]string {
	mut modules := direct_boot_modules()
	modules['maps-direct-boot-diagnostic.tar'] = context_storage_direct_boot_overlay
	return modules
}

fn context_storage_fields() map[string]string {
	return {
		'kind': 'vinix-maps-context-storage-diagnostic-v1'
		'base_root': context_storage_base
		'base_manifest_sha256': context_storage_base_seal
		'controller_build_root': controller_memory_root
		'controller_manifest_sha256': controller_memory_seal
		'controller_sha256': controller_memory_pin
		'framework_build_root': context_storage_framework
		'framework_manifest_sha256': context_storage_framework_seal
		'framework_jar_sha256': context_storage_jar
		'framework_dex_sha256': context_storage_dex
		'retained_framework_manifest_sha256': direct_boot_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn context_storage_inputs() map[string]string {
	mut inputs := direct_boot_inputs()
	inputs[context_storage_base + '/sha256.json'] = context_storage_base_seal
	inputs[context_storage_framework + '/sha256.json'] = context_storage_framework_seal
	return inputs
}

fn context_storage_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: context_storage_jar
		'/' + service_query_dex_path: context_storage_dex
		'/' + service_query_headless + '/framework-build.json': context_storage_build
		'/' + service_query_headless + '/framework-sha256.json': context_storage_framework_seal
	}
}

fn verify_context_storage_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('context storage deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := context_storage_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('context storage headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == '88404ba463ab108502adaaec46c2038abb0a4984d4af6c68e72e887558f50651' {
		return error('invalid or retained context storage headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('context storage five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: context_storage_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('context storage receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('context storage overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe context storage overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) {
				return error('context storage regular allowlist differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected context storage overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six context storage files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('context storage declared input differs from overlay inventory')
		}
	}
}

fn verify_context_storage_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [context_storage_base_seal, context_storage_boot_sha, context_storage_direct_boot_overlay,
		context_storage_framework_seal, context_storage_jar, context_storage_dex, context_storage_build] {
		if !digest_valid(pin) { return error('sealed context storage base and framework pins required') }
	}
	for name, expected in context_storage_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('context storage receipt differs: ' + name)
		}
	}
	for path, pin in context_storage_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('context storage input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != context_storage_modules()
		|| stage.preserved_modules_sha256 != context_storage_modules() {
		return error('context storage original twelve module pins differ')
	}
	verify_context_storage_overlay(receipt)!
}

fn context_storage_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_context_storage_receipt(receipt, stage)!
	path := context_storage_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != context_storage_base_seal {
		return error('context storage original direct-boot manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != context_storage_boot_sha {
		return error('context storage original boot inventory differs')
	}
	return context_storage_base + '/boot.img'
}

fn broadcast_result_profile() Profile {
	mut modules := context_storage_profile().modules.clone()
	modules << 'maps-context-storage-diagnostic.tar'
	return Profile{'maps-broadcast-result', broadcast_result_boot_sha, 'maps-broadcast-result-diagnostic.tar', modules}
}

fn broadcast_result_modules() map[string]string {
	mut modules := context_storage_modules()
	modules['maps-context-storage-diagnostic.tar'] = broadcast_result_context_overlay
	return modules
}

fn broadcast_result_fields() map[string]string {
	return {
		'kind': 'vinix-maps-broadcast-result-diagnostic-v1'
		'base_root': broadcast_result_base
		'base_manifest_sha256': broadcast_result_base_seal
		'controller_build_root': controller_memory_root
		'controller_manifest_sha256': controller_memory_seal
		'controller_sha256': controller_memory_pin
		'framework_build_root': broadcast_result_framework
		'framework_manifest_sha256': broadcast_result_framework_seal
		'framework_jar_sha256': broadcast_result_jar
		'framework_dex_sha256': broadcast_result_dex
		'retained_framework_manifest_sha256': context_storage_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn broadcast_result_inputs() map[string]string {
	mut inputs := context_storage_inputs()
	inputs[broadcast_result_base + '/sha256.json'] = broadcast_result_base_seal
	inputs[broadcast_result_framework + '/sha256.json'] = broadcast_result_framework_seal
	return inputs
}

fn broadcast_result_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: broadcast_result_jar
		'/' + service_query_dex_path: broadcast_result_dex
		'/' + service_query_headless + '/framework-build.json': broadcast_result_build
		'/' + service_query_headless + '/framework-sha256.json': broadcast_result_framework_seal
	}
}

fn verify_broadcast_result_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('broadcast result deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := broadcast_result_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('broadcast result headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == 'c9ff204863dec37bc1913e0eef2bdf6c9edca1c8cecebeefb7e3659f90e05ab6' {
		return error('invalid or retained broadcast result headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('broadcast result five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: broadcast_result_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('broadcast result receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('broadcast result overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe broadcast result overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) { return error('broadcast result regular allowlist differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected broadcast result overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six broadcast result files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('broadcast result declared input differs from overlay inventory')
		}
	}
}

fn verify_broadcast_result_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [broadcast_result_base_seal, broadcast_result_boot_sha, broadcast_result_context_overlay,
		broadcast_result_framework_seal, broadcast_result_jar, broadcast_result_dex, broadcast_result_build] {
		if !digest_valid(pin) { return error('sealed broadcast result base and framework pins required') }
	}
	for name, expected in broadcast_result_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('broadcast result receipt differs: ' + name) }
	}
	for path, pin in broadcast_result_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('broadcast result input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != broadcast_result_modules()
		|| stage.preserved_modules_sha256 != broadcast_result_modules() {
		return error('broadcast result original thirteen module pins differ')
	}
	verify_broadcast_result_overlay(receipt)!
}

fn broadcast_result_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_broadcast_result_receipt(receipt, stage)!
	path := broadcast_result_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != broadcast_result_base_seal {
		return error('broadcast result original Context storage manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != broadcast_result_boot_sha { return error('broadcast result original boot inventory differs') }
	return broadcast_result_base + '/boot.img'
}

fn onboarding_trace_profile() Profile {
	mut modules := broadcast_result_profile().modules.clone()
	modules << 'maps-broadcast-result-diagnostic.tar'
	return Profile{'maps-onboarding-trace', onboarding_trace_boot_sha, 'maps-onboarding-trace-diagnostic.tar', modules}
}

fn onboarding_trace_modules() map[string]string {
	mut modules := broadcast_result_modules()
	modules['maps-broadcast-result-diagnostic.tar'] = onboarding_trace_base_overlay
	return modules
}

fn onboarding_trace_fields() map[string]string {
	return {
		'kind': 'vinix-maps-onboarding-trace-diagnostic-v1'
		'base_root': onboarding_trace_base
		'base_manifest_sha256': onboarding_trace_base_seal
		'controller_build_root': onboarding_trace_controller
		'controller_manifest_sha256': onboarding_trace_controller_seal
		'controller_sha256': onboarding_trace_controller_pin
		'retained_controller_manifest_sha256': controller_memory_seal
		'framework_manifest_sha256': broadcast_result_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn onboarding_trace_inputs() map[string]string {
	mut inputs := broadcast_result_inputs()
	inputs[onboarding_trace_base + '/sha256.json'] = onboarding_trace_base_seal
	inputs[onboarding_trace_controller + '/sha256.json'] = onboarding_trace_controller_seal
	return inputs
}

fn onboarding_trace_delta() map[string]string {
	return {
		'/opt/vinix-maps-account/bin/maps-account-guest': onboarding_trace_controller_pin
		'/usr/bin/run-android-calculator': onboarding_trace_controller_pin
	}
}

fn verify_onboarding_trace_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('onboarding trace deployment input delta absent') }
	top_delta := receipt['deployment_top_level_delta'] or { return error('onboarding trace deployment top delta absent') }
	if input_delta != json2.decode[json2.Any](json2.encode(onboarding_trace_delta()))!
		|| top_delta != json2.decode[json2.Any](json2.encode(['inputs_sha256']))! {
		return error('onboarding trace deployment delta differs')
	}
	inventory := receipt['overlay_inventory'] or { return error('onboarding trace overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := onboarding_trace_delta().keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe onboarding trace overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) { return error('onboarding trace regular allowlist differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected onboarding trace overlay inode')
		}
	}
	if regulars.len != 3 { return error('exact three onboarding trace files required') }
	for path, pin in onboarding_trace_delta() {
		if regulars[path.trim_left('/')] or { '' } != pin { return error('onboarding trace aliases differ from exact executable') }
	}
}

fn verify_onboarding_trace_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [onboarding_trace_base_seal, onboarding_trace_boot_sha, onboarding_trace_base_overlay,
		onboarding_trace_controller_seal, onboarding_trace_controller_pin] {
		if !digest_valid(pin) { return error('sealed onboarding trace base and controller pins required') }
	}
	if onboarding_trace_controller_seal == controller_memory_seal || onboarding_trace_controller_pin == controller_memory_pin {
		return error('new onboarding trace controller required')
	}
	for name, expected in onboarding_trace_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('onboarding trace receipt differs: ' + name) }
	}
	for path, pin in onboarding_trace_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('onboarding trace input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != onboarding_trace_modules()
		|| stage.preserved_modules_sha256 != onboarding_trace_modules() {
		return error('onboarding trace original fourteen module pins differ')
	}
	verify_onboarding_trace_overlay(receipt)!
}

fn onboarding_trace_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_onboarding_trace_receipt(receipt, stage)!
	path := onboarding_trace_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != onboarding_trace_base_seal {
		return error('onboarding trace original broadcast-result manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != onboarding_trace_boot_sha { return error('onboarding trace original boot inventory differs') }
	return onboarding_trace_base + '/boot.img'
}

fn native_onboarding_trace_profile() Profile {
	mut modules := onboarding_trace_profile().modules.clone()
	modules << 'maps-onboarding-trace-diagnostic.tar'
	return Profile{'maps-native-onboarding-trace', native_onboarding_trace_boot_sha,
		'maps-native-onboarding-trace-diagnostic.tar', modules}
}

fn native_onboarding_trace_modules() map[string]string {
	mut modules := onboarding_trace_modules()
	modules['maps-onboarding-trace-diagnostic.tar'] = native_onboarding_trace_base_overlay
	return modules
}

fn native_onboarding_trace_fields() map[string]string {
	return {
		'kind': 'vinix-maps-native-onboarding-trace-diagnostic-v1'
		'base_root': native_onboarding_trace_base
		'base_manifest_sha256': native_onboarding_trace_base_seal
		'controller_build_root': onboarding_trace_controller
		'controller_manifest_sha256': onboarding_trace_controller_seal
		'controller_sha256': onboarding_trace_controller_pin
		'native_build_root': native_onboarding_trace_root
		'native_manifest_sha256': native_onboarding_trace_seal
		'native_sha256': native_onboarding_trace_pin
		'retained_native_manifest_sha256': protected_native_seal
		'framework_manifest_sha256': broadcast_result_framework_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn native_onboarding_trace_inputs() map[string]string {
	mut inputs := onboarding_trace_inputs()
	inputs[native_onboarding_trace_base + '/sha256.json'] = native_onboarding_trace_base_seal
	inputs[native_onboarding_trace_root + '/sha256.json'] = native_onboarding_trace_seal
	return inputs
}

fn native_onboarding_trace_known_delta() map[string]string {
	return {
		'/' + native_onboarding_trace_path: native_onboarding_trace_pin
		'/' + service_query_headless + '/native-build.json': native_onboarding_trace_build
		'/' + service_query_headless + '/native-sha256.json': native_onboarding_trace_seal
	}
}

fn verify_native_onboarding_trace_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('native onboarding trace deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := native_onboarding_trace_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('native onboarding trace headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == native_onboarding_trace_retained_guest {
		return error('invalid or retained native onboarding trace headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('native onboarding trace four deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + native_onboarding_trace_path: native_onboarding_trace_pin})
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'native_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('native onboarding trace receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('native onboarding trace overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe native onboarding trace overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) { return error('native onboarding trace regular allowlist differs') }
			expected_mode := if entry.name == native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }
			if entry.mode != expected_mode { return error('native onboarding trace inherited regular mode differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected native onboarding trace overlay inode')
		}
	}
	if regulars.len != 5 { return error('exact five native onboarding trace files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('native onboarding trace declared input differs from overlay inventory')
		}
	}
}

fn verify_native_onboarding_trace_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [native_onboarding_trace_base_seal, native_onboarding_trace_boot_sha,
		native_onboarding_trace_base_overlay, native_onboarding_trace_seal,
		native_onboarding_trace_pin, native_onboarding_trace_build] {
		if !digest_valid(pin) { return error('sealed native onboarding trace base and producer pins required') }
	}
	if native_onboarding_trace_seal == protected_native_seal
		|| native_onboarding_trace_pin == native_onboarding_trace_retained_pin
		|| native_onboarding_trace_build == native_onboarding_trace_retained_build {
		return error('new native onboarding trace producer required')
	}
	for name, expected in native_onboarding_trace_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('native onboarding trace receipt differs: ' + name) }
	}
	for path, pin in native_onboarding_trace_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('native onboarding trace input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != native_onboarding_trace_modules()
		|| stage.preserved_modules_sha256 != native_onboarding_trace_modules() {
		return error('native onboarding trace original fifteen module pins differ')
	}
	verify_native_onboarding_trace_overlay(receipt)!
}

fn native_onboarding_trace_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_native_onboarding_trace_receipt(receipt, stage)!
	path := native_onboarding_trace_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != native_onboarding_trace_base_seal {
		return error('native onboarding trace original onboarding manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != native_onboarding_trace_boot_sha { return error('native onboarding trace original boot inventory differs') }
	return native_onboarding_trace_base + '/boot.img'
}

fn onboarding_framework_profile() Profile {
	mut modules := native_onboarding_trace_profile().modules.clone()
	modules << 'maps-native-onboarding-trace-diagnostic.tar'
	return Profile{'maps-onboarding-framework', onboarding_framework_boot_sha,
		'maps-onboarding-framework-diagnostic.tar', modules}
}

fn onboarding_framework_modules() map[string]string {
	mut modules := native_onboarding_trace_modules()
	modules['maps-native-onboarding-trace-diagnostic.tar'] = onboarding_framework_base_overlay
	return modules
}

fn onboarding_framework_fields() map[string]string {
	return {
		'kind': 'vinix-maps-onboarding-framework-diagnostic-v1'
		'base_root': onboarding_framework_base
		'base_manifest_sha256': onboarding_framework_base_seal
		'controller_build_root': onboarding_trace_controller
		'controller_manifest_sha256': onboarding_trace_controller_seal
		'controller_sha256': onboarding_trace_controller_pin
		'native_build_root': native_onboarding_trace_root
		'native_manifest_sha256': native_onboarding_trace_seal
		'native_sha256': native_onboarding_trace_pin
		'framework_build_root': onboarding_framework_root
		'framework_manifest_sha256': onboarding_framework_seal
		'retained_framework_manifest_sha256': broadcast_result_framework_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn onboarding_framework_inputs() map[string]string {
	mut inputs := native_onboarding_trace_inputs()
	// Retain the original role bundles as well as the later diagnostic successors.
	for path, pin in {
		'account-token-fixture-2026-10-26-r7': '3a1cad685bc9c16316e1de97fbd8db8bd75e8b3b5d6380fc985197a44c6e9f58'
		'account-ui-stage-2026-10-26-r3': 'bcb7656ee29c66d2d54fad120aff2d09f078e3a7684ce59c3ac1dd88aa16d394'
		'combined-account-webview-descriptions-framework-2026-10-26-r1': 'd898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021'
		'current-account-build-2026-10-26-r7': '1c761aa0e437bab4f1f2219837c11c78697b31444f0f11b5eea671f09932ce4a'
		'current-browser-build-2026-10-26-r2': 'af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3'
		'current-native-build-2026-10-26-r17': '77503d184cc53fe3527f1949f7b88648b5a6bacd1e6b74bd82acb82fec222419'
		'current-token-cache-controller-build-2026-10-26-r2': '5ea4efd5327ba354cd16207ee1602d085d0576d4641d119f1a1f0b5a2a52f52c'
		'current-ui-controller-build-2026-10-26-r1': '503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a'
		'maps-account-browser-deployment-2026-10-26-r7': 'bc9f6e776d0c81bb1bca160ab1e4289e31db9f2a05983e00ba0fcb42be86244d'
		'maps-account-r5': protected_base_seal
	} {
		inputs['/Users/alex/.local/state/vinix/android/' + path + '/sha256.json'] = pin
	}
	inputs[onboarding_framework_base + '/sha256.json'] = onboarding_framework_base_seal
	inputs[onboarding_framework_root + '/sha256.json'] = onboarding_framework_seal
	return inputs
}

fn onboarding_framework_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: onboarding_framework_jar
		'/' + service_query_dex_path: onboarding_framework_dex
		'/' + service_query_headless + '/framework-build.json': onboarding_framework_build
		'/' + service_query_headless + '/framework-sha256.json': onboarding_framework_seal
	}
}

fn verify_onboarding_framework_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('onboarding framework deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := onboarding_framework_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('onboarding framework headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == onboarding_framework_retained_guest {
		return error('invalid or retained onboarding framework headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('onboarding framework five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: onboarding_framework_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('onboarding framework receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('onboarding framework overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe onboarding framework overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != 0o644 {
				return error('onboarding framework regular allowlist or inherited mode differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected onboarding framework overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six onboarding framework files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('onboarding framework declared input differs from overlay inventory')
		}
	}
}

fn verify_onboarding_framework_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [onboarding_framework_base_seal, onboarding_framework_boot_sha,
		onboarding_framework_base_overlay, onboarding_framework_seal,
		onboarding_framework_jar, onboarding_framework_dex, onboarding_framework_build] {
		if !digest_valid(pin) { return error('sealed onboarding framework base and producer pins required') }
	}
	if onboarding_framework_seal == broadcast_result_framework_seal || onboarding_framework_jar == broadcast_result_jar
		|| onboarding_framework_dex == broadcast_result_dex || onboarding_framework_build == broadcast_result_build {
		return error('new onboarding framework producer required')
	}
	for name, expected in onboarding_framework_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('onboarding framework receipt differs: ' + name) }
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 32 || sealed_inputs != onboarding_framework_inputs() {
		return error('onboarding framework exact thirty-two complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != onboarding_framework_modules()
		|| stage.preserved_modules_sha256 != onboarding_framework_modules() {
		return error('onboarding framework original sixteen module pins differ')
	}
	verify_onboarding_framework_overlay(receipt)!
}

fn onboarding_framework_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_onboarding_framework_receipt(receipt, stage)!
	path := onboarding_framework_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != onboarding_framework_base_seal {
		return error('onboarding framework original native trace manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != onboarding_framework_boot_sha { return error('onboarding framework original boot inventory differs') }
	return onboarding_framework_base + '/boot.img'
}

fn native_heartbeat_profile() Profile {
	mut modules := onboarding_framework_profile().modules.clone()
	modules << 'maps-onboarding-framework-diagnostic.tar'
	return Profile{'maps-native-heartbeat', native_heartbeat_boot_sha,
		'maps-native-heartbeat-diagnostic.tar', modules}
}

fn native_heartbeat_modules() map[string]string {
	mut modules := onboarding_framework_modules()
	modules['maps-onboarding-framework-diagnostic.tar'] = native_heartbeat_base_overlay
	return modules
}

fn native_heartbeat_fields() map[string]string {
	return {
		'kind': 'vinix-maps-native-heartbeat-diagnostic-v1'
		'base_root': native_heartbeat_base
		'base_manifest_sha256': native_heartbeat_base_seal
		'controller_build_root': onboarding_trace_controller
		'controller_manifest_sha256': onboarding_trace_controller_seal
		'controller_sha256': onboarding_trace_controller_pin
		'native_build_root': native_heartbeat_root
		'native_manifest_sha256': native_heartbeat_seal
		'native_sha256': native_heartbeat_pin
		'retained_native_manifest_sha256': native_onboarding_trace_seal
		'framework_build_root': onboarding_framework_root
		'framework_manifest_sha256': onboarding_framework_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn native_heartbeat_inputs() map[string]string {
	mut inputs := onboarding_framework_inputs()
	inputs[native_heartbeat_base + '/sha256.json'] = native_heartbeat_base_seal
	inputs[native_heartbeat_root + '/sha256.json'] = native_heartbeat_seal
	return inputs
}

fn native_heartbeat_known_delta() map[string]string {
	return {
		'/' + native_onboarding_trace_path: native_heartbeat_pin
		'/' + service_query_headless + '/native-build.json': native_heartbeat_build
		'/' + service_query_headless + '/native-sha256.json': native_heartbeat_seal
	}
}

fn verify_native_heartbeat_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('native heartbeat deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := native_heartbeat_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('native heartbeat headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == native_heartbeat_retained_guest {
		return error('invalid or retained native heartbeat headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('native heartbeat four deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + native_onboarding_trace_path: native_heartbeat_pin})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'native_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('native heartbeat receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('native heartbeat overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe native heartbeat overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) { return error('native heartbeat regular allowlist differs') }
			expected_mode := if entry.name == native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }
			if entry.mode != expected_mode { return error('native heartbeat inherited regular mode differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected native heartbeat overlay inode')
		}
	}
	if regulars.len != 5 { return error('exact five native heartbeat files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('native heartbeat declared input differs from overlay inventory')
		}
	}
}

fn verify_native_heartbeat_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [native_heartbeat_base_seal, native_heartbeat_boot_sha,
		native_heartbeat_base_overlay, native_heartbeat_seal, native_heartbeat_pin,
		native_heartbeat_build, onboarding_framework_seal, onboarding_framework_jar,
		onboarding_framework_dex] {
		if !digest_valid(pin) { return error('sealed native heartbeat base and producer pins required') }
	}
	if native_heartbeat_seal == native_onboarding_trace_seal
		|| native_heartbeat_pin == native_onboarding_trace_pin
		|| native_heartbeat_build == native_onboarding_trace_build {
		return error('new native heartbeat producer required')
	}
	for name, expected in native_heartbeat_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('native heartbeat receipt differs: ' + name) }
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 34 || sealed_inputs != native_heartbeat_inputs() {
		return error('native heartbeat exact thirty-four complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != native_heartbeat_modules()
		|| stage.preserved_modules_sha256 != native_heartbeat_modules() {
		return error('native heartbeat original seventeen module pins differ')
	}
	verify_native_heartbeat_overlay(receipt)!
}

fn native_heartbeat_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_native_heartbeat_receipt(receipt, stage)!
	path := native_heartbeat_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != native_heartbeat_base_seal {
		return error('native heartbeat original framework manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != native_heartbeat_boot_sha { return error('native heartbeat original boot inventory differs') }
	return native_heartbeat_base + '/boot.img'
}

fn browser_poll_profile() Profile {
	mut modules := native_heartbeat_profile().modules.clone()
	modules << 'maps-native-heartbeat-diagnostic.tar'
	return Profile{'maps-browser-poll', browser_poll_boot_sha, 'maps-browser-poll.tar', modules}
}

fn browser_poll_modules() map[string]string {
	mut modules := native_heartbeat_modules()
	modules['maps-native-heartbeat-diagnostic.tar'] = browser_poll_base_overlay
	return modules
}

fn browser_poll_fields() map[string]string {
	return {
		'kind': 'vinix-maps-browser-poll-v1'
		'base_root': browser_poll_base
		'base_manifest_sha256': browser_poll_base_seal
		'browser_client_build_root': browser_poll_root
		'browser_client_manifest_sha256': browser_poll_seal
		'browser_client_sha256': browser_poll_pin
		'retained_browser_client_manifest_sha256': browser_poll_retained_seal
		'controller_build_root': onboarding_trace_controller
		'controller_manifest_sha256': onboarding_trace_controller_seal
		'controller_sha256': onboarding_trace_controller_pin
		'native_build_root': native_heartbeat_root
		'native_manifest_sha256': native_heartbeat_seal
		'native_sha256': native_heartbeat_pin
		'framework_build_root': onboarding_framework_root
		'framework_manifest_sha256': onboarding_framework_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn browser_poll_inputs() map[string]string {
	mut inputs := native_heartbeat_inputs()
	inputs[browser_poll_base + '/sha256.json'] = browser_poll_base_seal
	inputs[browser_poll_root + '/sha256.json'] = browser_poll_seal
	return inputs
}

fn verify_browser_poll_overlay(receipt map[string]json2.Any) ! {
	expected := {'/' + browser_poll_path: browser_poll_pin}
	input_delta := receipt['deployment_input_delta'] or { return error('browser poll deployment input delta absent') }
	if json2.decode[map[string]string](json2.encode(input_delta))! != expected {
		return error('browser poll exact one browser library input change required')
	}
	if receipt['deployment_top_level_delta'] or { json2.Any('absent') }
		!= json2.decode[json2.Any](json2.encode(['inputs_sha256', 'browser_client_manifest_sha256']))! {
		return error('browser poll deployment top-level delta differs')
	}
	if 'headless_input_delta' in receipt || 'headless_top_level_delta' in receipt {
		return error('browser poll must preserve headless receipts')
	}
	inventory := receipt['overlay_inventory'] or { return error('browser poll overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	paths := [browser_poll_path, service_query_deployment]
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe browser poll overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != 0o644 {
				return error('browser poll inherited regular file allowlist or mode differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected browser poll overlay inode')
		}
	}
	if regulars.len != 2 || regulars[browser_poll_path] or { '' } != browser_poll_pin {
		return error('exact two browser poll files with selected library required')
	}
}

fn verify_browser_poll_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [browser_poll_base_seal, browser_poll_boot_sha, browser_poll_base_overlay,
		browser_poll_seal, browser_poll_pin, browser_poll_retained_seal, browser_poll_retained_pin,
		native_heartbeat_seal, native_heartbeat_pin, onboarding_framework_seal,
		onboarding_framework_jar, onboarding_framework_dex, onboarding_trace_controller_seal,
		onboarding_trace_controller_pin] {
		if !digest_valid(pin) { return error('sealed browser poll base and producer pins required') }
	}
	if browser_poll_seal == browser_poll_retained_seal || browser_poll_pin == browser_poll_retained_pin {
		return error('new browser poll producer required')
	}
	for name, expected in browser_poll_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('browser poll receipt differs: ' + name)
		}
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 36 || sealed_inputs != browser_poll_inputs() {
		return error('browser poll exact thirty-six complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != browser_poll_modules()
		|| stage.preserved_modules_sha256 != browser_poll_modules() {
		return error('browser poll original eighteen module pins differ')
	}
	verify_browser_poll_overlay(receipt)!
}

fn browser_poll_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_browser_poll_receipt(receipt, stage)!
	path := browser_poll_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != browser_poll_base_seal {
		return error('browser poll original heartbeat manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != browser_poll_boot_sha { return error('browser poll original boot inventory differs') }
	return browser_poll_base + '/boot.img'
}

fn account_pump_profile() Profile {
	mut modules := browser_poll_profile().modules.clone()
	modules << 'maps-browser-poll.tar'
	return Profile{'maps-account-pump', account_pump_boot_sha, 'maps-account-pump.tar', modules}
}

fn account_pump_modules() map[string]string {
	mut modules := browser_poll_modules()
	modules['maps-browser-poll.tar'] = account_pump_base_overlay
	return modules
}

fn account_pump_fields() map[string]string {
	mut fields := browser_poll_fields()
	fields['kind'] = 'vinix-maps-account-pump-v1'
	fields['base_root'] = account_pump_base
	fields['base_manifest_sha256'] = account_pump_base_seal
	fields['native_build_root'] = account_pump_root
	fields['native_manifest_sha256'] = account_pump_seal
	fields['native_sha256'] = account_pump_pin
	fields['native_build_sha256'] = account_pump_build
	fields['retained_native_manifest_sha256'] = native_heartbeat_seal
	fields['retained_browser_client_manifest_sha256'] = browser_poll_seal
	return fields
}

fn account_pump_inputs() map[string]string {
	mut inputs := browser_poll_inputs()
	inputs[account_pump_base + '/sha256.json'] = account_pump_base_seal
	inputs[account_pump_root + '/sha256.json'] = account_pump_seal
	return inputs
}

fn verify_account_pump_overlay(receipt map[string]json2.Any) ! {
	expected := {'/' + native_onboarding_trace_path: account_pump_pin}
	input_delta := receipt['deployment_input_delta'] or { return error('account pump deployment input delta absent') }
	if json2.decode[map[string]string](json2.encode(input_delta))! != expected {
		return error('account pump exact one native library input change required')
	}
	if receipt['deployment_top_level_delta'] or { json2.Any('absent') }
		!= json2.decode[json2.Any](json2.encode(['inputs_sha256', 'native_manifest_sha256']))! {
		return error('account pump deployment top-level delta differs')
	}
	if 'headless_input_delta' in receipt || 'headless_top_level_delta' in receipt {
		return error('account pump must preserve headless receipts')
	}
	source_delta := receipt['native_source_delta'] or { return error('account pump source delta absent') }
	if json2.decode[map[string]string](json2.encode(source_delta))!
		!= {'build-support/android/nativews/account_service.v': account_pump_source_pin} {
		return error('account pump exact reviewed account service source delta required')
	}
	inventory := receipt['overlay_inventory'] or { return error('account pump overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	paths := [native_onboarding_trace_path, service_query_deployment]
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe account pump overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			expected_mode := if entry.name == native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != expected_mode {
				return error('account pump regular file allowlist or mode differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected account pump overlay inode')
		}
	}
	if regulars.len != 2 || regulars[native_onboarding_trace_path] or { '' } != account_pump_pin {
		return error('exact two account pump files with selected native library required')
	}
}

fn verify_account_pump_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [account_pump_base_seal, account_pump_boot_sha, account_pump_base_overlay,
		account_pump_seal, account_pump_pin, account_pump_build, account_pump_source_pin,
		native_heartbeat_seal, native_heartbeat_pin, native_heartbeat_build,
		browser_poll_seal, browser_poll_pin, onboarding_framework_seal,
		onboarding_framework_jar, onboarding_framework_dex, onboarding_trace_controller_seal,
		onboarding_trace_controller_pin] {
		if !digest_valid(pin) { return error('sealed account pump base and reviewed native producer pins required') }
	}
	if account_pump_seal == native_heartbeat_seal || account_pump_pin == native_heartbeat_pin
		|| account_pump_build == native_heartbeat_build {
		return error('new account pump native producer required')
	}
	for name, expected in account_pump_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('account pump receipt differs: ' + name)
		}
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 38 || sealed_inputs != account_pump_inputs() {
		return error('account pump exact thirty-eight complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != account_pump_modules()
		|| stage.preserved_modules_sha256 != account_pump_modules() {
		return error('account pump original nineteen module pins differ')
	}
	verify_account_pump_overlay(receipt)!
}

fn account_pump_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_account_pump_receipt(receipt, stage)!
	path := account_pump_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != account_pump_base_seal {
		return error('account pump original browser poll manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != account_pump_boot_sha
		|| pins['maps-browser-poll.tar'] or { '' } != account_pump_base_overlay {
		return error('account pump original boot or browser poll overlay inventory differs')
	}
	return account_pump_base + '/boot.img'
}

fn application_restrictions_profile() Profile {
	mut modules := account_pump_profile().modules.clone()
	modules << 'maps-account-pump.tar'
	return Profile{'maps-application-restrictions', application_restrictions_boot_sha,
		'maps-application-restrictions.tar', modules}
}

fn application_restrictions_modules() map[string]string {
	mut modules := account_pump_modules()
	modules['maps-account-pump.tar'] = application_restrictions_base_overlay
	return modules
}

fn application_restrictions_fields() map[string]string {
	mut fields := onboarding_framework_fields()
	fields['kind'] = 'vinix-maps-application-restrictions-v1'
	fields['base_root'] = application_restrictions_base
	fields['base_manifest_sha256'] = application_restrictions_base_seal
	fields['framework_build_root'] = application_restrictions_root
	fields['framework_manifest_sha256'] = application_restrictions_seal
	fields['retained_framework_manifest_sha256'] = onboarding_framework_seal
	fields['native_build_root'] = account_pump_root
	fields['native_manifest_sha256'] = account_pump_seal
	fields['native_sha256'] = account_pump_pin
	fields['native_build_sha256'] = account_pump_build
	fields['browser_client_build_root'] = browser_poll_root
	fields['browser_client_manifest_sha256'] = browser_poll_seal
	fields['browser_client_sha256'] = browser_poll_pin
	return fields
}

fn application_restrictions_inputs() map[string]string {
	mut inputs := account_pump_inputs()
	inputs[application_restrictions_base + '/sha256.json'] = application_restrictions_base_seal
	inputs[application_restrictions_root + '/sha256.json'] = application_restrictions_seal
	return inputs
}

fn application_restrictions_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: application_restrictions_jar
		'/' + service_query_dex_path: application_restrictions_dex
		'/' + service_query_headless + '/framework-build.json': application_restrictions_build
		'/' + service_query_headless + '/framework-sha256.json': application_restrictions_seal
	}
}

fn verify_application_restrictions_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('application restrictions deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := application_restrictions_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('application restrictions headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == application_restrictions_retained_guest {
		return error('invalid or retained application restrictions headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('application restrictions exact five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: application_restrictions_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('application restrictions receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('application restrictions overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe application restrictions overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != 0o644 {
				return error('application restrictions regular allowlist or inherited mode differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected application restrictions overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six application restrictions files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('application restrictions declared input differs from overlay inventory')
		}
	}
}

fn verify_application_restrictions_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [application_restrictions_base_seal, application_restrictions_boot_sha,
		application_restrictions_base_overlay, application_restrictions_seal,
		application_restrictions_jar, application_restrictions_dex, application_restrictions_build,
		application_restrictions_retained_guest, account_pump_seal, account_pump_pin,
		account_pump_build, browser_poll_seal, browser_poll_pin] {
		if !digest_valid(pin) { return error('sealed application restrictions base and producer pins required') }
	}
	if application_restrictions_seal == onboarding_framework_seal || application_restrictions_jar == onboarding_framework_jar
		|| application_restrictions_dex == onboarding_framework_dex || application_restrictions_build == onboarding_framework_build {
		return error('new application restrictions framework producer required')
	}
	for name, expected in application_restrictions_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('application restrictions receipt differs: ' + name) }
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 40 || sealed_inputs != application_restrictions_inputs() {
		return error('application restrictions exact forty complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != application_restrictions_modules()
		|| stage.preserved_modules_sha256 != application_restrictions_modules() {
		return error('application restrictions original twenty module pins differ')
	}
	verify_application_restrictions_overlay(receipt)!
}

fn application_restrictions_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_application_restrictions_receipt(receipt, stage)!
	path := application_restrictions_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != application_restrictions_base_seal {
		return error('application restrictions original account pump manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != application_restrictions_boot_sha
		|| pins['maps-account-pump.tar'] or { '' } != application_restrictions_base_overlay {
		return error('application restrictions original boot or account pump overlay inventory differs')
	}
	return application_restrictions_base + '/boot.img'
}

fn account_handoff_profile() Profile {
	mut modules := application_restrictions_profile().modules.clone()
	modules << 'maps-application-restrictions.tar'
	return Profile{'maps-account-handoff', account_handoff_boot_sha, 'maps-account-handoff.tar', modules}
}

fn account_handoff_modules() map[string]string {
	mut modules := application_restrictions_modules()
	modules['maps-application-restrictions.tar'] = account_handoff_base_overlay
	return modules
}

fn account_handoff_fields() map[string]string {
	mut fields := application_restrictions_fields()
	fields['kind'] = 'vinix-maps-account-handoff-v1'
	fields['base_root'] = account_handoff_base
	fields['base_manifest_sha256'] = account_handoff_base_seal
	fields['broker_build_root'] = account_handoff_broker_root
	fields['broker_manifest_sha256'] = account_handoff_broker_seal
	fields['broker_sha256'] = account_handoff_broker_pin
	fields['retained_broker_manifest_sha256'] = fields['retained_launch_manifest_sha256']!
	fields['controller_build_root'] = account_handoff_controller_root
	fields['controller_manifest_sha256'] = account_handoff_controller_seal
	fields['controller_sha256'] = account_handoff_controller_pin
	fields['retained_controller_manifest_sha256'] = onboarding_trace_controller_seal
	return fields
}

fn account_handoff_inputs() map[string]string {
	mut inputs := application_restrictions_inputs()
	inputs[account_handoff_base + '/sha256.json'] = account_handoff_base_seal
	inputs[account_handoff_broker_root + '/sha256.json'] = account_handoff_broker_seal
	inputs[account_handoff_controller_root + '/sha256.json'] = account_handoff_controller_seal
	return inputs
}

fn account_handoff_delta() map[string]string {
	return {
		'/' + account_handoff_broker_path: account_handoff_broker_pin
		'/opt/vinix-maps-account/bin/maps-account-guest': account_handoff_controller_pin
		'/usr/bin/run-android-calculator': account_handoff_controller_pin
	}
}

fn verify_account_handoff_overlay(receipt map[string]json2.Any) ! {
	for name, value in {
		'deployment_input_delta': json2.encode(account_handoff_delta())
		'deployment_top_level_delta': json2.encode(['inputs_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('account handoff exact deployment delta differs: ' + name)
		}
	}
	for name in ['headless_input_delta', 'headless_top_level_delta'] {
		if name in receipt { return error('account handoff declares an unexpected headless delta') }
	}
	inventory := receipt['overlay_inventory'] or { return error('account handoff overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut paths := account_handoff_delta().keys().map(it.trim_left('/'))
	paths << service_query_deployment
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe account handoff overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			mode := if entry.name == service_query_deployment { u32(0o644) } else { u32(0o755) }
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != mode {
				return error('account handoff regular allowlist or inherited mode differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected account handoff overlay inode')
		}
	}
	if regulars.len != 4 { return error('exact four account handoff files required') }
	for path, pin in account_handoff_delta() {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('account handoff executable differs from exact producer')
		}
	}
	if regulars[service_query_deployment] or { '' } == account_handoff_retained_deployment {
		return error('account handoff retained deployment receipt supplied')
	}
}

fn verify_account_handoff_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [account_handoff_base_seal, account_handoff_boot_sha, account_handoff_base_overlay,
		account_handoff_retained_deployment, account_handoff_retained_broker,
		account_handoff_broker_seal, account_handoff_broker_pin,
		account_handoff_controller_seal, account_handoff_controller_pin] {
		if !digest_valid(pin) { return error('sealed account handoff base and producer pins required') }
	}
	if account_handoff_controller_seal == onboarding_trace_controller_seal
		|| account_handoff_controller_pin == onboarding_trace_controller_pin
		|| account_handoff_broker_pin == account_handoff_retained_broker
		|| account_handoff_broker_seal == account_handoff_fields()['retained_launch_manifest_sha256']! {
		return error('new account handoff broker and controller producers required')
	}
	for name, expected in account_handoff_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('account handoff receipt differs: ' + name)
		}
	}
	mut sealed_inputs := map[string]string{}
	for path, pin in stage.inputs_sha256 {
		if path.ends_with('/sha256.json') { sealed_inputs[path] = pin }
	}
	if sealed_inputs.len != 43 || sealed_inputs != account_handoff_inputs() {
		return error('account handoff exact forty-three complete dependency seals differ')
	}
	if stage.format != 1 || stage.original_modules_sha256 != account_handoff_modules()
		|| stage.preserved_modules_sha256 != account_handoff_modules() {
		return error('account handoff original twenty-one module pins differ')
	}
	verify_account_handoff_overlay(receipt)!
}

fn account_handoff_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_account_handoff_receipt(receipt, stage)!
	path := account_handoff_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != account_handoff_base_seal {
		return error('account handoff original application restrictions manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != account_handoff_boot_sha
		|| pins['maps-application-restrictions.tar'] or { '' } != account_handoff_base_overlay {
		return error('account handoff original boot or application restrictions overlay differs')
	}
	return account_handoff_base + '/boot.img'
}

fn auth_exception_profile() Profile {
	mut modules := account_handoff_profile().modules.clone()
	modules << 'maps-account-handoff.tar'
	return Profile{'maps-auth-exception', auth_exception_boot_sha, 'maps-auth-exception.tar', modules}
}

fn auth_exception_modules() map[string]string {
	mut modules := account_handoff_modules()
	modules['maps-account-handoff.tar'] = auth_exception_base_overlay
	return modules
}

fn auth_exception_fields() map[string]string {
	mut fields := account_handoff_fields()
	fields['kind'] = 'vinix-maps-auth-exception-v1'
	fields['base_root'] = auth_exception_base
	fields['base_manifest_sha256'] = auth_exception_base_seal
	fields['framework_build_root'] = auth_exception_framework
	fields['framework_manifest_sha256'] = auth_exception_framework_seal
	fields['framework_jar_sha256'] = auth_exception_jar
	fields['framework_dex_sha256'] = auth_exception_dex
	fields['retained_framework_manifest_sha256'] = application_restrictions_seal
	return fields
}

fn auth_exception_inputs() map[string]string {
	mut inputs := account_handoff_inputs()
	inputs[auth_exception_base + '/sha256.json'] = auth_exception_base_seal
	inputs[auth_exception_framework + '/sha256.json'] = auth_exception_framework_seal
	return inputs
}

fn auth_exception_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: auth_exception_jar
		'/' + service_query_dex_path: auth_exception_dex
		'/' + service_query_headless + '/framework-build.json': auth_exception_build
		'/' + service_query_headless + '/framework-sha256.json': auth_exception_framework_seal
	}
}

fn verify_auth_exception_overlay(receipt map[string]json2.Any) ! {
	delta := json2.decode[map[string]string](json2.encode(receipt['deployment_input_delta'] or { return error('auth exception deployment delta absent') }))!
	mut expected := auth_exception_known_delta()
	guest := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest] or { return error('auth exception headless pin absent') }
	if !digest_valid(guest_pin) || guest_pin == '3564b3199e852f5ca7046fbe4fd199ccd02ba150c1c1f20b6d87e202a8dec930' {
		return error('invalid or retained auth exception headless receipt')
	}
	expected[guest] = guest_pin
	if delta != expected { return error('auth exception exact five deployment changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: auth_exception_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! { return error('auth exception receipt delta differs: ' + name) }
	}
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(receipt['overlay_inventory'] or { return error('auth exception inventory absent') }))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 { return error('unsafe auth exception inode') }
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != 0o644 { return error('auth exception file allowlist or mode differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) { return error('unexpected auth exception inode') }
	}
	if regulars.len != 6 || regulars[service_query_deployment] or { '' } == auth_exception_retained_deployment { return error('exact six new auth exception files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin { return error('auth exception declared input differs from inventory') }
	}
}

fn verify_auth_exception_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [auth_exception_base_seal, auth_exception_boot_sha, auth_exception_base_overlay,
		auth_exception_retained_deployment, auth_exception_framework_seal, auth_exception_jar, auth_exception_dex, auth_exception_build] {
		if !digest_valid(pin) { return error('sealed auth exception producer pins required') }
	}
	if auth_exception_framework_seal == application_restrictions_seal || auth_exception_jar == application_restrictions_jar
		|| auth_exception_dex == application_restrictions_dex { return error('new auth exception framework required') }
	for name, expected in auth_exception_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('auth exception receipt differs: ' + name) }
	}
	mut seals := map[string]string{}
	for path, pin in stage.inputs_sha256 { if path.ends_with('/sha256.json') { seals[path] = pin } }
	if seals.len != 45 || seals != auth_exception_inputs() { return error('auth exception exact forty-five dependency seals differ') }
	if stage.format != 1 || stage.original_modules_sha256 != auth_exception_modules() || stage.preserved_modules_sha256 != auth_exception_modules() {
		return error('auth exception original twenty-two modules differ')
	}
	verify_auth_exception_overlay(receipt)!
}

fn auth_exception_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_auth_exception_receipt(receipt, stage)!
	path := auth_exception_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != auth_exception_base_seal { return error('auth exception original handoff manifest differs') }
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != auth_exception_boot_sha || pins['maps-account-handoff.tar'] or { '' } != auth_exception_base_overlay {
		return error('auth exception original boot or handoff overlay differs')
	}
	return auth_exception_base + '/boot.img'
}

fn auth_worker_profile() Profile {
	mut modules := auth_exception_profile().modules.clone()
	modules << 'maps-auth-exception.tar'
	return Profile{'maps-auth-worker', auth_worker_boot_sha, 'maps-auth-worker.tar', modules}
}
fn auth_worker_modules() map[string]string {
	mut modules := auth_exception_modules()
	modules['maps-auth-exception.tar'] = auth_worker_base_overlay
	return modules
}
fn auth_worker_fields() map[string]string {
	mut fields := auth_exception_fields()
	fields['kind'] = 'vinix-maps-auth-worker-v1'
	fields['base_root'] = auth_worker_base
	fields['base_manifest_sha256'] = auth_worker_base_seal
	fields['native_build_root'] = auth_worker_root
	fields['native_manifest_sha256'] = auth_worker_seal
	fields['native_sha256'] = auth_worker_pin
	fields['native_build_sha256'] = auth_worker_build
	fields['retained_native_manifest_sha256'] = account_pump_seal
	return fields
}
fn auth_worker_inputs() map[string]string {
	mut inputs := auth_exception_inputs()
	inputs[auth_worker_base + '/sha256.json'] = auth_worker_base_seal
	inputs[auth_worker_root + '/sha256.json'] = auth_worker_seal
	return inputs
}
fn auth_worker_delta() map[string]string {
	return {'/' + native_onboarding_trace_path: auth_worker_pin}
}
fn verify_auth_worker_overlay(receipt map[string]json2.Any) ! {
	for name, value in {
		'deployment_input_delta': json2.encode(auth_worker_delta())
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'native_manifest_sha256'])
		'native_source_delta': json2.encode({'build-support/android/nativews/account_service.v': auth_worker_service_source,
			'build-support/android/nativews/account_worker.v': auth_worker_added_source})
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! { return error('auth worker declared delta differs: ' + name) }
	}
	for name in ['headless_input_delta', 'headless_top_level_delta'] { if name in receipt { return error('auth worker may not change retained headless roles') } }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(receipt['overlay_inventory'] or { return error('auth worker overlay inventory absent') }))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	paths := [native_onboarding_trace_path, service_query_deployment]
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 { return error('unsafe auth worker overlay inode') }
		seen[entry.name] = true
		if entry.kind == 'regular' {
			mode := if entry.name == native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }
			if entry.name !in paths || !digest_valid(entry.sha256) || entry.mode != mode { return error('auth worker file allowlist or mode differs') }
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !paths.any(it.starts_with(entry.name + '/')) { return error('unexpected auth worker inode') }
	}
	if regulars.len != 2 || regulars[native_onboarding_trace_path] or { '' } != auth_worker_pin
		|| regulars[service_query_deployment] or { '' } == auth_worker_retained_deployment { return error('exact two new auth worker files required') }
}
fn verify_auth_worker_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [auth_worker_base_seal, auth_worker_boot_sha, auth_worker_base_overlay,
		auth_worker_retained_deployment, auth_worker_seal, auth_worker_pin, auth_worker_build, auth_worker_service_source, auth_worker_added_source] {
		if !digest_valid(pin) { return error('completed reviewed auth worker producer required') }
	}
	if auth_worker_seal == account_pump_seal || auth_worker_pin == account_pump_pin || auth_worker_service_source == account_pump_source_pin { return error('new auth worker implementation required') }
	for name, expected in auth_worker_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) { return error('auth worker receipt differs: ' + name) }
	}
	mut seals := map[string]string{}
	for path, pin in stage.inputs_sha256 { if path.ends_with('/sha256.json') { seals[path] = pin } }
	if seals.len != 47 || seals != auth_worker_inputs() { return error('auth worker exact forty-seven dependency seals differ') }
	if stage.format != 1 || stage.original_modules_sha256 != auth_worker_modules() || stage.preserved_modules_sha256 != auth_worker_modules() { return error('auth worker original twenty-three modules differ') }
	verify_auth_worker_overlay(receipt)!
}
fn auth_worker_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_auth_worker_receipt(receipt, stage)!
	path := auth_worker_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != auth_worker_base_seal { return error('auth worker original exception-stage manifest differs') }
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != auth_worker_boot_sha || pins['maps-auth-exception.tar'] or { '' } != auth_worker_base_overlay { return error('auth worker original boot or exception overlay differs') }
	return auth_worker_base + '/boot.img'
}

fn service_query_modules() map[string]string {
	mut modules := controller_modules()
	modules['maps-controller-diagnostic.tar'] = 'bef5f25859e77a9671a6a144ccb56891da5ed2f7b4324a93a96da7fdcab1987a'
	return modules
}

fn service_query_fields() map[string]string {
	return {
		'kind': 'vinix-maps-service-query-diagnostic-v1'
		'base_root': service_query_base
		'base_manifest_sha256': service_query_base_seal
		'framework_build_root': service_query_framework
		'framework_manifest_sha256': service_query_framework_seal
		'framework_jar_sha256': service_query_jar
		'framework_dex_sha256': service_query_dex
		'retained_framework_manifest_sha256': protected_framework_seal
		'controller_build_root': controller_root
		'controller_manifest_sha256': controller_seal
		'controller_sha256': controller_pin
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn service_query_inputs() map[string]string {
	mut inputs := controller_inputs()
	inputs[service_query_base + '/sha256.json'] = service_query_base_seal
	inputs[service_query_framework + '/sha256.json'] = service_query_framework_seal
	return inputs
}

fn service_query_known_delta() map[string]string {
	return {
		'/' + service_query_jar_path: service_query_jar
		'/' + service_query_dex_path: service_query_dex
		'/' + service_query_headless + '/framework-build.json': service_query_build
		'/' + service_query_headless + '/framework-sha256.json': service_query_framework_seal
	}
}

struct ServiceQueryEntry {
	name string
	kind string
	sha256 string
	mode u32
}

// The generated headless input receipt has a digest declared by the stager.
// All other framework files are pinned here to the complete sealed producer.
fn verify_service_query_overlay(receipt map[string]json2.Any) ! {
	input_delta := receipt['deployment_input_delta'] or { return error('service-query deployment input delta absent') }
	delta := json2.decode[map[string]string](json2.encode(input_delta))!
	mut expected := service_query_known_delta()
	guest_path := '/' + service_query_headless + '/guest-inputs.json'
	guest_pin := delta[guest_path] or { return error('service-query headless receipt pin absent') }
	if !digest_valid(guest_pin) || guest_pin == 'e60879ad6b10077c22fd271b29f741b28ad54b7eb7aed256782afe7f5a7550a9' {
		return error('invalid or retained service-query headless receipt pin')
	}
	expected[guest_path] = guest_pin
	if delta != expected { return error('service-query five deployment input changes differ') }
	for name, value in {
		'headless_input_delta': json2.encode({'/' + service_query_jar_path: service_query_jar})
		'headless_top_level_delta': json2.encode(['inputs_sha256'])
		'deployment_top_level_delta': json2.encode(['inputs_sha256', 'framework_manifest_sha256'])
	} {
		if receipt[name] or { json2.Any('absent') } != json2.decode[json2.Any](value)! {
			return error('service-query receipt delta differs: ' + name)
		}
	}
	inventory := receipt['overlay_inventory'] or { return error('service-query overlay inventory absent') }
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(inventory))!
	mut regulars := map[string]string{}
	mut seen := map[string]bool{}
	mut paths := expected.keys().map(it.trim_left('/'))
	paths << service_query_deployment
	for entry in entries {
		if entry.name in seen || !relative(entry.name) || entry.mode & 0o7022 != 0 {
			return error('unsafe service-query overlay inventory entry')
		}
		seen[entry.name] = true
		if entry.kind == 'regular' {
			if entry.name !in paths || !digest_valid(entry.sha256) {
				return error('service-query regular allowlist differs')
			}
			regulars[entry.name] = entry.sha256
		} else if entry.kind != 'directory' || !paths.any(it.starts_with(entry.name + '/')) {
			return error('unexpected service-query overlay inode')
		}
	}
	if regulars.len != 6 { return error('exact six service-query files required') }
	for path, pin in expected {
		if regulars[path.trim_left('/')] or { '' } != pin {
			return error('service-query declared input differs from overlay inventory')
		}
	}
}

fn verify_service_query_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for pin in [service_query_framework_seal, service_query_jar, service_query_dex, service_query_build] {
		if !digest_valid(pin) { return error('sealed service-query framework pins required') }
	}
	for name, expected in service_query_fields() {
		if receipt[name] or { json2.Any('absent') } != json2.Any(expected) {
			return error('service-query receipt differs: ' + name)
		}
	}
	for path, pin in service_query_inputs() {
		if stage.inputs_sha256[path] or { '' } != pin { return error('service-query input differs: ' + path) }
	}
	if stage.format != 1 || stage.original_modules_sha256 != service_query_modules()
		|| stage.preserved_modules_sha256 != service_query_modules() {
		return error('service-query original nine module pins differ')
	}
	verify_service_query_overlay(receipt)!
}

fn service_query_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_service_query_receipt(receipt, stage)!
	path := service_query_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != service_query_base_seal {
		return error('service-query original controller manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != service_query_boot_sha {
		return error('service-query original boot inventory differs')
	}
	return service_query_base + '/boot.img'
}

fn controller_modules() map[string]string {
	mut modules := protected_modules()
	modules['protected-storage-diagnostic.tar'] = 'cb2d855ac82924d6bc0f2221bea0d6cccbf2f9a9d467c455fbf9acba5d594ac3'
	return modules
}

fn controller_fields() map[string]string {
	return {
		'kind': 'vinix-maps-controller-diagnostic-v1'
		'base_root': controller_base
		'base_manifest_sha256': controller_base_seal
		'controller_build_root': controller_root
		'controller_manifest_sha256': controller_seal
		'controller_sha256': controller_pin
		'retained_controller_manifest_sha256': retained_controller_seal
		'framework_manifest_sha256': protected_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn controller_inputs() map[string]string {
	return {
		controller_base + '/sha256.json': controller_base_seal
		controller_root + '/sha256.json': controller_seal
		'/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r6/sha256.json': retained_controller_seal
		'/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json': protected_framework_seal
		'/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1/sha256.json': protected_native_seal
		'/Users/alex/.local/state/vinix/android/current-launch-build-2026-10-26-r13/sha256.json': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	}
}

fn controller_delta() map[string]string {
	return {
		'/opt/vinix-maps-account/bin/maps-account-guest': controller_pin
		'/usr/bin/run-android-calculator': controller_pin
	}
}

// This separate producer changes only the controller and its identical alias.
// The original startup stage and its eight modules remain immutable inputs.
fn verify_controller_receipt(receipt map[string]json2.Any, stage Stage) ! {
	if !digest_valid(controller_seal) || !digest_valid(controller_pin) {
		return error('sealed controller producer pins required')
	}
	for name, expected in controller_fields() {
		actual := receipt[name] or { return error('Maps controller receipt field absent: ' + name) }
		if actual != json2.Any(expected) { return error('Maps controller receipt differs: ' + name) }
	}
	for path, expected in controller_inputs() {
		if stage.inputs_sha256[path] or { '' } != expected {
			return error('Maps controller input differs: ' + path)
		}
	}
	input_delta := receipt['deployment_input_delta'] or { return error('controller deployment input delta absent') }
	top_delta := receipt['deployment_top_level_delta'] or { return error('controller deployment top delta absent') }
	if input_delta != json2.decode[json2.Any](json2.encode(controller_delta()))!
		|| top_delta != json2.decode[json2.Any](json2.encode(['inputs_sha256']))! {
		return error('Maps controller deployment delta differs')
	}
	if stage.format != 1 || stage.original_modules_sha256 != controller_modules()
		|| stage.preserved_modules_sha256 != controller_modules() {
		return error('Maps controller original eight module pins differ')
	}
}

fn controller_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_controller_receipt(receipt, stage)!
	path := controller_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != controller_base_seal {
		return error('Maps controller original startup manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != controller_boot_sha {
		return error('Maps controller original boot inventory differs')
	}
	return controller_base + '/boot.img'
}

fn protected_modules() map[string]string {
	return {
		'headless-service.tar': 'c3466dcfda28617c91242e54f382da22b5b67187fba6ab93d5926c6481d5175c'
		'initramfs.tar': '863944c8ff791dbf94841cb48bbfa0ad8adbab427589bf76a2d20276f5040efb'
		'maps335-diagnostics.tar': '50c1e8aeef5aab5bc6a1a2d7aeb862ff6f674172eec308b827f654a580cabf56'
		'maps350-diagnostics.tar': '27fab286f1d162a997acef67aaac5670118ef6e6eb83969310c0182123a82ead'
		'maps372-diagnostics.tar': '6ab69d2a2c86ce8c7c51543dd596a789cacb7c0880a5f33b2429cf5008cd74d0'
		'qemu-runtime.tar': '1c6988d1f3d3844425f0e8cbb49a878b3a16f2a270b4eb3852c71dfaa8fe200e'
		'maps-account.tar': 'db724d216208abfb1ae873035fb7cbc21d646ba2ff5e5773dd1f18fd05c2ac81'
	}
}

// This diagnostic producer declares a sealed r5 base instead of a direct
// boot.img input. Its separate profile accepts only that exact producer contract.
fn verify_protected_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for name, expected in {
		'kind': 'vinix-protected-storage-maps-diagnostic-v1'
		'base_root': protected_base
		'base_manifest_sha256': protected_base_seal
		'framework_manifest_sha256': protected_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	} {
		actual := receipt[name] or { return error('protected Maps receipt field absent: ' + name) }
		if actual != json2.Any(expected) { return error('protected Maps receipt differs: ' + name) }
	}
	for path, expected in {
		protected_base + '/sha256.json': protected_base_seal
		'/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json': protected_framework_seal
		'/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1/sha256.json': protected_native_seal
	} {
		if stage.inputs_sha256[path] or { '' } != expected {
			return error('protected Maps input differs: ' + path)
		}
	}
	if stage.format != 1 || stage.original_modules_sha256 != protected_modules()
		|| stage.preserved_modules_sha256 != protected_modules() {
		return error('protected Maps original seven module pins differ')
	}
}

fn protected_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_protected_receipt(receipt, stage)!
	path := protected_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != protected_base_seal {
		return error('protected Maps original r5 manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != protected_boot_sha {
		return error('protected Maps original boot inventory differs')
	}
	return protected_base + '/boot.img'
}

struct Stage {
	format                   int
	inputs_sha256            map[string]string
	original_modules_sha256  map[string]string
	preserved_modules_sha256 map[string]string
	overlay_sha256           string
	limine_before_sha256     string
	limine_after_sha256      string
	staged_boot_sha256       string
	staged_efivars_sha256    string
}

struct Build {
	format                    int
	source_revision           string
	architecture              string
	kernel_path               string
	kernel_sha256             string
	kernel_unix_source_sha256 string
	generated_c_sha256        string
	compiler_sha256           string
	guest_executed            bool
	link_seed                 int
}

struct Inventory {
	files map[string]string
	links map[string]string
}

struct Config {
	kernel  string
	modules []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &digest }) != 1 { return error('SHA256 initialization') }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) != 1 {
			return error('SHA256 update')
		}
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) != 1 {
		return error('SHA256 finalization')
	}
	return result[..].hex()
}

fn hash_self_test(root string) ! {
	path := root + '/sha256-input'
	defer { os.rm(path) or {} }
	for input, expected in {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	} {
		os.write_file(path, input)!
		assert hash(path)! == expected
	}
	mut bytes := []u8{len: 2 * 1024 * 1024 + 65}
	for i in 0 .. bytes.len { bytes[i] = u8((i * 29 + 11) % 251) }
	for size in [55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1, bytes.len] {
		os.write_file_array(path, bytes[..size])!
		assert hash(path)! == sha256.sum(bytes[..size]).hex()
	}
	println('HOST-SHA256 SELF-TEST PASS known-vectors block-padding streaming-boundaries V-reference')
}

fn digest_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn regular(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular {
		return error('regular non-symlink file required: ' + path)
	}
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\r\n\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn member(line string, key string) !string {
	prefix := key + ': boot():/boot/'
	if !line.starts_with(prefix) { return error('unsupported Limine path: ' + line) }
	name := line[prefix.len..]
	if name == '' || name in ['.', '..'] || name.len > 255
		|| !name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`]) {
		return error('literal FAT basename required')
	}
	return name
}

fn configure(text string) !Config {
	if text == '' || text.contains_any('\x00\r') {
		return error('expected LF-delimited Limine configuration')
	}
	mut entries := 0
	mut kernel := ''
	mut modules := []string{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('/') || line.starts_with(':') { entries++ }
		if line.starts_with('kernel_path:') {
			if entries != 1 || kernel != '' { return error('ambiguous kernel entry') }
			kernel = member(line, 'kernel_path')!
		}
		if line.starts_with('module_path:') {
			if entries != 1 { return error('ambiguous module entry') }
			name := member(line, 'module_path')!
			if name in modules || !name.ends_with('.tar') {
				return error('duplicate or non-tar module')
			}
			modules << name
		}
	}
	if entries != 1 || kernel != 'vinix' || modules.len == 0 {
		return error('one Vinix kernel entry required')
	}
	return Config{kernel, modules}
}

fn execute(root string, label string, argv []string) !string {
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline { return error('command deadline: ' + label) }
		time.sleep(10 * time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
	}
	child.wait()
	finished = true
	os.write_file(root + '/kernel-patch-commands/' + label + '.json', json2.encode({
		'argv':      json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout':    json2.Any(stdout)
		'stderr':    json2.Any(stderr)
	},
		prettify: true
	))!
	if child.code != 0 { return error(label + ' failed: ' + stderr) }
	return stdout
}

fn fat_hash(root string, label string, image string, name string) !string {
	result := modulestream.hash_member(image, name, root + '/kernel-patch-commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 || !digest_valid(result.sha256) {
		return error('FAT hash stream failed: ' + name)
	}
	return result.sha256
}

fn unlaunched(root string) ! {
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('fresh unlaunched diagnostic stage required: ' + name)
		}
	}
}

fn verify_inventory(root string, inventory Inventory) ! {
	if inventory.files.len == 0 { return error('empty frozen build inventory') }
	for name, expected in inventory.files {
		if !relative(name) || !digest_valid(expected) {
			return error('unsafe frozen build inventory member')
		}
		path := root + '/' + name
		regular(path)!
		if !os.real_path(path).starts_with(root + '/') || hash(path)! != expected {
			return error('frozen build file differs: ' + name)
		}
	}
	for name, target in inventory.links {
		if !relative(name) || target == '' || target.contains_any('\x00\r\n')
			|| !os.is_link(root + '/' + name) || os.readlink(root + '/' + name)! != target {
			return error('frozen build symlink differs: ' + name)
		}
	}
}

fn validate_build(root string, receipt_sha string) !Build {
	for name in ['build.json', 'input-pins.json', 'sha256.json'] { regular(root + '/' + name)! }
	if !digest_valid(receipt_sha) || hash(root + '/build.json')! != receipt_sha {
		return error('kernel build receipt pin differs')
	}
	build := json2.decode[Build](os.read_file(root + '/build.json')!)!
	if build.format != 1 || build.architecture != 'aarch64' || build.guest_executed
		|| build.source_revision.len != 40 || !build.source_revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| !digest_valid(build.kernel_sha256) || !digest_valid(build.kernel_unix_source_sha256)
		|| !digest_valid(build.generated_c_sha256) || !digest_valid(build.compiler_sha256)
		|| build.link_seed != 20261026 || !os.is_abs_path(build.kernel_path)
		|| !os.real_path(build.kernel_path).starts_with(root + '/') {
		return error('unsupported or incomplete frozen kernel build receipt')
	}
	regular(build.kernel_path)!
	if hash(build.kernel_path)! != build.kernel_sha256 {
		return error('frozen kernel hash differs')
	}
	mut file := os.open(build.kernel_path)!
	mut header := []u8{len: 20}
	n := file.read(mut header)!
	file.close()
	if n != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| header[16..20] != [u8(2), 0, 183, 0] {
		return error('AArch64 ELF64 executable kernel required')
	}
	inventory := json2.decode[Inventory](os.read_file(root + '/sha256.json')!)!
	verify_inventory(root, inventory)!
	kernel_relative := os.real_path(build.kernel_path)[root.len + 1..]
	if inventory.files[kernel_relative] or { '' } != build.kernel_sha256 {
		return error('frozen kernel is absent from build inventory')
	}
	pins := json2.decode[map[string]json2.Any](os.read_file(root + '/input-pins.json')!)!
	kernel_pins := json2.decode[map[string]string](json2.encode(pins['kernel']!))!
	if kernel_pins['kernel/socket/unix/unix.v'] or { '' } != build.kernel_unix_source_sha256 {
		return error('Unix socket source pin differs from kernel inputs')
	}
	mut unix_source_present := false
	for name, expected in inventory.files {
		if (name == 'kernel/socket/unix/unix.v' || name.ends_with('/kernel/socket/unix/unix.v'))
			&& expected == build.kernel_unix_source_sha256 {
			unix_source_present = true
		}
	}
	if !unix_source_present {
		return error('frozen Unix socket source is absent from build inventory')
	}
	return build
}

fn verify_modules(profile Profile, before Config, after Config) ! {
	mut expected := before.modules.clone()
	expected << profile.overlay
	if (profile.modules.len > 0 && before.modules != profile.modules)
		|| after.kernel != before.kernel || after.modules != expected {
		return error('stage modules differ from audited ' + profile.name + ' profile')
	}
}

fn patch(root string, build_root string, receipt_sha string, profile Profile) ! {
	baseline_pin := profile.baseline_sha
	unlaunched(root)!
	for name in ['kernel-patch.json', 'kernel-patch-request.json', 'kernel-patch-commands',
		'kernel-patch-build', 'stage-before-kernel.json', 'kernel-patch-source.v', 'kernel-patch-tool'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('kernel patch is once-only: ' + name)
		}
	}
	for name in ['stage.json', 'boot.img', 'efivars.fd', 'limine-before.conf', 'limine-after.conf'] {
		regular(root + '/' + name)!
	}
	stage_text := os.read_file(root + '/stage.json')!
	stage := json2.decode[Stage](stage_text)!
	mut stage_map := json2.decode[map[string]json2.Any](stage_text)!
	if 'kernel_patch' in stage_map { return error('stage already declares a kernel patch') }
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(root + '/limine-before.conf')! != stage.limine_before_sha256
		|| hash(root + '/limine-after.conf')! != stage.limine_after_sha256 {
		return error('fresh stage media or configuration pin differs')
	}
	mut baseline := ''
	if profile.name == 'protected-storage-maps' {
		baseline = protected_baseline(stage_map, stage)!
	} else if profile.name == 'maps-controller' {
		baseline = controller_baseline(stage_map, stage)!
	} else if profile.name == 'maps-service-query' {
		baseline = service_query_baseline(stage_map, stage)!
	} else if profile.name == 'maps-controller-memory' {
		baseline = controller_memory_baseline(stage_map, stage)!
	} else if profile.name == 'maps-direct-boot' {
		baseline = direct_boot_baseline(stage_map, stage)!
	} else if profile.name == 'maps-context-storage' {
		baseline = context_storage_baseline(stage_map, stage)!
	} else if profile.name == 'maps-broadcast-result' {
		baseline = broadcast_result_baseline(stage_map, stage)!
	} else if profile.name == 'maps-onboarding-trace' {
		baseline = onboarding_trace_baseline(stage_map, stage)!
	} else if profile.name == 'maps-native-onboarding-trace' {
		baseline = native_onboarding_trace_baseline(stage_map, stage)!
	} else if profile.name == 'maps-onboarding-framework' {
		baseline = onboarding_framework_baseline(stage_map, stage)!
	} else if profile.name == 'maps-native-heartbeat' {
		baseline = native_heartbeat_baseline(stage_map, stage)!
	} else if profile.name == 'maps-browser-poll' {
		baseline = browser_poll_baseline(stage_map, stage)!
	} else if profile.name == 'maps-account-pump' {
		baseline = account_pump_baseline(stage_map, stage)!
	} else if profile.name == 'maps-application-restrictions' {
		baseline = application_restrictions_baseline(stage_map, stage)!
	} else if profile.name == 'maps-account-handoff' {
		baseline = account_handoff_baseline(stage_map, stage)!
	} else if profile.name == 'maps-auth-exception' {
		baseline = auth_exception_baseline(stage_map, stage)!
	} else if profile.name == 'maps-auth-worker' {
		baseline = auth_worker_baseline(stage_map, stage)!
	} else {
		for path, expected in stage.inputs_sha256 {
			if os.file_name(path) == 'boot.img' && expected == baseline_pin {
				if baseline != '' { return error('ambiguous baseline boot input') }
				baseline = path
			}
		}
	}
	if baseline == '' || baseline == root + '/boot.img' {
		return error('audited original baseline boot input required')
	}
	regular(baseline)!
	if hash(baseline)! != baseline_pin { return error('baseline boot bytes differ') }
	build := validate_build(build_root, receipt_sha)!
	before_text := os.read_file(root + '/limine-before.conf')!
	after_text := os.read_file(root + '/limine-after.conf')!
	before := configure(before_text)!
	after := configure(after_text)!
	verify_modules(profile, before, after)!
	if stage.original_modules_sha256.len != before.modules.len
		|| stage.original_modules_sha256 != stage.preserved_modules_sha256
		|| !digest_valid(stage.overlay_sha256) {
		return error('stage baseline/module manifest differs')
	}
	for name in before.modules {
		if !digest_valid(stage.original_modules_sha256[name] or { '' }) {
			return error('module manifest member absent')
		}
	}
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mtype := os.find_abs_path_of_executable('mtype')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	os.mkdir(root + '/kernel-patch-commands')!
	for line in execute(root, 'process-check', ['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains('qemu-system-') && line.contains(root + '/') {
			return error('QEMU references this stage; refusing kernel replacement')
		}
	}
	if execute(root, 'baseline-limine', [mtype, '-i', baseline, '::/boot/limine.conf'])! != before_text
		|| execute(root, 'stage-limine-before', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text {
		return error('FAT Limine configuration differs')
	}
	old_kernel := fat_hash(root, 'baseline-kernel', baseline, before.kernel)!
	if fat_hash(root, 'staged-kernel-before', root + '/boot.img', after.kernel)! != old_kernel {
		return error('fresh staged kernel differs from original baseline')
	}
	if old_kernel == build.kernel_sha256 {
		return error('replacement kernel equals baseline kernel')
	}
	mut preserved := map[string]string{}
	for name in before.modules {
		expected := stage.original_modules_sha256[name]!
		if fat_hash(root, 'baseline-' + name, baseline, name)! != expected
			|| fat_hash(root, 'before-' + name, root + '/boot.img', name)! != expected {
			return error('original module differs before patch: ' + name)
		}
		preserved[name] = expected
	}
	if fat_hash(root, 'before-' + profile.overlay, root + '/boot.img', profile.overlay)! != stage.overlay_sha256 {
		return error('diagnostic payload differs before patch')
	}
	preserved[profile.overlay] = stage.overlay_sha256
	os.mkdir(root + '/kernel-patch-build')!
	mut build_receipts := map[string]string{}
	for name in ['build.json', 'input-pins.json', 'sha256.json'] {
		os.cp(build_root + '/' + name, root + '/kernel-patch-build/' + name)!
		build_receipts[name] = hash(root + '/kernel-patch-build/' + name)!
	}
	os.write_file(root + '/stage-before-kernel.json', stage_text)!
	os.write_file(root + '/kernel-patch-source.v', source)!
	os.cp(os.executable(), root + '/kernel-patch-tool')!
	os.write_file(root + '/kernel-patch-request.json', json2.encode({
		'profile':                     json2.Any(profile.name)
		'created_utc':                 json2.Any(time.utc().str())
		'original_stage_sha256':       json2.Any(sha256.sum(stage_text.bytes()).hex())
		'baseline_boot_sha256':        json2.Any(baseline_pin)
		'kernel_build_receipt_sha256': json2.Any(receipt_sha)
		'original_kernel_sha256':      json2.Any(old_kernel)
		'replacement_kernel_sha256':   json2.Any(build.kernel_sha256)
	}, prettify: true))!
	unlaunched(root)!
	if hash(build_root + '/build.json')! != receipt_sha || hash(build.kernel_path)! != build.kernel_sha256 {
		return error('kernel build changed before installation')
	}
	execute(root, 'install-kernel', [mcopy, '-o', '-i', root + '/boot.img', build.kernel_path,
		'::/boot/' + after.kernel])!
	if fat_hash(root, 'staged-kernel-after', root + '/boot.img', after.kernel)! != build.kernel_sha256 {
		return error('installed kernel readback differs')
	}
	for name, expected in preserved {
		if fat_hash(root, 'after-' + name, root + '/boot.img', name)! != expected {
			return error('module changed during kernel replacement: ' + name)
		}
	}
	if execute(root, 'stage-limine-after', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(baseline)! != baseline_pin || hash(build.kernel_path)! != build.kernel_sha256
		|| os.read_file(root + '/stage.json')! != stage_text {
		return error('preserved input changed during replacement')
	}
	for name, expected in build_receipts {
		if hash(build_root + '/' + name)! != expected {
			return error('frozen build receipt changed')
		}
	}
	unlaunched(root)!
	provenance := json2.decode[json2.Any](json2.encode({
		'format':                       json2.Any(1)
		'scope':                        json2.Any('Fresh diagnostic stage only; prepared payload preserved byte-for-byte; no guest execution or Google login evidence.')
		'profile':                      json2.Any(profile.name)
		'created_utc':                  json2.Any(time.utc().str())
		'baseline_boot_path':           json2.Any(baseline)
		'baseline_boot_sha256':         json2.Any(baseline_pin)
		'original_stage_sha256':        json2.Any(sha256.sum(stage_text.bytes()).hex())
		'original_kernel_sha256':       json2.Any(old_kernel)
		'kernel_member':                json2.Any(after.kernel)
		'kernel_sha256':                json2.Any(build.kernel_sha256)
		'kernel_build_root':            json2.Any(build_root)
		'kernel_build_receipt_sha256':  json2.Any(receipt_sha)
		'kernel_build_receipts_sha256': json2.decode[json2.Any](json2.encode(build_receipts))!
		'kernel_source_revision':       json2.Any(build.source_revision)
		'kernel_unix_source_sha256':    json2.Any(build.kernel_unix_source_sha256)
		'preserved_modules_sha256':     json2.decode[json2.Any](json2.encode(preserved))!
		'limine_sha256':                json2.Any(stage.limine_after_sha256)
		'efivars_sha256':               json2.Any(stage.staged_efivars_sha256)
		'staged_boot_sha256':           json2.Any(hash(root + '/boot.img')!)
		'tool_sha256':                  json2.Any(hash(root + '/kernel-patch-tool')!)
		'tool_source_sha256':           json2.Any(hash(root + '/kernel-patch-source.v')!)
		'mcopy_sha256':                 json2.Any(hash(mcopy)!)
		'mtype_sha256':                 json2.Any(hash(mtype)!)
	}, prettify: true))!
	os.write_file(root + '/kernel-patch.json', json2.encode(provenance, prettify: true) + '\n')!
	stage_map['kernel_patch'] = provenance
	stage_map['kernel_patch_receipt_sha256'] = json2.Any(hash(root + '/kernel-patch.json')!)
	stage_map['staged_boot_sha256'] = json2.Any(hash(root + '/boot.img')!)
	os.write_file(root + '/stage.json', json2.encode(stage_map, prettify: true) + '\n')!
	println('BROWSER-KERNEL-PATCH PASS ' + root + '/kernel-patch.json')
}

fn external(path string) !string {
	abs := os.abs_path(path)
	root := os.real_path(path)
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if abs != root || !os.is_dir(root) || root == repo || root.starts_with(repo + '/')
		|| root.contains_any('\x00\r\n') {
		return error('canonical external stage/build directory required')
	}
	return root
}

fn fat_self_test(root string, overlay string, module_names []string) ! {
	os.mkdir(root)!
	os.mkdir(root + '/kernel-patch-commands')!
	os.mkdir(root + '/baseline')!
	os.mkdir(root + '/stage')!
	os.mkdir_all(root + '/build/kernel/socket/unix')!
	baseline := root + '/baseline/boot.img'
	mut config := '/Vinix\n kernel_path: boot():/boot/vinix\n'
	for name in module_names { config += ' module_path: boot():/boot/' + name + '\n' }
	updated := config + ' module_path: boot():/boot/' + overlay + '\n'
	os.write_file(root + '/config', config)!
	os.write_file(root + '/old-kernel', 'old baseline kernel')!
	os.write_file(root + '/runtime', 'original module\x00exact bytes')!
	os.write_file(root + '/overlay', 'unchanged r8 browser overlay\x00exact bytes')!
	mcopy := os.find_abs_path_of_executable('mcopy')!
	execute(root, 'fixture-format', [os.find_abs_path_of_executable('mformat')!, '-i', baseline,
		'-C', '-f', '1440', '::'])!
	execute(root, 'fixture-mkdir', [os.find_abs_path_of_executable('mmd')!, '-i', baseline, '::/boot'])!
	for pair in [['config', 'limine.conf'], ['old-kernel', 'vinix']] {
		execute(root, 'fixture-install-' + pair[0], [mcopy, '-i', baseline, root + '/' + pair[0],
			'::/boot/' + pair[1]])!
	}
	for name in module_names {
		execute(root, 'fixture-install-' + name, [mcopy, '-i', baseline, root + '/runtime',
			'::/boot/' + name])!
	}
	os.cp(baseline, root + '/stage/boot.img')!
	os.write_file(root + '/config-after', updated)!
	execute(root, 'fixture-update-limine', [mcopy, '-o', '-i', root + '/stage/boot.img',
		root + '/config-after', '::/boot/limine.conf'])!
	execute(root, 'fixture-install-overlay', [mcopy, '-i', root + '/stage/boot.img', root + '/overlay',
		'::/boot/' + overlay])!
	os.write_file(root + '/stage/efivars.fd', 'unchanged firmware state')!
	os.write_file(root + '/stage/limine-before.conf', config)!
	os.write_file(root + '/stage/limine-after.conf', updated)!
	mut original_modules := map[string]string{}
	for name in module_names { original_modules[name] = hash(root + '/runtime')! }
	stage := Stage{
		format:                   1
		inputs_sha256:            {
			baseline: hash(baseline)!
		}
		original_modules_sha256:  original_modules
		preserved_modules_sha256: original_modules
		overlay_sha256:           hash(root + '/overlay')!
		limine_before_sha256:     hash(root + '/stage/limine-before.conf')!
		limine_after_sha256:      hash(root + '/stage/limine-after.conf')!
		staged_boot_sha256:       hash(root + '/stage/boot.img')!
		staged_efivars_sha256:    hash(root + '/stage/efivars.fd')!
	}
	stage_text := json2.encode(stage, prettify: true)
	os.write_file(root + '/stage/stage.json', stage_text)!
	mut kernel := []u8{len: 64}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { kernel[index] = value }
	kernel[16] = 2
	kernel[18] = 183
	os.write_file_array(root + '/build/vinix', kernel)!
	os.write_file(root + '/build/kernel/socket/unix/unix.v', 'frozen Unix socket source')!
	kernel_hash := hash(root + '/build/vinix')!
	unix_hash := hash(root + '/build/kernel/socket/unix/unix.v')!
	os.write_file(root + '/build/build.json', json2.encode(Build{
		format:                    1
		source_revision:           'a'.repeat(40)
		architecture:              'aarch64'
		kernel_path:               root + '/build/vinix'
		kernel_sha256:             kernel_hash
		kernel_unix_source_sha256: unix_hash
		generated_c_sha256:        'b'.repeat(64)
		compiler_sha256:           'c'.repeat(64)
		link_seed:                 20261026
	}))!
	os.write_file(root + '/build/input-pins.json', json2.encode({
		'kernel': {
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	os.write_file(root + '/build/sha256.json', json2.encode(Inventory{
		files: {
			'vinix':                     kernel_hash
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	receipt_sha := hash(root + '/build/build.json')!
	profile := Profile{'fixture', hash(baseline)!, overlay, module_names}
	if _ := patch(root + '/stage', root + '/build', '0'.repeat(64), profile) {
		return error('wrong build receipt pin accepted')
	}
	if os.read_file(root + '/stage/stage.json')! != stage_text
		|| hash(root + '/stage/boot.img')! != stage.staged_boot_sha256 {
		return error('rejected kernel patch changed fixture media or receipt')
	}
	patch(root + '/stage', root + '/build', receipt_sha, profile)!
	updated_stage := json2.decode[Stage](os.read_file(root + '/stage/stage.json')!)!
	if updated_stage.staged_boot_sha256 == stage.staged_boot_sha256
		|| updated_stage.inputs_sha256 != stage.inputs_sha256
		|| updated_stage.original_modules_sha256 != stage.original_modules_sha256
		|| updated_stage.preserved_modules_sha256 != stage.preserved_modules_sha256
		|| updated_stage.overlay_sha256 != stage.overlay_sha256
		|| updated_stage.staged_efivars_sha256 != stage.staged_efivars_sha256
		|| os.read_file(root + '/stage/stage-before-kernel.json')! != stage_text
		|| !os.is_file(root + '/stage/kernel-patch.json') {
		return error('successful kernel patch fixture preservation or provenance differs')
	}
	if _ := patch(root + '/stage', root + '/build', receipt_sha, profile) {
		return error('second patch of same stage accepted')
	}
	println('BROWSER-KERNEL-PATCH FAT-SELF-TEST PASS pinned build rejection exact kernel readback baseline modules overlay firmware receipts once-only')
}

fn protected_receipt_fixture() map[string]json2.Any {
	return {
		'kind': json2.Any('vinix-protected-storage-maps-diagnostic-v1')
		'base_root': json2.Any(protected_base)
		'base_manifest_sha256': json2.Any(protected_base_seal)
		'framework_manifest_sha256': json2.Any(protected_framework_seal)
		'native_manifest_sha256': json2.Any(protected_native_seal)
		'retained_launch_manifest_sha256': json2.Any('920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be')
	}
}

fn protected_profile_self_test() ! {
	profile := protected_maps_profile()
	assert profile.baseline_sha == protected_boot_sha
	assert profile.modules.len == 7 && profile.modules.last() == 'maps-account.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..7].clone()}, Config{'other', modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe protected Maps modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', maps_profile().modules},
		Config{'vinix', modules}) { return error('six-module protected Maps baseline accepted') }
	stage := Stage{
		format: 1
		inputs_sha256: {
			protected_base + '/sha256.json': protected_base_seal
			'/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json': protected_framework_seal
			'/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1/sha256.json': protected_native_seal
		}
		original_modules_sha256: protected_modules()
		preserved_modules_sha256: protected_modules()
	}
	receipt := protected_receipt_fixture()
	verify_protected_receipt(receipt, stage)!
	old_native_seal := 'bd0e3902130f74877abaf269301377c7b5d2cbfe9e7732508838d84ec863d19d'
	native_path := '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1/sha256.json'
	old_native_path := '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-binding-r2/sha256.json'
	mut old_receipt := protected_receipt_fixture()
	old_receipt['native_manifest_sha256'] = json2.Any(old_native_seal)
	if _ := verify_protected_receipt(old_receipt, stage) {
		return error('obsolete protected native receipt accepted')
	}
	for pin in [old_native_seal, protected_native_seal] {
		mut old_inputs := stage.inputs_sha256.clone()
		old_inputs.delete(native_path)
		old_inputs[old_native_path] = pin
		if _ := verify_protected_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
			return error('obsolete protected native input path accepted')
		}
	}
	mut old_pin_inputs := stage.inputs_sha256.clone()
	old_pin_inputs[native_path] = old_native_seal
	if _ := verify_protected_receipt(receipt, Stage{...stage, inputs_sha256: old_pin_inputs}) {
		return error('obsolete protected native input pin accepted')
	}
	for name in receipt.keys() {
		mut bad := protected_receipt_fixture()
		bad[name] = json2.Any('wrong')
		if _ := verify_protected_receipt(bad, stage) { return error('changed protected receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_protected_receipt(bad, stage) { return error('missing protected receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut bad_inputs := stage.inputs_sha256.clone()
		bad_inputs[path] = '0'.repeat(64)
		if _ := verify_protected_receipt(receipt, Stage{...stage, inputs_sha256: bad_inputs}) {
			return error('changed protected input pin accepted')
		}
	}
	mut bad_modules := protected_modules()
	bad_modules['maps-account.tar'] = '0'.repeat(64)
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: bad_modules},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_protected_receipt(receipt, bad) { return error('changed protected module contract accepted') }
	}
	println('PROTECTED-STORAGE-MAPS KERNEL-PROFILE-SELF-TEST PASS exact receipt base framework native launch inputs seven modules obsolete native rejection')
}

fn controller_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, expected in controller_fields() { receipt[name] = json2.Any(expected) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(controller_delta()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	return receipt
}

fn controller_profile_self_test() ! {
	profile := controller_profile()
	assert profile.baseline_sha == controller_boot_sha
	assert profile.modules.len == 8 && profile.modules.last() == 'protected-storage-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..8].clone()}, Config{'other', modules},
		Config{'vinix', protected_maps_profile().modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe controller modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', protected_maps_profile().modules}, Config{'vinix', modules}) {
		return error('seven-module controller baseline accepted')
	}
	stage := Stage{
		format: 1
		inputs_sha256: controller_inputs()
		original_modules_sha256: controller_modules()
		preserved_modules_sha256: controller_modules()
	}
	receipt := controller_receipt_fixture()!
	verify_controller_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := controller_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_controller_receipt(bad, stage) { return error('changed controller receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_controller_receipt(bad, stage) { return error('missing controller receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut bad_inputs := stage.inputs_sha256.clone()
		bad_inputs[path] = '0'.repeat(64)
		if _ := verify_controller_receipt(receipt, Stage{...stage, inputs_sha256: bad_inputs}) {
			return error('changed controller input pin accepted')
		}
		bad_inputs.delete(path)
		if _ := verify_controller_receipt(receipt, Stage{...stage, inputs_sha256: bad_inputs}) {
			return error('missing controller input accepted')
		}
	}
	mut obsolete_receipt := controller_receipt_fixture()!
	obsolete_receipt['controller_manifest_sha256'] = json2.Any(retained_controller_seal)
	if _ := verify_controller_receipt(obsolete_receipt, stage) { return error('obsolete controller receipt accepted') }
	mut old_inputs := stage.inputs_sha256.clone()
	old_inputs.delete(controller_root + '/sha256.json')
	old_inputs['/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r6/sha256.json'] = controller_seal
	if _ := verify_controller_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
		return error('old controller path with new seal accepted')
	}
	for name in controller_modules().keys() {
		mut bad_modules := controller_modules()
		bad_modules[name] = '0'.repeat(64)
		for bad in [Stage{...stage, original_modules_sha256: bad_modules},
			Stage{...stage, preserved_modules_sha256: bad_modules}] {
			if _ := verify_controller_receipt(receipt, bad) { return error('changed controller module accepted') }
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: protected_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_controller_receipt(receipt, bad) { return error('changed controller module contract accepted') }
	}
	for deltas in [map[string]string{}, {'/opt/vinix-maps-account/bin/maps-account-guest': controller_pin},
		{'/opt/vinix-maps-account/bin/maps-account-guest': controller_pin, '/usr/bin/run-android-calculator': '0'.repeat(64)},
		{'/opt/vinix-maps-account/bin/maps-account-guest': controller_pin, '/usr/bin/run-android-calculator': controller_pin, '/extra': controller_pin}] {
		mut bad := controller_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(deltas))!
		if _ := verify_controller_receipt(bad, stage) { return error('unsafe controller deployment input delta accepted') }
	}
	for deltas in [ []string{}, ['inputs_sha256', 'native_manifest_sha256'], ['inputs_sha256', 'inputs_sha256'] ] {
		mut bad := controller_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(deltas))!
		if _ := verify_controller_receipt(bad, stage) { return error('unsafe controller deployment top delta accepted') }
	}
	if _ := verify_protected_receipt(receipt, stage) { return error('controller receipt accepted by protected profile') }
	if _ := verify_controller_receipt(protected_receipt_fixture(), stage) { return error('protected receipt accepted by controller profile') }
	println('MAPS-CONTROLLER KERNEL-PROFILE-SELF-TEST PASS exact startup base controller receipt inputs deployment delta eight modules historical profile rejection')
}

fn service_query_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in service_query_known_delta() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_headless + '/guest-inputs.json', kind: 'regular', sha256: 'b'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn service_query_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in service_query_fields() { receipt[name] = json2.Any(value) }
	mut delta := service_query_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'b'.repeat(64)
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: service_query_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(service_query_entries_fixture()))!
	return receipt
}

fn service_query_profile_self_test() ! {
	profile := service_query_profile()
	assert profile.baseline_sha == service_query_boot_sha
	assert profile.modules.len == 9 && profile.modules.last() == 'maps-controller-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..9].clone()}, Config{'other', modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe service-query modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', controller_profile().modules}, Config{'vinix', modules}) {
		return error('eight-module service-query baseline accepted')
	}
	stage := Stage{format: 1, inputs_sha256: service_query_inputs(),
		original_modules_sha256: service_query_modules(), preserved_modules_sha256: service_query_modules()}
	receipt := service_query_receipt_fixture()!
	verify_service_query_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := service_query_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_service_query_receipt(bad, stage) { return error('changed service-query receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_service_query_receipt(bad, stage) { return error('missing service-query receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_service_query_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('changed service-query input pin accepted')
		}
		inputs.delete(path)
		if _ := verify_service_query_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('missing service-query input accepted')
		}
	}
	mut old_inputs := stage.inputs_sha256.clone()
	old_inputs.delete(service_query_framework + '/sha256.json')
	old_inputs['/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json'] = service_query_framework_seal
	if _ := verify_service_query_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
		return error('old framework path with service-query seal accepted')
	}
	mut old := service_query_receipt_fixture()!
	old['framework_manifest_sha256'] = json2.Any(protected_framework_seal)
	if _ := verify_service_query_receipt(old, stage) { return error('retained framework accepted') }
	for name in service_query_modules().keys() {
		mut pins := service_query_modules()
		pins[name] = '0'.repeat(64)
		for bad in [Stage{...stage, original_modules_sha256: pins}, Stage{...stage, preserved_modules_sha256: pins}] {
			if _ := verify_service_query_receipt(receipt, bad) { return error('changed service-query module accepted') }
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: controller_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_service_query_receipt(receipt, bad) { return error('changed service-query module contract accepted') }
	}
	mut delta := service_query_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'b'.repeat(64)
	for path in delta.keys() {
		mut bad_delta := delta.clone()
		bad_delta.delete(path)
		mut bad := service_query_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(bad_delta))!
		if _ := verify_service_query_receipt(bad, stage) { return error('partial service-query delta accepted') }
		bad_delta = delta.clone()
		bad_delta[path] = '0'.repeat(64)
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(bad_delta))!
		if _ := verify_service_query_receipt(bad, stage) { return error('changed service-query delta accepted') }
	}
	delta['/extra'] = 'd'.repeat(64)
	mut extra := service_query_receipt_fixture()!
	extra['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
	if _ := verify_service_query_receipt(extra, stage) { return error('extra service-query input accepted') }
	for name, alternatives in {
		'headless_top_level_delta': [ []string{}, ['inputs_sha256', 'extra'], ['inputs_sha256', 'inputs_sha256'] ]
		'deployment_top_level_delta': [ []string{}, ['inputs_sha256'], ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256'] ]
	} {
		for alternative in alternatives {
			mut bad := service_query_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(alternative))!
			if _ := verify_service_query_receipt(bad, stage) { return error('unsafe service-query top delta accepted') }
		}
	}
	for bad_delta in [map[string]string{}, {'/' + service_query_jar_path: '0'.repeat(64)},
		{'/' + service_query_jar_path: service_query_jar, '/extra': service_query_jar}] {
		mut bad := service_query_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(bad_delta))!
		if _ := verify_service_query_receipt(bad, stage) { return error('unsafe service-query headless delta accepted') }
	}
	entries := service_query_entries_fixture()
	for index, entry in entries {
		mut bad_entries := entries.clone()
		bad_entries[index] = ServiceQueryEntry{...entry, kind: 'symlink'}
		mut bad := service_query_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
		if _ := verify_service_query_receipt(bad, stage) { return error('service-query symlink accepted') }
		bad_entries[index] = ServiceQueryEntry{...entry, mode: 0o777}
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
		if _ := verify_service_query_receipt(bad, stage) { return error('unsafe service-query mode accepted') }
		if entry.kind == 'regular' && entry.name != service_query_deployment {
			bad_entries[index] = ServiceQueryEntry{...entry, sha256: '0'.repeat(64)}
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
			if _ := verify_service_query_receipt(bad, stage) { return error('changed service-query inventory digest accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/extra', kind: 'regular', sha256: 'd'.repeat(64), mode: 0o644},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut bad_entries := entries.clone()
		bad_entries << addition
		mut bad := service_query_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
		if _ := verify_service_query_receipt(bad, stage) { return error('extra or duplicate service-query inode accepted') }
	}
	mut removed := service_query_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_service_query_receipt(removed, stage) { return error('missing service-query file accepted') }
	if _ := verify_controller_receipt(receipt, stage) { return error('service-query receipt accepted by controller profile') }
	if _ := verify_service_query_receipt(controller_receipt_fixture()!, stage) { return error('controller receipt accepted by service-query profile') }
	println('MAPS-SERVICE-QUERY KERNEL-PROFILE-SELF-TEST PASS exact controller base framework inputs five-path deployment one-path headless delta six-file inventory nine modules historical profile rejection')
}

fn controller_memory_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in controller_memory_delta() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o755}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn controller_memory_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in controller_memory_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(controller_memory_delta()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(controller_memory_entries_fixture()))!
	return receipt
}

fn controller_memory_profile_self_test() ! {
	profile := controller_memory_profile()
	assert profile.baseline_sha == controller_memory_boot_sha
	assert profile.modules.len == 10 && profile.modules.last() == 'maps-service-query-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..10].clone()}, Config{'other', modules},
		Config{'vinix', service_query_profile().modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe controller memory modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', service_query_profile().modules}, Config{'vinix', modules}) {
		return error('nine-module controller memory baseline accepted')
	}
	stage := Stage{format: 1, inputs_sha256: controller_memory_inputs(),
		original_modules_sha256: controller_memory_modules(), preserved_modules_sha256: controller_memory_modules()}
	receipt := controller_memory_receipt_fixture()!
	verify_controller_memory_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := controller_memory_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_controller_memory_receipt(bad, stage) { return error('changed controller memory receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_controller_memory_receipt(bad, stage) { return error('missing controller memory receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_controller_memory_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('changed controller memory input pin accepted')
		}
		inputs.delete(path)
		if _ := verify_controller_memory_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('missing controller memory input accepted')
		}
	}
	mut old := controller_memory_receipt_fixture()!
	old['controller_manifest_sha256'] = json2.Any(controller_seal)
	if _ := verify_controller_memory_receipt(old, stage) { return error('old controller memory receipt accepted') }
	mut old_inputs := stage.inputs_sha256.clone()
	old_inputs.delete(controller_memory_root + '/sha256.json')
	old_inputs[controller_root + '/sha256.json'] = controller_memory_seal
	if _ := verify_controller_memory_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
		return error('old controller path with memory seal accepted')
	}
	mut old_seal := stage.inputs_sha256.clone()
	old_seal[controller_memory_root + '/sha256.json'] = controller_seal
	if _ := verify_controller_memory_receipt(receipt, Stage{...stage, inputs_sha256: old_seal}) {
		return error('memory controller path with old seal accepted')
	}
	for name in controller_memory_modules().keys() {
		mut pins := controller_memory_modules()
		pins[name] = '0'.repeat(64)
		for bad in [Stage{...stage, original_modules_sha256: pins}, Stage{...stage, preserved_modules_sha256: pins}] {
			if _ := verify_controller_memory_receipt(receipt, bad) { return error('changed controller memory module accepted') }
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: service_query_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_controller_memory_receipt(receipt, bad) { return error('changed controller memory module contract accepted') }
	}
	for delta in [map[string]string{}, {'/opt/vinix-maps-account/bin/maps-account-guest': controller_memory_pin},
		{'/opt/vinix-maps-account/bin/maps-account-guest': controller_memory_pin, '/usr/bin/run-android-calculator': controller_pin},
		{'/opt/vinix-maps-account/bin/maps-account-guest': controller_memory_pin, '/usr/bin/run-android-calculator': controller_memory_pin, '/extra': controller_memory_pin}] {
		mut bad := controller_memory_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		if _ := verify_controller_memory_receipt(bad, stage) { return error('unsafe controller memory input delta accepted') }
	}
	for delta in [[]string{}, ['inputs_sha256', 'framework_manifest_sha256'], ['inputs_sha256', 'inputs_sha256']] {
		mut bad := controller_memory_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		if _ := verify_controller_memory_receipt(bad, stage) { return error('unsafe controller memory top delta accepted') }
	}
	entries := controller_memory_entries_fixture()
	for index, entry in entries {
		mut changed := entries.clone()
		changed[index] = ServiceQueryEntry{...entry, kind: 'symlink'}
		mut bad := controller_memory_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_controller_memory_receipt(bad, stage) { return error('controller memory symlink accepted') }
		changed[index] = ServiceQueryEntry{...entry, mode: 0o777}
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_controller_memory_receipt(bad, stage) { return error('unsafe controller memory mode accepted') }
		if entry.kind == 'regular' {
			changed[index] = ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { controller_pin }}
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_controller_memory_receipt(bad, stage) { return error('changed controller memory inventory digest accepted') }
		}
	}
	for addition in [ServiceQueryEntry{name: 'extra', kind: 'regular', sha256: controller_memory_pin, mode: 0o644},
		ServiceQueryEntry{name: '../escape', kind: 'directory', mode: 0o755},
		ServiceQueryEntry{name: 'unrelated', kind: 'directory', mode: 0o755}, entries[0]] {
		mut changed := entries.clone()
		changed << addition
		mut bad := controller_memory_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_controller_memory_receipt(bad, stage) { return error('extra or duplicate controller memory inode accepted') }
	}
	mut removed := controller_memory_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_controller_memory_receipt(removed, stage) { return error('missing controller memory file accepted') }
	if _ := verify_service_query_receipt(receipt, stage) { return error('memory receipt accepted by service-query profile') }
	if _ := verify_controller_memory_receipt(service_query_receipt_fixture()!, stage) { return error('service-query receipt accepted by memory profile') }
	if _ := verify_controller_receipt(receipt, stage) { return error('memory receipt accepted by controller profile') }
	if _ := verify_controller_memory_receipt(controller_receipt_fixture()!, stage) { return error('old controller receipt accepted by memory profile') }
	println('MAPS-CONTROLLER-MEMORY KERNEL-PROFILE-SELF-TEST PASS exact service-query base controller inputs two-alias deployment delta three-file inventory ten modules historical profile rejection')
}

fn direct_boot_delta_fixture() map[string]string {
	mut delta := direct_boot_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'b'.repeat(64)
	return delta
}

fn direct_boot_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in direct_boot_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn direct_boot_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in direct_boot_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(direct_boot_delta_fixture()))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: direct_boot_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(direct_boot_entries_fixture()))!
	return receipt
}

fn direct_boot_profile_self_test() ! {
	profile := direct_boot_profile()
	assert profile.baseline_sha == direct_boot_boot_sha
	assert profile.modules.len == 11 && profile.modules.last() == 'maps-controller-memory-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..11].clone()}, Config{'other', modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe direct-boot modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', controller_memory_profile().modules}, Config{'vinix', modules}) {
		return error('ten-module direct-boot baseline accepted')
	}
	stage := Stage{format: 1, inputs_sha256: direct_boot_inputs(),
		original_modules_sha256: direct_boot_modules(), preserved_modules_sha256: direct_boot_modules()}
	receipt := direct_boot_receipt_fixture()!
	verify_direct_boot_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := direct_boot_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_direct_boot_receipt(bad, stage) { return error('changed direct-boot receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_direct_boot_receipt(bad, stage) { return error('missing direct-boot receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_direct_boot_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('changed direct-boot input pin accepted')
		}
		inputs.delete(path)
		if _ := verify_direct_boot_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('missing direct-boot input accepted')
		}
	}
	mut old_inputs := stage.inputs_sha256.clone()
	old_inputs.delete(direct_boot_framework + '/sha256.json')
	old_inputs[service_query_framework + '/sha256.json'] = direct_boot_framework_seal
	if _ := verify_direct_boot_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
		return error('old framework path with direct-boot seal accepted')
	}
	mut old_seal := stage.inputs_sha256.clone()
	old_seal[direct_boot_framework + '/sha256.json'] = service_query_framework_seal
	if _ := verify_direct_boot_receipt(receipt, Stage{...stage, inputs_sha256: old_seal}) {
		return error('direct-boot framework path with old seal accepted')
	}
	for name in direct_boot_modules().keys() {
		mut pins := direct_boot_modules()
		pins[name] = '0'.repeat(64)
		for bad in [Stage{...stage, original_modules_sha256: pins}, Stage{...stage, preserved_modules_sha256: pins}] {
			if _ := verify_direct_boot_receipt(receipt, bad) { return error('changed direct-boot module accepted') }
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: controller_memory_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_direct_boot_receipt(receipt, bad) { return error('changed direct-boot module contract accepted') }
	}
	delta := direct_boot_delta_fixture()
	for path in delta.keys() {
		mut changed := delta.clone()
		changed.delete(path)
		mut bad := direct_boot_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('partial direct-boot delta accepted') }
		changed = delta.clone()
		changed[path] = '0'.repeat(64)
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('changed direct-boot delta accepted') }
	}
	for addition in ['/extra', '/opt/vinix-maps-account/bin/maps-account-guest'] {
		mut changed := delta.clone()
		changed[addition] = controller_memory_pin
		mut bad := direct_boot_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('extra direct-boot input accepted') }
	}
	for name, alternatives in {
		'headless_top_level_delta': [[]string{}, ['inputs_sha256', 'extra'], ['inputs_sha256', 'inputs_sha256']]
		'deployment_top_level_delta': [[]string{}, ['inputs_sha256'], ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256']]
	} {
		for alternative in alternatives {
			mut bad := direct_boot_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(alternative))!
			if _ := verify_direct_boot_receipt(bad, stage) { return error('unsafe direct-boot top delta accepted') }
		}
	}
	for changed in [map[string]string{}, {'/' + service_query_jar_path: service_query_jar},
		{'/' + service_query_jar_path: direct_boot_jar, '/extra': direct_boot_jar}] {
		mut bad := direct_boot_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('unsafe direct-boot headless delta accepted') }
	}
	for pin in ['invalid', '11920c8c77da858898ef2dfaca45ecf70f32d41b8884d41c450f6691f7e16292'] {
		mut changed := delta.clone()
		changed['/' + service_query_headless + '/guest-inputs.json'] = pin
		mut bad := direct_boot_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('retained direct-boot guest input pin accepted') }
	}
	entries := direct_boot_entries_fixture()
	for index, entry in entries {
		mut changed := entries.clone()
		changed[index] = ServiceQueryEntry{...entry, kind: 'symlink'}
		mut bad := direct_boot_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('direct-boot symlink accepted') }
		changed[index] = ServiceQueryEntry{...entry, mode: 0o777}
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('unsafe direct-boot mode accepted') }
		if entry.kind == 'regular' {
			changed[index] = ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_direct_boot_receipt(bad, stage) { return error('changed direct-boot inventory digest accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: controller_memory_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := direct_boot_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_direct_boot_receipt(bad, stage) { return error('extra or duplicate direct-boot inode accepted') }
	}
	mut removed := direct_boot_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_direct_boot_receipt(removed, stage) { return error('missing direct-boot file accepted') }
	if _ := verify_controller_memory_receipt(receipt, stage) { return error('direct-boot receipt accepted by memory profile') }
	if _ := verify_direct_boot_receipt(controller_memory_receipt_fixture()!, stage) { return error('memory receipt accepted by direct-boot profile') }
	if _ := verify_service_query_receipt(receipt, stage) { return error('direct-boot receipt accepted by service-query profile') }
	if _ := verify_direct_boot_receipt(service_query_receipt_fixture()!, stage) { return error('service-query receipt accepted by direct-boot profile') }
	println('MAPS-DIRECT-BOOT KERNEL-PROFILE-SELF-TEST PASS exact memory base framework inputs five-path deployment one-path headless delta six-file inventory eleven modules historical profile rejection')
}

fn context_storage_delta_fixture() map[string]string {
	mut delta := context_storage_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'b'.repeat(64)
	return delta
}

fn context_storage_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in context_storage_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn context_storage_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in context_storage_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(context_storage_delta_fixture()))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: context_storage_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(context_storage_entries_fixture()))!
	return receipt
}

fn context_storage_profile_self_test() ! {
	profile := context_storage_profile()
	assert profile.baseline_sha == context_storage_boot_sha
	assert profile.modules.len == 12 && profile.modules.last() == 'maps-direct-boot-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..12].clone()}, Config{'other', modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe context storage modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', direct_boot_profile().modules}, Config{'vinix', modules}) {
		return error('eleven-module context storage baseline accepted')
	}
	stage := Stage{format: 1, inputs_sha256: context_storage_inputs(),
		original_modules_sha256: context_storage_modules(), preserved_modules_sha256: context_storage_modules()}
	receipt := context_storage_receipt_fixture()!
	verify_context_storage_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := context_storage_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_context_storage_receipt(bad, stage) { return error('changed context storage receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_context_storage_receipt(bad, stage) { return error('missing context storage receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_context_storage_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('changed context storage input pin accepted')
		}
		inputs.delete(path)
		if _ := verify_context_storage_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) {
			return error('missing context storage input accepted')
		}
	}
	mut old_inputs := stage.inputs_sha256.clone()
	old_inputs.delete(context_storage_framework + '/sha256.json')
	old_inputs[direct_boot_framework + '/sha256.json'] = context_storage_framework_seal
	if _ := verify_context_storage_receipt(receipt, Stage{...stage, inputs_sha256: old_inputs}) {
		return error('old framework path with context storage seal accepted')
	}
	mut old_seal := stage.inputs_sha256.clone()
	old_seal[context_storage_framework + '/sha256.json'] = direct_boot_framework_seal
	if _ := verify_context_storage_receipt(receipt, Stage{...stage, inputs_sha256: old_seal}) {
		return error('context storage framework path with old seal accepted')
	}
	for name in context_storage_modules().keys() {
		mut pins := context_storage_modules()
		pins[name] = '0'.repeat(64)
		for bad in [Stage{...stage, original_modules_sha256: pins}, Stage{...stage, preserved_modules_sha256: pins}] {
			if _ := verify_context_storage_receipt(receipt, bad) { return error('changed context storage module accepted') }
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: direct_boot_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_context_storage_receipt(receipt, bad) { return error('changed context storage module contract accepted') }
	}
	context_storage_overlay_self_test(receipt, stage)!
	if _ := verify_direct_boot_receipt(receipt, stage) { return error('context storage receipt accepted by direct-boot profile') }
	if _ := verify_context_storage_receipt(direct_boot_receipt_fixture()!, stage) { return error('direct-boot receipt accepted by context storage profile') }
	if _ := verify_context_storage_receipt(controller_memory_receipt_fixture()!, stage) { return error('memory receipt accepted by context storage profile') }
	println('MAPS-CONTEXT-STORAGE KERNEL-PROFILE-SELF-TEST PASS exact direct-boot base framework inputs five-path deployment one-path headless delta six-file inventory twelve modules historical profile rejection')
}

fn context_storage_overlay_self_test(receipt map[string]json2.Any, stage Stage) ! {
	delta := context_storage_delta_fixture()
	for path in delta.keys() {
		mut changed := delta.clone()
		changed.delete(path)
		mut bad := context_storage_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('partial context storage delta accepted') }
		changed = delta.clone()
		changed[path] = '0'.repeat(64)
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('changed context storage delta accepted') }
	}
	for addition in ['/extra', '/opt/vinix-maps-account/bin/maps-account-guest'] {
		mut changed := delta.clone()
		changed[addition] = controller_memory_pin
		mut bad := context_storage_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('extra context storage input accepted') }
	}
	for name, alternatives in {
		'headless_top_level_delta': [[]string{}, ['inputs_sha256', 'extra'], ['inputs_sha256', 'inputs_sha256']]
		'deployment_top_level_delta': [[]string{}, ['inputs_sha256'], ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256']]
	} {
		for alternative in alternatives {
			mut bad := context_storage_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(alternative))!
			if _ := verify_context_storage_receipt(bad, stage) { return error('unsafe context storage top delta accepted') }
		}
	}
	for changed in [map[string]string{}, {'/' + service_query_jar_path: direct_boot_jar},
		{'/' + service_query_jar_path: context_storage_jar, '/extra': context_storage_jar}] {
		mut bad := context_storage_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('unsafe context storage headless delta accepted') }
	}
	entries := context_storage_entries_fixture()
	// Keep the inventory coherent to exercise the retained digest guard itself.
	for pin in ['invalid', '88404ba463ab108502adaaec46c2038abb0a4984d4af6c68e72e887558f50651'] {
		mut changed := delta.clone()
		guest_path := '/' + service_query_headless + '/guest-inputs.json'
		changed[guest_path] = pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == guest_path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: pin} }
		}
		mut bad := context_storage_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('retained context storage guest input pin accepted') }
	}
	// A coherent old payload and delta must still fail the new producer pins.
	for path, old_pin in {
		'/' + service_query_jar_path: direct_boot_jar
		'/' + service_query_dex_path: direct_boot_dex
		'/' + service_query_headless + '/framework-build.json': direct_boot_build
		'/' + service_query_headless + '/framework-sha256.json': direct_boot_framework_seal
	} {
		mut changed := delta.clone()
		changed[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := context_storage_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('mixed old context storage framework accepted') }
	}
	for index, entry in entries {
		mut changed := entries.clone()
		changed[index] = ServiceQueryEntry{...entry, kind: 'symlink'}
		mut bad := context_storage_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('context storage symlink accepted') }
		changed[index] = ServiceQueryEntry{...entry, mode: 0o777}
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('unsafe context storage mode accepted') }
		if entry.kind == 'regular' {
			changed[index] = ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_context_storage_receipt(bad, stage) { return error('changed context storage inventory digest accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: controller_memory_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := context_storage_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_context_storage_receipt(bad, stage) { return error('extra or duplicate context storage inode accepted') }
	}
	mut removed := context_storage_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_context_storage_receipt(removed, stage) { return error('missing context storage file accepted') }
	verify_context_storage_receipt(receipt, stage)!
}

fn broadcast_result_delta_fixture() map[string]string {
	mut delta := broadcast_result_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'b'.repeat(64)
	return delta
}

fn broadcast_result_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in broadcast_result_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn broadcast_result_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in broadcast_result_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(broadcast_result_delta_fixture()))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: broadcast_result_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(broadcast_result_entries_fixture()))!
	return receipt
}

fn broadcast_result_profile_self_test() ! {
	profile := broadcast_result_profile()
	assert profile.baseline_sha == broadcast_result_boot_sha
	assert profile.modules.len == 13 && profile.modules.last() == 'maps-context-storage-diagnostic.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	mut duplicate := modules.clone()
	duplicate << profile.overlay
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..13].clone()}, Config{'other', modules}, Config{'vinix', duplicate}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe broadcast result modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', context_storage_profile().modules}, Config{'vinix', modules}) {
		return error('twelve-module broadcast result baseline accepted')
	}
	stage := Stage{format: 1, inputs_sha256: broadcast_result_inputs(),
		original_modules_sha256: broadcast_result_modules(), preserved_modules_sha256: broadcast_result_modules()}
	receipt := broadcast_result_receipt_fixture()!
	verify_broadcast_result_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := broadcast_result_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('changed broadcast result receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('missing broadcast result receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_broadcast_result_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed broadcast result input pin accepted') }
		inputs.delete(path)
		if _ := verify_broadcast_result_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing broadcast result input accepted') }
	}
	mut old_path := stage.inputs_sha256.clone()
	old_path.delete(broadcast_result_framework + '/sha256.json')
	old_path[context_storage_framework + '/sha256.json'] = broadcast_result_framework_seal
	if _ := verify_broadcast_result_receipt(receipt, Stage{...stage, inputs_sha256: old_path}) { return error('old framework path with broadcast result seal accepted') }
	mut old_seal := stage.inputs_sha256.clone()
	old_seal[broadcast_result_framework + '/sha256.json'] = context_storage_framework_seal
	if _ := verify_broadcast_result_receipt(receipt, Stage{...stage, inputs_sha256: old_seal}) { return error('broadcast result framework path with old seal accepted') }
	for name in broadcast_result_modules().keys() {
		for remove in [false, true] {
			mut pins := broadcast_result_modules()
			if remove { pins.delete(name) } else { pins[name] = '0'.repeat(64) }
			for bad in [Stage{...stage, original_modules_sha256: pins}, Stage{...stage, preserved_modules_sha256: pins}] {
				if _ := verify_broadcast_result_receipt(receipt, bad) { return error('changed or missing broadcast result module accepted') }
			}
		}
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: context_storage_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_broadcast_result_receipt(receipt, bad) { return error('changed broadcast result module contract accepted') }
	}
	broadcast_result_overlay_self_test(receipt, stage)!
	if _ := verify_context_storage_receipt(receipt, stage) { return error('broadcast result receipt accepted by Context storage profile') }
	if _ := verify_broadcast_result_receipt(context_storage_receipt_fixture()!, stage) { return error('Context storage receipt accepted by broadcast result profile') }
	// Replacing all producer headers and payload declarations coherently still fails.
	mut old := context_storage_receipt_fixture()!
	old['kind'] = receipt['kind'] or { return error('fixture kind absent') }
	old['base_root'] = json2.Any(broadcast_result_base)
	old['base_manifest_sha256'] = json2.Any(broadcast_result_base_seal)
	old['retained_framework_manifest_sha256'] = json2.Any(context_storage_framework_seal)
	mut old_inputs := broadcast_result_inputs()
	old_inputs.delete(broadcast_result_framework + '/sha256.json')
	if _ := verify_broadcast_result_receipt(old, Stage{...stage, inputs_sha256: old_inputs}) { return error('coherent old Context framework accepted') }
	println('MAPS-BROADCAST-RESULT KERNEL-PROFILE-SELF-TEST PASS exact Context base framework inputs five-path deployment one-path headless delta six-file inventory thirteen modules coherent old producer rejection')
}

fn broadcast_result_overlay_self_test(receipt map[string]json2.Any, stage Stage) ! {
	delta := broadcast_result_delta_fixture()
	for path in delta.keys() {
		mut changed := delta.clone()
		changed.delete(path)
		mut bad := broadcast_result_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('partial broadcast result delta accepted') }
		changed = delta.clone()
		changed[path] = '0'.repeat(64)
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('changed broadcast result delta accepted') }
	}
	for addition in ['/extra', '/opt/vinix-maps-account/bin/maps-account-guest'] {
		mut changed := delta.clone()
		changed[addition] = controller_memory_pin
		mut bad := broadcast_result_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('extra broadcast result input accepted') }
	}
	for name, alternatives in {
		'headless_top_level_delta': [[]string{}, ['inputs_sha256', 'extra'], ['inputs_sha256', 'inputs_sha256']]
		'deployment_top_level_delta': [[]string{}, ['inputs_sha256'], ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256']]
	} {
		for alternative in alternatives {
			mut bad := broadcast_result_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(alternative))!
			if _ := verify_broadcast_result_receipt(bad, stage) { return error('unsafe broadcast result top delta accepted') }
		}
	}
	for changed in [map[string]string{}, {'/' + service_query_jar_path: context_storage_jar},
		{'/' + service_query_jar_path: broadcast_result_jar, '/extra': broadcast_result_jar}] {
		mut bad := broadcast_result_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('unsafe broadcast result headless delta accepted') }
	}
	entries := broadcast_result_entries_fixture()
	mut retained := context_storage_known_delta()
	retained['/' + service_query_headless + '/guest-inputs.json'] = 'c9ff204863dec37bc1913e0eef2bdf6c9edca1c8cecebeefb7e3659f90e05ab6'
	retained['/' + service_query_headless + '/guest-inputs.json-invalid'] = 'invalid'
	for original_path, old_pin in retained {
		path := original_path.replace('-invalid', '')
		mut changed := delta.clone()
		changed[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := broadcast_result_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if path == '/' + service_query_jar_path {
			bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode({path: old_pin}))!
		}
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('coherent retained broadcast result payload accepted') }
	}
	for index, entry in entries {
		mut changed := entries.clone()
		changed[index] = ServiceQueryEntry{...entry, kind: 'symlink'}
		mut bad := broadcast_result_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('broadcast result symlink accepted') }
		changed[index] = ServiceQueryEntry{...entry, mode: 0o777}
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('unsafe broadcast result mode accepted') }
		if entry.kind == 'regular' {
			changed[index] = ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_broadcast_result_receipt(bad, stage) { return error('changed broadcast result inventory digest accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: controller_memory_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := broadcast_result_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_broadcast_result_receipt(bad, stage) { return error('extra or duplicate broadcast result inode accepted') }
	}
	mut removed := broadcast_result_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_broadcast_result_receipt(removed, stage) { return error('missing broadcast result file accepted') }
	verify_broadcast_result_receipt(receipt, stage)!
}

fn onboarding_trace_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in onboarding_trace_fields() { receipt[name] = json2.Any(value) }
	mut entries := []ServiceQueryEntry{}
	for path, pin in onboarding_trace_delta() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o755}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(onboarding_trace_delta()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries))!
	return receipt
}

fn onboarding_trace_profile_self_test() ! {
	profile := onboarding_trace_profile()
	assert profile.baseline_sha == onboarding_trace_boot_sha
	assert profile.modules.len == 14 && profile.modules.last() == 'maps-broadcast-result-diagnostic.tar'
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', broadcast_result_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe onboarding trace modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: onboarding_trace_inputs(),
		original_modules_sha256: onboarding_trace_modules(), preserved_modules_sha256: onboarding_trace_modules()}
	receipt := onboarding_trace_receipt_fixture()!
	verify_onboarding_trace_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := onboarding_trace_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_onboarding_trace_receipt(bad, stage) { return error('changed onboarding trace field accepted') }
		bad.delete(name)
		if _ := verify_onboarding_trace_receipt(bad, stage) { return error('missing onboarding trace field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_onboarding_trace_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed onboarding trace input accepted') }
		inputs.delete(path)
		if _ := verify_onboarding_trace_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing onboarding trace input accepted') }
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: broadcast_result_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_onboarding_trace_receipt(receipt, bad) { return error('wrong onboarding trace module inventory accepted') }
	}
	entries := json2.decode[[]ServiceQueryEntry](json2.encode(receipt['overlay_inventory']!))!
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777}] {
			mut bad_entries := entries.clone()
			bad_entries[index] = replacement
			mut bad := onboarding_trace_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
			if _ := verify_onboarding_trace_receipt(bad, stage) { return error('unsafe onboarding trace inode accepted') }
		}
	}
	for extra in [entries[0], ServiceQueryEntry{name: 'extra', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o644}] {
		mut bad_entries := entries.clone()
		bad_entries << extra
		mut bad := onboarding_trace_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(bad_entries))!
		if _ := verify_onboarding_trace_receipt(bad, stage) { return error('extra onboarding trace inode accepted') }
	}
	if _ := verify_onboarding_trace_receipt(broadcast_result_receipt_fixture()!, stage) { return error('broadcast receipt accepted by onboarding profile') }
	if _ := verify_broadcast_result_receipt(receipt, stage) { return error('onboarding receipt accepted by broadcast profile') }
	println('MAPS-ONBOARDING-TRACE KERNEL-PROFILE-SELF-TEST PASS exact controller input aliases delta inventory fourteen modules historical rejection')
}

fn native_onboarding_trace_delta_fixture() map[string]string {
	mut delta := native_onboarding_trace_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'd'.repeat(64)
	return delta
}

fn native_onboarding_trace_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in native_onboarding_trace_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin,
			mode: if path == '/' + native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn native_onboarding_trace_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in native_onboarding_trace_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(native_onboarding_trace_delta_fixture()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'native_manifest_sha256']))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + native_onboarding_trace_path: native_onboarding_trace_pin}))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(native_onboarding_trace_entries_fixture()))!
	return receipt
}

fn native_onboarding_trace_profile_self_test() ! {
	profile := native_onboarding_trace_profile()
	assert profile.baseline_sha == native_onboarding_trace_boot_sha
	assert profile.modules.len == 15 && profile.modules.last() == 'maps-onboarding-trace-diagnostic.tar'
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', onboarding_trace_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe native onboarding trace modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: native_onboarding_trace_inputs(),
		original_modules_sha256: native_onboarding_trace_modules(), preserved_modules_sha256: native_onboarding_trace_modules()}
	receipt := native_onboarding_trace_receipt_fixture()!
	verify_native_onboarding_trace_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := native_onboarding_trace_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('changed native onboarding trace field accepted') }
		bad.delete(name)
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('missing native onboarding trace field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_native_onboarding_trace_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed native onboarding trace input accepted') }
		inputs.delete(path)
		if _ := verify_native_onboarding_trace_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing native onboarding trace input accepted') }
	}
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: onboarding_trace_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_native_onboarding_trace_receipt(receipt, bad) { return error('wrong native onboarding trace module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + native_onboarding_trace_path: native_onboarding_trace_retained_pin},
		{'/' + native_onboarding_trace_path: native_onboarding_trace_pin, '/extra': native_onboarding_trace_pin}] {
		mut bad := native_onboarding_trace_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('unsafe native onboarding trace headless delta accepted') }
	}
	for changed in [[]string{}, ['inputs_sha256'], ['native_manifest_sha256', 'inputs_sha256'],
		['inputs_sha256', 'native_manifest_sha256', 'framework_manifest_sha256']] {
		mut bad := native_onboarding_trace_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('unsafe native onboarding trace top delta accepted') }
	}
	entries := native_onboarding_trace_entries_fixture()
	for path, old_pin in {
		'/' + native_onboarding_trace_path: native_onboarding_trace_retained_pin
		'/' + service_query_headless + '/native-build.json': native_onboarding_trace_retained_build
		'/' + service_query_headless + '/native-sha256.json': protected_native_seal
		'/' + service_query_headless + '/guest-inputs.json': native_onboarding_trace_retained_guest
	} {
		mut delta := native_onboarding_trace_delta_fixture()
		delta[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := native_onboarding_trace_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if path == '/' + native_onboarding_trace_path {
			bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode({path: old_pin}))!
		}
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('coherent retained native onboarding trace payload accepted') }
	}
	for index, entry in entries {
		mut changed := entries.clone()
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			changed[index] = replacement
			mut bad := native_onboarding_trace_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('unsafe native onboarding trace inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := native_onboarding_trace_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_native_onboarding_trace_receipt(bad, stage) { return error('extra or duplicate native onboarding trace inode accepted') }
	}
	mut removed := native_onboarding_trace_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_native_onboarding_trace_receipt(removed, stage) { return error('missing native onboarding trace file accepted') }
	if _ := verify_native_onboarding_trace_receipt(onboarding_trace_receipt_fixture()!, stage) { return error('controller trace receipt accepted by native onboarding profile') }
	if _ := verify_onboarding_trace_receipt(receipt, stage) { return error('native trace receipt accepted by controller onboarding profile') }
	if _ := verify_broadcast_result_receipt(receipt, stage) { return error('native trace receipt accepted by broadcast profile') }
	println('MAPS-NATIVE-ONBOARDING-TRACE KERNEL-PROFILE-SELF-TEST PASS exact native four-input delta five-file inventory fifteen modules historical rejection')
}

fn onboarding_framework_delta_fixture() map[string]string {
	mut delta := onboarding_framework_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'd'.repeat(64)
	return delta
}

fn onboarding_framework_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in onboarding_framework_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn onboarding_framework_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in onboarding_framework_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(onboarding_framework_delta_fixture()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: onboarding_framework_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(onboarding_framework_entries_fixture()))!
	return receipt
}

fn onboarding_framework_profile_self_test() ! {
	profile := onboarding_framework_profile()
	assert profile.baseline_sha == onboarding_framework_boot_sha
	assert profile.modules.len == 16 && profile.modules.last() == 'maps-native-onboarding-trace-diagnostic.tar'
	assert onboarding_framework_inputs().len == 32
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', native_onboarding_trace_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe onboarding framework modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: onboarding_framework_inputs(),
		original_modules_sha256: onboarding_framework_modules(), preserved_modules_sha256: onboarding_framework_modules()}
	receipt := onboarding_framework_receipt_fixture()!
	verify_onboarding_framework_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := onboarding_framework_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_onboarding_framework_receipt(bad, stage) { return error('changed onboarding framework field accepted') }
		bad.delete(name)
		if _ := verify_onboarding_framework_receipt(bad, stage) { return error('missing onboarding framework field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_onboarding_framework_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed onboarding framework input accepted') }
		inputs.delete(path)
		if _ := verify_onboarding_framework_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing onboarding framework input accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unexpected/sha256.json'] = 'a'.repeat(64)
	if _ := verify_onboarding_framework_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra onboarding framework dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: native_onboarding_trace_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_onboarding_framework_receipt(receipt, bad) { return error('wrong onboarding framework module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + service_query_jar_path: broadcast_result_jar},
		{'/' + service_query_jar_path: onboarding_framework_jar, '/' + native_onboarding_trace_path: native_onboarding_trace_pin}] {
		mut bad := onboarding_framework_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_onboarding_framework_receipt(bad, stage) { return error('unsafe onboarding framework headless delta accepted') }
	}
	for name in ['headless_top_level_delta', 'deployment_top_level_delta'] {
		for changed in [[]string{}, ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256']] {
			mut bad := onboarding_framework_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_onboarding_framework_receipt(bad, stage) { return error('unsafe onboarding framework top delta accepted') }
		}
	}
	entries := onboarding_framework_entries_fixture()
	for path, old_pin in {
		'/' + service_query_jar_path: broadcast_result_jar
		'/' + service_query_dex_path: broadcast_result_dex
		'/' + service_query_headless + '/framework-build.json': broadcast_result_build
		'/' + service_query_headless + '/framework-sha256.json': broadcast_result_framework_seal
		'/' + service_query_headless + '/guest-inputs.json': onboarding_framework_retained_guest
	} {
		mut delta := onboarding_framework_delta_fixture()
		delta[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := onboarding_framework_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if path == '/' + service_query_jar_path {
			bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode({path: old_pin}))!
		}
		if _ := verify_onboarding_framework_receipt(bad, stage) { return error('coherent retained onboarding framework payload accepted') }
	}
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := onboarding_framework_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_onboarding_framework_receipt(bad, stage) { return error('unsafe onboarding framework inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: native_onboarding_trace_path, kind: 'regular', sha256: native_onboarding_trace_pin, mode: 0o755},
		ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := onboarding_framework_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_onboarding_framework_receipt(bad, stage) { return error('extra or duplicate onboarding framework inode accepted') }
	}
	mut removed := onboarding_framework_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_onboarding_framework_receipt(removed, stage) { return error('missing onboarding framework file accepted') }
	if _ := verify_onboarding_framework_receipt(native_onboarding_trace_receipt_fixture()!, stage) { return error('native trace receipt accepted by onboarding framework profile') }
	if _ := verify_native_onboarding_trace_receipt(receipt, stage) { return error('framework receipt accepted by native trace profile') }
	if _ := verify_broadcast_result_receipt(receipt, stage) { return error('onboarding framework receipt accepted by broadcast profile') }
	println('MAPS-ONBOARDING-FRAMEWORK KERNEL-PROFILE-SELF-TEST PASS exact five-input delta six-file inventory sixteen modules thirty-two dependencies historical rejection')
}

fn native_heartbeat_delta_fixture() map[string]string {
	mut delta := native_heartbeat_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'd'.repeat(64)
	return delta
}

fn native_heartbeat_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in native_heartbeat_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin,
			mode: if path == '/' + native_onboarding_trace_path { u32(0o755) } else { u32(0o644) }}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn native_heartbeat_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in native_heartbeat_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(native_heartbeat_delta_fixture()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'native_manifest_sha256']))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + native_onboarding_trace_path: native_heartbeat_pin}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(native_heartbeat_entries_fixture()))!
	return receipt
}

fn native_heartbeat_profile_self_test() ! {
	profile := native_heartbeat_profile()
	assert profile.baseline_sha == native_heartbeat_boot_sha
	assert profile.modules.len == 17 && profile.modules.last() == 'maps-onboarding-framework-diagnostic.tar'
	assert native_heartbeat_inputs().len == 34
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', onboarding_framework_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe native heartbeat modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: native_heartbeat_inputs(),
		original_modules_sha256: native_heartbeat_modules(), preserved_modules_sha256: native_heartbeat_modules()}
	receipt := native_heartbeat_receipt_fixture()!
	verify_native_heartbeat_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := native_heartbeat_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_native_heartbeat_receipt(bad, stage) { return error('changed native heartbeat field accepted') }
		bad.delete(name)
		if _ := verify_native_heartbeat_receipt(bad, stage) { return error('missing native heartbeat field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_native_heartbeat_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed native heartbeat input accepted') }
		inputs.delete(path)
		if _ := verify_native_heartbeat_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing native heartbeat input accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unreviewed/sha256.json'] = '0'.repeat(64)
	if _ := verify_native_heartbeat_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra native heartbeat dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: onboarding_framework_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_native_heartbeat_receipt(receipt, bad) { return error('wrong native heartbeat module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + native_onboarding_trace_path: native_onboarding_trace_pin},
		{'/' + native_onboarding_trace_path: native_heartbeat_pin, '/' + service_query_jar_path: onboarding_framework_jar}] {
		mut bad := native_heartbeat_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_native_heartbeat_receipt(bad, stage) { return error('unsafe native heartbeat headless delta accepted') }
	}
	for field in ['deployment_top_level_delta', 'headless_top_level_delta'] {
		for changed in [[]string{}, ['inputs_sha256', 'framework_manifest_sha256'],
			['native_manifest_sha256', 'inputs_sha256'], ['inputs_sha256', 'native_manifest_sha256', 'framework_manifest_sha256']] {
			mut bad := native_heartbeat_receipt_fixture()!
			bad[field] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_native_heartbeat_receipt(bad, stage) { return error('unsafe native heartbeat top delta accepted') }
		}
	}
	entries := native_heartbeat_entries_fixture()
	for path, old_pin in {
		'/' + native_onboarding_trace_path: native_onboarding_trace_pin
		'/' + service_query_headless + '/native-build.json': native_onboarding_trace_build
		'/' + service_query_headless + '/native-sha256.json': native_onboarding_trace_seal
		'/' + service_query_headless + '/guest-inputs.json': native_heartbeat_retained_guest
	} {
		mut delta := native_heartbeat_delta_fixture()
		delta[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := native_heartbeat_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if path == '/' + native_onboarding_trace_path {
			bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode({path: old_pin}))!
		}
		if _ := verify_native_heartbeat_receipt(bad, stage) { return error('coherent retained native heartbeat payload accepted') }
	}
	for index, entry in entries {
		mut changed := entries.clone()
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			changed[index] = replacement
			mut bad := native_heartbeat_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_native_heartbeat_receipt(bad, stage) { return error('unsafe native heartbeat inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o755},
		ServiceQueryEntry{name: service_query_jar_path, kind: 'regular', sha256: onboarding_framework_jar, mode: 0o644},
		ServiceQueryEntry{name: service_query_dex_path, kind: 'regular', sha256: onboarding_framework_dex, mode: 0o644},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := native_heartbeat_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_native_heartbeat_receipt(bad, stage) { return error('extra or duplicate native heartbeat inode accepted') }
	}
	mut removed := native_heartbeat_receipt_fixture()!
	removed['overlay_inventory'] = json2.decode[json2.Any](json2.encode(entries[1..]))!
	if _ := verify_native_heartbeat_receipt(removed, stage) { return error('missing native heartbeat file accepted') }
	if _ := verify_native_heartbeat_receipt(onboarding_framework_receipt_fixture()!, stage) { return error('framework receipt accepted by native heartbeat profile') }
	if _ := verify_native_heartbeat_receipt(native_onboarding_trace_receipt_fixture()!, stage) { return error('old native trace receipt accepted by native heartbeat profile') }
	if _ := verify_onboarding_framework_receipt(receipt, stage) { return error('native heartbeat receipt accepted by framework profile') }
	if _ := verify_native_onboarding_trace_receipt(receipt, stage) { return error('native heartbeat receipt accepted by old native trace profile') }
	println('MAPS-NATIVE-HEARTBEAT KERNEL-PROFILE-SELF-TEST PASS exact native four-input delta five-file inventory seventeen modules thirty-four dependencies historical rejection')
}

fn browser_poll_entries_fixture() []ServiceQueryEntry {
	return [ServiceQueryEntry{name: browser_poll_path, kind: 'regular', sha256: browser_poll_pin, mode: 0o644},
		ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644},
		ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}]
}

fn browser_poll_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in browser_poll_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + browser_poll_path: browser_poll_pin}))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'browser_client_manifest_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(browser_poll_entries_fixture()))!
	return receipt
}

fn browser_poll_profile_self_test() ! {
	profile := browser_poll_profile()
	assert profile.baseline_sha == browser_poll_boot_sha
	assert profile.modules.len == 18 && profile.modules.last() == 'maps-native-heartbeat-diagnostic.tar'
	assert browser_poll_inputs().len == 36
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', native_heartbeat_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe browser poll modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: browser_poll_inputs(),
		original_modules_sha256: browser_poll_modules(), preserved_modules_sha256: browser_poll_modules()}
	receipt := browser_poll_receipt_fixture()!
	verify_browser_poll_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := browser_poll_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_browser_poll_receipt(bad, stage) { return error('changed browser poll field accepted') }
		bad.delete(name)
		if _ := verify_browser_poll_receipt(bad, stage) { return error('missing browser poll field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_browser_poll_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed browser poll input accepted') }
		inputs.delete(path)
		if _ := verify_browser_poll_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing browser poll input accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unreviewed/sha256.json'] = '0'.repeat(64)
	if _ := verify_browser_poll_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra browser poll dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: native_heartbeat_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_browser_poll_receipt(receipt, bad) { return error('wrong browser poll module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + browser_poll_path: browser_poll_retained_pin},
		{'/' + browser_poll_path: browser_poll_pin, '/' + native_onboarding_trace_path: native_heartbeat_pin}] {
		mut bad := browser_poll_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_browser_poll_receipt(bad, stage) { return error('unsafe browser poll input delta accepted') }
	}
	for changed in [[]string{}, ['inputs_sha256'], ['inputs_sha256', 'browser_manifest_sha256'],
		['browser_client_manifest_sha256', 'inputs_sha256'],
		['inputs_sha256', 'browser_client_manifest_sha256', 'native_manifest_sha256']] {
		mut bad := browser_poll_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_browser_poll_receipt(bad, stage) { return error('unsafe browser poll top-level delta accepted') }
	}
	for name in ['headless_input_delta', 'headless_top_level_delta'] {
		mut bad := browser_poll_receipt_fixture()!
		bad[name] = json2.decode[json2.Any](json2.encode([]string{}))!
		if _ := verify_browser_poll_receipt(bad, stage) { return error('browser poll headless change accepted') }
	}
	entries := browser_poll_entries_fixture()
	mut retained := browser_poll_receipt_fixture()!
	mut retained_entries := entries.clone()
	retained_entries[0] = ServiceQueryEntry{...entries[0], sha256: browser_poll_retained_pin}
	retained['deployment_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + browser_poll_path: browser_poll_retained_pin}))!
	retained['overlay_inventory'] = json2.decode[json2.Any](json2.encode(retained_entries))!
	if _ := verify_browser_poll_receipt(retained, stage) { return error('coherent retained browser poll payload accepted') }
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := browser_poll_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_browser_poll_receipt(bad, stage) { return error('unsafe browser poll inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: native_onboarding_trace_path, kind: 'regular', sha256: native_heartbeat_pin, mode: 0o755},
		ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o755},
		ServiceQueryEntry{name: service_query_jar_path, kind: 'regular', sha256: onboarding_framework_jar, mode: 0o644},
		ServiceQueryEntry{name: service_query_headless + '/guest-inputs.json', kind: 'regular', sha256: 'd'.repeat(64), mode: 0o644},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := browser_poll_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_browser_poll_receipt(bad, stage) { return error('extra or duplicate browser poll inode accepted') }
	}
	for removed_index in [0, 1] {
		mut changed := entries.clone()
		changed.delete(removed_index)
		mut bad := browser_poll_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_browser_poll_receipt(bad, stage) { return error('missing browser poll file accepted') }
	}
	if _ := verify_browser_poll_receipt(native_heartbeat_receipt_fixture()!, stage) { return error('native heartbeat receipt accepted by browser poll profile') }
	if _ := verify_native_heartbeat_receipt(receipt, stage) { return error('browser poll receipt accepted by native heartbeat profile') }
	if _ := verify_onboarding_framework_receipt(receipt, stage) { return error('browser poll receipt accepted by framework profile') }
	println('MAPS-BROWSER-POLL KERNEL-PROFILE-SELF-TEST PASS exact browser one-input delta two-file inventory eighteen inherited modules nineteen final thirty-six dependencies historical rejection')
}

fn account_pump_entries_fixture() []ServiceQueryEntry {
	return [ServiceQueryEntry{name: native_onboarding_trace_path, kind: 'regular', sha256: account_pump_pin, mode: 0o755},
		ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644},
		ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}]
}

fn account_pump_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in account_pump_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + native_onboarding_trace_path: account_pump_pin}))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'native_manifest_sha256']))!
	receipt['native_source_delta'] = json2.decode[json2.Any](json2.encode({'build-support/android/nativews/account_service.v': account_pump_source_pin}))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(account_pump_entries_fixture()))!
	return receipt
}

fn account_pump_profile_self_test() ! {
	profile := account_pump_profile()
	assert profile.baseline_sha == account_pump_boot_sha
	assert profile.modules.len == 19 && profile.modules.last() == 'maps-browser-poll.tar'
	assert account_pump_inputs().len == 38
	mut modules := profile.modules.clone()
	modules << profile.overlay
	assert modules.len == 20
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', browser_poll_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe account pump modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: account_pump_inputs(),
		original_modules_sha256: account_pump_modules(), preserved_modules_sha256: account_pump_modules()}
	receipt := account_pump_receipt_fixture()!
	verify_account_pump_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := account_pump_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_account_pump_receipt(bad, stage) { return error('changed account pump field accepted') }
		bad.delete(name)
		if _ := verify_account_pump_receipt(bad, stage) { return error('missing account pump field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_account_pump_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed account pump input accepted') }
		inputs.delete(path)
		if _ := verify_account_pump_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing account pump input accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unreviewed/sha256.json'] = '0'.repeat(64)
	if _ := verify_account_pump_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra account pump dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: browser_poll_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_account_pump_receipt(receipt, bad) { return error('wrong account pump module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + native_onboarding_trace_path: native_heartbeat_pin},
		{'/' + native_onboarding_trace_path: account_pump_pin, '/' + browser_poll_path: browser_poll_pin}] {
		mut bad := account_pump_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('unsafe account pump input delta accepted') }
	}
	for changed in [[]string{}, ['inputs_sha256'], ['inputs_sha256', 'browser_client_manifest_sha256'],
		['native_manifest_sha256', 'inputs_sha256'],
		['inputs_sha256', 'native_manifest_sha256', 'browser_client_manifest_sha256']] {
		mut bad := account_pump_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('unsafe account pump top-level delta accepted') }
	}
	for changed in [map[string]string{}, {'build-support/android/nativews/account_service.v': '0'.repeat(64)},
		{'build-support/android/nativews/account_service.v': account_pump_source_pin, 'build-support/android/nativews/core.v': '0'.repeat(64)}] {
		mut bad := account_pump_receipt_fixture()!
		bad['native_source_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('unsafe account pump source delta accepted') }
	}
	for name in ['headless_input_delta', 'headless_top_level_delta'] {
		mut bad := account_pump_receipt_fixture()!
		bad[name] = json2.decode[json2.Any](json2.encode([]string{}))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('account pump headless change accepted') }
	}
	entries := account_pump_entries_fixture()
	mut retained := account_pump_receipt_fixture()!
	mut retained_entries := entries.clone()
	retained_entries[0] = ServiceQueryEntry{...entries[0], sha256: native_heartbeat_pin}
	retained['deployment_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + native_onboarding_trace_path: native_heartbeat_pin}))!
	retained['overlay_inventory'] = json2.decode[json2.Any](json2.encode(retained_entries))!
	if _ := verify_account_pump_receipt(retained, stage) { return error('coherent retained account pump payload accepted') }
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := account_pump_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_account_pump_receipt(bad, stage) { return error('unsafe account pump inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: browser_poll_path, kind: 'regular', sha256: browser_poll_pin, mode: 0o644},
		ServiceQueryEntry{name: service_query_headless + '/native-build.json', kind: 'regular', sha256: account_pump_build, mode: 0o644},
		ServiceQueryEntry{name: service_query_jar_path, kind: 'regular', sha256: onboarding_framework_jar, mode: 0o644},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := account_pump_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('extra or duplicate account pump inode accepted') }
	}
	for removed_index in [0, 1] {
		mut changed := entries.clone()
		changed.delete(removed_index)
		mut bad := account_pump_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_pump_receipt(bad, stage) { return error('missing account pump file accepted') }
	}
	if _ := verify_account_pump_receipt(browser_poll_receipt_fixture()!, stage) { return error('browser poll receipt accepted by account pump profile') }
	if _ := verify_browser_poll_receipt(receipt, stage) { return error('account pump receipt accepted by browser poll profile') }
	if _ := verify_native_heartbeat_receipt(receipt, stage) { return error('account pump receipt accepted by native heartbeat profile') }
	println('MAPS-ACCOUNT-PUMP KERNEL-PROFILE-SELF-TEST PASS exact native source and one-input deployment delta two-file inventory nineteen inherited modules twenty final thirty-eight dependencies historical rejection')
}

fn application_restrictions_delta_fixture() map[string]string {
	mut delta := application_restrictions_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'd'.repeat(64)
	return delta
}

fn application_restrictions_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in application_restrictions_delta_fixture() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn application_restrictions_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in application_restrictions_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(application_restrictions_delta_fixture()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: application_restrictions_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(application_restrictions_entries_fixture()))!
	return receipt
}

fn application_restrictions_profile_self_test() ! {
	profile := application_restrictions_profile()
	if profile.baseline_sha != application_restrictions_boot_sha || profile.modules.len != 20
		|| profile.modules.last() != 'maps-account-pump.tar' || application_restrictions_inputs().len != 40 {
		return error('application restrictions positive profile fixture differs')
	}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	if modules.len != 21 { return error('application restrictions final module count differs') }
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', account_pump_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe application restrictions modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: application_restrictions_inputs(),
		original_modules_sha256: application_restrictions_modules(), preserved_modules_sha256: application_restrictions_modules()}
	receipt := application_restrictions_receipt_fixture()!
	verify_application_restrictions_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := application_restrictions_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('changed application restrictions field accepted') }
		bad.delete(name)
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('missing application restrictions field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_application_restrictions_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed application restrictions dependency accepted') }
		inputs.delete(path)
		if _ := verify_application_restrictions_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing application restrictions dependency accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unexpected/sha256.json'] = 'a'.repeat(64)
	if _ := verify_application_restrictions_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra application restrictions dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: account_pump_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_application_restrictions_receipt(receipt, bad) { return error('wrong application restrictions module inventory accepted') }
	}
	for changed in [map[string]string{}, {'/' + service_query_jar_path: onboarding_framework_jar},
		{'/' + service_query_jar_path: application_restrictions_jar, '/' + native_onboarding_trace_path: account_pump_pin}] {
		mut bad := application_restrictions_receipt_fixture()!
		bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('unsafe application restrictions headless delta accepted') }
	}
	for changed in [map[string]string{}, application_restrictions_known_delta()] {
		mut bad := application_restrictions_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('incomplete application restrictions deployment delta accepted') }
	}
	mut extra_delta := application_restrictions_delta_fixture()
	extra_delta['/' + native_onboarding_trace_path] = account_pump_pin
	mut extra_delta_receipt := application_restrictions_receipt_fixture()!
	extra_delta_receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(extra_delta))!
	if _ := verify_application_restrictions_receipt(extra_delta_receipt, stage) { return error('extra application restrictions deployment input accepted') }
	mut invalid_guest := application_restrictions_delta_fixture()
	invalid_guest['/' + service_query_headless + '/guest-inputs.json'] = 'invalid'
	mut invalid_guest_receipt := application_restrictions_receipt_fixture()!
	invalid_guest_receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(invalid_guest))!
	if _ := verify_application_restrictions_receipt(invalid_guest_receipt, stage) { return error('invalid application restrictions headless receipt digest accepted') }
	for name in ['headless_top_level_delta', 'deployment_top_level_delta'] {
		for changed in [[]string{}, ['inputs_sha256', 'native_manifest_sha256'], ['framework_manifest_sha256', 'inputs_sha256']] {
			mut bad := application_restrictions_receipt_fixture()!
			bad[name] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_application_restrictions_receipt(bad, stage) { return error('unsafe application restrictions top delta accepted') }
		}
	}
	entries := application_restrictions_entries_fixture()
	for path, old_pin in {
		'/' + service_query_jar_path: onboarding_framework_jar
		'/' + service_query_dex_path: onboarding_framework_dex
		'/' + service_query_headless + '/framework-build.json': onboarding_framework_build
		'/' + service_query_headless + '/framework-sha256.json': onboarding_framework_seal
		'/' + service_query_headless + '/guest-inputs.json': application_restrictions_retained_guest
	} {
		mut delta := application_restrictions_delta_fixture()
		delta[path] = old_pin
		mut inventory := entries.clone()
		for index, entry in inventory {
			if entry.name == path.trim_left('/') { inventory[index] = ServiceQueryEntry{...entry, sha256: old_pin} }
		}
		mut bad := application_restrictions_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(inventory))!
		if path == '/' + service_query_jar_path {
			bad['headless_input_delta'] = json2.decode[json2.Any](json2.encode({path: old_pin}))!
		}
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('coherent retained application restrictions payload accepted') }
	}
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: 0o755},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement == entry || (replacement.sha256 != entry.sha256 && entry.kind != 'regular') { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := application_restrictions_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_application_restrictions_receipt(bad, stage) { return error('unsafe application restrictions inode accepted') }
		}
	}
	for addition in [entries[0], ServiceQueryEntry{name: native_onboarding_trace_path, kind: 'regular', sha256: account_pump_pin, mode: 0o755},
		ServiceQueryEntry{name: browser_poll_path, kind: 'regular', sha256: browser_poll_pin, mode: 0o644},
		ServiceQueryEntry{name: 'opt/vinix-maps-account/bin/maps-account-guest', kind: 'regular', sha256: onboarding_trace_controller_pin, mode: 0o755},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := application_restrictions_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('extra or duplicate application restrictions inode accepted') }
	}
	for removed_index in 0 .. entries.len {
		if entries[removed_index].kind != 'regular' { continue }
		mut changed := entries.clone()
		changed.delete(removed_index)
		mut bad := application_restrictions_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_application_restrictions_receipt(bad, stage) { return error('missing application restrictions file accepted') }
	}
	if _ := verify_application_restrictions_receipt(account_pump_receipt_fixture()!, stage) { return error('account pump receipt accepted by application restrictions profile') }
	if _ := verify_account_pump_receipt(receipt, stage) { return error('application restrictions receipt accepted by account pump profile') }
	if _ := verify_onboarding_framework_receipt(receipt, stage) { return error('application restrictions receipt accepted by onboarding framework profile') }
	println('MAPS-APPLICATION-RESTRICTIONS KERNEL-PROFILE-SELF-TEST PASS exact five-input delta six-file inventory twenty inherited modules twenty-one final forty dependencies historical rejection')
}

fn account_handoff_entries_fixture() []ServiceQueryEntry {
	mut entries := []ServiceQueryEntry{}
	for path, pin in account_handoff_delta() {
		entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o755}
	}
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'c'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn account_handoff_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in account_handoff_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(account_handoff_delta()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(account_handoff_entries_fixture()))!
	return receipt
}

fn account_handoff_profile_self_test() ! {
	profile := account_handoff_profile()
	if profile.baseline_sha != account_handoff_boot_sha || profile.modules.len != 21
		|| profile.modules.last() != 'maps-application-restrictions.tar' || account_handoff_inputs().len != 43 {
		return error('account handoff positive profile fixture differs')
	}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	if modules.len != 22 { return error('account handoff final module count differs') }
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', application_restrictions_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe account handoff modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: account_handoff_inputs(),
		original_modules_sha256: account_handoff_modules(), preserved_modules_sha256: account_handoff_modules()}
	receipt := account_handoff_receipt_fixture()!
	verify_account_handoff_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := account_handoff_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_account_handoff_receipt(bad, stage) { return error('changed account handoff field accepted') }
		bad.delete(name)
		if _ := verify_account_handoff_receipt(bad, stage) { return error('missing account handoff field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_account_handoff_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed account handoff dependency accepted') }
		inputs.delete(path)
		if _ := verify_account_handoff_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing account handoff dependency accepted') }
	}
	mut extra_inputs := stage.inputs_sha256.clone()
	extra_inputs['/unreviewed/sha256.json'] = '0'.repeat(64)
	if _ := verify_account_handoff_receipt(receipt, Stage{...stage, inputs_sha256: extra_inputs}) { return error('extra account handoff dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: application_restrictions_modules()},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_account_handoff_receipt(receipt, bad) { return error('wrong account handoff module inventory accepted') }
	}
	mut extra_delta := account_handoff_delta()
	extra_delta['/' + native_onboarding_trace_path] = account_pump_pin
	for changed in [map[string]string{}, controller_delta(), extra_delta] {
		mut bad := account_handoff_receipt_fixture()!
		bad['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_handoff_receipt(bad, stage) { return error('unsafe account handoff input delta accepted') }
	}
	for changed in [[]string{}, ['inputs_sha256', 'framework_manifest_sha256'],
		['inputs_sha256', 'native_manifest_sha256'], ['inputs_sha256', 'browser_client_manifest_sha256']] {
		mut bad := account_handoff_receipt_fixture()!
		bad['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_handoff_receipt(bad, stage) { return error('unsafe account handoff top-level delta accepted') }
	}
	for name in ['headless_input_delta', 'headless_top_level_delta'] {
		mut bad := account_handoff_receipt_fixture()!
		bad[name] = json2.decode[json2.Any](json2.encode([]string{}))!
		if _ := verify_account_handoff_receipt(bad, stage) { return error('account handoff headless declaration accepted') }
	}
	entries := account_handoff_entries_fixture()
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.mode == 0o755 { u32(0o644) } else { u32(0o755) }},
			ServiceQueryEntry{...entry, sha256: if entry.name == service_query_deployment { 'invalid' } else { '0'.repeat(64) }}] {
			if replacement.sha256 != entry.sha256 && entry.kind != 'regular' { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := account_handoff_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_account_handoff_receipt(bad, stage) { return error('unsafe account handoff inode accepted') }
		}
		if entry.kind != 'regular' { continue }
		mut missing := entries.clone()
		missing.delete(index)
		mut bad := account_handoff_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(missing))!
		if _ := verify_account_handoff_receipt(bad, stage) { return error('missing account handoff file accepted') }
	}
	for addition in [entries[0], ServiceQueryEntry{name: browser_poll_path, kind: 'regular', sha256: browser_poll_pin, mode: 0o644},
		ServiceQueryEntry{name: service_query_jar_path, kind: 'regular', sha256: application_restrictions_jar, mode: 0o644},
		ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := account_handoff_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_account_handoff_receipt(bad, stage) { return error('extra or duplicate account handoff inode accepted') }
	}
	mut retained_entries := entries.clone()
	for index, entry in entries {
		if entry.name == service_query_deployment {
			retained_entries[index] = ServiceQueryEntry{...entry, sha256: account_handoff_retained_deployment}
		}
	}
	mut retained := account_handoff_receipt_fixture()!
	retained['overlay_inventory'] = json2.decode[json2.Any](json2.encode(retained_entries))!
	if _ := verify_account_handoff_receipt(retained, stage) { return error('retained account handoff deployment receipt accepted') }
	if _ := verify_account_handoff_receipt(application_restrictions_receipt_fixture()!, stage) { return error('application restrictions receipt accepted by account handoff profile') }
	if _ := verify_application_restrictions_receipt(receipt, stage) { return error('account handoff receipt accepted by application restrictions profile') }
	println('MAPS-ACCOUNT-HANDOFF KERNEL-PROFILE-SELF-TEST PASS exact broker and controller aliases four-file inventory twenty-one inherited modules twenty-two final forty-three dependencies inherited runtime and historical rejection')
}

fn auth_exception_entries_fixture() []ServiceQueryEntry {
	mut pins := auth_exception_known_delta()
	pins['/' + service_query_headless + '/guest-inputs.json'] = 'c'.repeat(64)
	mut entries := []ServiceQueryEntry{}
	for path, pin in pins { entries << ServiceQueryEntry{name: path.trim_left('/'), kind: 'regular', sha256: pin, mode: 0o644} }
	entries << ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'd'.repeat(64), mode: 0o644}
	entries << ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}
	return entries
}

fn auth_exception_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in auth_exception_fields() { receipt[name] = json2.Any(value) }
	mut delta := auth_exception_known_delta()
	delta['/' + service_query_headless + '/guest-inputs.json'] = 'c'.repeat(64)
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(delta))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'framework_manifest_sha256']))!
	receipt['headless_input_delta'] = json2.decode[json2.Any](json2.encode({'/' + service_query_jar_path: auth_exception_jar}))!
	receipt['headless_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256']))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(auth_exception_entries_fixture()))!
	return receipt
}

fn auth_exception_profile_self_test() ! {
	profile := auth_exception_profile()
	if profile.baseline_sha != auth_exception_boot_sha || profile.modules.len != 22
		|| profile.modules.last() != 'maps-account-handoff.tar' || auth_exception_inputs().len != 45 { return error('auth exception positive profile differs') }
	mut modules := profile.modules.clone()
	modules << profile.overlay
	if modules.len != 23 { return error('auth exception final module count differs') }
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', account_handoff_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe auth exception modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: auth_exception_inputs(), original_modules_sha256: auth_exception_modules(), preserved_modules_sha256: auth_exception_modules()}
	receipt := auth_exception_receipt_fixture()!
	verify_auth_exception_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := auth_exception_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_auth_exception_receipt(bad, stage) { return error('changed auth exception field accepted') }
		bad.delete(name)
		if _ := verify_auth_exception_receipt(bad, stage) { return error('missing auth exception field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_auth_exception_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed auth exception dependency accepted') }
		inputs.delete(path)
		if _ := verify_auth_exception_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing auth exception dependency accepted') }
	}
	mut extra := stage.inputs_sha256.clone()
	extra['/unexpected/sha256.json'] = '0'.repeat(64)
	if _ := verify_auth_exception_receipt(receipt, Stage{...stage, inputs_sha256: extra}) { return error('extra auth exception dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: account_handoff_modules()}, Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_auth_exception_receipt(receipt, bad) { return error('wrong auth exception module inventory accepted') }
	}
	entries := auth_exception_entries_fixture()
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.kind == 'regular' { u32(0o755) } else { u32(0o644) }}, ServiceQueryEntry{...entry, sha256: 'invalid'}] {
			if entry.kind != 'regular' && replacement.sha256 != entry.sha256 { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := auth_exception_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_auth_exception_receipt(bad, stage) { return error('unsafe auth exception inode accepted') }
		}
		if entry.kind != 'regular' { continue }
		mut missing := entries.clone()
		missing.delete(index)
		mut bad := auth_exception_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(missing))!
		if _ := verify_auth_exception_receipt(bad, stage) { return error('missing auth exception file accepted') }
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755},
		ServiceQueryEntry{name: account_handoff_broker_path, kind: 'regular', sha256: account_handoff_broker_pin, mode: 0o755}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := auth_exception_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_auth_exception_receipt(bad, stage) { return error('extra auth exception inode accepted') }
	}
	if _ := verify_auth_exception_receipt(account_handoff_receipt_fixture()!, stage) { return error('historical handoff receipt accepted by auth exception profile') }
	if _ := verify_account_handoff_receipt(receipt, stage) { return error('auth exception receipt accepted by handoff profile') }
	println('MAPS-AUTH-EXCEPTION KERNEL-PROFILE-SELF-TEST PASS exact framework six-file inventory five-input delta twenty-two inherited modules twenty-three final forty-five dependencies retained roles historical rejection')
}

fn auth_worker_entries_fixture() []ServiceQueryEntry {
	return [ServiceQueryEntry{name: native_onboarding_trace_path, kind: 'regular', sha256: auth_worker_pin, mode: 0o755},
		ServiceQueryEntry{name: service_query_deployment, kind: 'regular', sha256: 'd'.repeat(64), mode: 0o644},
		ServiceQueryEntry{name: 'opt', kind: 'directory', mode: 0o755}]
}
fn auth_worker_receipt_fixture() !map[string]json2.Any {
	mut receipt := map[string]json2.Any{}
	for name, value in auth_worker_fields() { receipt[name] = json2.Any(value) }
	receipt['deployment_input_delta'] = json2.decode[json2.Any](json2.encode(auth_worker_delta()))!
	receipt['deployment_top_level_delta'] = json2.decode[json2.Any](json2.encode(['inputs_sha256', 'native_manifest_sha256']))!
	receipt['native_source_delta'] = json2.decode[json2.Any](json2.encode({'build-support/android/nativews/account_service.v': auth_worker_service_source,
		'build-support/android/nativews/account_worker.v': auth_worker_added_source}))!
	receipt['overlay_inventory'] = json2.decode[json2.Any](json2.encode(auth_worker_entries_fixture()))!
	return receipt
}
fn auth_worker_profile_self_test() ! {
	profile := auth_worker_profile()
	if profile.baseline_sha != auth_worker_boot_sha || profile.modules.len != 23 || profile.modules.last() != 'maps-auth-exception.tar' || auth_worker_inputs().len != 47 {
		return error('auth worker positive profile fixture differs')
	}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	if modules.len != 24 { return error('auth worker final module count differs') }
	verify_modules(profile, Config{'vinix', profile.modules}, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()}, Config{'vinix', auth_exception_profile().modules}, Config{'other', modules}] {
		if _ := verify_modules(profile, Config{'vinix', profile.modules}, bad) { return error('unsafe auth worker modules accepted') }
	}
	stage := Stage{format: 1, inputs_sha256: auth_worker_inputs(), original_modules_sha256: auth_worker_modules(), preserved_modules_sha256: auth_worker_modules()}
	receipt := auth_worker_receipt_fixture()!
	verify_auth_worker_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := auth_worker_receipt_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_auth_worker_receipt(bad, stage) { return error('changed auth worker field accepted') }
		bad.delete(name)
		if _ := verify_auth_worker_receipt(bad, stage) { return error('missing auth worker field accepted') }
	}
	for path in stage.inputs_sha256.keys() {
		mut inputs := stage.inputs_sha256.clone()
		inputs[path] = '0'.repeat(64)
		if _ := verify_auth_worker_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('changed auth worker dependency accepted') }
		inputs.delete(path)
		if _ := verify_auth_worker_receipt(receipt, Stage{...stage, inputs_sha256: inputs}) { return error('missing auth worker dependency accepted') }
	}
	mut extra := stage.inputs_sha256.clone()
	extra['/unreviewed/sha256.json'] = '0'.repeat(64)
	if _ := verify_auth_worker_receipt(receipt, Stage{...stage, inputs_sha256: extra}) { return error('extra auth worker dependency accepted') }
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: auth_exception_modules()}, Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_auth_worker_receipt(receipt, bad) { return error('wrong auth worker module inventory accepted') }
	}
	for field in ['headless_input_delta', 'headless_top_level_delta'] {
		mut bad := auth_worker_receipt_fixture()!
		bad[field] = json2.decode[json2.Any](json2.encode([]string{}))!
		if _ := verify_auth_worker_receipt(bad, stage) { return error('auth worker headless declaration accepted') }
	}
	entries := auth_worker_entries_fixture()
	for index, entry in entries {
		for replacement in [ServiceQueryEntry{...entry, kind: 'symlink'}, ServiceQueryEntry{...entry, mode: 0o777},
			ServiceQueryEntry{...entry, mode: if entry.name == native_onboarding_trace_path { u32(0o644) } else { u32(0o755) }}, ServiceQueryEntry{...entry, sha256: 'invalid'}] {
			if replacement == entry || (entry.kind != 'regular' && replacement.sha256 != entry.sha256) { continue }
			mut changed := entries.clone()
			changed[index] = replacement
			mut bad := auth_worker_receipt_fixture()!
			bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
			if _ := verify_auth_worker_receipt(bad, stage) { return error('unsafe auth worker inode accepted') }
		}
		if entry.kind != 'regular' { continue }
		mut missing := entries.clone()
		missing.delete(index)
		mut bad := auth_worker_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(missing))!
		if _ := verify_auth_worker_receipt(bad, stage) { return error('missing auth worker file accepted') }
	}
	for addition in [entries[0], ServiceQueryEntry{name: 'extra', kind: 'directory', mode: 0o755}, ServiceQueryEntry{name: 'opt/../escape', kind: 'directory', mode: 0o755},
		ServiceQueryEntry{name: service_query_jar_path, kind: 'regular', sha256: auth_exception_jar, mode: 0o644}] {
		mut changed := entries.clone()
		changed << addition
		mut bad := auth_worker_receipt_fixture()!
		bad['overlay_inventory'] = json2.decode[json2.Any](json2.encode(changed))!
		if _ := verify_auth_worker_receipt(bad, stage) { return error('extra auth worker inode accepted') }
	}
	if _ := verify_auth_worker_receipt(auth_exception_receipt_fixture()!, stage) { return error('historical exception receipt accepted by worker profile') }
	if _ := verify_auth_exception_receipt(receipt, stage) { return error('worker receipt accepted by exception profile') }
	println('MAPS-AUTH-WORKER KERNEL-PROFILE-SELF-TEST PASS exact native two-file inventory one-input delta twenty-three inherited modules twenty-four final forty-seven dependencies retained roles historical rejection')
}

fn self_test() ! {
	protected_profile_self_test()!
	controller_profile_self_test()!
	service_query_profile_self_test()!
	controller_memory_profile_self_test()!
	direct_boot_profile_self_test()!
	context_storage_profile_self_test()!
	broadcast_result_profile_self_test()!
	onboarding_trace_profile_self_test()!
	native_onboarding_trace_profile_self_test()!
	onboarding_framework_profile_self_test()!
	native_heartbeat_profile_self_test()!
	browser_poll_profile_self_test()!
	account_pump_profile_self_test()!
	application_restrictions_profile_self_test()!
	account_handoff_profile_self_test()!
	auth_exception_profile_self_test()!
	auth_worker_profile_self_test()!
	maps := maps_profile()
	before := Config{'vinix', maps.modules}
	mut modules := maps.modules.clone()
	modules << maps.overlay
	verify_modules(maps, before, Config{'vinix', modules})!
	mut wrong_overlay := maps.modules.clone()
	wrong_overlay << 'browser-probe.tar'
	for bad in [Config{'vinix', maps.modules},
		Config{'vinix', modules.reverse()},
		Config{'vinix', wrong_overlay},
		Config{'other', modules}] {
		if _ := verify_modules(maps, before, bad) {
			return error('altered Maps module profile accepted')
		}
	}
	if _ := verify_modules(maps, Config{'vinix', ['runtime.tar']},
		Config{'vinix', ['runtime.tar', maps.overlay]}) {
		return error('unaudited Maps baseline modules accepted')
	}
	config := '/Vinix\n kernel_path: boot():/boot/vinix\n module_path: boot():/boot/runtime.tar\n'
	assert configure(config)!.modules == ['runtime.tar']
	for bad in [config + '/Other\n', config + ' kernel_path: boot():/boot/vinix\n',
		config + ' module_path: boot():/boot/runtime.tar\n', config.replace('/vinix', '/../vinix'),
		config.replace('/runtime.tar', '/runtime')] {
		if _ := configure(bad) { return error('ambiguous or unsafe configuration accepted') }
	}
	assert !relative('../escape') && !relative('a//b') && !digest_valid('a'.repeat(63))
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-browser-kernel-patch-' + os.getpid().str())
	if os.exists(root) { return error('self-test path exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	hash_self_test(root)!
	os.write_file(root + '/payload', 'exact frozen input\x00bytes')!
	verify_inventory(root, Inventory{ files: {
		'payload': hash(root + '/payload')!
	} })!
	for bad in [Inventory{}, Inventory{ files: {
		'../escape': hash(root + '/payload')!
	} }, Inventory{ files: {
		'payload': '0'.repeat(64)
	} }] {
		if _ := verify_inventory(root, bad) { return error('invalid frozen inventory accepted') }
	}
	os.symlink('payload', root + '/link')!
	if _ := verify_inventory(root, Inventory{ files: {
		'link': hash(root + '/payload')!
	} }) {
		return error('symlink substituted for regular frozen input')
	}
	unlaunched(root)!
	os.write_file(root + '/launch.json', '{}')!
	if _ := unlaunched(root) { return error('historical launched stage accepted') }
	fat_self_test(root + '/browser', 'browser-probe.tar', ['runtime.tar'])!
	fat_self_test(root + '/maps', 'maps-account.tar', ['runtime.tar'])!
	fat_self_test(root + '/protected-maps', 'protected-storage-diagnostic.tar', protected_maps_profile().modules)!
	fat_self_test(root + '/controller', 'maps-controller-diagnostic.tar', controller_profile().modules)!
	fat_self_test(root + '/service-query', 'maps-service-query-diagnostic.tar', service_query_profile().modules)!
	fat_self_test(root + '/controller-memory', 'maps-controller-memory-diagnostic.tar', controller_memory_profile().modules)!
	fat_self_test(root + '/direct-boot', 'maps-direct-boot-diagnostic.tar', direct_boot_profile().modules)!
	fat_self_test(root + '/context-storage', 'maps-context-storage-diagnostic.tar', context_storage_profile().modules)!
	fat_self_test(root + '/broadcast-result', 'maps-broadcast-result-diagnostic.tar', broadcast_result_profile().modules)!
	fat_self_test(root + '/onboarding-trace', 'maps-onboarding-trace-diagnostic.tar', onboarding_trace_profile().modules)!
	fat_self_test(root + '/native-onboarding-trace', 'maps-native-onboarding-trace-diagnostic.tar', native_onboarding_trace_profile().modules)!
	fat_self_test(root + '/onboarding-framework', 'maps-onboarding-framework-diagnostic.tar', onboarding_framework_profile().modules)!
	fat_self_test(root + '/native-heartbeat', 'maps-native-heartbeat-diagnostic.tar', native_heartbeat_profile().modules)!
	fat_self_test(root + '/browser-poll', 'maps-browser-poll.tar', browser_poll_profile().modules)!
	fat_self_test(root + '/account-pump', 'maps-account-pump.tar', account_pump_profile().modules)!
	fat_self_test(root + '/application-restrictions', 'maps-application-restrictions.tar', application_restrictions_profile().modules)!
	fat_self_test(root + '/account-handoff', 'maps-account-handoff.tar', account_handoff_profile().modules)!
	println('BROWSER-KERNEL-PATCH SELF-TEST PASS configuration inventory digest symlink launched-stage guards')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	is_maps := os.args.len == 5 && os.args[1] == '--maps-account'
	is_protected := os.args.len == 5 && os.args[1] == '--protected-storage-maps'
	is_controller := os.args.len == 5 && os.args[1] == '--maps-controller'
	is_service_query := os.args.len == 5 && os.args[1] == '--maps-service-query'
	is_controller_memory := os.args.len == 5 && os.args[1] == '--maps-controller-memory'
	is_direct_boot := os.args.len == 5 && os.args[1] == '--maps-direct-boot'
	is_context_storage := os.args.len == 5 && os.args[1] == '--maps-context-storage'
	is_broadcast_result := os.args.len == 5 && os.args[1] == '--maps-broadcast-result'
	is_onboarding_trace := os.args.len == 5 && os.args[1] == '--maps-onboarding-trace'
	is_native_onboarding_trace := os.args.len == 5 && os.args[1] == '--maps-native-onboarding-trace'
	is_onboarding_framework := os.args.len == 5 && os.args[1] == '--maps-onboarding-framework'
	is_native_heartbeat := os.args.len == 5 && os.args[1] == '--maps-native-heartbeat'
	is_browser_poll := os.args.len == 5 && os.args[1] == '--maps-browser-poll'
	is_account_pump := os.args.len == 5 && os.args[1] == '--maps-account-pump'
	is_application_restrictions := os.args.len == 5 && os.args[1] == '--maps-application-restrictions'
	is_account_handoff := os.args.len == 5 && os.args[1] == '--maps-account-handoff'
	is_auth_exception := os.args.len == 5 && os.args[1] == '--maps-auth-exception'
	is_auth_worker := os.args.len == 5 && os.args[1] == '--maps-auth-worker'
	is_selected := is_maps || is_protected || is_controller || is_service_query || is_controller_memory || is_direct_boot || is_context_storage || is_broadcast_result || is_onboarding_trace || is_native_onboarding_trace || is_onboarding_framework || is_native_heartbeat || is_browser_poll || is_account_pump || is_application_restrictions || is_account_handoff || is_auth_exception || is_auth_worker
	if os.args.len != 4 && !is_selected {
		eprintln('usage: patch-kernel [--maps-account|--protected-storage-maps|--maps-controller|--maps-service-query|--maps-controller-memory|--maps-direct-boot|--maps-context-storage|--maps-broadcast-result|--maps-onboarding-trace|--maps-native-onboarding-trace|--maps-onboarding-framework|--maps-native-heartbeat|--maps-browser-poll|--maps-account-pump|--maps-application-restrictions|--maps-account-handoff|--maps-auth-exception|--maps-auth-worker] FRESH_STAGE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256')
		exit(2)
	}
	offset := if is_selected { 1 } else { 0 }
	root := external(os.args[1 + offset]) or {
		eprintln(err)
		exit(1)
	}
	build_root := external(os.args[2 + offset]) or {
		eprintln(err)
		exit(1)
	}
	profile := if is_auth_worker { auth_worker_profile() } else if is_auth_exception { auth_exception_profile() } else if is_account_handoff { account_handoff_profile() } else if is_application_restrictions { application_restrictions_profile() } else if is_account_pump { account_pump_profile() } else if is_browser_poll { browser_poll_profile() } else if is_native_heartbeat { native_heartbeat_profile() } else if is_onboarding_framework { onboarding_framework_profile() } else if is_native_onboarding_trace { native_onboarding_trace_profile() } else if is_onboarding_trace { onboarding_trace_profile() } else if is_broadcast_result { broadcast_result_profile() } else if is_context_storage { context_storage_profile() } else if is_direct_boot { direct_boot_profile() } else if is_controller_memory { controller_memory_profile() } else if is_service_query { service_query_profile() } else if is_controller { controller_profile() } else if is_protected { protected_maps_profile() } else if is_maps { maps_profile() } else { browser_profile() }
	patch(root, build_root, os.args[3 + offset], profile) or {
		eprintln(err)
		exit(1)
	}
}
