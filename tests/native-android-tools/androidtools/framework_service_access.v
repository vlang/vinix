// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_service_access_class_names() []string {
	return ['android/app/ContextImpl']
}

// Ordinary explicit Context calls use the ContextImpl's loaded-app owner. That
// owner is the runtime's compatibility model, not an unforgeable APK identity.
// Reuse the Activity package resolver: it checks that owner before cache lookup.
// The pinned parser has no <queries> model. Implicit service behavior is retained.
// No permission grants or privileged authenticator/broker exception is inferred.
pub fn framework_service_access_sources(context string) !string {
	companion_activity_validate_class(context, '.class public final Landroid/app/ContextImpl;', 'Landroid/content/Context;')!
	if context.contains('vinixGetServiceTarget') || context.contains(':vinix_explicit_service') {
		return error('explicit service access routing already exists')
	}
	owners := context.split_into_lines().filter(it.starts_with('.field ') && it.ends_with(' atl_loaded_app:Landroid/atl/ATLLoadedApp;'))
	if owners != ['.field private final atl_loaded_app:Landroid/atl/ATLLoadedApp;'] {
		return error('unexpected service Context owner field')
	}
	lookup := 'invoke-direct {p0, p1}, Landroid/app/ContextImpl;->atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;'
	bind_signature := 'bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z'
	start_signature := 'startService(Landroid/content/Intent;)Landroid/content/ComponentName;'
	bind := companion_activity_original(context, bind_signature)!
	start := companion_activity_original(context, start_signature)!
	companion_activity_original(context, 'atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;')!
	if bind.count(lookup) != 1 || !bind.contains('Landroid/atl/VinixServiceBinding;->register(')
		|| !bind.contains('if-eqz v0, :missing') {
		return error('unexpected service binding routing')
	}
	if start.count('    .registers 6\n') != 1 || start.count(lookup) != 1
		|| start.count('->nativeStartExternalService(') != 1 {
		return error('unexpected service start routing')
	}
	mut output := framework_replace_method(context, bind_signature, bind.replace(lookup,
		'invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixGetServiceTarget(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;'))!
	// Explicit misses must return null, without the external-service fallback or
	// legacy GCM receiver registration in the original implicit path.
	guard := '
    invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
    move-result-object v0
    if-eqz v0, :vinix_explicit_service_legacy
    invoke-direct {p0, p1}, Landroid/app/ContextImpl;->vinixGetServiceTarget(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;
    move-result-object v0
    if-eqz v0, :vinix_explicit_service_missing
    const/4 v1, 0
    invoke-virtual {v0, p1, v1}, Landroid/atl/ATLLoadedApp;->startOrBindService(Landroid/content/Intent;Landroid/content/ServiceConnection;)Landroid/content/ComponentName;
    move-result-object v0
    return-object v0
    :vinix_explicit_service_missing
    const/4 v0, 0
    return-object v0
    :vinix_explicit_service_legacy
'
	output = framework_replace_method(output, start_signature,
		start.replace('    .registers 6\n', '    .registers 6\n' + guard))!
	output += companion_activity_method('private vinixGetServiceTarget(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;', 8, '
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-nez v0, :explicit
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;
move-result-object v0
return-object v0
:explicit
invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v2
invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
iget-object v1, p0, Landroid/app/ContextImpl;->atl_loaded_app:Landroid/atl/ATLLoadedApp;
invoke-static {v1, v0}, Landroid/atl/ATLLoadedAppManager;->vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;
move-result-object v3
if-eqz v3, :missing
iget-object v4, v3, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v7, v4, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget-boolean v7, v7, Landroid/content/pm/ApplicationInfo;->enabled:Z
if-eqz v7, :missing
iget-object v5, v4, Landroid/content/pm/PackageParser$Package;->services:Ljava/util/ArrayList;
invoke-virtual {v5}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v5
:next
invoke-interface {v5}, Ljava/util/Iterator;->hasNext()Z
move-result v7
if-eqz v7, :missing
invoke-interface {v5}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v6
check-cast v6, Landroid/content/pm/PackageParser$Service;
iget-object v6, v6, Landroid/content/pm/PackageParser$Service;->info:Landroid/content/pm/ServiceInfo;
iget-object v7, v6, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v7
if-eqz v7, :next
iget-object v7, v6, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
invoke-virtual {v2, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v7
if-eqz v7, :next
iget-boolean v7, v6, Landroid/content/pm/ComponentInfo;->enabled:Z
if-eqz v7, :missing
iget-object v7, v1, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v7, v7, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
invoke-virtual {v0, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v7
if-nez v7, :allowed
iget-boolean v7, v6, Landroid/content/pm/ComponentInfo;->exported:Z
if-eqz v7, :denied
iget-object v7, v6, Landroid/content/pm/ServiceInfo;->permission:Ljava/lang/String;
if-eqz v7, :allowed
invoke-virtual {v7}, Ljava/lang/String;->isEmpty()Z
move-result v7
if-eqz v7, :denied
:allowed
return-object v3
:missing
const/4 v0, 0
return-object v0
:denied
new-instance v0, Ljava/lang/SecurityException;
const-string v1, "Cross-package service access is denied"
invoke-direct {v0, v1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
throw v0')
	return output
}

fn framework_service_access(smali string) ! {
	path := smali + '/android/app/ContextImpl.smali'
	os.write_file(path, framework_service_access_sources(os.read_file(path)!)!)!
}
