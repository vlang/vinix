// SPDX-License-Identifier: GPL-2.0-or-later
// Credential-free fixture delivery to QEMU usernet; never a general file server.
module main

import crypto.sha256
import json2
import net
import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, uint) int
fn C.write(int, voidptr, uint) int
fn C.fstat(int, &C.stat) int

const runner_path = '/Users/alex/.local/state/vinix/android/service-query-run-arm64-r1'
const runner_pin = '8ef76b9e4c9f1eb0cc84780eaa0b618a3a70f317cd4f0e87824ddcdffcae8727'
const fixture_root = '/Users/alex/.local/state/vinix/android/service-query-fixture-2026-10-27-r1'
const client_pin = '890de9d4ff410aaf5cd87a52b630ccfa7280fd3c0b2b38eee57159d525b1565d'
const disabled_pin = 'e5075f571f3b8334dded40accb08257ccfdf83e8526a7b61e502d586daa66048'
const direct_boot_runner = '/Users/alex/.local/state/vinix/android/direct-boot-run-2026-10-27-r1/run'
const direct_boot_runner_pin = '8caab5559b73dbe1ffc9645006e899fd82dfbe5cfac810df4f189db9eb152a60'
const direct_boot_fixture = '/Users/alex/.local/state/vinix/android/direct-boot-fixture-2026-10-27-r1'
const direct_boot_client_pin = 'a77c25679d47032a8bac73a8ec7751dae271f7828973a8f9b722f004a0ad0c02'
const direct_boot_disabled_pin = '91e209b043a1f65379ecf16107263d513681bb56bbf25bbce11022d0824f9af5'
const credential_storage_runner = '/Users/alex/.local/state/vinix/android/credential-storage-run-2026-10-27-r1/run'
const credential_storage_runner_pin = '74cc1fb3721c400d4a64d5c7e0c9fb095b0404aa9eed927cbfb6ace06774cb46'
const credential_storage_fixture = '/Users/alex/.local/state/vinix/android/credential-storage-fixture-2026-10-27-r1'
const credential_storage_client_pin = '22bc2b0aa822b2305f8ed63b50be32114ca55d1d83f79ca468f8f6addc6e373e'
const credential_storage_disabled_pin = '42723f25adaf0a5ae789a37e4bddff512d10b219c187d368fce61de1f700f752'
const broadcast_result_runner = '/Users/alex/.local/state/vinix/android/broadcast-result-run-2026-10-27-r1/run'
const broadcast_result_runner_pin = '95be25cf1f8837bc717d200b0b92642c3085adbd789aad25356b89a73f07a8df'
const broadcast_result_fixture = '/Users/alex/.local/state/vinix/android/broadcast-result-fixture-2026-10-27-r1'
const broadcast_result_client_pin = '44f6c4356a5d031cf68191476bb0d2fb0fc2ceec8ecea26ffd395024d19321e7'
const broadcast_result_disabled_pin = '5293215a5899d2adb3ca9c6a52248c10874a2ad5b2e9cf08168935e829527966'
const onboarding_api_runner = '/Users/alex/.local/state/vinix/android/onboarding-api-run-2026-10-27-r1/run'
const onboarding_api_runner_pin = '0c8926b74244b7f505ffa6aafb6ff8a6e7beef2bd96369310a30d35d063b10b8'
const child_attach_apk = '/Users/alex/.local/state/vinix/android/child-attach-checks-2026-10-27-r1/apk/probe.apk'
const child_attach_apk_pin = '27869d74fd03598dda9b75b740cbaf2efcc423ee0c5ff3b2f447d22ade9f999e'
const settings_global_apk = '/Users/alex/.local/state/vinix/android/settings-global-checks-2026-10-27-r1/apk/probe.apk'
const settings_global_apk_pin = 'c3e912e4e05c2af28d6d64d1fcb46874136a6164f7e2e19cc5ba1b62d950fedd'
const application_restrictions_runner = '/Users/alex/.local/state/vinix/android/application-restrictions-run-2026-10-28-r2/run'
const application_restrictions_runner_pin = '1079d41f4df536e7a14c468e22a6e8021449dd2f36d563ed40e108f4e11abd53'
const application_restrictions_apk = '/Users/alex/.local/state/vinix/android/application-restrictions-fixture-2026-10-28-r2/probe.apk'
const application_restrictions_apk_pin = '1fcd38978709198743aa9127b14f02bbebbf55e1f4d7793cd03270f3c3c25a07'
const auth_exception_api_runner = '/Users/alex/.local/state/vinix/android/auth-exception-api-run-2026-10-29-r1/run'
const auth_exception_api_runner_pin = '49e53828402f44c5c45afb8dd611bbf6198b4046da19d37db2c6d0195c1fd0e1'
const authenticator_exception_apk = '/Users/alex/.local/state/vinix/android/authenticator-private-exception-check-2026-10-29-r1/fixture/probe.apk'
const authenticator_exception_apk_pin = 'c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941'
const maps_network_apk = '/Users/alex/.local/state/vinix/android/maps-network-fixture-2026-10-29-r1/probe.apk'
const maps_network_apk_pin = 'f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43'
const auth_worker_api_runner = '/Users/alex/.local/state/vinix/android/auth-worker-api-run-2026-10-29-r1/run'
const auth_worker_api_runner_pin = '35bb212db62c2734ecf1198deddee04f20a8761d4b3cfb383cd978d4670856e9'
const maps_network_v2_apk = '/Users/alex/.local/state/vinix/android/maps-network-tls-v2-fixture-2026-10-29-r1/probe.apk'
const maps_network_v2_apk_pin = 'abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051'
const binder_identity_api_runner = '/Users/alex/.local/state/vinix/android/binder-identity-api-run-2026-10-29-r1/run'
const binder_identity_api_runner_pin = '29975834bca029b057df515c1210d9121e481c8b999bbcb2f4f7af8495b6c922'
const maps_network_v3_apk = '/Users/alex/.local/state/vinix/android/maps-network-tls-v3-fixture-2026-10-29-r1/probe.apk'
const maps_network_v3_apk_pin = 'bd07eddf7594fd6cc6b90b984baf7ee5855af0fc56ee0322fbc45ea318cf393a'
const service_lifecycle_api_runner = '/Users/alex/.local/state/vinix/android/service-lifecycle-api-run-2026-10-29-r1/run'
const service_lifecycle_api_runner_pin = '0d259a0e76d6ccff48b6d053264de4eb7bb49fc47c59b179b2150e03153b61de'
const service_lifecycle_apk = '/Users/alex/.local/state/vinix/android/service-lifecycle-fixture-2026-10-29-r2/probe.apk'
const service_lifecycle_apk_pin = 'd15082450bbc70efc761ec8403e5544e40a98efe3f0a3d69b75b9d142e25b283'
// Distinct verified platform-fragment ARM runner and signed fixture.
const platform_fragments_api_runner = '/Users/alex/.local/state/vinix/android/platform-fragments-api-run-2026-10-29-r1/run'
const platform_fragments_api_runner_pin = '58259a403faa16d64e2e4d56d6447128520d2e768c0feaa1ee908b595a52bf1f'
const platform_fragments_apk = '/Users/alex/.local/state/vinix/android/platform-fragments-fixture-2026-10-29-r1/probe.apk'
const platform_fragments_apk_pin = 'f2e08f444782607a408bd25766da399100e908cf2b99edeebcfb80d267dc21de'
const image_bounds_api_runner = '/Users/alex/.local/state/vinix/android/image-bounds-api-run-2026-10-30-r1/run'
const image_bounds_api_runner_pin = '52cfbb82ec2d3cb5034a6a84bf15fce44c52a45829e4de6005c7c15778103305'
const image_bounds_apk = '/Users/alex/.local/state/vinix/android/image-bounds-fixture-2026-10-30-r1/probe.apk'
const image_bounds_apk_pin = '7d11a0e6d71b6c556a57f84fd5f27610157f0a49735282f0bb31aaac0ff00a62'
const window_system_ui_api_runner = '/Users/alex/.local/state/vinix/android/window-system-ui-api-run-2026-10-30-r1/run'
const window_system_ui_api_runner_pin = 'd10f94b3ecfe3f90b397e31504f79a4654f52779369af039f6e7e98ecd3bdc97'
const window_system_ui_apk = '/Users/alex/.local/state/vinix/android/window-system-ui-fixture-2026-10-30-r2/probe.apk'
const window_system_ui_apk_pin = 'af7f9bfcb8f106c43f9d86badfa2c5e0deb49e3a1e6da19cbe68ab6a5254ca90'
const seed_account_options_api_runner = '/Users/alex/.local/state/vinix/android/seed-account-options-api-run-2026-10-30-r1/run'
const seed_account_options_api_runner_pin = 'f4750504c0e8c7718773095c04661d18003098fe60db89434e0d9a2182da3862'
const seed_account_options_apk = '/Users/alex/.local/state/vinix/android/seed-account-options-fixture-2026-10-30-r1/probe.apk'
const seed_account_options_apk_pin = '36c87d606306c799f50771ab0bed5cacdf07603e96f3e85b6c4aab4870f1f333'
const persistent_data_block_api_runner = '/Users/alex/.local/state/vinix/android/persistent-data-block-api-run-2026-10-30-r1/run'
const persistent_data_block_api_runner_pin = '7d5d99c7ece106a16fa1ffe277a909feb665744651c986e88d96780c025c4df0'
const persistent_data_block_apk = '/Users/alex/.local/state/vinix/android/persistent-data-block-fixture-2026-10-30-r1/probe.apk'
const persistent_data_block_apk_pin = '0acd05b909c7c2d3b798cb515a799df8c40263af9be1e7ab4334f7b4f113b7a8'
const bitmap_tiles_api_runner = '/Users/alex/.local/state/vinix/android/bitmap-tiles-api-run-2026-10-30-r1/run'
const bitmap_tiles_api_runner_pin = 'a12a419781dcc81d59b7edf076a9f535ccc7d55c731a3296a63c2a3bcb8a205a'
const bitmap_tiles_apk = '/Users/alex/.local/state/vinix/android/bitmap-tiles-fixture-2026-10-30-r2/probe.apk'
const bitmap_tiles_apk_pin = 'd4aedf04a871758249fbea08e79a7ac49f9fdb2eb98f915f6a7c8ee389fede7c'
const connectivity_truth_api_runner = '/Users/alex/.local/state/vinix/android/connectivity-truth-api-run-2026-10-30-r1/run'
const connectivity_truth_api_runner_pin = 'aada0a7bd5b920ff42734764511f1368595645a9d3636f3068bff08b534f1c43'
const connectivity_truth_apk = '/Users/alex/.local/state/vinix/android/connectivity-truth-fixture-2026-10-30-r2/probe.apk'
const connectivity_truth_apk_pin = 'e562c6344c8560908a5d5cd70fa0480d76ea60ba6929e0720a2fbe69abba943d'
const window_animations_api_runner = '/Users/alex/.local/state/vinix/android/window-animations-api-run-2026-10-30-r1/run'
const window_animations_api_runner_pin = '050cef8a7a79ea5c1a1b460ad539b72234de936b983ae85210d529bdabb382cc'
const window_animations_apk = '/Users/alex/.local/state/vinix/android/window-animations-fixture-2026-10-30-r1/probe.apk'
const window_animations_apk_pin = 'b78a43516d2f5f42ec7686c39acd81b3612402d80eb25ccd854de512fd6119a6'
const layout_alignment_api_runner = '/Users/alex/.local/state/vinix/android/layout-alignment-api-run-2026-10-30-r1/run'
const layout_alignment_api_runner_pin = '45d4bc546ce4bbb3e30a9ac6bec9c1a88f006647de33e30ba7be942215ef01c8'
const layout_alignment_apk = '/Users/alex/.local/state/vinix/android/layout-alignment-fixture-2026-10-30-r1/probe.apk'
const layout_alignment_apk_pin = 'd0a5f8524c5d135cce08705946d72487947b637b0d7c1c7fa77994a323111fd6'
const user_restrictions_api_runner = '/Users/alex/.local/state/vinix/android/user-restrictions-api-run-2026-10-31-r2/run'
const user_restrictions_api_runner_pin = 'b17eec119da181bc0be8ca04351d895deb600104907bf21d8cbb7231ce415fbe'
const user_restrictions_apk = '/Users/alex/.local/state/vinix/android/user-restrictions-fixture-2026-10-30-r1/probe.apk'
const user_restrictions_apk_pin = '19f8715bcc6e5f19dff1dc11e031912907d7c762a7f1927b85dda697f447dbea'
const bundle_cross_profile_api_runner = '/Users/alex/.local/state/vinix/android/bundle-cross-profile-api-run-2026-10-31-r1/run'
const bundle_cross_profile_api_runner_pin = 'ca7165c9758553dedc6815451f2a8618f56357e097dc5718188688b3e88dc7e1'
const bundle_cross_profile_apk = '/Users/alex/.local/state/vinix/android/bundle-boolean-fixture-2026-10-31-r1/probe.apk'
const bundle_cross_profile_apk_pin = 'c781769a0ef5fd5357ae1f678d52ef98a2532a5ae07c155a013e278a7b2248ab'
const resources_float_api_runner = '/Users/alex/.local/state/vinix/android/resources-float-api-run-2026-11-01-r1/run'
const resources_float_api_runner_pin = 'dbe6ed9779facb8de3257eaf76b0420ac6a60f777af7575dacfb6a1ac35d04f9'
const resources_float_apk = '/Users/alex/.local/state/vinix/android/resources-float-fixture-2026-10-31-r1/probe.apk'
const resources_float_apk_pin = '59439180e4b2bff8c533689db5e4f6ba121406a3cb4950b3746f170a960a7d93'
const paint_drawable_api_runner = '/Users/alex/.local/state/vinix/android/paint-drawable-api-run-2026-11-01-r1/run'
const paint_drawable_api_runner_pin = 'b18b61aa29edd5760e06c164899ed66fd220e1d74e1715c511b984b7ab68d43e'
const paint_drawable_apk = '/Users/alex/.local/state/vinix/android/paint-drawable-fixture-2026-11-01-r1/probe.apk'
const paint_drawable_apk_pin = 'cd459b703196920a7e07e1bfdb7d43e304c1115b12b1ad0998281fab1ea64868'
const dialog_theme_api_runner = '/Users/alex/.local/state/vinix/android/dialog-theme-api-run-2026-11-01-r1/run'
const dialog_theme_api_runner_pin = 'bfcc6464a0d55f1fd9ce2ec452f834f01c3aa6d6525c470bbec2bf74d6cdbb08'
const dialog_theme_apk = '/Users/alex/.local/state/vinix/android/dialog-theme-fixture-2026-11-01-r2/probe.apk'
const dialog_theme_apk_pin = '57e1bc1d8f1df2874be1c4837f169176e5fa88310f37ea99fd726c5f839a2161'
const intent_extras_api_runner = '/Users/alex/.local/state/vinix/android/intent-extras-api-run-2026-11-01-r2/run'
const intent_extras_api_runner_pin = 'cad7bf5ff030b01af3bcf9a7cfc4b0bd41d3b54d93a7a864bc19daade444cc12'
const intent_extras_apk = '/Users/alex/.local/state/vinix/android/intent-extras-fixture-2026-11-01-r2/probe.apk'
const intent_extras_apk_pin = 'b3e0278a185bb3f7f1a302c2f515fa7a4b98edf4cfcefd69ede3f45f85a5ba2c'
// Distinct verified resource-lock fixture ARM runner and signed APK.
const resource_locks_api_runner = '/Users/alex/.local/state/vinix/android/resource-locks-api-run-2026-11-01-r4/run'
const resource_locks_api_runner_pin = '8cf50d0972cda4bfa445f33a944b19026eae862cf5caa00f0292bc44453d6bca'
const resource_locks_apk = '/Users/alex/.local/state/vinix/android/resource-lock-fixture-2026-11-01-r6/probe.apk'
const resource_locks_apk_pin = 'eedcc5a40c86f2f6131121e922a7625e416f5df68671baa70cea581246c3e55e'
// Distinct verified PendingIntent fixture ARM runner and signed APK.
const pending_intent_api_runner = '/Users/alex/.local/state/vinix/android/pending-intent-api-run-2026-11-02-r1/run'
const pending_intent_api_runner_pin = '1c54386f45e64b1879cc6d0954b8dff59dc605ad6a70b52b286e86ccdaaaeecf'
const pending_intent_apk = '/Users/alex/.local/state/vinix/android/pending-intent-fixture-2026-11-02-r1/probe.apk'
const pending_intent_apk_pin = '24ee07ce193fbde0ee448aeceee70a6013095301cbb6b487c9e61aaf175a9456'
// Distinct verified stable-display fixture ARM runner and signed APK.
const stable_display_api_runner = '/Users/alex/.local/state/vinix/android/stable-display-api-run-2026-11-02-r2/run'
const stable_display_api_runner_pin = '2e819f47963d75a09345cacea3a81db28c119d267bff5818c6d0de6e4a5b476b'
const stable_display_apk = '/Users/alex/.local/state/vinix/android/stable-display-fixture-2026-11-02-r2/probe.apk'
const stable_display_apk_pin = '190b832396158ce1ac584ef41abf279d6f13b82b001d17c35e2bd711d5ebcee1'
// Distinct verified asset-locales fixture ARM runner and signed APK.
const asset_locales_api_runner = '/Users/alex/.local/state/vinix/android/asset-locales-api-run-2026-11-02-r1/run'
const asset_locales_api_runner_pin = '8470df7af7820263e1c2dfb132f51f2fadc808e759d07dce7212344af9a20885'
const asset_locales_apk = '/Users/alex/.local/state/vinix/android/asset-locales-fixture-2026-11-02-r1/probe.apk'
const asset_locales_apk_pin = '03877624fde8928fac5efb3a2c49d9306356f5cb1488c3fa343799a39044a265'
// Distinct verified unmanaged-queries fixture ARM runner and signed APK.
const unmanaged_queries_api_runner = '/Users/alex/.local/state/vinix/android/unmanaged-queries-api-run-2026-11-02-r1/run'
const unmanaged_queries_api_runner_pin = '1e056cefa8c7af1ffc0f9477fcd22b4377f290129d560981e6c13ba8ca52872f'
const unmanaged_queries_apk = '/Users/alex/.local/state/vinix/android/unmanaged-queries-fixture-2026-11-02-r1/probe.apk'
const unmanaged_queries_apk_pin = 'dcea26199cfb0bfc2b0b44126b45923c717893b3670f1788b60c4038d4213400'
// Distinct verified stats-unavailable fixture ARM runner and signed APK.
const stats_unavailable_api_runner = '/Users/alex/.local/state/vinix/android/stats-unavailable-api-run-2026-11-02-r1/run'
const stats_unavailable_api_runner_pin = '53299db9d33cb1f1513ff80ba81037bad675c59be949ddd3d675dfdaa7131520'
const stats_unavailable_apk = '/Users/alex/.local/state/vinix/android/stats-unavailable-fixture-2026-11-02-r1/probe.apk'
const stats_unavailable_apk_pin = 'a0742e010e52dd042500a6811fddc6fe369b28852a85bfd22987dbb0c894a4dc'
// Distinct verified subscription-service fixture ARM runner and signed APK.
const subscription_service_api_runner = '/Users/alex/.local/state/vinix/android/subscription-service-api-run-2026-11-02-r1/run'
const subscription_service_api_runner_pin = 'dfc7f4a0e6dfc299f88568c739a07e5fd87766e570871086c35834f52b7513dd'
const subscription_service_apk = '/Users/alex/.local/state/vinix/android/subscription-service-fixture-2026-11-02-r1/probe.apk'
const subscription_service_apk_pin = 'c841324557b839b051bceb8f847d9e943cb69139ebe09d0422b13938164853e5'
// Distinct verified autofill-service fixture ARM runner and signed APK.
const autofill_service_api_runner = '/Users/alex/.local/state/vinix/android/autofill-service-api-run-2026-11-02-r1/run'
const autofill_service_api_runner_pin = 'ba3c6e2a2b88406441210b2f58113e6b70fcdba43e36600aa17b3da07644af69'
const autofill_service_apk = '/Users/alex/.local/state/vinix/android/autofill-service-fixture-2026-11-02-r1/probe.apk'
const autofill_service_apk_pin = 'e9e3e6ce83e99f439550d494438fb3d245d67d74be3f915dcecf83b7c452e360'
// Distinct verified keyguard-policy fixture ARM runner and signed APK.
const keyguard_policy_api_runner = '/Users/alex/.local/state/vinix/android/keyguard-policy-api-run-2026-11-02-r1/run'
const keyguard_policy_api_runner_pin = '35177750c4935e36001810f24281377e0c83a609677b45476a518ce4639027b4'
const keyguard_policy_apk = '/Users/alex/.local/state/vinix/android/keyguard-policy-fixture-2026-11-02-r1/probe.apk'
const keyguard_policy_apk_pin = 'e02a832fa82b6531fe8928d119e6113bc1abfe94c722e020f4ede1b4179f0454'
// Distinct verified broadcast-permission fixture ARM runner and signed APK.
const broadcast_permission_api_runner = '/Users/alex/.local/state/vinix/android/broadcast-permission-api-run-2026-11-02-r1/run'
const broadcast_permission_api_runner_pin = '8de1014a44c56cf05d336643a24baeca31886139afab148b1fbf783911126881'
const broadcast_permission_apk = '/Users/alex/.local/state/vinix/android/broadcast-permission-fixture-2026-11-02-r2/probe.apk'
const broadcast_permission_apk_pin = '0219961f053e02b8d4435b87e86acec64e56d57eb2b68d2f175638016eda37b5'
// Distinct verifier-corrected broadcast-permission fixture and ARM runner.
const broadcast_permission_v2_api_runner = '/Users/alex/.local/state/vinix/android/broadcast-permission-v2-api-run-2026-11-02-r1/run'
const broadcast_permission_v2_api_runner_pin = '4b7de3a657bb55efd4ee80dee23cdaaf7677b070518e594d270af6232005f5e0'
const broadcast_permission_v2_apk = '/Users/alex/.local/state/vinix/android/broadcast-permission-fixture-2026-11-02-r3/probe.apk'
const broadcast_permission_v2_apk_pin = '8c6446247e9660eb58c54a166c839abe4e372403620d727fa004bafd847d41a3'
// Distinct verified secure-settings fixture ARM runner and signed APK.
const secure_settings_api_runner = '/Users/alex/.local/state/vinix/android/secure-settings-api-run-2026-11-02-r1/run'
const secure_settings_api_runner_pin = '5a0e9319bee33804b3c406d6db9d1893ab4684e041c93db68147e2eaf075218a'
const secure_settings_apk = '/Users/alex/.local/state/vinix/android/secure-settings-fixture-2026-11-02-r1/probe.apk'
const secure_settings_apk_pin = '1e2628151f851619bbae164f0c3a6830c354d11fe3f2104e584afe39482ccdd8'
// Distinct verified usage-inactive fixture ARM runner and signed APK.
const usage_inactive_api_runner = '/Users/alex/.local/state/vinix/android/usage-inactive-api-run-2026-11-02-r1/run'
const usage_inactive_api_runner_pin = 'd2adc8c54ccfdda67845e0d8b29f0ee4204dbb5066ab2487dc41129a95f7b179'
const usage_inactive_apk = '/Users/alex/.local/state/vinix/android/usage-inactive-fixture-2026-11-02-r1/probe.apk'
const usage_inactive_apk_pin = 'ae580b4c0ed99b97787f552d8e6f08a94daeed137fc346440cea832a7795a3d2'
// Distinct verified Messenger Binder fixture ARM runner and signed APK.
const messenger_binder_api_runner = '/Users/alex/.local/state/vinix/android/messenger-binder-api-run-2026-11-02-r1/run'
const messenger_binder_api_runner_pin = 'b8ed42d605b5f81d6900515cc3389a3fa6811ec813fd6bb3fd53078f0d62698c'
const messenger_binder_apk = '/Users/alex/.local/state/vinix/android/messenger-binder-fixture-2026-11-02-r2/probe.apk'
const messenger_binder_apk_pin = '7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a'
// V2 changes only the runtime pair; its exact signed APK is deliberately shared with V1.
const messenger_binder_v2_api_runner = '/Users/alex/.local/state/vinix/android/messenger-binder-v2-api-run-2026-11-02-r1/run'
const messenger_binder_v2_api_runner_pin = '077e2a7ad387594f3dcb6caa7eac3762c9e884370283436479e6f56758a5ab88'
const messenger_binder_v2_apk = messenger_binder_apk
const messenger_binder_v2_apk_pin = messenger_binder_apk_pin
// Distinct verified EventLog fixture ARM runner and signed APK.
const event_log_api_runner = '/Users/alex/.local/state/vinix/android/event-log-api-run-2026-11-02-r1/run'
const event_log_api_runner_pin = '36a9b6f597cd620c0a4a9ff805a960fa8260fbb9278f3db853212e7ee6b763ff'
const event_log_apk = '/Users/alex/.local/state/vinix/android/event-log-fixture-2026-11-02-r1/probe.apk'
const event_log_apk_pin = '22d733567f05b56fe7b40183c83eea5b680b867771620f9440a14939835c2844'
// Distinct verified Build ABIs fixture ARM runner and signed APK.
const build_abis_api_runner = '/Users/alex/.local/state/vinix/android/build-abis-api-run-2026-11-02-r1/run'
const build_abis_api_runner_pin = '31fe9f0fe8d80ac5c568d380fb0317afba9fc672f8c490d5b8289aea3b80d1ff'
const build_abis_apk = '/Users/alex/.local/state/vinix/android/build-abis-fixture-2026-11-02-r1/probe.apk'
const build_abis_apk_pin = '2036c430d632f7fbca0cfbbe2c0c975b146e80686934fc482ae59ab9662b439a'
// Distinct verified WebView provider-package fixture and fresh coupled runtime.
const webview_package_api_runner = '/Users/alex/.local/state/vinix/android/webview-package-api-run-2026-11-03-r1/run'
const webview_package_api_runner_pin = 'b62f42bc279412b845884875d57f1b63a10ec31a8c9d1fcfbab69af7fcd444fa'
const webview_package_apk = '/Users/alex/.local/state/vinix/android/webview-package-fixture-2026-11-03-r1/probe.apk'
const webview_package_apk_pin = '896cd9dbec8ccde28d3e0363c1a77ad593708c3ef7e73cf57001e2ae19327579'
// Distinct boot-classpath fixture ARM runner and signed two-class APK.
const bootclasspath_api_runner = '/Users/alex/.local/state/vinix/android/bootclasspath-api-run-2026-11-03-r1/run'
const bootclasspath_api_runner_pin = '047ec4bd70628a7b7e2c81621f306a2065537cbcb8d711d25403c99a19e8a3fb'
const bootclasspath_apk = '/Users/alex/.local/state/vinix/android/bootclasspath-fixture-2026-11-03-r1/probe.apk'
const bootclasspath_apk_pin = 'bd7384342cb18c6d9d519186f921bba9c6acfe5c0f07b75f3db16dfc650a22e4'
// The JNI retry retains the exact signed fixture; its ARM runner is separate.
const bootclasspath_jni_api_runner = '/Users/alex/.local/state/vinix/android/bootclasspath-jni-api-run-2026-11-04-r1/run'
const bootclasspath_jni_api_runner_pin = '1b1103b948baf32b7b71741887cbdb033b7833c9833ce114ad0addbe0b4eb24c'
const bootclasspath_jni_apk = bootclasspath_apk
const bootclasspath_jni_apk_pin = bootclasspath_apk_pin
const traffic_stats_uid_api_runner = '/Users/alex/.local/state/vinix/android/traffic-stats-uid-api-run-2026-11-04-r1/run'
const traffic_stats_uid_api_runner_pin = '370beb2dbfc5418dc53db6cc422968932f7e0a3a8e65ec66bd382f4d2fa9cac2'
const traffic_stats_uid_apk = '/Users/alex/.local/state/vinix/android/traffic-stats-uid-fixture-2026-11-04-r1/probe.apk'
const traffic_stats_uid_apk_pin = 'bf1045fb4fd9c5fb468c7c59f7f594654de15cd6b54f9e07bc3f2aa4bc199cc1'
const process_packages_api_runner = '/Users/alex/.local/state/vinix/android/process-packages-api-run-2026-11-04-r1/run'
// Exact static ARM runner from the guarded process-package delivery build.
const process_packages_api_runner_pin = '725710de6957816c0ece03008c54bf3ca78bc31635d9495c18a04a922f12d21f'
const process_packages_apk = '/Users/alex/.local/state/vinix/android/process-packages-fixture-2026-11-04-r2/probe.apk'
const process_packages_apk_pin = 'db555d086522f003e912e3de5fcf0905d3079025c92397c7b92c6ba714d497e7'
// Distinct qualified static ARM runner and signed Global String-write fixture.
const global_settings_string_api_runner = '/Users/alex/.local/state/vinix/android/global-settings-string-api-run-2026-11-05-r1/run'
const global_settings_string_api_runner_pin = '7dedaf0f25f4eb3daa9a6af9f94b6d65329dded9d90645fa2d1f37c195010ae7'
const global_settings_string_apk = '/Users/alex/.local/state/vinix/android/global-settings-string-fixture-2026-11-05-r1/probe.apk'
const global_settings_string_apk_pin = 'faee136b4cdb500ff165b7b7aceb6649f8af27054593a5905a64f217553c806a'
// Draft only: qualify the final static ARM runner after SDK/native pins settle.
const default_network_active_api_runner = '/Users/alex/.local/state/vinix/android/default-network-active-api-run-2026-11-05-r1/run'
const default_network_active_api_runner_pin = ''
const default_network_active_apk = '/Users/alex/.local/state/vinix/android/default-network-active-fixture-2026-11-05-r2/probe.apk'
const default_network_active_apk_pin = 'be0b524b85218bd0f570fe72a0154c97c06bc15c32271e140c3c39eb76090dd2'
const file_limit = 32 * 1024 * 1024
const request_limit = 12
const seconds_limit = 600
const scope = 'Credential-free generic ART fixture transfer only; no Google account sign-in evidence.'

struct Asset {
	url string
	path string
	sha256 string
	bytes u64
}

struct Event {
	request int
	status int
	url string
	error string
}

struct Outcome {
	success bool
	reason string
	events []Event
	completed []string
}

fn valid_digest(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn external(root string) ! {
	parent := os.dir(root)
	name := os.file_name(root)
	if !root.starts_with('/') || root.contains_any('\x00\r\n\\') || name in ['', '.', '..']
		|| os.real_path(parent) != parent || parent + '/' + name != root {
		return error('canonical absolute external output required')
	}
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output must be outside Git checkouts') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn create(path string) !int {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('fresh private output file required: ' + path) }
	return fd
}

fn write_fd(fd int, data []u8) ! {
	mut offset := 0
	for offset < data.len {
		n := unsafe { C.write(fd, &u8(data.data) + offset, uint(data.len - offset)) }
		if n <= 0 { return error('file write failed') }
		offset += int(n)
	}
}

fn write_json(path string, value string) ! {
	fd := create(path)!
	defer { C.close(fd) }
	write_fd(fd, (value + '\n').bytes())!
}

fn open_bounded(path string) !(int, u64) {
	if os.real_path(path) != path { return error('canonical regular input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open input') }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG
		|| st.st_size <= 0 || st.st_size > file_limit {
		C.close(fd)
		return error('nonempty regular input at most 32 MiB required')
	}
	return fd, u64(st.st_size)
}

// Snapshot only the selected bounded inputs. Verify bytes while copying; serving never
// resolves a request path to a filesystem path or opens another input.
fn snapshot(input Asset, output string) !Asset {
	if !valid_digest(input.sha256) { return error('pinned fixture digest required') }
	fd, size := open_bounded(input.path)!
	defer { C.close(fd) }
	out := create(output)!
	defer { C.close(out) }
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('input read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('input grew during snapshot') }
		hash.write(buffer[..int(n)])!
		write_fd(out, buffer[..int(n)])!
	}
	if count != size || hash.sum([]u8{}).hex() != input.sha256 {
		return error('input size or SHA256 differs')
	}
	os.chmod(output, 0o400)!
	return Asset{url: input.url, path: output, sha256: input.sha256, bytes: count}
}

fn parse_request(header string) !(string, int) {
	if header.len > 8192 || !header.ends_with('\r\n\r\n')
		|| header.contains('\x00') || header.bytes().any(it < 32 && it !in [u8(`\r`), `\n`, `\t`]) {
		return error('invalid bounded HTTP headers')
	}
	lines := header[..header.len - 4].split('\r\n')
	parts := lines[0].split(' ')
	if parts.len != 3 || parts[2] !in ['HTTP/1.0', 'HTTP/1.1'] { return error('invalid request line') }
	if parts[0] != 'GET' { return parts[1], 405 }
	for line in lines[1..] {
		index := line.index(':') or { return error('invalid header') }
		if index == 0 { return error('empty header name') }
		name := line[..index].to_lower()
		if name == 'transfer-encoding' || (name == 'content-length' && line[index + 1..].trim_space() != '0') {
			return error('request body is not allowed')
		}
	}
	return parts[1], 200
}

fn read_request(mut connection net.TcpConn) !string {
	mut header := []u8{cap: 8192}
	mut buffer := []u8{len: 1024}
	for header.len < 8192 {
		n := connection.read(mut buffer[..int_min(buffer.len, 8192 - header.len)])!
		if n <= 0 { return error('incomplete request') }
		header << buffer[..n]
		if end := header.bytestr().index('\r\n\r\n') {
			if end + 4 != header.len { return error('request body or pipelining rejected') }
			return header.bytestr()
		}
	}
	return error('request headers exceed 8 KiB')
}

fn status(mut connection net.TcpConn, code int) ! {
	label := if code == 405 { 'Method Not Allowed' } else if code == 404 { 'Not Found' } else { 'Bad Request' }
	connection.write_string('HTTP/1.1 ' + code.str() + ' ' + label + '\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')!
}

fn send_asset(mut connection net.TcpConn, asset Asset, deadline time.Time) ! {
	fd, size := open_bounded(asset.path)!
	defer { C.close(fd) }
	if size != asset.bytes { return error('snapshot size changed') }
	connection.write_string('HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: '
		+ size.str() + '\r\nX-Content-SHA256: ' + asset.sha256 + '\r\nConnection: close\r\n\r\n')!
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		if time.now() >= deadline { return error('absolute transfer deadline expired') }
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('snapshot read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('snapshot grew') }
		hash.write(buffer[..int(n)])!
		if connection.write(buffer[..int(n)])! != int(n) { return error('short HTTP body write') }
	}
	if count != size || hash.sum([]u8{}).hex() != asset.sha256 { return error('snapshot SHA256 changed') }
}

fn serve_loop(mut listener net.TcpListener, assets []Asset, limit int, deadline time.Time) Outcome {
	mut events := []Event{}
	mut complete := []string{}
	listener.set_accept_deadline(deadline)
	for number in 1 .. limit + 1 {
		mut connection := listener.accept() or {
			return Outcome{reason: 'accept failed or deadline expired: ' + err.msg(), events: events, completed: complete}
		}
		read_deadline := time.now().add(5 * time.second)
		connection.set_read_deadline(if read_deadline < deadline { read_deadline } else { deadline })
		connection.set_write_deadline(deadline)
		mut code := 400
		mut url := ''
		mut message := ''
		header := read_request(mut connection) or { message = err.msg(); '' }
		if header != '' {
			url, code = parse_request(header) or { message = err.msg(); '', 400 }
		}
		mut found := -1
		if code == 200 {
			for index, asset in assets { if url == asset.url { found = index; break } }
			if found < 0 { code = 404 }
		}
		if code == 200 {
			send_asset(mut connection, assets[found], deadline) or { message = err.msg() }
			if message == '' && url !in complete { complete << url }
		} else {
			status(mut connection, code) or { message = err.msg() }
		}
		connection.close() or { message += ' close: ' + err.msg() }
		events << Event{number, code, url, message}
		if complete.len == assets.len { return Outcome{success: true, events: events, completed: complete} }
		if time.now() >= deadline { return Outcome{reason: 'absolute deadline expired', events: events, completed: complete} }
	}
	return Outcome{reason: 'request limit exhausted', events: events, completed: complete}
}

fn pinned_assets() []Asset {
	return [Asset{url: '/service-query-run', path: runner_path, sha256: runner_pin},
		Asset{url: '/client.apk', path: fixture_root + '/client/probe.apk', sha256: client_pin},
		Asset{url: '/disabled.apk', path: fixture_root + '/disabled/probe.apk', sha256: disabled_pin}]
}

fn direct_boot_assets() []Asset {
	return [Asset{url: '/direct-boot-run', path: direct_boot_runner, sha256: direct_boot_runner_pin},
		Asset{url: '/client.apk', path: direct_boot_fixture + '/client/probe.apk', sha256: direct_boot_client_pin},
		Asset{url: '/disabled.apk', path: direct_boot_fixture + '/disabled/probe.apk', sha256: direct_boot_disabled_pin}]
}

fn credential_storage_assets() []Asset {
	return [Asset{url: '/credential-storage-run', path: credential_storage_runner, sha256: credential_storage_runner_pin},
		Asset{url: '/client.apk', path: credential_storage_fixture + '/client/probe.apk', sha256: credential_storage_client_pin},
		Asset{url: '/disabled.apk', path: credential_storage_fixture + '/disabled/probe.apk', sha256: credential_storage_disabled_pin}]
}

fn broadcast_result_assets() []Asset {
	return [Asset{url: '/broadcast-result-run', path: broadcast_result_runner, sha256: broadcast_result_runner_pin},
		Asset{url: '/client.apk', path: broadcast_result_fixture + '/client/probe.apk', sha256: broadcast_result_client_pin},
		Asset{url: '/disabled.apk', path: broadcast_result_fixture + '/disabled/probe.apk', sha256: broadcast_result_disabled_pin}]
}

fn onboarding_api_assets() []Asset {
	return [Asset{url: '/onboarding-api-run', path: onboarding_api_runner, sha256: onboarding_api_runner_pin},
		Asset{url: '/child-attach.apk', path: child_attach_apk, sha256: child_attach_apk_pin},
		Asset{url: '/settings-global.apk', path: settings_global_apk, sha256: settings_global_apk_pin}]
}

fn application_restrictions_assets() []Asset {
	return [Asset{url: '/application-restrictions-run', path: application_restrictions_runner, sha256: application_restrictions_runner_pin},
		Asset{url: '/application-restrictions.apk', path: application_restrictions_apk, sha256: application_restrictions_apk_pin}]
}

fn auth_exception_api_assets() []Asset {
	return [Asset{url: '/auth-exception-api-run', path: auth_exception_api_runner, sha256: auth_exception_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network.apk', path: maps_network_apk, sha256: maps_network_apk_pin}]
}

fn auth_worker_api_assets() []Asset {
	return [Asset{url: '/auth-worker-api-run', path: auth_worker_api_runner, sha256: auth_worker_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network-v2.apk', path: maps_network_v2_apk, sha256: maps_network_v2_apk_pin}]
}

fn binder_identity_api_assets() []Asset {
	return [Asset{url: '/binder-identity-api-run', path: binder_identity_api_runner, sha256: binder_identity_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network-v3.apk', path: maps_network_v3_apk, sha256: maps_network_v3_apk_pin}]
}

fn service_lifecycle_api_assets() []Asset {
	return [Asset{url: '/service-lifecycle-api-run', path: service_lifecycle_api_runner, sha256: service_lifecycle_api_runner_pin},
		Asset{url: '/service-lifecycle.apk', path: service_lifecycle_apk, sha256: service_lifecycle_apk_pin}]
}

fn platform_fragments_api_assets() []Asset {
	return [Asset{url: '/platform-fragments-api-run', path: platform_fragments_api_runner, sha256: platform_fragments_api_runner_pin},
		Asset{url: '/platform-fragments.apk', path: platform_fragments_apk, sha256: platform_fragments_apk_pin}]
}

fn image_bounds_api_assets() []Asset {
	return [Asset{url: '/image-bounds-api-run', path: image_bounds_api_runner, sha256: image_bounds_api_runner_pin},
		Asset{url: '/image-bounds.apk', path: image_bounds_apk, sha256: image_bounds_apk_pin}]
}

fn window_system_ui_api_assets() []Asset {
	return [Asset{url: '/window-system-ui-api-run', path: window_system_ui_api_runner, sha256: window_system_ui_api_runner_pin},
		Asset{url: '/window-system-ui.apk', path: window_system_ui_apk, sha256: window_system_ui_apk_pin}]
}

fn seed_account_options_api_assets() []Asset {
	return [Asset{url: '/seed-account-options-api-run', path: seed_account_options_api_runner, sha256: seed_account_options_api_runner_pin},
		Asset{url: '/seed-account-options.apk', path: seed_account_options_apk, sha256: seed_account_options_apk_pin}]
}

fn persistent_data_block_api_assets() []Asset {
	return [Asset{url: '/persistent-data-block-api-run', path: persistent_data_block_api_runner, sha256: persistent_data_block_api_runner_pin},
		Asset{url: '/persistent-data-block.apk', path: persistent_data_block_apk, sha256: persistent_data_block_apk_pin}]
}

fn bitmap_tiles_api_assets() []Asset {
	return [Asset{url: '/bitmap-tiles-api-run', path: bitmap_tiles_api_runner, sha256: bitmap_tiles_api_runner_pin},
		Asset{url: '/bitmap-tiles.apk', path: bitmap_tiles_apk, sha256: bitmap_tiles_apk_pin}]
}

fn connectivity_truth_api_assets() []Asset {
	return [Asset{url: '/connectivity-truth-api-run', path: connectivity_truth_api_runner, sha256: connectivity_truth_api_runner_pin},
		Asset{url: '/connectivity-truth.apk', path: connectivity_truth_apk, sha256: connectivity_truth_apk_pin}]
}

fn window_animations_api_assets() []Asset {
	return [Asset{url: '/window-animations-api-run', path: window_animations_api_runner, sha256: window_animations_api_runner_pin},
		Asset{url: '/window-animations.apk', path: window_animations_apk, sha256: window_animations_apk_pin}]
}

fn layout_alignment_api_assets() []Asset {
	return [Asset{url: '/layout-alignment-api-run', path: layout_alignment_api_runner, sha256: layout_alignment_api_runner_pin},
		Asset{url: '/layout-alignment.apk', path: layout_alignment_apk, sha256: layout_alignment_apk_pin}]
}

fn user_restrictions_api_assets() []Asset {
	return [Asset{url: '/user-restrictions-api-run', path: user_restrictions_api_runner, sha256: user_restrictions_api_runner_pin},
		Asset{url: '/user-restrictions.apk', path: user_restrictions_apk, sha256: user_restrictions_apk_pin}]
}

fn bundle_cross_profile_api_assets() []Asset {
	return [Asset{url: '/bundle-cross-profile-api-run', path: bundle_cross_profile_api_runner, sha256: bundle_cross_profile_api_runner_pin},
		Asset{url: '/bundle-cross-profile.apk', path: bundle_cross_profile_apk, sha256: bundle_cross_profile_apk_pin}]
}

fn user_restrictions_bundle_api_assets() []Asset {
	return [Asset{url: '/user-restrictions-bundle-api-run', path: bundle_cross_profile_api_runner, sha256: bundle_cross_profile_api_runner_pin},
		Asset{url: '/user-restrictions.apk', path: user_restrictions_apk, sha256: user_restrictions_apk_pin}]
}

fn resources_float_api_assets() []Asset {
	return [Asset{url: '/resources-float-api-run', path: resources_float_api_runner, sha256: resources_float_api_runner_pin},
		Asset{url: '/resources-float.apk', path: resources_float_apk, sha256: resources_float_apk_pin}]
}

fn paint_drawable_api_assets() []Asset {
	return [Asset{url: '/paint-drawable-api-run', path: paint_drawable_api_runner, sha256: paint_drawable_api_runner_pin},
		Asset{url: '/paint-drawable.apk', path: paint_drawable_apk, sha256: paint_drawable_apk_pin}]
}

fn dialog_theme_api_assets() []Asset {
	return [Asset{url: '/dialog-theme-api-run', path: dialog_theme_api_runner, sha256: dialog_theme_api_runner_pin},
		Asset{url: '/dialog-theme.apk', path: dialog_theme_apk, sha256: dialog_theme_apk_pin}]
}

fn intent_extras_api_assets() []Asset {
	return [Asset{url: '/intent-extras-api-run', path: intent_extras_api_runner, sha256: intent_extras_api_runner_pin},
		Asset{url: '/intent-extras.apk', path: intent_extras_apk, sha256: intent_extras_apk_pin}]
}

fn resource_locks_api_assets() []Asset {
	return [Asset{url: '/resource-locks-api-run', path: resource_locks_api_runner, sha256: resource_locks_api_runner_pin},
		Asset{url: '/resource-locks.apk', path: resource_locks_apk, sha256: resource_locks_apk_pin}]
}

fn pending_intent_api_assets() []Asset {
	return [Asset{url: '/pending-intent-api-run', path: pending_intent_api_runner, sha256: pending_intent_api_runner_pin},
		Asset{url: '/pending-intent.apk', path: pending_intent_apk, sha256: pending_intent_apk_pin}]
}

fn stable_display_api_assets() []Asset {
	return [Asset{url: '/stable-display-api-run', path: stable_display_api_runner, sha256: stable_display_api_runner_pin},
		Asset{url: '/stable-display.apk', path: stable_display_apk, sha256: stable_display_apk_pin}]
}

fn asset_locales_api_assets() []Asset {
	return [Asset{url: '/asset-locales-api-run', path: asset_locales_api_runner, sha256: asset_locales_api_runner_pin},
		Asset{url: '/asset-locales.apk', path: asset_locales_apk, sha256: asset_locales_apk_pin}]
}

fn unmanaged_queries_api_assets() []Asset {
	return [Asset{url: '/unmanaged-queries-api-run', path: unmanaged_queries_api_runner, sha256: unmanaged_queries_api_runner_pin},
		Asset{url: '/unmanaged-queries.apk', path: unmanaged_queries_apk, sha256: unmanaged_queries_apk_pin}]
}

fn stats_unavailable_api_assets() []Asset {
	return [Asset{url: '/stats-unavailable-api-run', path: stats_unavailable_api_runner, sha256: stats_unavailable_api_runner_pin},
		Asset{url: '/stats-unavailable.apk', path: stats_unavailable_apk, sha256: stats_unavailable_apk_pin}]
}

fn subscription_service_api_assets() []Asset {
	return [Asset{url: '/subscription-service-api-run', path: subscription_service_api_runner, sha256: subscription_service_api_runner_pin},
		Asset{url: '/subscription-service.apk', path: subscription_service_apk, sha256: subscription_service_apk_pin}]
}

fn autofill_service_api_assets() []Asset {
	return [Asset{url: '/autofill-service-api-run', path: autofill_service_api_runner, sha256: autofill_service_api_runner_pin},
		Asset{url: '/autofill-service.apk', path: autofill_service_apk, sha256: autofill_service_apk_pin}]
}

fn keyguard_policy_api_assets() []Asset {
	return [Asset{url: '/keyguard-policy-api-run', path: keyguard_policy_api_runner, sha256: keyguard_policy_api_runner_pin},
		Asset{url: '/keyguard-policy.apk', path: keyguard_policy_apk, sha256: keyguard_policy_apk_pin}]
}

fn broadcast_permission_api_assets() []Asset {
	return [Asset{url: '/broadcast-permission-api-run', path: broadcast_permission_api_runner, sha256: broadcast_permission_api_runner_pin},
		Asset{url: '/broadcast-permission.apk', path: broadcast_permission_apk, sha256: broadcast_permission_apk_pin}]
}

fn broadcast_permission_v2_api_assets() []Asset {
	return [Asset{url: '/broadcast-permission-v2-api-run', path: broadcast_permission_v2_api_runner, sha256: broadcast_permission_v2_api_runner_pin},
		Asset{url: '/broadcast-permission-v2.apk', path: broadcast_permission_v2_apk, sha256: broadcast_permission_v2_apk_pin}]
}

fn secure_settings_api_assets() []Asset {
	return [Asset{url: '/secure-settings-api-run', path: secure_settings_api_runner, sha256: secure_settings_api_runner_pin},
		Asset{url: '/secure-settings.apk', path: secure_settings_apk, sha256: secure_settings_apk_pin}]
}

fn usage_inactive_api_assets() []Asset {
	return [Asset{url: '/usage-inactive-api-run', path: usage_inactive_api_runner, sha256: usage_inactive_api_runner_pin},
		Asset{url: '/usage-inactive.apk', path: usage_inactive_apk, sha256: usage_inactive_apk_pin}]
}

fn messenger_binder_api_assets() []Asset {
	return [Asset{url: '/messenger-binder-api-run', path: messenger_binder_api_runner, sha256: messenger_binder_api_runner_pin},
		Asset{url: '/messenger-binder.apk', path: messenger_binder_apk, sha256: messenger_binder_apk_pin}]
}

fn messenger_binder_v2_api_assets() []Asset {
	return [Asset{url: '/messenger-binder-v2-api-run', path: messenger_binder_v2_api_runner, sha256: messenger_binder_v2_api_runner_pin},
		Asset{url: '/messenger-binder-v2.apk', path: messenger_binder_v2_apk, sha256: messenger_binder_v2_apk_pin}]
}

fn event_log_api_assets() []Asset {
	return [Asset{url: '/event-log-api-run', path: event_log_api_runner, sha256: event_log_api_runner_pin},
		Asset{url: '/event-log.apk', path: event_log_apk, sha256: event_log_apk_pin}]
}

fn build_abis_api_assets() []Asset {
	return [Asset{url: '/build-abis-api-run', path: build_abis_api_runner, sha256: build_abis_api_runner_pin},
		Asset{url: '/build-abis.apk', path: build_abis_apk, sha256: build_abis_apk_pin}]
}

fn webview_package_api_assets() []Asset {
	return [Asset{url: '/webview-package-api-run', path: webview_package_api_runner, sha256: webview_package_api_runner_pin},
		Asset{url: '/webview-package.apk', path: webview_package_apk, sha256: webview_package_apk_pin}]
}

fn bootclasspath_api_assets() []Asset {
	return [Asset{url: '/bootclasspath-api-run', path: bootclasspath_api_runner, sha256: bootclasspath_api_runner_pin},
		Asset{url: '/bootclasspath.apk', path: bootclasspath_apk, sha256: bootclasspath_apk_pin}]
}

fn bootclasspath_jni_api_assets() []Asset {
	return [Asset{url: '/bootclasspath-jni-api-run', path: bootclasspath_jni_api_runner, sha256: bootclasspath_jni_api_runner_pin},
		Asset{url: '/bootclasspath-jni.apk', path: bootclasspath_jni_apk, sha256: bootclasspath_jni_apk_pin}]
}

fn traffic_stats_uid_api_assets() []Asset {
	return [Asset{url: '/traffic-stats-uid-api-run', path: traffic_stats_uid_api_runner, sha256: traffic_stats_uid_api_runner_pin},
		Asset{url: '/traffic-stats-uid.apk', path: traffic_stats_uid_apk, sha256: traffic_stats_uid_apk_pin}]
}

fn process_packages_api_assets() []Asset {
	return [Asset{url: '/process-packages-api-run', path: process_packages_api_runner, sha256: process_packages_api_runner_pin},
		Asset{url: '/process-packages.apk', path: process_packages_apk, sha256: process_packages_apk_pin}]
}

fn global_settings_string_api_assets() []Asset {
	return [Asset{url: '/global-settings-string-api-run', path: global_settings_string_api_runner, sha256: global_settings_string_api_runner_pin},
		Asset{url: '/global-settings-string.apk', path: global_settings_string_apk, sha256: global_settings_string_apk_pin}]
}

fn default_network_active_api_assets() []Asset {
	return [Asset{url: '/default-network-active-api-run', path: default_network_active_api_runner, sha256: default_network_active_api_runner_pin},
		Asset{url: '/default-network-active.apk', path: default_network_active_apk, sha256: default_network_active_apk_pin}]
}

fn default_network_active_distinct(asset Asset, old Asset) ! {
	if asset.url == old.url || asset.path == old.path || asset.sha256 == old.sha256 {
		return error('default network activity route or artifact collision')
	}
}

// This selector retains historical routing and the existing bounded protocol.
fn serve_default_network_active(root string, port string) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if default_network_active_api_runner == '' || default_network_active_apk == ''
		|| !valid_digest(default_network_active_api_runner_pin) || !valid_digest(default_network_active_apk_pin) {
		return error('qualified default network activity artifact paths and pins required')
	}
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := default_network_active_api_assets()
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any('vinix-default-network-active-api-http-v1')
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS two pinned files transferred')
}

fn global_settings_string_distinct(asset Asset, old Asset) ! {
	if asset.url == old.url || asset.path == old.path || asset.sha256 == old.sha256 {
		return error('Global settings String route or artifact collision')
	}
}

// This independent selector keeps all historical dispatch and shared-APK
// exceptions intact. Only its two pinned snapshots enter the bounded server.
fn serve_global_settings_string(root string, port string) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if global_settings_string_api_runner == '' || global_settings_string_apk == ''
		|| !valid_digest(global_settings_string_api_runner_pin) || !valid_digest(global_settings_string_apk_pin) {
		return error('qualified Global settings String artifact paths and pins required')
	}
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := global_settings_string_api_assets()
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any('vinix-global-settings-string-api-http-v1')
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS two pinned files transferred')
}

fn process_packages_distinct(asset Asset, old Asset) ! {
	if asset.url == old.url || asset.path == old.path || asset.sha256 == old.sha256 {
		return error('process packages route or artifact collision')
	}
}

// Additive dispatch preserves all historical selectors and shared-APK exceptions.
// This profile admits only its distinct newly qualified runner and fixture.
fn serve_process_packages(root string, port string) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if !valid_digest(process_packages_api_runner_pin) || !valid_digest(process_packages_apk_pin) {
		return error('qualified process packages artifact pins required')
	}
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := process_packages_api_assets()
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any('vinix-process-packages-api-http-v1')
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS two pinned files transferred')
}

fn traffic_stats_uid_distinct(asset Asset, old Asset) ! {
	if asset.url == old.url || asset.path == old.path || asset.sha256 == old.sha256 {
		return error('TrafficStats UID route or artifact collision')
	}
}

// Additive dispatch keeps every historical selector and shared-APK exception
// unchanged. This profile has no shared route, source path or digest exception.
fn serve_traffic_stats_uid(root string, port string) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if !valid_digest(traffic_stats_uid_api_runner_pin) { return error('qualified TrafficStats UID runner pin required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := traffic_stats_uid_api_assets()
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any('vinix-traffic-stats-uid-api-http-v1')
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS two pinned files transferred')
}

// Only the exact old/new signed boot APK pair may share a source path/hash.
// Both routes remain distinct, and every other collision still fails closed.
fn bootclasspath_jni_distinct(asset Asset, old Asset) ! {
	if asset.url == old.url { return error('bootclasspath JNI route collision') }
	if asset.url == '/bootclasspath-jni.apk' && old.url == '/bootclasspath.apk' {
		if asset.path != bootclasspath_apk || old.path != bootclasspath_apk
			|| asset.sha256 != bootclasspath_apk_pin || old.sha256 != bootclasspath_apk_pin {
			return error('only the exact signed bootclasspath APK may be reused')
		}
	} else if asset.path == old.path || asset.sha256 == old.sha256 {
		return error('bootclasspath JNI artifact collision')
	}
}

// Keep historical selector dispatch byte-for-byte intact. This additive pair
// uses the same pinned snapshots, bounded GET server, request limit and deadline.
fn serve_bootclasspath_jni(root string, port string) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := bootclasspath_jni_api_assets()
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any('vinix-bootclasspath-jni-api-http-v1')
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS two pinned files transferred')
}

fn serve(root string, port string, is_direct_boot bool, is_credential_storage bool, is_broadcast_result bool, is_onboarding_api bool, is_application_restrictions bool, is_auth_exception_api bool, is_auth_worker_api bool, is_binder_identity_api bool, is_service_lifecycle_api bool, is_platform_fragments_api bool, is_image_bounds_api bool, is_window_system_ui_api bool, is_seed_account_options_api bool, is_persistent_data_block_api bool, is_bitmap_tiles_api bool, is_connectivity_truth_api bool, is_window_animations_api bool, is_layout_alignment_api bool, is_user_restrictions_api bool, is_bundle_cross_profile_api bool, is_user_restrictions_bundle_api bool, is_resources_float_api bool, is_paint_drawable_api bool, is_dialog_theme_api bool, is_intent_extras_api bool, is_resource_locks_api bool, is_pending_intent_api bool, is_stable_display_api bool, is_asset_locales_api bool, is_unmanaged_queries_api bool, is_stats_unavailable_api bool, is_subscription_service_api bool, is_autofill_service_api bool, is_keyguard_policy_api bool, is_broadcast_permission_api bool, is_broadcast_permission_v2_api bool, is_secure_settings_api bool, is_usage_inactive_api bool, is_messenger_binder_api bool, is_messenger_binder_v2_api bool, is_event_log_api bool, is_build_abis_api bool, is_webview_package_api bool, is_bootclasspath_api bool) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := if is_bootclasspath_api { bootclasspath_api_assets() } else if is_webview_package_api { webview_package_api_assets() } else if is_build_abis_api { build_abis_api_assets() } else if is_event_log_api { event_log_api_assets() } else if is_messenger_binder_v2_api { messenger_binder_v2_api_assets() } else if is_messenger_binder_api { messenger_binder_api_assets() } else if is_usage_inactive_api { usage_inactive_api_assets() } else if is_secure_settings_api { secure_settings_api_assets() } else if is_broadcast_permission_v2_api { broadcast_permission_v2_api_assets() } else if is_broadcast_permission_api { broadcast_permission_api_assets() } else if is_keyguard_policy_api { keyguard_policy_api_assets() } else if is_autofill_service_api { autofill_service_api_assets() } else if is_subscription_service_api { subscription_service_api_assets() } else if is_stats_unavailable_api { stats_unavailable_api_assets() } else if is_unmanaged_queries_api { unmanaged_queries_api_assets() } else if is_asset_locales_api { asset_locales_api_assets() } else if is_stable_display_api { stable_display_api_assets() } else if is_pending_intent_api { pending_intent_api_assets() } else if is_resource_locks_api { resource_locks_api_assets() } else if is_intent_extras_api { intent_extras_api_assets() } else if is_dialog_theme_api { dialog_theme_api_assets() } else if is_paint_drawable_api { paint_drawable_api_assets() } else if is_resources_float_api { resources_float_api_assets() } else if is_user_restrictions_bundle_api { user_restrictions_bundle_api_assets() } else if is_bundle_cross_profile_api { bundle_cross_profile_api_assets() } else if is_user_restrictions_api { user_restrictions_api_assets() } else if is_layout_alignment_api { layout_alignment_api_assets() } else if is_window_animations_api { window_animations_api_assets() } else if is_connectivity_truth_api { connectivity_truth_api_assets() } else if is_bitmap_tiles_api { bitmap_tiles_api_assets() } else if is_persistent_data_block_api { persistent_data_block_api_assets() } else if is_seed_account_options_api { seed_account_options_api_assets() } else if is_window_system_ui_api { window_system_ui_api_assets() } else if is_image_bounds_api { image_bounds_api_assets() } else if is_platform_fragments_api { platform_fragments_api_assets() } else if is_service_lifecycle_api { service_lifecycle_api_assets() } else if is_binder_identity_api { binder_identity_api_assets() } else if is_auth_worker_api { auth_worker_api_assets() } else if is_auth_exception_api { auth_exception_api_assets() } else if is_application_restrictions { application_restrictions_assets() } else if is_onboarding_api { onboarding_api_assets() } else if is_broadcast_result { broadcast_result_assets() } else if is_credential_storage { credential_storage_assets() } else if is_direct_boot { direct_boot_assets() } else { pinned_assets() }
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any(if is_bootclasspath_api { 'vinix-bootclasspath-api-http-v1' } else if is_webview_package_api { 'vinix-webview-package-api-http-v1' } else if is_build_abis_api { 'vinix-build-abis-api-http-v1' } else if is_event_log_api { 'vinix-event-log-api-http-v1' } else if is_messenger_binder_v2_api { 'vinix-messenger-binder-v2-api-http-v1' } else if is_messenger_binder_api { 'vinix-messenger-binder-api-http-v1' } else if is_usage_inactive_api { 'vinix-usage-inactive-api-http-v1' } else if is_secure_settings_api { 'vinix-secure-settings-api-http-v1' } else if is_broadcast_permission_v2_api { 'vinix-broadcast-permission-v2-api-http-v1' } else if is_broadcast_permission_api { 'vinix-broadcast-permission-api-http-v1' } else if is_keyguard_policy_api { 'vinix-keyguard-policy-api-http-v1' } else if is_autofill_service_api { 'vinix-autofill-service-api-http-v1' } else if is_subscription_service_api { 'vinix-subscription-service-api-http-v1' } else if is_stats_unavailable_api { 'vinix-stats-unavailable-api-http-v1' } else if is_unmanaged_queries_api { 'vinix-unmanaged-queries-api-http-v1' } else if is_asset_locales_api { 'vinix-asset-locales-api-http-v1' } else if is_stable_display_api { 'vinix-stable-display-api-http-v1' } else if is_pending_intent_api { 'vinix-pending-intent-api-http-v1' } else if is_resource_locks_api { 'vinix-resource-locks-api-http-v1' } else if is_intent_extras_api { 'vinix-intent-extras-api-http-v1' } else if is_dialog_theme_api { 'vinix-dialog-theme-api-http-v1' } else if is_paint_drawable_api { 'vinix-paint-drawable-api-http-v1' } else if is_resources_float_api { 'vinix-resources-float-api-http-v1' } else if is_user_restrictions_bundle_api { 'vinix-user-restrictions-bundle-api-http-v1' } else if is_bundle_cross_profile_api { 'vinix-bundle-cross-profile-api-http-v1' } else if is_user_restrictions_api { 'vinix-user-restrictions-api-http-v1' } else if is_layout_alignment_api { 'vinix-layout-alignment-api-http-v1' } else if is_window_animations_api { 'vinix-window-animations-api-http-v1' } else if is_connectivity_truth_api { 'vinix-connectivity-truth-api-http-v1' } else if is_bitmap_tiles_api { 'vinix-bitmap-tiles-api-http-v1' } else if is_persistent_data_block_api { 'vinix-persistent-data-block-api-http-v1' } else if is_seed_account_options_api { 'vinix-seed-account-options-api-http-v1' } else if is_window_system_ui_api { 'vinix-window-system-ui-api-http-v1' } else if is_image_bounds_api { 'vinix-image-bounds-api-http-v1' } else if is_platform_fragments_api { 'vinix-platform-fragments-api-http-v1' } else if is_service_lifecycle_api { 'vinix-service-lifecycle-api-http-v1' } else if is_binder_identity_api { 'vinix-binder-identity-api-http-v1' } else if is_auth_worker_api { 'vinix-auth-worker-api-http-v1' } else if is_auth_exception_api { 'vinix-auth-exception-api-http-v1' } else if is_application_restrictions { 'vinix-application-restrictions-http-v1' } else if is_onboarding_api { 'vinix-onboarding-api-http-v1' } else if is_broadcast_result { 'vinix-broadcast-result-http-v1' } else if is_credential_storage { 'vinix-credential-storage-http-v1' } else if is_direct_boot { 'vinix-direct-boot-http-v1' } else { 'vinix-service-query-http-v1' })
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println(if is_application_restrictions || is_service_lifecycle_api || is_image_bounds_api || is_window_system_ui_api || is_seed_account_options_api || is_persistent_data_block_api || is_bitmap_tiles_api || is_connectivity_truth_api || is_window_animations_api || is_layout_alignment_api || is_user_restrictions_api || is_bundle_cross_profile_api || is_user_restrictions_bundle_api || is_resources_float_api || is_paint_drawable_api || is_dialog_theme_api || is_intent_extras_api || is_resource_locks_api || is_pending_intent_api || is_stable_display_api || is_asset_locales_api || is_unmanaged_queries_api || is_stats_unavailable_api || is_subscription_service_api || is_autofill_service_api || is_keyguard_policy_api || is_broadcast_permission_api || is_broadcast_permission_v2_api || is_secure_settings_api || is_usage_inactive_api || is_messenger_binder_api || is_messenger_binder_v2_api || is_event_log_api || is_build_abis_api || is_webview_package_api || is_bootclasspath_api { 'SERVICE-QUERY-HTTP PASS two pinned files transferred' } else { 'SERVICE-QUERY-HTTP PASS three pinned files transferred' })
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 && os.args[1] == 'serve' && os.args[2] == '--global-settings-string-api' {
		if os.args.len != 5 {
			eprintln('usage: transfer serve --global-settings-string-api FRESH_EXTERNAL_DIR PORT')
			exit(2)
		}
		serve_global_settings_string(os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 && os.args[1] == 'serve' && os.args[2] == '--default-network-active-api' {
		if os.args.len != 5 {
			eprintln('usage: transfer serve --default-network-active-api FRESH_EXTERNAL_DIR PORT')
			exit(2)
		}
		serve_default_network_active(os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 && os.args[1] == 'serve' && os.args[2] == '--process-packages-api' {
		if os.args.len != 5 {
			eprintln('usage: transfer serve --process-packages-api FRESH_EXTERNAL_DIR PORT')
			exit(2)
		}
		serve_process_packages(os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 && os.args[1] == 'serve' && os.args[2] == '--traffic-stats-uid-api' {
		if os.args.len != 5 {
			eprintln('usage: transfer serve --traffic-stats-uid-api FRESH_EXTERNAL_DIR PORT')
			exit(2)
		}
		serve_traffic_stats_uid(os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len > 2 && os.args[1] == 'serve' && os.args[2] == '--bootclasspath-jni-api' {
		if os.args.len != 5 {
			eprintln('usage: transfer serve --bootclasspath-jni-api FRESH_EXTERNAL_DIR PORT')
			exit(2)
		}
		serve_bootclasspath_jni(os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	is_direct_boot := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--direct-boot'
	is_credential_storage := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--credential-storage'
	is_broadcast_result := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--broadcast-result'
	is_onboarding_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--onboarding-apis'
	is_application_restrictions := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--application-restrictions'
	is_auth_exception_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--auth-exception-apis'
	is_auth_worker_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--auth-worker-apis'
	is_binder_identity_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--binder-identity-apis'
	is_service_lifecycle_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--service-lifecycle-api'
	is_platform_fragments_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--platform-fragments-api'
	is_image_bounds_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--image-bounds-api'
	is_window_system_ui_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--window-system-ui-api'
	is_seed_account_options_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--seed-account-options-api'
	is_persistent_data_block_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--persistent-data-block-api'
	is_bitmap_tiles_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--bitmap-tiles-api'
	is_connectivity_truth_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--connectivity-truth-api'
	is_window_animations_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--window-animations-api'
	is_layout_alignment_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--layout-alignment-api'
	is_user_restrictions_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--user-restrictions-api'
	is_bundle_cross_profile_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--bundle-cross-profile-api'
	is_user_restrictions_bundle_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--user-restrictions-bundle-api'
	is_resources_float_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--resources-float-api'
	is_paint_drawable_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--paint-drawable-api'
	is_dialog_theme_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--dialog-theme-api'
	is_intent_extras_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--intent-extras-api'
	is_resource_locks_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--resource-locks-api'
	is_pending_intent_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--pending-intent-api'
	is_stable_display_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--stable-display-api'
	is_asset_locales_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--asset-locales-api'
	is_unmanaged_queries_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--unmanaged-queries-api'
	is_stats_unavailable_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--stats-unavailable-api'
	is_subscription_service_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--subscription-service-api'
	is_autofill_service_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--autofill-service-api'
	is_keyguard_policy_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--keyguard-policy-api'
	is_broadcast_permission_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--broadcast-permission-api'
	is_broadcast_permission_v2_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--broadcast-permission-v2-api'
	is_secure_settings_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--secure-settings-api'
	is_usage_inactive_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--usage-inactive-api'
	is_messenger_binder_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--messenger-binder-api'
	is_messenger_binder_v2_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--messenger-binder-v2-api'
	is_event_log_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--event-log-api'
	is_build_abis_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--build-abis-api'
	is_webview_package_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--webview-package-api'
	is_bootclasspath_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--bootclasspath-api'
	if !is_direct_boot && !is_credential_storage && !is_broadcast_result && !is_onboarding_api && !is_application_restrictions && !is_auth_exception_api && !is_auth_worker_api && !is_binder_identity_api && !is_service_lifecycle_api && !is_platform_fragments_api && !is_image_bounds_api && !is_window_system_ui_api && !is_seed_account_options_api && !is_persistent_data_block_api && !is_bitmap_tiles_api && !is_connectivity_truth_api && !is_window_animations_api && !is_layout_alignment_api && !is_user_restrictions_api && !is_bundle_cross_profile_api && !is_user_restrictions_bundle_api && !is_resources_float_api && !is_paint_drawable_api && !is_dialog_theme_api && !is_intent_extras_api && !is_resource_locks_api && !is_pending_intent_api && !is_stable_display_api && !is_asset_locales_api && !is_unmanaged_queries_api && !is_stats_unavailable_api && !is_subscription_service_api && !is_autofill_service_api && !is_keyguard_policy_api && !is_broadcast_permission_api && !is_broadcast_permission_v2_api && !is_secure_settings_api && !is_usage_inactive_api && !is_messenger_binder_api && !is_messenger_binder_v2_api && !is_event_log_api && !is_build_abis_api && !is_webview_package_api && !is_bootclasspath_api && (os.args.len != 4 || os.args[1] != 'serve') {
		eprintln('usage: service-query-transfer serve [--direct-boot|--credential-storage|--broadcast-result|--onboarding-apis|--application-restrictions|--auth-exception-apis|--auth-worker-apis|--binder-identity-apis|--service-lifecycle-api|--platform-fragments-api|--image-bounds-api|--window-system-ui-api|--seed-account-options-api|--persistent-data-block-api|--bitmap-tiles-api|--connectivity-truth-api|--window-animations-api|--layout-alignment-api|--user-restrictions-api|--bundle-cross-profile-api|--user-restrictions-bundle-api|--resources-float-api|--paint-drawable-api|--dialog-theme-api|--intent-extras-api|--resource-locks-api|--pending-intent-api|--stable-display-api|--asset-locales-api|--unmanaged-queries-api|--stats-unavailable-api|--subscription-service-api|--autofill-service-api|--keyguard-policy-api|--broadcast-permission-api|--broadcast-permission-v2-api|--secure-settings-api|--usage-inactive-api|--messenger-binder-api|--messenger-binder-v2-api|--event-log-api|--build-abis-api|--webview-package-api|--bootclasspath-api] FRESH_EXTERNAL_DIR PORT | --self-test FRESH_EXTERNAL_DIR')
		exit(2)
	}
	offset := if is_direct_boot || is_credential_storage || is_broadcast_result || is_onboarding_api || is_application_restrictions || is_auth_exception_api || is_auth_worker_api || is_binder_identity_api || is_service_lifecycle_api || is_platform_fragments_api || is_image_bounds_api || is_window_system_ui_api || is_seed_account_options_api || is_persistent_data_block_api || is_bitmap_tiles_api || is_connectivity_truth_api || is_window_animations_api || is_layout_alignment_api || is_user_restrictions_api || is_bundle_cross_profile_api || is_user_restrictions_bundle_api || is_resources_float_api || is_paint_drawable_api || is_dialog_theme_api || is_intent_extras_api || is_resource_locks_api || is_pending_intent_api || is_stable_display_api || is_asset_locales_api || is_unmanaged_queries_api || is_stats_unavailable_api || is_subscription_service_api || is_autofill_service_api || is_keyguard_policy_api || is_broadcast_permission_api || is_broadcast_permission_v2_api || is_secure_settings_api || is_usage_inactive_api || is_messenger_binder_api || is_messenger_binder_v2_api || is_event_log_api || is_build_abis_api || is_webview_package_api || is_bootclasspath_api { 1 } else { 0 }
	serve(os.args[2 + offset], os.args[3 + offset], is_direct_boot, is_credential_storage, is_broadcast_result, is_onboarding_api, is_application_restrictions, is_auth_exception_api, is_auth_worker_api, is_binder_identity_api, is_service_lifecycle_api, is_platform_fragments_api, is_image_bounds_api, is_window_system_ui_api, is_seed_account_options_api, is_persistent_data_block_api, is_bitmap_tiles_api, is_connectivity_truth_api, is_window_animations_api, is_layout_alignment_api, is_user_restrictions_api, is_bundle_cross_profile_api, is_user_restrictions_bundle_api, is_resources_float_api, is_paint_drawable_api, is_dialog_theme_api, is_intent_extras_api, is_resource_locks_api, is_pending_intent_api, is_stable_display_api, is_asset_locales_api, is_unmanaged_queries_api, is_stats_unavailable_api, is_subscription_service_api, is_autofill_service_api, is_keyguard_policy_api, is_broadcast_permission_api, is_broadcast_permission_v2_api, is_secure_settings_api, is_usage_inactive_api, is_messenger_binder_api, is_messenger_binder_v2_api, is_event_log_api, is_build_abis_api, is_webview_package_api, is_bootclasspath_api) or { eprintln(err); exit(1) }
}

fn get(address string, request string) !string {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_read_deadline(time.now().add(2 * time.second))
	connection.set_write_deadline(time.now().add(2 * time.second))
	connection.write_string(request)!
	mut result := []u8{}
	mut buffer := []u8{len: 65536}
	for {
		n := connection.read(mut buffer) or { break }
		if n == 0 { break }
		if result.len + n > 256 * 1024 { return error('test response exceeds bound') }
		result << buffer[..n]
	}
	return result.bytestr()
}

fn bootclasspath_jni_self_test(root string) ! {
	for bad in [['serve', '--bootclasspath-jni-api'],
		['serve', '--bootclasspath-jni-api', root + '/must-not-exist'],
		['serve', '--bootclasspath-jni-api-other', root + '/must-not-exist', '0'],
		['serve', '--bootclasspath-jni-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--bootclasspath-jni-api', '--bootclasspath-api', root + '/must-not-exist', '0'],
		['serve', '--bootclasspath-api', '--bootclasspath-jni-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed bootclasspath JNI transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--bootclasspath-jni-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical bootclasspath JNI port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	current := bootclasspath_jni_api_assets()
	prior := bootclasspath_api_assets()
	assert current.len == 2
	assert current.map(it.url) == ['/bootclasspath-jni-api-run', '/bootclasspath-jni.apk']
	assert current[0].path != current[1].path && current[0].sha256 != current[1].sha256
	assert current[1].path == prior[1].path && current[1].sha256 == prior[1].sha256
	for asset in current {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets(), bootclasspath_api_assets()] {
			for old in older { bootclasspath_jni_distinct(asset, old)! }
		}
	}
	for pair in [[Asset{...current[1], path: '/wrong'}, prior[1]],
		[Asset{...current[1], sha256: '0'.repeat(64)}, prior[1]],
		[current[1], Asset{...prior[1], path: '/wrong'}],
		[current[1], Asset{...prior[1], sha256: '0'.repeat(64)}],
		[Asset{...current[1], url: '/wrong.apk'}, prior[1]],
		[Asset{...current[1], url: prior[1].url}, prior[1]],
		[Asset{...current[0], path: prior[0].path}, prior[0]],
		[Asset{...current[0], sha256: prior[0].sha256}, prior[0]]] {
		if _ := bootclasspath_jni_distinct(pair[0], pair[1]) { return error('broadened bootclasspath shared-APK exception accepted') }
	}
	println('BOOTCLASSPATH-JNI-HTTP SELF-TEST PASS exact-selector routes pins shared-apk-only collision-controls8')
}

fn traffic_stats_uid_self_test(root string) ! {
	for bad in [['serve', '--traffic-stats-uid-api'],
		['serve', '--traffic-stats-uid-api', root + '/must-not-exist'],
		['serve', '--traffic-stats-uid-api-other', root + '/must-not-exist', '0'],
		['serve', '--traffic-stats-uid-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--traffic-stats-uid-api', '--bootclasspath-jni-api', root + '/must-not-exist', '0'],
		['serve', '--bootclasspath-jni-api', '--traffic-stats-uid-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed TrafficStats UID transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--traffic-stats-uid-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical TrafficStats UID port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	current := traffic_stats_uid_api_assets()
	assert current.len == 2
	assert current.map(it.url) == ['/traffic-stats-uid-api-run', '/traffic-stats-uid.apk']
	traffic_stats_uid_distinct(current[0], current[1])!
	for asset in current {
		assert valid_digest(asset.sha256)
		assert os.is_abs_path(asset.path) && os.abs_path(asset.path) == asset.path
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets(), bootclasspath_api_assets(), bootclasspath_jni_api_assets()] {
			for old in older { traffic_stats_uid_distinct(asset, old)! }
		}
		old := bootclasspath_jni_api_assets()[0]
		for changed in [Asset{...asset, url: old.url}, Asset{...asset, path: old.path}, Asset{...asset, sha256: old.sha256}] {
			if _ := traffic_stats_uid_distinct(changed, old) { return error('TrafficStats UID collision accepted') }
		}
	}
	println('TRAFFIC-STATS-UID-HTTP SELF-TEST PASS exact-selector routes pins distinct-artifacts collision-controls6')
}

fn process_packages_self_test(root string) ! {
	for bad in [['serve', '--process-packages-api'],
		['serve', '--process-packages-api', root + '/must-not-exist'],
		['serve', '--process-packages-api-other', root + '/must-not-exist', '0'],
		['serve', '--process-packages-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--process-packages-api', '--traffic-stats-uid-api', root + '/must-not-exist', '0'],
		['serve', '--traffic-stats-uid-api', '--process-packages-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed process packages transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--process-packages-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical process packages port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	current := process_packages_api_assets()
	assert current.len == 2
	assert current.map(it.url) == ['/process-packages-api-run', '/process-packages.apk']
	process_packages_distinct(current[0], current[1])!
	for asset in current {
		assert valid_digest(asset.sha256)
		assert os.is_abs_path(asset.path) && os.abs_path(asset.path) == asset.path
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets(), bootclasspath_api_assets(), bootclasspath_jni_api_assets(), traffic_stats_uid_api_assets()] {
			for old in older { process_packages_distinct(asset, old)! }
		}
		old := traffic_stats_uid_api_assets()[0]
		for changed in [Asset{...asset, url: old.url}, Asset{...asset, path: old.path}, Asset{...asset, sha256: old.sha256}] {
			if _ := process_packages_distinct(changed, old) { return error('process packages collision accepted') }
		}
	}
	println('PROCESS-PACKAGES-HTTP SELF-TEST PASS exact-selector routes pins distinct-artifacts collision-controls6')
}

fn global_settings_string_self_test(root string) ! {
	for bad in [['serve', '--global-settings-string-api'],
		['serve', '--global-settings-string-api', root + '/must-not-exist'],
		['serve', '--global-settings-string-api-other', root + '/must-not-exist', '0'],
		['serve', '--global-settings-string-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--global-settings-string-api', '--process-packages-api', root + '/must-not-exist', '0'],
		['serve', '--process-packages-api', '--global-settings-string-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Global settings String transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--global-settings-string-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'),
			'noncanonical Global settings String port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	current := global_settings_string_api_assets()
	assert current.len == 2
	assert current.map(it.url) == ['/global-settings-string-api-run', '/global-settings-string.apk']
	global_settings_string_distinct(current[0], current[1])!
	for asset in current {
		assert valid_digest(asset.sha256)
		assert os.is_abs_path(asset.path) && os.abs_path(asset.path) == asset.path
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets(), bootclasspath_api_assets(), bootclasspath_jni_api_assets(), traffic_stats_uid_api_assets(), process_packages_api_assets()] {
			for old in older { global_settings_string_distinct(asset, old)! }
		}
		old := process_packages_api_assets()[0]
		for changed in [Asset{...asset, url: old.url}, Asset{...asset, path: old.path}, Asset{...asset, sha256: old.sha256}] {
			if _ := global_settings_string_distinct(changed, old) { return error('Global settings String collision accepted') }
		}
	}
	println('GLOBAL-SETTINGS-STRING-HTTP SELF-TEST PASS exact-selector routes pins distinct-artifacts collision-controls6')
}

fn default_network_active_self_test(root string) ! {
	for bad in [['serve', '--default-network-active-api'],
		['serve', '--default-network-active-api', root + '/must-not-exist'],
		['serve', '--default-network-active-api-other', root + '/must-not-exist', '0'],
		['serve', '--default-network-active-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--default-network-active-api', '--global-settings-string-api', root + '/must-not-exist', '0'],
		['serve', '--global-settings-string-api', '--default-network-active-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed default network activity transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--default-network-active-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'),
			'noncanonical default network activity port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	current := default_network_active_api_assets()
	assert current.len == 2
	assert current.map(it.url) == ['/default-network-active-api-run', '/default-network-active.apk']
	default_network_active_distinct(current[0], current[1])!
	for asset in current {
		assert valid_digest(asset.sha256)
		assert os.is_abs_path(asset.path) && os.abs_path(asset.path) == asset.path
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets(), bootclasspath_api_assets(), bootclasspath_jni_api_assets(), traffic_stats_uid_api_assets(), process_packages_api_assets(), global_settings_string_api_assets()] {
			for old in older { default_network_active_distinct(asset, old)! }
		}
		for old in user_restrictions_bundle_api_assets() { default_network_active_distinct(asset, old)! }
		old := global_settings_string_api_assets()[0]
		for changed in [Asset{...asset, url: old.url}, Asset{...asset, path: old.path}, Asset{...asset, sha256: old.sha256}] {
			if _ := default_network_active_distinct(changed, old) { return error('default network activity collision accepted') }
		}
	}
	println('DEFAULT-NETWORK-ACTIVE-HTTP SELF-TEST PASS exact-selector routes pins distinct-artifacts collision-controls6')
}

fn self_test(root string) ! {
	$if !net_nonblocking_sockets ? { return error('self-test requires nonblocking sockets') }
	external(root)!
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh self-test output required') }
	bootclasspath_jni_self_test(root)!
	traffic_stats_uid_self_test(root)!
	process_packages_self_test(root)!
	global_settings_string_self_test(root)!
	default_network_active_self_test(root)!
	for bad in [['serve', '--binder-identity-apis'],
		['serve', '--binder-identity-apis', root + '/must-not-exist'],
		['serve', '--binder-identity-apis-other', root + '/must-not-exist', '0'],
		['serve', '--binder-identity-apis', root + '/must-not-exist', '0', 'extra']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Binder identity transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--binder-identity-apis', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--service-lifecycle-api'],
		['serve', '--service-lifecycle-api', root + '/must-not-exist'],
		['serve', '--service-lifecycle-api-other', root + '/must-not-exist', '0'],
		['serve', '--service-lifecycle-api', root + '/must-not-exist', '0', 'extra']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Service lifecycle transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--service-lifecycle-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--platform-fragments-api'],
		['serve', '--platform-fragments-api', root + '/must-not-exist'],
		['serve', '--platform-fragments-api-other', root + '/must-not-exist', '0'],
		['serve', '--platform-fragments-api', root + '/must-not-exist', '0', 'extra']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed platform fragments transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--platform-fragments-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--image-bounds-api'],
		['serve', '--image-bounds-api', root + '/must-not-exist'],
		['serve', '--image-bounds-api-other', root + '/must-not-exist', '0'],
		['serve', '--image-bounds-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--image-bounds-api', '--platform-fragments-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed ImageView bounds transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--image-bounds-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--window-system-ui-api'],
		['serve', '--window-system-ui-api', root + '/must-not-exist'],
		['serve', '--window-system-ui-api-other', root + '/must-not-exist', '0'],
		['serve', '--window-system-ui-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--window-system-ui-api', '--image-bounds-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed window system UI transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--window-system-ui-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--seed-account-options-api'],
		['serve', '--seed-account-options-api', root + '/must-not-exist'],
		['serve', '--seed-account-options-api-other', root + '/must-not-exist', '0'],
		['serve', '--seed-account-options-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--seed-account-options-api', '--window-system-ui-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed seed account options transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--seed-account-options-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--persistent-data-block-api'],
		['serve', '--persistent-data-block-api', root + '/must-not-exist'],
		['serve', '--persistent-data-block-api-other', root + '/must-not-exist', '0'],
		['serve', '--persistent-data-block-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--persistent-data-block-api', '--seed-account-options-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed persistent data block transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--persistent-data-block-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--connectivity-truth-api'],
		['serve', '--connectivity-truth-api', root + '/must-not-exist'],
		['serve', '--connectivity-truth-api-other', root + '/must-not-exist', '0'],
		['serve', '--connectivity-truth-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--connectivity-truth-api', '--bitmap-tiles-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed connectivity truth transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--connectivity-truth-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--window-animations-api'],
		['serve', '--window-animations-api', root + '/must-not-exist'],
		['serve', '--window-animations-api-other', root + '/must-not-exist', '0'],
		['serve', '--window-animations-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--window-animations-api', '--connectivity-truth-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed window animations transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--window-animations-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--layout-alignment-api'],
		['serve', '--layout-alignment-api', root + '/must-not-exist'],
		['serve', '--layout-alignment-api-other', root + '/must-not-exist', '0'],
		['serve', '--layout-alignment-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--layout-alignment-api', '--window-animations-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Layout alignment transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--layout-alignment-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--user-restrictions-api'],
		['serve', '--user-restrictions-api', root + '/must-not-exist'],
		['serve', '--user-restrictions-api-other', root + '/must-not-exist', '0'],
		['serve', '--user-restrictions-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--user-restrictions-api', '--layout-alignment-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed user restrictions transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--user-restrictions-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for selector in ['--bundle-cross-profile-api', '--user-restrictions-bundle-api'] {
		for bad in [['serve', selector], ['serve', selector, root + '/must-not-exist'],
			['serve', selector + '-other', root + '/must-not-exist', '0'],
			['serve', selector, root + '/must-not-exist', '0', 'extra'],
			['serve', selector, '--user-restrictions-api', root + '/must-not-exist', '0']] {
			mut argv := [os.executable()]
			argv << bad
			result := os.exec(argv)
			assert result.exit_code != 0, 'malformed corrected-bundle transfer CLI accepted'
			assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
		}
		for port in ['', '00', '-1', '65536', '0x10'] {
			result := os.exec([os.executable(), 'serve', selector, root + '/must-not-exist', port])
			assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
			assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
		}
	}
	for bad in [['serve', '--resources-float-api'],
		['serve', '--resources-float-api', root + '/must-not-exist'],
		['serve', '--resources-float-api-other', root + '/must-not-exist', '0'],
		['serve', '--resources-float-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--resources-float-api', '--bundle-cross-profile-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed resource float transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--resources-float-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--paint-drawable-api'],
		['serve', '--paint-drawable-api', root + '/must-not-exist'],
		['serve', '--paint-drawable-api-other', root + '/must-not-exist', '0'],
		['serve', '--paint-drawable-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--paint-drawable-api', '--resources-float-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed PaintDrawable transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--paint-drawable-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--dialog-theme-api'],
		['serve', '--dialog-theme-api', root + '/must-not-exist'],
		['serve', '--dialog-theme-api-other', root + '/must-not-exist', '0'],
		['serve', '--dialog-theme-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--dialog-theme-api', '--paint-drawable-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Dialog theme transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--dialog-theme-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--intent-extras-api'],
		['serve', '--intent-extras-api', root + '/must-not-exist'],
		['serve', '--intent-extras-api-other', root + '/must-not-exist', '0'],
		['serve', '--intent-extras-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--intent-extras-api', '--dialog-theme-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Intent extras transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--intent-extras-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	for bad in [['serve', '--resource-locks-api'],
		['serve', '--resource-locks-api', root + '/must-not-exist'],
		['serve', '--resource-locks-api-other', root + '/must-not-exist', '0'],
		['serve', '--resource-locks-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--resource-locks-api', '--intent-extras-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed resource locks transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--resource-locks-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	assert pinned_assets().len == 3 && direct_boot_assets().len == 3 && credential_storage_assets().len == 3
	for bad in [['serve', '--pending-intent-api'],
		['serve', '--pending-intent-api', root + '/must-not-exist'],
		['serve', '--pending-intent-api-other', root + '/must-not-exist', '0'],
		['serve', '--pending-intent-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--pending-intent-api', '--resource-locks-api', root + '/must-not-exist', '0'],
		['serve', '--resource-locks-api', '--pending-intent-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed PendingIntent transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--pending-intent-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical PendingIntent port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--stable-display-api'],
		['serve', '--stable-display-api', root + '/must-not-exist'],
		['serve', '--stable-display-api-other', root + '/must-not-exist', '0'],
		['serve', '--stable-display-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--stable-display-api', '--pending-intent-api', root + '/must-not-exist', '0'],
		['serve', '--pending-intent-api', '--stable-display-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed stable display transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--stable-display-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical stable display port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--asset-locales-api'],
		['serve', '--asset-locales-api', root + '/must-not-exist'],
		['serve', '--asset-locales-api-other', root + '/must-not-exist', '0'],
		['serve', '--asset-locales-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--asset-locales-api', '--stable-display-api', root + '/must-not-exist', '0'],
		['serve', '--stable-display-api', '--asset-locales-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed asset locales transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--asset-locales-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical asset locales port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--unmanaged-queries-api'],
		['serve', '--unmanaged-queries-api', root + '/must-not-exist'],
		['serve', '--unmanaged-queries-api-other', root + '/must-not-exist', '0'],
		['serve', '--unmanaged-queries-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--unmanaged-queries-api', '--asset-locales-api', root + '/must-not-exist', '0'],
		['serve', '--asset-locales-api', '--unmanaged-queries-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed unmanaged queries transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--unmanaged-queries-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical unmanaged queries port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--stats-unavailable-api'],
		['serve', '--stats-unavailable-api', root + '/must-not-exist'],
		['serve', '--stats-unavailable-api-other', root + '/must-not-exist', '0'],
		['serve', '--stats-unavailable-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--stats-unavailable-api', '--unmanaged-queries-api', root + '/must-not-exist', '0'],
		['serve', '--unmanaged-queries-api', '--stats-unavailable-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed stats unavailable transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--stats-unavailable-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical stats unavailable port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--subscription-service-api'],
		['serve', '--subscription-service-api', root + '/must-not-exist'],
		['serve', '--subscription-service-api-other', root + '/must-not-exist', '0'],
		['serve', '--subscription-service-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--subscription-service-api', '--stats-unavailable-api', root + '/must-not-exist', '0'],
		['serve', '--stats-unavailable-api', '--subscription-service-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed subscription service transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--subscription-service-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical subscription service port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--autofill-service-api'],
		['serve', '--autofill-service-api', root + '/must-not-exist'],
		['serve', '--autofill-service-api-other', root + '/must-not-exist', '0'],
		['serve', '--autofill-service-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--autofill-service-api', '--subscription-service-api', root + '/must-not-exist', '0'],
		['serve', '--subscription-service-api', '--autofill-service-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed autofill service transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--autofill-service-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical autofill service port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--keyguard-policy-api'],
		['serve', '--keyguard-policy-api', root + '/must-not-exist'],
		['serve', '--keyguard-policy-api-other', root + '/must-not-exist', '0'],
		['serve', '--keyguard-policy-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--keyguard-policy-api', '--autofill-service-api', root + '/must-not-exist', '0'],
		['serve', '--autofill-service-api', '--keyguard-policy-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed keyguard policy transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--keyguard-policy-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical keyguard policy port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--broadcast-permission-api'],
		['serve', '--broadcast-permission-api', root + '/must-not-exist'],
		['serve', '--broadcast-permission-api-other', root + '/must-not-exist', '0'],
		['serve', '--broadcast-permission-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--broadcast-permission-api', '--keyguard-policy-api', root + '/must-not-exist', '0'],
		['serve', '--keyguard-policy-api', '--broadcast-permission-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed broadcast permission transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--broadcast-permission-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical broadcast permission port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--broadcast-permission-v2-api'],
		['serve', '--broadcast-permission-v2-api', root + '/must-not-exist'],
		['serve', '--broadcast-permission-v2-api-other', root + '/must-not-exist', '0'],
		['serve', '--broadcast-permission-v2-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--broadcast-permission-v2-api', '--broadcast-permission-api', root + '/must-not-exist', '0'],
		['serve', '--broadcast-permission-api', '--broadcast-permission-v2-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed broadcast permission v2 transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--broadcast-permission-v2-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical broadcast permission v2 port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--secure-settings-api'],
		['serve', '--secure-settings-api', root + '/must-not-exist'],
		['serve', '--secure-settings-api-other', root + '/must-not-exist', '0'],
		['serve', '--secure-settings-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--secure-settings-api', '--broadcast-permission-v2-api', root + '/must-not-exist', '0'],
		['serve', '--broadcast-permission-v2-api', '--secure-settings-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed secure settings transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--secure-settings-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical secure settings port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--bootclasspath-api'],
		['serve', '--bootclasspath-api', root + '/must-not-exist'],
		['serve', '--bootclasspath-api-other', root + '/must-not-exist', '0'],
		['serve', '--bootclasspath-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--bootclasspath-api', '--webview-package-api', root + '/must-not-exist', '0'],
		['serve', '--webview-package-api', '--bootclasspath-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed bootclasspath transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--bootclasspath-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical bootclasspath port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--webview-package-api'],
		['serve', '--webview-package-api', root + '/must-not-exist'],
		['serve', '--webview-package-api-other', root + '/must-not-exist', '0'],
		['serve', '--webview-package-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--webview-package-api', '--build-abis-api', root + '/must-not-exist', '0'],
		['serve', '--build-abis-api', '--webview-package-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed WebView package transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--webview-package-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical WebView package port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--build-abis-api'],
		['serve', '--build-abis-api', root + '/must-not-exist'],
		['serve', '--build-abis-api-other', root + '/must-not-exist', '0'],
		['serve', '--build-abis-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--build-abis-api', '--event-log-api', root + '/must-not-exist', '0'],
		['serve', '--event-log-api', '--build-abis-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed build abis transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--build-abis-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical build abis port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--event-log-api'],
		['serve', '--event-log-api', root + '/must-not-exist'],
		['serve', '--event-log-api-other', root + '/must-not-exist', '0'],
		['serve', '--event-log-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--event-log-api', '--messenger-binder-v2-api', root + '/must-not-exist', '0'],
		['serve', '--messenger-binder-v2-api', '--event-log-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed event log transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--event-log-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical event log port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--messenger-binder-v2-api'],
		['serve', '--messenger-binder-v2-api', root + '/must-not-exist'],
		['serve', '--messenger-binder-v2-api-other', root + '/must-not-exist', '0'],
		['serve', '--messenger-binder-v2-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--messenger-binder-v2-api', '--messenger-binder-api', root + '/must-not-exist', '0'],
		['serve', '--messenger-binder-api', '--messenger-binder-v2-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed messenger binder v2 transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--messenger-binder-v2-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical messenger binder v2 port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--messenger-binder-api'],
		['serve', '--messenger-binder-api', root + '/must-not-exist'],
		['serve', '--messenger-binder-api-other', root + '/must-not-exist', '0'],
		['serve', '--messenger-binder-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--messenger-binder-api', '--usage-inactive-api', root + '/must-not-exist', '0'],
		['serve', '--usage-inactive-api', '--messenger-binder-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed messenger binder transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--messenger-binder-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical messenger binder port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--usage-inactive-api'],
		['serve', '--usage-inactive-api', root + '/must-not-exist'],
		['serve', '--usage-inactive-api-other', root + '/must-not-exist', '0'],
		['serve', '--usage-inactive-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--usage-inactive-api', '--secure-settings-api', root + '/must-not-exist', '0'],
		['serve', '--secure-settings-api', '--usage-inactive-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed usage inactivity transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for port in ['', '-1', '65536', '00', '01', '+1', '1x', ' 1'] {
		result := os.exec([os.executable(), 'serve', '--usage-inactive-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required'), 'noncanonical usage inactivity port accepted'
		assert !os.exists(root + '/must-not-exist')
	}
	for bad in [['serve', '--bitmap-tiles-api'],
		['serve', '--bitmap-tiles-api', root + '/must-not-exist'],
		['serve', '--bitmap-tiles-api-other', root + '/must-not-exist', '0'],
		['serve', '--bitmap-tiles-api', root + '/must-not-exist', '0', 'extra'],
		['serve', '--bitmap-tiles-api', '--persistent-data-block-api', root + '/must-not-exist', '0']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed bitmap tiles transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--bitmap-tiles-api', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	assert broadcast_result_assets().len == 3
	assert pinned_assets()[0].url == '/service-query-run' && direct_boot_assets()[0].url == '/direct-boot-run'
	assert credential_storage_assets()[0].url == '/credential-storage-run'
	assert broadcast_result_assets()[0].url == '/broadcast-result-run'
	assert onboarding_api_assets().len == 3
	assert onboarding_api_assets().map(it.url) == ['/onboarding-api-run', '/child-attach.apk', '/settings-global.apk']
	assert application_restrictions_assets().len == 2
	assert application_restrictions_assets().map(it.url) == ['/application-restrictions-run', '/application-restrictions.apk']
	assert auth_exception_api_assets().len == 3
	assert auth_exception_api_assets().map(it.url) == ['/auth-exception-api-run', '/authenticator-exception.apk', '/maps-network.apk']
	assert auth_worker_api_assets().len == 3
	assert auth_worker_api_assets().map(it.url) == ['/auth-worker-api-run', '/authenticator-exception.apk', '/maps-network-v2.apk']
	assert binder_identity_api_assets().len == 3
	assert binder_identity_api_assets().map(it.url) == ['/binder-identity-api-run', '/authenticator-exception.apk', '/maps-network-v3.apk']
	assert service_lifecycle_api_assets().len == 2
	assert service_lifecycle_api_assets().map(it.url) == ['/service-lifecycle-api-run', '/service-lifecycle.apk']
	assert platform_fragments_api_assets().len == 2
	assert platform_fragments_api_assets().map(it.url) == ['/platform-fragments-api-run', '/platform-fragments.apk']
	assert image_bounds_api_assets().len == 2
	assert image_bounds_api_assets().map(it.url) == ['/image-bounds-api-run', '/image-bounds.apk']
	assert window_system_ui_api_assets().len == 2
	assert window_system_ui_api_assets().map(it.url) == ['/window-system-ui-api-run', '/window-system-ui.apk']
	assert seed_account_options_api_assets().len == 2
	assert seed_account_options_api_assets().map(it.url) == ['/seed-account-options-api-run', '/seed-account-options.apk']
	assert persistent_data_block_api_assets().len == 2
	assert persistent_data_block_api_assets().map(it.url) == ['/persistent-data-block-api-run', '/persistent-data-block.apk']
	assert bitmap_tiles_api_assets().len == 2
	assert bitmap_tiles_api_assets().map(it.url) == ['/bitmap-tiles-api-run', '/bitmap-tiles.apk']
	assert connectivity_truth_api_assets().len == 2
	assert connectivity_truth_api_assets().map(it.url) == ['/connectivity-truth-api-run', '/connectivity-truth.apk']
	assert window_animations_api_assets().len == 2
	assert window_animations_api_assets().map(it.url) == ['/window-animations-api-run', '/window-animations.apk']
	assert layout_alignment_api_assets().len == 2
	assert layout_alignment_api_assets().map(it.url) == ['/layout-alignment-api-run', '/layout-alignment.apk']
	assert user_restrictions_api_assets().len == 2
	assert user_restrictions_api_assets().map(it.url) == ['/user-restrictions-api-run', '/user-restrictions.apk']
	assert resources_float_api_assets().len == 2
	assert resources_float_api_assets().map(it.url) == ['/resources-float-api-run', '/resources-float.apk']
	assert paint_drawable_api_assets().len == 2
	assert paint_drawable_api_assets().map(it.url) == ['/paint-drawable-api-run', '/paint-drawable.apk']
	assert dialog_theme_api_assets().len == 2
	assert dialog_theme_api_assets().map(it.url) == ['/dialog-theme-api-run', '/dialog-theme.apk']
	assert intent_extras_api_assets().len == 2
	assert intent_extras_api_assets().map(it.url) == ['/intent-extras-api-run', '/intent-extras.apk']
	assert resource_locks_api_assets().len == 2
	assert resource_locks_api_assets().map(it.url) == ['/resource-locks-api-run', '/resource-locks.apk']
	assert pending_intent_api_assets().len == 2
	assert pending_intent_api_assets().map(it.url) == ['/pending-intent-api-run', '/pending-intent.apk']
	assert stable_display_api_assets().len == 2
	assert stable_display_api_assets().map(it.url) == ['/stable-display-api-run', '/stable-display.apk']
	assert asset_locales_api_assets().len == 2
	assert asset_locales_api_assets().map(it.url) == ['/asset-locales-api-run', '/asset-locales.apk']
	assert unmanaged_queries_api_assets().len == 2
	assert unmanaged_queries_api_assets().map(it.url) == ['/unmanaged-queries-api-run', '/unmanaged-queries.apk']
	assert stats_unavailable_api_assets().len == 2
	assert stats_unavailable_api_assets().map(it.url) == ['/stats-unavailable-api-run', '/stats-unavailable.apk']
	assert bootclasspath_api_assets().len == 2
	assert bootclasspath_api_assets().map(it.url) == ['/bootclasspath-api-run', '/bootclasspath.apk']
	assert bootclasspath_api_assets()[0].path != bootclasspath_api_assets()[1].path
	assert bootclasspath_api_assets()[0].sha256 != bootclasspath_api_assets()[1].sha256
	for asset in bootclasspath_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets(), webview_package_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert webview_package_api_assets().len == 2
	assert webview_package_api_assets().map(it.url) == ['/webview-package-api-run', '/webview-package.apk']
	assert webview_package_api_assets()[0].path != webview_package_api_assets()[1].path
	assert webview_package_api_assets()[0].sha256 != webview_package_api_assets()[1].sha256
	for asset in webview_package_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets(), build_abis_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert build_abis_api_assets().len == 2
	assert build_abis_api_assets().map(it.url) == ['/build-abis-api-run', '/build-abis.apk']
	assert build_abis_api_assets()[0].path != build_abis_api_assets()[1].path
	assert build_abis_api_assets()[0].sha256 != build_abis_api_assets()[1].sha256
	for asset in build_abis_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets(), event_log_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert event_log_api_assets().len == 2
	assert event_log_api_assets().map(it.url) == ['/event-log-api-run', '/event-log.apk']
	assert event_log_api_assets()[0].path != event_log_api_assets()[1].path
	assert event_log_api_assets()[0].sha256 != event_log_api_assets()[1].sha256
	for asset in event_log_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets(), messenger_binder_v2_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert messenger_binder_v2_api_assets().len == 2
	assert messenger_binder_v2_api_assets().map(it.url) == ['/messenger-binder-v2-api-run', '/messenger-binder-v2.apk']
	assert messenger_binder_v2_api_assets()[0].path != messenger_binder_v2_api_assets()[1].path
	assert messenger_binder_v2_api_assets()[0].sha256 != messenger_binder_v2_api_assets()[1].sha256
	assert messenger_binder_v2_api_assets()[1].path == messenger_binder_api_assets()[1].path
		&& messenger_binder_v2_api_assets()[1].sha256 == messenger_binder_api_assets()[1].sha256,
		'the exact signed Messenger fixture is deliberately reused only across V1 and V2'
	for asset in messenger_binder_v2_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets(), messenger_binder_api_assets()] {
			for old in older {
				assert asset.url != old.url
				if asset.url == '/messenger-binder-v2.apk' && old.url == '/messenger-binder.apk' {
					// This exact pair is the sole approved path/hash sharing exception.
					assert asset.path == messenger_binder_apk && old.path == messenger_binder_apk
						&& asset.sha256 == messenger_binder_apk_pin && old.sha256 == messenger_binder_apk_pin
				} else {
					assert asset.path != old.path && asset.sha256 != old.sha256
				}
			}
		}
	}
	assert messenger_binder_api_assets().len == 2
	assert messenger_binder_api_assets().map(it.url) == ['/messenger-binder-api-run', '/messenger-binder.apk']
	assert messenger_binder_api_assets()[0].path != messenger_binder_api_assets()[1].path
	assert messenger_binder_api_assets()[0].sha256 != messenger_binder_api_assets()[1].sha256
	for asset in messenger_binder_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets(), usage_inactive_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert usage_inactive_api_assets().len == 2
	assert usage_inactive_api_assets().map(it.url) == ['/usage-inactive-api-run', '/usage-inactive.apk']
	assert usage_inactive_api_assets()[0].path != usage_inactive_api_assets()[1].path
	assert usage_inactive_api_assets()[0].sha256 != usage_inactive_api_assets()[1].sha256
	for asset in usage_inactive_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets(), secure_settings_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert secure_settings_api_assets().len == 2
	assert secure_settings_api_assets().map(it.url) == ['/secure-settings-api-run', '/secure-settings.apk']
	assert secure_settings_api_assets()[0].path != secure_settings_api_assets()[1].path
	assert secure_settings_api_assets()[0].sha256 != secure_settings_api_assets()[1].sha256
	for asset in secure_settings_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets(), broadcast_permission_v2_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert broadcast_permission_v2_api_assets().len == 2
	assert broadcast_permission_v2_api_assets().map(it.url) == ['/broadcast-permission-v2-api-run', '/broadcast-permission-v2.apk']
	assert broadcast_permission_v2_api_assets()[0].path != broadcast_permission_v2_api_assets()[1].path
	assert broadcast_permission_v2_api_assets()[0].sha256 != broadcast_permission_v2_api_assets()[1].sha256
	for asset in broadcast_permission_v2_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets(), broadcast_permission_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert broadcast_permission_api_assets().len == 2
	assert broadcast_permission_api_assets().map(it.url) == ['/broadcast-permission-api-run', '/broadcast-permission.apk']
	assert broadcast_permission_api_assets()[0].path != broadcast_permission_api_assets()[1].path
	assert broadcast_permission_api_assets()[0].sha256 != broadcast_permission_api_assets()[1].sha256
	for asset in broadcast_permission_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets(), keyguard_policy_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert keyguard_policy_api_assets().len == 2
	assert keyguard_policy_api_assets().map(it.url) == ['/keyguard-policy-api-run', '/keyguard-policy.apk']
	assert keyguard_policy_api_assets()[0].path != keyguard_policy_api_assets()[1].path
	assert keyguard_policy_api_assets()[0].sha256 != keyguard_policy_api_assets()[1].sha256
	for asset in keyguard_policy_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets(), autofill_service_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert autofill_service_api_assets().len == 2
	assert autofill_service_api_assets().map(it.url) == ['/autofill-service-api-run', '/autofill-service.apk']
	assert autofill_service_api_assets()[0].path != autofill_service_api_assets()[1].path
	assert autofill_service_api_assets()[0].sha256 != autofill_service_api_assets()[1].sha256
	for asset in autofill_service_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets(), subscription_service_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert subscription_service_api_assets().len == 2
	assert subscription_service_api_assets().map(it.url) == ['/subscription-service-api-run', '/subscription-service.apk']
	assert subscription_service_api_assets()[0].path != subscription_service_api_assets()[1].path
	assert subscription_service_api_assets()[0].sha256 != subscription_service_api_assets()[1].sha256
	for asset in subscription_service_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets(), stats_unavailable_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert stats_unavailable_api_assets()[0].path != stats_unavailable_api_assets()[1].path
	assert stats_unavailable_api_assets()[0].sha256 != stats_unavailable_api_assets()[1].sha256
	for asset in stats_unavailable_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets(), unmanaged_queries_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert unmanaged_queries_api_assets()[0].path != unmanaged_queries_api_assets()[1].path
	assert unmanaged_queries_api_assets()[0].sha256 != unmanaged_queries_api_assets()[1].sha256
	for asset in unmanaged_queries_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets(), asset_locales_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert asset_locales_api_assets()[0].path != asset_locales_api_assets()[1].path
	assert asset_locales_api_assets()[0].sha256 != asset_locales_api_assets()[1].sha256
	for asset in asset_locales_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets(), stable_display_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert stable_display_api_assets()[0].path != stable_display_api_assets()[1].path
	assert stable_display_api_assets()[0].sha256 != stable_display_api_assets()[1].sha256
	for asset in stable_display_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets(), pending_intent_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert pending_intent_api_assets()[0].path != pending_intent_api_assets()[1].path
	assert pending_intent_api_assets()[0].sha256 != pending_intent_api_assets()[1].sha256
	for asset in pending_intent_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets(), resource_locks_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in resource_locks_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets(), intent_extras_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in intent_extras_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets(), dialog_theme_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in dialog_theme_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets(), paint_drawable_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in paint_drawable_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets(), resources_float_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in resources_float_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets(), bundle_cross_profile_api_assets(), user_restrictions_bundle_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	assert bundle_cross_profile_api_assets().len == 2 && user_restrictions_bundle_api_assets().len == 2
	assert bundle_cross_profile_api_assets().map(it.url) == ['/bundle-cross-profile-api-run', '/bundle-cross-profile.apk']
	assert user_restrictions_bundle_api_assets().map(it.url) == ['/user-restrictions-bundle-api-run', '/user-restrictions.apk']
	combined := bundle_cross_profile_api_assets()
	retry := user_restrictions_bundle_api_assets()
	original := user_restrictions_api_assets()
	assert retry[0].path == combined[0].path && retry[0].sha256 == combined[0].sha256 && retry[0].url != combined[0].url
	assert retry[1].path == original[1].path && retry[1].sha256 == original[1].sha256 && retry[1].url == original[1].url
	for selected in [combined, retry] {
		for asset in selected {
			assert valid_digest(asset.sha256)
			for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets(), user_restrictions_api_assets()] {
				for old in older {
					if asset.url == '/user-restrictions.apk' && old.url == asset.url {
						assert asset.path == old.path && asset.sha256 == old.sha256, 'UserManager retry must transfer the unchanged signed APK'
					} else {
						assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url
					}
				}
			}
		}
	}
	for asset in user_restrictions_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets(), layout_alignment_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in layout_alignment_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets(), window_animations_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in window_animations_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets(), connectivity_truth_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in connectivity_truth_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets(), bitmap_tiles_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in bitmap_tiles_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets(), persistent_data_block_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in persistent_data_block_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets(), seed_account_options_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in seed_account_options_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets(), window_system_ui_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in window_system_ui_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets(), image_bounds_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in image_bounds_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets(), platform_fragments_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in platform_fragments_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets(), service_lifecycle_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for asset in service_lifecycle_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets(), binder_identity_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
		}
	}
	for index, asset in binder_identity_api_assets() {
		assert valid_digest(asset.sha256)
		if index == 1 {
			assert asset == auth_exception_api_assets()[1] && asset == auth_worker_api_assets()[1]
		} else {
			for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets()] {
				for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
			}
		}
	}
	for index, asset in auth_worker_api_assets() {
		assert valid_digest(asset.sha256)
		if index == 1 {
			assert asset == auth_exception_api_assets()[1]
		} else {
			for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets()] {
				for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
			}
		}
	}
	for asset in auth_exception_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for asset in application_restrictions_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for asset in onboarding_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for index, asset in direct_boot_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path
	}
	for index, asset in credential_storage_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.sha256 != direct_boot_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path && asset.path != direct_boot_assets()[index].path
	}
	for index, asset in broadcast_result_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.sha256 != direct_boot_assets()[index].sha256
		assert asset.sha256 != credential_storage_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path && asset.path != direct_boot_assets()[index].path
		assert asset.path != credential_storage_assets()[index].path
	}
	for bad in ['POST /client.apk HTTP/1.1\r\n\r\n', 'HEAD /client.apk HTTP/1.0\r\n\r\n'] {
		_, code := parse_request(bad)!
		assert code == 405
	}
	for bad in ['GET / HTTP/2\r\n\r\n', 'GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n',
		'GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n', 'x'.repeat(8193)] {
		if _, _ := parse_request(bad) { return error('unsafe request accepted') }
	}
	body := 'binary\x00\xff\n'.repeat(20000)
	input := root + '/input'
	os.write_file(input, body)!
	asset := snapshot(Asset{url: '/one', path: input, sha256: sha256.hexhash(body)}, root + '/snapshot')!
	if _ := snapshot(Asset{path: input, sha256: '0'.repeat(64)}, root + '/wrong-pin') { return error('wrong input pin accepted') }
	os.symlink(input, root + '/link')!
	if _, _ := open_bounded(root + '/link') { return error('symlink input accepted') }
	os.write_file(root + '/empty', '')!
	if _, _ := open_bounded(root + '/empty') { return error('empty input accepted') }
	if _ := snapshot(Asset{path: input, sha256: sha256.hexhash(body)}, root + '/snapshot') { return error('existing output accepted') }
	assert os.lstat(root + '/snapshot')!.mode & 0o777 == 0o400
	assets := [asset, Asset{...asset, url: '/two'}, Asset{...asset, url: '/three'}]
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	address := listener.addr()!.str()
	worker := spawn serve_loop(mut listener, assets, 7, time.now().add(5 * time.second))
	for request in ['POST /one HTTP/1.1\r\n\r\n', 'GET /../input HTTP/1.1\r\n\r\n',
		'GET /%2e%2e/input HTTP/1.1\r\n\r\n', 'GET /one?query HTTP/1.1\r\n\r\n'] {
		response := get(address, request)!
		assert !response.starts_with('HTTP/1.1 200')
		assert response.ends_with('\r\n\r\n')
	}
	for name in ['/one', '/two', '/three'] {
		response := get(address, 'GET ' + name + ' HTTP/1.0\r\n\r\n')!
		assert response.starts_with('HTTP/1.1 200 OK\r\n')
		assert response.all_after('\r\n\r\n') == body
	}
	result := worker.wait()
	listener.close()!
	assert result.success && result.events.len == 7 && result.completed.len == 3
	mut paired := net.listen_tcp(.ip, '127.0.0.1:0')!
	paired_address := paired.addr()!.str()
	paired_worker := spawn serve_loop(mut paired, assets[..2], 2, time.now().add(5 * time.second))
	for name in ['/one', '/two'] {
		response := get(paired_address, 'GET ' + name + ' HTTP/1.0\r\n\r\n')!
		assert response.starts_with('HTTP/1.1 200 OK\r\n') && response.all_after('\r\n\r\n') == body
	}
	paired_result := paired_worker.wait()
	paired.close()!
	assert paired_result.success && paired_result.events.len == 2 && paired_result.completed.len == 2
	mut limited := net.listen_tcp(.ip, '127.0.0.1:0')!
	limited_address := limited.addr()!.str()
	limited_worker := spawn serve_loop(mut limited, assets, 1, time.now().add(time.second))
	get(limited_address, 'GET /missing HTTP/1.0\r\n\r\n')!
	limited_result := limited_worker.wait()
	limited.close()!
	assert !limited_result.success && limited_result.reason == 'request limit exhausted'
	mut idle := net.listen_tcp(.ip, '127.0.0.1:0')!
	watch := time.new_stopwatch()
	idle_result := serve_loop(mut idle, assets, 1, time.now().add(50 * time.millisecond))
	idle.close()!
	assert !idle_result.success && watch.elapsed() < time.second
	write_json(root + '/self-test.json', json2.encode(result, prettify: true))!
	println('SERVICE-QUERY-HTTP SELF-TEST PASS pinned snapshots exact binary multi-buffer GET-only traversal request-limit absolute accept deadline')
}
