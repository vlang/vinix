// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone child-attach / Settings.Global ART regressions. No account IPC.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.fork() i32
fn C.setpgid(i32, i32) i32
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.chown(&char, i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)
fn C.fcntl(i32, i32, ...i32) i32
fn C.open(&char, i32, ...voidptr) i32

// Sealed child-attach + Settings.Global successor; signed fixture identities below.
const framework_sha = 'e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd'
const ready_marker = 'ANDROID-WS-READY backend=vinix-native'
// Existing two-file generic fixture wire format, accepted by the reconstructor.
const serial_prefix = 'VINIX-SERVICE-QUERY-RESULTS-1 '
const log_limit = 4 * 1024 * 1024
const line_limit = 8192
const auth_worker_native_sha = '0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136'
const binder_identity_native_sha = '6a87d8c2fd003c55cb572ab397342d0c39aa54376ffe7a5a2ba2fa4592099eae'
const binder_identity_framework_sha = '3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636'
const maps_network_v3_apk_sha = 'bd07eddf7594fd6cc6b90b984baf7ee5855af0fc56ee0322fbc45ea318cf393a'
const service_lifecycle_framework_sha = '7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74'
const service_lifecycle_native_sha = 'ea8b899971ac96335c1f53a32eb3dee8e5e8f87600c0bcd5b7edaa683b9a8136'
const service_lifecycle_apk_sha = 'd15082450bbc70efc761ec8403e5544e40a98efe3f0a3d69b75b9d142e25b283'
// Distinct platform-fragment fixture and verified coupled runtime identities.
const platform_fragments_framework_sha = '6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4'
const platform_fragments_native_sha = '613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c'
const platform_fragments_apk_sha = 'f2e08f444782607a408bd25766da399100e908cf2b99edeebcfb80d267dc21de'
const platform_fragments_pass_marker = 'PLATFORM-FRAGMENTS-PASS stable-manager tagged-queue fifo-once application-injection lifecycle-order late-add host-isolation callback-identity'
// ImageView properties use their separately signed fixture and coupled runtime.
const image_bounds_framework_sha = '9cfdbeaff047b693837508c3f7676510a63c05af118e864964b4b432fb813af9'
const image_bounds_native_sha = 'fd38d7f8e3c0d17934617242cb95b0412a0c6ed676cb4454e5a52c8cf494dc2c'
const image_bounds_apk_sha = '7d11a0e6d71b6c556a57f84fd5f27610157f0a49735282f0bb31aaac0ff00a62'
const image_bounds_pass_marker = 'IMAGE-BOUNDS-PASS defaults setters axis-isolation instance-isolation styled-dimensions'
// Window attributes use their own fixture and newly coupled runtime inputs.
const window_system_ui_framework_sha = '3f0d220a24e7d91a47f7b2d42cd5620aa498981e915a90cdbd806164b8ef0fc1'
const window_system_ui_native_sha = 'c97862ecb4eba730290a832b2766d58c1552ddf58ae40f77d7e140e69538ce75'
const window_system_ui_apk_sha = 'af7f9bfcb8f106c43f9d86badfa2c5e0deb49e3a1e6da19cbe68ab6a5254ca90'
const window_system_ui_pass_marker = 'WINDOW-SYSTEM-UI-PASS defaults field-shape bitmasks instance-isolation window-attributes'
// Unseeded account options use the explicit corrected runtime pair.
const seed_account_options_framework_sha = 'cb2e3fabab652c65351da16770ae98c4113781df0830440b734395bb35b6f265'
const seed_account_options_native_sha = '179f51ad25cc99fd939ca1f217e87f1d3ab9c452b98db861da11e0344363f6ce'
const seed_account_options_apk_sha = '36c87d606306c799f50771ab0bed5cacdf07603e96f3e85b6c4aab4870f1f333'
const seed_account_options_pass_marker = 'SEED-ACCOUNT-OPTIONS-PASS unseeded-null service-lookup method-shape empty-singleton immutable-empty null-branch'
// Unsupported persistent storage is absent through both service lookup forms.
const persistent_data_block_framework_sha = '7c1b2fa03924003c7717e07ef463bff81c6429c7667b2bc42d35954fb6d41752'
const persistent_data_block_native_sha = '192411171dec072c89a64a81d8b35f36e92d060c75505fadceb47d683e9ed2e5'
const persistent_data_block_apk_sha = '0acd05b909c7c2d3b798cb515a799df8c40263af9be1e7ab4334f7b4f113b7a8'
const persistent_data_block_pass_marker = 'PERSISTENT-DATA-BLOCK-PASS class-shape named-null typed-null null-cast user-service seed-options immutable-empty'
// Bitmap tiling uses its signed pixel fixture and freshly coupled native sampler.
const bitmap_tiles_framework_sha = '741641c30098cf2f682672889c7ac653c6b2f23b9c09001a7af8f56bb01d9500'
const bitmap_tiles_native_sha = '6969a813fbfe69cd882f3cb47760cb09cb106ca9aad748ea67ab93967aacad20'
const bitmap_tiles_apk_sha = 'd4aedf04a871758249fbea08e79a7ac49f9fdb2eb98f915f6a7c8ee389fede7c'
const bitmap_tiles_pass_marker = 'BITMAP-TILES-PASS modes reset invalidation stable-paint pixels-repeat-mirror-clamp nullable-axis'
// Read-only network observations use the same bitmap runtime, without assertions of connectivity.
const connectivity_truth_apk_sha = 'e562c6344c8560908a5d5cd70fa0480d76ea60ba6929e0720a2fbe69abba943d'
const connectivity_truth_pass_marker = 'CONNECTIVITY-TRUTH-PASS observations active-info active-network all-networks capabilities interfaces raw-native'
// Window animation resource attributes and callbacks use their own exact pair.
const window_animations_framework_sha = '255718e8a943f8d3e276f99694c52ed5ec39af86d5d06abef3c9b14d7b9aa197'
const window_animations_native_sha = 'a1f27a68285dfe6d5cef34ad077bde7537ee41c136fd40d82ad42e14097377ba'
const window_animations_apk_sha = 'b78a43516d2f5f42ec7686c39acd81b3612402d80eb25ccd854de512fd6119a6'
const window_animations_pass_marker = 'WINDOW-ANIMATIONS-PASS attributes alias always-dispatch callbacks reentrancy exceptions activity dialog'
// Layout getters expose retained constructor alignment and additive spacing.
const layout_alignment_framework_sha = '162c77f853e6cb85f373493c40c302ff4df5b90ed52f2e6dce961e5e17281d01'
const layout_alignment_native_sha = 'b6aeb06b7473220da8844015a253ed87394fef6209173c14317fcbaf19141e95'
const layout_alignment_apk_sha = 'd0a5f8524c5d135cce08705946d72487947b637b0d7c1c7fa77994a323111fd6'
const layout_alignment_pass_marker = 'LAYOUT-ALIGNMENT-PASS enums nullable constructors identity spacing-bits builder-retained'
// Current-user restrictions use the new framework and verified retained native.
const user_restrictions_framework_sha = '646a83ea74795fb29b4db8811fc3249add3693b6e2de03e043c52e4e13b09bdc'
const user_restrictions_native_sha = 'b6aeb06b7473220da8844015a253ed87394fef6209173c14317fcbaf19141e95'
const user_restrictions_apk_sha = '19f8715bcc6e5f19dff1dc11e031912907d7c762a7f1927b85dda697f447dbea'
const user_restrictions_pass_marker = 'USER-RESTRICTIONS-PASS fresh-snapshots bundle-truth virtual-backend mutation-isolation exceptions context-controls'
// Boolean null-key repair and absent CrossProfileApps service share this SDK.
const bundle_cross_profile_framework_sha = '3ebf88615dcb87ec103b098a0baf397f5a4428623f809fd139b23e9f60978235'
const bundle_cross_profile_apk_sha = 'c781769a0ef5fd5357ae1f678d52ef98a2532a5ae07c155a013e278a7b2248ab'
const bundle_cross_profile_pass_marker = 'BUNDLE-BOOLEAN-PASS null-keys defaults stored-values nonmutating ordinary-keys legacy-control cross-profile-absent'
// Resource floats require their signed fixture and exact coupled runtime pair.
const resources_float_framework_sha = 'aac12a41b70ce34c0893580431a28de81cb3476e7c6833cbe0c0ca8596db677d'
const resources_float_native_sha = '441ae035ec4b69c36635cc4521af3fafcb6a867305b0ba25d6e55df7ff0dadc9'
const resources_float_apk_sha = '59439180e4b2bff8c533689db5e4f6ba121406a3cb4950b3746f170a960a7d93'
const resources_float_pass_marker = 'RESOURCES-FLOAT-PASS packaged-floats aliases strict-types virtual-lookup raw-bits unchanged-values failures'
// PaintDrawable adds one API class over the verified Resources/native pair.
const paint_drawable_framework_sha = 'b3fed7d846a23d9e8afc1256e5bfa7d9ebcd1ba5330705d40fd14131291d516c'
const paint_drawable_apk_sha = 'cd459b703196920a7e07e1bfdb7d43e304c1115b12b1ad0998281fab1ea64868'
const paint_drawable_pass_marker = 'PAINT-DRAWABLE-PASS constructors corners invalidation arrays pixels inflation canvas-state'
// Dialog theme resolution requires its dedicated fixture and coupled pair.
const dialog_theme_framework_sha = '9d8d2b1f59f80bf0d704daa65eaf3b479fa83458338f23d9fe17aa7a57b541b6'
const dialog_theme_native_sha = '280730c4166687394cf69e548cdd106e58c57ba9472f339dde2c80ebdee2595a'
const dialog_theme_apk_sha = '57e1bc1d8f1df2874be1c4837f169176e5fa88310f37ea99fd726c5f839a2161'
const dialog_theme_pass_marker = 'DIALOG-THEME-PASS explicit default inherited contexts inflation isolation missing-default'
// Intent extras use the successor framework and verified retained native.
const intent_extras_framework_sha = '02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20'
const intent_extras_apk_sha = 'b3e0278a185bb3f7f1a302c2f515fa7a4b98edf4cfcefd69ede3f45f85a5ba2c'
const intent_extras_pass_marker = 'INTENT-EXTRAS-PASS merge precedence copies no-op nulls shallow controlled-intent'
// Resource synchronization uses the retained Intent framework and its corrected native.
const resource_locks_framework_sha = '02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20'
const resource_locks_native_sha = 'aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7'
const resource_locks_apk_sha = 'eedcc5a40c86f2f6131121e922a7625e416f5df68671baa70cea581246c3e55e'
const resource_locks_pass_marker = 'RESOURCE-LOCKS-PASS workers=4 iterations=64 ids names strings arrays bags themes same-app-copy cross-framework-copy configuration paths owned-asset owned-directory'
// PendingIntent tokens use their successor framework and retained resource-lock native.
const pending_intent_framework_sha = 'bc82567de6d8abd6a4084c68e0e4c698df12d2c7848c7d23b6af7e5d0e6df7cc'
const pending_intent_native_sha = 'aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7'
const pending_intent_apk_sha = '24ee07ce193fbde0ee448aeceee70a6013095301cbb6b487c9e61aaf175a9456'
const pending_intent_pass_marker = 'PENDING-INTENT-PASS no-create identity send fill-in update cancel one-shot immutable parcel service recovery broadcast cleanup'
// Stable display dimensions require their successor framework and native framebuffer query.
const stable_display_framework_sha = '3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52'
const stable_display_native_sha = '364f76761b57da6e0674d9a0c20f85e2589e5b8705d22aac6e6c3a9b82f8fcae'
const stable_display_apk_sha = '190b832396158ce1ac584ef41abf279d6f13b82b001d17c35e2bd711d5ebcee1'
const stable_display_pass_marker = 'STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation'
// Asset locale enumeration uses its successor framework and real native asset manager.
const asset_locales_framework_sha = '43e3e2b941677cda70021ae9cd674aac6f4897af4ab4bda1d2d751b805d1f137'
const asset_locales_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const asset_locales_apk_sha = '03877624fde8928fac5efb3a2c49d9306356f5cb1488c3fa343799a39044a265'
const asset_locales_pass_marker = 'ASSET-LOCALES-PASS framework-app canonical-set fresh-arrays mutation-isolation default-locale device-secure'
// Unmanaged state queries use their successor framework and verified native pair.
const unmanaged_queries_framework_sha = '25500d52cf7c03a2a1c82656c00284c507dbdb03cff546dbc6e5840aa45b5c1c'
const unmanaged_queries_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const unmanaged_queries_apk_sha = 'dcea26199cfb0bfc2b0b44126b45923c717893b3670f1788b60c4038d4213400'
const unmanaged_queries_pass_marker = 'UNMANAGED-QUERIES-PASS owner-null profile-false service-lookups restrictions-defaults snapshots repeated-queries'
// StatsManager linkage uses its successor framework and verified native pair.
const stats_unavailable_framework_sha = '86d1cc8dc592082aeb837fd260e36a4a0c93bbe5a23e3f22e4f97b5ba09e7ffd'
const stats_unavailable_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const stats_unavailable_apk_sha = 'a0742e010e52dd042500a6811fddc6fe369b28852a85bfd22987dbb0c894a4dc'
const stats_unavailable_pass_marker = 'STATS-UNAVAILABLE-PASS class-identity string-null typed-null early-returns dormant-references service-fallback repeated-queries'
// Subscription service queries use their successor framework and verified native pair.
const subscription_service_framework_sha = '72c57e05b4458d8c62f82cd29fe70065318303af6b741bf1726337ce922c60ef'
const subscription_service_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const subscription_service_apk_sha = 'c841324557b839b051bceb8f847d9e943cb69139ebe09d0422b13938164853e5'
const subscription_service_pass_marker = 'SUBSCRIPTION-SERVICE-PASS service-identity null-list null-info unavailable-phone zero-modems fresh-bound-wrappers dormant-getters fallback-controls'
// Autofill component queries use their successor framework and verified native pair.
const autofill_service_framework_sha = 'e2bea62dcd6f59269c36612f76b806942018700f37fbf202915cc2e74329a54a'
const autofill_service_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const autofill_service_apk_sha = 'e9e3e6ce83e99f439550d494438fb3d245d67d74be3f915dcecf83b7c452e360'
const autofill_service_pass_marker = 'AUTOFILL-SERVICE-PASS typed-manager string-null component-null public-instance null-branch notifications typed-values'
// Keyguard policy queries use their successor framework and verified native pair.
const keyguard_policy_framework_sha = '1ff4080bbfdc95c4c370e88b3b283f004f165f4a93c816e224d823e98f7dc4b4'
const keyguard_policy_native_sha = 'c87ccc623d70b1d582cd5486a9a6316c5117091ca10113682aa07cc72c80912f'
const keyguard_policy_apk_sha = 'e02a832fa82b6531fe8928d119e6113bc1abfe94c722e020f4ede1b4179f0454'
const keyguard_policy_pass_marker = 'KEYGUARD-POLICY-PASS cached-manager public-instance zero-flags null-admin component-preservation trust-mask dormant-config unmanaged-controls'
// Receiver-permission delivery requires its successor framework and fresh coupled native.
const broadcast_permission_framework_sha = '9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9'
const broadcast_permission_native_sha = '29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1'
const broadcast_permission_apk_sha = '0219961f053e02b8d4435b87e86acec64e56d57eb2b68d2f175638016eda37b5'
const broadcast_permission_pass_marker = 'BROADCAST-PERMISSION-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers'
// The verifier-corrected fixture is a distinct opt-in over the same runtime pair.
const broadcast_permission_v2_framework_sha = '9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9'
const broadcast_permission_v2_native_sha = '29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1'
const broadcast_permission_v2_apk_sha = '8c6446247e9660eb58c54a166c839abe4e372403620d727fa004bafd847d41a3'
const broadcast_permission_v2_pass_marker = 'BROADCAST-PERMISSION-V2-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers bounded-startup'
// Secure writes and tile requests use their successor framework and verified native pair.
const secure_settings_framework_sha = 'f7eef1e9b2a2a7730ce0b024823c9cc38dc1d510252dc6dccd30f1ada79f9768'
const secure_settings_native_sha = '29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1'
const secure_settings_apk_sha = '1e2628151f851619bbae164f0c3a6830c354d11fe3f2104e584afe39482ccdd8'
const secure_settings_pass_marker = 'SECURE-SETTINGS-PASS public-static virtual-insert secure-uri exact-string-null-values nearby-component empty-clear provider-result SQLException narrow-exceptions null-resolver absent-provider preserved-getters tile-broadcast intent-payload nullable-component fresh-intents inherited-static'
// App inactivity uses its successor framework and the verified retained native pair.
const usage_inactive_framework_sha = 'd7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b'
const usage_inactive_native_sha = '29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1'
const usage_inactive_apk_sha = 'ae580b4c0ed99b97787f552d8e6f08a94daeed137fc346440cea832a7795a3d2'
const usage_inactive_pass_marker = 'USAGE-INACTIVE-PASS public-instance typed-service constructor arbitrary-packages null-empty-unicode repeat-32 legacy-service-null disabled-policy'
// Messenger transport uses its successor framework and verified retained native pair.
const messenger_binder_framework_sha = 'ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129'
const messenger_binder_native_sha = '29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1'
const messenger_binder_apk_sha = '7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a'
const messenger_binder_pass_marker = 'MESSENGER-BINDER-PASS endpoint-identity local-proxy queued-reply token-oneway cloned-payload sending-uid parcel-copy-reset null-errors bounded-worker'

struct FixtureProfile {
	name          string
	apk_sha       string
	framework_sha string
	native_sha    string
	pass_marker   string
	scope         string = 'standalone generic framework contract fixture; Google login and SettingsProvider persistence are not exercised'
}

fn child_attach_profile() FixtureProfile {
	return FixtureProfile{
		name: 'child-attach'
		apk_sha: '27869d74fd03598dda9b75b740cbaf2efcc423ee0c5ff3b2f447d22ade9f999e'
		framework_sha: framework_sha
		pass_marker: 'CHILD-ATTACH-PASS fresh-once repeated-once remove-no-orphan detached-reattach-order params-parent'
	}
}

fn settings_global_profile() FixtureProfile {
	return FixtureProfile{
		name: 'settings-global'
		apk_sha: 'c3e912e4e05c2af28d6d64d1fcb46874136a6164f7e2e19cc5ba1b62d950fedd'
		framework_sha: framework_sha
		pass_marker: 'SETTINGS-GLOBAL-PASS linkage virtual-insert URI exact-string-values zero negative min max repeated-key null-result SQLException SecurityException-identity absent-provider'
	}
}

fn application_restrictions_profile() FixtureProfile {
	return FixtureProfile{
		name: 'application-restrictions'
		apk_sha: '1fcd38978709198743aa9127b14f02bbebbf55e1f4d7793cd03270f3c3c25a07'
		framework_sha: 'd4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32'
		pass_marker: 'APPLICATION-RESTRICTIONS-PASS own-package nonnull empty fresh-bundles missing-string-array mutation-isolation repeated-32'
	}
}

fn authenticator_exception_profile() FixtureProfile {
	return FixtureProfile{
		name: 'authenticator-private-exception'
		apk_sha: 'c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941'
		framework_sha: '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		native_sha: 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
		pass_marker: 'AUTHENTICATOR-BASE-PASS fourteen-dispatch permission-denied-before-dispatch result error-mapping async-null label default-removal default-cloning default-sessions suggested-false no-account-registration'
	}
}

fn maps_network_profile() FixtureProfile {
	return FixtureProfile{
		name: 'maps-network-observations'
		apk_sha: 'f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43'
		framework_sha: '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		native_sha: 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
		pass_marker: 'MAPS-NETWORK-PASS observations-complete'
		scope: 'standalone credential-free network observations; completion does not establish DNS, TCP, TLS or Google login success; validate the finite observation sequence separately'
	}
}

fn authenticator_worker_profile() FixtureProfile {
	base := authenticator_exception_profile()
	return FixtureProfile{
		...base
		name: 'authenticator-worker-private-exception'
		native_sha: auth_worker_native_sha
	}
}

fn maps_network_v2_profile() FixtureProfile {
	base := maps_network_profile()
	return FixtureProfile{
		...base
		name: 'maps-network-tls-v2-observations'
		apk_sha: 'abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051'
		native_sha: auth_worker_native_sha
		pass_marker: 'MAPS-NETWORK-V2-PASS observations-complete'
	}
}

fn authenticator_binder_identity_profile() FixtureProfile {
	base := authenticator_exception_profile()
	return FixtureProfile{
		...base
		name: 'authenticator-binder-identity-private-exception'
		framework_sha: binder_identity_framework_sha
		native_sha: binder_identity_native_sha
	}
}

fn maps_network_v3_profile() FixtureProfile {
	base := maps_network_profile()
	return FixtureProfile{
		...base
		name: 'maps-network-tls-v3-binder-identity-observations'
		apk_sha: maps_network_v3_apk_sha
		framework_sha: binder_identity_framework_sha
		native_sha: binder_identity_native_sha
		pass_marker: 'MAPS-NETWORK-V3-PASS observations-complete'
	}
}

fn service_lifecycle_profile() FixtureProfile {
	return FixtureProfile{
		name: 'service-lifecycle'
		apk_sha: service_lifecycle_apk_sha
		framework_sha: service_lifecycle_framework_sha
		native_sha: service_lifecycle_native_sha
		pass_marker: 'SERVICE-LIFECYCLE-PASS constructors attach-base-context create destroy no-disk-callback policy-identity duplicate-attach null-attach real-write-control restored-original'
		scope: 'standalone Service construction, attachment and StrictMode callback regression; no GMS or Google authentication claim'
	}
}

fn platform_fragments_profile() FixtureProfile {
	return FixtureProfile{
		name: 'platform-fragments'
		apk_sha: platform_fragments_apk_sha
		framework_sha: platform_fragments_framework_sha
		native_sha: platform_fragments_native_sha
		pass_marker: platform_fragments_pass_marker
		scope: 'standalone platform FragmentManager lifecycle regression; no GMS or Google authentication claim'
	}
}

fn image_bounds_profile() FixtureProfile {
	return FixtureProfile{
		name: 'image-bounds'
		apk_sha: image_bounds_apk_sha
		framework_sha: image_bounds_framework_sha
		native_sha: image_bounds_native_sha
		pass_marker: image_bounds_pass_marker
		scope: 'standalone ImageView maximum-dimension property regression; measurement, GMS and Google authentication are not exercised'
	}
}

fn window_system_ui_profile() FixtureProfile {
	return FixtureProfile{
		name: 'window-system-ui'
		apk_sha: window_system_ui_apk_sha
		framework_sha: window_system_ui_framework_sha
		native_sha: window_system_ui_native_sha
		pass_marker: window_system_ui_pass_marker
		scope: 'standalone WindowManager.LayoutParams systemUiVisibility field regression; rendering, GMS and Google authentication are not exercised'
	}
}

fn seed_account_options_profile() FixtureProfile {
	return FixtureProfile{
		name: 'seed-account-options'
		apk_sha: seed_account_options_apk_sha
		framework_sha: seed_account_options_framework_sha
		native_sha: seed_account_options_native_sha
		pass_marker: seed_account_options_pass_marker
		scope: 'standalone UserManager unseeded options and immutable empty bundle regression; GMS and Google authentication are not exercised'
	}
}

fn persistent_data_block_profile() FixtureProfile {
	return FixtureProfile{
		name: 'persistent-data-block'
		apk_sha: persistent_data_block_apk_sha
		framework_sha: persistent_data_block_framework_sha
		native_sha: persistent_data_block_native_sha
		pass_marker: persistent_data_block_pass_marker
		scope: 'standalone PersistentDataBlockManager class and absent service regression with UserManager controls; GMS and Google authentication are not exercised'
	}
}

fn bitmap_tiles_profile() FixtureProfile {
	return FixtureProfile{
		name: 'bitmap-tiles'
		apk_sha: bitmap_tiles_apk_sha
		framework_sha: bitmap_tiles_framework_sha
		native_sha: bitmap_tiles_native_sha
		pass_marker: bitmap_tiles_pass_marker
		scope: 'standalone BitmapDrawable tile state and offscreen pixel regression; GMS and Google authentication are not exercised'
	}
}

fn connectivity_truth_profile() FixtureProfile {
	return FixtureProfile{
		name: 'connectivity-truth'
		apk_sha: connectivity_truth_apk_sha
		framework_sha: bitmap_tiles_framework_sha
		native_sha: bitmap_tiles_native_sha
		pass_marker: connectivity_truth_pass_marker
		scope: 'standalone read-only ConnectivityManager, NetworkInterface and raw native observations; offline, null and operational errors are observations, not connectivity assertions; separate bootstrap package under the selected Unix identity, no GMS data access or authentication claim'
	}
}

fn window_animations_profile() FixtureProfile {
	return FixtureProfile{
		name: 'window-animations'
		apk_sha: window_animations_apk_sha
		framework_sha: window_animations_framework_sha
		native_sha: window_animations_native_sha
		pass_marker: window_animations_pass_marker
		scope: 'standalone Window animation resource attributes and callback dispatch regression with Activity and Dialog controls; visual animation execution, GMS and Google authentication are not exercised'
	}
}

fn layout_alignment_profile() FixtureProfile {
	return FixtureProfile{
		name: 'layout-alignment'
		apk_sha: layout_alignment_apk_sha
		framework_sha: layout_alignment_framework_sha
		native_sha: layout_alignment_native_sha
		pass_marker: layout_alignment_pass_marker
		scope: 'standalone Layout alignment and additive-spacing getter regression with constructor identity and retained Builder controls; text layout rendering, GMS and Google authentication are not exercised'
	}
}

fn user_restrictions_profile() FixtureProfile {
	return FixtureProfile{
		name: 'user-restrictions'
		apk_sha: user_restrictions_apk_sha
		framework_sha: user_restrictions_framework_sha
		native_sha: user_restrictions_native_sha
		pass_marker: user_restrictions_pass_marker
		scope: 'standalone UserManager restriction snapshot and virtual boolean query regression for the unmanaged base and backend controls; policy enforcement, GMS and Google authentication are not exercised'
	}
}

fn bundle_cross_profile_profile() FixtureProfile {
	return FixtureProfile{
		name: 'bundle-cross-profile'
		apk_sha: bundle_cross_profile_apk_sha
		framework_sha: bundle_cross_profile_framework_sha
		native_sha: user_restrictions_native_sha
		pass_marker: bundle_cross_profile_pass_marker
		scope: 'standalone BaseBundle boolean null-key and default-value regression with typed-null unsupported CrossProfileApps controls; wrong-type warning fallback, cross-profile backend, GMS and authentication are not exercised'
	}
}

fn user_restrictions_bundle_profile() FixtureProfile {
	base := user_restrictions_profile()
	return FixtureProfile{
		...base
		name: 'user-restrictions-bundle'
		framework_sha: bundle_cross_profile_framework_sha
		scope: 'unchanged signed UserManager snapshot and backend-query regression on the corrected BaseBundle framework; no fixture cases are removed or altered; policy enforcement, GMS and authentication are not exercised'
	}
}

fn resources_float_profile() FixtureProfile {
	return FixtureProfile{
		name: 'resources-float'
		apk_sha: resources_float_apk_sha
		framework_sha: resources_float_framework_sha
		native_sha: resources_float_native_sha
		pass_marker: resources_float_pass_marker
		scope: 'standalone Resources floating-point lookup regression with packaged resources, aliases, strict type checks and virtual lookup controls; Maps UI, GMS and authentication are not exercised'
	}
}

fn paint_drawable_profile() FixtureProfile {
	return FixtureProfile{
		name: 'paint-drawable'
		apk_sha: paint_drawable_apk_sha
		framework_sha: paint_drawable_framework_sha
		native_sha: resources_float_native_sha
		pass_marker: paint_drawable_pass_marker
		scope: 'standalone PaintDrawable constructors, corner state, callbacks, offscreen pixels and packaged XML inflation regression; Maps UI, network, GMS and authentication are not exercised'
	}
}

fn dialog_theme_profile() FixtureProfile {
	return FixtureProfile{
		name: 'dialog-theme'
		apk_sha: dialog_theme_apk_sha
		framework_sha: dialog_theme_framework_sha
		native_sha: dialog_theme_native_sha
		pass_marker: dialog_theme_pass_marker
		scope: 'standalone Dialog theme resolution regression with packaged styles, explicit/default themes, inheritance, context, Window and inflation controls; Maps UI, GMS and authentication are not exercised'
	}
}

fn intent_extras_profile() FixtureProfile {
	return FixtureProfile{
		name: 'intent-extras'
		apk_sha: intent_extras_apk_sha
		framework_sha: intent_extras_framework_sha
		native_sha: dialog_theme_native_sha
		pass_marker: intent_extras_pass_marker
		scope: 'standalone Intent extras merge, copy, precedence, no-op, null and shallow-value regression with controlled-intent controls; Maps UI, GMS and authentication are not exercised'
	}
}

fn resource_locks_profile() FixtureProfile {
	return FixtureProfile{
		name: 'resource-locks'
		apk_sha: resource_locks_apk_sha
		framework_sha: resource_locks_framework_sha
		native_sha: resource_locks_native_sha
		pass_marker: resource_locks_pass_marker
		scope: 'standalone native resource synchronization regression with four workers, packaged resources, app-attribute apply and copies within one asset owner, framework-attribute copies across asset owners and owned NDK assets/directories; Maps UI, GMS and authentication are not exercised'
	}
}

fn pending_intent_profile() FixtureProfile {
	return FixtureProfile{
		name: 'pending-intent'
		apk_sha: pending_intent_apk_sha
		framework_sha: pending_intent_framework_sha
		native_sha: pending_intent_native_sha
		pass_marker: pending_intent_pass_marker
		scope: 'standalone process-local PendingIntent token identity, flags, parcel aliases, cancellation, one-shot consumption, snapshots and service/broadcast dispatch regression; cross-process token transport, Maps UI, GMS and authentication are not exercised'
	}
}

fn stable_display_profile() FixtureProfile {
	return FixtureProfile{
		name: 'stable-display'
		apk_sha: stable_display_apk_sha
		framework_sha: stable_display_framework_sha
		native_sha: stable_display_native_sha
		pass_marker: stable_display_pass_marker
		scope: 'standalone physical display dimensions, retained application window dimensions and fresh caller-owned Point regression; Google Play Services and authentication are not exercised'
	}
}

fn asset_locales_profile() FixtureProfile {
	return FixtureProfile{
		name: 'asset-locales'
		apk_sha: asset_locales_apk_sha
		framework_sha: asset_locales_framework_sha
		native_sha: asset_locales_native_sha
		pass_marker: asset_locales_pass_marker
		scope: 'standalone compiled framework/application asset locale enumeration, fresh arrays, mutation isolation, default-locale independence and absent Android credential backend regression; Google Play Services and authentication are not exercised'
	}
}

fn unmanaged_queries_profile() FixtureProfile {
	return FixtureProfile{
		name: 'unmanaged-queries'
		apk_sha: unmanaged_queries_apk_sha
		framework_sha: unmanaged_queries_framework_sha
		native_sha: unmanaged_queries_native_sha
		pass_marker: unmanaged_queries_pass_marker
		scope: 'standalone unmanaged device-owner and managed-profile query contracts; Google Play Services and authentication are not exercised'
	}
}

fn stats_unavailable_profile() FixtureProfile {
	return FixtureProfile{
		name: 'stats-unavailable'
		apk_sha: stats_unavailable_apk_sha
		framework_sha: stats_unavailable_framework_sha
		native_sha: stats_unavailable_native_sha
		pass_marker: stats_unavailable_pass_marker
		scope: 'standalone unavailable StatsManager type, service lookup and guarded-path linkage regression; Google Play Services and authentication are not exercised'
	}
}

fn subscription_service_profile() FixtureProfile {
	return FixtureProfile{
		name: 'subscription-service'
		apk_sha: subscription_service_apk_sha
		framework_sha: subscription_service_framework_sha
		native_sha: subscription_service_native_sha
		pass_marker: subscription_service_pass_marker
		scope: 'standalone no-modem subscription service, query and telephony wrapper contracts; Google Play Services and authentication are not exercised'
	}
}

fn autofill_service_profile() FixtureProfile {
	return FixtureProfile{
		name: 'autofill-service'
		apk_sha: autofill_service_apk_sha
		framework_sha: autofill_service_framework_sha
		native_sha: autofill_service_native_sha
		pass_marker: autofill_service_pass_marker
		scope: 'standalone absent autofill component query, null-provider branch, inactive notifications and ordinary typed values; Google Play Services and authentication are not exercised'
	}
}

fn keyguard_policy_profile() FixtureProfile {
	return FixtureProfile{
		name: 'keyguard-policy'
		apk_sha: keyguard_policy_apk_sha
		framework_sha: keyguard_policy_framework_sha
		native_sha: keyguard_policy_native_sha
		pass_marker: keyguard_policy_pass_marker
		scope: 'standalone absent keyguard policy feature mask, real policy service and guarded trust-agent branch; Google Play Services and authentication are not exercised'
	}
}

fn broadcast_permission_profile() FixtureProfile {
	return FixtureProfile{
		name: 'broadcast-permission'
		apk_sha: broadcast_permission_apk_sha
		framework_sha: broadcast_permission_framework_sha
		native_sha: broadcast_permission_native_sha
		pass_marker: broadcast_permission_pass_marker
		scope: 'standalone process-local dynamic and manifest broadcast delivery constrained by immutable primary APK self-owned requested signature permission; Google Play Services and authentication are not exercised'
	}
}

fn broadcast_permission_v2_profile() FixtureProfile {
	return FixtureProfile{
		name: 'broadcast-permission-v2'
		apk_sha: broadcast_permission_v2_apk_sha
		framework_sha: broadcast_permission_v2_framework_sha
		native_sha: broadcast_permission_v2_native_sha
		pass_marker: broadcast_permission_v2_pass_marker
		scope: 'standalone process-local receiver-permission delivery fixture with corrected register lifetimes and bounded HandlerThread startup over the unchanged broadcast runtime pair; Google Play Services and authentication are not exercised'
	}
}

fn secure_settings_profile() FixtureProfile {
	return FixtureProfile{
		name: 'secure-settings'
		apk_sha: secure_settings_apk_sha
		framework_sha: secure_settings_framework_sha
		native_sha: secure_settings_native_sha
		pass_marker: secure_settings_pass_marker
		scope: 'standalone Secure settings write delegation and API-28 tile listening-request broadcast contract; Google Play Services, authentication, system SettingsProvider persistence and SystemUI delivery are not exercised'
	}
}

fn messenger_binder_profile() FixtureProfile {
	return FixtureProfile{
		name: 'messenger-binder'
		apk_sha: messenger_binder_apk_sha
		framework_sha: messenger_binder_framework_sha
		native_sha: messenger_binder_native_sha
		pass_marker: messenger_binder_pass_marker
		scope: 'standalone process-local Messenger Binder Message request-reply contract; cross-process transport, Google Play Services, Maps and authentication are not exercised'
	}
}

fn usage_inactive_profile() FixtureProfile {
	return FixtureProfile{
		name: 'usage-inactive'
		apk_sha: usage_inactive_apk_sha
		framework_sha: usage_inactive_framework_sha
		native_sha: usage_inactive_native_sha
		pass_marker: usage_inactive_pass_marker
		scope: 'standalone disabled AppStandby inactivity query contract; application usage history, foreground state, permission enforcement, Google Play Services and authentication are not exercised'
	}
}

struct Configuration {
	runtime   string
	apk       string
	output    string
	uid       u32
	gid       u32
	profile   FixtureProfile
}

struct Receipt {
	kind             string = 'vinix-onboarding-api-runtime-v1'
	created_utc      string
	profile          string
	uid              u32
	gid              u32
	child_pid        i32
	wait_status      i32
	startup_seconds  int = 180
	shutdown_seconds int = 20
	log_limit_bytes  int = log_limit
	input_sha256     map[string]string
	log_sha256       string
	checks           []string
	scope            string = 'standalone generic framework contract fixture; Google login and SettingsProvider persistence are not exercised'
}

struct EvidenceEntry {
	path   string
	kind   string = 'regular'
	mode   u32    = 0o600
	size   u64
	sha256 string
	data   string
}

struct EvidenceArchive {
	version   int = 1
	root_mode u32 = 0o755
	entries   []EvidenceEntry
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn canonical(path string) bool {
	return path.starts_with('/') && path.len > 1 && !path.ends_with('/')
		&& !path.contains('\\') && !path.contains('\x00')
		&& path.bytes().all(it >= 32 && it != 127)
		&& path.split('/')[1..].all(it !in ['', '.', '..'])
}

fn digest(path string) !string {
	info := os.lstat(path)!
	require(info.get_filetype() == .regular && info.nlink == 1, 'single-link regular input: ' + path)!
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn protected_parents(path string) ! {
	require(canonical(path), 'canonical absolute path')!
	parts := path.split('/')
	mut current := '/'
	for part in parts[1..parts.len - 1] {
		current = current.trim_right('/') + '/' + part
		info := os.lstat(current)!
		require(info.get_filetype() == .directory && info.uid == 0 && info.mode & 0o022 == 0
			&& info.mode & 0o001 != 0, 'root-protected, target-traversable ancestors: ' + current)!
	}
}

fn input_pin(path string) !string {
	protected_parents(path)!
	info := os.lstat(path)!
	require(info.uid == 0 && info.mode & 0o022 == 0, 'root-protected input: ' + path)!
	return digest(path)
}

fn owned_directory(path string, config Configuration) ! {
	os.mkdir(path, mode: 0o700)!
	os.chmod(path, 0o700)!
	require(unsafe { C.chown(&char(path.str), int(config.uid), int(config.gid)) } == 0, 'chown fixture directory')!
}

fn health(line string, expected_marker string) ! {
	for bad in ['-FAIL', 'FATAL EXCEPTION', 'JNI DETECTED ERROR', 'JNI exception', 'VerifyError',
		'Exception in thread', 'Abort message:', 'AssertionError', 'NoSuchMethodError',
		'NoSuchFieldError', 'ClassNotFoundException', 'NoClassDefFoundError', 'Exception:', 'Error:',
		'SIGABRT', 'SIGSEGV', 'panic:'] {
		if line.contains(bad) { return error('child failure marker: ' + bad) }
	}
	if (line.contains('CHILD-ATTACH-PASS') || line.contains('SETTINGS-GLOBAL-PASS')
		|| line.contains('APPLICATION-RESTRICTIONS-PASS') || line.contains('AUTHENTICATOR-BASE-PASS')
		|| line.contains('MAPS-NETWORK-PASS') || line.contains('MAPS-NETWORK-V2-PASS')
		|| line.contains('MAPS-NETWORK-V3-PASS') || line.contains('SERVICE-LIFECYCLE-PASS')
		|| line.contains('PLATFORM-FRAGMENTS-PASS') || line.contains('IMAGE-BOUNDS-PASS')
		|| line.contains('WINDOW-SYSTEM-UI-PASS') || line.contains('SEED-ACCOUNT-OPTIONS-PASS')
		|| line.contains('PERSISTENT-DATA-BLOCK-PASS') || line.contains('BITMAP-TILES-PASS')
		|| line.contains('CONNECTIVITY-TRUTH-PASS') || line.contains('WINDOW-ANIMATIONS-PASS')
		|| line.contains('LAYOUT-ALIGNMENT-PASS') || line.contains('USER-RESTRICTIONS-PASS')
		|| line.contains('BUNDLE-BOOLEAN-PASS') || line.contains('RESOURCES-FLOAT-PASS')
		|| line.contains('PAINT-DRAWABLE-PASS') || line.contains('DIALOG-THEME-PASS')
		|| line.contains('INTENT-EXTRAS-PASS') || line.contains('RESOURCE-LOCKS-PASS')
		|| line.contains('PENDING-INTENT-PASS') || line.contains('STABLE-DISPLAY-PASS')
		|| line.contains('ASSET-LOCALES-PASS') || line.contains('UNMANAGED-QUERIES-PASS')
		|| line.contains('STATS-UNAVAILABLE-PASS') || line.contains('SUBSCRIPTION-SERVICE-PASS')
		|| line.contains('AUTOFILL-SERVICE-PASS') || line.contains('KEYGUARD-POLICY-PASS')
		|| line.contains('BROADCAST-PERMISSION-PASS') || line.contains('BROADCAST-PERMISSION-V2-PASS')
		|| line.contains('SECURE-SETTINGS-PASS') || line.contains('USAGE-INACTIVE-PASS')
		|| line.contains('MESSENGER-BINDER-PASS')) && line != expected_marker {
		return error('conflicting fixture marker')
	}
}

fn is_ready(line string) bool {
	return line == ready_marker || line.starts_with(ready_marker + ' ')
}

fn check_log(text string, expected_marker string) ! {
	require(text.len <= log_limit && text.ends_with('\n'), 'bounded complete child log')!
	lines := text.split_into_lines()
	require(lines.filter(it == expected_marker).len == 1 && text.count(expected_marker) == 1, 'exact fixture pass once')!
	require(lines.filter(is_ready(it)).len == 1, 'native WS readiness once')!
	for line in lines {
		require(line.len <= line_limit, 'bounded child line')!
		health(line, expected_marker)!
	}
}

fn write_all(fd i32, bytes []u8) ! {
	mut sent := 0
	for sent < bytes.len {
		n := unsafe { C.write(fd, bytes[sent..].data, uint(bytes.len - sent)) }
		if n < 0 && C.errno == C.EINTR { continue }
		require(n > 0, 'output write')!
		sent += int(n)
	}
}

fn pipe() ![2]i32 {
	mut pair := [2]i32{}
	require(C.pipe(&pair[0]) == 0, 'create fixture pipe')!
	for fd in pair {
		if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) < 0 {
			C.close(pair[0])
			C.close(pair[1])
			return error('protect fixture pipe')
		}
	}
	return pair
}

fn spawn_child(config Configuration, input [2]i32, output [2]i32) !i32 {
	// Enumerate before fork; all inherited descriptors except duplicated stdio
	// are closed, including unrelated app/account/browser channels.
	mut inherited := []i32{}
	for name in os.ls('/proc/self/fd')! {
		require(name.len > 0 && name.bytes().all(it >= `0` && it <= `9`), 'numeric /proc/self/fd entry')!
		if name.int() >= 3 { inherited << i32(name.int()) }
	}
	child := C.fork()
	require(child >= 0, 'fork fixture')!
	if child != 0 { return child }
	if C.setpgid(0, 0) != 0 || C.dup2(input[0], 0) < 0
		|| C.dup2(output[1], 1) < 0 || C.dup2(output[1], 2) < 0 {
		C._exit(126)
	}
	for fd in inherited { C.close(fd) }
	environment := ['PATH=/usr/bin:/bin', 'HOME=' + config.output + '/home',
		'VINIX_ANDROID_ROOT=' + config.runtime, 'VINIX_ANDROID_HOME=' + config.output + '/home',
		'VINIX_ANDROID_UID=' + config.uid.str(), 'VINIX_ANDROID_GID=' + config.gid.str(),
		'ANDROID_APP_DATA_DIR=' + config.output + '/data',
		'VINIX_INPUT_FD=0',
		'VINIX_SURFACE_PATH=' + config.output + '/data/probe.surface']
	os.execve(config.runtime + '/usr/bin/run-android', [config.output + '/client.apk', '-l',
		'org/vinix/bootstrap/Main', '-w', '64', '-h', '64'], environment) or { C._exit(127) }
	C._exit(127)
	return i32(-1)
}

fn execute(config Configuration) !i32 {
	for fd in 0 .. 3 { require(C.fcntl(i32(fd), C.F_GETFD) >= 0, 'open controller stdio')! }
	input := pipe()!
	mut input_writer := input[1]
	defer { if input_writer >= 0 { C.close(input_writer) } }
	output := pipe() or {
		C.close(input[0])
		return err
	}
	defer { C.close(output[0]) }
	mut log := os.create(config.output + '/child.log') or {
		C.close(input[0])
		C.close(output[1])
		return err
	}
	defer { log.close() }
	os.chmod(config.output + '/child.log', 0o600)!
	pid := spawn_child(config, input, output) or {
		C.close(input[0])
		C.close(output[1])
		return err
	}
	C.close(input[0])
	C.close(output[1])
	mut reaped := false
	defer {
		if !reaped {
			// The direct child remains unreaped until pipe EOF. Its PID cannot be
			// reused, so failure cleanup owns both this process and its group.
			C.kill(-pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			mut status := i32(0)
			for {
				waited := C.waitpid(pid, &status, 0)
				if waited >= 0 || C.errno != C.EINTR { break }
			}
		}
	}
	flags := C.fcntl(output[0], C.F_GETFL, 0)
	require(flags >= 0 && C.fcntl(output[0], C.F_SETFL, flags | C.O_NONBLOCK) >= 0, 'nonblocking fixture output')!
	mut buffer := [4096]u8{}
	mut line := []u8{cap: line_limit}
	mut total := 0
	mut passed := 0
	mut ready := 0
	mut deadline := time.sys_mono_now() + u64(180 * time.second)
	mut status := i32(0)
	for {
		require(time.sys_mono_now() < deadline, 'fixture startup/shutdown deadline')!
		n := unsafe { C.read(output[0], &buffer[0], buffer.len) }
		if n > 0 {
			total += int(n)
			require(total <= log_limit, 'child output exceeds 4 MiB')!
			write_all(i32(log.fd), buffer[..int(n)])!
			for byte in buffer[..int(n)] {
				if byte != `\n` {
					require(line.len < line_limit, 'child line exceeds 8192 bytes')!
					line << byte
					continue
				}
				text := line.bytestr()
				health(text, config.profile.pass_marker)!
				if text == config.profile.pass_marker { passed++ }
				if is_ready(text) { ready++ }
				require(passed <= 1 && ready <= 1, 'duplicate pass/readiness marker')!
				line.clear()
			}
			if input_writer >= 0 && passed == 1 && ready == 1 {
				C.close(input_writer)
				input_writer = -1
				deadline = time.sys_mono_now() + u64(20 * time.second)
				println('ONBOARDING-API-RUN-STDIN-CLOSED reason=ready-and-pass')
			}
			continue
		}
		if n < 0 { require(C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR], 'child output read')! }
		if n == 0 {
			waited := C.waitpid(pid, &status, C.WNOHANG)
			require(waited == 0 || waited == pid || (waited < 0 && C.errno == C.EINTR), 'wait for fixture child')!
			if waited == pid {
				reaped = true
				break
			}
		}
		time.sleep(10 * time.millisecond)
	}
	require(line.len == 0 && passed == 1 && ready == 1 && input_writer == -1 && status == 0,
		'exact fixture markers, complete output, stdin shutdown and clean child exit')!
	check_log(os.read_file(config.output + '/child.log')!, config.profile.pass_marker)!
	println('ONBOARDING-API-RUN-EXIT status=' + status.str())
	return pid
}

fn serial_frame(fd i32, frame string) ! {
	require(frame.len < 1024 && frame.ends_with('\n'), 'bounded serial frame')!
	mut n := i64(-1)
	for {
		n = unsafe { C.write(fd, frame.str, uint(frame.len)) }
		if n < 0 && C.errno == C.EINTR { continue }
		break
	}
	require(n == frame.len, 'atomic serial frame')!
}

fn export_evidence(output string) ! {
	mut entries := []EvidenceEntry{}
	for name in ['receipt.json', 'child.log'] {
		path := output + '/' + name
		require(os.file_size(path) <= log_limit, 'bounded evidence file')!
		bytes := os.read_bytes(path)!
		entries << EvidenceEntry{ path: name, size: u64(bytes.len), sha256: sha256.sum(bytes).hex(), data: base64.encode(bytes) }
	}
	payload := json2.encode(EvidenceArchive{ entries: entries })
	require(payload.len <= 6 * 1024 * 1024, 'bounded evidence archive')!
	fd := unsafe { C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY | C.O_CLOEXEC) }
	require(fd >= 0, 'open evidence console')!
	defer { C.close(fd) }
	sha := sha256.sum(payload.bytes()).hex()
	shape := sha + ' ' + payload.len.str() + ' ' + ((payload.len + 511) / 512).str() + '\n'
	serial_frame(fd, serial_prefix + 'BEGIN ' + shape)!
	for offset := 0; offset < payload.len; offset += 512 {
		end := if offset + 512 < payload.len { offset + 512 } else { payload.len }
		serial_frame(fd, serial_prefix + 'CHUNK ' + sha + ' ' + (offset / 512).str() + ' ' +
			base64.encode(payload[offset..end].bytes()) + '\n')!
	}
	serial_frame(fd, serial_prefix + 'END ' + shape)!
}

fn selftest() ! {
	mut cases := 0
	profiles := [child_attach_profile(), settings_global_profile(), application_restrictions_profile(), authenticator_exception_profile(), maps_network_profile(), authenticator_worker_profile(), maps_network_v2_profile(), authenticator_binder_identity_profile(), maps_network_v3_profile(), service_lifecycle_profile(), platform_fragments_profile(), image_bounds_profile(), window_system_ui_profile(), seed_account_options_profile(), persistent_data_block_profile(), bitmap_tiles_profile(), connectivity_truth_profile(), window_animations_profile(), layout_alignment_profile(), user_restrictions_profile(), bundle_cross_profile_profile(), user_restrictions_bundle_profile(), resources_float_profile(), paint_drawable_profile(), dialog_theme_profile(), intent_extras_profile(), resource_locks_profile(), pending_intent_profile(), stable_display_profile(), asset_locales_profile(), unmanaged_queries_profile(), stats_unavailable_profile(), subscription_service_profile(), autofill_service_profile(), keyguard_policy_profile(), broadcast_permission_profile(), broadcast_permission_v2_profile(), secure_settings_profile(), usage_inactive_profile(), messenger_binder_profile()]
	require(child_attach_profile().framework_sha == framework_sha
		&& settings_global_profile().framework_sha == framework_sha
		&& application_restrictions_profile().framework_sha != framework_sha, 'exact per-profile framework identities')!
	require(authenticator_exception_profile().framework_sha == '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		&& authenticator_exception_profile().native_sha == 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791', 'exact diagnostic runtime identities')!
	require(maps_network_profile().framework_sha == authenticator_exception_profile().framework_sha
		&& maps_network_profile().native_sha == authenticator_exception_profile().native_sha, 'network observations use the same pinned runtime')!
	require(authenticator_worker_profile().native_sha == maps_network_v2_profile().native_sha
		&& authenticator_worker_profile().native_sha != authenticator_exception_profile().native_sha
		&& maps_network_v2_profile().framework_sha == maps_network_profile().framework_sha
		&& maps_network_v2_profile().apk_sha != maps_network_profile().apk_sha, 'worker and TLS-v2 identities are distinct opt-ins')!
	require(authenticator_binder_identity_profile().apk_sha == authenticator_exception_profile().apk_sha
		&& authenticator_binder_identity_profile().native_sha == maps_network_v3_profile().native_sha
		&& authenticator_binder_identity_profile().native_sha != authenticator_worker_profile().native_sha
		&& authenticator_binder_identity_profile().framework_sha == maps_network_v3_profile().framework_sha
		&& authenticator_binder_identity_profile().framework_sha != authenticator_worker_profile().framework_sha
		&& maps_network_v3_profile().apk_sha != maps_network_v2_profile().apk_sha,
		'Binder identity and TLS-v3 require their distinct pinned runtime pair')!
	require(service_lifecycle_profile().native_sha == service_lifecycle_native_sha
		&& service_lifecycle_profile().native_sha != binder_identity_native_sha
		&& service_lifecycle_profile().framework_sha != binder_identity_framework_sha
		&& service_lifecycle_profile().apk_sha != authenticator_binder_identity_profile().apk_sha
		&& service_lifecycle_profile().apk_sha != maps_network_v3_profile().apk_sha,
		'Service lifecycle uses its new framework and terminal-exit diagnostic native')!
	require(platform_fragments_profile().framework_sha != service_lifecycle_profile().framework_sha
		&& platform_fragments_profile().native_sha != service_lifecycle_profile().native_sha
		&& platform_fragments_profile().apk_sha != service_lifecycle_profile().apk_sha,
		'platform fragments requires its distinct framework, exception-restore native and fixture')!
	require(image_bounds_profile().framework_sha != platform_fragments_profile().framework_sha
		&& image_bounds_profile().native_sha.len == 64
		&& image_bounds_profile().apk_sha != platform_fragments_profile().apk_sha,
		'ImageView bounds requires its distinct framework and fixture with an exact coupled native pin')!
	require(window_system_ui_profile().framework_sha != image_bounds_profile().framework_sha
		&& window_system_ui_profile().native_sha.len == 64
		&& window_system_ui_profile().apk_sha != image_bounds_profile().apk_sha,
		'window system UI requires its distinct framework and fixture with an exact coupled native pin')!
	require(seed_account_options_profile().framework_sha != window_system_ui_profile().framework_sha
		&& seed_account_options_profile().native_sha.len == 64
		&& seed_account_options_profile().apk_sha != window_system_ui_profile().apk_sha,
		'seed account options requires its distinct framework and fixture with an exact coupled native pin')!
	require(persistent_data_block_profile().framework_sha != seed_account_options_profile().framework_sha
		&& persistent_data_block_profile().native_sha.len == 64
		&& persistent_data_block_profile().apk_sha != seed_account_options_profile().apk_sha,
		'persistent data block requires its distinct framework and fixture with an exact coupled native pin')!
	require(bitmap_tiles_profile().framework_sha != persistent_data_block_profile().framework_sha
		&& bitmap_tiles_profile().native_sha != persistent_data_block_profile().native_sha
		&& bitmap_tiles_profile().apk_sha != persistent_data_block_profile().apk_sha,
		'bitmap tiling requires its distinct framework, native sampler and signed pixel fixture')!
	require(connectivity_truth_profile().framework_sha == bitmap_tiles_profile().framework_sha
		&& connectivity_truth_profile().native_sha == bitmap_tiles_profile().native_sha
		&& connectivity_truth_profile().apk_sha != bitmap_tiles_profile().apk_sha
		&& connectivity_truth_profile().pass_marker != bitmap_tiles_profile().pass_marker,
		'connectivity observations require the exact existing pair and a distinct signed diagnostic fixture')!
	require(window_animations_profile().framework_sha != bitmap_tiles_profile().framework_sha
		&& window_animations_profile().native_sha.len == 64
		&& window_animations_profile().apk_sha != bitmap_tiles_profile().apk_sha
		&& window_animations_profile().apk_sha != connectivity_truth_profile().apk_sha,
		'window animations require their new framework and fixture with the actual coupled native pin')!
	require(layout_alignment_profile().framework_sha != window_animations_profile().framework_sha
		&& layout_alignment_profile().native_sha.len == 64
		&& layout_alignment_profile().apk_sha != window_animations_profile().apk_sha,
		'Layout getters require their new framework, signed fixture and actual coupled native pin')!
	require(user_restrictions_profile().framework_sha != layout_alignment_profile().framework_sha
		&& user_restrictions_profile().native_sha == layout_alignment_profile().native_sha
		&& user_restrictions_profile().apk_sha != layout_alignment_profile().apk_sha,
		'user restriction queries require their new framework and fixture with the verified retained native pin')!
	require(bundle_cross_profile_profile().framework_sha != user_restrictions_profile().framework_sha
		&& bundle_cross_profile_profile().native_sha == user_restrictions_profile().native_sha
		&& bundle_cross_profile_profile().apk_sha != user_restrictions_profile().apk_sha,
		'boolean and absent-service controls require the corrected framework and their own fixture')!
	require(user_restrictions_bundle_profile().framework_sha == bundle_cross_profile_profile().framework_sha
		&& user_restrictions_bundle_profile().native_sha == user_restrictions_profile().native_sha
		&& user_restrictions_bundle_profile().apk_sha == user_restrictions_profile().apk_sha
		&& user_restrictions_bundle_profile().pass_marker == user_restrictions_profile().pass_marker,
		'UserManager retry must preserve the exact original signed fixture and marker on the corrected framework')!
	require(resources_float_profile().framework_sha != bundle_cross_profile_profile().framework_sha
		&& resources_float_profile().native_sha.len == 64
		&& resources_float_profile().apk_sha != bundle_cross_profile_profile().apk_sha,
		'resource floats require their new framework, signed fixture and exact coupled native pin')!
	require(paint_drawable_profile().framework_sha != resources_float_profile().framework_sha
		&& paint_drawable_profile().native_sha == resources_float_profile().native_sha
		&& paint_drawable_profile().apk_sha != resources_float_profile().apk_sha,
		'PaintDrawable requires its new framework and fixture with the verified retained native pin')!
	require(dialog_theme_profile().framework_sha != paint_drawable_profile().framework_sha
		&& dialog_theme_profile().native_sha.len == 64
		&& dialog_theme_profile().apk_sha != paint_drawable_profile().apk_sha,
		'Dialog themes require their corrected framework, signed fixture and exact coupled native pin')!
	require(intent_extras_profile().framework_sha != dialog_theme_profile().framework_sha
		&& intent_extras_profile().native_sha == dialog_theme_profile().native_sha
		&& intent_extras_profile().apk_sha != dialog_theme_profile().apk_sha,
		'Intent extras require their new framework and fixture with the verified retained native pin')!
	require(resource_locks_profile().framework_sha == intent_extras_profile().framework_sha
		&& resource_locks_profile().native_sha != intent_extras_profile().native_sha
		&& resource_locks_profile().native_sha.len == 64
		&& resource_locks_profile().apk_sha != intent_extras_profile().apk_sha,
		'resource locks require the unchanged Intent framework and their distinct signed fixture and native library')!
	require(pending_intent_profile().framework_sha != resource_locks_profile().framework_sha
		&& pending_intent_profile().native_sha == resource_locks_profile().native_sha
		&& pending_intent_profile().apk_sha != resource_locks_profile().apk_sha,
		'PendingIntent requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(stable_display_profile().framework_sha != pending_intent_profile().framework_sha
		&& stable_display_profile().native_sha != pending_intent_profile().native_sha
		&& stable_display_profile().native_sha.len == 64
		&& stable_display_profile().apk_sha != pending_intent_profile().apk_sha,
		'stable display requires its successor framework, native framebuffer query and distinct signed fixture')!
	require(asset_locales_profile().framework_sha != stable_display_profile().framework_sha
		&& asset_locales_profile().native_sha != stable_display_profile().native_sha
		&& asset_locales_profile().native_sha.len == 64
		&& asset_locales_profile().apk_sha != stable_display_profile().apk_sha,
		'asset locales require their successor framework, real native asset query and distinct signed fixture')!
	require(unmanaged_queries_profile().framework_sha != asset_locales_profile().framework_sha
		&& unmanaged_queries_profile().native_sha == asset_locales_profile().native_sha
		&& unmanaged_queries_profile().apk_sha != asset_locales_profile().apk_sha,
		'unmanaged queries require their successor framework and distinct signed fixture with the verified retained native pin')!
	require(stats_unavailable_profile().framework_sha != unmanaged_queries_profile().framework_sha
		&& stats_unavailable_profile().native_sha == unmanaged_queries_profile().native_sha
		&& stats_unavailable_profile().apk_sha != unmanaged_queries_profile().apk_sha,
		'stats unavailability requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(subscription_service_profile().framework_sha != stats_unavailable_profile().framework_sha
		&& subscription_service_profile().native_sha == stats_unavailable_profile().native_sha
		&& subscription_service_profile().apk_sha != stats_unavailable_profile().apk_sha,
		'subscription service requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(autofill_service_profile().framework_sha != subscription_service_profile().framework_sha
		&& autofill_service_profile().native_sha == subscription_service_profile().native_sha
		&& autofill_service_profile().apk_sha != subscription_service_profile().apk_sha,
		'autofill service requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(keyguard_policy_profile().framework_sha != autofill_service_profile().framework_sha
		&& keyguard_policy_profile().native_sha == autofill_service_profile().native_sha
		&& keyguard_policy_profile().apk_sha != autofill_service_profile().apk_sha,
		'keyguard policy requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(broadcast_permission_profile().framework_sha != keyguard_policy_profile().framework_sha
		&& broadcast_permission_profile().native_sha != keyguard_policy_profile().native_sha
		&& broadcast_permission_profile().apk_sha != keyguard_policy_profile().apk_sha,
		'broadcast permission requires its successor framework, fresh coupled native and distinct signed fixture')!
	require(broadcast_permission_v2_profile().framework_sha == broadcast_permission_profile().framework_sha
		&& broadcast_permission_v2_profile().native_sha == broadcast_permission_profile().native_sha
		&& broadcast_permission_v2_profile().apk_sha != broadcast_permission_profile().apk_sha
		&& broadcast_permission_v2_profile().pass_marker != broadcast_permission_profile().pass_marker,
		'broadcast permission v2 requires the unchanged runtime pair and distinct signed fixture and marker')!
	require(secure_settings_profile().framework_sha != broadcast_permission_v2_profile().framework_sha
		&& secure_settings_profile().native_sha == broadcast_permission_v2_profile().native_sha
		&& secure_settings_profile().apk_sha != broadcast_permission_v2_profile().apk_sha,
		'secure settings requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(usage_inactive_profile().framework_sha != secure_settings_profile().framework_sha
		&& usage_inactive_profile().native_sha == secure_settings_profile().native_sha
		&& usage_inactive_profile().apk_sha != secure_settings_profile().apk_sha,
		'usage inactivity requires its successor framework and distinct signed fixture with the verified retained native pin')!
	require(messenger_binder_profile().framework_sha != usage_inactive_profile().framework_sha
		&& messenger_binder_profile().native_sha == usage_inactive_profile().native_sha
		&& messenger_binder_profile().apk_sha != usage_inactive_profile().apk_sha,
		'messenger binder requires its successor framework and distinct signed fixture with the verified retained native pin')!
	for profile in profiles {
		mut pins := [profile.apk_sha, profile.framework_sha]
		if profile.native_sha != '' { pins << profile.native_sha }
		for pin in pins {
			require(pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'canonical profile SHA256')!
		}
		good := profile.pass_marker + '\n' + ready_marker + '\n'
		check_log(good, profile.pass_marker)!
		for bad in [good + profile.pass_marker + '\n', good + ready_marker + '\n', good.replace(profile.pass_marker, ''),
			good.replace(ready_marker, ''), good.trim_right('\n'),
			good.replace(profile.pass_marker, profile.pass_marker + ' other'), good + 'JNI exception\n',
			good + 'AssertionError\n', good + 'NoSuchFieldError\n', good + 'ClassNotFoundException\n',
			good + 'SIGSEGV\n', good.replace(ready_marker, ready_marker + 'other'),
			good + 'java.lang.IllegalStateException: unexpected\n',
			good + 'x'.repeat(line_limit + 1) + '\n', good + 'x'.repeat(log_limit) + '\n'] {
			mut rejected := false
			check_log(bad, profile.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted invalid log')!
			cases++
		}
		for other in profiles {
			if other.name == profile.name { continue }
			// Reused APKs share a marker; exact framework/native pin pairs
			// identify their runtime before execution, independently of the log.
			if other.pass_marker == profile.pass_marker {
				require(other.apk_sha == profile.apk_sha && other.native_sha != '' && profile.native_sha != ''
					&& (other.framework_sha != profile.framework_sha || other.native_sha != profile.native_sha),
					'shared fixture marker requires distinct pinned runtime pairs')!
				continue
			}
			mut rejected := false
			check_log(good, other.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted another profile marker')!
			cases++
			rejected = false
			check_log(good + other.pass_marker + '\n', profile.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted mixed profile markers')!
			cases++
		}
	}
	for path in ['relative', '/', '/a/', '/a//b', '/a/../b', '/a/./b', '/a\\b', '/a\x00b'] {
		require(!canonical(path), 'checker accepted noncanonical path')!
		cases++
	}
	require(canonical('/var/lib/onboarding-api-r1'), 'canonical path rejected')!
	for selector in ['--authenticator-binder-identity', '--maps-network-v3', '--service-lifecycle', '--platform-fragments', '--image-bounds', '--window-system-ui', '--seed-account-options', '--persistent-data-block', '--bitmap-tiles', '--connectivity-truth', '--window-animations', '--layout-alignment', '--user-restrictions', '--bundle-cross-profile', '--user-restrictions-bundle', '--resources-float', '--paint-drawable', '--dialog-theme', '--intent-extras', '--resource-locks', '--pending-intent', '--stable-display', '--asset-locales', '--unmanaged-queries', '--stats-unavailable', '--subscription-service', '--autofill-service', '--keyguard-policy', '--broadcast-permission', '--broadcast-permission-v2', '--secure-settings', '--usage-inactive', '--messenger-binder'] {
		full := [selector, '/runtime', '/fixture.apk', '10117', '10117', '/results']
		for count in 1 .. full.len {
			mut argv := [os.executable()]
			argv << full[..count]
			result := os.exec(argv)
			require(result.exit_code == 1 && result.output.contains('usage: onboarding-api-run'),
				'incomplete explicit fixture CLI accepted')!
			cases++
		}
		for bad in [[selector + '-other', '/runtime', '/fixture.apk', '10117', '10117', '/results'],
			[selector, '/runtime', '/fixture.apk', '10117', '10117', '/results', 'extra']] {
			mut argv := [os.executable()]
			argv << bad
			result := os.exec(argv)
			require(result.exit_code == 1 && result.output.contains('usage: onboarding-api-run'),
				'unknown or surplus explicit fixture CLI accepted')!
			cases++
		}
	}
	println('ONBOARDING-API-RUN-SELFTEST-PASS rejected=' + cases.str())
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selftest' {
		selftest()!
		return
	}
	mut arguments := os.args[1..]
	require(arguments.len == 6 && arguments[0] in ['--child-attach', '--settings-global', '--application-restrictions', '--authenticator-private-exception', '--maps-network', '--authenticator-worker', '--maps-network-v2', '--authenticator-binder-identity', '--maps-network-v3', '--service-lifecycle', '--platform-fragments', '--image-bounds', '--window-system-ui', '--seed-account-options', '--persistent-data-block', '--bitmap-tiles', '--connectivity-truth', '--window-animations', '--layout-alignment', '--user-restrictions', '--bundle-cross-profile', '--user-restrictions-bundle', '--resources-float', '--paint-drawable', '--dialog-theme', '--intent-extras', '--resource-locks', '--pending-intent', '--stable-display', '--asset-locales', '--unmanaged-queries', '--stats-unavailable', '--subscription-service', '--autofill-service', '--keyguard-policy', '--broadcast-permission', '--broadcast-permission-v2', '--secure-settings', '--usage-inactive', '--messenger-binder'],
		'usage: onboarding-api-run (--child-attach|--settings-global|--application-restrictions|--authenticator-private-exception|--maps-network|--authenticator-worker|--maps-network-v2|--authenticator-binder-identity|--maps-network-v3|--service-lifecycle|--platform-fragments|--image-bounds|--window-system-ui|--seed-account-options|--persistent-data-block|--bitmap-tiles|--connectivity-truth|--window-animations|--layout-alignment|--user-restrictions|--bundle-cross-profile|--user-restrictions-bundle|--resources-float|--paint-drawable|--dialog-theme|--intent-extras|--resource-locks|--pending-intent|--stable-display|--asset-locales|--unmanaged-queries|--stats-unavailable|--subscription-service|--autofill-service|--keyguard-policy|--broadcast-permission|--broadcast-permission-v2|--secure-settings|--usage-inactive|--messenger-binder) RUNTIME APK UID GID FRESH_OUTPUT | selftest')!
	profile := if arguments[0] == '--authenticator-private-exception' { authenticator_exception_profile() }
		else if arguments[0] == '--messenger-binder' { messenger_binder_profile() }
		else if arguments[0] == '--usage-inactive' { usage_inactive_profile() }
		else if arguments[0] == '--secure-settings' { secure_settings_profile() }
		else if arguments[0] == '--broadcast-permission-v2' { broadcast_permission_v2_profile() }
		else if arguments[0] == '--broadcast-permission' { broadcast_permission_profile() }
		else if arguments[0] == '--keyguard-policy' { keyguard_policy_profile() }
		else if arguments[0] == '--autofill-service' { autofill_service_profile() }
		else if arguments[0] == '--subscription-service' { subscription_service_profile() }
		else if arguments[0] == '--stats-unavailable' { stats_unavailable_profile() }
		else if arguments[0] == '--unmanaged-queries' { unmanaged_queries_profile() }
		else if arguments[0] == '--asset-locales' { asset_locales_profile() }
		else if arguments[0] == '--stable-display' { stable_display_profile() }
		else if arguments[0] == '--pending-intent' { pending_intent_profile() }
		else if arguments[0] == '--resource-locks' { resource_locks_profile() }
		else if arguments[0] == '--intent-extras' { intent_extras_profile() }
		else if arguments[0] == '--dialog-theme' { dialog_theme_profile() }
		else if arguments[0] == '--paint-drawable' { paint_drawable_profile() }
		else if arguments[0] == '--resources-float' { resources_float_profile() }
		else if arguments[0] == '--bundle-cross-profile' { bundle_cross_profile_profile() }
		else if arguments[0] == '--user-restrictions-bundle' { user_restrictions_bundle_profile() }
		else if arguments[0] == '--user-restrictions' { user_restrictions_profile() }
		else if arguments[0] == '--layout-alignment' { layout_alignment_profile() }
		else if arguments[0] == '--window-animations' { window_animations_profile() }
		else if arguments[0] == '--connectivity-truth' { connectivity_truth_profile() }
		else if arguments[0] == '--bitmap-tiles' { bitmap_tiles_profile() }
		else if arguments[0] == '--persistent-data-block' { persistent_data_block_profile() }
		else if arguments[0] == '--seed-account-options' { seed_account_options_profile() }
		else if arguments[0] == '--window-system-ui' { window_system_ui_profile() }
		else if arguments[0] == '--image-bounds' { image_bounds_profile() }
		else if arguments[0] == '--platform-fragments' { platform_fragments_profile() }
		else if arguments[0] == '--service-lifecycle' { service_lifecycle_profile() }
		else if arguments[0] == '--authenticator-binder-identity' { authenticator_binder_identity_profile() }
		else if arguments[0] == '--maps-network-v3' { maps_network_v3_profile() }
		else if arguments[0] == '--authenticator-worker' { authenticator_worker_profile() }
		else if arguments[0] == '--maps-network-v2' { maps_network_v2_profile() }
		else if arguments[0] == '--maps-network' { maps_network_profile() }
		else if arguments[0] == '--application-restrictions' { application_restrictions_profile() }
		else if arguments[0] == '--child-attach' { child_attach_profile() } else { settings_global_profile() }
	arguments = arguments[1..]
	require(canonical(arguments[0]), 'canonical runtime path')!
	$if !linux {
		return error('runtime fixture requires Linux/Vinix')
	}
	require(C.getuid() == 0 && C.geteuid() == 0, 'fixture controller requires root')!
	for value in arguments[2..4] {
		require(value.len == 5 && value.bytes().all(it >= `0` && it <= `9`)
			&& value.int() >= 10000 && value.int() <= 19999, 'fixture UID/GID in 10000..19999')!
	}
	config := Configuration{
		runtime:   arguments[0]
		apk:       arguments[1]
		uid:       arguments[2].u32()
		gid:       arguments[3].u32()
		output:    arguments[4]
		profile:   profile
	}
	require(C.getpwuid(config.uid) != unsafe { nil } && C.getgrgid(config.gid) != unsafe { nil }, 'pre-provisioned fixture user/group')!
	protected_parents(config.output)!
	require(!os.exists(config.output) && !os.is_link(config.output), 'fresh fixture output')!
	require(input_pin(config.apk)! == config.profile.apk_sha, 'signed fixture APK pin')!
	framework := config.runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	require(input_pin(framework)! == config.profile.framework_sha, 'corrected framework JAR pin')!
	mut inputs := map[string]string{}
	for path in [config.apk, framework, config.runtime + '/usr/bin/run-android',
		config.runtime + '/usr/bin/vinix-android-native', os.executable()] {
		inputs[path] = input_pin(path)!
	}
	if config.profile.native_sha != '' {
		native := config.runtime + '/usr/lib/art/libvinix-android-native.so'
		inputs[native] = input_pin(native)!
		require(inputs[native] == config.profile.native_sha, 'corrected native library pin')!
	}
	os.mkdir(config.output, mode: 0o755)!
	os.chmod(config.output, 0o755)!
	for name in ['data', 'home'] { owned_directory(config.output + '/' + name, config)! }
	os.cp(config.apk, config.output + '/client.apk')!
	os.chmod(config.output + '/client.apk', 0o444)!
	require(digest(config.output + '/client.apk')! == config.profile.apk_sha, 'staged fixture APK pin')!
	println('ONBOARDING-API-RUN-BEGIN profile=' + config.profile.name + ' uid=' + config.uid.str() + ' gid=' + config.gid.str())
	pid := execute(config)!
	for path, pin in inputs { require(input_pin(path)! == pin, 'input unchanged after ART run')! }
	require(digest(config.output + '/client.apk')! == config.profile.apk_sha, 'staged APK unchanged after ART run')!
	log_sha := digest(config.output + '/child.log')!
	receipt := Receipt{
		created_utc:  time.utc().format_rfc3339()
		profile:      config.profile.name
		uid:          config.uid
		gid:          config.gid
		child_pid:    pid
		input_sha256: inputs
		log_sha256:   log_sha
		scope:        config.profile.scope
		checks:       ['exact-pass-once', 'native-ws-ready-once', 'bounded-log-and-lines',
			'live-input-until-pass-and-ready', 'drained-through-eof', 'clean-exit',
			'isolated-unix-identity-data-home-surface', 'standalone-explicit-activity',
			'explicit-environment-no-account-browser-channels', 'closed-inherited-descriptors',
			'unchanged-pinned-inputs']
	}
	os.write_file(config.output + '/receipt.json', json2.encode(receipt, prettify: true))!
	os.chmod(config.output + '/receipt.json', 0o600)!
	export_evidence(config.output)!
	println('ONBOARDING-API-RUN-PASS receipt=' + config.output + '/receipt.json')
}

fn main() {
	run() or {
		eprintln('ONBOARDING-API-RUN-FAIL ' + err.msg())
		exit(1)
	}
}
