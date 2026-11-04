// SPDX-License-Identifier: GPL-2.0-or-later
// Account client, broker response/context/interaction and real WebView delta over the sealed
// 2098-class framework. The pinned JAR is the only canonical class input.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const compiler = '/Users/alex/code/v/v'
const store_compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const store_compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const interaction_manifest = 'dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87'
const interaction_jar = '86278c9cbe1f25904b760250f34f859206d719cbb23cf5ff5411a75c480ac36f'
const store_manifest = '7cc408299a3a7d37578735e79b31c5c2ff96dbd1de00a2d7dd0d1e149b156690'
const store_jar = '9e89db595defb905b0322183f176613f2b42f951ec1b51d4ceb91431876c3c8e'
const auth_manifest = '1299ddd064ebe89bae35cafd4c509794894c7466fda0bfaee2dfb85cf404d309'
const auth_jar = 'c677808eb55f58845b4ce3dd5c72be481d4ca585fd4980cec18266271d4740bf'
const cache_manifest = 'f37e13b84b5dfb2c71ad852e2bae5b03fed04e8ee319f44e77fc7605f3b1994a'
const cache_jar = '3a590476c53e3f05533c327c5935e395c55694eacb7895b02940feaf888c56d0'
const descriptions_manifest = 'd898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021'
const descriptions_jar = '71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d'
const protected_storage_manifest = '67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938'
const protected_storage_jar = 'a8ba34eb79be2473f89042c8ee940ab1994dbc902c3d45143877f8891d3b428b'
const service_query_manifest = '12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559'
const service_query_jar = '74892a013cb72fdaef39852325a3fa46db217fbcd3a4f11fcba4cc7272b2a50b'
const direct_boot_manifest = 'a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552'
const direct_boot_jar = 'bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/combined-account-webview-build.v'
const providers = ['framework_accounts.v', 'framework_account_client.v',
 'framework_account_broker_context.v', 'framework_account_native_response.v', 'framework_webview.v',
 'framework_account_interaction.v', 'framework_account_store.v', 'framework_cookie_clear.v',
 'framework_account_token.v']
const changes = ['android/accounts/AccountManager.smali', 'android/atl/VinixAccountFuture.smali',
 'android/os/Binder.smali', 'android/content/Context.smali', 'android/webkit/WebView.smali',
 'android/webkit/WebSettings.smali', 'android/webkit/WebViewClient.smali', 'android/webkit/CookieManager.smali',
 'android/app/PendingIntent.smali', 'android/accounts/AccountAuthenticatorResponse.smali', 'android/os/Bundle.smali']
const additions = ['android/atl/VinixAccountBrokerContext.smali',
 'android/atl/VinixAuthenticatorResponse.smali', 'android/webkit/VinixCookieCallback.smali',
 'android/atl/VinixAccountInteraction.smali']
const accessors = {
 'android/app/PendingIntent.smali': 'public final vinixAccountActivityIntent()Landroid/content/Intent;'
 'android/accounts/AccountAuthenticatorResponse.smali': 'public final vinixMatchesResponse(Landroid/accounts/IAccountAuthenticatorResponse;)Z'
 'android/os/Bundle.smali': 'public final declared-synchronized vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;'
}
const store_methods = ['addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z',
 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z',
 'getAccounts()[Landroid/accounts/Account;', 'getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;',
 'getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;',
 'vinixAddExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z',
 'vinixAccounts(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;',
 'getUserData(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
 'setUserData(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
 'setAccountVisibility(Landroid/accounts/Account;Ljava/lang/String;I)Z',
 'getPassword(Landroid/accounts/Account;)Ljava/lang/String;',
 'setPassword(Landroid/accounts/Account;Ljava/lang/String;)V']
const clear_methods = ['removeAllCookie()V', 'removeAllCookies(Landroid/webkit/ValueCallback;)V',
 'removeSessionCookie()V', 'removeSessionCookies(Landroid/webkit/ValueCallback;)V', 'nativeClear(Z)Z']
const token_methods = ['getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;',
 'vinixStartToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/atl/VinixAccountFuture;)Z']
const cache_methods = ['peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
 'setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
 'invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V',
 'clearPassword(Landroid/accounts/Account;)V']
const description_methods = ['getAuthenticatorTypes()[Landroid/accounts/AuthenticatorDescription;']
const description_classes = ['android/accounts/AuthenticatorDescription.smali',
 'android/accounts/AuthenticatorDescription$Creator.smali']

struct StoreClassParts {
 methods map[string]string
 metadata string
}

struct NarrowProfile {
 name string
 baseline_name string
 manifest_pin string
 jar_pin string
 providers []string
 calls map[string]string
 methods map[string][]string
 changed map[string]int
 added map[string]int
 class_provider string
 class_providers []string
 extra_classes []string
 baseline_classes int = 2102
 directory_provider string
 fields map[string][]string
 removed_methods map[string]int
 removed_fields map[string][]string
}

fn storage_profile() NarrowProfile {
 return NarrowProfile{
  name: 'store'
  baseline_name: 'combined-account-webview-interaction-framework-2026-10-26'
  manifest_pin: interaction_manifest
  jar_pin: interaction_jar
  providers: ['framework_account_store.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_store'}
  methods: {'android/accounts/AccountManager.smali': store_methods}
  changed: {'android/accounts/AccountManager.smali': 4}
  added: {'android/accounts/AccountManager.smali': 8}
 }
}

fn auth_profile() NarrowProfile {
 return NarrowProfile{
  name: 'auth'
  baseline_name: 'combined-account-webview-store-framework-2026-10-26'
  manifest_pin: store_manifest
  jar_pin: store_jar
  providers: ['framework_cookie_clear.v', 'framework_account_token.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_token',
   'android/webkit/CookieManager.smali': 'framework_webview_cookie_clear'}
  methods: {'android/accounts/AccountManager.smali': token_methods,
   'android/webkit/CookieManager.smali': clear_methods}
  changed: {'android/accounts/AccountManager.smali': 0, 'android/webkit/CookieManager.smali': 4}
  added: {'android/accounts/AccountManager.smali': 5, 'android/webkit/CookieManager.smali': 1}
 }
}

fn cache_profile() NarrowProfile {
 return NarrowProfile{
  name: 'cache'
  baseline_name: 'combined-account-webview-auth-framework-2026-10-26'
  manifest_pin: auth_manifest
  jar_pin: auth_jar
  providers: ['framework_account_token_cache.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_token_cache'}
  methods: {'android/accounts/AccountManager.smali': cache_methods}
  changed: {'android/accounts/AccountManager.smali': 0}
  added: {'android/accounts/AccountManager.smali': 4}
 }
}

fn descriptions_profile() NarrowProfile {
 return NarrowProfile{
  name: 'descriptions'
  baseline_name: 'combined-account-webview-cache-framework-2026-10-26-r3'
  manifest_pin: cache_manifest
  jar_pin: cache_jar
  providers: ['framework_authenticator_descriptions.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_authenticator_descriptions'}
  methods: {'android/accounts/AccountManager.smali': description_methods}
  changed: {'android/accounts/AccountManager.smali': 0}
  added: {'android/accounts/AccountManager.smali': 1}
  class_provider: 'framework_authenticator_description_classes'
  extra_classes: description_classes
 }
}

fn protected_storage_profile() NarrowProfile {
 return NarrowProfile{
  name: 'protected-storage'
  baseline_name: 'combined-account-webview-descriptions-framework-2026-10-26-r1'
  manifest_pin: descriptions_manifest
  jar_pin: descriptions_jar
  baseline_classes: 2104
  providers: ['framework_protected_storage.v']
  directory_provider: 'framework_protected_storage'
  methods: {
   'android/content/pm/ApplicationInfo.smali': ['<init>(Landroid/content/pm/ApplicationInfo;)V', 'vinixSetDataDirectory(Ljava/lang/String;)V']
   'android/content/Context.smali': ['getDataDirFile()Ljava/io/File;', '<clinit>()V']
   'android/atl/ATLLoadedAppManager.smali': ['loadApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 'vinixLoadActivityApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']
   'android/app/ContextImpl.smali': ['createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;']
  }
  changed: {'android/content/pm/ApplicationInfo.smali': 1, 'android/content/Context.smali': 2,
   'android/atl/ATLLoadedAppManager.smali': 2, 'android/app/ContextImpl.smali': 1}
  added: {'android/content/pm/ApplicationInfo.smali': 1, 'android/content/Context.smali': 0,
   'android/atl/ATLLoadedAppManager.smali': 0, 'android/app/ContextImpl.smali': 0}
  fields: {'android/content/pm/ApplicationInfo.smali': ['.field public credentialProtectedDataDir:Ljava/lang/String;',
   '.field public deviceProtectedDataDir:Ljava/lang/String;']}
 }
}

fn service_query_profile() NarrowProfile {
 return NarrowProfile{
  name: 'service-query'
  baseline_name: 'combined-account-webview-protected-storage-framework-2026-10-27-r2'
  manifest_pin: protected_storage_manifest
  jar_pin: protected_storage_jar
  baseline_classes: 2104
  providers: ['framework_service_query.v']
  calls: {'android/content/pm/PackageManager.smali': 'framework_service_query'}
  methods: {'android/content/pm/PackageManager.smali': ['queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;']}
  changed: {'android/content/pm/PackageManager.smali': 1}
  added: {'android/content/pm/PackageManager.smali': 0}
 }
}

fn direct_boot_profile() NarrowProfile {
 return NarrowProfile{
  name: 'direct-boot'
  baseline_name: 'combined-account-webview-service-query-framework-2026-10-27-r1'
  manifest_pin: service_query_manifest
  jar_pin: service_query_jar
  baseline_classes: 2104
  providers: ['framework_direct_boot.v']
  calls: {'android/content/pm/ComponentInfo.smali': 'framework_component_direct_boot',
   'android/content/pm/PackageParser.smali': 'framework_parser_direct_boot'}
  methods: {
   'android/content/pm/ComponentInfo.smali': ['<init>(Landroid/content/pm/ComponentInfo;)V']
   'android/content/pm/PackageParser.smali': [
    'parseActivity(Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;ZZ)Landroid/content/pm/PackageParser$Activity;',
    'parseService(Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Service;',
    'parseProvider(Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Provider;',
    'parseActivityAlias(Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Activity;',
    'vinixParseDirectBoot(Landroid/content/res/Resources;Landroid/util/AttributeSet;Landroid/content/pm/ComponentInfo;)V']
  }
  changed: {'android/content/pm/ComponentInfo.smali': 1, 'android/content/pm/PackageParser.smali': 4}
  added: {'android/content/pm/ComponentInfo.smali': 0, 'android/content/pm/PackageParser.smali': 1}
  fields: {'android/content/pm/ComponentInfo.smali': ['.field public directBootAware:Z']}
 }
}

fn credential_storage_profile() NarrowProfile {
 signatures := ['createCredentialProtectedStorageContext()Landroid/content/Context;', 'isCredentialProtectedStorage()Z']
 return NarrowProfile{
  name: 'credential-storage'
  baseline_name: 'combined-account-webview-direct-boot-framework-2026-10-27-r1'
  manifest_pin: direct_boot_manifest
  jar_pin: direct_boot_jar
  baseline_classes: 2104
  providers: ['framework_credential_storage.v']
  calls: {'android/content/Context.smali': 'framework_credential_storage_context',
   'android/content/ContextWrapper.smali': 'framework_credential_storage_wrapper',
   'android/app/ContextImpl.smali': 'framework_credential_storage_impl'}
  methods: {'android/content/Context.smali': signatures, 'android/content/ContextWrapper.smali': signatures,
   'android/app/ContextImpl.smali': signatures}
  changed: {'android/content/Context.smali': 0, 'android/content/ContextWrapper.smali': 0, 'android/app/ContextImpl.smali': 0}
  added: {'android/content/Context.smali': 2, 'android/content/ContextWrapper.smali': 2, 'android/app/ContextImpl.smali': 2}
 }
}

fn broadcast_result_profile() NarrowProfile {
 receiver := 'android/content/BroadcastReceiver.smali'
 pending := 'android/content/BroadcastReceiver$PendingResult.smali'
 loaded := 'android/atl/ATLLoadedApp.smali'
 task := 'android/atl/VinixBroadcast.smali'
 result_methods := ['setResultCode(I)V', 'getResultCode()I', 'setResultData(Ljava/lang/String;)V',
  'getResultData()Ljava/lang/String;', 'setResultExtras(Landroid/os/Bundle;)V',
  'getResultExtras(Z)Landroid/os/Bundle;', 'setResult(ILjava/lang/String;Landroid/os/Bundle;)V',
  'getAbortBroadcast()Z', 'abortBroadcast()V', 'clearAbortBroadcast()V']
 mut receiver_methods := result_methods.clone()
 receiver_methods << ['goAsync()Landroid/content/BroadcastReceiver$PendingResult;',
  'isOrderedBroadcast()Z', 'isInitialStickyBroadcast()Z',
  'vinixRequirePending()Landroid/content/BroadcastReceiver$PendingResult;', 'vinixFinish()V',
  'vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V']
 mut pending_methods := result_methods.clone()
 pending_methods << ['finish()V', '<init>(Z)V', 'vinixWarnUnordered()V']
 return NarrowProfile{
  name: 'broadcast-result'
  baseline_name: 'combined-account-webview-credential-storage-framework-2026-10-27-r1'
  manifest_pin: 'cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691'
  jar_pin: '9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352'
  baseline_classes: 2104
  providers: ['framework_broadcast_result.v']
  calls: {receiver: 'framework_broadcast_receiver', pending: 'framework_broadcast_pending',
   loaded: 'framework_broadcast_loaded_app', task: 'framework_broadcast_run'}
  methods: {
   receiver: receiver_methods
   pending: pending_methods
   loaded: ['receiveBroadcast(Landroid/content/Context;Landroid/content/Intent;)V']
   task: ['run()V']
  }
  changed: {receiver: 2, pending: 2, loaded: 1, task: 1}
  added: {receiver: 14, pending: 11, loaded: 0, task: 0}
  fields: {
   receiver: ['.field private vinixPending:Landroid/content/BroadcastReceiver$PendingResult;']
   pending: ['.field private final vinixRegistered:Z', '.field private vinixCode:I',
    '.field private vinixData:Ljava/lang/String;', '.field private vinixExtras:Landroid/os/Bundle;',
    '.field private vinixAbort:Z', '.field private vinixFinished:Z']
  }
 }
}

fn onboarding_profile() NarrowProfile {
 group := 'android/view/ViewGroup.smali'
 settings := 'android/provider/Settings$Global.smali'
 return NarrowProfile{
  name: 'onboarding'
  baseline_name: 'combined-account-webview-broadcast-result-framework-2026-10-27-r1'
  manifest_pin: '21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046'
  jar_pin: '5dfba8c7e0006f6c84510d72b8fde84706bcb7f3489b3620cd340ec0361d8564'
  baseline_classes: 2104
  providers: ['framework_child_attach.v', 'framework_settings_global.v']
  calls: {group: 'framework_child_attach', settings: 'framework_settings_global_put_int'}
  methods: {
   group: ['attachViewToParent(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V']
   settings: ['putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z']
  }
  changed: {group: 1, settings: 0}
  added: {group: 0, settings: 1}
 }
}

fn application_restrictions_profile() NarrowProfile {
 manager := 'android/os/UserManager.smali'
 return NarrowProfile{
  name: 'application-restrictions'
  baseline_name: 'combined-account-webview-onboarding-framework-2026-10-27-r1'
  manifest_pin: 'bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42'
  jar_pin: 'e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd'
  baseline_classes: 2104
  providers: ['framework_application_restrictions.v']
  calls: {manager: 'framework_application_restrictions_user_manager'}
  methods: {manager: ['getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;']}
  changed: {manager: 0}
  added: {manager: 1}
 }
}

fn auth_exception_profile() NarrowProfile {
 authenticator := 'android/accounts/AbstractAccountAuthenticator.smali'
 return NarrowProfile{
  name: 'auth-exception'
  baseline_name: 'combined-account-webview-application-restrictions-framework-2026-10-28-r1'
  manifest_pin: '8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15'
  jar_pin: 'd4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32'
  baseline_classes: 2104
  providers: ['framework_authenticator_request.v', 'framework_authenticator_base.v']
  calls: {authenticator: 'framework_authenticator_private_exception'}
  methods: {authenticator: ['vinixHandleException(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/Exception;)V']}
  changed: {authenticator: 1}
  added: {authenticator: 0}
 }
}

fn binder_identity_profile() NarrowProfile {
 binder := 'android/os/Binder.smali'
 context := 'android/atl/VinixAccountBrokerContext.smali'
 return NarrowProfile{
  name: 'binder-identity'
  baseline_name: 'combined-account-webview-auth-exception-framework-2026-10-29-r1'
  manifest_pin: '4aa0c09e05c0d4fe3180a909648ebb344881ec1d2d6e60bba5d959148d93a284'
  jar_pin: '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
  baseline_classes: 2104
  providers: ['framework_account_broker_context.v']
  calls: {binder: 'framework_account_broker_identity', context: 'framework_account_broker_identity_context'}
  methods: {
   binder: ['clearCallingIdentity()J', 'restoreCallingIdentity(J)V',
    'vinixOriginalClearCallingIdentity()J', 'vinixOriginalRestoreCallingIdentity(J)V']
   context: ['clearCallingIdentity()J', 'restoreCallingIdentity(J)Z']
  }
  changed: {binder: 2, context: 0}
  added: {binder: 2, context: 2}
 }
}

fn service_lifecycle_profile() NarrowProfile {
 service := 'android/app/Service.smali'
 return NarrowProfile{
  name: 'service-lifecycle'
  baseline_name: 'combined-account-webview-binder-identity-framework-2026-10-29-r1'
  manifest_pin: '739fc9c17258915b0ce7ee01fa3d9e03f47c9d4f4de05ef0c6178d624f8ff3c5'
  jar_pin: '3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636'
  baseline_classes: 2104
  providers: ['framework_service_lifecycle.v']
  calls: {service: 'framework_service_lifecycle_source'}
  methods: {service: ['attachBaseContext(Landroid/content/Context;)V', 'onCreate()V', 'onDestroy()V']}
  changed: {service: 3}
  added: {service: 0}
 }
}

fn platform_fragments_profile() NarrowProfile {
 activity := 'android/app/Activity.smali'
 fragment := 'android/app/Fragment.smali'
 manager := 'android/app/FragmentManager.smali'
 transaction := 'android/app/FragmentTransaction.smali'
 return NarrowProfile{
  name: 'platform-fragments'
  baseline_name: 'combined-account-webview-service-lifecycle-framework-2026-10-29-r1'
  manifest_pin: '9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488'
  jar_pin: '7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74'
  baseline_classes: 2104
  providers: ['framework_platform_fragments.v']
  calls: {
   activity: 'framework_platform_fragments_activity'
   fragment: 'framework_platform_fragments_fragment'
   manager: 'framework_platform_fragments_manager'
   transaction: 'framework_platform_fragments_transaction'
  }
  methods: {
   activity: ['getFragmentManager()Landroid/app/FragmentManager;',
    'vinixLifecycleOnCreate(Landroid/os/Bundle;)V', 'vinixLifecycleOnStart()V',
    'vinixLifecycleOnResume()V', 'vinixLifecycleOnPause()V', 'vinixLifecycleOnStop()V',
    'vinixLifecycleOnDestroy()V', 'vinixPerformCreate(Landroid/os/Bundle;)V',
    'vinixPerformStart()V', 'vinixPerformResume()V', 'vinixPerformPause()V',
    'vinixPerformStop()V', 'vinixPerformDestroy()V']
   fragment: ['getTag()Ljava/lang/String;', 'onAttach(Landroid/app/Activity;)V',
    'onAttach(Landroid/content/Context;)V', 'onActivityCreated(Landroid/os/Bundle;)V', 'onDetach()V']
   manager: ['<init>(Landroid/app/Activity;)V', 'beginTransaction()Landroid/app/FragmentTransaction;',
    'executePendingTransactions()Z', 'findFragmentByTag(Ljava/lang/String;)Landroid/app/Fragment;',
    'vinixCheckHost()V', 'vinixEnqueue(Landroid/app/FragmentTransaction;)V',
    'vinixAdd(Landroid/app/Fragment;)V', 'vinixMoveToState(I)V', 'vinixCancelPosted()V',
    'vinixSynchronize()V', 'vinixMoveFragment(Landroid/app/Fragment;)V', 'vinixTerminalCleanup()V']
   transaction: ['<init>(Landroid/app/Activity;)V',
    'add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;',
    'commit()I', 'vinixExecute()V', 'vinixCancel()V']
  }
  changed: {activity: 13, fragment: 0, manager: 4, transaction: 3}
  added: {activity: 0, fragment: 5, manager: 8, transaction: 2}
  fields: {
   activity: ['.field private vinixPlatformFragments:Landroid/app/FragmentManager;']
   fragment: ['.field vinixManager:Landroid/app/FragmentManager;',
    '.field vinixTag:Ljava/lang/String;', '.field vinixState:I', '.field vinixAdded:Z']
   manager: ['.field private vinixPending:Ljava/util/ArrayList;',
    '.field private vinixHandler:Landroid/os/Handler;', '.field private vinixRunner:Ljava/lang/Runnable;',
    '.field private vinixState:I', '.field private vinixExecuting:Z', '.field private vinixDestroyed:Z']
   transaction: ['.field vinixManager:Landroid/app/FragmentManager;',
    '.field private vinixAdds:Ljava/util/ArrayList;', '.field private vinixCommitted:Z']
  }
  class_provider: 'framework_platform_fragments_classes'
  extra_classes: ['android/app/VinixFragmentCommit.smali']
 }
}

fn imageview_bounds_profile() NarrowProfile {
 image := 'android/widget/ImageView.smali'
 return NarrowProfile{
  name: 'imageview-bounds'
  baseline_name: 'combined-account-webview-platform-fragments-framework-2026-10-29-r1'
  manifest_pin: '5b452702e033f72f9056f994b94295f7925958c62fcaad039827710368249bfb'
  jar_pin: '6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4'
  baseline_classes: 2105
  providers: ['framework_image_bounds.v']
  calls: {image: 'framework_image_bounds_source'}
  methods: {image: ['<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V',
   'setMaxWidth(I)V', 'setMaxHeight(I)V', 'getMaxWidth()I', 'getMaxHeight()I']}
  changed: {image: 3}
  added: {image: 2}
  fields: {image: ['.field private vinixMaxWidth:I', '.field private vinixMaxHeight:I']}
 }
}

fn imageview_bounds_abi(source string) ! {
 parts := store_parts(source)!
 image := 'android/widget/ImageView.smali'
 for signature in imageview_bounds_profile().methods[image]! {
  flags := if signature.starts_with('<init>(') { 'public constructor' } else { 'public' }
  expected := '.method ' + flags + ' ' + signature
  method := parts.methods[signature] or { return error('missing ImageView bounds ABI member: ' + signature) }
  if method.all_before('\n').trim_space() != expected {
   return error('unexpected ImageView bounds method ABI: ' + signature)
  }
 }
}

fn window_system_ui_profile() NarrowProfile {
 layout := 'android/view/WindowManager$LayoutParams.smali'
 return NarrowProfile{
  name: 'window-system-ui'
  baseline_name: 'combined-account-webview-imageview-bounds-framework-2026-10-30-r1'
  manifest_pin: '95853b2f31ac34f731c8c31fc1251fd695ed6d856a8bfef0f71041efc10273e0'
  jar_pin: '9cfdbeaff047b693837508c3f7676510a63c05af118e864964b4b432fb813af9'
  baseline_classes: 2105
  providers: ['framework_window_system_ui.v']
  calls: {layout: 'framework_window_system_ui_source'}
  methods: {layout: []string{}}
  changed: {layout: 0}
  added: {layout: 0}
  fields: {layout: ['.field public systemUiVisibility:I']}
 }
}

fn seed_account_options_profile() NarrowProfile {
 manager := 'android/os/UserManager.smali'
 bundle := 'android/os/PersistableBundle.smali'
 array_map := 'android/util/ArrayMap.smali'
 return NarrowProfile{
  name: 'seed-account-options'
  baseline_name: 'combined-account-webview-window-system-ui-framework-2026-10-30-r1'
  manifest_pin: '1e24a8dcc2f5b315ebbb63cb06d3de46e0799b4b1a0d19339d3b98ecab0c3b09'
  jar_pin: '3f0d220a24e7d91a47f7b2d42cd5620aa498981e915a90cdbd806164b8ef0fc1'
  baseline_classes: 2105
  providers: ['framework_seed_account_options.v']
  calls: {manager: 'framework_seed_account_options_source', bundle: 'framework_seed_account_empty_source', array_map: 'framework_seed_account_array_map_source'}
  methods: {manager: ['getSeedAccountOptions()Landroid/os/PersistableBundle;'], bundle: ['<clinit>()V'], array_map: ['<clinit>()V']}
  changed: {manager: 0, bundle: 0, array_map: 1}
  added: {manager: 1, bundle: 1, array_map: 0}
  fields: {bundle: ['.field public static final EMPTY:Landroid/os/PersistableBundle;']}
 }
}

fn seed_account_options_abi(target string, source string) ! {
 manager := 'android/os/UserManager.smali'
 bundle := 'android/os/PersistableBundle.smali'
 array_map := 'android/util/ArrayMap.smali'
 if target !in [manager, bundle, array_map] { return error('unexpected seed account options target') }
 signature := if target == manager { 'getSeedAccountOptions()Landroid/os/PersistableBundle;' } else { '<clinit>()V' }
 method := store_parts(source)!.methods[signature] or { return error('missing UserManager seed account options API') }
 flags := if target == manager { 'public' } else { 'static constructor' }
 if method.all_before('\n').trim_space() != '.method ' + flags + ' ' + signature {
  return error('unexpected UserManager seed account options method ABI')
 }
 if target == bundle && !store_parts(source)!.metadata.split_into_lines().contains('.field public static final EMPTY:Landroid/os/PersistableBundle;') {
  return error('unexpected PersistableBundle EMPTY field ABI')
 }
}

fn seed_account_options_self_test() ! {
 profile := seed_account_options_profile()
 manager := 'android/os/UserManager.smali'
 bundle := 'android/os/PersistableBundle.smali'
 array_map := 'android/util/ArrayMap.smali'
 signature := 'getSeedAccountOptions()Landroid/os/PersistableBundle;'
 if profile.baseline_classes != 2105 || profile.methods != {manager: [signature], bundle: ['<clinit>()V'], array_map: ['<clinit>()V']}
  || profile.calls != {manager: 'framework_seed_account_options_source', bundle: 'framework_seed_account_empty_source', array_map: 'framework_seed_account_array_map_source'}
  || profile.changed != {manager: 0, bundle: 0, array_map: 1} || profile.added != {manager: 1, bundle: 1, array_map: 0}
  || profile.fields != {bundle: ['.field public static final EMPTY:Landroid/os/PersistableBundle;']} || profile.providers != ['framework_seed_account_options.v']
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('seed account options requires exact getter, EMPTY and initializer-order targets')
 }
 before := '.class public Landroid/os/UserManager;\n.super Ljava/lang/Object;\n' +
  '.method public existing()V\n.locals 0\nreturn-void\n.end method\n'
 method := '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
 after := before + method
 narrow_member_delta(before, after, [signature], 0, 1, []string{})!
 seed_account_options_abi(manager, after)!
 for bad in [before, after + method, after + '.field private extra:I\n',
  after.replace('public existing()V', 'private existing()V'), after.replace('.locals 0', '.locals 1'),
  after.replace('.super Ljava/lang/Object;', '.super Landroid/os/Bundle;'),
  after + '.method public extra()V\n.locals 0\nreturn-void\n.end method\n'] {
  narrow_member_delta(before, bad, [signature], 0, 1, []string{}) or { continue }
  return error('invalid seed account options member delta accepted')
 }
 for flags in ['private', 'public static', 'public final', 'public synthetic'] {
  seed_account_options_abi(manager, after.replace('.method public ' + signature, '.method ' + flags + ' ' + signature)) or { continue }
  return error('invalid seed account options API flags accepted')
 }
 narrow_method_self_test(['<clinit>()V'], 1, 0)!
 bundle_before := '.class public Landroid/os/PersistableBundle;\n.super Landroid/os/BaseBundle;\n'
 bundle_after := bundle_before + '.field public static final EMPTY:Landroid/os/PersistableBundle;\n' +
  '.method static constructor <clinit>()V\n.locals 0\nreturn-void\n.end method\n'
 narrow_member_delta(bundle_before, bundle_after, ['<clinit>()V'], 0, 1, profile.fields[bundle]!)!
 seed_account_options_abi(bundle, bundle_after)!
 for flags in ['private static final', 'public static', 'public final', 'public static final synthetic'] {
  seed_account_options_abi(bundle, bundle_after.replace('.field public static final EMPTY:', '.field ' + flags + ' EMPTY:')) or { continue }
  return error('invalid PersistableBundle EMPTY API flags accepted')
 }
 mut old := {manager: 'old', bundle: 'old', array_map: 'old'}
 for i in 0 .. 2102 { old['other/' + i.str() + '.smali'] = 'same' }
 mut new_classes := old.clone()
 for target in [manager, bundle, array_map] { new_classes[target] = 'new' }
 narrow_profile_class_delta(old, new_classes, [manager, bundle, array_map], []string{}, 2105)!
 new_classes['other/0.smali'] = 'changed'
 narrow_profile_class_delta(old, new_classes, [manager, bundle, array_map], []string{}, 2105) or { return }
 return error('unrelated class change accepted for seed account options')
}

fn persistent_data_block_profile() NarrowProfile {
 context := 'android/app/ContextImpl.smali'
 return NarrowProfile{
  name: 'persistent-data-block'
  baseline_name: 'combined-account-webview-seed-account-options-framework-2026-10-30-r1'
  manifest_pin: '470636b2812f339d58071ba59986282ac5107e5256aa2588dd9305d7ef5b45e9'
  jar_pin: 'cb2e3fabab652c65351da16770ae98c4113781df0830440b734395bb35b6f265'
  baseline_classes: 2105
  providers: ['framework_persistent_data_block.v']
  calls: {context: 'framework_persistent_data_block_source'}
  methods: {context: ['getSystemService(Ljava/lang/Class;)Ljava/lang/Object;']}
  changed: {context: 1}
  added: {context: 0}
  class_provider: 'framework_persistent_data_block_classes'
  extra_classes: ['android/service/persistentdata/PersistentDataBlockManager.smali']
 }
}

fn persistent_data_block_abi(target string, source string) ! {
 if target == 'android/app/ContextImpl.smali' {
  signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
  method := store_parts(source)!.methods[signature] or { return error('missing typed service lookup ABI') }
  if method.all_before('\n').trim_space() != '.method public ' + signature {
   return error('unexpected typed service lookup ABI')
  }
 } else if target == 'android/service/persistentdata/PersistentDataBlockManager.smali' {
  parts := store_parts(source)!
  if parts.methods.len != 0 || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
   '.class public Landroid/service/persistentdata/PersistentDataBlockManager;', '.super Ljava/lang/Object;'] {
   return error('persistent data block type must remain public, nonfinal and memberless')
  }
 } else { return error('unexpected persistent data block target') }
}

fn persistent_data_block_self_test() ! {
 profile := persistent_data_block_profile()
 context := 'android/app/ContextImpl.smali'
 helper := 'android/service/persistentdata/PersistentDataBlockManager.smali'
 signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
 if profile.baseline_classes != 2105 || profile.methods != {context: [signature]}
  || profile.calls != {context: 'framework_persistent_data_block_source'}
  || profile.changed != {context: 1} || profile.added != {context: 0}
  || profile.fields.len != 0 || profile.extra_classes != [helper]
  || profile.providers != ['framework_persistent_data_block.v']
  || profile.class_provider != 'framework_persistent_data_block_classes' || profile.directory_provider != '' {
  return error('persistent data block scope requires one changed lookup and one memberless type')
 }
 narrow_method_self_test([signature], 1, 0)!
 method := '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
 persistent_data_block_abi(context, method)!
 for flags in ['private', 'public static', 'public final', 'public synthetic'] {
  persistent_data_block_abi(context, method.replace('.method public ', '.method ' + flags + ' ')) or { continue }
  return error('invalid typed service lookup flags accepted')
 }
 empty_class := '.class public Landroid/service/persistentdata/PersistentDataBlockManager;\n.super Ljava/lang/Object;\n'
 persistent_data_block_abi(helper, empty_class)!
 for bad in [empty_class.replace('.class public ', '.class public final '),
  empty_class.replace('.class public ', '.class private '), empty_class.replace('Ljava/lang/Object;', 'Landroid/os/Bundle;'),
  empty_class + '.field public state:I\n', empty_class + '.implements Ljava/io/Serializable;\n',
  empty_class + '.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n',
  empty_class + '.method public getDataBlockSize()I\n.locals 1\nconst/4 v0, 0x0\nreturn v0\n.end method\n'] {
  persistent_data_block_abi(helper, bad) or { continue }
  return error('persistent data block type acquired unsupported state or behavior')
 }
 mut before := {context: 'old'}
 for i in 0 .. 2104 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[context] = 'new'
 after[helper] = 'new'
 narrow_profile_class_delta(before, after, [context], [helper], 2105)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad.delete(helper) }
   1 { bad[context] = 'old' }
   2 { bad['other/0.smali'] = 'changed' }
   3 { bad['extra.smali'] = 'new' }
   else { bad.delete(helper); bad['substitute.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [context], [helper], 2105) or { continue }
  return error('invalid persistent data block class scope accepted')
 }
}

fn bitmap_tiles_profile() NarrowProfile {
 drawable := 'android/graphics/drawable/BitmapDrawable.smali'
 return NarrowProfile{
  name: 'bitmap-tiles'
  baseline_name: 'combined-account-webview-persistent-data-block-framework-2026-10-30-r1'
  manifest_pin: 'a6d34af62a2b8fd6f85c84dd36493d47b3eefa9690cf875c7ac0e67abe882858'
  jar_pin: '7c1b2fa03924003c7717e07ef463bff81c6429c7667b2bc42d35954fb6d41752'
  baseline_classes: 2106
  providers: ['framework_bitmap_tiles.v']
  calls: {drawable: 'framework_bitmap_tiles_source'}
  methods: {drawable: bitmap_tiles_method_headers().keys()}
  changed: {drawable: 2}
  added: {drawable: bitmap_tiles_method_headers().len - 2}
  fields: {drawable: ['.field private vinixTileX:Landroid/graphics/Shader$TileMode;',
   '.field private vinixTileY:Landroid/graphics/Shader$TileMode;',
   '.field private vinixPaint:Landroid/graphics/Paint;']}
 }
}

fn bitmap_tiles_method_headers() map[string]string {
 return {
  'getPaint()Landroid/graphics/Paint;': 'public'
  'setTileModeX(Landroid/graphics/Shader$TileMode;)V': 'public'
  'setTileModeY(Landroid/graphics/Shader$TileMode;)V': 'public final'
  'setTileModeXY(Landroid/graphics/Shader$TileMode;Landroid/graphics/Shader$TileMode;)V': 'public'
  'getTileModeX()Landroid/graphics/Shader$TileMode;': 'public'
  'getTileModeY()Landroid/graphics/Shader$TileMode;': 'public'
  'draw(Landroid/graphics/Canvas;)V': 'public'
  'vinixTileMode(Landroid/graphics/Shader$TileMode;)I': 'private static'
  'nativeDrawTiles(Landroid/atl/GskCanvas;Landroid/graphics/Bitmap;IIIILandroid/graphics/Paint;II)V': 'private static native'
 }
}

fn bitmap_tiles_abi(source string) ! {
 parts := store_parts(source)!
 if parts.metadata.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/graphics/drawable/BitmapDrawable;']
  || parts.metadata.split_into_lines().filter(it.starts_with('.super ')) != ['.super Landroid/graphics/drawable/Drawable;'] {
  return error('bitmap tiles require the retained public BitmapDrawable type')
 }
 for signature, flags in bitmap_tiles_method_headers() {
  method := parts.methods[signature] or { return error('missing bitmap tile ABI member: ' + signature) }
  if method.all_before('\n').trim_space() != '.method ' + flags + ' ' + signature {
   return error('unexpected bitmap tile method ABI: ' + signature)
  }
  if flags == 'private static native' && method != '.method ' + flags + ' ' + signature + '\n.end method' {
   return error('bitmap tile native bridge must remain declaration-only')
  }
 }
}

fn bitmap_tiles_self_test() ! {
 profile := bitmap_tiles_profile()
 drawable := 'android/graphics/drawable/BitmapDrawable.smali'
 allowed := profile.methods[drawable]!
 fields := profile.fields[drawable]!
 if profile.baseline_classes != 2106 || profile.methods.len != 1
  || profile.calls != {drawable: 'framework_bitmap_tiles_source'}
  || profile.providers != ['framework_bitmap_tiles.v'] || profile.extra_classes.len != 0
  || profile.class_provider != '' || profile.directory_provider != ''
  || allowed.len != 9 || profile.changed != {drawable: 2} || profile.added != {drawable: 7}
  || fields != ['.field private vinixTileX:Landroid/graphics/Shader$TileMode;',
   '.field private vinixTileY:Landroid/graphics/Shader$TileMode;',
   '.field private vinixPaint:Landroid/graphics/Paint;'] {
  return error('bitmap tiles require exactly one drawable target and three private fields')
 }
 narrow_method_self_test(allowed, 2, allowed.len - 2)!
 metadata := '.class public Landroid/graphics/drawable/BitmapDrawable;\n.super Landroid/graphics/drawable/Drawable;\n.field private bitmap:Landroid/graphics/Bitmap;\n'
 retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + retained
 mut after := metadata + retained + fields.join('\n') + '\n'
 for signature, flags in bitmap_tiles_method_headers() {
  header := '.method ' + flags + ' ' + signature
  if signature in ['getPaint()Landroid/graphics/Paint;', 'setTileModeX(Landroid/graphics/Shader$TileMode;)V'] {
   before += header + '\n.locals 1\nreturn-void\n.end method\n'
  }
  after += if flags == 'private static native' { header + '\n.end method\n' } else {
   header + '\n.locals 2\nreturn-void\n.end method\n'
  }
 }
 narrow_member_delta(before, after, allowed, 2, allowed.len - 2, fields)!
 bitmap_tiles_abi(after)!
 for bad in [after.replace(fields[0], ''), after.replace(fields[0], fields[0] + '\n' + fields[0]),
  after.replace(fields[1], '.field public vinixTileY:Landroid/graphics/Shader$TileMode;'),
  after.replace('.field private bitmap:Landroid/graphics/Bitmap;', '.field private bitmap:Ljava/lang/Object;'),
  after.replace('public retained()V', 'private retained()V'), after + '.field private unrelated:I\n'] {
  narrow_member_delta(before, bad, allowed, 2, allowed.len - 2, fields) or { continue }
  return error('invalid bitmap tile field or retained-member delta accepted')
 }
 for signature, flags in bitmap_tiles_method_headers() {
  header := '.method ' + flags + ' ' + signature
  for replacement in ['.method protected static ' + signature, '.method public native ' + signature,
   '.method protected ' + signature, '.method public synthetic ' + signature] {
   bitmap_tiles_abi(after.replace(header, replacement)) or { continue }
   return error('invalid bitmap tile method flags accepted: ' + signature)
  }
 }
 bridge := '.method private static native nativeDrawTiles(Landroid/atl/GskCanvas;Landroid/graphics/Bitmap;IIIILandroid/graphics/Paint;II)V\n.end method'
 bitmap_tiles_abi(after.replace(bridge, bridge.replace('\n.end method', '\n.locals 0\nreturn-void\n.end method'))) or {
  bitmap_tiles_class_self_test()!
  return
 }
 return error('bitmap tile native bridge body accepted')
}

fn bitmap_tiles_class_self_test() ! {
 drawable := 'android/graphics/drawable/BitmapDrawable.smali'
 mut old_classes := {drawable: 'old'}
 for i in 0 .. 2105 { old_classes['other/' + i.str() + '.smali'] = 'same' }
 mut good := old_classes.clone()
 good[drawable] = 'new'
 narrow_profile_class_delta(old_classes, good, [drawable], []string{}, 2106)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[drawable] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(drawable) }
   3 { bad['unrelated.smali'] = 'added' }
   else { bad.delete(drawable); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old_classes, bad, [drawable], []string{}, 2106) or { continue }
  return error('invalid bitmap drawable-only class delta accepted')
 }
}

fn window_animations_profile() NarrowProfile {
 window := 'android/view/Window.smali'
 callback := 'android/view/Window$Callback.smali'
 activity := 'android/app/Activity.smali'
 dialog := 'android/app/Dialog.smali'
 notification := 'onWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V'
 return NarrowProfile{
  name: 'window-animations'
  baseline_name: 'combined-account-webview-bitmap-tiles-framework-2026-10-30-r1'
  manifest_pin: 'bf8626569c82826e4d6b6379a3e2266741db3d2919d2eda4cf647b18c5b5f7df'
  jar_pin: '741641c30098cf2f682672889c7ac653c6b2f23b9c09001a7af8f56bb01d9500'
  baseline_classes: 2106
  providers: ['framework_window_animations.v']
  calls: {window: 'framework_window_animations_source', callback: 'framework_window_animations_callback_source',
   activity: 'framework_window_animations_activity_source', dialog: 'framework_window_animations_dialog_source'}
  methods: {window: ['setWindowAnimations(I)V', 'dispatchWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V'],
   callback: [notification], activity: [notification], dialog: [notification]}
  changed: {window: 0, callback: 0, activity: 0, dialog: 0}
  added: {window: 2, callback: 1, activity: 1, dialog: 1}
 }
}

fn window_animations_method_headers(target string) !map[string]string {
 notification := 'onWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V'
 return match target {
  'android/view/Window.smali' { {'setWindowAnimations(I)V': 'public',
   'dispatchWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V': 'protected'} }
  'android/view/Window$Callback.smali' { map[string]string{notification: 'public abstract'} }
  'android/app/Activity.smali', 'android/app/Dialog.smali' { map[string]string{notification: 'public'} }
  else { return error('unexpected window animations target') }
 }
}

fn window_animations_abi(target string, source string) ! {
 parts := store_parts(source)!
 for signature, flags in window_animations_method_headers(target)! {
  method := parts.methods[signature] or { return error('missing window animations ABI member: ' + signature) }
  expected := '.method ' + flags + ' ' + signature
  if method.all_before('\n').trim_space() != expected { return error('unexpected window animations ABI flags: ' + signature) }
  if flags == 'public abstract' && method != expected + '\n.end method' {
   return error('window attribute callback interface member must remain declaration-only')
  }
 }
}

fn window_animations_self_test() ! {
 profile := window_animations_profile()
 window := 'android/view/Window.smali'
 callback := 'android/view/Window$Callback.smali'
 activity := 'android/app/Activity.smali'
 dialog := 'android/app/Dialog.smali'
 notification := 'onWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V'
 if profile.baseline_classes != 2106 || profile.methods != {
  window: ['setWindowAnimations(I)V', 'dispatchWindowAttributesChanged(Landroid/view/WindowManager$LayoutParams;)V'],
  callback: [notification], activity: [notification], dialog: [notification]}
  || profile.calls != {window: 'framework_window_animations_source', callback: 'framework_window_animations_callback_source',
   activity: 'framework_window_animations_activity_source', dialog: 'framework_window_animations_dialog_source'}
  || profile.changed != {window: 0, callback: 0, activity: 0, dialog: 0}
  || profile.added != {window: 2, callback: 1, activity: 1, dialog: 1}
  || profile.providers != ['framework_window_animations.v'] || profile.fields.len != 0
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('window animations require exactly five additive methods in four existing classes')
 }
 for target, signatures in profile.methods {
  narrow_method_self_test(signatures, 0, profile.added[target]!)!
  metadata := '.class public LExample;\n.super Ljava/lang/Object;\n'
  retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
  before := metadata + retained
  mut after := before
  for signature, flags in window_animations_method_headers(target)! {
   after += '.method ' + flags + ' ' + signature + if flags == 'public abstract' { '\n.end method\n' } else { '\n.locals 2\nreturn-void\n.end method\n' }
  }
  narrow_member_delta(before, after, signatures, 0, profile.added[target]!, []string{})!
  window_animations_abi(target, after)!
  for signature, flags in window_animations_method_headers(target)! {
   header := '.method ' + flags + ' ' + signature
   for replacement in ['.method public static ' + signature, '.method private ' + signature,
    '.method public native ' + signature, '.method public final ' + signature] {
    window_animations_abi(target, after.replace(header, replacement)) or { continue }
    return error('invalid window animations method flags accepted')
   }
  }
  if target == callback {
   changed := after.replace('\n.end method\n', '\n.locals 0\nreturn-void\n.end method\n')
   window_animations_abi(target, changed) or { continue }
   return error('window callback interface body accepted')
  }
 }
 mut old := map[string]string{}
 for target in profile.methods.keys() { old[target] = 'old' }
 for i in 0 .. 2102 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 for target in profile.methods.keys() { good[target] = 'new' }
 narrow_profile_class_delta(old, good, profile.methods.keys(), []string{}, 2106)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[window] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(callback) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(dialog); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, profile.methods.keys(), []string{}, 2106) or { continue }
  return error('invalid window animations class scope accepted')
 }
}

fn layout_alignment_profile() NarrowProfile {
 layout := 'android/text/Layout.smali'
 return NarrowProfile{
  name: 'layout-alignment'
  baseline_name: 'combined-account-webview-window-animations-framework-2026-10-30-r1'
  manifest_pin: '19d67639dce414866deab4c3de57ac8576b5542dff6d58c8b0b78caf066f3e53'
  jar_pin: '255718e8a943f8d3e276f99694c52ed5ec39af86d5d06abef3c9b14d7b9aa197'
  baseline_classes: 2106
  providers: ['framework_layout_alignment.v']
  calls: {layout: 'framework_layout_alignment_source'}
  methods: {layout: ['getAlignment()Landroid/text/Layout$Alignment;', 'getSpacingAdd()F']}
  changed: {layout: 0}
  added: {layout: 2}
 }
}

fn layout_alignment_abi(source string) ! {
 parts := store_parts(source)!
 for signature in ['getAlignment()Landroid/text/Layout$Alignment;', 'getSpacingAdd()F'] {
  method := parts.methods[signature] or { return error('missing Layout getter ABI: ' + signature) }
  if method.all_before('\n').trim_space() != '.method public final ' + signature {
   return error('Layout getters must retain public final ABI')
  }
 }
}

fn layout_alignment_self_test() ! {
 profile := layout_alignment_profile()
 layout := 'android/text/Layout.smali'
 signatures := ['getAlignment()Landroid/text/Layout$Alignment;', 'getSpacingAdd()F']
 if profile.baseline_classes != 2106 || profile.methods != {layout: signatures}
  || profile.calls != {layout: 'framework_layout_alignment_source'}
  || profile.changed != {layout: 0} || profile.added != {layout: 2}
  || profile.providers != ['framework_layout_alignment.v'] || profile.fields.len != 0
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('Layout alignment and spacing require two additive getters and no other members or classes')
 }
 narrow_method_self_test(signatures, 0, 2)!
 mut methods := ''
 for signature in signatures { methods += '.method public final ' + signature + '\n.locals 1\nconst/4 v0, 0x0\nreturn-void\n.end method\n' }
 layout_alignment_abi(methods)!
 for signature in signatures {
  for flags in ['public', 'private final', 'public static', 'public final native', 'public final synthetic'] {
   layout_alignment_abi(methods.replace('.method public final ' + signature, '.method ' + flags + ' ' + signature)) or { continue }
   return error('invalid Layout getter flags accepted')
  }
 }
 mut old := {layout: 'old'}
 for i in 0 .. 2105 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[layout] = 'new'
 narrow_profile_class_delta(old, good, [layout], []string{}, 2106)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[layout] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(layout) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(layout); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [layout], []string{}, 2106) or { continue }
  return error('invalid Layout-only class scope accepted')
 }
}

fn user_restrictions_profile() NarrowProfile {
 manager := 'android/os/UserManager.smali'
 return NarrowProfile{
  name: 'user-restrictions'
  baseline_name: 'combined-account-webview-layout-alignment-framework-2026-10-30-r1'
  manifest_pin: '1266de2e0a64d876e3559240fe5596ad67d9f2cfce81bd0e1e727675c0d39e00'
  jar_pin: '162c77f853e6cb85f373493c40c302ff4df5b90ed52f2e6dce961e5e17281d01'
  baseline_classes: 2106
  providers: ['framework_user_restrictions.v']
  calls: {manager: 'framework_user_restrictions_source'}
  methods: {manager: ['getUserRestrictions()Landroid/os/Bundle;', 'hasUserRestriction(Ljava/lang/String;)Z']}
  changed: {manager: 0}
  added: {manager: 2}
 }
}

fn user_restrictions_abi(source string) ! {
 parts := store_parts(source)!
 for signature in ['getUserRestrictions()Landroid/os/Bundle;', 'hasUserRestriction(Ljava/lang/String;)Z'] {
  method := parts.methods[signature] or { return error('missing UserManager restriction ABI: ' + signature) }
  if method.all_before('\n').trim_space() != '.method public ' + signature {
   return error('UserManager restriction queries must remain public virtual methods')
  }
 }
}

fn user_restrictions_self_test() ! {
 profile := user_restrictions_profile()
 manager := 'android/os/UserManager.smali'
 signatures := ['getUserRestrictions()Landroid/os/Bundle;', 'hasUserRestriction(Ljava/lang/String;)Z']
 if profile.baseline_classes != 2106 || profile.methods != {manager: signatures}
  || profile.calls != {manager: 'framework_user_restrictions_source'}
  || profile.changed != {manager: 0} || profile.added != {manager: 2}
  || profile.providers != ['framework_user_restrictions.v'] || profile.fields.len != 0
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('UserManager restrictions require two additive queries and no other members or classes')
 }
 narrow_method_self_test(signatures, 0, 2)!
 mut methods := ''
 for signature in signatures { methods += '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0x0\nreturn-void\n.end method\n' }
 user_restrictions_abi(methods)!
 for signature in signatures {
  for flags in ['public final', 'private', 'public static', 'public native', 'public synthetic'] {
   user_restrictions_abi(methods.replace('.method public ' + signature, '.method ' + flags + ' ' + signature)) or { continue }
   return error('invalid UserManager restriction query flags accepted')
  }
 }
 mut old := {manager: 'old'}
 for i in 0 .. 2105 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[manager] = 'new'
 narrow_profile_class_delta(old, good, [manager], []string{}, 2106)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[manager] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(manager) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(manager); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [manager], []string{}, 2106) or { continue }
  return error('invalid UserManager-only class scope accepted')
 }
}

fn bundle_cross_profile_profile() NarrowProfile {
 bundle := 'android/os/BaseBundle.smali'
 context := 'android/app/ContextImpl.smali'
 return NarrowProfile{
  name: 'bundle-cross-profile'
  baseline_name: 'combined-account-webview-user-restrictions-framework-2026-10-31-r3'
  manifest_pin: '2e3b4a212238fc14a47b6cc72d1abde24c95a26e379ecd79f99f54527314040c'
  jar_pin: '646a83ea74795fb29b4db8811fc3249add3693b6e2de03e043c52e4e13b09bdc'
  baseline_classes: 2106
  providers: ['framework_bundle_boolean.v', 'framework_cross_profile_apps.v']
  calls: {bundle: 'framework_bundle_boolean_source', context: 'framework_cross_profile_apps_source'}
  methods: {bundle: ['getBoolean(Ljava/lang/String;Z)Z'], context: ['getSystemService(Ljava/lang/Class;)Ljava/lang/Object;']}
  changed: {bundle: 1, context: 1}
  added: {bundle: 0, context: 0}
  class_provider: 'framework_cross_profile_apps_classes'
  extra_classes: ['android/content/pm/CrossProfileApps.smali']
 }
}

fn bundle_boolean_method(source string) !string {
 signature := 'getBoolean(Ljava/lang/String;Z)Z'
 method := store_parts(source)!.methods[signature] or { return error('missing BaseBundle boolean getter') }
 if method.all_before('\n').trim_space() != '.method public ' + signature {
  return error('BaseBundle boolean getter must retain its public virtual ABI')
 }
 return method.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn bundle_boolean_abi(source string) ! {
 method := bundle_boolean_method(source)!
 if method.count('const-string v1, "com.facebook.sdk.AutoLogAppEventsEnabled"') != 1
  || method.count('invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z') != 1
  || method.contains('invoke-virtual {p1, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z') {
  return error('BaseBundle boolean getter requires the exact constant-first legacy-key comparison')
 }
}

fn bundle_boolean_members(before string, after string) ! {
 narrow_method_delta(before, after, ['getBoolean(Ljava/lang/String;Z)Z'], 1, 0)!
 original := bundle_boolean_method(before)!
 updated := bundle_boolean_method(after)!
 old := 'invoke-virtual {p1, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'
 new := 'invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'
 if original.count(old) != 1 || original.contains(new) || updated != original.replace(old, new) {
  return error('BaseBundle boolean repair may change only the comparison receiver and argument')
 }
 bundle_boolean_abi(after)!
}

fn bundle_boolean_self_test() ! {
 bundle := 'android/os/BaseBundle.smali'
 signature := 'getBoolean(Ljava/lang/String;Z)Z'
 narrow_method_self_test([signature], 1, 0)!
 old_instruction := 'invoke-virtual {p1, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'
 new_instruction := 'invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'
 before := '.class public Landroid/os/BaseBundle;\n.super Ljava/lang/Object;\n' +
  '.method public ' + signature + '\n.registers 10\nconst-string v1, "com.facebook.sdk.AutoLogAppEventsEnabled"\n' +
  old_instruction + '\nmove-result v1\nreturn p2\n.end method\n' +
  '.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
 after := before.replace(old_instruction, new_instruction)
 bundle_boolean_members(before, after)!
 for bad in [before, after.replace(new_instruction, 'invoke-virtual {v1, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'),
  after.replace(new_instruction, new_instruction + '\n' + new_instruction),
  after.replace('com.facebook.sdk.AutoLogAppEventsEnabled', 'different-key'),
  after.replace('return p2', 'const/4 p2, 0x0\nreturn p2'),
  after.replace('.registers 10', '.registers 11'),
  after.replace('.locals 0', '.locals 1'),
  after + '.method public extra()V\n.locals 0\nreturn-void\n.end method\n'] {
  bundle_boolean_members(before, bad) or { continue }
  return error('unrelated BaseBundle boolean instruction or member change accepted')
 }
 for flags in ['private', 'public final', 'public static', 'public native', 'public synthetic'] {
  bundle_boolean_abi(after.replace('.method public ' + signature, '.method ' + flags + ' ' + signature)) or { continue }
  return error('changed BaseBundle getter flags accepted')
 }
 mut old := {bundle: 'old'}
 for i in 0 .. 2105 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[bundle] = 'new'
 narrow_profile_class_delta(old, good, [bundle], []string{}, 2106)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[bundle] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(bundle) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(bundle); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [bundle], []string{}, 2106) or { continue }
  return error('invalid BaseBundle-only class scope accepted')
 }
}

fn cross_profile_lookup_method(source string) !string {
 signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
 method := store_parts(source)!.methods[signature] or { return error('missing typed service lookup') }
 if method.all_before('\n').trim_space() != '.method public ' + signature {
  return error('typed cross-profile service lookup must retain public virtual ABI')
 }
 return method.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn cross_profile_members(before string, after string) ! {
 narrow_method_delta(before, after, ['getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'], 1, 0)!
 old := cross_profile_lookup_method(before)!
 updated := cross_profile_lookup_method(after)!.split_into_lines()
 if !old.contains('\n.registers 3\n') || updated.len < 8
  || updated[..6] != ['.method public getSystemService(Ljava/lang/Class;)Ljava/lang/Object;', '.registers 3',
   'const-class v0, Landroid/content/pm/CrossProfileApps;',
   updated[3], 'const/4 v0, 0x0', 'return-object v0'] {
  return error('typed cross-profile lookup requires one early null-return guard')
 }
 original_tail := old.all_after('\n.registers 3\n')
 actual_tail := updated[7..].join('\n')
 canonical_tail := original_tail.replace(':cond_c', ':cond_12').replace(':cond_6', ':cond_c')
 raw := updated[3] == 'if-ne p1, v0, :vinix_cross_profile_other' && updated[6] == ':vinix_cross_profile_other'
  && actual_tail == original_tail
 canonical := updated[3] == 'if-ne p1, v0, :cond_6' && updated[6] == ':cond_6' && actual_tail == canonical_tail
 if !raw && !canonical { return error('typed cross-profile guard or complete retained fallback changed') }
}

fn cross_profile_type_abi(source string) ! {
 parts := store_parts(source)!
 if parts.methods.len != 0 || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public Landroid/content/pm/CrossProfileApps;', '.super Ljava/lang/Object;'] {
  return error('unsupported cross-profile type must remain public, nonfinal and memberless')
 }
}

fn bundle_cross_profile_self_test() ! {
 profile := bundle_cross_profile_profile()
 bundle := 'android/os/BaseBundle.smali'
 context := 'android/app/ContextImpl.smali'
 helper := 'android/content/pm/CrossProfileApps.smali'
 signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
 methods := {bundle: ['getBoolean(Ljava/lang/String;Z)Z'], context: [signature]}
 if profile.baseline_classes != 2106 || profile.methods != methods
  || profile.calls != {bundle: 'framework_bundle_boolean_source', context: 'framework_cross_profile_apps_source'}
  || profile.changed != {bundle: 1, context: 1} || profile.added != {bundle: 0, context: 0}
  || profile.providers != ['framework_bundle_boolean.v', 'framework_cross_profile_apps.v'] || profile.fields.len != 0
  || profile.extra_classes != [helper] || profile.class_provider != 'framework_cross_profile_apps_classes'
  || profile.directory_provider != '' {
  return error('combined Bundle/cross-profile scope requires two changed methods and one memberless type')
 }
 bundle_boolean_self_test()!
 narrow_method_self_test([signature], 1, 0)!
 header := '.class public final Landroid/app/ContextImpl;\n.super Landroid/content/Context;\n'
 method_header := '.method public ' + signature + '\n.registers 3\n'
 tail := 'const-class v0, Landroid/service/persistentdata/PersistentDataBlockManager;\nif-ne p1, v0, :cond_6\nconst/4 v0, 0x0\nreturn-object v0\n:cond_6\nconst-class v0, Landroid/net/wifi/rtt/WifiRttManager;\nif-ne p1, v0, :cond_c\nconst/4 v0, 0x0\nreturn-object v0\n:cond_c\ninvoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixRttFallbackClass(Ljava/lang/Class;)Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n.end method\n'
 guard := 'const-class v0, Landroid/content/pm/CrossProfileApps;\nif-ne p1, v0, :vinix_cross_profile_other\nconst/4 v0, 0x0\nreturn-object v0\n:vinix_cross_profile_other\n'
 before := header + method_header + tail
 raw := header + method_header + guard + tail
 canonical := header + method_header + guard.replace(':vinix_cross_profile_other', ':cond_6') + tail.replace(':cond_c', ':cond_12').replace(':cond_6', ':cond_c')
 cross_profile_members(before, raw)!
 cross_profile_members(before, canonical)!
 for bad in [before, raw.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'),
  raw.replace('if-ne p1, v0, :vinix_cross_profile_other', 'if-eq p1, v0, :vinix_cross_profile_other'),
  raw.replace('vinixRttFallbackClass', 'otherFallback'), raw.replace('.registers 3', '.registers 4'),
  raw.replace('public ' + signature, 'public final ' + signature),
  raw + '.method public extra()V\n.locals 0\nreturn-void\n.end method\n',
  canonical.replace('if-ne p1, v0, :cond_c', 'if-ne p1, v0, :cond_6')] {
  cross_profile_members(before, bad) or { continue }
  return error('invalid typed cross-profile null guard or retained fallback accepted')
 }
 type_source := '.class public Landroid/content/pm/CrossProfileApps;\n.super Ljava/lang/Object;\n'
 cross_profile_type_abi(type_source)!
 for bad in [type_source.replace('.class public ', '.class public final '),
  type_source.replace('.super Ljava/lang/Object;', '.super Landroid/app/Service;'),
  type_source + '.field public value:I\n',
  type_source + '.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n'] {
  cross_profile_type_abi(bad) or { continue }
  return error('nonmemberless cross-profile API type accepted')
 }
 mut old := {bundle: 'old', context: 'old'}
 for i in 0 .. 2104 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[bundle] = 'new'
 good[context] = 'new'
 good[helper] = 'new'
 narrow_profile_class_delta(old, good, [bundle, context], [helper], 2106)!
 for case in 0 .. 7 {
  mut bad := good.clone()
  match case {
   0 { bad[bundle] = 'old' }
   1 { bad[context] = 'old' }
   2 { bad['other/0.smali'] = 'changed' }
   3 { bad.delete(helper) }
   4 { bad['unrelated.smali'] = 'new' }
   5 { bad.delete(context); bad['substituted.smali'] = 'new' }
   else { bad.delete(helper); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [bundle, context], [helper], 2106) or { continue }
  return error('invalid combined Bundle/cross-profile class scope accepted')
 }
}

fn resources_float_profile() NarrowProfile {
 resources := 'android/content/res/Resources.smali'
 return NarrowProfile{
  name: 'resources-float'
  baseline_name: 'combined-account-webview-bundle-cross-profile-framework-2026-10-31-r1'
  manifest_pin: 'e9b9093ee1b8546bca93732cab02a4b58e8ddb25f8c4aae216e40c6602e542aa'
  jar_pin: '3ebf88615dcb87ec103b098a0baf397f5a4428623f809fd139b23e9f60978235'
  baseline_classes: 2107
  providers: ['framework_resources_float.v']
  calls: {resources: 'framework_resources_float_source'}
  methods: {resources: ['getFloat(I)F']}
  changed: {resources: 0}
  added: {resources: 1}
 }
}

fn resources_float_expected_method() string {
 return '.method public getFloat(I)F
.locals 4
new-instance v0, Landroid/util/TypedValue;
invoke-direct {v0}, Landroid/util/TypedValue;-><init>()V
const/4 v1, 0x1
invoke-virtual {p0, p1, v0, v1}, Landroid/content/res/Resources;->getValue(ILandroid/util/TypedValue;Z)V
iget v1, v0, Landroid/util/TypedValue;->type:I
const/4 v2, 0x4
if-ne v1, v2, :not_float
invoke-virtual {v0}, Landroid/util/TypedValue;->getFloat()F
move-result v0
return v0
:not_float
new-instance v2, Landroid/content/res/Resources$NotFoundException;
new-instance v3, Ljava/lang/StringBuilder;
invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V
const-string v0, "Resource ID #0x"
invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {p1}, Ljava/lang/Integer;->toHexString(I)Ljava/lang/String;
move-result-object v0
invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v0, " type #0x"
invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {v1}, Ljava/lang/Integer;->toHexString(I)Ljava/lang/String;
move-result-object v0
invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v0, " is not valid"
invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
invoke-direct {v2, v0}, Landroid/content/res/Resources$NotFoundException;-><init>(Ljava/lang/String;)V
throw v2
.end method'
}

fn resources_float_abi(source string) ! {
 method := store_parts(source)!.methods['getFloat(I)F'] or { return error('missing Resources float getter') }
 // The literal resource diagnostic contains '#'; only whole comments may go.
 actual := method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
 expected := resources_float_expected_method()
 canonical := expected.replace('.locals 4', '.registers 6').replace(':not_float', ':cond_13')
 if actual != expected && actual != canonical {
  return error('Resources float getter must retain exact typed lookup, strict float test and NotFoundException body')
 }
}

fn resources_float_self_test() ! {
 profile := resources_float_profile()
 resources := 'android/content/res/Resources.smali'
 signature := 'getFloat(I)F'
 if profile.baseline_classes != 2107 || profile.methods != {resources: [signature]}
  || profile.calls != {resources: 'framework_resources_float_source'}
  || profile.changed != {resources: 0} || profile.added != {resources: 1}
  || profile.providers != ['framework_resources_float.v'] || profile.fields.len != 0
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('Resources float scope requires one added getter without other member or class changes')
 }
 narrow_method_self_test([signature], 0, 1)!
 expected := resources_float_expected_method()
 resources_float_abi(expected)!
 resources_float_abi(expected.replace('.locals 4', '.registers 6').replace(':not_float', ':cond_13'))!
 for flags in ['private', 'public final', 'public static', 'public native', 'public synthetic'] {
  resources_float_abi(expected.replace('.method public ' + signature, '.method ' + flags + ' ' + signature)) or { continue }
  return error('changed Resources float getter flags accepted')
 }
 for bad in [expected.replace('const/4 v1, 0x1', 'const/4 v1, 0x0'),
  expected.replace('const/4 v2, 0x4', 'const/4 v2, 0x5'),
  expected.replace('if-ne v1, v2', 'if-eq v1, v2'),
  expected.replace('invoke-virtual {p0, p1, v0, v1}', 'invoke-direct {p0, p1, v0, v1}'),
  expected.replace('Resource ID #0x', 'Resource ID 0x'),
  expected.replace('type #0x', 'type 0x'),
  expected.replace('invoke-static {p1}, Ljava/lang/Integer;', 'invoke-static {v1}, Ljava/lang/Integer;'),
  expected.replace('Resources$NotFoundException;', 'RuntimeException;'),
  expected.replace('throw v2', 'return v0'), expected.replace('.locals 4', '.locals 5')] {
  resources_float_abi(bad) or { continue }
  return error('changed Resources typed-float lookup or failure contract accepted')
 }
 mut old := {resources: 'old'}
 for i in 0 .. 2106 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[resources] = 'new'
 narrow_profile_class_delta(old, good, [resources], []string{}, 2107)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[resources] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(resources) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(resources); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [resources], []string{}, 2107) or { continue }
  return error('invalid Resources-only class scope accepted')
 }
}

fn paint_drawable_profile() NarrowProfile {
 return NarrowProfile{
  name: 'paint-drawable'
  baseline_name: 'combined-account-webview-resources-float-framework-2026-10-31-r1'
  manifest_pin: 'b88ea5adb85e7b5ea6ff70cdd7310fbb039e1922c4d3467b35ce6f71ebd0d38f'
  jar_pin: 'aac12a41b70ce34c0893580431a28de81cb3476e7c6833cbe0c0ca8596db677d'
  baseline_classes: 2107
  providers: ['framework_paint_drawable.v']
  directory_provider: 'framework_paint_drawable'
  class_provider: 'framework_paint_drawable_classes'
  extra_classes: ['android/graphics/drawable/PaintDrawable.smali']
 }
}

fn paint_drawable_raw_pin() string { return 'eba47a450e64ba9c72b2032e3bb79782b084347c01915a79e2acb9816b3ac461' }

fn paint_drawable_headers() map[string]string {
 return {
  '<init>()V': 'public constructor'
  '<init>(I)V': 'public constructor'
  'setCornerRadius(F)V': 'public'
  'setCornerRadii([F)V': 'public'
  'inflateTag(Ljava/lang/String;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;)Z': 'protected'
 }
}

// Compare all instructions while rebasing only labels to instruction ordinals
// and the equivalent .locals/.registers spelling of this added class.
fn paint_drawable_method(source string, parameters int) !string {
 lines := source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#'))
 mut labels := map[string]string{}
 mut instruction := 0
 for line in lines {
  if line.starts_with(':') {
   if line in labels { return error('duplicate PaintDrawable branch label') }
   labels[line] = ':instruction_' + instruction.str()
  } else if !line.starts_with('.') { instruction++ }
 }
 mut result := []string{}
 for line in lines {
  if line.starts_with(':') { continue }
  if line.starts_with('.locals ') {
   result << '.registers ' + (line.all_after(' ').int() + parameters).str()
   continue
  }
  mut parts := line.split(' ')
  for i, part in parts {
   if replacement := labels[part] { parts[i] = replacement }
   else if part.starts_with(':') { return error('undefined PaintDrawable branch label') }
  }
  result << parts.join(' ')
 }
 return result.join('\n')
}

fn paint_drawable_members(raw string, assembled string) ! {
 headers := paint_drawable_headers()
 for source in [raw, assembled] {
  parts := store_parts(source)!
  if parts.methods.keys().sorted() != headers.keys().sorted()
   || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '').join('\n') !=
    '.class public Landroid/graphics/drawable/PaintDrawable;\n.super Landroid/graphics/drawable/ShapeDrawable;' {
   return error('PaintDrawable must add only the exact public subclass and five methods')
  }
  for signature, flags in headers {
   if parts.methods[signature]!.all_before('\n').trim_space() != '.method ' + flags + ' ' + signature {
    return error('PaintDrawable method access or ABI changed: ' + signature)
   }
  }
 }
 before, after := store_parts(raw)!, store_parts(assembled)!
 for name, body in before.methods {
  parameters := if name == '<init>()V' { 1 } else if name.starts_with('inflateTag(') { 5 } else { 2 }
  if paint_drawable_method(body, parameters)! != paint_drawable_method(after.methods[name]!, parameters)! {
   return error('DEX changed PaintDrawable method instructions: ' + name)
  }
 }
}

fn paint_drawable_abi(raw string, assembled string) ! {
 if !valid_pin(paint_drawable_raw_pin()) || sha256.sum(raw.bytes()).hex() != paint_drawable_raw_pin() {
  return error('PaintDrawable raw class differs from the focused qualified provider')
 }
 paint_drawable_members(raw, assembled)!
}

fn paint_drawable_class_delta(old map[string]string, new map[string]string) ! {
 added := 'android/graphics/drawable/PaintDrawable.smali'
 if old.len != 2107 || new.len != 2108 || added in old || added !in new {
  return error('PaintDrawable requires exactly one new class over the complete 2107-class parent')
 }
 for name, pin in old {
  if name !in new || new[name]! != pin { return error('PaintDrawable changed existing class: ' + name) }
 }
}

fn paint_drawable_self_test() ! {
 profile := paint_drawable_profile()
 added := 'android/graphics/drawable/PaintDrawable.smali'
 if profile.baseline_classes != 2107 || profile.methods.len != 0 || profile.calls.len != 0
  || profile.changed.len != 0 || profile.added.len != 0 || profile.fields.len != 0
  || profile.providers != ['framework_paint_drawable.v'] || profile.extra_classes != [added]
  || profile.class_provider != 'framework_paint_drawable_classes'
  || profile.directory_provider != 'framework_paint_drawable' || !valid_pin(paint_drawable_raw_pin()) {
  return error('PaintDrawable scope requires one complete added class and no existing changes')
 }
 mut raw := '.class public Landroid/graphics/drawable/PaintDrawable;\n.super Landroid/graphics/drawable/ShapeDrawable;\n'
 for signature, flags in paint_drawable_headers() {
  body := if signature.starts_with('inflateTag(') { 'const/4 v0, 0x0\nreturn v0' }
   else if signature == 'setCornerRadius(F)V' { 'const/4 v0, 0x0\n:finish\nif-eqz v0, :finish\nreturn-void' }
   else { 'return-void' }
  raw += '.method ' + flags + ' ' + signature + '\n.locals 1\n' + body + '\n.end method\n'
 }
 paint_drawable_members(raw, raw)!
 canonical := raw.replace(':finish', ':cond_1')
  .replace('.method public constructor <init>()V\n.locals 1', '.method public constructor <init>()V\n.registers 2')
 paint_drawable_members(raw, canonical)!
 for bad in [canonical.replace('.class public ', '.class public final '),
  canonical.replace('.super Landroid/graphics/drawable/ShapeDrawable;', '.super Ljava/lang/Object;'),
  canonical + '.field public extra:I\n', canonical + '.implements Ljava/io/Serializable;\n',
  canonical.replace('.method public setCornerRadius', '.method public final setCornerRadius'),
  canonical.replace('.method protected inflateTag', '.method public inflateTag'),
  canonical.replace('if-eqz v0', 'if-nez v0'), canonical.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'),
  canonical.replace('\n:cond_1\n', '\n:renamed\n'),
  canonical.replace('.registers 2', '.registers 3'), canonical + store_parts(raw)!.methods['<init>()V']!,
  canonical.replace(store_parts(canonical)!.methods['<init>(I)V']!, '')] {
  paint_drawable_members(raw, bad) or { continue }
  return error('changed PaintDrawable body, access or metadata accepted')
 }
 mut raw_refused := false
 paint_drawable_abi(raw, raw) or { raw_refused = true }
 if !raw_refused { return error('unqualified PaintDrawable raw body accepted') }
 mut old := map[string]string{}
 for i in 0 .. 2107 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[added] = 'new'
 paint_drawable_class_delta(old, good)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad.delete(added) }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete('other/0.smali') }
   3 { bad['extra.smali'] = 'new' }
   else { bad.delete(added); bad['substituted.smali'] = 'new' }
  }
  paint_drawable_class_delta(old, bad) or { continue }
  return error('invalid PaintDrawable-only class addition accepted')
 }
}

fn dialog_theme_profile() NarrowProfile {
 dialog := 'android/app/Dialog.smali'
 return NarrowProfile{
  name: 'dialog-theme'
  baseline_name: 'combined-account-webview-paint-drawable-framework-2026-11-01-r1'
  manifest_pin: '15a60de7b8196aaca79d869cec972b0382da1be7327ee8f10c56b7e1db37cbb2'
  jar_pin: 'b3fed7d846a23d9e8afc1256e5bfa7d9ebcd1ba5330705d40fd14131291d516c'
  baseline_classes: 2108
  providers: ['framework_dialog_theme.v']
  directory_provider: 'framework_dialog_theme'
  methods: {dialog: ['<init>(Landroid/content/Context;I)V']}
  changed: {dialog: 1}
  added: {dialog: 0}
 }
}

fn dialog_theme_old_constructor() string {
 return '.method public constructor <init>(Landroid/content/Context;I)V
.registers 7
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/app/Dialog;->context:Landroid/content/Context;
new-instance v0, Landroid/view/Window;
invoke-direct {v0, p1, p0}, Landroid/view/Window;-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
iput-object v0, p0, Landroid/app/Dialog;->window:Landroid/view/Window;
invoke-virtual {p0}, Landroid/app/Dialog;->nativeInit()J
move-result-wide v0
iput-wide v0, p0, Landroid/app/Dialog;->nativePtr:J
iget-object v0, p0, Landroid/app/Dialog;->window:Landroid/view/Window;
iget-wide v2, p0, Landroid/app/Dialog;->nativePtr:J
invoke-virtual {v0, v2, v3}, Landroid/view/Window;->set_native_window(J)V
return-void
.end method'
}

fn dialog_theme_expected_constructor() string {
 old := dialog_theme_old_constructor()
 start := 'iput-object p1, p0, Landroid/app/Dialog;->context:Landroid/content/Context;'
 finish := 'iput-object v0, p0, Landroid/app/Dialog;->window:Landroid/view/Window;'
 before := old.all_before(start)
 after := old.all_after(finish)
 return before + 'if-nez p2, :theme_selected
new-instance v0, Landroid/util/TypedValue;
invoke-direct {v0}, Landroid/util/TypedValue;-><init>()V
invoke-virtual {p1}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v1
sget v2, Landroid/R$attr;->dialogTheme:I
const/4 v3, 0x1
invoke-virtual {v1, v2, v0, v3}, Landroid/content/res/Resources$Theme;->resolveAttribute(ILandroid/util/TypedValue;Z)Z
iget p2, v0, Landroid/util/TypedValue;->resourceId:I
:theme_selected
new-instance v0, Landroid/view/ContextThemeWrapper;
invoke-direct {v0, p1, p2}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
iput-object v0, p0, Landroid/app/Dialog;->context:Landroid/content/Context;
new-instance v1, Landroid/view/Window;
invoke-direct {v1, v0, p0}, Landroid/view/Window;-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
iput-object v1, p0, Landroid/app/Dialog;->window:Landroid/view/Window;' + after
}

fn dialog_theme_members(old string, updated string) ! {
 signature := '<init>(Landroid/content/Context;I)V'
 before := store_parts(old)!.methods[signature] or { return error('missing retained Dialog constructor') }
 after := store_parts(updated)!.methods[signature] or { return error('missing themed Dialog constructor') }
 expected := dialog_theme_expected_constructor()
 norm_before := before.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
 norm_after := after.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
 if norm_before != dialog_theme_old_constructor()
  || (norm_after != expected && norm_after != expected.replace(':theme_selected', ':cond_16')) {
  return error('Dialog theme constructor must retain exact wrapper/default lookup and original native window tail')
 }
}

fn dialog_theme_self_test() ! {
 profile := dialog_theme_profile()
 dialog := 'android/app/Dialog.smali'
 signature := '<init>(Landroid/content/Context;I)V'
 if profile.baseline_classes != 2108 || profile.methods != {dialog: [signature]}
  || profile.calls.len != 0 || profile.changed != {dialog: 1} || profile.added != {dialog: 0}
  || profile.providers != ['framework_dialog_theme.v'] || profile.directory_provider != 'framework_dialog_theme'
  || profile.fields.len != 0 || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('Dialog theme profile requires exactly one changed constructor body')
 }
 narrow_method_self_test([signature], 1, 0)!
 old := dialog_theme_old_constructor()
 expected := dialog_theme_expected_constructor()
 dialog_theme_members(old, expected)!
 dialog_theme_members(old, expected.replace(':theme_selected', ':cond_16'))!
 for invalid in [expected.replace('.method public constructor ', '.method private constructor '),
  expected.replace('.registers 7', '.registers 8'), expected.replace('if-nez p2', 'if-eqz p2'),
  expected.replace('const/4 v3, 0x1', 'const/4 v3, 0x0'),
  expected.replace('TypedValue;->resourceId:I', 'TypedValue;->data:I'),
  expected.replace('sget v2, Landroid/R$attr;->dialogTheme:I', 'const/4 v2, 0x0'),
  expected.replace('{v0, p1, p2}', '{v0, p1, v2}'),
  expected.replace('iput-object v0, p0, Landroid/app/Dialog;->context:', 'iput-object p1, p0, Landroid/app/Dialog;->context:'),
  expected.replace('{v1, v0, p0}', '{v1, p1, p0}'),
  expected.replace('move-result-wide v0', 'move-result-wide v2'),
  expected.replace('->set_native_window(J)V', '->wrong_native_window(J)V'),
  expected.replace(':theme_selected', ':wrong_label')] {
  dialog_theme_members(old, invalid) or { continue }
  return error('Dialog constructor wrapper/default/native-tail mutation accepted')
 }
 for invalid in [old.replace('iput-object p1', 'iput-object p2'), old.replace('.registers 7', '.registers 8')] {
  dialog_theme_members(invalid, expected) or { continue }
  return error('different original Dialog constructor accepted')
 }
 mut before := {dialog: 'old'}
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut good := before.clone()
 good[dialog] = 'new'
 narrow_profile_class_delta(before, good, [dialog], []string{}, 2108)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[dialog] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(dialog) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(dialog); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [dialog], []string{}, 2108) or { continue }
  return error('invalid Dialog-only class delta accepted')
 }
}

fn intent_extras_profile() NarrowProfile {
 intent := 'android/content/Intent.smali'
 return NarrowProfile{
  name: 'intent-extras'
  baseline_name: 'combined-account-webview-dialog-theme-framework-2026-11-01-r1'
  manifest_pin: 'a3547ad6477b3fb2eb7a9bcd7d73b8870c89a6bf69c4a84db03dc79e3222859f'
  jar_pin: '9d8d2b1f59f80bf0d704daa65eaf3b479fa83458338f23d9fe17aa7a57b541b6'
  baseline_classes: 2108
  providers: ['framework_intent_extras.v']
  directory_provider: 'framework_intent_extras'
  methods: {intent: ['putExtras(Landroid/content/Intent;)Landroid/content/Intent;', 'putExtras(Landroid/os/Bundle;)Landroid/content/Intent;']}
  changed: {intent: 2}
  added: {intent: 0}
 }
}

fn pending_intent_existing_methods() []string {
 return ['<clinit>()V',
  'getActivities(Landroid/content/Context;I[Landroid/content/Intent;ILandroid/os/Bundle;)Landroid/app/PendingIntent;',
  'getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;',
  'getService(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;',
  'getForegroundService(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;',
  'getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;',
  'cancel()V', 'send()V', 'send(Landroid/content/Context;ILandroid/content/Intent;)V',
  'getCreatorPackage()Ljava/lang/String;', 'getCreatorUid()I', 'toString()Ljava/lang/String;']
}

fn pending_intent_helper_headers() map[string]string {
 return {
  'vinixCopyIntents(Landroid/content/Intent;[Landroid/content/Intent;)[Landroid/content/Intent;': 'private static'
  'vinixGet(Landroid/content/Context;ILandroid/content/Intent;[Landroid/content/Intent;II)Landroid/app/PendingIntent;': 'private static'
  'vinixCreatorContext(Landroid/content/Context;)Landroid/content/Context;': 'private static'
  'vinixCancel(Landroid/app/PendingIntent;)V': 'private static'
  'vinixPrepare(Landroid/app/PendingIntent;Landroid/content/Intent;)[Landroid/content/Intent;': 'private static'
  'vinixDispatch(Landroid/app/PendingIntent;[Landroid/content/Intent;)V': 'private static'
  'vinixFillIn(Landroid/content/Intent;Landroid/content/Intent;I)V': 'private static'
 }
}

fn pending_intent_fields() []string {
 return ['.field private static final vinixOperations:Ljava/util/ArrayList;',
  '.field private vinixCreator:Landroid/content/Context;',
  '.field private vinixCreatorPackage:Ljava/lang/String;', '.field private vinixCreatorUid:I',
  '.field private vinixFlags:I', '.field private vinixIntents:[Landroid/content/Intent;',
  '.field private vinixKey:Landroid/content/Intent;']
}

fn pending_intent_profile() NarrowProfile {
 pending := 'android/app/PendingIntent.smali'
 mut helpers := pending_intent_helper_headers().keys()
 helpers.sort()
 mut allowed := pending_intent_existing_methods()
 allowed << helpers
 return NarrowProfile{
  name: 'pending-intent'
  baseline_name: 'combined-account-webview-intent-extras-framework-2026-11-01-r2'
  manifest_pin: 'bef486d060754858d51612b9c4bb8a24f7c2fdf8f37cc3565101e24a049bf52f'
  jar_pin: '02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20'
  baseline_classes: 2108
  providers: ['framework_pending_intent_successor.v']
  directory_provider: 'framework_pending_intent_successor'
  methods: {pending: allowed}
  changed: {pending: 12}
  added: {pending: 7}
  fields: {pending: pending_intent_fields()}
 }
}

fn pending_intent_abi(source string) ! {
 parts := store_parts(source)!
 mut headers := pending_intent_helper_headers()
 for signature in pending_intent_existing_methods() {
  headers[signature] = if signature == '<clinit>()V' { 'static constructor' }
   else if signature.starts_with('getActivit') || signature.starts_with('getService(')
    || signature.starts_with('getForegroundService(') || signature.starts_with('getBroadcast(') { 'public static' }
   else { 'public' }
 }
 for signature, flags in headers {
  method := parts.methods[signature] or { return error('missing PendingIntent operation member: ' + signature) }
  if method.all_before('\n').trim_space() != '.method ' + flags + ' ' + signature {
   return error('unexpected PendingIntent operation ABI or monitor boundary: ' + signature)
  }
 }
}

fn pending_intent_self_test() ! {
 profile := pending_intent_profile()
 pending := 'android/app/PendingIntent.smali'
 mut helpers := pending_intent_helper_headers().keys()
 helpers.sort()
 mut allowed := pending_intent_existing_methods()
 allowed << helpers
 if profile.name != 'pending-intent' || profile.baseline_classes != 2108
  || profile.baseline_name != 'combined-account-webview-intent-extras-framework-2026-11-01-r2'
  || profile.manifest_pin != 'bef486d060754858d51612b9c4bb8a24f7c2fdf8f37cc3565101e24a049bf52f'
  || profile.jar_pin != '02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20'
  || profile.methods != {pending: allowed} || allowed.len != 19
  || pending_intent_existing_methods().len != 12 || helpers.len != 7
  || profile.changed != {pending: 12} || profile.added != {pending: 7}
  || profile.providers != ['framework_pending_intent_successor.v']
  || profile.directory_provider != 'framework_pending_intent_successor'
  || profile.fields != {pending: pending_intent_fields()} || pending_intent_fields().len != 7
  || profile.calls.len != 0 || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('PendingIntent profile requires exactly one retained class with twelve replacements and seven private helpers/fields')
 }
 narrow_method_self_test(allowed, 12, 7)!
 metadata := '.class public Landroid/app/PendingIntent;\n.super Ljava/lang/Object;\n.field private retained:I\n'
 unrelated := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + unrelated
 mut after := metadata + pending_intent_fields().join('\n') + '\n' + unrelated
 mut headers := pending_intent_helper_headers()
 for signature in pending_intent_existing_methods() {
  headers[signature] = if signature == '<clinit>()V' { 'static constructor' }
   else if signature.starts_with('getActivit') || signature.starts_with('getService(')
    || signature.starts_with('getForegroundService(') || signature.starts_with('getBroadcast(') { 'public static' }
   else { 'public' }
 }
 for signature in allowed {
  method := '.method ' + headers[signature]! + ' ' + signature + '\n.locals 1\nreturn-void\n.end method\n'
  if signature in pending_intent_existing_methods() { before += method }
  after += method.replace('.locals 1', '.locals 2')
 }
 narrow_member_delta(before, after, allowed, 12, 7, pending_intent_fields())!
 pending_intent_abi(after)!
 for bad in [after.replace('.field private vinixFlags:I', '.field public vinixFlags:I'),
  after.replace('.field private vinixKey:Landroid/content/Intent;', ''),
  after + '\n.field private unrelated:I\n',
  after.replace('.field private retained:I', '.field public retained:I'),
  after.replace('.method public retained()V', '.method private retained()V'),
  after + unrelated] {
  narrow_member_delta(before, bad, allowed, 12, 7, pending_intent_fields()) or { continue }
  return error('PendingIntent metadata, retained member, duplicate or extra field mutation accepted')
 }
 for signature, flags in headers {
  marker := '.method ' + flags + ' ' + signature
  for replacement in ['.method public ' + signature, '.method private native ' + signature,
   '.method public static final ' + signature] {
   if marker == replacement { continue }
   pending_intent_abi(after.replace(marker, replacement)) or { continue }
   return error('PendingIntent method visibility/static/monitor mutation accepted')
  }
 }
 mut old := {pending: 'old'}
 for i in 0 .. 2107 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[pending] = 'new'
 narrow_profile_class_delta(old, good, [pending], []string{}, 2108)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[pending] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(pending) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(pending); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old, bad, [pending], []string{}, 2108) or { continue }
  return error('invalid PendingIntent-only class scope accepted')
 }
}

fn stable_display_profile() NarrowProfile {
 manager := 'android/hardware/display/DisplayManager.smali'
 return NarrowProfile{
  name: 'stable-display'
  baseline_name: 'combined-account-webview-pending-intent-framework-2026-11-02-r1'
  manifest_pin: '8717d3d489e9f86b8c96d2689c7ec6811bc7c80fbade0e35f64e9e84014f7c36'
  jar_pin: 'bc82567de6d8abd6a4084c68e0e4c698df12d2c7848c7d23b6af7e5d0e6df7cc'
  baseline_classes: 2108
  providers: ['framework_stable_display.v']
  calls: {manager: 'framework_stable_display_source'}
  methods: {manager: ['getStableDisplaySize()Landroid/graphics/Point;']}
  changed: {manager: 0}
  added: {manager: 1}
 }
}

fn stable_display_abi(source string) ! {
 signature := 'getStableDisplaySize()Landroid/graphics/Point;'
 method := store_parts(source)!.methods[signature] or { return error('missing stable display native declaration') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public native ' + signature, '.end method'] {
  return error('stable display requires exactly one public virtual native declaration without executable instructions')
 }
}

fn stable_display_self_test() ! {
 profile := stable_display_profile()
 manager := 'android/hardware/display/DisplayManager.smali'
 signature := 'getStableDisplaySize()Landroid/graphics/Point;'
 if profile.name != 'stable-display' || profile.baseline_classes != 2108
  || profile.baseline_name != 'combined-account-webview-pending-intent-framework-2026-11-02-r1'
  || profile.manifest_pin != '8717d3d489e9f86b8c96d2689c7ec6811bc7c80fbade0e35f64e9e84014f7c36'
  || profile.jar_pin != 'bc82567de6d8abd6a4084c68e0e4c698df12d2c7848c7d23b6af7e5d0e6df7cc'
  || profile.providers != ['framework_stable_display.v']
  || profile.calls != {manager: 'framework_stable_display_source'}
  || profile.methods != {manager: [signature]} || profile.changed != {manager: 0}
  || profile.added != {manager: 1} || profile.fields.len != 0 || profile.directory_provider != ''
  || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('stable display profile requires exactly one added native method in one retained class')
 }
 narrow_method_self_test([signature], 0, 1)!
 native := '.method public native ' + signature + '\n.end method\n'
 stable_display_abi(native)!
 for bad in [native.replace('public native', 'private native'),
  native.replace('public native', 'public static native'), native.replace('public native', 'public'),
  native.replace('public native', 'public final native'), native.replace('()Landroid/graphics/Point;', '(I)Landroid/graphics/Point;'),
  native.replace('.end method', '.registers 1\n.end method'),
  native.replace('.end method', 'return-object p0\n.end method'), native + native] {
  stable_display_abi(bad) or { continue }
  return error('stable display native visibility/static/signature/body mutation accepted')
 }
 mut before := {manager: 'old'}
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[manager] = 'new'
 narrow_profile_class_delta(before, after, [manager], []string{}, 2108)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[manager] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(manager) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(manager); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [manager], []string{}, 2108) or { continue }
  return error('invalid DisplayManager-only class scope accepted')
 }
}

fn device_secure_profile() NarrowProfile {
 manager := 'android/app/KeyguardManager.smali'
 return NarrowProfile{
  name: 'device-secure'
  baseline_name: 'combined-account-webview-stable-display-framework-2026-11-02-r1'
  manifest_pin: '44a0ad6abdf51562e770a1848f6db06c2c2de75a1160868e999c1face01136df'
  jar_pin: '3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52'
  baseline_classes: 2108
  providers: ['framework_device_secure.v']
  calls: {manager: 'framework_device_secure_source'}
  methods: {manager: ['isDeviceSecure()Z']}
  changed: {manager: 0}
  added: {manager: 1}
 }
}

fn device_secure_abi(source string) ! {
 signature := 'isDeviceSecure()Z'
 method := store_parts(source)!.methods[signature] or { return error('missing device secure query') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public ' + signature, '.registers 2', 'const/4 v0, 0x0', 'return v0', '.end method'] {
  return error('device secure query requires the exact public virtual false result for this credentialless guest')
 }
}

fn device_secure_self_test() ! {
 profile := device_secure_profile()
 manager := 'android/app/KeyguardManager.smali'
 signature := 'isDeviceSecure()Z'
 if profile.name != 'device-secure' || profile.baseline_classes != 2108
  || profile.baseline_name != 'combined-account-webview-stable-display-framework-2026-11-02-r1'
  || profile.manifest_pin != '44a0ad6abdf51562e770a1848f6db06c2c2de75a1160868e999c1face01136df'
  || profile.jar_pin != '3b51a6cfe506db8e87908fdf74fcaebd585aaace383e8880a0183cd901780e52'
  || profile.providers != ['framework_device_secure.v']
  || profile.calls != {manager: 'framework_device_secure_source'}
  || profile.methods != {manager: [signature]} || profile.changed != {manager: 0}
  || profile.added != {manager: 1} || profile.fields.len != 0 || profile.directory_provider != ''
  || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('device secure profile requires exactly one added query in one retained class')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := '.method public ' + signature + '\n.registers 2\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
 device_secure_abi(method)!
 for bad in [method.replace('public ', 'private '), method.replace('public ', 'public static '),
  method.replace('public ', 'public native '), method.replace('public ', 'public final '),
  method.replace('isDeviceSecure()Z', 'isDeviceSecure(I)Z'), method.replace('.registers 2', '.registers 3'),
  method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('return v0', 'return p0'),
  method.replace('return v0', 'return v0\nreturn v0'), method + method] {
  device_secure_abi(bad) or { continue }
  return error('device secure query ABI/register/result/body mutation accepted')
 }
 mut before := {manager: 'old'}
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[manager] = 'new'
 narrow_profile_class_delta(before, after, [manager], []string{}, 2108)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[manager] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(manager) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(manager); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [manager], []string{}, 2108) or { continue }
  return error('invalid KeyguardManager-only class scope accepted')
 }
}

fn unmanaged_query_methods() map[string]string {
 return {'android/app/admin/DevicePolicyManager.smali': 'getDeviceOwner()Ljava/lang/String;',
  'android/os/UserManager.smali': 'isManagedProfile()Z'}
}

fn unmanaged_queries_profile() NarrowProfile {
 policy := 'android/app/admin/DevicePolicyManager.smali'
 users := 'android/os/UserManager.smali'
 return NarrowProfile{
  name: 'unmanaged-queries'
  baseline_name: 'combined-account-webview-device-secure-framework-2026-11-02-r1'
  manifest_pin: 'db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2'
  jar_pin: '43e3e2b941677cda70021ae9cd674aac6f4897af4ab4bda1d2d751b805d1f137'
  baseline_classes: 2108
  providers: ['framework_unmanaged_queries.v']
  calls: {policy: 'framework_device_owner_source', users: 'framework_managed_profile_source'}
  methods: {policy: ['getDeviceOwner()Ljava/lang/String;'], users: ['isManagedProfile()Z']}
  changed: {policy: 0, users: 0}
  added: {policy: 1, users: 1}
 }
}

fn unmanaged_query_abi(source string, target string) ! {
 signature := unmanaged_query_methods()[target] or { return error('unsupported unmanaged query class') }
 method := store_parts(source)!.methods[signature] or { return error('missing unmanaged query: ' + signature) }
 returned := if target == 'android/app/admin/DevicePolicyManager.smali' { 'return-object v0' } else { 'return v0' }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public ' + signature, '.registers 2', 'const/4 v0, 0x0', returned, '.end method'] {
  return error('unmanaged guest query requires exact public virtual null-owner or false-profile result')
 }
}

fn unmanaged_queries_self_test() ! {
 profile := unmanaged_queries_profile()
 policy := 'android/app/admin/DevicePolicyManager.smali'
 users := 'android/os/UserManager.smali'
 if profile.name != 'unmanaged-queries' || profile.baseline_classes != 2108
  || profile.baseline_name != 'combined-account-webview-device-secure-framework-2026-11-02-r1'
  || profile.manifest_pin != 'db98d6fcd6e0c792761f39b07ceb40d5e5818b691dede6eaccd177ec0f9973f2'
  || profile.jar_pin != '43e3e2b941677cda70021ae9cd674aac6f4897af4ab4bda1d2d751b805d1f137'
  || profile.providers != ['framework_unmanaged_queries.v']
  || profile.calls != {policy: 'framework_device_owner_source', users: 'framework_managed_profile_source'}
  || profile.methods != {policy: ['getDeviceOwner()Ljava/lang/String;'], users: ['isManagedProfile()Z']}
  || profile.changed != {policy: 0, users: 0} || profile.added != {policy: 1, users: 1}
  || profile.fields.len != 0 || profile.directory_provider != '' || profile.extra_classes.len != 0
  || profile.class_provider != '' {
  return error('unmanaged queries require exactly one added method in each of two retained classes')
 }
 for target, signature in unmanaged_query_methods() {
  narrow_method_self_test([signature], 0, 1)!
  returned := if target == policy { 'return-object v0' } else { 'return v0' }
  other_return := if target == policy { 'return v0' } else { 'return-object v0' }
  method := '.method public ' + signature + '\n.registers 2\nconst/4 v0, 0x0\n' + returned + '\n.end method\n'
  unmanaged_query_abi(method, target)!
  for bad in [method.replace('public ', 'private '), method.replace('public ', 'public static '),
   method.replace('public ', 'public native '), method.replace('public ', 'public final '),
   method.replace('()', '(I)'), method.replace('.registers 2', '.registers 3'),
   method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace(returned, other_return),
   method.replace(returned, returned + '\n' + returned), method + method] {
   unmanaged_query_abi(bad, target) or { continue }
   return error('unmanaged query ABI/register/result/return-kind mutation accepted')
  }
 }
 mut before := {policy: 'old-policy', users: 'old-users'}
 for i in 0 .. 2106 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[policy] = 'new-policy'
 after[users] = 'new-users'
 targets := [policy, users]
 narrow_profile_class_delta(before, after, targets, []string{}, 2108)!
 for target in targets {
  for case in 0 .. 5 {
   mut bad := after.clone()
   match case {
    0 { bad[target] = before[target]! }
    1 { bad['other/0.smali'] = 'changed' }
    2 { bad.delete(target) }
    3 { bad['unrelated.smali'] = 'new' }
    else { bad.delete(target); bad['substituted.smali'] = 'new' }
   }
   narrow_profile_class_delta(before, bad, targets, []string{}, 2108) or { continue }
   return error('invalid exact two-class unmanaged-query scope accepted')
  }
 }
}

fn stats_unavailable_profile() NarrowProfile {
 context := 'android/app/ContextImpl.smali'
 return NarrowProfile{
  name: 'stats-unavailable'
  baseline_name: 'combined-account-webview-unmanaged-queries-framework-2026-11-02-r1'
  manifest_pin: 'c54e83fadd83a1e74f2fc8938c5767c190d5783fba5f95fd583aa6432d8c361e'
  jar_pin: '25500d52cf7c03a2a1c82656c00284c507dbdb03cff546dbc6e5840aa45b5c1c'
  baseline_classes: 2108
  providers: ['framework_stats_service.v']
  calls: {context: 'framework_stats_service_source'}
  methods: {context: ['getSystemService(Ljava/lang/Class;)Ljava/lang/Object;']}
  changed: {context: 1}
  added: {context: 0}
  class_provider: 'framework_stats_service_classes'
  extra_classes: ['android/app/StatsManager.smali']
 }
}

fn stats_unavailable_guard() string {
 return 'const-class v0, Landroid/app/StatsManager;\nif-ne p1, v0, :vinix_stats_unavailable_other\nconst/4 v0, 0x0\nreturn-object v0\n:vinix_stats_unavailable_other\n'
}

fn stats_unavailable_members(before string, after string) ! {
 signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
 narrow_method_delta(before, after, [signature], 1, 0)!
 old := cross_profile_lookup_method(before)!
 updated := cross_profile_lookup_method(after)!
 if old.count('\n.registers 3\n') != 1 || old.contains('Landroid/app/StatsManager;') {
  return error('retained typed lookup required before absent stats guard')
 }
 expected := old.replace('\n.registers 3\n', '\n.registers 3\n' + stats_unavailable_guard())
 if intent_extras_method(updated)! != intent_extras_method(expected)! {
  return error('stats typed lookup must add only the exact early null guard and preserve all fallback instructions')
 }
}

fn stats_unavailable_type_abi(source string) ! {
 parts := store_parts(source)!
 if parts.methods.len != 0 || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public final Landroid/app/StatsManager;', '.super Ljava/lang/Object;'] {
  return error('unsupported StatsManager must remain one public final memberless marker without a constructor or backend')
 }
}

fn stats_unavailable_self_test() ! {
 profile := stats_unavailable_profile()
 context := 'android/app/ContextImpl.smali'
 marker := 'android/app/StatsManager.smali'
 signature := 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
 if profile.name != 'stats-unavailable' || profile.baseline_classes != 2108 || profile.methods != {context: [signature]}
  || profile.calls != {context: 'framework_stats_service_source'}
  || profile.providers != ['framework_stats_service.v'] || profile.changed != {context: 1}
  || profile.added != {context: 0} || profile.fields.len != 0 || profile.directory_provider != ''
  || profile.extra_classes != [marker] || profile.class_provider != 'framework_stats_service_classes'
  || profile.baseline_name != 'combined-account-webview-unmanaged-queries-framework-2026-11-02-r1'
  || profile.manifest_pin != 'c54e83fadd83a1e74f2fc8938c5767c190d5783fba5f95fd583aa6432d8c361e'
  || profile.jar_pin != '25500d52cf7c03a2a1c82656c00284c507dbdb03cff546dbc6e5840aa45b5c1c' {
  return error('stats unavailable profile requires one typed lookup guard and one marker class')
 }
 narrow_method_self_test([signature], 1, 0)!
 old := '.method public ' + signature + '\n.registers 3\nconst-class v0, Landroid/content/pm/CrossProfileApps;\nif-ne p1, v0, :cond_6\nconst/4 v0, 0x0\nreturn-object v0\n:cond_6\nconst-class v0, Landroid/service/persistentdata/PersistentDataBlockManager;\nif-ne p1, v0, :cond_c\nconst/4 v0, 0x0\nreturn-object v0\n:cond_c\nconst-class v0, Landroid/net/wifi/rtt/WifiRttManager;\nif-ne p1, v0, :cond_12\nconst/4 v0, 0x0\nreturn-object v0\n:cond_12\ninvoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixRttFallbackClass(Ljava/lang/Class;)Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n.end method\n'
 raw := old.replace('.registers 3\n', '.registers 3\n' + stats_unavailable_guard())
 canonical := raw.replace(':cond_12', ':cond_18').replace(':cond_c', ':cond_12').replace(':cond_6', ':cond_c').replace(':vinix_stats_unavailable_other', ':cond_6')
 stats_unavailable_members(old, raw)!
 stats_unavailable_members(old, canonical)!
 stats_unavailable_members(old, raw.replace(':vinix_stats_unavailable_other\nconst-class', ':vinix_stats_unavailable_other\n:alias_fallback\nconst-class').replace('if-ne p1, v0, :vinix_stats_unavailable_other', 'if-ne p1, v0, :alias_fallback'))!
 for bad in [old, raw.replace('public ' + signature, 'public final ' + signature),
  raw.replace('.registers 3', '.registers 4'), raw.replace('Landroid/app/StatsManager;', 'Landroid/app/Activity;'),
  raw.replace('if-ne p1, v0, :vinix_stats_unavailable_other', 'if-eq p1, v0, :vinix_stats_unavailable_other'),
  raw.replace('if-ne p1, v0, :vinix_stats_unavailable_other', 'if-ne p1, v0, :cond_6'),
  raw.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), raw.replace('vinixRttFallbackClass', 'otherFallback'),
  raw.replace('return-object v0', 'return-object p0'), raw + '.method public extra()V\n.locals 0\nreturn-void\n.end method\n'] {
  stats_unavailable_members(old, bad) or { continue }
  return error('stats null-guard or retained fallback mutation accepted')
 }
 marker_source := '.class public final Landroid/app/StatsManager;\n.super Ljava/lang/Object;\n'
 stats_unavailable_type_abi(marker_source)!
 for bad in [marker_source.replace('public final', 'public'), marker_source.replace('public final', 'private final'),
  marker_source.replace('Ljava/lang/Object;', 'Ljava/lang/Exception;'), marker_source + '.field public backend:I\n',
  marker_source + '.implements Ljava/lang/Runnable;\n',
  marker_source + '.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n'] {
  stats_unavailable_type_abi(bad) or { continue }
  return error('StatsManager backend/member/constructor or marker metadata mutation accepted')
 }
 mut before := {context: 'old'}
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[context] = 'new'
 after[marker] = 'marker'
 narrow_profile_class_delta(before, after, [context], [marker], 2108)!
 for target in [context, marker, 'other/0.smali'] {
  mut bad := after.clone()
  if target in before { bad[target] = before[target]! } else { bad.delete(target) }
  if target.starts_with('other/') { bad[target] = 'changed' }
  narrow_profile_class_delta(before, bad, [context], [marker], 2108) or { continue }
  return error('stats unavailable class scope mutation accepted')
 }
}

fn subscription_service_methods() map[string][]string {
 return {
  'android/app/ContextImpl.smali': [
   'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;',
   'getSystemService(Ljava/lang/String;)Ljava/lang/Object;',
   'vinixSubscriptionService()Landroid/telephony/SubscriptionManager;']
  'android/telephony/SubscriptionManager.smali': [
   'getActiveSubscriptionInfoList()Ljava/util/List;',
   'getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;',
   'getPhoneNumber(I)Ljava/lang/String;']
  'android/telephony/TelephonyManager.smali': [
   'getPhoneCount()I', 'getActiveModemCount()I',
   'createForSubscriptionId(I)Landroid/telephony/TelephonyManager;']
 }
}

fn subscription_service_fields() map[string][]string {
 return {
  'android/app/ContextImpl.smali': ['.field private vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;']
  'android/telephony/TelephonyManager.smali': ['.field private vinixSubscriptionId:I']
 }
}

fn subscription_service_profile() NarrowProfile {
 context := 'android/app/ContextImpl.smali'
 subscriptions := 'android/telephony/SubscriptionManager.smali'
 telephony := 'android/telephony/TelephonyManager.smali'
 return NarrowProfile{
  name: 'subscription-service'
  baseline_name: 'combined-account-webview-stats-unavailable-framework-2026-11-02-r1'
  manifest_pin: 'f0bdf43e99a7ada2b8ec52dde5e8da45ebf6162cd2b8a9a0b32bfc55bfa12106'
  jar_pin: '86d1cc8dc592082aeb837fd260e36a4a0c93bbe5a23e3f22e4f97b5ba09e7ffd'
  baseline_classes: 2109
  providers: ['framework_subscription_service.v']
  calls: {
   context: 'framework_subscription_context_source'
   subscriptions: 'framework_subscription_manager_source'
   telephony: 'framework_subscription_telephony_source'
  }
  methods: subscription_service_methods()
  changed: {context: 2, subscriptions: 0, telephony: 0}
  added: {context: 1, subscriptions: 3, telephony: 3}
  fields: subscription_service_fields()
  class_provider: 'framework_subscription_service_classes'
  extra_classes: ['android/telephony/SubscriptionInfo.smali']
 }
}

fn subscription_service_type_abi(source string) ! {
 parts := store_parts(source)!
 if parts.methods.len != 0 || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public final Landroid/telephony/SubscriptionInfo;', '.super Ljava/lang/Object;'] {
  return error('absent subscription info must remain a public final memberless type without constructors or invented subscriptions')
 }
}

fn subscription_service_abi(source string, target string) ! {
 parts := store_parts(source)!
 signatures := subscription_service_methods()[target] or { return error('unsupported subscription service class') }
 for signature in signatures {
  method := parts.methods[signature] or { return error('missing subscription service method: ' + signature) }
  flags := if signature.starts_with('vinixSubscriptionService(') { 'private' } else { 'public' }
  if method.all_before('\n').trim_space() != '.method ' + flags + ' ' + signature {
   return error('subscription service requires exact public instance queries and private explicit-monitor cache helper')
  }
 }
}

fn subscription_service_guard(signature string) !string {
 helper := 'invoke-direct {p0}, Landroid/app/ContextImpl;->vinixSubscriptionService()Landroid/telephony/SubscriptionManager;\nmove-result-object v0\nreturn-object v0\n'
 return match signature {
  'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;' {
   'const-class v0, Landroid/telephony/SubscriptionManager;\nif-ne p1, v0, :vinix_subscription_typed_other\n' + helper + ':vinix_subscription_typed_other\n'
  }
  'getSystemService(Ljava/lang/String;)Ljava/lang/Object;' {
   'const-string v0, "telephony_subscription_service"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :vinix_subscription_string_other\n' + helper + ':vinix_subscription_string_other\n'
  }
  else { return error('unexpected subscription lookup overload') }
 }
}

// DEX may place the catchall directive beside its end label. Retain the exact
// protected interval/handler and every instruction, rebasing label aliases only.
fn subscription_service_method(source string) !string {
 mut lines := []string{}
 mut catches := []string{}
 for original in source.split_into_lines() {
  line := original.trim_space()
  if line.starts_with('.catchall ') { catches << line.replace('{:', '{ :').replace('}', ' }') }
  else if line != '.end method' { lines << line }
 }
 lines << catches
 lines << '.end method'
 return intent_extras_method(lines.join('\n'))
}

fn subscription_service_expected_methods() map[string]string {
 return {
  'vinixSubscriptionService()Landroid/telephony/SubscriptionManager;': '.method private vinixSubscriptionService()Landroid/telephony/SubscriptionManager;
.registers 2
monitor-enter p0
:locked
iget-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
if-nez v0, :unlock
new-instance v0, Landroid/telephony/SubscriptionManager;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager;-><init>()V
iput-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
:unlock
monitor-exit p0
return-object v0
:failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:locked .. :unlock} :failed
.end method'
  'getActiveSubscriptionInfoList()Ljava/util/List;': '.method public getActiveSubscriptionInfoList()Ljava/util/List;
.registers 2
const/4 v0, 0x0
return-object v0
.end method'
  'getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;': '.method public getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;
.registers 3
const/4 v0, 0x0
return-object v0
.end method'
  'getPhoneNumber(I)Ljava/lang/String;': '.method public getPhoneNumber(I)Ljava/lang/String;
.registers 4
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "subscription service unavailable."
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
.end method'
  'getPhoneCount()I': '.method public getPhoneCount()I
.registers 2
const/4 v0, 0x0
return v0
.end method'
  'getActiveModemCount()I': '.method public getActiveModemCount()I
.registers 2
const/4 v0, 0x0
return v0
.end method'
  'createForSubscriptionId(I)Landroid/telephony/TelephonyManager;': '.method public createForSubscriptionId(I)Landroid/telephony/TelephonyManager;
.registers 3
new-instance v0, Landroid/telephony/TelephonyManager;
invoke-direct {v0}, Landroid/telephony/TelephonyManager;-><init>()V
iput p1, v0, Landroid/telephony/TelephonyManager;->vinixSubscriptionId:I
return-object v0
.end method'
 }
}

fn subscription_service_members(before string, after string, target string) ! {
 profile := subscription_service_profile()
 allowed := profile.methods[target] or { return error('unexpected subscription target') }
 narrow_member_delta(before, after, allowed, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
 subscription_service_abi(after, target)!
 old_parts := store_parts(before)!
 new_parts := store_parts(after)!
 expected_methods := subscription_service_expected_methods()
 for signature in allowed {
  actual := new_parts.methods[signature]!
  if target == 'android/app/ContextImpl.smali' && signature.starts_with('getSystemService(') {
   old := old_parts.methods[signature]!
   if old.count('.registers 3\n') != 1 || old.contains('vinixSubscription') {
    return error('retained subscription lookup requires original register layout and no preexisting guard')
   }
   expected := old.replace('.registers 3\n', '.registers 3\n' + subscription_service_guard(signature)!)
   if subscription_service_method(actual)! != subscription_service_method(expected)! {
    return error('subscription lookup must add only a shared-cache guard and preserve every fallback instruction')
   }
  } else {
   if subscription_service_method(actual)! != subscription_service_method(expected_methods[signature]!)! {
    return error('subscription service must retain exact explicit monitors, absent-backend results and fresh ID-carrying telephony wrappers')
   }
  }
 }
}

fn subscription_service_instruction_self_test() ! {
 profile := subscription_service_profile()
 expected_methods := subscription_service_expected_methods()
 context := 'android/app/ContextImpl.smali'
 helper := 'vinixSubscriptionService()Landroid/telephony/SubscriptionManager;'
 for target, signatures in profile.methods {
  mut old := '.class public Lexample/Preserved;\n.super Ljava/lang/Object;\n' +
   '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
  if target == context {
   for signature in signatures.filter(it.starts_with('getSystemService(')) {
    old += '.method public ' + signature + '\n.registers 3\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
   }
  }
  mut good := old + (profile.fields[target] or { []string{} }).join('\n') + '\n'
  if target == context {
   for signature in signatures.filter(it.starts_with('getSystemService(')) {
    method := store_parts(old)!.methods[signature]!
    good = good.replace(method, method.replace('.registers 3\n', '.registers 3\n' + subscription_service_guard(signature)!))
   }
  }
  for signature in signatures { if signature in expected_methods { good += expected_methods[signature]! + '\n' } }
  subscription_service_members(old, good, target)!
  if target == context {
   relocated := good.replace('.catchall {:locked .. :unlock} :failed\n', '').replace(':unlock\nmonitor-exit', ':unlock\n.catchall {:locked .. :unlock} :failed\nmonitor-exit')
   subscription_service_members(old, relocated.replace(':locked', ':try_start_1').replace(':unlock', ':goto_finish').replace(':failed', ':catchall_2'), target)!
  }
  mut bad_methods := []string{}
  for signature in signatures {
   method := store_parts(good)!.methods[signature]!
   mut mutations := [method.replace('return-object v0', 'return-object p0'),
    method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('return v0', 'return p0'),
    method.replace('.registers 2', '.registers 3').replace('.registers 3', '.registers 4').replace('.registers 4', '.registers 5')]
   if signature == helper {
    mutations << [method.replace('monitor-enter p0', 'monitor-enter v0'),
     method.replace('monitor-exit p0\nthrow v0', 'throw v0'),
     method.replace('.catchall {:locked .. :unlock} :failed', '.catchall {:unlock .. :failed} :failed'),
     method.replace('iput-object v0, p0', 'iput-object p0, p0')]
   }
   if signature == 'getPhoneNumber(I)Ljava/lang/String;' {
    mutations << [method.replace('IllegalStateException', 'UnsupportedOperationException'),
     method.replace('subscription service unavailable.', 'subscription available.'), method.replace('throw v0', 'return-object v0')]
   }
   if signature.starts_with('createForSubscriptionId(') {
    mutations << [method.replace('iput p1, v0', 'iput p1, p0'), method.replace('return-object v0', 'return-object p0')]
   }
   if signature.starts_with('getSystemService(') {
    mutations << [method.replace('vinixSubscriptionService()', 'vinixDevicePolicy()'),
     method.replace('if-ne p1, v0', 'if-eq p1, v0').replace('if-eqz v0', 'if-nez v0'),
     method.replace('const/4 v0, 0x0\nreturn-object v0', 'const/4 v0, 0x1\nreturn-object v0')]
   }
   for mutation in mutations { if mutation != method { bad_methods << good.replace(method, mutation) } }
  }
  for bad in bad_methods {
   subscription_service_members(old, bad, target) or { continue }
   return error('subscription instruction, exception, monitor, fallback or factory mutation accepted')
  }
 }
}

fn subscription_service_self_test() ! {
 profile := subscription_service_profile()
 context := 'android/app/ContextImpl.smali'
 subscriptions := 'android/telephony/SubscriptionManager.smali'
 telephony := 'android/telephony/TelephonyManager.smali'
 marker := 'android/telephony/SubscriptionInfo.smali'
 if profile.name != 'subscription-service' || profile.baseline_classes != 2109
  || profile.baseline_name != 'combined-account-webview-stats-unavailable-framework-2026-11-02-r1'
  || profile.manifest_pin != 'f0bdf43e99a7ada2b8ec52dde5e8da45ebf6162cd2b8a9a0b32bfc55bfa12106'
  || profile.jar_pin != '86d1cc8dc592082aeb837fd260e36a4a0c93bbe5a23e3f22e4f97b5ba09e7ffd'
  || profile.providers != ['framework_subscription_service.v'] || profile.directory_provider != ''
  || profile.calls != {context: 'framework_subscription_context_source', subscriptions: 'framework_subscription_manager_source', telephony: 'framework_subscription_telephony_source'}
  || profile.methods != subscription_service_methods()
  || profile.changed != {context: 2, subscriptions: 0, telephony: 0}
  || profile.added != {context: 1, subscriptions: 3, telephony: 3}
  || profile.fields != subscription_service_fields()
  || profile.extra_classes != [marker] || profile.class_provider != 'framework_subscription_service_classes' {
  return error('subscription service profile requires exactly three retained classes, seven additions, two replacements, two private fields and one marker')
 }
 subscription_service_instruction_self_test()!
 for target, signatures in profile.methods {
  narrow_method_self_test(signatures, profile.changed[target]!, profile.added[target]!)!
  metadata := '.class public Lexample/Preserved;\n.super Ljava/lang/Object;\n.field private retained:I\n'
  unrelated := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
  mut before := metadata + unrelated
  mut after := metadata + (profile.fields[target] or { []string{} }).join('\n') + '\n' + unrelated
  for index, signature in signatures {
   flags := if signature.starts_with('vinixSubscriptionService(') { 'private' } else { 'public' }
   method := '.method ' + flags + ' ' + signature + '\n.locals 1\nreturn-void\n.end method\n'
   if index < profile.changed[target]! { before += method }
   after += method.replace('.locals 1', '.locals 2')
  }
  narrow_member_delta(before, after, signatures, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
  subscription_service_abi(after, target)!
  for bad in [after.replace('.field private retained:I', '.field public retained:I'), after + '\n.field private extra:I\n', after + unrelated] {
   narrow_member_delta(before, bad, signatures, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} }) or { continue }
   return error('subscription unrelated member/metadata mutation accepted')
  }
  for signature in signatures {
   flags := if signature.starts_with('vinixSubscriptionService(') { 'private' } else { 'public' }
   declaration := '.method ' + flags + ' ' + signature
   for bad_flags in ['public static', 'private native', 'public final', 'private synchronized'] {
    subscription_service_abi(after.replace(declaration, '.method ' + bad_flags + ' ' + signature), target) or { continue }
    return error('subscription visibility/static/native/monitor declaration mutation accepted')
   }
  }
 }
 marker_source := '.class public final Landroid/telephony/SubscriptionInfo;\n.super Ljava/lang/Object;\n'
 subscription_service_type_abi(marker_source)!
 for bad in [marker_source.replace('public final', 'public'), marker_source.replace('Ljava/lang/Object;', 'Ljava/lang/Exception;'),
  marker_source + '.field public subscriptionId:I\n', marker_source + '.implements Ljava/lang/Runnable;\n',
  marker_source + '.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n'] {
  subscription_service_type_abi(bad) or { continue }
  return error('invented subscription marker members or metadata accepted')
 }
 targets := profile.methods.keys()
 mut before := map[string]string{}
 for target in targets { before[target] = 'old' }
 for index in 0 .. 2106 { before['other/' + index.str() + '.smali'] = 'same' }
 mut after := before.clone()
 for target in targets { after[target] = 'new' }
 after[marker] = 'marker'
 narrow_profile_class_delta(before, after, targets, [marker], 2109)!
 for target in [context, subscriptions, telephony, marker, 'other/0.smali'] {
  mut bad := after.clone()
  if target in before { bad[target] = before[target]! } else { bad.delete(target) }
  if target.starts_with('other/') { bad[target] = 'changed' }
  narrow_profile_class_delta(before, bad, targets, [marker], 2109) or { continue }
  return error('subscription service class scope mutation accepted')
 }
}

fn autofill_service_profile() NarrowProfile {
 manager := 'android/view/autofill/AutofillManager.smali'
 return NarrowProfile{
  name: 'autofill-service'
  baseline_name: 'combined-account-webview-subscription-service-framework-2026-11-02-r1'
  manifest_pin: '958e5a7c02710a3aa78a04b499f6c6d5ca4701e1c2c8d33b7dda6f640ac561db'
  jar_pin: '72c57e05b4458d8c62f82cd29fe70065318303af6b741bf1726337ce922c60ef'
  baseline_classes: 2110
  providers: ['framework_autofill_service.v']
  calls: {manager: 'framework_autofill_service_source'}
  methods: {manager: ['getAutofillServiceComponentName()Landroid/content/ComponentName;']}
  changed: {manager: 0}
  added: {manager: 1}
 }
}

fn autofill_service_abi(source string) ! {
 signature := 'getAutofillServiceComponentName()Landroid/content/ComponentName;'
 method := store_parts(source)!.methods[signature] or { return error('missing autofill service component query') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public ' + signature, '.registers 2', 'const/4 v0, 0x0', 'return-object v0', '.end method'] {
  return error('autofill component query requires the exact public instance null result for the absent backend')
 }
}

fn autofill_service_self_test() ! {
 profile := autofill_service_profile()
 manager := 'android/view/autofill/AutofillManager.smali'
 signature := 'getAutofillServiceComponentName()Landroid/content/ComponentName;'
 if profile.name != 'autofill-service' || profile.baseline_classes != 2110
  || profile.baseline_name != 'combined-account-webview-subscription-service-framework-2026-11-02-r1'
  || profile.manifest_pin != '958e5a7c02710a3aa78a04b499f6c6d5ca4701e1c2c8d33b7dda6f640ac561db'
  || profile.jar_pin != '72c57e05b4458d8c62f82cd29fe70065318303af6b741bf1726337ce922c60ef'
  || profile.providers != ['framework_autofill_service.v']
  || profile.calls != {manager: 'framework_autofill_service_source'}
  || profile.methods != {manager: [signature]} || profile.changed != {manager: 0}
  || profile.added != {manager: 1} || profile.fields.len != 0 || profile.directory_provider != ''
  || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('autofill service profile requires exactly one added query in one retained class')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := '.method public ' + signature + '\n.registers 2\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
 autofill_service_abi(method)!
 for bad in [method.replace('public ', 'private '), method.replace('public ', 'public static '),
  method.replace('public ', 'public native '), method.replace('public ', 'public final '),
  method.replace('()', '(I)'), method.replace('.registers 2', '.registers 3'),
  method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('return-object v0', 'return v0'),
  method.replace('return-object v0', 'return-object p0'),
  method.replace('return-object v0', 'return-object v0\nreturn-object v0'), method + method] {
  autofill_service_abi(bad) or { continue }
  return error('autofill component query ABI/register/result/body mutation accepted')
 }
 metadata := '.class public Landroid/view/autofill/AutofillManager;\n.super Ljava/lang/Object;\n'
 retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 before_source := metadata + retained
 after_source := before_source + method
 narrow_member_delta(before_source, after_source, [signature], 0, 1, []string{})!
 for bad in [after_source.replace('public retained()V', 'private retained()V'),
  after_source.replace('.super Ljava/lang/Object;', '.super Lother/Base;'),
  after_source + '.field private unexpected:I\n', after_source + retained] {
  narrow_member_delta(before_source, bad, [signature], 0, 1, []string{}) or { continue }
  return error('autofill unrelated member or metadata mutation accepted')
 }
 mut before := {manager: 'old'}
 for i in 0 .. 2109 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[manager] = 'new'
 narrow_profile_class_delta(before, after, [manager], []string{}, 2110)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[manager] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(manager) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(manager); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [manager], []string{}, 2110) or { continue }
  return error('invalid AutofillManager-only class scope accepted')
 }
}

fn keyguard_policy_profile() NarrowProfile {
 policy := 'android/app/admin/DevicePolicyManager.smali'
 return NarrowProfile{
  name: 'keyguard-policy'
  baseline_name: 'combined-account-webview-autofill-service-framework-2026-11-02-r1'
  manifest_pin: 'df8ec5e67f683f78dd5aca9b42291f4ebcd3638342d8e3a215dbfc42d60c3533'
  jar_pin: 'e2bea62dcd6f59269c36612f76b806942018700f37fbf202915cc2e74329a54a'
  baseline_classes: 2110
  providers: ['framework_keyguard_policy.v']
  calls: {policy: 'framework_keyguard_policy_source'}
  methods: {policy: ['getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I']}
  changed: {policy: 0}
  added: {policy: 1}
 }
}

fn keyguard_policy_abi(source string) ! {
 signature := 'getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I'
 method := store_parts(source)!.methods[signature] or { return error('missing keyguard policy query') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public ' + signature, '.registers 3', 'const/4 v0, 0x0', 'return v0', '.end method'] {
  return error('keyguard policy query requires the exact public instance zero result for the absent backend')
 }
}

fn keyguard_policy_self_test() ! {
 profile := keyguard_policy_profile()
 policy := 'android/app/admin/DevicePolicyManager.smali'
 signature := 'getKeyguardDisabledFeatures(Landroid/content/ComponentName;)I'
 if profile.name != 'keyguard-policy' || profile.baseline_classes != 2110
  || profile.baseline_name != 'combined-account-webview-autofill-service-framework-2026-11-02-r1'
  || profile.manifest_pin != 'df8ec5e67f683f78dd5aca9b42291f4ebcd3638342d8e3a215dbfc42d60c3533'
  || profile.jar_pin != 'e2bea62dcd6f59269c36612f76b806942018700f37fbf202915cc2e74329a54a'
  || profile.providers != ['framework_keyguard_policy.v']
  || profile.calls != {policy: 'framework_keyguard_policy_source'}
  || profile.methods != {policy: [signature]} || profile.changed != {policy: 0}
  || profile.added != {policy: 1} || profile.fields.len != 0 || profile.directory_provider != ''
  || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('keyguard policy profile requires exactly one added query in one retained class')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := '.method public ' + signature + '\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
 keyguard_policy_abi(method)!
 for bad in [method.replace('public ', 'private '), method.replace('public ', 'public static '),
  method.replace('public ', 'public native '), method.replace('public ', 'public final '),
  method.replace('(Landroid/content/ComponentName;)I', '()I'), method.replace('.registers 3', '.registers 2'),
  method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('return v0', 'return-object v0'),
  method.replace('return v0', 'return p1'), method.replace('return v0', 'return v0\nreturn v0'), method + method] {
  keyguard_policy_abi(bad) or { continue }
  return error('keyguard policy query ABI/register/result/body mutation accepted')
 }
 metadata := '.class public Landroid/app/admin/DevicePolicyManager;\n.super Ljava/lang/Object;\n'
 retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 before_source := metadata + retained
 after_source := before_source + method
 narrow_member_delta(before_source, after_source, [signature], 0, 1, []string{})!
 for bad in [after_source.replace('public retained()V', 'private retained()V'),
  after_source.replace('.super Ljava/lang/Object;', '.super Lother/Base;'),
  after_source + '.field private unexpected:I\n', after_source + retained] {
  narrow_member_delta(before_source, bad, [signature], 0, 1, []string{}) or { continue }
  return error('keyguard policy unrelated member or metadata mutation accepted')
 }
 mut before := {policy: 'old'}
 for i in 0 .. 2109 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[policy] = 'new'
 narrow_profile_class_delta(before, after, [policy], []string{}, 2110)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[policy] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(policy) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(policy); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [policy], []string{}, 2110) or { continue }
  return error('invalid DevicePolicyManager-only class scope accepted')
 }
}

fn broadcast_permission_profile() NarrowProfile {
 context := 'android/content/Context.smali'
 loaded := 'android/atl/ATLLoadedApp.smali'
 return NarrowProfile{
  name: 'broadcast-permission'
  baseline_name: 'combined-account-webview-keyguard-policy-framework-2026-11-02-r1'
  manifest_pin: '13ef4747529ec6d0d3669a3ad059e6eee82bf99b80900b835b7de2d40a007a92'
  jar_pin: '1ff4080bbfdc95c4c370e88b3b283f004f165f4a93c816e224d823e98f7dc4b4'
  baseline_classes: 2110
  providers: ['framework_broadcast_permission.v']
  calls: {context: 'framework_broadcast_permission_context_source', loaded: 'framework_broadcast_permission_loaded_source'}
  methods: {
   context: ['sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V']
   loaded: ['<init>(Landroid/content/res/Resources;Ljava/lang/ClassLoader;Landroid/content/pm/PackageParser$Package;)V',
    'vinixHasBroadcastPermission(Ljava/lang/String;)Z']
  }
  changed: {context: 0, loaded: 1}
  added: {context: 1, loaded: 1}
  fields: {loaded: ['.field private final vinixBroadcastPermissions:Ljava/util/Set;']}
  class_provider: 'framework_broadcast_permission_classes'
  extra_classes: ['android/atl/VinixBroadcastPolicy.smali']
 }
}

fn broadcast_permission_expected_methods() map[string]string {
 return {
  'sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V': '.method public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
.registers 3
invoke-static {p0, p1, p2}, Landroid/atl/VinixBroadcastPolicy;->send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V
return-void
.end method'
  'vinixHasBroadcastPermission(Ljava/lang/String;)Z': '.method public final vinixHasBroadcastPermission(Ljava/lang/String;)Z
.registers 3
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;
invoke-interface {v0, p1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z
move-result v0
return v0
.end method'
  'snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;': '.method public static snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;
.registers 12
new-instance v0, Ljava/util/HashSet;
invoke-direct {v0}, Ljava/util/HashSet;-><init>()V
if-eqz p0, :freeze
iget-object v1, p0, Landroid/content/pm/PackageParser$Package;->vinixSigningInfo:Landroid/content/pm/SigningInfo;
if-eqz v1, :freeze
invoke-virtual {v1}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v1
if-eqz v1, :freeze
array-length v2, v1
if-lez v2, :freeze
const/4 v3, 0x0
:signers
if-ge v3, v2, :metadata
aget-object v4, v1, v3
if-eqz v4, :freeze
add-int/lit8 v3, v3, 0x1
goto :signers
:metadata
iget-object v2, p0, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
if-eqz v2, :freeze
invoke-virtual {v2}, Ljava/lang/String;->length()I
move-result v1
if-lez v1, :freeze
iget-object v3, p0, Landroid/content/pm/PackageParser$Package;->requestedPermissions:Ljava/util/ArrayList;
if-eqz v3, :freeze
iget-object v4, p0, Landroid/content/pm/PackageParser$Package;->permissions:Ljava/util/ArrayList;
if-eqz v4, :freeze
invoke-virtual {v4}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v4
new-instance v5, Ljava/util/HashSet;
invoke-direct {v5}, Ljava/util/HashSet;-><init>()V
:next
invoke-interface {v4}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :freeze
invoke-interface {v4}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v6
if-eqz v6, :next
check-cast v6, Landroid/content/pm/PackageParser$Permission;
iget-object v7, v6, Landroid/content/pm/PackageParser$Permission;->info:Landroid/content/pm/PermissionInfo;
if-eqz v7, :next
iget-object v8, v7, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
if-eqz v8, :next
invoke-virtual {v8}, Ljava/lang/String;->length()I
move-result v1
if-lez v1, :next
invoke-virtual {v5, v8}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :unique
invoke-virtual {v0, v8}, Ljava/util/HashSet;->remove(Ljava/lang/Object;)Z
goto :next
:unique
iget-boolean v1, v6, Landroid/content/pm/PackageParser$Permission;->tree:Z
if-nez v1, :next
iget-object v9, v7, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v2, v9}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :next
iget v9, v7, Landroid/content/pm/PermissionInfo;->protectionLevel:I
and-int/lit8 v9, v9, 0xf
const/4 v1, 0x2
if-ne v9, v1, :next
invoke-virtual {v3, v8}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :next
invoke-virtual {v0, v8}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z
goto :next
:freeze
invoke-static {v0}, Ljava/util/Collections;->unmodifiableSet(Ljava/util/Set;)Ljava/util/Set;
move-result-object v0
return-object v0
.end method'
  'send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V': '.method public static send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V
.registers 4
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
if-eqz p2, :deliver
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v0
invoke-virtual {v0, p2}, Landroid/atl/ATLLoadedApp;->vinixHasBroadcastPermission(Ljava/lang/String;)Z
move-result v0
if-nez v0, :deliver
return-void
:deliver
invoke-virtual {p0, p1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
return-void
.end method'
 }
}

fn broadcast_permission_members(before string, after string, target string) ! {
 previous := store_parts(before)!
 updated := store_parts(after)!
 expected := broadcast_permission_expected_methods()
 signatures := broadcast_permission_profile().methods[target] or { return error('unsupported broadcast permission target') }
 for signature in signatures {
  method := updated.methods[signature] or { return error('required broadcast permission member absent') }
  if signature.starts_with('<init>(') {
   old := previous.methods[signature] or { return error('original loaded application constructor absent') }
   normalized_old := intent_extras_method(old)!
   anchor := 'iput-object p3, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;'
   inserted := '\ninvoke-static {p3}, Landroid/atl/VinixBroadcastPolicy;->snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;\nmove-result-object v0\niput-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;'
   if !normalized_old.starts_with('.method constructor ' + signature + '\n.registers 6\n')
    || normalized_old.count(anchor) != 1 || normalized_old.contains('vinixBroadcast')
    || intent_extras_method(method)! != normalized_old.replace(anchor, anchor + inserted) {
    return error('loaded constructor must preserve every old instruction and snapshot exactly after the unpublished package assignment')
   }
  } else if intent_extras_method(method)! != intent_extras_method(expected[signature]!)! {
   return error('broadcast permission member must preserve its exact validated forwarding or private snapshot lookup')
  }
 }
 if target == 'android/content/Context.smali'
  && (updated.methods['sendBroadcast(Landroid/content/Intent;)V'] or { '' }) !=
   (previous.methods['sendBroadcast(Landroid/content/Intent;)V'] or { '' }) {
  return error('original native broadcast declaration must remain unchanged')
 }
}

fn broadcast_permission_helper_abi(source string) ! {
 parts := store_parts(source)!
 expected := broadcast_permission_expected_methods()
 signatures := ['snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;',
  'send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V']
 if parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public final Landroid/atl/VinixBroadcastPolicy;', '.super Ljava/lang/Object;']
  || parts.methods.keys().sorted() != signatures.sorted() {
  return error('broadcast policy requires one fieldless utility with exactly snapshot and send, without constructors or ambient grant state')
 }
 for signature in signatures {
  if intent_extras_method(parts.methods[signature]!)! != intent_extras_method(expected[signature]!)! {
   return error('broadcast policy requires exact authenticated immutable permission snapshot and deny-before-delivery flow')
  }
 }
}

fn broadcast_permission_self_test() ! {
 profile := broadcast_permission_profile()
 context := 'android/content/Context.smali'
 loaded := 'android/atl/ATLLoadedApp.smali'
 helper := 'android/atl/VinixBroadcastPolicy.smali'
 signatures := profile.methods[loaded]!
 if profile.name != 'broadcast-permission' || profile.baseline_classes != 2110
  || profile.baseline_name != 'combined-account-webview-keyguard-policy-framework-2026-11-02-r1'
  || profile.manifest_pin != '13ef4747529ec6d0d3669a3ad059e6eee82bf99b80900b835b7de2d40a007a92'
  || profile.jar_pin != '1ff4080bbfdc95c4c370e88b3b283f004f165f4a93c816e224d823e98f7dc4b4'
  || profile.providers != ['framework_broadcast_permission.v'] || profile.directory_provider != ''
  || profile.calls != {context: 'framework_broadcast_permission_context_source', loaded: 'framework_broadcast_permission_loaded_source'}
  || profile.methods != {context: ['sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V'],
   loaded: ['<init>(Landroid/content/res/Resources;Ljava/lang/ClassLoader;Landroid/content/pm/PackageParser$Package;)V', 'vinixHasBroadcastPermission(Ljava/lang/String;)Z']}
  || profile.changed != {context: 0, loaded: 1} || profile.added != {context: 1, loaded: 1}
  || profile.fields != {loaded: ['.field private final vinixBroadcastPermissions:Ljava/util/Set;']}
  || profile.class_provider != 'framework_broadcast_permission_classes' || profile.extra_classes != [helper] {
  return error('broadcast permission profile requires exactly two retained classes, one constructor change, two method additions, one private final field and one policy utility')
 }
 for target, allowed in profile.methods { narrow_method_self_test(allowed, profile.changed[target]!, profile.added[target]!)! }
 expected := broadcast_permission_expected_methods()
 ctor := '.method constructor ' + signatures[0] + '\n.registers 6\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p3, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;\niget-object v0, p3, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;\nreturn-void\n.end method'
 insertion := '\ninvoke-static {p3}, Landroid/atl/VinixBroadcastPolicy;->snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;\nmove-result-object v0\niput-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;'
 anchor := 'iput-object p3, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;'
 patched_ctor := ctor.replace(anchor, anchor + insertion)
 loaded_after := patched_ctor + '\n' + expected[signatures[1]]!
 broadcast_permission_members(ctor, loaded_after, loaded)!
 for bad in [loaded_after.replace('.registers 6', '.registers 7'), loaded_after.replace('{p3}, Landroid/atl/VinixBroadcastPolicy;', '{p0}, Landroid/atl/VinixBroadcastPolicy;'),
  loaded_after.replace(anchor + insertion, insertion.trim_left('\n') + '\n' + anchor),
  loaded_after.replace('->pkg:Landroid/content/pm/PackageParser$Package;', '->other:Landroid/content/pm/PackageParser$Package;'),
  loaded_after.replace('iget-object v0, p3', 'iget-object v1, p3'),
  loaded_after.replace('return v0', 'const/4 v0, 0x1\nreturn v0')] {
  broadcast_permission_members(ctor, bad, loaded) or { continue }
  return error('broadcast constructor publication/order/register/old-body or lookup mutation accepted')
 }
 loaded_metadata := '.class public final Landroid/atl/ATLLoadedApp;\n.super Ljava/lang/Object;\n'
 field := profile.fields[loaded]![0]
 loaded_with_field := loaded_metadata + field + '\n' + loaded_after
 narrow_member_delta(loaded_metadata + ctor, loaded_with_field, signatures, 1, 1, [field])!
 for bad in [loaded_with_field.replace(field, field.replace('private final', 'public final')),
  loaded_with_field.replace(field, field.replace('private final', 'private')),
  loaded_with_field.replace(field, field.replace('Ljava/util/Set;', 'Ljava/util/HashSet;')),
  loaded_with_field + field + '\n', loaded_with_field + '.field private extra:I\n'] {
  narrow_member_delta(loaded_metadata + ctor, bad, signatures, 1, 1, [field]) or { continue }
  return error('broadcast snapshot field access/finality/type or metadata mutation accepted')
 }
 native := '.method public native sendBroadcast(Landroid/content/Intent;)V\n.end method'
 context_after := native + '\n' + expected[profile.methods[context]![0]]!
 broadcast_permission_members(native, context_after, context)!
 for bad in [context_after.replace('{p0, p1, p2}', '{p0, p2, p1}'), context_after.replace('public native sendBroadcast', 'public sendBroadcast'),
  context_after.replace('public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)', 'public static sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)')] {
  broadcast_permission_members(native, bad, context) or { continue }
  return error('broadcast Context parameter forwarding or retained native ABI mutation accepted')
 }
 snapshot := expected['snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;']!
 send := expected['send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V']!
 metadata := '.class public final Landroid/atl/VinixBroadcastPolicy;\n.super Ljava/lang/Object;\n'
 policy := metadata + snapshot + '\n' + send
 broadcast_permission_helper_abi(policy)!
 broadcast_permission_helper_abi(policy.replace(':freeze', ':alias_freeze').replace(':next', ':alias_next').replace(':deliver', ':alias_deliver'))!
 for bad in [policy.replace('if-eqz v1, :freeze', 'if-nez v1, :freeze'),
  policy.replace('if-lez v2, :freeze', 'if-ltz v2, :freeze'), policy.replace('if-eqz v4, :freeze', 'if-nez v4, :freeze'),
  policy.replace('if-nez v1, :unique', 'if-eqz v1, :unique'), policy.replace('->remove(Ljava/lang/Object;)Z', '->add(Ljava/lang/Object;)Z'),
  policy.replace('if-nez v1, :next', 'if-eqz v1, :next'), policy.replace('if-eqz v1, :next', 'if-nez v1, :next'),
  policy.replace('and-int/lit8 v9, v9, 0xf', 'and-int/lit8 v9, v9, 0x0'), policy.replace('const/4 v1, 0x2', 'const/4 v1, 0x0'),
  policy.replace('->requestedPermissions:Ljava/util/ArrayList;', '->permissions:Ljava/util/ArrayList;'),
  policy.replace('->unmodifiableSet(Ljava/util/Set;)Ljava/util/Set;', '->emptySet()Ljava/util/Set;'),
  policy.replace('->getPrimaryApplication()', '->getSystemApplication()'), policy.replace('if-nez v0, :deliver', 'if-eqz v0, :deliver'),
  policy.replace('invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;', ''),
  policy.replace('.class public final ', '.class public '), policy + '.field public static grants:Ljava/util/Set;\n', policy + send] {
  broadcast_permission_helper_abi(bad) or { continue }
  return error('broadcast policy authentication/duplicates/owner/signature/requested/freeze/primary/gate/null/utility-state mutation accepted')
 }
 mut before := {context: 'context-old', loaded: 'loaded-old'}
 for index in 0 .. 2108 { before['other/' + index.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[context] = 'context-new'
 after[loaded] = 'loaded-new'
 after[helper] = 'policy'
 narrow_profile_class_delta(before, after, [context, loaded], [helper], 2110)!
 for target in [context, loaded, helper, 'other/0.smali'] {
  mut bad := after.clone()
  if target in before { bad[target] = before[target]! } else { bad.delete(target) }
  if target.starts_with('other/') { bad[target] = 'changed' }
  narrow_profile_class_delta(before, bad, [context, loaded], [helper], 2110) or { continue }
  return error('broadcast permission exact three-class scope mutation accepted')
 }
}

fn secure_settings_profile() NarrowProfile {
 secure := 'android/provider/Settings$Secure.smali'
 return NarrowProfile{
  name: 'secure-settings'
  baseline_name: 'combined-account-webview-broadcast-permission-framework-2026-11-02-r1'
  manifest_pin: '49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5'
  jar_pin: '9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9'
  baseline_classes: 2111
  providers: ['framework_settings_secure.v', 'framework_quick_settings.v']
  calls: {secure: 'framework_settings_secure_source'}
  methods: {secure: ['putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z']}
  changed: {secure: 0}
  added: {secure: 1}
  class_provider: 'framework_quick_settings_classes'
  extra_classes: ['android/service/quicksettings/TileService.smali']
 }
}

fn secure_settings_expected_method() string {
 return '.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
.registers 6
new-instance v0, Landroid/content/ContentValues;
invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
const-string v1, "name"
invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
sget-object v2, Landroid/provider/Settings$Secure;->CONTENT_URI:Landroid/net/Uri;
:try_start
invoke-virtual {p0, v2, v0}, Landroid/content/ContentResolver;->insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
move-result-object v0
:try_end
if-eqz v0, :failed
const/4 v0, 0x1
return v0
:database_error
move-exception v0
:failed
const/4 v0, 0x0
return v0
.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error
.end method'
}

// DEX may move the catch directive beside the try-end label. Rebase its span
// and handler to instruction positions while preserving type and all code.
fn secure_settings_method(source string) !string {
 mut code := []string{}
 mut catches := []string{}
 for original in source.split_into_lines() {
  line := original.trim_space()
  if line.starts_with('.catch ') { catches << line.replace('{:', '{ :').replace('}', ' }') }
  else if line != '.end method' { code << line }
 }
 code << catches
 code << '.end method'
 return intent_extras_method(code.join('\n'))!
}

fn secure_settings_abi(source string) ! {
 signature := 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
 method := store_parts(source)!.methods[signature] or { return error('secure settings string writer missing') }
 if secure_settings_method(method)! != secure_settings_method(secure_settings_expected_method())! {
  return error('secure settings writer requires exact nullable name/value forwarding, secure URI, real insert result and SQLException-only failure')
 }
}

fn secure_settings_tile_methods() map[string]string {
 return {
  '<init>()V': '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void\n.end method'
  'onBind(Landroid/content/Intent;)Landroid/os/IBinder;': '.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;\n.registers 3\nconst/4 v0, 0x0\nreturn-object v0\n.end method'
  'requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V': '.method public static final requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V
.registers 4
new-instance v0, Landroid/content/Intent;
const-string v1, "android.service.quicksettings.action.REQUEST_LISTENING"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v1, "android.intent.extra.COMPONENT_NAME"
invoke-virtual {v0, v1, p1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;
const-string v1, "com.android.systemui"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "android.permission.BIND_QUICK_SETTINGS_TILE"
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
return-void
.end method'
 }
}

fn secure_settings_tile_abi(source string) ! {
 parts := store_parts(source)!
 expected := secure_settings_tile_methods()
 if parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public Landroid/service/quicksettings/TileService;', '.super Landroid/app/Service;']
  || parts.methods.keys().sorted() != expected.keys().sorted() {
  return error('TileService requires a fieldless concrete Service with exactly constructor, unavailable binder and API-28 request delegation')
 }
 for signature, method in expected {
  if intent_extras_method(parts.methods[signature]!)! != intent_extras_method(method)! {
   return error('TileService must preserve exact API-28 intent/component/package/permission forwarding without invented status-bar or callback behavior')
  }
 }
}

fn secure_settings_self_test() ! {
 profile := secure_settings_profile()
 secure := 'android/provider/Settings$Secure.smali'
 signature := 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
 if profile.name != 'secure-settings' || profile.baseline_classes != 2111
  || profile.baseline_name != 'combined-account-webview-broadcast-permission-framework-2026-11-02-r1'
  || profile.manifest_pin != '49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5'
  || profile.jar_pin != '9e998094f8e122c22195e0c9a8f79377dbf16cd04d321ab4d1a47650908082f9'
  || profile.providers != ['framework_settings_secure.v', 'framework_quick_settings.v'] || profile.directory_provider != ''
  || profile.calls != {secure: 'framework_settings_secure_source'} || profile.methods != {secure: [signature]}
  || profile.changed != {secure: 0} || profile.added != {secure: 1} || profile.fields.len != 0
  || profile.class_provider != 'framework_quick_settings_classes'
  || profile.extra_classes != ['android/service/quicksettings/TileService.smali'] {
  return error('API-28 secure settings profile requires one added writer and one concrete TileService, without unrelated user or status-bar changes')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := secure_settings_expected_method()
 secure_settings_abi(method)!
 secure_settings_abi(method.replace(':try_start', ':start_alias').replace(':try_end', ':end_alias').replace(':database_error', ':handler_alias').replace(':failed', ':failure_alias'))!
 moved_catch := method.replace('.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error\n', '')
  .replace(':try_end\n', ':try_end\n.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error\n')
 secure_settings_abi(moved_catch)!
 for bad in [method.replace('public static ', 'public '), method.replace('public static ', 'private static '),
  method.replace('public static ', 'public static native '), method.replace('.registers 6', '.registers 7'),
  method.replace('"name"', '"key"'), method.replace('"value"', '"entry"'),
  method.replace('{v0, v1, p1}', '{v0, v1, p2}'), method.replace('{v0, v1, p2}', '{v0, v1, p1}'),
  method.replace('Settings$Secure;->CONTENT_URI', 'Settings$Global;->CONTENT_URI'),
  method.replace('{p0, v2, v0}', '{p0, v0, v2}'), method.replace('if-eqz v0, :failed', 'if-nez v0, :failed'),
  method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('const/4 v0, 0x1', 'const/4 v0, 0x0'),
  method.replace('Landroid/database/SQLException;', 'Ljava/lang/RuntimeException;'),
  method.replace('{:try_start .. :try_end}', '{:try_start .. :database_error}'),
  method.replace('} :database_error', '} :failed'), method.replace('return v0', 'return-object v0'), method + method] {
  secure_settings_abi(bad) or { continue }
  return error('secure settings visibility/register/values/namespace/result/catch-scope mutation accepted')
 }
 metadata := '.class public final Landroid/provider/Settings$Secure;\n.super Landroid/provider/Settings$NameValueTable;\n'
 retained := '.method public static retained()V\n.locals 0\nreturn-void\n.end method\n'
 before_source := metadata + retained
 after_source := before_source + method
 narrow_member_delta(before_source, after_source, [signature], 0, 1, []string{})!
 for bad in [after_source.replace('public static retained()V', 'private static retained()V'),
  after_source.replace('.super Landroid/provider/Settings$NameValueTable;', '.super Ljava/lang/Object;'),
  after_source + '\n.field private cache:Ljava/util/Map;\n', after_source + '\n' + retained] {
  narrow_member_delta(before_source, bad, [signature], 0, 1, []string{}) or { continue }
  return error('secure settings unrelated method, metadata or invented cache accepted')
 }
 mut before := {secure: 'old'}
 for index in 0 .. 2110 { before['other/' + index.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[secure] = 'new'
 tile := profile.extra_classes[0]
 after[tile] = 'tile'
 narrow_profile_class_delta(before, after, [secure], [tile], 2111)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[secure] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(secure) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(secure); bad['substitution.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [secure], [tile], 2111) or { continue }
  return error('invalid Settings.Secure plus TileService class scope accepted')
 }
 mut missing_tile := after.clone()
 missing_tile.delete(tile)
 narrow_profile_class_delta(before, missing_tile, [secure], [tile], 2111) or {
  secure_settings_tile_self_test()!
  return
 }
 return error('missing TileService accepted')
}

fn secure_settings_tile_self_test() ! {
 expected := secure_settings_tile_methods()
 metadata := '.class public Landroid/service/quicksettings/TileService;\n.super Landroid/app/Service;\n'
 tile := metadata + expected.values().join('\n')
 secure_settings_tile_abi(tile)!
 for bad in [tile.replace('.class public ', '.class public abstract '), tile.replace('Landroid/app/Service;', 'Ljava/lang/Object;'),
  tile + '\n.field private tile:Ljava/lang/Object;\n', tile + '\n.method public onStartListening()V\n.registers 1\nreturn-void\n.end method\n',
  tile.replace('public static final requestListeningState', 'public static requestListeningState'),
  tile.replace('public static final requestListeningState', 'public final requestListeningState'),
  tile.replace('.registers 4', '.registers 3'), tile.replace('REQUEST_LISTENING', 'QS_TILE'),
  tile.replace('android.intent.extra.COMPONENT_NAME', 'android.intent.extra.COMPONENT'),
  tile.replace('putExtra(Ljava/lang/String;Landroid/os/Parcelable;)', 'putExtra(Ljava/lang/String;Ljava/lang/String;)'),
  tile.replace('{v0, v1, p1}', '{v0, v1, p0}'), tile.replace('com.android.systemui', 'com.google.android.gms'),
  tile.replace('android.permission.BIND_QUICK_SETTINGS_TILE', 'android.permission.BIND_JOB_SERVICE'),
  tile.replace('{p0, v0, v1}', '{p0, v1, v0}'), tile.replace('sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)', 'sendBroadcast(Landroid/content/Intent;)'),
  tile.replace('const/4 v0, 0x0\nreturn-object v0', 'return-object p0'),
  tile.replace('return-void\n.end method', 'return-void\nreturn-void\n.end method')] {
  secure_settings_tile_abi(bad) or { continue }
  return error('TileService class/state/dispatch/signature/intent/component/package/permission/binder mutation accepted')
 }
}

fn usage_inactive_profile() NarrowProfile {
 usage := 'android/app/usage/UsageStatsManager.smali'
 return NarrowProfile{
  name: 'usage-inactive'
  baseline_name: 'combined-account-webview-secure-settings-framework-2026-11-02-r1'
  manifest_pin: '0c7485f9a38c52dd6ef6ddd60c936f49d694da267ae30fccf6dea1163a21529b'
  jar_pin: 'f7eef1e9b2a2a7730ce0b024823c9cc38dc1d510252dc6dccd30f1ada79f9768'
  baseline_classes: 2112
  providers: ['framework_usage_inactive.v']
  calls: {usage: 'framework_usage_inactive_source'}
  methods: {usage: ['isAppInactive(Ljava/lang/String;)Z']}
  changed: {usage: 0}
  added: {usage: 1}
 }
}

fn usage_inactive_abi(source string) ! {
 signature := 'isAppInactive(Ljava/lang/String;)Z'
 method := store_parts(source)!.methods[signature] or { return error('usage inactivity query missing') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public ' + signature, '.registers 3', 'const/4 v0, 0x0', 'return v0', '.end method'] {
  return error('disabled AppStandby query requires the exact public instance false result before any package lookup or validation')
 }
}

fn usage_inactive_self_test() ! {
 profile := usage_inactive_profile()
 usage := 'android/app/usage/UsageStatsManager.smali'
 signature := 'isAppInactive(Ljava/lang/String;)Z'
 if profile.name != 'usage-inactive' || profile.baseline_classes != 2112
  || profile.baseline_name != 'combined-account-webview-secure-settings-framework-2026-11-02-r1'
  || profile.manifest_pin != '0c7485f9a38c52dd6ef6ddd60c936f49d694da267ae30fccf6dea1163a21529b'
  || profile.jar_pin != 'f7eef1e9b2a2a7730ce0b024823c9cc38dc1d510252dc6dccd30f1ada79f9768'
  || profile.providers != ['framework_usage_inactive.v'] || profile.directory_provider != ''
  || profile.calls != {usage: 'framework_usage_inactive_source'} || profile.methods != {usage: [signature]}
  || profile.changed != {usage: 0} || profile.added != {usage: 1} || profile.fields.len != 0
  || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('usage inactivity profile requires exactly one added query in the retained constructor-only manager')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := '.method public ' + signature + '\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
 usage_inactive_abi(method)!
 for bad in [method.replace('public ', 'private '), method.replace('public ', 'public static '),
  method.replace('public ', 'public native '), method.replace('public ', 'public final '),
  method.replace('(Ljava/lang/String;)Z', '()Z'), method.replace('.registers 3', '.registers 2'),
  method.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'), method.replace('return v0', 'return-object v0'),
  method.replace('return v0', 'return p1'), method.replace('const/4 v0, 0x0', 'invoke-virtual {p1}, Ljava/lang/String;->length()I\nmove-result v0'),
  method + method] {
  usage_inactive_abi(bad) or { continue }
  return error('usage inactivity ABI/register/package-dependence/result mutation accepted')
 }
 metadata := '.class public Landroid/app/usage/UsageStatsManager;\n.super Ljava/lang/Object;\n'
 constructor := '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
 before_source := metadata + constructor
 after_source := before_source + method
 narrow_member_delta(before_source, after_source, [signature], 0, 1, []string{})!
 for bad in [after_source.replace('public constructor <init>()V', 'private constructor <init>()V'),
  after_source.replace('.super Ljava/lang/Object;', '.super Lother/Base;'),
  after_source + '.field private history:Ljava/util/Map;\n', after_source + constructor] {
  narrow_member_delta(before_source, bad, [signature], 0, 1, []string{}) or { continue }
  return error('usage inactivity constructor/metadata or invented history state accepted')
 }
 mut before := {usage: 'old'}
 for index in 0 .. 2111 { before['other/' + index.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[usage] = 'new'
 narrow_profile_class_delta(before, after, [usage], []string{}, 2112)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[usage] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(usage) }
   3 { bad['unrelated.smali'] = 'new' }
   else { bad.delete(usage); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [usage], []string{}, 2112) or { continue }
  return error('invalid UsageStatsManager-only class scope accepted')
 }
}

fn messenger_binder_profile() NarrowProfile {
 handler := 'android/os/Handler\$MessengerImpl.smali'
 iface := 'android/os/IMessenger.smali'
 message := 'android/os/Message.smali'
 creator := 'android/os/Messenger\$1.smali'
 messenger := 'android/os/Messenger.smali'
 return NarrowProfile{
  name: 'messenger-binder'
  baseline_name: 'combined-account-webview-usage-inactive-framework-2026-11-02-r1'
  manifest_pin: 'bfadac214671937539a4732b3ca6be22d561c366b96a72a9de045fc362aba1fe'
  jar_pin: 'd7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b'
  baseline_classes: 2112
  providers: ['framework_messenger.v', 'framework_message_parcel.v']
  calls: {handler: 'framework_handler_messenger_source', iface: 'framework_imessenger_source',
   message: 'framework_message_parcel_source', creator: 'framework_messenger_creator_source',
   messenger: 'framework_messenger_source'}
  methods: {handler: ['<init>(Landroid/os/Handler;)V', 'send(Landroid/os/Message;)V'],
   iface: []string{}, message: ['<clinit>()V', '<init>()V', 'clearForRecycle()V',
    'copyFrom(Landroid/os/Message;)V', 'obtain(Landroid/os/Message;)Landroid/os/Message;',
    'writeToParcel(Landroid/os/Parcel;I)V'],
   creator: ['<init>()V', 'createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;',
    'createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'newArray(I)[Landroid/os/Messenger;', 'newArray(I)[Ljava/lang/Object;'],
   messenger: ['<init>(Landroid/os/IBinder;)V', 'equals(Ljava/lang/Object;)Z',
    'getBinder()Landroid/os/IBinder;', 'hashCode()I', '<clinit>()V', 'writeToParcel(Landroid/os/Parcel;I)V',
    'readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;',
    'writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V']}
  changed: {handler: 2, iface: 0, message: 5, creator: 0, messenger: 4}
  added: {handler: 0, iface: 0, message: 1, creator: 5, messenger: 4}
  removed_methods: {handler: 0, iface: 0, message: 0, creator: 2, messenger: 0}
  fields: {messenger: ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;'],
   message: ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;', '.field public sendingUid:I']}
  removed_fields: {creator: ['.field final synthetic this\$0:Landroid/os/Messenger;']}
  class_providers: ['framework_messenger_classes', 'framework_message_parcel_classes']
  extra_classes: ['android/os/IMessenger\$Stub.smali', 'android/os/IMessenger\$Stub\$Proxy.smali',
   'android/os/VinixMessageCreator.smali']
 }
}

fn messenger_binder_lines(source string) string {
 return source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
}

// Rebase labels by actual instruction position. Catch placement may change in
// DEX; preserve its exact exception type, protected interval and handler.
fn messenger_binder_method(source string) !string {
 mut code := []string{}
 mut catches := []string{}
 for original in source.split_into_lines() {
  raw_line := original.trim_space()
  line := if raw_line.starts_with('const-string ') { raw_line.replace("\\'", "'") } else { raw_line }
  if line.starts_with('.catch ') || line.starts_with('.catchall ') {
   catches << line.replace('{:', '{ :').replace('}', ' }')
  } else if line != '.end method' { code << line }
 }
 code << catches
 code << '.end method'
 return intent_extras_method(code.join('\n'))!
}

fn messenger_binder_metadata(metadata string) string {
 lines := messenger_binder_lines(metadata).split_into_lines()
 // DEX groups fields by static/instance category and sorts their names. Field
 // membership and declarations are exact; all other metadata keeps its order.
 return lines.filter(!it.starts_with('.field ')).join('\n') + '\n' +
  lines.filter(it.starts_with('.field ')).sorted().join('\n')
}

fn messenger_binder_m(header string, registers int, body string) string {
 return '.method ' + header + '\n.registers ' + registers.str() + '\n' + body + '\n.end method'
}

fn messenger_binder_messenger_methods() map[string]string {
 return {
  '<init>(Landroid/os/IBinder;)V': messenger_binder_m('public constructor <init>(Landroid/os/IBinder;)V', 3,
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Landroid/os/IMessenger\$Stub;->asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;\nmove-result-object v0\niput-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\nreturn-void')
  'equals(Ljava/lang/Object;)Z': messenger_binder_m('public equals(Ljava/lang/Object;)Z', 4,
   'instance-of v0, p1, Landroid/os/Messenger;\nif-eqz v0, :different\ncheck-cast p1, Landroid/os/Messenger;\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:different\nconst/4 v0, 0x0\nreturn v0')
  'getBinder()Landroid/os/IBinder;': messenger_binder_m('public getBinder()Landroid/os/IBinder;', 2,
   'iget-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\ninvoke-interface {v0}, Landroid/os/IMessenger;->asBinder()Landroid/os/IBinder;\nmove-result-object v0\nreturn-object v0')
  'hashCode()I': messenger_binder_m('public hashCode()I', 2,
   'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {v0}, Ljava/lang/Object;->hashCode()I\nmove-result v0\nreturn v0')
  '<clinit>()V': messenger_binder_m('static constructor <clinit>()V', 1,
   'new-instance v0, Landroid/os/Messenger\$1;\ninvoke-direct {v0}, Landroid/os/Messenger\$1;-><init>()V\nsput-object v0, Landroid/os/Messenger;->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void')
  'writeToParcel(Landroid/os/Parcel;I)V': messenger_binder_m('public writeToParcel(Landroid/os/Parcel;I)V', 4,
   'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void')
  'writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V': messenger_binder_m('public static writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V', 3,
   'const/4 v0, 0x0\nif-eqz p0, :write\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\n:write\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void')
  'readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;': messenger_binder_m('public static readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
   'invoke-virtual {p0}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\nif-nez v0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nnew-instance v1, Landroid/os/Messenger;\ninvoke-direct {v1, v0}, Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V\nreturn-object v1')
 }
}

fn messenger_binder_creator_methods() map[string]string {
 return {
  '<init>()V': messenger_binder_m('constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
  'createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;': messenger_binder_m('public createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
   'invoke-static {p1}, Landroid/os/Messenger;->readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0')
  'createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;': messenger_binder_m('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 3,
   'invoke-virtual {p0, p1}, Landroid/os/Messenger\$1;->createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0')
  'newArray(I)[Landroid/os/Messenger;': messenger_binder_m('public newArray(I)[Landroid/os/Messenger;', 3,
   'new-array v0, p1, [Landroid/os/Messenger;\nreturn-object v0')
  'newArray(I)[Ljava/lang/Object;': messenger_binder_m('public bridge synthetic newArray(I)[Ljava/lang/Object;', 3,
   'invoke-virtual {p0, p1}, Landroid/os/Messenger\$1;->newArray(I)[Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0')
 }
}

fn messenger_binder_message_write() string {
 return messenger_binder_m('public writeToParcel(Landroid/os/Parcel;I)V', 5,
  'iget-object v0, p0, Landroid/os/Message;->callback:Ljava/lang/Runnable;
if-eqz v0, :no_callback
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Can\'t marshal callbacks across processes."
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:no_callback
iget v0, p0, Landroid/os/Message;->what:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget v0, p0, Landroid/os/Message;->arg1:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget v0, p0, Landroid/os/Message;->arg2:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget-object v0, p0, Landroid/os/Message;->obj:Ljava/lang/Object;
if-eqz v0, :null_object
:object_try_start
check-cast v0, Landroid/os/Parcelable;
const/4 v1, 0x1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {p1, v0, p2}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V
:object_try_end
goto :object_done
:object_error
move-exception v0
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Can\'t marshal non-Parcelable objects across processes."
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:null_object
const/4 v0, 0x0
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
:object_done
iget-wide v0, p0, Landroid/os/Message;->when:J
invoke-virtual {p1, v0, v1}, Landroid/os/Parcel;->writeLong(J)V
iget-object v0, p0, Landroid/os/Message;->data:Landroid/os/Bundle;
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
iget-object v0, p0, Landroid/os/Message;->replyTo:Landroid/os/Messenger;
invoke-static {v0, p1}, Landroid/os/Messenger;->writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V
iget v0, p0, Landroid/os/Message;->sendingUid:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
return-void
.catch Ljava/lang/ClassCastException; {:object_try_start .. :object_try_end} :object_error')
}

fn messenger_binder_new_parts(target string) !StoreClassParts {
 match target {
  'android/os/IMessenger\$Stub.smali' {
   metadata := '.class public abstract Landroid/os/IMessenger\$Stub;\n.super Landroid/os/Binder;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x409\nname = "Stub"\n.end annotation\n.field private static final DESCRIPTOR:Ljava/lang/String; = "android.os.IMessenger"\n.field static final TRANSACTION_send:I = 0x1'
   methods := {
    '<init>()V': messenger_binder_m('public constructor <init>()V', 2,
     'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void')
    'asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;': messenger_binder_m('public static asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;', 3,
     'if-nez p0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nconst-string v0, "android.os.IMessenger"\ninvoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\ninstance-of v1, v0, Landroid/os/IMessenger;\nif-eqz v1, :proxy\ncheck-cast v0, Landroid/os/IMessenger;\nreturn-object v0\n:proxy\nnew-instance v0, Landroid/os/IMessenger\$Stub\$Proxy;\ninvoke-direct {v0, p0}, Landroid/os/IMessenger\$Stub\$Proxy;-><init>(Landroid/os/IBinder;)V\nreturn-object v0')
    'asBinder()Landroid/os/IBinder;': messenger_binder_m('public asBinder()Landroid/os/IBinder;', 1, 'return-object p0')
    'onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z': messenger_binder_m('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 7,
     'const v0, 0x5f4e5446\nif-ne p1, v0, :send\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0x1\nreturn v0\n:send\nconst/4 v0, 0x1\nif-ne p1, v0, :unknown\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\ninvoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :absent\nsget-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable\$Creator;\ninvoke-interface {v0, p2}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/os/Message;\ngoto :deliver\n:absent\nconst/4 v0, 0x0\n:deliver\ninvoke-interface {p0, v0}, Landroid/os/IMessenger;->send(Landroid/os/Message;)V\nconst/4 v0, 0x1\nreturn v0\n:unknown\ninvoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0')
   }
   return StoreClassParts{methods, metadata}
  }
  'android/os/IMessenger\$Stub\$Proxy.smali' {
   metadata := '.class Landroid/os/IMessenger\$Stub\$Proxy;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger\$Stub;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0xa\nname = "Proxy"\n.end annotation\n.field private final mRemote:Landroid/os/IBinder;'
   methods := {
    '<init>(Landroid/os/IBinder;)V': messenger_binder_m('constructor <init>(Landroid/os/IBinder;)V', 2,
     'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-void')
    'asBinder()Landroid/os/IBinder;': messenger_binder_m('public asBinder()Landroid/os/IBinder;', 2,
     'iget-object v0, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-object v0')
    'getInterfaceDescriptor()Ljava/lang/String;': messenger_binder_m('public getInterfaceDescriptor()Ljava/lang/String;', 2,
     'const-string v0, "android.os.IMessenger"\nreturn-object v0')
    'send(Landroid/os/Message;)V': messenger_binder_m('public send(Landroid/os/Message;)V', 7,
     'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n:begin\nconst-string v1, "android.os.IMessenger"\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\nif-eqz p1, :absent\nconst/4 v1, 0x1\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\nconst/4 v1, 0x0\ninvoke-virtual {p1, v0, v1}, Landroid/os/Message;->writeToParcel(Landroid/os/Parcel;I)V\ngoto :dispatch\n:absent\nconst/4 v1, 0x0\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n:dispatch\niget-object v1, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nconst/4 v2, 0x1\nconst/4 v3, 0x0\nconst/4 v4, 0x1\ninvoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n:end\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n.catchall {:begin .. :end} :failed\n:failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nthrow v1')
   }
   return StoreClassParts{methods, metadata}
  }
  'android/os/VinixMessageCreator.smali' {
   metadata := '.class final Landroid/os/VinixMessageCreator;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;'
   methods := {
    '<init>()V': messenger_binder_m('public constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
    'newArray(I)[Ljava/lang/Object;': messenger_binder_m('public newArray(I)[Ljava/lang/Object;', 3, 'new-array v0, p1, [Landroid/os/Message;\nreturn-object v0')
    'createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;': messenger_binder_m('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 5,
     'invoke-static {}, Landroid/os/Message;->obtain()Landroid/os/Message;
move-result-object v0
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->what:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->arg1:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->arg2:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
if-eqz v1, :object_done
const-class v1, Landroid/os/Message;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->obj:Ljava/lang/Object;
:object_done
invoke-virtual {p1}, Landroid/os/Parcel;->readLong()J
move-result-wide v1
iput-wide v1, v0, Landroid/os/Message;->when:J
invoke-virtual {p1}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->data:Landroid/os/Bundle;
invoke-static {p1}, Landroid/os/Messenger;->readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->replyTo:Landroid/os/Messenger;
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->sendingUid:I
return-object v0')
   }
   return StoreClassParts{methods, metadata}
  }
  else { return error('unexpected added Messenger class') }
 }
}

fn messenger_binder_expected(old string, target string) !StoreClassParts {
 before := store_parts(old)!
 mut metadata := messenger_binder_lines(before.metadata)
 mut methods := before.methods.clone()
 match target {
  'android/os/Messenger.smali' {
   metadata += '\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;'
   for name, method in messenger_binder_messenger_methods() { methods[name] = method }
  }
  'android/os/Messenger\$1.smali' {
   metadata = metadata.replace('.implements Landroid/os/IMessenger;', '.implements Landroid/os/Parcelable\$Creator;')
    .replace('value = Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V', 'value = Landroid/os/Messenger;-><clinit>()V')
    .replace('\n.field final synthetic this\$0:Landroid/os/Messenger;', '')
   methods = messenger_binder_creator_methods()
  }
  'android/os/IMessenger.smali' {
   metadata = metadata.replace('.class interface abstract ', '.class public interface abstract ')
    .replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;')
  }
  'android/os/Handler\$MessengerImpl.smali' {
   metadata = metadata.replace('.super Ljava/lang/Object;', '.super Landroid/os/IMessenger\$Stub;')
   ctor := '<init>(Landroid/os/Handler;)V'
   methods[ctor] = (methods[ctor] or { return error('retained Handler messenger constructor missing') })
    .replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'invoke-direct {p0}, Landroid/os/IMessenger\$Stub;-><init>()V')
   send := 'send(Landroid/os/Message;)V'
   methods[send] = messenger_binder_lines(methods[send] or { return error('retained Handler messenger send missing') })
    .replace('.registers 3\n', '.registers 3\ninvoke-static {}, Landroid/os/Binder;->getCallingUid()I\nmove-result v0\niput v0, p1, Landroid/os/Message;->sendingUid:I\n')
  }
  'android/os/Message.smali' {
   metadata = metadata.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;')
    + '\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n.field public sendingUid:I'
   for name in ['<clinit>()V', '<init>()V', 'clearForRecycle()V', 'copyFrom(Landroid/os/Message;)V', 'obtain(Landroid/os/Message;)Landroid/os/Message;'] {
    mut method := messenger_binder_lines(methods[name] or { return error('retained Message member missing') })
    match name {
     '<clinit>()V' { method = method.replace('return-void', 'new-instance v0, Landroid/os/VinixMessageCreator;\ninvoke-direct {v0}, Landroid/os/VinixMessageCreator;-><init>()V\nsput-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void') }
     '<init>()V' { method = method.replace('.registers 1', '.registers 2').replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void') }
     'clearForRecycle()V' { method = method.replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void') }
     'copyFrom(Landroid/os/Message;)V' { method = method.replace('.registers 3\n', '.registers 3\niget v0, p1, Landroid/os/Message;->sendingUid:I\niput v0, p0, Landroid/os/Message;->sendingUid:I\n') }
     else { method = method.replace('return-object v0', 'iget v1, p0, Landroid/os/Message;->sendingUid:I\niput v1, v0, Landroid/os/Message;->sendingUid:I\nreturn-object v0') }
    }
    methods[name] = method
   }
   methods['writeToParcel(Landroid/os/Parcel;I)V'] = messenger_binder_message_write()
  }
  else { return error('unexpected Messenger Binder target') }
 }
 return StoreClassParts{methods, metadata}
}

fn messenger_binder_parts_equal(expected StoreClassParts, actual StoreClassParts) ! {
 if messenger_binder_metadata(expected.metadata) != messenger_binder_metadata(actual.metadata)
  || expected.methods.keys().sorted() != actual.methods.keys().sorted() {
  return error('Messenger class/member/field/interface/annotation metadata differs')
 }
 for name, method in expected.methods {
  if messenger_binder_method(method)! != messenger_binder_method(actual.methods[name]!)! {
   return error('Messenger instructions/registers/flags/wire/branch/catch differ: ' + name)
  }
 }
}

fn messenger_binder_members(old string, new string, target string) ! {
 profile := messenger_binder_profile()
 before, after := store_parts(old)!, store_parts(new)!
 counts := {'android/os/Messenger.smali': 7, 'android/os/Messenger\$1.smali': 2,
  'android/os/IMessenger.smali': 1, 'android/os/Handler\$MessengerImpl.smali': 3, 'android/os/Message.smali': 28}
 count := counts[target] or { return error('unknown Messenger target') }
 if before.methods.len != count {
  return error('exact retained Messenger member count required')
 }
 messenger_binder_parts_equal(messenger_binder_expected(old, target)!, after)!
 mut changed := 0
 mut added := 0
 mut removed := 0
 for name, method in before.methods {
  if next := after.methods[name] {
   if messenger_binder_method(method)! != messenger_binder_method(next)! { changed++ }
  } else { removed++ }
 }
 for name in after.methods.keys() { if name !in before.methods { added++ } }
 if changed != profile.changed[target]! || added != profile.added[target]! || removed != profile.removed_methods[target]! {
  return error('exact Messenger replacement/addition/removal counts required')
 }
}

fn messenger_binder_factory_main(profile NarrowProfile) !string {
 if profile.name != 'messenger-binder' || profile.class_provider != ''
  || profile.directory_provider != ''
  || profile.class_providers != ['framework_messenger_classes', 'framework_message_parcel_classes']
  || profile.extra_classes != ['android/os/IMessenger\$Stub.smali', 'android/os/IMessenger\$Stub\$Proxy.smali', 'android/os/VinixMessageCreator.smali'] {
  return error('exact two distinct Messenger class factories required')
 }
 mut result := 'mut classes := map[string]string{}\n'
 for i, factory in profile.class_providers {
  name := 'factory' + i.str()
  result += name + ' := androidtools.' + factory + '()\nfor name, source in ' + name + ' {\n' +
   'if name in classes { panic("duplicate added class from factories") }\nclasses[name] = source\n}\n'
 }
 result += 'expected := ' + json2.encode(profile.extra_classes.map(it.all_before_last('.smali'))) + '\n' +
  'if classes.keys().sorted() != expected.sorted() { panic("exact merged Messenger class set required") }\n' +
  'for name in expected {\npath := os.args[1] + "/" + name + ".smali"\n' +
  'if os.exists(path) || os.is_link(path) { panic("added class collision") }\n}\n'
 return result
}

fn messenger_binder_source(parts StoreClassParts) string {
 return parts.metadata + '\n' + parts.methods.values().join('\n') + '\n'
}

// Independent baseline fixtures exercise old-member retention. Production also
// requires the complete immutable parent SDK, not these reduced test bodies.
fn messenger_binder_old_fixture(target string) !string {
 match target {
  'android/os/Messenger.smali' {
   metadata := '.class public final Landroid/os/Messenger;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field private final mTarget:Landroid/os/IMessenger;'
   mut methods := map[string]string{}
   for header in ['public constructor <init>(Landroid/os/Handler;)V', 'public constructor <init>(Landroid/os/IBinder;)V',
    'public describeContents()I', 'public equals(Ljava/lang/Object;)Z', 'public getBinder()Landroid/os/IBinder;',
    'public hashCode()I', 'public send(Landroid/os/Message;)V'] {
    methods[header.all_after_last(' ')] = messenger_binder_m(header, 3, 'const/4 v0, 0x0\nreturn-void')
   }
   return messenger_binder_source(StoreClassParts{methods, metadata})
  }
  'android/os/Messenger\$1.smali' {
   return '.class Landroid/os/Messenger\$1;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingMethod;\nvalue = Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x0\nname = null\n.end annotation\n.field final synthetic this\$0:Landroid/os/Messenger;\n' +
    messenger_binder_m('constructor <init>(Landroid/os/Messenger;)V', 2, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + '\n' +
    messenger_binder_m('public send(Landroid/os/Message;)V', 2, 'return-void') + '\n'
  }
  'android/os/IMessenger.smali' { return '.class interface abstract Landroid/os/IMessenger;\n.super Ljava/lang/Object;\n.method public abstract send(Landroid/os/Message;)V\n.end method\n' }
  'android/os/Handler\$MessengerImpl.smali' {
   return '.class final Landroid/os/Handler\$MessengerImpl;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.field final synthetic this\$0:Landroid/os/Handler;\n' +
    messenger_binder_m('private constructor <init>(Landroid/os/Handler;)V', 2, 'iput-object p1, p0, Landroid/os/Handler\$MessengerImpl;->this\$0:Landroid/os/Handler;\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + '\n' +
    messenger_binder_m('synthetic constructor <init>(Landroid/os/Handler;Landroid/os/Handler\$1;)V', 3, 'invoke-direct {p0, p1}, Landroid/os/Handler\$MessengerImpl;-><init>(Landroid/os/Handler;)V\nreturn-void') + '\n' +
    messenger_binder_m('public send(Landroid/os/Message;)V', 3, 'iget-object v0, p0, Landroid/os/Handler\$MessengerImpl;->this\$0:Landroid/os/Handler;\ninvoke-virtual {v0, p1}, Landroid/os/Handler;->sendMessage(Landroid/os/Message;)Z\nreturn-void') + '\n'
  }
  'android/os/Message.smali' {
   metadata := '.class public final Landroid/os/Message;\n.super Ljava/lang/Object;\n.field private static sPool:Landroid/os/Message;\n.field public replyTo:Landroid/os/Messenger;'
   mut methods := {
    '<clinit>()V': messenger_binder_m('static constructor <clinit>()V', 1, 'const/4 v0, 0x0\nreturn-void')
    '<init>()V': messenger_binder_m('public constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
    'clearForRecycle()V': messenger_binder_m('clearForRecycle()V', 4, 'const/4 v0, 0x0\nreturn-void')
    'copyFrom(Landroid/os/Message;)V': messenger_binder_m('public copyFrom(Landroid/os/Message;)V', 3, 'const/4 v0, 0x0\nreturn-void')
    'obtain(Landroid/os/Message;)Landroid/os/Message;': messenger_binder_m('public static obtain(Landroid/os/Message;)Landroid/os/Message;', 4, 'const/4 v0, 0x0\nreturn-object v0')
   }
   for i in 0 .. 23 { methods['retained' + i.str() + '()V'] = messenger_binder_m('public retained' + i.str() + '()V', 1, 'return-void') }
   return messenger_binder_source(StoreClassParts{methods, metadata})
  }
  else { return error('unknown Messenger fixture target') }
 }
}

fn messenger_binder_self_test() ! {
 profile := messenger_binder_profile()
 if profile.name != 'messenger-binder' || profile.baseline_classes != 2112
  || profile.baseline_name != 'combined-account-webview-usage-inactive-framework-2026-11-02-r1'
  || profile.manifest_pin != 'bfadac214671937539a4732b3ca6be22d561c366b96a72a9de045fc362aba1fe'
  || profile.jar_pin != 'd7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b'
  || profile.providers != ['framework_messenger.v', 'framework_message_parcel.v']
  || profile.calls != {'android/os/Handler\$MessengerImpl.smali': 'framework_handler_messenger_source',
   'android/os/IMessenger.smali': 'framework_imessenger_source', 'android/os/Message.smali': 'framework_message_parcel_source',
   'android/os/Messenger\$1.smali': 'framework_messenger_creator_source', 'android/os/Messenger.smali': 'framework_messenger_source'}
  || profile.methods.keys().sorted() != profile.calls.keys().sorted()
  || profile.changed != {'android/os/Handler\$MessengerImpl.smali': 2, 'android/os/IMessenger.smali': 0,
   'android/os/Message.smali': 5, 'android/os/Messenger\$1.smali': 0, 'android/os/Messenger.smali': 4}
  || profile.added != {'android/os/Handler\$MessengerImpl.smali': 0, 'android/os/IMessenger.smali': 0,
   'android/os/Message.smali': 1, 'android/os/Messenger\$1.smali': 5, 'android/os/Messenger.smali': 4}
  || profile.fields != {'android/os/Messenger.smali': ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;'],
   'android/os/Message.smali': ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;', '.field public sendingUid:I']}
  || profile.removed_fields != {
   'android/os/Messenger\$1.smali': ['.field final synthetic this\$0:Landroid/os/Messenger;']}
  || profile.removed_methods != {'android/os/Handler\$MessengerImpl.smali': 0, 'android/os/IMessenger.smali': 0,
   'android/os/Message.smali': 0, 'android/os/Messenger\$1.smali': 2, 'android/os/Messenger.smali': 0} {
  return error('exact five-class Messenger profile and explicit removals required')
 }
 for target, methods in {
  'android/os/Handler\$MessengerImpl.smali': ['<init>(Landroid/os/Handler;)V', 'send(Landroid/os/Message;)V'],
  'android/os/IMessenger.smali': []string{},
  'android/os/Message.smali': ['<clinit>()V', '<init>()V', 'clearForRecycle()V', 'copyFrom(Landroid/os/Message;)V',
   'obtain(Landroid/os/Message;)Landroid/os/Message;', 'writeToParcel(Landroid/os/Parcel;I)V'],
  'android/os/Messenger\$1.smali': messenger_binder_creator_methods().keys(),
  'android/os/Messenger.smali': messenger_binder_messenger_methods().keys()
 } {
  if (profile.methods[target] or { []string{} }).sorted() != methods.sorted() { return error('exact published Messenger changed/added method sets required') }
 }
 main_source := messenger_binder_factory_main(profile)!
 if main_source.count('androidtools.framework_messenger_classes()') != 1
  || main_source.count('androidtools.framework_message_parcel_classes()') != 1
  || !main_source.contains('if name in classes') || !main_source.contains('classes.keys().sorted() != expected.sorted()')
  || main_source.contains('os.write_file') { return error('both class factories must be fully validated before writes') }
 for case in 0 .. 4 {
  mut bad := profile
  match case {
   0 { bad = NarrowProfile{...profile, class_provider: 'other'} }
   1 { bad = NarrowProfile{...profile, class_providers: ['framework_messenger_classes', 'framework_messenger_classes']} }
   2 { bad = NarrowProfile{...profile, directory_provider: 'other'} }
   else { bad = NarrowProfile{...profile, extra_classes: ['unexpected.smali']} }
  }
  messenger_binder_factory_main(bad) or { continue }
  return error('ambiguous/mixed/duplicate Messenger factory or wrong class set accepted')
 }
 for target in profile.methods.keys() {
  old := messenger_binder_old_fixture(target)!
  expected := messenger_binder_expected(old, target)!
  good := messenger_binder_source(expected)
  messenger_binder_members(old, good, target)!
  for bad in [good.replace('.super ', '.super Lwrong/Base;\n# '), good + '.field private unrelated:I\n',
   good + '.method public unrelated()V\n.registers 1\nreturn-void\n.end method\n',
   good.replace('public ', 'private ')] {
   messenger_binder_members(old, bad, target) or { continue }
   return error('Messenger unrelated field/method or class/access metadata mutation accepted')
  }
  for name, method in expected.methods {
   for bad_method in [method.replace('.method ', '.method static '), method.replace('.registers ', '.registers 1 # '),
    method.replace('return', 'throw'), method + '\n' + method] {
    if bad_method == method { continue }
    messenger_binder_members(old, good.replace(method, bad_method), target) or { continue }
    return error('Messenger changed or retained method flags/registers/return/duplication accepted: ' + name)
   }
  }
 }
 for target in profile.extra_classes {
  expected := messenger_binder_new_parts(target)!
  good := messenger_binder_source(expected)
  messenger_binder_parts_equal(expected, store_parts(good)!)!
  for bad in [good + '.field private unrelated:I\n', good.replace('.super ', '.super Lwrong/Base;\n# '),
   good.replace('.implements Landroid/os/', '.implements Lwrong/'), good.replace('.method ', '.method static ')] {
   messenger_binder_parts_equal(expected, store_parts(bad)!) or { continue }
   return error('Messenger added class metadata/field/method ABI mutation accepted')
  }
 }
 message := messenger_binder_message_write()
 if messenger_binder_method(message)! != messenger_binder_method(message.replace("Can't", "Can\\'t"))! {
  return error('equivalent Smali apostrophe escaping in const-string rejected')
 }
 for changed in [message.replace('->arg1:I', '->arg2:I'), message.replace('->writeLong(J)V', '->writeInt(I)V'),
  message.replace("Can't marshal callbacks", 'Wrong callback error'),
  message.replace('->replyTo:', '->target:'), message.replace('->sendingUid:I', '->what:I'),
  message.replace('if-eqz v0, :no_callback', 'if-nez v0, :no_callback'),
  message.replace('Ljava/lang/ClassCastException;', 'Ljava/lang/Exception;'),
  message.replace('{:object_try_start .. :object_try_end}', '{:no_callback .. :object_try_end}'),
  message.replace('->writeParcelable(Landroid/os/Parcelable;I)V', '->writeParcelable(Landroid/os/Parcelable;)V'),
  message.replace('invoke-virtual {p1, v0, p2}', 'invoke-virtual {p1, v0, v1}')] {
  if messenger_binder_method(changed)! == messenger_binder_method(message)! { return error('Message callback/wire/flags/catch-span mutation accepted') }
 }
 proxy := messenger_binder_new_parts('android/os/IMessenger\$Stub\$Proxy.smali')!
 send := proxy.methods['send(Landroid/os/Message;)V']!
 for bad in [send.replace('"android.os.IMessenger"', '"wrong"'), send.replace('const/4 v4, 0x1', 'const/4 v4, 0x0'),
  send.replace('const/4 v3, 0x0', 'const/4 v3, 0x1'), send.replace('if-eqz p1, :absent', 'if-nez p1, :absent'),
  send.replace('invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V', ''),
  send.replace('.catchall {:begin .. :end}', '.catchall {:dispatch .. :end}'), send.replace('throw v1', 'return-void'),
  send.replace(':end\n', 'move-result v2\n:end\n')] {
  if messenger_binder_method(bad)! == messenger_binder_method(send)! { return error('Messenger one-way/null-reply/ignored-bool/finally mutation accepted') }
 }
 moved := send.replace('.catchall {:begin .. :end} :failed\n', '').replace(':end\n', ':end\n.catchall {:begin .. :end} :failed\n')
 if messenger_binder_method(send)! != messenger_binder_method(moved.replace(':begin', ':try_start').replace(':end', ':try_end').replace(':failed', ':caught'))! {
  return error('equivalent DEX catch relocation/label aliases rejected')
 }
 mut before := map[string]string{}
 for target in profile.methods.keys() { before[target] = 'old' }
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 for target in profile.methods.keys() { after[target] = 'new' }
 for target in profile.extra_classes { after[target] = 'added' }
 narrow_profile_class_delta(before, after, profile.methods.keys(), profile.extra_classes, 2112)!
 mut scope_mutations := profile.methods.keys()
 scope_mutations << profile.extra_classes
 scope_mutations << 'other/0.smali'
 for target in scope_mutations {
  mut bad := after.clone()
  if target in before { bad[target] = before[target]! } else { bad.delete(target) }
  if target == 'other/0.smali' { bad[target] = 'changed' }
  narrow_profile_class_delta(before, bad, profile.methods.keys(), profile.extra_classes, 2112) or { continue }
  return error('Messenger complete five-change/three-addition class scope mutation accepted')
 }
}

fn component_parcel_profile() NarrowProfile {
 component := 'android/content/ComponentName.smali'
 return NarrowProfile{
  name: 'component-parcel'
  baseline_name: 'combined-account-webview-messenger-binder-framework-2026-11-02-r1'
  manifest_pin: 'e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85'
  jar_pin: 'ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129'
  baseline_classes: 2115
  providers: ['framework_component_parcel.v']
  calls: {component: 'framework_component_parcel_source'}
  methods: {component: ['<clinit>()V', '<init>(Landroid/os/Parcel;)V',
   '<init>(Ljava/lang/String;Landroid/os/Parcel;)V', 'writeToParcel(Landroid/os/Parcel;I)V',
   'writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V',
   'readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;']}
  changed: {component: 0}
  added: {component: 6}
  fields: {component: ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;']}
  class_provider: 'framework_component_parcel_classes'
  extra_classes: ['android/content/VinixComponentNameCreator.smali']
 }
}

fn component_parcel_expected_methods() map[string]string {
 return {
  '<clinit>()V': messenger_binder_m('static constructor <clinit>()V', 1,
   'new-instance v0, Landroid/content/VinixComponentNameCreator;\ninvoke-direct {v0}, Landroid/content/VinixComponentNameCreator;-><init>()V\nsput-object v0, Landroid/content/ComponentName;->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void')
  '<init>(Landroid/os/Parcel;)V': messenger_binder_m('public constructor <init>(Landroid/os/Parcel;)V', 4,
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;
if-nez v0, :package_present
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "package name is null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:package_present
invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;
if-nez v0, :done
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "class name is null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void')
  '<init>(Ljava/lang/String;Landroid/os/Parcel;)V': messenger_binder_m('private constructor <init>(Ljava/lang/String;Landroid/os/Parcel;)V', 4,
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\ninvoke-virtual {p2}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\niput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;\nreturn-void')
  'writeToParcel(Landroid/os/Parcel;I)V': messenger_binder_m('public writeToParcel(Landroid/os/Parcel;I)V', 4,
   'iget-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\niget-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void')
  'writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V': messenger_binder_m('public static writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V', 3,
   'const/4 v0, 0x0\nif-eqz p0, :absent\ninvoke-virtual {p0, p1, v0}, Landroid/content/ComponentName;->writeToParcel(Landroid/os/Parcel;I)V\nreturn-void\n:absent\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void')
  'readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;': messenger_binder_m('public static readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;', 3,
   'invoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\nif-nez v0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nnew-instance v1, Landroid/content/ComponentName;\ninvoke-direct {v1, v0, p0}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Landroid/os/Parcel;)V\nreturn-object v1')
 }
}

fn component_parcel_abi(source string) ! {
 parts := store_parts(source)!
 for signature, expected in component_parcel_expected_methods() {
  method := parts.methods[signature] or { return error('ComponentName parcel method missing') }
  if intent_extras_method(method)! != intent_extras_method(expected)! {
   return error('ComponentName requires exact API28 wire, null-validation order and nullable-helper semantics: ' + signature)
  }
 }
}

fn component_parcel_creator_methods() map[string]string {
 return {
  '<init>()V': messenger_binder_m('public constructor <init>()V', 1,
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
  'createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;': messenger_binder_m('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 3,
   'new-instance v0, Landroid/content/ComponentName;\ninvoke-direct {v0, p1}, Landroid/content/ComponentName;-><init>(Landroid/os/Parcel;)V\nreturn-object v0')
  'newArray(I)[Ljava/lang/Object;': messenger_binder_m('public newArray(I)[Ljava/lang/Object;', 3,
   'new-array v0, p1, [Landroid/content/ComponentName;\nreturn-object v0')
 }
}

fn component_parcel_creator_abi(source string) ! {
 parts := store_parts(source)!
 methods := component_parcel_creator_methods()
 if parts.methods.keys().sorted() != methods.keys().sorted()
  || parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
   '.class final Landroid/content/VinixComponentNameCreator;', '.super Ljava/lang/Object;',
   '.implements Landroid/os/Parcelable\$Creator;'] {
  return error('ComponentName creator requires exact fieldless class and three methods')
 }
 for signature, expected in methods {
  if intent_extras_method(parts.methods[signature]!)! != intent_extras_method(expected)! {
   return error('ComponentName creator requires public validating Parcel constructor and actual ComponentName array')
  }
 }
}

fn component_parcel_self_test() ! {
 profile := component_parcel_profile()
 component := 'android/content/ComponentName.smali'
 creator := 'android/content/VinixComponentNameCreator.smali'
 expected := component_parcel_expected_methods()
 field := '.field public static final CREATOR:Landroid/os/Parcelable\$Creator;'
 if profile.name != 'component-parcel' || profile.baseline_classes != 2115
  || profile.baseline_name != 'combined-account-webview-messenger-binder-framework-2026-11-02-r1'
  || profile.manifest_pin != 'e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85'
  || profile.jar_pin != 'ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129'
  || profile.providers != ['framework_component_parcel.v'] || profile.calls != {component: 'framework_component_parcel_source'}
  || profile.methods.keys() != [component] || profile.methods[component]!.sorted() != expected.keys().sorted()
  || profile.changed != {component: 0} || profile.added != {component: 6} || profile.fields != {component: [field]}
  || profile.class_provider != 'framework_component_parcel_classes' || profile.class_providers.len != 0
  || profile.extra_classes != [creator] || profile.directory_provider != ''
  || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('ComponentName parcel profile requires exact six additions, one field and one creator')
 }
 narrow_method_self_test(profile.methods[component]!, 0, 6)!
 raw := expected.values().join('\n') + '\n'
 component_parcel_abi(raw)!
 component_parcel_abi(raw.replace(':package_present', ':renamed_package').replace(':done', ':renamed_done')
  .replace(':absent', ':renamed_absent').replace(':present', ':renamed_present'))!
 for signature, method in expected {
  for bad in [method.replace('.method ', '.method native '), method.replace('.registers ', '.registers 9 # '),
   method.replace('public ', 'private '), method.replace('private ', 'public '), method.replace('return', 'throw'),
   method.replace('->mPackage:', '->mClass:'), method.replace('->readString()', '->readInt()'),
   method.replace('->writeString(Ljava/lang/String;)', '->writeInt(I)'), method + '\n' + method] {
   if bad == method { continue }
   component_parcel_abi(raw.replace(method, bad)) or { continue }
   return error('ComponentName parcel flags/register/wire/field/member mutation accepted: ' + signature)
  }
 }
 public_ctor := expected['<init>(Landroid/os/Parcel;)V']!
 for bad in [public_ctor.replace('if-nez v0, :package_present', 'if-eqz v0, :package_present'),
  public_ctor.replace('if-nez v0, :done', 'if-eqz v0, :done'),
  public_ctor.replace('"package name is null"', '"class name is null"'),
  public_ctor.replace('Ljava/lang/NullPointerException;', 'Ljava/lang/IllegalArgumentException;'),
  public_ctor.replace(':package_present\n', ':package_present\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\n')] {
  component_parcel_abi(raw.replace(public_ctor, bad)) or { continue }
  return error('ComponentName public Parcel constructor null checks or cursor order mutation accepted')
 }
 nullable_read := expected['readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;']!
 private_ctor := expected['<init>(Ljava/lang/String;Landroid/os/Parcel;)V']!
 nullable_write := expected['writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V']!
 for bad in [raw.replace(nullable_read, nullable_read.replace('if-nez v0, :present', 'if-eqz v0, :present')),
  raw.replace(nullable_read, nullable_read.replace('invoke-direct {v1, v0, p0}', 'invoke-direct {v1, p0, v0}')),
  raw.replace(private_ctor, private_ctor.replace('return-void', 'if-nez v0, :ok\nthrow v0\n:ok\nreturn-void')),
  raw.replace(nullable_write, nullable_write.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')),
  raw.replace(nullable_write, nullable_write.replace('if-eqz p0, :absent', 'if-nez p0, :absent'))] {
  component_parcel_abi(bad) or { continue }
  return error('ComponentName nullable reader/private constructor/null sentinel/flags mutation accepted')
 }
 metadata := '.class public final Landroid/content/ComponentName;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field private final mClass:Ljava/lang/String;\n.field private final mPackage:Ljava/lang/String;\n'
 retained := '.method public getPackageName()Ljava/lang/String;\n.registers 2\niget-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;\nreturn-object v0\n.end method\n'
 before := metadata + retained
 after := before + field + '\n' + raw
 narrow_member_delta(before, after, profile.methods[component]!, 0, 6, [field])!
 for bad in [after.replace(field, ''), after.replace('private final mClass', 'public mClass'),
  after.replace('->mPackage:Ljava/lang/String;\nreturn-object v0', '->mClass:Ljava/lang/String;\nreturn-object v0'),
  after + '.field private unrelated:I\n', after.replace('.implements Landroid/os/Parcelable;', '.implements Lwrong/Interface;')] {
  narrow_member_delta(before, bad, profile.methods[component]!, 0, 6, [field]) or { continue }
  return error('ComponentName retained fields/getter/metadata or CREATOR mutation accepted')
 }
 creator_source := '.class final Landroid/content/VinixComponentNameCreator;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n' + component_parcel_creator_methods().values().join('\n') + '\n'
 component_parcel_creator_abi(creator_source)!
 for bad in [creator_source.replace('.class final ', '.class public final '),
  creator_source + '.field private state:I\n', creator_source.replace('[Landroid/content/ComponentName;', '[Ljava/lang/Object;'),
  creator_source.replace('public createFromParcel', 'private createFromParcel'),
  creator_source.replace('-><init>(Landroid/os/Parcel;)V', '-><init>(Ljava/lang/String;Landroid/os/Parcel;)V'),
  creator_source.replace('public newArray', 'public static newArray')] {
  component_parcel_creator_abi(bad) or { continue }
  return error('ComponentName creator metadata/ABI/constructor/array mutation accepted')
 }
 mut old := {component: 'old'}
 for i in 0 .. 2114 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[component] = 'new'
 good[creator] = 'creator'
 narrow_profile_class_delta(old, good, [component], [creator], 2115)!
 for case in 0 .. 6 {
  mut bad := good.clone()
  match case {
   0 { bad[component] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(component) }
   3 { bad.delete(creator) }
   4 { bad['unrelated.smali'] = 'extra' }
   else { bad.delete(creator); bad['substitution.smali'] = 'creator' }
  }
  narrow_profile_class_delta(old, bad, [component], [creator], 2115) or { continue }
  return error('ComponentName-only six-method/one-creator class scope mutation accepted')
 }
}

fn event_log_profile() NarrowProfile {
 return NarrowProfile{
  name: 'event-log'
  baseline_name: 'combined-account-webview-component-parcel-framework-2026-11-02-r1'
  manifest_pin: '79d78a512ac764807a2ecd3ca39317a5030e133f3749c0dd349c037482dcd512'
  jar_pin: '329a45c23bd981b67733f36cde2828b2d890597a384acf1e0ce30f8f8fb582f4'
  baseline_classes: 2116
  providers: ['framework_event_log.v']
  class_provider: 'framework_event_log_classes'
  extra_classes: ['android/util/EventLog.smali']
 }
}

fn event_log_class_delta(old map[string]string, new map[string]string) ! {
 added := 'android/util/EventLog.smali'
 if old.len != 2116 || new.len != 2117 || added in old || added !in new {
  return error('EventLog requires exactly one new class over the complete 2116-class parent')
 }
 for name, pin in old {
  if name !in new || new[name]! != pin {
   return error('EventLog changed existing class: ' + name)
  }
 }
}

fn event_log_expected_methods() map[string]string {
 mut methods := {
  '<init>()V': messenger_binder_m('public constructor <init>()V', 1,
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 }
 for signature, registers in {'writeEvent(II)I': 3, 'writeEvent(IJ)I': 4,
  'writeEvent(IF)I': 3, 'writeEvent(ILjava/lang/String;)I': 3} {
  methods[signature] = messenger_binder_m('public static ' + signature, registers,
   'const/16 v0, -0x13\nreturn v0')
 }
 methods['writeEvent(I[Ljava/lang/Object;)I'] = messenger_binder_m('public static varargs writeEvent(I[Ljava/lang/Object;)I', 10,
  'if-eqz p1, :unavailable
const/4 v0, 0x0
const/4 v1, 0x2
array-length v2, p1
const/16 v3, 0xff
const/16 v7, 0xfe0
:next_item
if-ge v0, v2, :unavailable
if-ge v0, v3, :unavailable
aget-object v4, p1, v0
if-eqz v4, :null_item
instance-of v5, v4, Ljava/lang/String;
if-nez v5, :string_item
instance-of v5, v4, Ljava/lang/Integer;
if-nez v5, :fixed_five
instance-of v5, v4, Ljava/lang/Long;
if-nez v5, :fixed_nine
instance-of v5, v4, Ljava/lang/Float;
if-nez v5, :fixed_five
new-instance v4, Ljava/lang/IllegalArgumentException;
const-string v5, "Invalid payload item type"
invoke-direct {v4, v5}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v4
:fixed_five
const/4 v5, 0x5
goto :fixed_item
:fixed_nine
const/16 v5, 0x9
:fixed_item
add-int v6, v1, v5
if-gt v6, v7, :encoding_error
move v1, v6
goto :advance
:null_item
const/4 v5, 0x4
goto :string_length
:string_item
check-cast v4, Ljava/lang/String;
invoke-static {v4}, Landroid/util/EventLog;->vinixUtf8Length(Ljava/lang/String;)I
move-result v5
:string_length
add-int/lit8 v5, v5, 0x5
add-int v6, v1, v5
if-le v6, v7, :string_accepted
add-int/lit8 v5, v1, 0x5
if-ge v5, v7, :encoding_error
:string_accepted
move v1, v6
:advance
add-int/lit8 v0, v0, 0x1
goto :next_item
:encoding_error
const/4 v0, -0x5
return v0
:unavailable
const/16 v0, -0x13
return v0')
 methods['vinixUtf8Length(Ljava/lang/String;)I'] = messenger_binder_m('private static vinixUtf8Length(Ljava/lang/String;)I', 9,
  'const/4 v0, 0x0
const/4 v1, 0x0
invoke-virtual {p0}, Ljava/lang/String;->length()I
move-result v2
const/16 v4, 0xfe0
:next_character
if-ge v0, v4, :capped
if-ge v1, v2, :done
invoke-virtual {p0, v1}, Ljava/lang/String;->charAt(I)C
move-result v3
if-eqz v3, :two_bytes
const/16 v5, 0x80
if-lt v3, v5, :one_byte
const/16 v5, 0x800
if-lt v3, v5, :two_bytes
const v5, 0xd800
if-lt v3, v5, :three_bytes
const v5, 0xdc00
if-ge v3, v5, :three_bytes
add-int/lit8 v6, v1, 0x1
if-ge v6, v2, :three_bytes
invoke-virtual {p0, v6}, Ljava/lang/String;->charAt(I)C
move-result v7
const v5, 0xdc00
if-lt v7, v5, :three_bytes
const v5, 0xe000
if-ge v7, v5, :three_bytes
add-int/lit8 v0, v0, 0x4
move v1, v6
goto :advance
:three_bytes
add-int/lit8 v0, v0, 0x3
goto :advance
:one_byte
add-int/lit8 v0, v0, 0x1
goto :advance
:two_bytes
add-int/lit8 v0, v0, 0x2
:advance
add-int/lit8 v1, v1, 0x1
goto :next_character
:capped
move v0, v4
:done
return v0')
 return methods
}

fn event_log_abi(source string) ! {
 parts := store_parts(source)!
 expected := event_log_expected_methods()
 if parts.metadata.split_into_lines().map(it.trim_space()).filter(it != '') != [
  '.class public Landroid/util/EventLog;', '.super Ljava/lang/Object;']
  || parts.methods.keys().sorted() != expected.keys().sorted() {
  return error('EventLog requires one fieldless public class, five write overloads, constructor and private UTF helper only')
 }
 for signature, method in expected {
  if intent_extras_method(parts.methods[signature]!)! != intent_extras_method(method)! {
   return error('EventLog type/UTF/budget/error-precedence/unavailable-backend instructions differ: ' + signature)
  }
 }
}

fn event_log_self_test() ! {
 profile := event_log_profile()
 added := 'android/util/EventLog.smali'
 if profile.name != 'event-log' || profile.baseline_classes != 2116
  || profile.baseline_name != 'combined-account-webview-component-parcel-framework-2026-11-02-r1'
  || profile.manifest_pin != '79d78a512ac764807a2ecd3ca39317a5030e133f3749c0dd349c037482dcd512'
  || profile.jar_pin != '329a45c23bd981b67733f36cde2828b2d890597a384acf1e0ce30f8f8fb582f4'
  || profile.providers != ['framework_event_log.v'] || profile.class_provider != 'framework_event_log_classes'
  || profile.methods.len != 0 || profile.calls.len != 0 || profile.changed.len != 0 || profile.added.len != 0
  || profile.fields.len != 0 || profile.extra_classes != [added] || profile.class_providers.len != 0
  || profile.directory_provider != '' || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('EventLog requires one added class and no existing class/member/field/removal deltas')
 }
 expected := event_log_expected_methods()
 raw := '.class public Landroid/util/EventLog;\n.super Ljava/lang/Object;\n' + expected.values().join('\n') + '\n'
 event_log_abi(raw)!
 event_log_abi(raw.replace(':unavailable', ':changed_unavailable').replace(':encoding_error', ':changed_error')
  .replace(':next_item', ':changed_next').replace(':next_character', ':changed_character'))!
 for bad in [raw.replace('.class public ', '.class public final '), raw.replace('.super Ljava/lang/Object;', '.super Lwrong/Base;'),
  raw + '.field private state:I\n', raw + '.implements Ljava/lang/Runnable;\n',
  raw + '.method public static readEvents()V\n.registers 0\nreturn-void\n.end method\n',
  raw.replace('public static varargs ', 'public static '), raw.replace('private static vinixUtf8Length', 'public static vinixUtf8Length'),
  raw.replace('const/16 v0, -0x13', 'const/16 v0, 0x13'), raw.replace('const/16 v0, -0x13', 'const/16 v0, 0x0'),
  raw.replace('return v0', 'return-object v0'), raw.replace('public static writeEvent(II)', 'public static native writeEvent(II)')] {
  event_log_abi(bad) or { continue }
  return error('EventLog class/fields/readers/native/ABI/result mutation accepted')
 }
 for signature, method in expected {
  for bad in [method.replace('.method ', '.method final '), method.replace('.registers ', '.registers 12 # '),
   method.replace('return', 'throw'), method + '\n' + method] {
   event_log_abi(raw.replace(method, bad)) or { continue }
   return error('EventLog flags/register/return/duplicate mutation accepted: ' + signature)
  }
 }
 array := expected['writeEvent(I[Ljava/lang/Object;)I']!
 for bad in [array.replace('if-eqz p1, :unavailable', 'if-nez p1, :unavailable'),
  array.replace('const/4 v1, 0x2', 'const/4 v1, 0x0'), array.replace('const/16 v3, 0xff', 'const/16 v3, 0x100'),
  array.replace('const/16 v7, 0xfe0', 'const/16 v7, 0xfe1'), array.replace('Ljava/lang/Integer;', 'Ljava/lang/Double;'),
  array.replace('Ljava/lang/Float;', 'Ljava/lang/Boolean;'), array.replace('const/16 v5, 0x9', 'const/16 v5, 0x5'),
  array.replace('const/4 v5, 0x4', 'const/4 v5, 0x0'), array.replace('const/4 v0, -0x5', 'const/4 v0, -0x1'),
  array.replace('Ljava/lang/IllegalArgumentException;', 'Ljava/lang/RuntimeException;'),
  array.replace('"Invalid payload item type"', '"Invalid event"'), array.replace('if-gt v6, v7, :encoding_error', 'if-ge v6, v7, :encoding_error'),
  array.replace('if-ge v5, v7, :encoding_error', 'if-gt v5, v7, :encoding_error'),
  array.replace('move v1, v6', 'move v1, v7'), array.replace('if-ge v0, v3, :unavailable', 'if-ge v0, v3, :encoding_error')] {
  event_log_abi(raw.replace(array, bad)) or { continue }
  return error('EventLog array type/cap/budget/truncation/status/exception ordering mutation accepted')
 }
 utf := expected['vinixUtf8Length(Ljava/lang/String;)I']!
 for bad in [utf.replace('if-eqz v3, :two_bytes', 'if-eqz v3, :one_byte'),
  utf.replace('const v5, 0xd800', 'const v5, 0xd7ff'), utf.replace('const v5, 0xdc00', 'const v5, 0xdbff'),
  utf.replace('const v5, 0xe000', 'const v5, 0xe001'), utf.replace('add-int/lit8 v0, v0, 0x4', 'add-int/lit8 v0, v0, 0x6'),
  utf.replace('add-int/lit8 v0, v0, 0x3', 'add-int/lit8 v0, v0, 0x1'), utf.replace('move v1, v6', 'move v1, v2'),
  utf.replace('if-ge v0, v4, :capped', 'if-ge v0, v4, :done'), utf.replace('const/16 v4, 0xfe0', 'const/16 v4, 0xfe1')] {
  event_log_abi(raw.replace(utf, bad)) or { continue }
  return error('EventLog ART28 NUL/surrogate/width/cap mutation accepted')
 }
 mut old := map[string]string{}
 for i in 0 .. 2116 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good[added] = 'EventLog'
 event_log_class_delta(old, good)!
 for case in 0 .. 6 {
  mut bad := good.clone()
  match case {
   0 { bad.delete(added) }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete('other/0.smali') }
   3 { bad['unrelated.smali'] = 'extra' }
   4 { bad.delete(added); bad['substitution.smali'] = 'EventLog' }
   else { old[added] = 'preexisting' }
  }
  event_log_class_delta(old, bad) or { continue }
  return error('EventLog-only addition or whole predecessor preservation mutation accepted')
 }
}

fn build_abis_profile() NarrowProfile {
 build_class := 'android/os/Build.smali'
 properties := 'android/os/SystemProperties.smali'
 return NarrowProfile{
  name: 'build-abis'
  baseline_name: 'combined-account-webview-event-log-framework-2026-11-02-r1'
  manifest_pin: '56adef59b9210f72117709c26c5e008503379586407c70ab00297c32a70f5670'
  jar_pin: '0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad'
  baseline_classes: 2117
  providers: ['framework_build_abis.v']
  calls: {build_class: 'framework_build_abis_source', properties: 'framework_build_abi_properties_source'}
  methods: {build_class: ['<clinit>()V', 'getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;'],
   properties: ['<clinit>()V']}
  changed: {build_class: 1, properties: 1}
  added: {build_class: 1, properties: 0}
  fields: {build_class: ['.field public static final SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;',
   '.field public static final SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;']}
 }
}

fn build_abis_list_helper() string {
 return messenger_binder_m('private static getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;', 4,
  'const-string v0, ""
invoke-static {p0, v0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z
move-result v1
if-eqz v1, :split
const/4 v0, 0x0
new-array v0, v0, [Ljava/lang/String;
return-object v0
:split
invoke-virtual {v0, p1}, Ljava/lang/String;->split(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
return-object v0')
}

fn build_abis_anchor(target string) !string {
 return match target {
  'android/os/Build.smali' { 'sput-object v0, Landroid/os/Build;->SUPPORTED_ABIS:[Ljava/lang/String;' }
  'android/os/SystemProperties.smali' {
   'const-string v1, "ro.product.cpu.abilist"\nconst-string v2, "arm64-v8a"\ninvoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
  }
  else { return error('unexpected Build ABI target') }
 }
}

fn build_abis_insertion(target string) !string {
 return match target {
  'android/os/Build.smali' {
   'const-string v0, "ro.product.cpu.abilist64"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
const-string v0, "ro.product.cpu.abilist32"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;'
  }
  'android/os/SystemProperties.smali' {
   'const-string v1, "ro.product.cpu.abilist64"
const-string v2, "arm64-v8a"
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abilist32"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abi2"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
  }
  else { return error('unexpected Build ABI insertion target') }
 }
}

fn build_abis_members(old string, new string, target string) ! {
 before, after := store_parts(old)!, store_parts(new)!
 original := messenger_binder_lines(before.methods['<clinit>()V'] or { return error('original ABI initializer absent') })
 updated := after.methods['<clinit>()V'] or { return error('updated ABI initializer absent') }
 registers := if target == 'android/os/Build.smali' { 4 } else { 3 }
 anchor := build_abis_anchor(target)!
 if !original.starts_with('.method static constructor <clinit>()V\n.registers ' + registers.str() + '\n')
  || original.count(anchor) != 1 || original.contains('ro.product.cpu.abilist64')
  || original.contains('ro.product.cpu.abilist32') {
  return error('exact retained ABI initializer and unique insertion point required')
 }
 expected := original.replace(anchor, anchor + '\n' + build_abis_insertion(target)!)
 if intent_extras_method(updated)! != intent_extras_method(expected)! {
  return error('Build ABI initializer must retain every old instruction and branch around the exact insertion')
 }
 if target == 'android/os/Build.smali' {
  helper := after.methods['getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;'] or { return error('empty-aware ABI list helper absent') }
  if intent_extras_method(helper)! != intent_extras_method(build_abis_list_helper())! {
   return error('ABI list helper requires defaultempty/freshzeroarray/parameterseparator/private-static behavior')
  }
 }
}

fn build_abis_self_test() ! {
 profile := build_abis_profile()
 build_class := 'android/os/Build.smali'
 properties := 'android/os/SystemProperties.smali'
 helper := 'getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;'
 fields := ['.field public static final SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;',
  '.field public static final SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;']
 if profile.name != 'build-abis' || profile.baseline_classes != 2117
  || profile.baseline_name != 'combined-account-webview-event-log-framework-2026-11-02-r1'
  || profile.manifest_pin != '56adef59b9210f72117709c26c5e008503379586407c70ab00297c32a70f5670'
  || profile.jar_pin != '0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad'
  || profile.providers != ['framework_build_abis.v']
  || profile.calls != {build_class: 'framework_build_abis_source', properties: 'framework_build_abi_properties_source'}
  || profile.methods != {build_class: ['<clinit>()V', helper], properties: ['<clinit>()V']}
  || profile.changed != {build_class: 1, properties: 1} || profile.added != {build_class: 1, properties: 0}
  || profile.fields != {build_class: fields} || profile.class_provider != '' || profile.class_providers.len != 0
  || profile.extra_classes.len != 0 || profile.directory_provider != ''
  || profile.removed_fields.len != 0 || profile.removed_methods.len != 0 {
  return error('Build ABI profile requires two narrow initializers, two Build fields and one private helper only')
 }
 for target in [build_class, properties] {
  narrow_method_self_test(profile.methods[target]!, profile.changed[target]!, profile.added[target]!)!
  metadata := '.class public L' + target.all_before_last('.smali') + ';\n.super Ljava/lang/Object;\n.field private static retained:Ljava/lang/String;\n'
  retained := '.method public retained()V\n.registers 1\nreturn-void\n.end method\n'
  registers := if target == build_class { 4 } else { 3 }
  anchor := build_abis_anchor(target)!
  body := '.method static constructor <clinit>()V\n.registers ' + registers.str() + '\nconst/4 v0, 0x0\nif-eqz v0, :arm\nreturn-void\n:arm\n' + anchor + '\n:done\nreturn-void\n.end method\n'
  old := metadata + retained + body
  mut good := old.replace(body, body.replace(anchor, anchor + '\n' + build_abis_insertion(target)!))
  if target == build_class { good += fields.join('\n') + '\n' + build_abis_list_helper() + '\n' }
  build_abis_members(old, good, target)!
  build_abis_members(old, good.replace(':arm', ':changed_arm').replace(':done', ':changed_done').replace(':split', ':changed_split'), target)!
  narrow_member_delta(old, good, profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
  for bad in [good.replace('ro.product.cpu.abilist64', 'ro.product.cpu.abilist32'),
   good.replace('if-eqz v0, :arm', 'if-nez v0, :arm'), good.replace('.registers ' + registers.str(), '.registers 8'),
   good.replace(anchor + '\n', anchor + '\nreturn-void\n'), good.replace('const/4 v0, 0x0', 'const/4 v0, 0x1')] {
   build_abis_members(old, bad, target) or { continue }
   return error('ABI initializer property/branch/register/insertion or old-code mutation accepted')
  }
  for bad in [good.replace('public retained()V', 'private retained()V'),
   good.replace('.field private static retained:', '.field public static retained:'),
   good.replace('.super Ljava/lang/Object;', '.super Lwrong/Base;'), good + retained] {
   narrow_member_delta(old, bad, profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} }) or { continue }
   return error('Build ABI unrelated old member/field/class metadata mutation accepted')
  }
  if target == build_class {
   for bad in [good.replace('private static getStringList', 'public static getStringList'),
    good.replace('const-string v0, ""', 'const-string v0, "unknown"'),
    good.replace('if-eqz v1, :split', 'if-nez v1, :split'), good.replace('new-array v0, v0', 'new-array v0, p0'),
    good.replace('invoke-virtual {v0, p1}', 'invoke-virtual {v0, p0}'),
    good.replace('SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;', 'SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;')] {
    build_abis_members(old, bad, target) or { continue }
    return error('Build ABI helper/empty-list/default/array/field-target mutation accepted')
   }
   for bad in [good.replace(fields[0], ''), good.replace('public static final SUPPORTED_32', 'public static SUPPORTED_32'),
    good.replace(fields[1], '.field public static final SUPPORTED_32_BIT_ABIS:Ljava/lang/String;')] {
    narrow_member_delta(old, bad, profile.methods[target]!, 1, 1, fields) or { continue }
    return error('Build ABI array field membership/finality/type mutation accepted')
   }
  } else {
   for bad in [good.replace('const-string v2, ""', 'const-string v2, "armeabi-v7a"'),
    good.replace('const-string v1, "ro.product.cpu.abi2"', 'const-string v1, "ro.build.version.sdk"'),
    good.replace('const-string v1, "ro.product.cpu.abilist64"\nconst-string v2, "arm64-v8a"', 'const-string v1, "ro.product.cpu.abilist64"\nconst-string v2, "x86_64"')] {
    build_abis_members(old, bad, target) or { continue }
    return error('ARM ABI seeds advertised nonexistent 32-bit support or changed unrelated property')
   }
  }
 }
 mut before := {build_class: 'old-build', properties: 'old-properties'}
 for i in 0 .. 2115 { before['other/' + i.str() + '.smali'] = 'same' }
 mut good := before.clone()
 good[build_class] = 'new-build'
 good[properties] = 'new-properties'
 narrow_profile_class_delta(before, good, [build_class, properties], []string{}, 2117)!
 for target in [build_class, properties, 'other/0.smali'] {
  mut bad := good.clone()
  bad[target] = if target == 'other/0.smali' { 'changed' } else { before[target]! }
  narrow_profile_class_delta(before, bad, [build_class, properties], []string{}, 2117) or { continue }
  return error('Build ABI exact two-class scope mutation accepted')
 }
}

fn webview_package_profile() NarrowProfile {
 webview_class := 'android/webkit/WebView.smali'
 return NarrowProfile{
  name: 'webview-package'
  baseline_name: 'combined-account-webview-build-abis-framework-2026-11-02-r1'
  manifest_pin: '23c75e5be1445f177d7a6a801f907235d166b7a0f541c41bf0895f861bbed3e9'
  jar_pin: '251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f'
  baseline_classes: 2117
  providers: ['framework_webview_package.v']
  calls: {webview_class: 'framework_webview_package_source'}
  methods: {webview_class: ['getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;']}
  changed: {webview_class: 0}
  added: {webview_class: 1}
 }
}

fn webview_package_abi(source string) ! {
 signature := 'getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;'
 method := store_parts(source)!.methods[signature] or { return error('current Android WebView package query missing') }
 if method.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')) != [
  '.method public static ' + signature, '.registers 1', 'const/4 v0, 0x0', 'return-object v0', '.end method'] {
  return error('absent Android WebView provider requires exact public static null PackageInfo without renderer/provider/PM initialization')
 }
}

fn webview_package_self_test() ! {
 profile := webview_package_profile()
 webview_class := 'android/webkit/WebView.smali'
 signature := 'getCurrentWebViewPackage()Landroid/content/pm/PackageInfo;'
 if profile.name != 'webview-package' || profile.baseline_classes != 2117
  || profile.baseline_name != 'combined-account-webview-build-abis-framework-2026-11-02-r1'
  || profile.manifest_pin != '23c75e5be1445f177d7a6a801f907235d166b7a0f541c41bf0895f861bbed3e9'
  || profile.jar_pin != '251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f'
  || profile.providers != ['framework_webview_package.v']
  || profile.calls != {webview_class: 'framework_webview_package_source'}
  || profile.methods != {webview_class: [signature]} || profile.changed != {webview_class: 0}
  || profile.added != {webview_class: 1} || profile.fields.len != 0
  || profile.class_provider != '' || profile.class_providers.len != 0 || profile.extra_classes.len != 0
  || profile.directory_provider != '' || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('WebView package profile requires exactly one Java static query and no other API/class/field changes')
 }
 narrow_method_self_test([signature], 0, 1)!
 method := '.method public static ' + signature + '\n.registers 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
 webview_package_abi(method)!
 for bad in [method.replace('public static ', 'private static '), method.replace('public static ', 'public '),
  method.replace('public static ', 'public static native '), method.replace('public static ', 'public static final '),
  method.replace('()Landroid/content/pm/PackageInfo;', '(Landroid/content/Context;)Landroid/content/pm/PackageInfo;'),
  method.replace('.registers 1', '.registers 2'), method.replace('const/4 v0, 0x0', 'new-instance v0, Landroid/content/pm/PackageInfo;'),
  method.replace('const/4 v0, 0x0', 'invoke-static {}, Landroid/webkit/WebView;->getFactory()Ljava/lang/Object;\nmove-result-object v0'),
  method.replace('return-object v0', 'return v0'), method + method] {
  webview_package_abi(bad) or { continue }
  return error('WebView package query ABI/result or provider/renderer initialization mutation accepted')
 }
 metadata := '.class public Landroid/webkit/WebView;\n.super Landroid/view/ViewGroup;\n.field private vinixWebSettings:Landroid/webkit/WebSettings;\n.field private webViewClient:Landroid/webkit/WebViewClient;\n'
 retained := '.method private native native_destroy()V\n.end method\n.method public loadUrl(Ljava/lang/String;)V\n.registers 2\nreturn-void\n.end method\n'
 before := metadata + retained
 after := before + method
 narrow_member_delta(before, after, [signature], 0, 1, []string{})!
 for bad in [after.replace('private native native_destroy', 'private native other_destroy'),
  after.replace('public loadUrl', 'private loadUrl'), after.replace('private webViewClient:', 'public webViewClient:'),
  after.replace('.super Landroid/view/ViewGroup;', '.super Landroid/view/View;'), after + '.field private provider:Landroid/content/pm/PackageInfo;\n'] {
  narrow_member_delta(before, bad, [signature], 0, 1, []string{}) or { continue }
  return error('WebView old native/Java member, field or class metadata mutation accepted')
 }
 mut before_classes := {webview_class: 'old'}
 for i in 0 .. 2116 { before_classes['other/' + i.str() + '.smali'] = 'same' }
 mut after_classes := before_classes.clone()
 after_classes[webview_class] = 'new'
 narrow_profile_class_delta(before_classes, after_classes, [webview_class], []string{}, 2117)!
 for case in 0 .. 5 {
  mut bad := after_classes.clone()
  match case {
   0 { bad[webview_class] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(webview_class) }
   3 { bad['unrelated.smali'] = 'extra' }
   else { bad.delete(webview_class); bad['substitution.smali'] = 'new' }
  }
  narrow_profile_class_delta(before_classes, bad, [webview_class], []string{}, 2117) or { continue }
  return error('WebView-only package query class scope mutation accepted')
 }
}

fn traffic_stats_profile() NarrowProfile {
 target := 'android/net/TrafficStats.smali'
 return NarrowProfile{
  name: 'traffic-stats'
  baseline_name: 'combined-account-webview-framework-boot-framework-2026-11-03-r1'
  manifest_pin: 'af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91'
  jar_pin: 'd9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974'
  baseline_classes: 2117
  providers: ['framework_atomic_file.v']
  calls: {target: 'framework_traffic_stats_uid_source'}
  methods: {target: ['<clinit>()V', 'clearThreadStatsUid()V', 'setThreadStatsUid(I)V', 'getThreadStatsUid()I']}
  changed: {target: 2}
  added: {target: 2}
  fields: {target: ['.field private static uids:Ljava/lang/ThreadLocal;']}
 }
}

// Independent complete method bodies: the provider is never used as its own
// production oracle. Only register directives, blank lines and branch-label
// spelling may differ after API-28 DEX assembly and disassembly.
fn traffic_stats_uid_methods() map[string]string {
 owner := 'Landroid/net/TrafficStats;'
 construct := 'new-instance v0, Ljava/lang/ThreadLocal;\n' +
  'invoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n'
 return {
  '<clinit>()V': '.method static constructor <clinit>()V\n.registers 1\n' + construct +
   'sput-object v0, ' + owner + '->tags:Ljava/lang/ThreadLocal;\n' + construct +
   'sput-object v0, ' + owner + '->uids:Ljava/lang/ThreadLocal;\nreturn-void\n.end method'
  'clearThreadStatsUid()V': '.method public static clearThreadStatsUid()V\n.registers 1\n' +
   'sget-object v0, ' + owner + '->uids:Ljava/lang/ThreadLocal;\n' +
   'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->remove()V\nreturn-void\n.end method'
  'setThreadStatsUid(I)V': '.method public static setThreadStatsUid(I)V\n.registers 3\n' +
   'sget-object v0, ' + owner + '->uids:Ljava/lang/ThreadLocal;\n' +
   'invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;\nmove-result-object v1\n' +
   'invoke-virtual {v0, v1}, Ljava/lang/ThreadLocal;->set(Ljava/lang/Object;)V\nreturn-void\n.end method'
  'getThreadStatsUid()I': '.method public static getThreadStatsUid()I\n.registers 1\n' +
   'sget-object v0, ' + owner + '->uids:Ljava/lang/ThreadLocal;\n' +
   'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->get()Ljava/lang/Object;\nmove-result-object v0\n' +
   'if-nez v0, :uid\nconst/4 v0, -0x1\nreturn v0\n:uid\ncheck-cast v0, Ljava/lang/Integer;\n' +
   'invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I\nmove-result v0\nreturn v0\n.end method'
 }
}

fn traffic_stats_uid_normalized(source string, parameters int) !string {
 mut lines := source.split_into_lines().map(it.trim_space())
 for index, line in lines {
  if line == 'const/4 v0, -1' { lines[index] = 'const/4 v0, -0x1' }
 }
 return framework_boot_normalized_method(lines.join('\n'), parameters)
}

fn traffic_stats_uid_members(old string, updated string) ! {
 profile := traffic_stats_profile()
 target := 'android/net/TrafficStats.smali'
 narrow_member_delta(old, updated, profile.methods[target]!, 2, 2, profile.fields[target]!)!
 before, after := store_parts(old)!, store_parts(updated)!
 old_init := '.method static constructor <clinit>()V\n.registers 1\n' +
  'new-instance v0, Ljava/lang/ThreadLocal;\ninvoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n' +
  'sput-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\nreturn-void\n.end method'
 old_clear := '.method public static clearThreadStatsUid()V\n.registers 0\nreturn-void\n.end method'
 for signature, expected in {'<clinit>()V': old_init, 'clearThreadStatsUid()V': old_clear} {
  actual := before.methods[signature] or { return error('retained TrafficStats UID method missing') }
  if traffic_stats_uid_normalized(actual, 0)! != traffic_stats_uid_normalized(expected, 0)! {
   return error('exact retained TrafficStats tag initializer and no-op UID clear required')
  }
 }
 for signature, expected in traffic_stats_uid_methods() {
  actual := after.methods[signature] or { return error('TrafficStats UID method missing') }
  parameters := if signature == 'setThreadStatsUid(I)V' { 1 } else { 0 }
  if traffic_stats_uid_normalized(actual, parameters)! != traffic_stats_uid_normalized(expected, parameters)! {
   return error('TrafficStats UID API requires exact independent ThreadLocal state, unset sentinel and public Java ABI')
  }
 }
}

fn traffic_stats_self_test() ! {
 profile := traffic_stats_profile()
 target := 'android/net/TrafficStats.smali'
 signatures := ['<clinit>()V', 'clearThreadStatsUid()V', 'setThreadStatsUid(I)V', 'getThreadStatsUid()I']
 field := '.field private static uids:Ljava/lang/ThreadLocal;'
 if profile.name != 'traffic-stats' || profile.baseline_classes != 2117
  || profile.baseline_name != 'combined-account-webview-framework-boot-framework-2026-11-03-r1'
  || profile.manifest_pin != 'af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91'
  || profile.jar_pin != 'd9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974'
  || profile.providers != ['framework_atomic_file.v'] || profile.calls != {target: 'framework_traffic_stats_uid_source'}
  || profile.methods != {target: signatures} || profile.changed != {target: 2} || profile.added != {target: 2}
  || profile.fields != {target: [field]} || profile.class_provider != '' || profile.class_providers.len != 0
  || profile.extra_classes.len != 0 || profile.directory_provider != ''
  || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('TrafficStats profile requires one private ThreadLocal field, two changed and two added methods over exact 2117 classes')
 }
 narrow_method_self_test(signatures, 2, 2)!
 metadata := '.class public Landroid/net/TrafficStats;\n.super Ljava/lang/Object;\n' +
  '.field public static final UNSUPPORTED:I = -0x1\n.field private static tags:Ljava/lang/ThreadLocal;\n'
 retained := '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public static setThreadStatsTag(I)V\n.registers 3\nreturn-void\n.end method\n' +
  '.method public static clearThreadStatsTag()V\n.registers 1\nreturn-void\n.end method\n' +
  '.method public static getThreadStatsTag()I\n.registers 1\nconst/4 v0, -0x1\nreturn v0\n.end method\n' +
  '.method public static getUidRxBytes(I)J\n.registers 3\nconst-wide/16 v0, -0x1\nreturn-wide v0\n.end method\n' +
  '.method public static getUidTxBytes(I)J\n.registers 3\nconst-wide/16 v0, -0x1\nreturn-wide v0\n.end method\n'
 expected := traffic_stats_uid_methods()
 init := expected['<clinit>()V']!
 second := 'new-instance v0, Ljava/lang/ThreadLocal;\ninvoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n' +
  'sput-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;\n'
 old := metadata + retained + init.replace(second, '') + '\n' +
  '.method public static clearThreadStatsUid()V\n.registers 0\nreturn-void\n.end method\n'
 mut methods := ''
 mut raw_methods := ''
 for signature in signatures {
  method := expected[signature]!
  methods += method + '\n'
  locals := if signature == 'setThreadStatsUid(I)V' { 2 } else { 1 }
  registers := if signature == 'setThreadStatsUid(I)V' { 3 } else { 1 }
  raw_methods += method.replace('.registers ' + registers.str(), '.locals ' + locals.str())
   .replace(':uid', ':renamed_uid').replace('const/4 v0, -0x1', 'const/4 v0, -1') + '\n'
 }
 good := metadata + field + '\n' + retained + methods
 traffic_stats_uid_members(old, good)!
 traffic_stats_uid_members(old, metadata + field + '\n' + retained + raw_methods)!
 mut controls := 0
 getter := expected['getThreadStatsUid()I']!
 setter := expected['setThreadStatsUid(I)V']!
 clear := expected['clearThreadStatsUid()V']!
 for bad in [good.replace(field + '\n', ''), good.replace(field, field + '\n' + field),
  good.replace('private static uids:', 'public static uids:'), good.replace('private static uids:', 'private static final uids:'),
  good.replace('uids:Ljava/lang/ThreadLocal;', 'uids:Ljava/lang/InheritableThreadLocal;'),
  good.replace(init, init.replace(second, '')), good.replace(init, init.replace('->uids:', '->tags:')),
  good.replace(clear, clear.replace('->uids:', '->tags:')), good.replace(clear, clear.replace('->remove()V', '->get()Ljava/lang/Object;')),
  good.replace(setter, setter.replace('->uids:', '->tags:')), good.replace(setter, setter.replace('{p0}', '{v0}')),
  good.replace(setter, setter.replace('{v0, v1}', '{v1, v0}')), good.replace(setter, setter.replace('.registers 3', '.registers 4')),
  good.replace(getter, getter.replace('->uids:', '->tags:')), good.replace(getter, getter.replace('if-nez', 'if-eqz')),
  good.replace(getter, getter.replace('const/4 v0, -0x1', 'const/4 v0, 0x0')),
  good.replace(getter, getter.replace('()I', '()J')), good.replace(getter, getter.replace('public static ', 'private static ')),
  good.replace(getter, getter.replace('public static ', 'public static native ')),
  good.replace(getter, getter.replace('move-result v0', 'move-result v1')),
  good.replace('const-wide/16 v0, -0x1', 'const-wide/16 v0, 0x0'),
  good.replace('static getThreadStatsTag()I', 'static getThreadStatsTag()J'),
  good.replace('private static tags:', 'private static tagValues:'), good + '.field private static unrelated:I\n',
  good + '.method public static unrelated()V\n.registers 0\nreturn-void\n.end method\n'] {
  if bad == good { return error('inactive TrafficStats producer mutation') }
  traffic_stats_uid_members(old, bad) or { controls++; continue }
  return error('TrafficStats UID behavior, metadata or unrelated-body mutation accepted')
 }
 for bad_old in [old.replace('return-void\n.end method\n.method public static clearThreadStatsUid', 'nop\nreturn-void\n.end method\n.method public static clearThreadStatsUid'),
  old.replace('clearThreadStatsUid()V\n.registers 0\nreturn-void', 'clearThreadStatsUid()V\n.registers 1\nreturn-void'),
  old + field + '\n'] {
  if bad_old == old { return error('inactive TrafficStats predecessor mutation') }
  traffic_stats_uid_members(bad_old, good) or { controls++; continue }
  return error('unknown TrafficStats predecessor accepted')
 }
 mut before_classes := {target: 'old'}
 for i in 0 .. 2116 { before_classes['other/' + i.str() + '.smali'] = 'same' }
 mut after_classes := before_classes.clone()
 after_classes[target] = 'new'
 narrow_profile_class_delta(before_classes, after_classes, [target], []string{}, 2117)!
 for case in 0 .. 5 {
  mut bad := after_classes.clone()
  match case {
   0 { bad[target] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(target) }
   3 { bad['extra.smali'] = 'extra' }
   else { bad.delete(target); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before_classes, bad, [target], []string{}, 2117) or { controls++; continue }
  return error('TrafficStats-only 2117-class scope mutation accepted')
 }
 println('TRAFFIC-STATS-PRODUCER-SELFTEST-PASS controls=' + controls.str() + ' independent-UID-state exact-two-changed-two-added private-ThreadLocal raw-canonical-forms 2116-unchanged')
}

fn process_packages_profile() NarrowProfile {
 target := 'android/app/ActivityManager\$RunningAppProcessInfo.smali'
 return NarrowProfile{
  name: 'process-packages'
  baseline_name: 'combined-account-webview-traffic-stats-framework-2026-11-04-r1'
  manifest_pin: 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
  jar_pin: 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
  baseline_classes: 2117
  providers: ['framework_activity_manager.v']
  calls: {target: 'framework_process_packages_source'}
  methods: {target: []string{}}
  changed: {target: 0}
  added: {target: 0}
  fields: {target: ['.field public pkgList:[Ljava/lang/String;']}
 }
}

fn process_packages_helper_source(source string) !string {
 helper := helper_function(source, 'fn interface_class(')!
 if !helper.starts_with('fn interface_class(name string, methods []string) string {\n') {
  return error('exact interface_class helper signature required')
 }
 return 'module androidtools\n' + helper
}

fn process_packages_helper_self_test() ! {
 helper := '\nfn interface_class(name string, methods []string) string {\n return name + methods.join("")\n}\n'
 source := 'module androidtools\n' + helper + '\nfn unrelated() string {\n return "excluded"\n}\n'
 if process_packages_helper_source(source)! != 'module androidtools\n' + helper.trim_left('\n') {
  return error('process packages must extract only the single interface helper')
 }
 mut controls := 0
 for bad in [source.replace(helper, ''), source + helper,
  '\nfn interface_class(name string, methods []string) string {\n',
  source.replace('methods []string', 'methods string')] {
  if bad == source { return error('inactive process package helper mutation') }
  process_packages_helper_source(bad) or { controls++; continue }
  return error('missing, duplicate, unterminated or incompatible process package helper accepted')
 }
 println('PROCESS-PACKAGES-HELPER-SELFTEST-PASS controls=' + controls.str() + ' single-interface-helper unrelated-functions-excluded')
}

fn process_packages_original_fields() []string {
 return ['.field public static final IMPORTANCE_CACHED:I = 0x190',
  '.field public static final IMPORTANCE_FOREGROUND:I = 0x64',
  '.field public static final IMPORTANCE_FOREGROUND_SERVICE:I = 0x7d',
  '.field public static final IMPORTANCE_GONE:I = 0x3e8',
  '.field public static final IMPORTANCE_PERCEPTIBLE:I = 0xe6',
  '.field public static final IMPORTANCE_SERVICE:I = 0x12c',
  '.field public static final IMPORTANCE_VISIBLE:I = 0xc8',
  '.field public importance:I', '.field public pid:I',
  '.field public processName:Ljava/lang/String;', '.field public uid:I']
}

// Independent constructor oracle: package attribution belongs to process
// enumeration. Constructing this value object does not populate pkgList.
fn process_packages_original_methods() map[string]string {
 owner := 'Landroid/app/ActivityManager\$RunningAppProcessInfo;'
 return {
  '<init>()V': '.method public constructor <init>()V\n.registers 1\n' +
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method'
  '<init>(ILjava/lang/String;)V': '.method private constructor <init>(ILjava/lang/String;)V\n.registers 3\n' +
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ' + owner + '->pid:I\n' +
   'iput-object p2, p0, ' + owner + '->processName:Ljava/lang/String;\nreturn-void\n.end method'
  '<init>(ILjava/lang/String;Landroid/app/ActivityManager\$1;)V':
   '.method synthetic constructor <init>(ILjava/lang/String;Landroid/app/ActivityManager\$1;)V\n.registers 4\n' +
   'invoke-direct {p0, p1, p2}, ' + owner + '-><init>(ILjava/lang/String;)V\nreturn-void\n.end method'
 }
}

fn process_packages_members(old string, updated string) ! {
 field := '.field public pkgList:[Ljava/lang/String;'
 narrow_member_delta(old, updated, []string{}, 0, 0, [field])!
 before, after := store_parts(old)!, store_parts(updated)!
 metadata := before.metadata.split_into_lines().map(it.trim_space())
 if metadata.filter(it.starts_with('.class ')) != ['.class public Landroid/app/ActivityManager\$RunningAppProcessInfo;']
  || metadata.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
  || metadata.filter(it.starts_with('.field ')).sorted() != process_packages_original_fields().sorted() {
  return error('process package field requires exact original class and eleven existing fields')
 }
 expected := process_packages_original_methods()
 if before.methods.keys().sorted() != expected.keys().sorted() || after.methods.keys().sorted() != expected.keys().sorted() {
  return error('process package field must preserve exactly the three original constructors')
 }
 for signature, body in expected {
  parameters := if signature == '<init>()V' { 1 } else if signature == '<init>(ILjava/lang/String;)V' { 3 } else { 4 }
  if framework_boot_normalized_method(before.methods[signature]!, parameters)!
   != framework_boot_normalized_method(body, parameters)! {
   return error('process package field cannot change constructor behavior or add package attribution')
  }
 }
}

fn process_packages_self_test() ! {
 process_packages_helper_self_test()!
 profile := process_packages_profile()
 target := 'android/app/ActivityManager\$RunningAppProcessInfo.smali'
 field := '.field public pkgList:[Ljava/lang/String;'
 if profile.name != 'process-packages' || profile.baseline_classes != 2117
  || profile.baseline_name != 'combined-account-webview-traffic-stats-framework-2026-11-04-r1'
  || profile.manifest_pin != 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
  || profile.jar_pin != 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
  || profile.providers != ['framework_activity_manager.v'] || profile.calls != {target: 'framework_process_packages_source'}
  || profile.methods != {target: []string{}} || profile.changed != {target: 0} || profile.added != {target: 0}
  || profile.fields != {target: [field]} || profile.class_provider != '' || profile.class_providers.len != 0
  || profile.extra_classes.len != 0 || profile.directory_provider != ''
  || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('process packages profile must add one public instance String array field and no methods')
 }
 metadata := '.class public Landroid/app/ActivityManager\$RunningAppProcessInfo;\n.super Ljava/lang/Object;\n' +
  '.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/app/ActivityManager;\n.end annotation\n' +
  process_packages_original_fields().join('\n') + '\n'
 methods := process_packages_original_methods()
 mut old := metadata
 mut raw_old := metadata
 for signature in methods.keys().sorted() {
  method := methods[signature]!
  old += method + '\n'
  registers := if signature == '<init>()V' { 1 } else if signature == '<init>(ILjava/lang/String;)V' { 3 } else { 4 }
  raw_old += method.replace('.registers ' + registers.str(), '.locals 0') + '\n'
 }
 good := old + field + '\n'
 process_packages_members(old, good)!
 process_packages_members(raw_old, raw_old + field + '\n')!
 mut controls := 0
 for bad in [old, good + field + '\n', good.replace(field, '.field private pkgList:[Ljava/lang/String;'),
  good.replace(field, '.field public static pkgList:[Ljava/lang/String;'),
  good.replace(field, '.field public final pkgList:[Ljava/lang/String;'),
  good.replace(field, '.field public pkgList:Ljava/lang/String;'),
  good.replace(field, '.field public pkgList:[Ljava/lang/Object;'),
  good.replace('value = Landroid/app/ActivityManager;', 'value = Lwrong/Manager;'),
  good.replace('.field public pid:I', '.field public pid:J'),
  good + '.field private unrelated:I\n',
  good + '.method public constructor <init>(Ljava/lang/String;I[Ljava/lang/String;)V\n.registers 4\nreturn-void\n.end method\n',
  good + '.method public native unrelated()V\n.end method\n'] {
  if bad == good { return error('inactive process package field mutation') }
  process_packages_members(old, bad) or { controls++; continue }
  return error('process package field ABI or unrelated-member mutation accepted')
 }
 for signature, method in methods {
  for replacement in [method.replace('constructor ', 'static constructor '),
   method.replace('return-void', 'nop\nreturn-void'), method.replace('.registers ', '.registers 9 # ')] {
   if replacement == method { return error('inactive process package constructor mutation') }
   process_packages_members(old, good.replace(method, replacement)) or { controls++; continue }
   return error('process package constructor change accepted: ' + signature)
  }
  changed := old.replace(method, method.replace('return-void', 'nop\nreturn-void'))
  process_packages_members(changed, changed + field + '\n') or { controls++; continue }
  return error('unknown process package predecessor constructor accepted')
 }
 mut before_classes := {target: 'old', 'android/net/TrafficStats.smali': 'retained-traffic-stats'}
 for i in 0 .. 2115 { before_classes['other/' + i.str() + '.smali'] = 'same' }
 mut after_classes := before_classes.clone()
 after_classes[target] = 'new'
 narrow_profile_class_delta(before_classes, after_classes, [target], []string{}, 2117)!
 for case in 0 .. 6 {
  mut bad := after_classes.clone()
  match case {
   0 { bad[target] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(target) }
   3 { bad['extra.smali'] = 'extra' }
   4 { bad['android/net/TrafficStats.smali'] = 'changed' }
   else { bad.delete(target); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before_classes, bad, [target], []string{}, 2117) or { controls++; continue }
  return error('process packages-only 2117-class scope mutation accepted')
 }
 println('PROCESS-PACKAGES-PRODUCER-SELFTEST-PASS controls=' + controls.str() + ' one-instance-String-array three-constructors eleven-fields-preserved no-new-methods 2116-unchanged')
}

struct FrameworkBootMethod {
 signature string
 owner string
 register string
 registers int
 parameters int
}

fn framework_boot_details(target string) !FrameworkBootMethod {
 return match target {
  'android/content/res/Resources.smali' {
   FrameworkBootMethod{'getSystem()Landroid/content/res/Resources;', 'android/content/res/Resources', 'v3', 5, 0}
  }
  'android/atl/ATLLoadedApp.smali' {
   FrameworkBootMethod{'loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 'android/atl/ATLLoadedApp', 'v1', 12, 3}
  }
  else { return error('unexpected framework boot resource-loader target') }
 }
}

fn framework_boot_profile() NarrowProfile {
 resources := 'android/content/res/Resources.smali'
 loaded := 'android/atl/ATLLoadedApp.smali'
 return NarrowProfile{
  name: 'framework-boot'
  baseline_name: 'combined-account-webview-webview-package-framework-2026-11-03-r1'
  manifest_pin: 'c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a'
  jar_pin: '0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9'
  baseline_classes: 2117
  providers: ['framework_boot_classpath.v']
  calls: {resources: 'framework_boot_resources_source', loaded: 'framework_boot_loaded_source'}
  methods: {resources: ['getSystem()Landroid/content/res/Resources;'], loaded: ['loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']}
  changed: {resources: 1, loaded: 1}
  added: {resources: 0, loaded: 0}
 }
}

fn framework_boot_normalized_method(source string, parameters int) !string {
 mut lines := source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#'))
 for index, line in lines {
  if line.starts_with('.locals ') {
   lines[index] = '.registers ' + (line.all_after(' ').int() + parameters).str()
  } else if line.starts_with('.catch ') || line.starts_with('.catchall ') {
   // Separate catch-range punctuation so the existing ordinal-label oracle
   // verifies its protected start/end and handler just like branch targets.
   lines[index] = line.replace('{:', '{ :').replace('}', ' }')
  }
 }
 return intent_extras_method(lines.join('\n'))
}

fn framework_boot_old_site(details FrameworkBootMethod) string {
 return 'const-class ' + details.register + ', L' + details.owner + ';\n' +
  'invoke-virtual {' + details.register + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;\n' +
  'move-result-object ' + details.register
}

fn framework_boot_new_site(details FrameworkBootMethod) string {
 return 'invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()Ljava/lang/ClassLoader;\n' +
  'move-result-object ' + details.register
}

fn framework_boot_members(old string, updated string, target string) ! {
 details := framework_boot_details(target)!
 narrow_member_delta(old, updated, [details.signature], 1, 0, []string{})!
 before, after := store_parts(old)!, store_parts(updated)!
 original := messenger_binder_lines(before.methods[details.signature] or { return error('retained framework resource-loader method absent') })
 method := after.methods[details.signature] or { return error('updated framework resource-loader method absent') }
 lines := original.split_into_lines()
 registers := lines.filter(it.starts_with('.registers ') || it.starts_with('.locals '))
 old_site := framework_boot_old_site(details)
 if lines[0] != '.method public static ' + details.signature
  || (registers != ['.registers ' + details.registers.str()] && registers != ['.locals ' + (details.registers - details.parameters).str()])
  || original.count(old_site) != 1 || original.contains('Ljava/lang/ClassLoader;->getSystemClassLoader(') {
  return error('exact retained framework resource-loader declaration/registers and unique loader site required')
 }
 expected := original.replace(old_site, framework_boot_new_site(details))
 if framework_boot_normalized_method(method, details.parameters)! != framework_boot_normalized_method(expected, details.parameters)! {
  return error('framework resource loading may replace only its exact defining-loader pair with the system-loader getter')
 }
}

fn framework_boot_self_test() ! {
 profile := framework_boot_profile()
 resources, loaded := 'android/content/res/Resources.smali', 'android/atl/ATLLoadedApp.smali'
 if profile.name != 'framework-boot' || profile.baseline_classes != 2117
  || profile.baseline_name != 'combined-account-webview-webview-package-framework-2026-11-03-r1'
  || profile.manifest_pin != 'c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a'
  || profile.jar_pin != '0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9'
  || profile.providers != ['framework_boot_classpath.v']
  || profile.calls != {resources: 'framework_boot_resources_source', loaded: 'framework_boot_loaded_source'}
  || profile.methods != {resources: ['getSystem()Landroid/content/res/Resources;'], loaded: ['loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']}
  || profile.changed != {resources: 1, loaded: 1} || profile.added != {resources: 0, loaded: 0}
  || profile.fields.len != 0 || profile.extra_classes.len != 0 || profile.class_provider != ''
  || profile.class_providers.len != 0 || profile.directory_provider != ''
  || profile.removed_methods.len != 0 || profile.removed_fields.len != 0 {
  return error('framework boot SDK companion requires exactly two existing loader methods and no added API/state')
 }
 for target in [resources, loaded] {
  details := framework_boot_details(target)!
  narrow_method_self_test([details.signature], 1, 0)!
  metadata := '.class public LExample;\n.super Ljava/lang/Object;\n.field private retained:Ljava/lang/Object;\n'
  retained := '.method public native retainedNative()V\n.end method\n.method public retained()V\n.registers 1\nreturn-void\n.end method\n'
  method := '.method public static ' + details.signature + '\n.registers ' + details.registers.str() +
   '\nconst/4 v0, 0x0\n:loader\n:try_start\n' + framework_boot_old_site(details) +
   '\nif-eqz ' + details.register + ', :done\nnop\n:try_end\ngoto :done\n:handler\nmove-exception v0\nthrow v0\n:done\nreturn-object v0\n.catchall {:try_start .. :try_end} :handler\n.end method\n'
  before := metadata + retained + method
  changed := method.replace(framework_boot_old_site(details), framework_boot_new_site(details))
  after := metadata + retained + changed
  framework_boot_members(before, after, target)!
  framework_boot_members(before, after.replace(':loader', ':renamed_loader').replace(':done', ':renamed_done')
   .replace('.registers ' + details.registers.str(), '.locals ' + (details.registers - details.parameters).str()), target)!
  for bad in [after.replace('public static ' + details.signature, 'private static ' + details.signature),
   after.replace('invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()', 'invoke-static {}, Ljava/lang/Thread;->getContextClassLoader()'),
   after.replace('move-result-object ' + details.register, 'move-result-object v0'),
   after.replace('.registers ' + details.registers.str(), '.registers ' + (details.registers + 1).str()),
   after.replace('nop', 'const/4 v0, 0x1'), after.replace('{:try_start .. :try_end}', '{:try_start .. :done}'),
   after.replace('if-eqz ' + details.register + ', :done', 'if-eqz ' + details.register + ', :handler'),
   after.replace('retainedNative()V', 'retainedNative(I)V'),
   after + '.field private unrelated:Ljava/lang/ClassLoader;\n', before] {
   framework_boot_members(before, bad, target) or { continue }
   return error('framework boot unrelated member/instruction/register/branch/exception/state mutation accepted')
  }
  for bad_old in [before.replace(framework_boot_old_site(details), framework_boot_new_site(details)),
   before.replace('const-class ' + details.register + ', L' + details.owner + ';', 'const-class ' + details.register + ', Landroid/content/Context;')] {
   framework_boot_members(bad_old, after, target) or { continue }
   return error('framework boot missing or preexisting old loader site accepted')
  }
 }
 mut before_classes := {resources: 'old-resource', loaded: 'old-loaded'}
 for i in 0 .. 2115 { before_classes['other/' + i.str() + '.smali'] = 'same' }
 mut good := before_classes.clone()
 good[resources] = 'new-resource'
 good[loaded] = 'new-loaded'
 narrow_profile_class_delta(before_classes, good, [resources, loaded], []string{}, 2117)!
 for target in [resources, loaded, 'other/0.smali'] {
  mut bad := good.clone()
  bad[target] = if target == 'other/0.smali' { 'changed' } else { before_classes[target]! }
  narrow_profile_class_delta(before_classes, bad, [resources, loaded], []string{}, 2117) or { continue }
  return error('framework boot exact two-class change scope accepted an unrelated or missing change')
 }
}

fn intent_extras_old_methods() map[string]string {
 return {
  'putExtras(Landroid/content/Intent;)Landroid/content/Intent;': '.method public putExtras(Landroid/content/Intent;)Landroid/content/Intent;
.registers 3
invoke-virtual {p1}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v0
iput-object v0, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
return-object p0
.end method'
  'putExtras(Landroid/os/Bundle;)Landroid/content/Intent;': '.method public putExtras(Landroid/os/Bundle;)Landroid/content/Intent;
.registers 2
iput-object p1, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
return-object p0
.end method'
 }
}

fn intent_extras_expected_methods() map[string]string {
 return {
  'putExtras(Landroid/content/Intent;)Landroid/content/Intent;': '.method public putExtras(Landroid/content/Intent;)Landroid/content/Intent;
.registers 4
iget-object v0, p1, Landroid/content/Intent;->extras:Landroid/os/Bundle;
if-eqz v0, :done
iget-object v1, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
if-nez v1, :merge
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1, v0}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V
iput-object v1, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
goto :done
:merge
invoke-virtual {v1, v0}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V
:done
return-object p0
.end method'
  'putExtras(Landroid/os/Bundle;)Landroid/content/Intent;': '.method public putExtras(Landroid/os/Bundle;)Landroid/content/Intent;
.registers 3
iget-object v0, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
if-nez v0, :merge
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
iput-object v0, p0, Landroid/content/Intent;->extras:Landroid/os/Bundle;
:merge
invoke-virtual {v0, p1}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V
return-object p0
.end method'
 }
}

// Retain every instruction, register and directive; rebase only branch labels
// to instruction ordinals, including aliases emitted at one DEX address.
fn intent_extras_method(source string) !string {
 lines := source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#'))
 mut labels := map[string]string{}
 mut instruction := 0
 for line in lines {
  if line.starts_with(':') {
   if line in labels { return error('duplicate Intent extras branch label') }
   labels[line] = ':instruction_' + instruction.str()
  } else if !line.starts_with('.') { instruction++ }
 }
 mut result := []string{}
 for line in lines {
  if line.starts_with(':') { continue }
  mut parts := line.split(' ')
  for i, part in parts {
   if replacement := labels[part] { parts[i] = replacement }
   else if part.starts_with(':') { return error('undefined Intent extras branch label') }
  }
  result << parts.join(' ')
 }
 return result.join('\n')
}

fn intent_extras_members(old string, updated string) ! {
 before, after := store_parts(old)!, store_parts(updated)!
 expected := intent_extras_expected_methods()
 for signature, original in intent_extras_old_methods() {
  previous := before.methods[signature] or { return error('missing retained Intent extras overload') }
  next := after.methods[signature] or { return error('missing merged Intent extras overload') }
  if intent_extras_method(previous)! != intent_extras_method(original)!
   || intent_extras_method(next)! != intent_extras_method(expected[signature]!)! {
   return error('Intent extras require exact copy/merge instructions and null-source control flow')
  }
 }
}

fn intent_extras_self_test() ! {
 profile := intent_extras_profile()
 intent := 'android/content/Intent.smali'
 signatures := ['putExtras(Landroid/content/Intent;)Landroid/content/Intent;', 'putExtras(Landroid/os/Bundle;)Landroid/content/Intent;']
 if profile.baseline_classes != 2108 || profile.methods != {intent: signatures}
  || profile.calls.len != 0 || profile.changed != {intent: 2} || profile.added != {intent: 0}
  || profile.providers != ['framework_intent_extras.v'] || profile.directory_provider != 'framework_intent_extras'
  || profile.fields.len != 0 || profile.extra_classes.len != 0 || profile.class_provider != '' {
  return error('Intent extras profile requires exactly two changed overload bodies')
 }
 narrow_method_self_test(signatures, 2, 0)!
 previous := intent_extras_old_methods()
 expected := intent_extras_expected_methods()
 old := previous.values().join('\n')
 good := expected.values().join('\n')
 intent_extras_members(old, good)!
 intent_extras_members(old, good.replace(':merge', ':cond_copy').replace(':done', ':goto_finish'))!
 intent_extras_members(old, good.replace(':done\nreturn-object', ':done\n:alias_finish\nreturn-object').replace('goto :done', 'goto :alias_finish'))!
 for signature, body in expected {
  for invalid in [body.replace('.method public ', '.method private '),
   body.replace('.registers 4', '.registers 5').replace('.registers 3', '.registers 4'), body.replace('return-object p0', 'return-object p1'),
   body.replace('->putAll(Landroid/os/Bundle;)V', '->clear()V'),
   body.replace('new-instance ', 'const/4 '), body.replace('->extras:Landroid/os/Bundle;', '->wrong:Landroid/os/Bundle;'),
   body.replace('if-nez ', 'if-eqz '), body.replace('iput-object ', 'iget-object ')] {
   mut changed := expected.clone()
   changed[signature] = invalid
   intent_extras_members(old, changed.values().join('\n')) or { continue }
   return error('Intent extras method/register/copy/merge mutation accepted')
  }
 }
 source := expected[signatures[0]]!
 for invalid in [source.replace('iget-object v0, p1', 'iget-object v0, p0'),
  source.replace('if-eqz v0, :done', 'if-eqz v0, :merge'),
  source.replace('if-eqz v0, :done', 'if-eqz v0, :missing'),
  source.replace('{v1, v0}, Landroid/os/Bundle;-><init>', '{v1, p0}, Landroid/os/Bundle;-><init>'),
  source.replace('iput-object v1, p0', 'iput-object v0, p0'),
  source.replace('{v1, v0}, Landroid/os/Bundle;->putAll', '{v0, v1}, Landroid/os/Bundle;->putAll'),
  source.replace(':done\nreturn-object', ':done\n:done\nreturn-object')] {
  intent_extras_members(old, invalid + '\n' + expected[signatures[1]]!) or { continue }
  return error('Intent extras source aliasing/null-source/branch mutation accepted')
 }
 for invalid in [old.replace('move-result-object v0', 'move-result-object p0'),
  old.replace('iput-object p1, p0', 'iput-object p0, p1')] {
  intent_extras_members(invalid, good) or { continue }
  return error('different original Intent extras body accepted')
 }
 mut before := {intent: 'old'}
 for i in 0 .. 2107 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[intent] = 'new'
 narrow_profile_class_delta(before, after, [intent], []string{}, 2108)!
 for case in 0 .. 5 {
  mut bad := after.clone()
  match case {
   0 { bad[intent] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(intent) }
   3 { bad['extra.smali'] = 'new' }
   else { bad.delete(intent); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(before, bad, [intent], []string{}, 2108) or { continue }
  return error('invalid Intent-only class delta accepted')
 }
}

fn window_system_ui_self_test() ! {
 profile := window_system_ui_profile()
 layout := 'android/view/WindowManager$LayoutParams.smali'
 fields := profile.fields[layout]!
 if profile.baseline_classes != 2105 || profile.methods != {layout: []string{}}
  || profile.calls != {layout: 'framework_window_system_ui_source'}
  || profile.changed != {layout: 0} || profile.added != {layout: 0}
  || profile.fields != {layout: ['.field public systemUiVisibility:I']}
  || profile.providers != ['framework_window_system_ui.v']
  || profile.extra_classes.len != 0 || profile.class_provider != '' || profile.directory_provider != '' {
  return error('Window system UI requires exactly one field-only target')
 }
 before := '.class public Landroid/view/WindowManager$LayoutParams;\n.super Landroid/view/ViewGroup$LayoutParams;\n.field public flags:I\n' +
  '.method public constructor <init>()V\n.locals 0\nreturn-void\n.end method\n'
 after := before + fields.join('\n') + '\n'
 narrow_member_delta(before, after, []string{}, 0, 0, fields)!
 for bad in [before, after + fields[0] + '\n', after.replace('public systemUiVisibility:I', 'private systemUiVisibility:I'),
  after.replace('public systemUiVisibility:I', 'public static systemUiVisibility:I'),
  after.replace('public systemUiVisibility:I', 'public final systemUiVisibility:I'),
  after.replace('public systemUiVisibility:I', 'public systemUiVisibility:J'),
  after.replace('public flags:I', 'public flags:J'), after.replace('.locals 0', '.locals 1'),
  after.replace('.super Landroid/view/ViewGroup$LayoutParams;', '.super Ljava/lang/Object;'),
  after + '.method public added()V\n.locals 0\nreturn-void\n.end method\n'] {
  narrow_member_delta(before, bad, []string{}, 0, 0, fields) or { continue }
  return error('invalid Window field-only ABI or retained-member delta accepted')
 }
 mut old_classes := {layout: 'old'}
 for i in 0 .. 2104 { old_classes['other/' + i.str() + '.smali'] = 'same' }
 mut good := old_classes.clone()
 good[layout] = 'new'
 narrow_profile_class_delta(old_classes, good, [layout], []string{}, 2105)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[layout] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(layout) }
   3 { bad['unrelated.smali'] = 'added' }
   else { bad.delete(layout); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old_classes, bad, [layout], []string{}, 2105) or { continue }
  return error('invalid Window-only class delta accepted')
 }
}

fn platform_fragments_method_headers(target string) !map[string]string {
 profile := platform_fragments_profile()
 signatures := profile.methods[target] or { return error('unexpected platform fragment target') }
 mut headers := map[string]string{}
 for signature in signatures {
  flags := if signature.starts_with('<init>(') { 'public constructor' }
   else if target == 'android/app/FragmentManager.smali'
    && signature in ['vinixCancelPosted()V', 'vinixSynchronize()V', 'vinixMoveFragment(Landroid/app/Fragment;)V', 'vinixTerminalCleanup()V'] { 'private' }
   else { 'public' }
  headers[signature] = '.method ' + flags + ' ' + signature
 }
 if target == 'android/app/Activity.smali' {
  for signature in ['onStart()V', 'onStop()V', 'onDestroy()V'] {
   headers[signature] = '.method public native ' + signature
  }
 }
 return headers
}

fn platform_fragments_abi(source string, target string) ! {
 parts := store_parts(source)!
 if target == 'android/app/VinixFragmentCommit.smali' {
  expected := '.class public final Landroid/app/VinixFragmentCommit;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private manager:Landroid/app/FragmentManager;'
  if parts.metadata != expected || parts.methods.len != 2 {
   return error('unexpected platform fragment Runnable metadata or member count')
  }
  for signature, header in {
   '<init>(Landroid/app/FragmentManager;)V': '.method public constructor <init>(Landroid/app/FragmentManager;)V'
   'run()V': '.method public run()V'
  } {
   method := parts.methods[signature] or { return error('missing platform fragment Runnable member') }
   if method.all_before('\n').trim_space() != header { return error('unexpected platform fragment Runnable ABI') }
  }
  return
 }
 for signature, header in platform_fragments_method_headers(target)! {
  method := parts.methods[signature] or { return error('missing platform fragment ABI member: ' + signature) }
  if method.all_before('\n').trim_space() != header { return error('unexpected platform fragment method ABI: ' + signature) }
 }
}

fn store_parts(source string) !StoreClassParts {
 mut methods := map[string]string{}
 mut metadata := []string{}
 mut current := []string{}
 mut signature := ''
 for line in source.split_into_lines() {
  trimmed := line.trim_space()
  if trimmed.starts_with('.method ') {
   if signature != '' { return error('nested store method') }
   signature = trimmed.all_after_last(' ')
   if signature in methods { return error('duplicate store method: ' + signature) }
  }
  if signature != '' {
   current << line
   if trimmed == '.end method' {
    methods[signature] = current.join('\n')
    current = []string{}
    signature = ''
   }
  } else if trimmed != '' && !trimmed.starts_with('#') {
   if trimmed == '.end method' { return error('stray store method terminator') }
   metadata << line
  }
 }
 if signature != '' { return error('unterminated store method') }
 return StoreClassParts{methods, metadata.join('\n')}
}

fn narrow_method_delta(old string, new string, allowed []string, expected_changed int, expected_added int) ! {
 narrow_member_delta(old, new, allowed, expected_changed, expected_added, []string{})!
}

fn binder_identity_members(old string, new string, target string) ! {
 before := store_parts(old)!
 after := store_parts(new)!
 if target == 'android/os/Binder.smali' {
  for signature, fallback in {
   'clearCallingIdentity()J': 'vinixOriginalClearCallingIdentity()J'
   'restoreCallingIdentity(J)V': 'vinixOriginalRestoreCallingIdentity(J)V'
  } {
   original := before.methods[signature] or { return error('original identity method absent') }
   public_header := '.method public static ' + signature + '\n'
   if !original.starts_with(public_header)
    || !(after.methods[signature] or { '' }).starts_with(public_header) {
    return error('identity method public/static ABI changed')
   }
   expected := '.method private static ' + fallback + '\n' + original.all_after('\n')
   if (after.methods[fallback] or { '' }) != expected {
    return error('private identity fallback must preserve the complete original body')
   }
  }
 } else if target == 'android/atl/VinixAccountBrokerContext.smali' {
  for signature in ['clearCallingIdentity()J', 'restoreCallingIdentity(J)Z'] {
   if signature in before.methods
    || (after.methods[signature] or { '' }) != '.method public static native ' + signature + '\n.end method' {
    return error('identity context addition must be exactly its public static native declaration')
   }
  }
 } else {
  return error('unexpected binder identity class')
 }
}

fn binder_identity_members_self_test() ! {
 binder := 'android/os/Binder.smali'
 context := 'android/atl/VinixAccountBrokerContext.smali'
 clear := '.method public static clearCallingIdentity()J\n.registers 2\nconst-wide/16 v0, 0x0\nreturn-wide v0\n.end method\n'
 restore := '.method public static restoreCallingIdentity(J)V\n.registers 2\nreturn-void\n.end method\n'
 old := '.class public Landroid/os/Binder;\n.super Ljava/lang/Object;\n' + clear + restore
 new := old.replace('const-wide/16 v0, 0x0', 'const-wide/16 v0, 0x1')
  + clear.replace('public static clearCallingIdentity', 'private static vinixOriginalClearCallingIdentity')
  + restore.replace('public static restoreCallingIdentity', 'private static vinixOriginalRestoreCallingIdentity')
 binder_identity_members(old, new, binder)!
 for bad in [new.replace('private static vinixOriginalClearCallingIdentity', 'public static vinixOriginalClearCallingIdentity'),
  new.replace('private static vinixOriginalRestoreCallingIdentity', 'public static vinixOriginalRestoreCallingIdentity'),
  new.replace('const-wide/16 v0, 0x0', 'const-wide/16 v0, 0x2'),
  new.replace('public static clearCallingIdentity', 'private static clearCallingIdentity'),
  new.replace('public static restoreCallingIdentity', 'private static restoreCallingIdentity'),
  new.replace('vinixOriginalRestoreCallingIdentity', 'unexpectedRestoreCallingIdentity')] {
  binder_identity_members(old, bad, binder) or { continue }
  return error('invalid identity original-body or access delta accepted')
 }
 context_old := '.class public final Landroid/atl/VinixAccountBrokerContext;\n.super Ljava/lang/Object;\n'
 clear_native := '.method public static native clearCallingIdentity()J\n.end method\n'
 restore_native := '.method public static native restoreCallingIdentity(J)Z\n.end method\n'
 context_new := context_old + clear_native + restore_native
 binder_identity_members(context_old, context_new, context)!
 for bad in [context_old + clear_native, context_new.replace(' static native ', ' native '),
  context_new.replace(' native ', ' '), context_new.replace('restoreCallingIdentity(J)Z', 'restoreCallingIdentity(J)V'),
  context_new.replace('clearCallingIdentity()J\n.end method', 'clearCallingIdentity()J\n.locals 0\nreturn-void\n.end method')] {
  binder_identity_members(context_old, bad, context) or { continue }
  return error('invalid identity native declaration accepted')
 }
 mut preexisting_rejected := false
 binder_identity_members(context_new, context_new, context) or { preexisting_rejected = true }
 if !preexisting_rejected { return error('preexisting identity context natives accepted') }
}

fn narrow_member_delta(old string, new string, allowed []string, expected_changed int, expected_added int, fields []string) ! {
 before := store_parts(old)!
 after := store_parts(new)!
 mut metadata := after.metadata.split_into_lines()
 mut seen := map[string]bool{}
 for field in fields {
  if !field.starts_with('.field ') || field in seen || field in before.metadata.split_into_lines()
   || metadata.filter(it == field).len != 1 {
   return error('missing, duplicate or preexisting required field: ' + field)
  }
  seen[field] = true
  metadata = metadata.filter(it != field)
 }
 if before.metadata != metadata.join('\n') { return error('provider changed class/field metadata') }
 mut changed := 0
 mut added := 0
 for name, method in before.methods {
  if name !in after.methods { return error('provider removed method: ' + name) }
  if method != after.methods[name]! {
   if name !in allowed { return error('provider changed unrelated method: ' + name) }
   changed++
  }
 }
 for name in after.methods.keys() {
  if name !in before.methods {
   if name !in allowed { return error('provider added unrelated method: ' + name) }
   added++
  }
 }
 for name in allowed {
  if name !in after.methods { return error('missing required method: ' + name) }
 }
 if changed != expected_changed || added != expected_added { return error('unexpected provider changed/added method count') }
}

fn store_method_self_test() ! {
 narrow_method_self_test(store_methods, 4, 8)!
 narrow_method_self_test(clear_methods, 4, 1)!
 narrow_method_self_test(token_methods, 0, 5)!
 narrow_method_self_test(cache_methods, 0, 4)!
 narrow_method_self_test(description_methods, 0, 1)!
}

fn narrow_method_self_test(allowed []string, changed int, added int) ! {
 metadata := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
 unrelated := '.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + unrelated
 mut after := metadata + unrelated
 for i, name in allowed {
  method := '.method public ' + name + '\n.locals 1\nreturn-void\n.end method\n'
  if i < changed { before += method }
  after += method.replace('.locals 1', '.locals 2')
 }
 narrow_method_delta(before, after, allowed, changed, added)!
 mut count_rejected := false
 narrow_method_delta(before, after, allowed, changed, added + 1) or { count_rejected = true }
 if !count_rejected { return error('incorrect expected method count accepted') }
 for bad in [after.replace('.super Ljava/lang/Object;', '.super LOther;'),
  after.replace('public unrelated()V', 'public renamed()V'),
  after.replace('.locals 0', '.locals 3'), after + unrelated,
  after.replace('public ' + allowed.last(), 'public extra()V'),
  after + '.method public broken()V\n',
  after.replace('public ' + allowed[0], 'public renamed_target()V')] {
  narrow_method_delta(before, bad, allowed, changed, added) or { continue }
  return error('invalid store method delta accepted')
 }
}

fn digest(path string) !string {
 if os.lstat(path)!.get_filetype() != .regular { return error('regular input required: ' + path) }
 mut file := os.open(path)!
 defer { file.close() }
 mut sum := sha256.new()
 mut bytes := []u8{len: 1024 * 1024}
 for {
  n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  sum.write(bytes[..n])!
 }
 return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
 executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
 pin := digest(executable)!
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(root + '/commands/' + label + '.log', r.output)!
 write_json(root + '/commands/' + label + '.json', {
  'argv': json2.Any(argv), 'started_utc': json2.Any(started),
  'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
  'executable': json2.Any(executable), 'executable_sha256': json2.Any(pin)
 })!
 if r.exit_code != 0 { return error(label + ': ' + r.output) }
 if digest(executable)! != pin { return error('executable changed: ' + executable) }
 return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
 mut names := os.ls(root + '/' + prefix)!
 names.sort()
 for name in names {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut pins)! }
   .regular { pins[key] = digest(root + '/' + key)! }
   else { return error('nonregular build entry: ' + key) }
  }
 }
}

fn class_delta(old map[string]string, new map[string]string) ! {
 if old.len != 2098 || new.len != old.len + additions.len {
  return error('unexpected framework class set')
 }
 for name in additions {
  if name in old || name !in new { return error('unexpected added class: ' + name) }
 }
 for name in changes {
  if name !in old || name !in new || old[name]! == new[name]! {
   return error('missing required class change: ' + name)
  }
 }
 for name, pin in old {
  if name !in new || ((name in changes) == (pin == new[name]!)) {
   return error('unexpected existing class delta: ' + name)
  }
 }
}

fn jar_delta(old map[string]string, new map[string]string) ! {
 if old.len != 3 || new.len != old.len || 'classes.dex' !in old { return error('unexpected JAR members') }
 for name, pin in old {
  if name !in new || ((name == 'classes.dex') == (pin == new[name]!)) {
   return error('unexpected JAR member delta: ' + name)
  }
 }
}

fn store_class_delta(old map[string]string, new map[string]string) ! {
 narrow_class_delta(old, new, ['android/accounts/AccountManager.smali'])!
}

fn narrow_class_delta(old map[string]string, new map[string]string, targets []string) ! {
 narrow_added_class_delta(old, new, targets, []string{})!
}

fn narrow_added_class_delta(old map[string]string, new map[string]string, targets []string, extras []string) ! {
 narrow_profile_class_delta(old, new, targets, extras, 2102)!
}

fn narrow_profile_class_delta(old map[string]string, new map[string]string, targets []string, extras []string, baseline_classes int) ! {
 if old.len != baseline_classes || new.len != old.len + extras.len || targets.len == 0 {
  return error('narrow profile requires exactly ' + baseline_classes.str() + ' baseline classes and explicit targets/additions')
 }
 mut seen := map[string]bool{}
 for name in extras {
  if name in seen || name in old || name !in new || !name.ends_with('.smali') {
   return error('missing, duplicate or preexisting narrow addition: ' + name)
  }
  seen[name] = true
 }
 for name, pin in old {
  if name !in new || ((name in targets) == (pin == new[name]!)) {
   return error('unexpected narrow profile class delta: ' + name)
  }
 }
 for name in targets { if name !in old { return error('missing narrow baseline class: ' + name) } }
}

fn protected_storage_self_test() ! {
 profile := protected_storage_profile()
 targets := profile.methods.keys()
 for target in targets { narrow_method_self_test(profile.methods[target]!, profile.changed[target]!, profile.added[target]!)! }
 mut old := map[string]string{}
 for target in targets { old[target] = 'old' }
 for i in 0 .. profile.baseline_classes - targets.len { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 for target in targets { good[target] = 'new' }
 narrow_profile_class_delta(old, good, targets, []string{}, profile.baseline_classes)!
 for case in 0 .. targets.len + 4 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   targets.len { bad['other/0.smali'] = 'changed' }
   targets.len + 1 { bad.delete('other/0.smali'); bad['extra.smali'] = 'new' }
   targets.len + 2 { before.delete('other/0.smali'); bad.delete('other/0.smali') }
   targets.len + 3 { bad['extra.smali'] = 'new' }
   else { bad[targets[case]] = 'old' }
  }
  narrow_profile_class_delta(before, bad, targets, []string{}, profile.baseline_classes) or { continue }
  return error('invalid protected storage class delta accepted: ' + case.str())
 }
 metadata := '.class public LExample;\n.super Ljava/lang/Object;\n.field public dataDir:Ljava/lang/String;\n'
 method := '.method public existing()V\n.locals 0\nreturn-void\n.end method\n'
 fields := profile.fields['android/content/pm/ApplicationInfo.smali']!
 before := metadata + method
 after := metadata + fields.join('\n') + '\n' + method
 narrow_member_delta(before, after, []string{}, 0, 0, fields)!
 for bad in [before, after + fields[0] + '\n', after.replace('public deviceProtectedDataDir:', 'private deviceProtectedDataDir:'),
  after + '.field public unexpected:I\n', after.replace('public dataDir:', 'private dataDir:'),
  after.replace('Ljava/lang/Object;', 'LOther;')] {
  narrow_member_delta(before, bad, []string{}, 0, 0, fields) or { continue }
  return error('invalid protected storage field delta accepted')
 }
 narrow_member_delta(after, after, []string{}, 0, 0, fields) or {
  narrow_member_delta(before, after, []string{}, 0, 0, [fields[0], fields[0]]) or { return }
  return error('duplicate required storage field accepted')
 }
 return error('preexisting required storage fields accepted')
}

fn store_delta_self_test() ! {
 mut old := {'android/accounts/AccountManager.smali': 'old'}
 for i in 0 .. 2101 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good['android/accounts/AccountManager.smali'] = 'new'
 store_class_delta(old, good)!
 for case in 0 .. 6 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['android/accounts/AccountManager.smali'] = 'old' }
   1 { bad['other/0.smali'] = 'new' }
   2 { bad.delete('other/0.smali') }
   3 { bad['extra.smali'] = 'new' }
   4 { bad.delete('other/0.smali'); bad['extra.smali'] = 'new' }
   else {
    before.delete('android/accounts/AccountManager.smali')
    bad.delete('android/accounts/AccountManager.smali')
    before['substitution.smali'] = 'same'; bad['substitution.smali'] = 'same'
   }
  }
  store_class_delta(before, bad) or { continue }
  return error('invalid store profile class delta accepted: ' + case.str())
 }
 targets := ['android/accounts/AccountManager.smali', 'other/0.smali']
 mut two := good.clone()
 two[targets[1]] = 'new'
 narrow_class_delta(old, two, targets)!
 for bad in [good, old] {
  narrow_class_delta(old, bad, targets) or { continue }
  return error('missing one of multiple required class deltas accepted')
 }
 mut extended := good.clone()
 for name in description_classes { extended[name] = 'new class' }
 narrow_added_class_delta(old, extended, ['android/accounts/AccountManager.smali'], description_classes)!
 for case in 0 .. 5 {
  mut bad := extended.clone()
  match case {
   0 { bad.delete(description_classes[0]) }
   1 { bad.delete(description_classes[0]); bad['extra.smali'] = 'new class' }
   2 { bad['other/0.smali'] = 'changed' }
   3 { bad['android/accounts/AccountManager.smali'] = 'old' }
   else { bad.delete('other/0.smali'); bad['extra.smali'] = 'new class' }
  }
  narrow_added_class_delta(old, bad, ['android/accounts/AccountManager.smali'], description_classes) or { continue }
  return error('invalid descriptions class delta accepted')
 }
 for invalid in [[description_classes[0], description_classes[0]],
  ['android/accounts/AccountManager.smali', description_classes[0]]] {
  narrow_added_class_delta(old, extended, ['android/accounts/AccountManager.smali'], invalid) or { continue }
  return error('duplicate or preexisting descriptions class addition accepted')
 }
}

fn accessor_delta(old string, new string, declaration string) ! {
 marker := '.method ' + declaration + '\n'
 if old.contains(marker) || new.count(marker) != 1 {
  return error('missing, duplicate or preexisting interaction accessor: ' + declaration)
 }
 start := new.index(marker) or { return error('missing accessor') }
 tail := new[start..]
 end := tail.index('.end method') or { return error('unterminated interaction accessor') }
 block := tail[..end + '.end method'.len]
 if block.count('.method ') != 1 { return error('nested interaction accessor') }
 stripped := new[..start] + new[start + block.len..]
 if old.split_into_lines().filter(it.trim_space() != '').join('\n') !=
  stripped.split_into_lines().filter(it.trim_space() != '').join('\n') {
  return error('interaction accessor changed existing class code: ' + declaration)
 }
}

fn onboarding_self_test() ! {
 profile := onboarding_profile()
 targets := ['android/view/ViewGroup.smali', 'android/provider/Settings$Global.smali']
 if profile.methods.len != 2 || profile.calls.len != 2
  || profile.changed[targets[0]]! != 1 || profile.added[targets[0]]! != 0
  || profile.changed[targets[1]]! != 0 || profile.added[targets[1]]! != 1
  || profile.fields.len != 0 || profile.extra_classes.len != 0
  || profile.baseline_classes != 2104 {
  return error('onboarding profile requires exactly two narrow classes and no field or class additions')
 }
 narrow_method_self_test(profile.methods[targets[0]]!, 1, 0)!
 narrow_method_self_test(profile.methods[targets[1]]!, 0, 1)!
 mut before := {targets[0]: 'old', targets[1]: 'old'}
 for i in 0 .. 2102 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 for target in targets { after[target] = 'new' }
 narrow_profile_class_delta(before, after, targets, []string{}, 2104)!
 for case in 0 .. 7 {
  mut old := before.clone()
  mut bad := after.clone()
  match case {
   0 { bad[targets[0]] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(targets[0]); bad['substitute.smali'] = 'new' }
   3 { bad.delete('other/0.smali') }
   4 { bad['extra.smali'] = 'new' }
   5 { old.delete('other/0.smali'); bad.delete('other/0.smali') }
   else { bad[targets[1]] = 'old' }
  }
  narrow_profile_class_delta(old, bad, targets, []string{}, 2104) or { continue }
  return error('invalid onboarding class delta accepted: ' + case.str())
 }
}

fn auth_exception_self_test() ! {
 profile := auth_exception_profile()
 target := 'android/accounts/AbstractAccountAuthenticator.smali'
 if profile.methods.len != 1 || profile.calls.len != 1
  || profile.changed[target]! != 1 || profile.added[target]! != 0
  || profile.fields.len != 0 || profile.extra_classes.len != 0
  || profile.baseline_classes != 2104 {
  return error('auth exception profile requires one changed method with no field or class additions')
 }
 narrow_method_self_test(profile.methods[target]!, 1, 0)!
 mut before := {
  target: 'old'
  'android/accounts/AbstractAccountAuthenticator$Transport.smali': 'same'
  'android/accounts/AbstractAccountAuthenticator$DefaultResponse.smali': 'same'
 }
 for i in 0 .. 2101 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[target] = 'new'
 narrow_profile_class_delta(before, after, [target], []string{}, 2104)!
 for case in 0 .. 7 {
  mut old := before.clone()
  mut bad := after.clone()
  match case {
   0 { bad[target] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(target); bad['substitute.smali'] = 'new' }
   3 { bad.delete('other/0.smali') }
   4 { bad['android/accounts/AbstractAccountAuthenticator$Transport.smali'] = 'changed' }
   5 { old.delete('other/0.smali'); bad.delete('other/0.smali') }
   else { bad['android/accounts/AbstractAccountAuthenticator$DefaultResponse.smali'] = 'changed' }
  }
  narrow_profile_class_delta(old, bad, [target], []string{}, 2104) or { continue }
  return error('invalid auth exception class delta accepted: ' + case.str())
 }
}

fn binder_identity_self_test() ! {
 profile := binder_identity_profile()
 binder := 'android/os/Binder.smali'
 context := 'android/atl/VinixAccountBrokerContext.smali'
 if profile.methods.len != 2 || profile.calls.len != 2
  || profile.changed[binder]! != 2 || profile.added[binder]! != 2
  || profile.changed[context]! != 0 || profile.added[context]! != 2
  || profile.fields.len != 0 || profile.extra_classes.len != 0
  || profile.baseline_classes != 2104 {
  return error('binder identity profile requires two identity changes, two original-body helpers and two context natives')
 }
 for target, signatures in profile.methods {
  narrow_method_self_test(signatures, profile.changed[target]!, profile.added[target]!)!
 }
 binder_identity_members_self_test()!
 mut before := {
  binder: 'old'
  context: 'old'
  'android/accounts/AbstractAccountAuthenticator.smali': 'same'
 }
 for i in 0 .. 2101 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[binder] = 'new'
 after[context] = 'new'
 narrow_profile_class_delta(before, after, [binder, context], []string{}, 2104)!
 for case in 0 .. 8 {
  mut old := before.clone()
  mut bad := after.clone()
  match case {
   0 { bad[binder] = 'old' }
   1 { bad[context] = 'old' }
   2 { bad['android/accounts/AbstractAccountAuthenticator.smali'] = 'changed' }
   3 { bad.delete(binder); bad['substitute.smali'] = 'new' }
   4 { bad.delete('other/0.smali') }
   5 { bad['extra.smali'] = 'new' }
   6 { old.delete('other/0.smali'); bad.delete('other/0.smali') }
   else { bad['other/0.smali'] = 'changed' }
  }
  narrow_profile_class_delta(old, bad, [binder, context], []string{}, 2104) or { continue }
  return error('invalid binder identity class delta accepted: ' + case.str())
 }
}

fn service_lifecycle_self_test() ! {
 profile := service_lifecycle_profile()
 service := 'android/app/Service.smali'
 if profile.methods.len != 1 || profile.calls.len != 1
  || profile.changed[service]! != 3 || profile.added[service]! != 0
  || profile.fields.len != 0 || profile.extra_classes.len != 0
  || profile.baseline_classes != 2104 {
  return error('service lifecycle profile requires only three changed callbacks')
 }
 allowed := profile.methods[service]!
 narrow_method_self_test(allowed, 3, 0)!
 metadata := '.class public abstract Landroid/app/Service;\n.super Landroid/content/ContextWrapper;\n.field private retained:I\n'
 unrelated := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 mut before_methods := metadata + unrelated
 mut after_methods := metadata + unrelated
 for signature in allowed {
  method := '.method public ' + signature + '\n.locals 1\nreturn-void\n.end method\n'
  before_methods += method
  after_methods += method.replace('.locals 1', '.locals 2')
 }
 narrow_method_delta(before_methods, after_methods, allowed, 3, 0)!
 for bad in [after_methods.replace('.field private retained:I', '.field private retained:J'),
  after_methods.replace('public retained()V', 'private retained()V'),
  after_methods.replace(unrelated, ''),
  after_methods + '.method public unexpected()V\n.locals 0\nreturn-void\n.end method\n'] {
  narrow_method_delta(before_methods, bad, allowed, 3, 0) or { continue }
  return error('invalid Service member or field delta accepted')
 }
 mut before := {
  service: 'old'
  'android/os/StrictMode.smali': 'same'
  'android/os/StrictMode$ThreadPolicy.smali': 'same'
  'android/content/ContextWrapper.smali': 'same'
  'android/os/Binder.smali': 'same'
  'android/atl/VinixAccountBrokerContext.smali': 'same'
 }
 for i in 0 .. 2098 { before['other/' + i.str() + '.smali'] = 'same' }
 mut after := before.clone()
 after[service] = 'new'
 narrow_profile_class_delta(before, after, [service], []string{}, 2104)!
 for case in 0 .. 10 {
  mut old := before.clone()
  mut bad := after.clone()
  match case {
   0 { bad[service] = 'old' }
   1 { bad['android/os/StrictMode.smali'] = 'changed' }
   2 { bad['android/os/StrictMode$ThreadPolicy.smali'] = 'changed' }
   3 { bad['android/content/ContextWrapper.smali'] = 'changed' }
   4 { bad['android/os/Binder.smali'] = 'changed' }
   5 { bad['android/atl/VinixAccountBrokerContext.smali'] = 'changed' }
   6 { bad['extra.smali'] = 'new' }
   7 { bad.delete('other/0.smali') }
   8 { bad.delete(service); bad['substitute.smali'] = 'new' }
   else { old.delete('other/0.smali'); bad.delete('other/0.smali') }
  }
  narrow_profile_class_delta(old, bad, [service], []string{}, 2104) or { continue }
  return error('invalid Service-only class delta accepted: ' + case.str())
 }
}

fn platform_fragments_self_test() ! {
 profile := platform_fragments_profile()
 targets := ['android/app/Activity.smali', 'android/app/Fragment.smali',
  'android/app/FragmentManager.smali', 'android/app/FragmentTransaction.smali']
 helper := 'android/app/VinixFragmentCommit.smali'
 if profile.methods.len != 4 || profile.calls.len != 4 || profile.fields.len != 4
  || profile.baseline_classes != 2104 || profile.extra_classes != [helper]
  || profile.class_provider != 'framework_platform_fragments_classes' {
  return error('platform fragments require exactly four targets and one explicit helper')
 }
 mut changed := 0
 mut added := 0
 mut fields_count := 0
 for target in targets {
  allowed := profile.methods[target]!
  count := profile.changed[target]!
  additions_count := profile.added[target]!
  fields := profile.fields[target]!
  changed += count
  added += additions_count
  fields_count += fields.len
  narrow_method_self_test(allowed, count, additions_count)!
  headers := platform_fragments_method_headers(target)!
  metadata := '.class public LFixture;\n.super Ljava/lang/Object;\n.field private retained:I\n'
  retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
  mut before := metadata + retained
  mut after := metadata + retained
  for i, signature in allowed {
   header := headers[signature]!
   if i < count { before += header + '\n.locals 1\nreturn-void\n.end method\n' }
   after += header + '\n.locals 2\nreturn-void\n.end method\n'
  }
  if target == 'android/app/Activity.smali' {
   for signature in ['onStart()V', 'onStop()V', 'onDestroy()V'] {
    declaration := headers[signature]! + '\n.end method\n'
    before += declaration
    after += declaration
   }
  }
  after += fields.join('\n') + '\n'
  narrow_member_delta(before, after, allowed, count, additions_count, fields)!
  platform_fragments_abi(after, target)!
  for bad in [after.replace(fields[0], fields[0] + '\n' + fields[0]),
   after.replace(fields[0], ''), after + '.field private unexpected:I\n',
   after.replace('.field private retained:I', '.field private retained:J'),
   after.replace('public retained()V', 'private retained()V')] {
   narrow_member_delta(before, bad, allowed, count, additions_count, fields) or { continue }
   return error('invalid platform fragment field/member delta accepted: ' + target)
  }
  for signature, header in headers {
   bad := after.replace(header, header.replace('.method ', '.method static '))
   platform_fragments_abi(bad, target) or { continue }
   return error('invalid platform fragment method flags accepted: ' + signature)
  }
  if target == 'android/app/Activity.smali' {
   for signature in ['onStart()V', 'onStop()V', 'onDestroy()V'] {
    bad := after.replace(headers[signature]!, '.method public ' + signature)
    platform_fragments_abi(bad, target) or { continue }
    return error('removed Activity native declaration accepted')
   }
  }
 }
 if changed != 20 || added != 15 || fields_count != 14 {
  return error('platform fragment exact method/field counts differ')
 }
 helper_source := '.class public final Landroid/app/VinixFragmentCommit;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private manager:Landroid/app/FragmentManager;\n' +
  '.method public constructor <init>(Landroid/app/FragmentManager;)V\n.locals 0\nreturn-void\n.end method\n' +
  '.method public run()V\n.locals 0\nreturn-void\n.end method\n'
 platform_fragments_abi(helper_source, helper)!
 for bad in [helper_source.replace('.super Ljava/lang/Object;', '.super Landroid/app/Fragment;'),
  helper_source.replace('.class public final', '.class public'),
  helper_source.replace('.implements Ljava/lang/Runnable;', ''),
  helper_source.replace('private manager:', 'public manager:'),
  helper_source.replace('.method public run()V', '.method public native run()V'),
  helper_source.replace('.method public constructor', '.method private constructor'),
  helper_source + '.field private unexpected:I\n',
  helper_source + '.method public extra()V\n.locals 0\nreturn-void\n.end method\n'] {
  platform_fragments_abi(bad, helper) or { continue }
  return error('invalid platform fragment Runnable ABI accepted')
 }
 mut before_classes := {
  'android/app/Service.smali': 'same'
  'android/os/StrictMode.smali': 'same'
  'android/os/Binder.smali': 'same'
  'android/atl/VinixAccountBrokerContext.smali': 'same'
 }
 for target in targets { before_classes[target] = 'old' }
 for i in 0 .. 2096 { before_classes['other/' + i.str() + '.smali'] = 'same' }
 mut after_classes := before_classes.clone()
 for target in targets { after_classes[target] = 'new' }
 after_classes[helper] = 'added'
 narrow_profile_class_delta(before_classes, after_classes, targets, [helper], 2104)!
 for case in 0 .. 13 {
  mut old := before_classes.clone()
  mut bad := after_classes.clone()
  match case {
   0...3 { bad[targets[case]] = 'old' }
   4 { bad['android/app/Service.smali'] = 'changed' }
   5 { bad['android/os/StrictMode.smali'] = 'changed' }
   6 { bad['android/os/Binder.smali'] = 'changed' }
   7 { bad['android/atl/VinixAccountBrokerContext.smali'] = 'changed' }
   8 { bad.delete(helper) }
   9 { bad['unexpected.smali'] = 'added' }
   10 { bad.delete(helper); bad['substitute.smali'] = 'added' }
   11 { old[helper] = 'preexisting' }
   else { old.delete('other/0.smali'); bad.delete('other/0.smali') }
  }
  narrow_profile_class_delta(old, bad, targets, [helper], 2104) or { continue }
  return error('invalid platform fragment class delta accepted: ' + case.str())
 }
 narrow_profile_class_delta(before_classes, after_classes, targets, [helper, helper], 2104) or { return }
 return error('duplicate platform fragment helper addition accepted')
}

fn self_test() ! {
 store_delta_self_test()!
 store_method_self_test()!
 protected_storage_self_test()!
 onboarding_self_test()!
 auth_exception_self_test()!
 binder_identity_self_test()!
 service_lifecycle_self_test()!
 platform_fragments_self_test()!
 imageview_bounds_self_test()!
 window_system_ui_self_test()!
 seed_account_options_self_test()!
 persistent_data_block_self_test()!
 bitmap_tiles_self_test()!
 window_animations_self_test()!
 layout_alignment_self_test()!
 user_restrictions_self_test()!
 bundle_cross_profile_self_test()!
 resources_float_self_test()!
 paint_drawable_self_test()!
 dialog_theme_self_test()!
 intent_extras_self_test()!
 pending_intent_self_test()!
 stable_display_self_test()!
 device_secure_self_test()!
 unmanaged_queries_self_test()!
 stats_unavailable_self_test()!
 subscription_service_self_test()!
 autofill_service_self_test()!
 keyguard_policy_self_test()!
 broadcast_permission_self_test()!
 secure_settings_self_test()!
 usage_inactive_self_test()!
 messenger_binder_self_test()!
 component_parcel_self_test()!
 event_log_self_test()!
 build_abis_self_test()!
 webview_package_self_test()!
 framework_boot_self_test()!
 traffic_stats_self_test()!
 process_packages_self_test()!
 query_profile := service_query_profile()
 narrow_method_self_test(query_profile.methods['android/content/pm/PackageManager.smali']!, 1, 0)!
 boot_profile := direct_boot_profile()
 narrow_method_self_test(boot_profile.methods['android/content/pm/ComponentInfo.smali']!, 1, 0)!
 narrow_method_self_test(boot_profile.methods['android/content/pm/PackageParser.smali']!, 4, 1)!
 credential_profile := credential_storage_profile()
 for _, signatures in credential_profile.methods { narrow_method_self_test(signatures, 0, 2)! }
 restrictions_profile := application_restrictions_profile()
 narrow_method_self_test(restrictions_profile.methods['android/os/UserManager.smali']!, 0, 1)!
 broadcast_profile := broadcast_result_profile()
 for target, signatures in broadcast_profile.methods {
  narrow_method_self_test(signatures, broadcast_profile.changed[target]!, broadcast_profile.added[target]!)!
 }
 for _, fields in broadcast_profile.fields {
  original := '.class public LExample;\n.super Ljava/lang/Object;\n'
  extended := original + fields.join('\n') + '\n'
  narrow_member_delta(original, extended, []string{}, 0, 0, fields)!
  for bad in [original, extended + fields[0] + '\n', extended + '.field public extra:I\n',
   extended.replace(fields[0], fields[0] + ' = 0x0')] {
   narrow_member_delta(original, bad, []string{}, 0, 0, fields) or { continue }
   return error('invalid broadcast field metadata accepted')
  }
 }
 boot_metadata := '.class public LExample;\n.super Ljava/lang/Object;\n'
 boot_fields := boot_profile.fields['android/content/pm/ComponentInfo.smali']!
 boot_extended := boot_metadata + boot_fields[0] + '\n'
 narrow_member_delta(boot_metadata, boot_extended, []string{}, 0, 0, boot_fields)!
 for bad in [boot_metadata, boot_extended + boot_fields[0] + '\n',
  boot_extended.replace('directBootAware:Z', 'directBootAware:I'),
  boot_extended.replace('.field public ', '.field private '),
  boot_extended + '.field public extra:I\n'] {
  narrow_member_delta(boot_metadata, bad, []string{}, 0, 0, boot_fields) or { continue }
  return error('invalid direct boot field metadata accepted')
 }
 mut old := map[string]string{}
 for name in changes { old[name] = 'old' }
 for i in 0 .. 2098 - changes.len { old['other/' + i.str() + '.smali'] = 'old' }
 mut good := old.clone()
 for name in changes { good[name] = 'changed' }
 for name in additions { good[name] = 'new' }
 class_delta(old, good)!
 for case in 0 .. 8 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['other/0.smali'] = 'changed' }
   1 { bad.delete('other/0.smali') }
   2 { bad['surprise.smali'] = 'new' }
   3 { before.delete('other/0.smali'); bad.delete('other/0.smali') }
   4 { bad.delete(additions[0]) }
   5 { bad.delete(additions[0]); bad['surprise.smali'] = 'new' }
   6 { before['surprise.smali'] = 'old'; bad['surprise.smali'] = 'old' }
   else { before.delete('other/0.smali'); before[additions[0]] = 'old' }
  }
  class_delta(before, bad) or { continue }
  return error('invalid class delta accepted: ' + case.str())
 }
 for name in additions {
  mut bad := good.clone()
  bad.delete(name)
  bad['surprise.smali'] = 'new'
  class_delta(old, bad) or { continue }
  return error('missing required addition accepted: ' + name)
 }
 for name in changes {
  mut bad := good.clone()
  bad[name] = 'old'
  class_delta(old, bad) or { continue }
  return error('missing required change accepted: ' + name)
 }
 for name in changes {
  mut before := old.clone()
  mut bad := good.clone()
  before.delete(name)
  bad.delete(name)
  before['substitution.smali'] = 'old'
  bad['substitution.smali'] = 'old'
  class_delta(before, bad) or { continue }
  return error('substituted baseline change accepted: ' + name)
 }
 accessor_old := '.class public LExample;\n.super Ljava/lang/Object;\n.method public existing()V\n.locals 0\nreturn-void\n.end method\n'
 accessor := '.method public added()V\n.locals 0\nreturn-void\n.end method\n'
 accessor_delta(accessor_old, accessor_old + '\n' + accessor, 'public added()V')!
 for bad in [accessor_old, accessor_old + accessor + accessor,
  (accessor_old + accessor).replace('public existing()V', 'public changed()V'),
  (accessor_old + accessor).replace('.super Ljava/lang/Object;', '.super LOther;'),
  accessor_old + accessor.all_before('.end method'),
  accessor_old + accessor.replace('return-void', '.method private injected()V\nreturn-void')] {
  accessor_delta(accessor_old, bad, 'public added()V') or { continue }
  return error('invalid accessor-only class delta accepted')
 }
 accessor_delta(accessor_old + accessor, accessor_old + accessor, 'public added()V') or {
  jar_self_test()!
  return
 }
 return error('preexisting accessor accepted')
}

fn imageview_bounds_self_test() ! {
 profile := imageview_bounds_profile()
 image := 'android/widget/ImageView.smali'
 allowed := profile.methods[image]!
 fields := profile.fields[image]!
 if profile.baseline_classes != 2105 || profile.methods.len != 1
  || profile.calls != {image: 'framework_image_bounds_source'}
  || profile.providers != ['framework_image_bounds.v'] || profile.extra_classes.len != 0
  || profile.class_provider != '' || profile.directory_provider != '' {
  return error('ImageView bounds require exactly one target and no class additions')
 }
 narrow_method_self_test(allowed, 3, 2)!
 metadata := '.class public Landroid/widget/ImageView;\n.super Landroid/view/View;\n.field private retained:I\n'
 retained := '.method public retained()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + retained
 mut after := metadata + retained
 for i, signature in allowed {
  flags := if signature.starts_with('<init>(') { 'public constructor' } else { 'public' }
  header := '.method ' + flags + ' ' + signature
  if i < 3 { before += header + '\n.locals 1\nreturn-void\n.end method\n' }
  after += header + '\n.locals 2\nreturn-void\n.end method\n'
 }
 after += fields.join('\n') + '\n'
 narrow_member_delta(before, after, allowed, 3, 2, fields)!
 imageview_bounds_abi(after)!
 for bad in [after.replace(fields[0], ''), after.replace(fields[0], fields[0] + '\n' + fields[0]),
  after.replace(fields[1], '.field public vinixMaxHeight:I'),
  after.replace('.field private retained:I', '.field private retained:J'),
  after.replace('public retained()V', 'private retained()V'), after + '.field private unrelated:I\n'] {
  narrow_member_delta(before, bad, allowed, 3, 2, fields) or { continue }
  return error('invalid ImageView bounds field or retained-member delta accepted')
 }
 for signature in allowed {
  flags := if signature.starts_with('<init>(') { 'public constructor' } else { 'public' }
  header := '.method ' + flags + ' ' + signature
  for replacement in [header.replace('public', 'private'), header.replace('.method ', '.method static '),
   header.replace('.method ', '.method native ')] {
   imageview_bounds_abi(after.replace(header, replacement)) or { continue }
   return error('invalid ImageView bounds method flags accepted: ' + signature)
  }
 }
 mut old_classes := {image: 'old'}
 for i in 0 .. 2104 { old_classes['other/' + i.str() + '.smali'] = 'same' }
 mut good := old_classes.clone()
 good[image] = 'new'
 narrow_profile_class_delta(old_classes, good, [image], []string{}, 2105)!
 for case in 0 .. 5 {
  mut bad := good.clone()
  match case {
   0 { bad[image] = 'old' }
   1 { bad['other/0.smali'] = 'changed' }
   2 { bad.delete(image) }
   3 { bad['unrelated.smali'] = 'added' }
   else { bad.delete(image); bad['substituted.smali'] = 'new' }
  }
  narrow_profile_class_delta(old_classes, bad, [image], []string{}, 2105) or { continue }
  return error('invalid ImageView-only class delta accepted')
 }
}

// Narrow follow-ups retain the complete pinned class set and allow only their
// named method deltas. The original combined build keeps its historical ABI.
fn build_narrow(profile NarrowProfile, baseline string, manifest_pin string, jar_pin string, root string) ! {
 if profile.class_providers.len > 0 { messenger_binder_factory_main(profile)! }
 if profile.name != 'messenger-binder' && (profile.removed_methods.len > 0 || profile.removed_fields.len > 0) {
  return error('method and field removals require the dedicated Messenger oracle')
 }
 if baseline != state + profile.baseline_name
  || manifest_pin != profile.manifest_pin || jar_pin != profile.jar_pin
  || os.real_path(baseline) != baseline || !root.starts_with(state + 'combined-account-webview-' + profile.name + '-')
  || os.real_path(os.dir(root)) != os.dir(root) || os.exists(root) || os.is_link(root)
  || root.contains_any(' \n\t') {
  return error('exact sealed baseline and fresh external narrow output required')
 }
 if digest(store_compiler)! != store_compiler_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('store compiler or interaction JAR pin differs')
 }
 sealed_baseline(baseline, manifest_pin)!
 os.mkdir_all(root + '/commands')!
 command(root, 'builder-self-test', [os.executable(), '--self-test'])!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 os.mkdir_all(root + '/tools')!
 os.mkdir_all(root + '/provider-helper-inputs')!
 mut inputs := map[string]string{}
 for path in [source_file, store_compiler, os.real_path(java), os.executable(),
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
  inputs[path] = digest(path)!
 }
 os.cp(source_file, root + '/builder-source.v')!
 os.cp(os.executable(), root + '/builder')!
 os.cp(store_compiler, root + '/tools/v')!
 os.cp(baseline + '/sha256.json', root + '/baseline-sha256.json')!
 os.cp(baseline + '/build.json', root + '/baseline-build.json')!
 mut jars := os.ls(tools)!.filter(it.ends_with('.jar'))
 jars.sort()
 if jars.len == 0 { return error('no smali tool JARs') }
 mut classpath := []string{}
 for name in jars {
  path := tools + '/' + name
  inputs[path] = digest(path)!
  target := root + '/smali-tools/' + name
  os.cp(path, target)!
  if digest(target)! != inputs[path]! { return error('smali tool copy differs') }
  classpath << target
 }
 helper := repo + '/tests/native-android-tools/androidtools/framework.v'
 inputs[helper] = digest(helper)!
 for name in profile.providers {
  provider := repo + '/tests/native-android-tools/androidtools/' + name
  inputs[provider] = digest(provider)!
  os.cp(provider, root + '/provider-source/androidtools/' + name)!
  if digest(root + '/provider-source/androidtools/' + name)! != inputs[provider]! {
   return error('provider copy differs: ' + name)
  }
 }
 os.cp(helper, root + '/provider-helper-inputs/framework.v')!
 if digest(root + '/provider-helper-inputs/framework.v')! != inputs[helper]! {
  return error('provider helper copy differs')
 }
 if profile.name == 'autofill-service' {
  integration := repo + '/tests/native-android-tools/androidtools/framework_autofill.v'
  inputs[integration] = digest(integration)!
  os.cp(integration, root + '/provider-helper-inputs/framework_autofill.v')!
  if digest(root + '/provider-helper-inputs/framework_autofill.v')! != inputs[integration]! {
   return error('autofill integration source copy differs')
  }
 }
 if profile.name == 'process-packages' {
  classes := repo + '/tests/native-android-tools/androidtools/framework_classes.v'
  inputs[classes] = digest(classes)!
  os.cp(classes, root + '/provider-helper-inputs/framework_classes.v')!
  if digest(root + '/provider-helper-inputs/framework_classes.v')! != inputs[classes]! {
   return error('process packages transitive helper source copy differs')
  }
  os.write_file(root + '/provider-source/androidtools/framework_process_packages_helpers.v',
   process_packages_helper_source(os.read_file(root + '/provider-helper-inputs/framework_classes.v')!)!)!
 }
 os.write_file(root + '/provider-source/androidtools/framework_account_helpers.v',
  'module androidtools\n' + helper_function(os.read_file(root + '/provider-helper-inputs/framework.v')!, 'pub fn framework_replace_method(')!)!
 mut application := 'module main\nimport androidtools\nimport os\nfn main() {\n'
 if profile.class_providers.len > 0 { application += messenger_binder_factory_main(profile)! }
 mut targets := profile.methods.keys()
 targets.sort()
 if profile.directory_provider != '' {
  if profile.calls.len != 0 { return error('directory provider cannot also have per-class calls') }
  application += 'androidtools.' + profile.directory_provider + '(os.args[1])!\n'
 } else {
  if profile.calls.len != targets.len { return error('narrow calls differ from explicit method targets') }
  for i, target in targets {
   name := 'path' + i.str()
   application += name + ' := os.args[1] + "/' + target + '"\n'
   if profile.name == 'messenger-binder' {
    application += 'source' + i.str() + ' := androidtools.' + profile.calls[target]! + '(os.read_file(' + name + ')!)!\n'
   } else {
    application += 'os.write_file(' + name + ',androidtools.' + profile.calls[target]! + '(os.read_file(' + name + ')!)!)!\n'
   }
  }
  if profile.name == 'messenger-binder' {
   for i in 0 .. targets.len { application += 'os.write_file(path' + i.str() + ', source' + i.str() + ')!\n' }
  }
 }
 if profile.class_providers.len > 0 {
  application += 'for name, source in classes {\npath := os.args[1] + "/" + name + ".smali"\n' +
   'os.mkdir_all(os.dir(path))!\nos.write_file(path, source)!\n}\n'
 } else if profile.class_provider != '' {
  application += 'classes := androidtools.' + profile.class_provider + '()\n' +
   'expected := ' + json2.encode(profile.extra_classes.map(it.all_before_last('.smali'))) + '\n' +
   'if classes.len != expected.len { panic("unexpected added class count") }\n' +
   'for name, source in classes {\nif name !in expected { panic("unexpected added class") }\n' +
   'path := os.args[1] + "/" + name + ".smali"\n'
  if profile.directory_provider != '' {
   application += 'if os.is_link(path) || !os.is_file(path) || os.read_file(path)! != source { panic("directory provider added class differs") }\n}\n'
  } else {
   application += 'if os.exists(path) { panic("added class already exists") }\n' +
    'os.mkdir_all(os.dir(path))!\nos.write_file(path, source)!\n}\n'
  }
 } else if profile.extra_classes.len != 0 { return error('class additions require an explicit provider') }
 os.write_file(root + '/provider-source/main.v', application + '}\n')!
 os.setenv('VROOT', os.dir(store_compiler), true)
 os.setenv('V', store_compiler, true)
 os.setenv('VINIX_V_COMPILER', store_compiler, true)
 command(root, 'java-version', [java, '--version'])!
 command(root, 'v-version', [store_compiler, 'version'])!
 driver_closure := freeze_closure(root, command(root, 'builder-closure', [store_compiler, '-print-v-files', source_file])!, 'builder-closure-inputs')!
 // Smali has a small worker pool and fixed heap even on hosts with large RAM.
 command(root, 'old-disassemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', baseline + '/api-impl.jar', '-o', root + '/old-dex'])!
 command(root, 'clone-canonical-smali', ['/bin/cp', '-c', '-R', root + '/old-dex', root + '/smali'])!
 os.cp(baseline + '/api-impl.jar', root + '/api-impl.jar')!
 mut old := map[string]string{}
 inventory(root + '/old-dex', '', mut old)!
 provider_closure := freeze_closure(root, command(root, 'provider-closure', [store_compiler, '-print-v-files', '-path', root + '/provider-source|@vlib', root + '/provider-source'])!, 'provider-closure-inputs')!
 command(root, 'compile-provider', [store_compiler, '-nocache', '-cc', 'cc', '-path', root + '/provider-source|@vlib', '-o', root + '/provider', root + '/provider-source'])!
 for path, pin in provider_closure { if digest(path)! != pin { return error('store provider input changed: ' + path) } }
 command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
 mut applied := map[string]string{}
 inventory(root + '/smali', '', mut applied)!
 if profile.name == 'paint-drawable' { paint_drawable_class_delta(old, applied)! }
 else if profile.name == 'event-log' { event_log_class_delta(old, applied)! }
 else { narrow_profile_class_delta(old, applied, targets, profile.extra_classes, profile.baseline_classes)! }
 for target in targets {
  if profile.name == 'messenger-binder' {
   messenger_binder_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)!
  } else {
   narrow_member_delta(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!,
    profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
  }
  if profile.name == 'binder-identity' {
   binder_identity_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)!
  }
  if profile.name == 'platform-fragments' {
   platform_fragments_abi(os.read_file(root + '/smali/' + target)!, target)!
  }
  if profile.name == 'imageview-bounds' { imageview_bounds_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'seed-account-options' { seed_account_options_abi(target, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'persistent-data-block' { persistent_data_block_abi(target, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'bitmap-tiles' { bitmap_tiles_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'window-animations' { window_animations_abi(target, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'layout-alignment' { layout_alignment_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'user-restrictions' { user_restrictions_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'bundle-cross-profile' {
   if target == 'android/os/BaseBundle.smali' { bundle_boolean_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
   else { cross_profile_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
  }
  if profile.name == 'resources-float' { resources_float_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'dialog-theme' { dialog_theme_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'intent-extras' { intent_extras_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'pending-intent' { pending_intent_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'stable-display' { stable_display_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'device-secure' { device_secure_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'unmanaged-queries' { unmanaged_query_abi(os.read_file(root + '/smali/' + target)!, target)! }
  if profile.name == 'stats-unavailable' { stats_unavailable_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'subscription-service' { subscription_service_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)! }
  if profile.name == 'autofill-service' { autofill_service_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'keyguard-policy' { keyguard_policy_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'broadcast-permission' { broadcast_permission_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)! }
  if profile.name == 'secure-settings' { secure_settings_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'usage-inactive' { usage_inactive_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'component-parcel' { component_parcel_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'build-abis' { build_abis_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)! }
  if profile.name == 'webview-package' { webview_package_abi(os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'framework-boot' { framework_boot_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!, target)! }
  if profile.name == 'traffic-stats' { traffic_stats_uid_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
  if profile.name == 'process-packages' { process_packages_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!)! }
 }
 if profile.name == 'platform-fragments' {
  for target in profile.extra_classes { platform_fragments_abi(os.read_file(root + '/smali/' + target)!, target)! }
 }
 if profile.name == 'persistent-data-block' {
  for target in profile.extra_classes { persistent_data_block_abi(target, os.read_file(root + '/smali/' + target)!)! }
 }
 if profile.name == 'bundle-cross-profile' { cross_profile_type_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'stats-unavailable' { stats_unavailable_type_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'subscription-service' { subscription_service_type_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'broadcast-permission' { broadcast_permission_helper_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'secure-settings' { secure_settings_tile_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'component-parcel' { component_parcel_creator_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'event-log' { event_log_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!)! }
 if profile.name == 'messenger-binder' {
  for target in profile.extra_classes { messenger_binder_parts_equal(messenger_binder_new_parts(target)!, store_parts(os.read_file(root + '/smali/' + target)!)!)! }
 }
 if profile.name == 'paint-drawable' {
  raw := os.read_file(root + '/smali/' + profile.extra_classes[0])!
  paint_drawable_abi(raw, raw)!
 }
 command(root, 'assemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('store assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 if profile.name == 'paint-drawable' { paint_drawable_class_delta(old, new)! }
 else if profile.name == 'event-log' { event_log_class_delta(old, new)! }
 else { narrow_profile_class_delta(old, new, targets, profile.extra_classes, profile.baseline_classes)! }
 for target in targets {
  if profile.name == 'messenger-binder' {
   messenger_binder_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)!
  } else {
   narrow_member_delta(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!,
    profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
  }
  if profile.name == 'binder-identity' {
   binder_identity_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)!
  }
  if profile.name == 'platform-fragments' {
   platform_fragments_abi(os.read_file(root + '/new-dex/' + target)!, target)!
  }
  if profile.name == 'imageview-bounds' { imageview_bounds_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'seed-account-options' { seed_account_options_abi(target, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'persistent-data-block' { persistent_data_block_abi(target, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'bitmap-tiles' { bitmap_tiles_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'window-animations' { window_animations_abi(target, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'layout-alignment' { layout_alignment_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'user-restrictions' { user_restrictions_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'bundle-cross-profile' {
   if target == 'android/os/BaseBundle.smali' { bundle_boolean_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
   else { cross_profile_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
  }
  if profile.name == 'resources-float' { resources_float_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'dialog-theme' { dialog_theme_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'intent-extras' { intent_extras_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'pending-intent' { pending_intent_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'stable-display' { stable_display_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'device-secure' { device_secure_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'unmanaged-queries' { unmanaged_query_abi(os.read_file(root + '/new-dex/' + target)!, target)! }
  if profile.name == 'stats-unavailable' { stats_unavailable_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'subscription-service' { subscription_service_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)! }
  if profile.name == 'autofill-service' { autofill_service_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'keyguard-policy' { keyguard_policy_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'broadcast-permission' { broadcast_permission_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)! }
  if profile.name == 'secure-settings' { secure_settings_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'usage-inactive' { usage_inactive_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'component-parcel' { component_parcel_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'build-abis' { build_abis_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)! }
  if profile.name == 'webview-package' { webview_package_abi(os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'framework-boot' { framework_boot_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!, target)! }
  if profile.name == 'traffic-stats' { traffic_stats_uid_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
  if profile.name == 'process-packages' { process_packages_members(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!)! }
 }
 if profile.name == 'platform-fragments' {
  for target in profile.extra_classes { platform_fragments_abi(os.read_file(root + '/new-dex/' + target)!, target)! }
 }
 if profile.name == 'persistent-data-block' {
  for target in profile.extra_classes { persistent_data_block_abi(target, os.read_file(root + '/new-dex/' + target)!)! }
 }
 if profile.name == 'bundle-cross-profile' { cross_profile_type_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'stats-unavailable' { stats_unavailable_type_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'subscription-service' { subscription_service_type_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'broadcast-permission' { broadcast_permission_helper_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'secure-settings' { secure_settings_tile_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'component-parcel' { component_parcel_creator_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'event-log' { event_log_abi(os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)! }
 if profile.name == 'messenger-binder' {
  for target in profile.extra_classes { messenger_binder_parts_equal(messenger_binder_new_parts(target)!, store_parts(os.read_file(root + '/new-dex/' + target)!)!)! }
 }
 if profile.name == 'paint-drawable' {
  paint_drawable_abi(os.read_file(root + '/smali/' + profile.extra_classes[0])!,
   os.read_file(root + '/new-dex/' + profile.extra_classes[0])!)!
 }
 write_json(root + '/framework-dex-before.json', old)!
 write_json(root + '/framework-dex-after.json', new)!
 for pair in [[baseline + '/api-impl.jar', 'old'], [root + '/api-impl.jar', 'new']] {
  command(root, pair[1] + '-unzip', ['/usr/bin/unzip', '-q', pair[0], '-d', root + '/' + pair[1] + '-jar'])!
 }
 mut old_jar := map[string]string{}
 mut new_jar := map[string]string{}
 inventory(root + '/old-jar', '', mut old_jar)!
 inventory(root + '/new-jar', '', mut new_jar)!
 jar_delta(old_jar, new_jar)!
 sealed_baseline(baseline, manifest_pin)!
 for path, pin in driver_closure { if digest(path)! != pin { return error('store builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('store input changed: ' + path) } }
 mut build_receipt := {
  'scope': json2.Any('Narrow ' + profile.name + ' provider delta over exact sealed framework; host assembly only, no guest or Google login proof'),
  'profile': json2.Any(profile.name + '-' + new.len.str()),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any(targets), 'added_classes': json2.Any(profile.extra_classes),
  'class_count': json2.Any(new.len), 'compiler_sha256': json2.Any(store_compiler_pin),
  'changed_method_counts': json2.decode[json2.Any](json2.encode(profile.changed))!,
  'added_method_counts': json2.decode[json2.Any](json2.encode(profile.added))!,
  'added_fields': json2.decode[json2.Any](json2.encode(profile.fields))!,
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; exact V source closures, compiler and smali tool JARs retained and checked')
 }
 if profile.name == 'messenger-binder' {
  build_receipt['removed_method_counts'] = json2.decode[json2.Any](json2.encode(profile.removed_methods))!
  build_receipt['removed_fields'] = json2.decode[json2.Any](json2.encode(profile.removed_fields))!
 }
 write_json(root + '/build.json', build_receipt)!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 sealed_baseline(root, digest(root + '/sha256.json')!)!
 println('NARROW-FRAMEWORK-BUILD-PASS profile=' + profile.name + ' classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('NARROW-FRAMEWORK-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
}

fn jar_self_test() ! {
 jar_old := {'classes.dex': 'old', 'manifest': 'same', 'resources': 'same'}
 jar_good := {'classes.dex': 'new', 'manifest': 'same', 'resources': 'same'}
 jar_delta(jar_old, jar_good)!
 for case in 0 .. 4 {
  mut bad := jar_good.clone()
  match case {
   0 { bad['classes.dex'] = 'old' }
   1 { bad['manifest'] = 'changed' }
   2 { bad.delete('manifest') }
   else { bad['extra'] = 'new' }
  }
  jar_delta(jar_old, bad) or { continue }
  return error('invalid JAR delta accepted: ' + case.str())
 }
 helper := '\nfn exact() string {\n return "retained"\n}\n'
 if helper_function(helper, 'fn exact(')! != helper.trim_left('\n') { return error('helper extraction differs') }
 helper_function(helper + helper, 'fn exact(') or {
  helper_function('\nfn exact() string {\n', 'fn exact(') or {
   println('COMBINED-FRAMEWORK-SELF-TEST-PASS strict class/JAR mutations, accessor-only deltas, missing required deltas, substituted baseline classes and malformed/duplicate helpers rejected')
   return
  }
  return error('unterminated helper accepted')
 }
 return error('duplicate helper accepted')
}

fn freeze_closure(root string, listing string, destination string) !map[string]string {
 mut pins := map[string]string{}
 for path in listing.split_into_lines().filter(it.ends_with('.v')) {
  pins[path] = digest(path)!
  target := root + '/' + destination + '/' + path.trim_left('/')
  os.mkdir_all(os.dir(target))!
  os.cp(path, target)!
  if digest(target)! != pins[path]! { return error('closure copy differs: ' + path) }
 }
 if pins.len == 0 { return error('empty V source closure') }
 write_json(root + '/' + destination + '.json', pins)!
 return pins
}

fn valid_pin(pin string) bool {
 return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn sealed_baseline(root string, pin string) ! {
 if !valid_pin(pin) || digest(root + '/sha256.json')! != pin {
  return error('sealed baseline manifest differs')
 }
 expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
 mut actual := map[string]string{}
 inventory(root, '', mut actual)!
 actual.delete('sha256.json')
 if actual != expected { return error('sealed baseline file set or checksums differ') }
}

fn helper_function(source string, signature string) !string {
 marker := '\n' + signature
 if source.count(marker) != 1 { return error('unique helper required: ' + signature) }
 start := (source.index(marker) or { return error('missing helper: ' + signature) }) + 1
 tail := source[start..]
 end := tail.index('\n}') or { return error('unterminated helper: ' + signature) }
 return tail[..end + 2] + '\n'
}

fn provider_main() string {
 return 'module main\nimport androidtools\nimport os\nfn main() {\nr := os.args[1]\n' +
  'classes := androidtools.framework_account_client_classes()\n' +
  'for name,source in classes {\npath := r + "/" + name + ".smali"\n' +
  'if !os.is_file(path) { panic("missing baseline account class " + name) }\nos.write_file(path,source)!\n}\n' +
  'manager := r + "/android/accounts/AccountManager.smali"\n' +
  'os.write_file(manager, androidtools.framework_account_client_addition(os.read_file(manager)!)!)!\n' +
  'androidtools.framework_account_broker_context(r)!\n' +
  'for name,source in androidtools.framework_account_native_response_classes() {\n' +
  'path := r + "/" + name + ".smali"\nif os.exists(path) { panic("native response already exists") }\n' +
  'os.write_file(path,source)!\n}\n' +
  'web := r + "/android/webkit/"\n' +
  'patched := androidtools.framework_webview_sources(os.read_file(web + "WebView.smali")!,\n' +
  'os.read_file(web + "WebSettings.smali")!,os.read_file(web + "WebViewClient.smali")!,\n' +
  'os.read_file(web + "CookieManager.smali")!)!\n' +
  'for name,source in patched { os.write_file(web + name + ".smali",source)! }\n' +
  'if os.exists(web + "VinixCookieCallback.smali") { panic("cookie callback already exists") }\n' +
  'os.write_file(web + "VinixCookieCallback.smali",androidtools.framework_webview_callback())!\n' +
  'for name,accessor in {\n' +
  '"android/app/PendingIntent": androidtools.framework_account_interaction_pending_accessor()\n' +
  '"android/accounts/AccountAuthenticatorResponse": androidtools.framework_account_interaction_response_accessor()\n' +
  '"android/os/Bundle": androidtools.framework_account_interaction_bundle_accessor()\n} {\n' +
  'path := r + "/" + name + ".smali"\nsource := os.read_file(path)!\n' +
  'declaration := accessor.all_before("\\n")\n' +
  'if !declaration.starts_with(".method ") || source.contains(declaration + "\\n") { panic("preexisting or invalid accessor " + name) }\n' +
  'os.write_file(path,source + "\\n" + accessor)!\n}\n' +
  'for name,source in androidtools.framework_account_interaction_classes() {\n' +
  'path := r + "/" + name + ".smali"\nif os.exists(path) { panic("interaction helper already exists") }\n' +
  'os.write_file(path,source)!\n}\n}\n'
}

fn build(baseline string, manifest_pin string, jar_pin string, root string) ! {
 if !valid_pin(manifest_pin) || !valid_pin(jar_pin) { return error('SHA256 pins required') }
 if !baseline.starts_with(state + 'account-contract-') || os.real_path(baseline) != baseline
  || !root.starts_with(state + 'combined-account-webview-') || os.real_path(os.dir(root)) != os.dir(root)
  || os.exists(root) || os.is_link(root) || root.contains_any(' \n\t') {
  return error('canonical baseline and fresh external combined-account-webview output required')
 }
 if digest(baseline + '/sha256.json')! != manifest_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('sealed framework baseline differs')
 }
 sealed_baseline(baseline, manifest_pin)!
 os.mkdir_all(root + '/commands')!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 mut inputs := map[string]string{}
 for path in [source_file, compiler, os.real_path(java), os.executable(),
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
  inputs[path] = digest(path)!
 }
 os.cp(source_file, root + '/builder-source.v')!
 os.cp(os.executable(), root + '/builder')!
 os.cp(baseline + '/sha256.json', root + '/baseline-sha256.json')!
 os.cp(baseline + '/build.json', root + '/baseline-build.json')!
 mut jars := os.ls(tools)!.filter(it.ends_with('.jar'))
 jars.sort()
 if jars.len == 0 { return error('no smali tool JARs') }
 mut classpath := []string{}
 for name in jars {
  path := tools + '/' + name
  inputs[path] = digest(path)!
  target := root + '/smali-tools/' + name
  os.cp(path, target)!
  if digest(target)! != inputs[path]! { return error('smali tool copy differs') }
  classpath << target
 }
 for name in providers {
  path := repo + '/tests/native-android-tools/androidtools/' + name
  inputs[path] = digest(path)!
  os.cp(path, root + '/provider-source/androidtools/' + name)!
  if digest(root + '/provider-source/androidtools/' + name)! != inputs[path]! {
   return error('provider copy differs: ' + name)
  }
 }
 // Providers share these self-contained helpers with the full framework
 // generator. Retain their complete originals and compile exact
 // function bytes without importing the unrelated framework generators.
 mut helpers := 'module androidtools\n'
 os.mkdir_all(root + '/provider-helper-inputs')!
 for pair in [['framework.v', 'pub fn framework_replace_method('],
  ['framework_classes.v', 'fn interface_class('],
  ['framework_signatures.v', 'fn signature_method('],
  ['framework_bundle_parcel.v', 'fn bundle_parcel_method('],
  ['framework_bundle_parcel.v', 'fn bundle_parcel_lock(']] {
  name := pair[0]
  signature := pair[1]
  path := repo + '/tests/native-android-tools/androidtools/' + name
  target := root + '/provider-helper-inputs/' + name
  if path !in inputs {
   inputs[path] = digest(path)!
   os.cp(path, target)!
  }
  if digest(path)! != inputs[path]! || digest(target)! != inputs[path]! { return error('helper copy differs') }
  helpers += '\n' + helper_function(os.read_file(target)!, signature)!
 }
 os.write_file(root + '/provider-source/androidtools/framework_account_helpers.v', helpers)!
 os.write_file(root + '/provider-source/main.v', provider_main())!
 os.setenv('VROOT', '/Users/alex/code/v', true)
 os.setenv('V', compiler, true)
 os.setenv('VINIX_V_COMPILER', compiler, true)
 command(root, 'java-version', [java, '--version'])!
 command(root, 'v-version', [compiler, 'version'])!
 driver_closure := freeze_closure(root, command(root, 'builder-closure', [compiler, '-print-v-files', source_file])!, 'builder-closure-inputs')!
 command(root, 'old-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', baseline + '/api-impl.jar', '-o', root + '/old-dex'])!
 command(root, 'clone-canonical-smali', ['/bin/cp', '-c', '-R', root + '/old-dex', root + '/smali'])!
 os.cp(baseline + '/api-impl.jar', root + '/api-impl.jar')!
 mut old := map[string]string{}
 inventory(root + '/old-dex', '', mut old)!
 provider_closure := freeze_closure(root, command(root, 'provider-closure', [compiler, '-print-v-files', '-path', root + '/provider-source|@vlib', root + '/provider-source'])!, 'provider-closure-inputs')!
 command(root, 'compile-provider', [compiler, '-cc', 'cc', '-path', root + '/provider-source|@vlib', '-o', root + '/provider', root + '/provider-source'])!
 for path, pin in provider_closure { if digest(path)! != pin { return error('provider input changed: ' + path) } }
 command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
 mut applied := map[string]string{}
 inventory(root + '/smali', '', mut applied)!
 // Raw generated formatting can differ from baksmali. The canonical delta is
 // checked after assembly/disassembly; no non-smali input is accepted here.
 if applied.len != 2098 + additions.len || applied.keys().any(!it.ends_with('.smali')) {
  return error('unexpected provider class set')
 }
 command(root, 'assemble', [java, '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 class_delta(old, new)!
 for name, declaration in accessors {
  accessor_delta(os.read_file(root + '/old-dex/' + name)!,
   os.read_file(root + '/new-dex/' + name)!, declaration)!
 }
 write_json(root + '/framework-dex-before.json', old)!
 write_json(root + '/framework-dex-after.json', new)!
 for pair in [[baseline + '/api-impl.jar', 'old'], [root + '/api-impl.jar', 'new']] {
  command(root, pair[1] + '-unzip', ['/usr/bin/unzip', '-q', pair[0], '-d', root + '/' + pair[1] + '-jar'])!
 }
 mut old_jar := map[string]string{}
 mut new_jar := map[string]string{}
 inventory(root + '/old-jar', '', mut old_jar)!
 inventory(root + '/new-jar', '', mut new_jar)!
 jar_delta(old_jar, new_jar)!
 sealed_baseline(baseline, manifest_pin)!
 for path, pin in driver_closure { if digest(path)! != pin { return error('builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('Combined account client, broker context/response/interaction and WebView framework; source and assembly validation only, no Google login success claim'),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any(changes), 'added_classes': json2.Any(additions), 'class_count': json2.Any(new.len),
  'accessor_only_classes': json2.decode[json2.Any](json2.encode(accessors))!,
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; V source closures and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 sealed_baseline(root, digest(root + '/sha256.json')!)!
 println('COMBINED-FRAMEWORK-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('COMBINED-FRAMEWORK-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
 if os.args.len == 4 && os.args[1] == '--check' {
  sealed_baseline(os.abs_path(os.args[2]), os.args[3]) or { eprintln(err); exit(1) }
  println('COMBINED-FRAMEWORK-INTEGRITY-PASS ' + os.args[3])
  return
 }
 if os.args.len == 6 && os.args[1] == '--seed-account-options' {
  build_narrow(seed_account_options_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--persistent-data-block' {
  build_narrow(persistent_data_block_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--bitmap-tiles' {
  build_narrow(bitmap_tiles_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--window-animations' {
  build_narrow(window_animations_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--layout-alignment' {
  build_narrow(layout_alignment_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--user-restrictions' {
  build_narrow(user_restrictions_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--bundle-cross-profile' {
  build_narrow(bundle_cross_profile_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--resources-float' {
  build_narrow(resources_float_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--paint-drawable' {
  build_narrow(paint_drawable_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--dialog-theme' {
  build_narrow(dialog_theme_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--intent-extras' {
  build_narrow(intent_extras_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--pending-intent' {
  build_narrow(pending_intent_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--stable-display' {
  build_narrow(stable_display_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--device-secure' {
  build_narrow(device_secure_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--unmanaged-queries' {
  build_narrow(unmanaged_queries_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--stats-unavailable' {
  build_narrow(stats_unavailable_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--subscription-service' {
  build_narrow(subscription_service_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--autofill-service' {
  build_narrow(autofill_service_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--keyguard-policy' {
  build_narrow(keyguard_policy_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--broadcast-permission' {
  build_narrow(broadcast_permission_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--secure-settings' {
  build_narrow(secure_settings_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--usage-inactive' {
  build_narrow(usage_inactive_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--messenger-binder' {
  build_narrow(messenger_binder_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--component-parcel' {
  build_narrow(component_parcel_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--event-log' {
  build_narrow(event_log_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--build-abis' {
  build_narrow(build_abis_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--webview-package' {
  build_narrow(webview_package_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--framework-boot' {
  build_narrow(framework_boot_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--traffic-stats' {
  build_narrow(traffic_stats_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == '--process-packages' {
  build_narrow(process_packages_profile(), os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] in ['--store', '--auth', '--cache', '--descriptions', '--protected-storage', '--service-query', '--direct-boot', '--credential-storage', '--broadcast-result', '--onboarding', '--application-restrictions', '--auth-exception', '--binder-identity', '--service-lifecycle', '--platform-fragments', '--imageview-bounds', '--window-system-ui'] {
  profile := match os.args[1] { '--store' { storage_profile() } '--auth' { auth_profile() } '--cache' { cache_profile() } '--descriptions' { descriptions_profile() } '--protected-storage' { protected_storage_profile() } '--service-query' { service_query_profile() } '--direct-boot' { direct_boot_profile() } '--credential-storage' { credential_storage_profile() } '--broadcast-result' { broadcast_result_profile() } '--application-restrictions' { application_restrictions_profile() } '--auth-exception' { auth_exception_profile() } '--binder-identity' { binder_identity_profile() } '--service-lifecycle' { service_lifecycle_profile() } '--platform-fragments' { platform_fragments_profile() } '--imageview-bounds' { imageview_bounds_profile() } '--window-system-ui' { window_system_ui_profile() } else { onboarding_profile() } }
  build_narrow(profile, os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len != 5 { eprintln('usage: combined-account-webview-build [--store|--auth|--cache|--descriptions|--protected-storage|--service-query|--direct-boot|--credential-storage|--broadcast-result|--onboarding|--application-restrictions|--auth-exception|--binder-identity|--service-lifecycle|--platform-fragments|--imageview-bounds|--window-system-ui|--bitmap-tiles|--window-animations|--layout-alignment|--user-restrictions|--bundle-cross-profile|--resources-float|--paint-drawable|--dialog-theme|--intent-extras|--pending-intent|--stable-display|--device-secure|--unmanaged-queries|--stats-unavailable|--subscription-service|--autofill-service|--keyguard-policy|--broadcast-permission|--secure-settings|--usage-inactive|--messenger-binder|--component-parcel|--event-log|--build-abis|--webview-package|--framework-boot|--traffic-stats|--process-packages] BASELINE BASELINE_MANIFEST_SHA256 BASELINE_JAR_SHA256 FRESH_OUTPUT | --self-test'); exit(2) }
 build(os.abs_path(os.args[1]), os.args[2], os.args[3], os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
