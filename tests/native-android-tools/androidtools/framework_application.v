// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_application_startup(smali string) ! {
	path := smali + '/android/atl/ATLLoadedApp.smali'
	os.write_file(path, os.read_file(path)! + '\n.field private vinixApplicationState:I\n' +
		'.method public native vinixEnsureApplicationStarted()V\n.end method\n')!
	// A service constructor can already read globals set by Application.onCreate.
	// Loading a package context alone does not start that package's Application.
	runnable := smali + '/android/atl/ATLLoadedApp$1.smali'
	mut text := os.read_file(runnable)!
	anchor := '    :try_start_0\n    iget-object v0, p0, Landroid/atl/ATLLoadedApp$1;->this$0:Landroid/atl/ATLLoadedApp;'
	if text.count(anchor) != 1 { return error('unexpected ATL service startup') }
	text = text.replace(anchor, anchor + '\n\n    invoke-virtual {v0}, Landroid/atl/ATLLoadedApp;->vinixEnsureApplicationStarted()V')
	os.write_file(runnable, text)!
	context := smali + '/android/content/Context.smali'
	os.write_file(context, framework_replace_method(os.read_file(context)!,
		'getApplicationContext()Landroid/content/Context;', '.method public getApplicationContext()Landroid/content/Context;
.locals 1
invoke-virtual {p0}, Landroid/content/Context;->get_atl_loaded_app()Landroid/atl/ATLLoadedApp;
move-result-object v0
invoke-virtual {v0}, Landroid/atl/ATLLoadedApp;->getApplication()Landroid/app/Application;
move-result-object v0
return-object v0
.end method')!)!
	impl := smali + '/android/app/ContextImpl.smali'
	os.write_file(impl, framework_replace_method(os.read_file(impl)!,
		'bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z', '.method public bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
.locals 2
if-nez p2, :lookup
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "ServiceConnection must not be null"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:lookup
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;
move-result-object v0
if-eqz v0, :missing
invoke-virtual {v0, p1, p2}, Landroid/atl/ATLLoadedApp;->startOrBindService(Landroid/content/Intent;Landroid/content/ServiceConnection;)Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :missing
const/4 v0, 1
return v0
:missing
const/4 v0, 0
return v0
.end method')!)!
	// Android 11 introduced package filtering for target SDK 30 and newer.
	// Older callers and QUERY_ALL_PACKAGES must also see installed companions.
	manager := smali + '/android/atl/ATLLoadedAppManager.smali'
	os.write_file(manager, framework_replace_method(os.read_file(manager)!,
		'isPackageVisible(Ljava/lang/String;Ljava/lang/String;)Z', '.method private static isPackageVisible(Ljava/lang/String;Ljava/lang/String;)Z
.locals 3
invoke-virtual {p0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :visible
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v0
iget-object v0, v0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v1, v0, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
invoke-virtual {p0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :policy
iget-object v1, v0, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget v1, v1, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
const/16 v2, 30
if-lt v1, v2, :visible
iget-object v0, v0, Landroid/content/pm/PackageParser$Package;->requestedPermissions:Ljava/util/ArrayList;
const-string v1, "android.permission.QUERY_ALL_PACKAGES"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :visible
:policy
sget-object v0, Landroid/atl/ATLLoadedAppManager;->always_visible_packages:Ljava/util/HashSet;
invoke-virtual {v0, p1}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :visible
sget-object v0, Landroid/atl/ATLLoadedAppManager;->always_allow_query_all_packages:Ljava/util/HashSet;
invoke-virtual {v0, p0}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z
move-result v0
return v0
:visible
const/4 v0, 1
return v0
.end method')!)!
}
