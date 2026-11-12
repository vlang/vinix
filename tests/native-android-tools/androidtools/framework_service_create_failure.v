// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Named companion processes currently share ART. A secondary service's failed
// onCreate must not tear down the primary application's looper or enter the
// running-service cache. Primary-process failures retain their propagation.
pub fn framework_service_create_failure(smali string) ! {
	app := smali + '/android/atl/ATLLoadedApp.smali'
	runner := smali + r'/android/atl/ATLLoadedApp$1.smali'
	mut owner := os.read_file(app)!
	mut dispatch := os.read_file(runner)!
	if owner.contains('vinixCreateService') || dispatch.contains(':vinix_service_created') {
		return error('service creation boundary already installed')
	}
	call := 'invoke-virtual {v0}, Landroid/app/Service;->onCreate()V'
	if dispatch.count(call) != 1 || !dispatch.contains('.method public run()V\n    .registers 6') {
		return error('unexpected service creation dispatch')
	}
	dispatch = dispatch.replace(call, r'
iget-object v1, p0, Landroid/atl/ATLLoadedApp$1;->this$0:Landroid/atl/ATLLoadedApp;
iget-object v2, p0, Landroid/atl/ATLLoadedApp$1;->val$className:Ljava/lang/String;
invoke-virtual {v1, v0, v2}, Landroid/atl/ATLLoadedApp;->vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
move-result v1
if-nez v1, :vinix_service_created
iget-object v0, p0, Landroid/atl/ATLLoadedApp$1;->val$serviceConnection:Landroid/content/ServiceConnection;
if-eqz v0, :vinix_service_failed
check-cast v0, Landroid/atl/VinixServiceBinding;
const/4 v1, 0
iput-boolean v1, v0, Landroid/atl/VinixServiceBinding;->active:Z
:vinix_service_failed
return-void
:vinix_service_created')
	owner += r'
.method public vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
.locals 4
:create
invoke-virtual {p1}, Landroid/app/Service;->onCreate()V
:created
const/4 v0, 1
return v0
:failed
move-exception v0
invoke-virtual {p1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v1
invoke-virtual {v1, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :primary_failure
invoke-direct {p0, p2}, Landroid/atl/ATLLoadedApp;->vinixSecondaryServiceProcess(Ljava/lang/String;)Z
move-result v1
if-eqz v1, :primary_failure
const-string v1, "ATLLoadedApp"
const-string v2, "Creation failed in cohosted secondary service: "
invoke-virtual {v2, p2}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v2
invoke-static {v1, v2, v0}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I
const/4 v0, 0
return v0
:primary_failure
throw v0
.catch Ljava/lang/RuntimeException; {:create .. :created} :failed
.end method
.method private vinixSecondaryServiceProcess(Ljava/lang/String;)Z
.locals 6
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
if-eqz v0, :primary
iget-object v1, v0, Landroid/content/pm/PackageParser$Package;->services:Ljava/util/ArrayList;
if-eqz v1, :primary
invoke-virtual {v1}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v1
:next
invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :primary
invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/content/pm/PackageParser$Service;
iget-object v2, v2, Landroid/content/pm/PackageParser$Service;->info:Landroid/content/pm/ServiceInfo;
if-eqz v2, :next
iget-object v3, v2, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
if-eqz v3, :next
invoke-virtual {v3, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :next
iget-object v3, v0, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
if-eqz v3, :primary
iget-object v4, v2, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :primary
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v1
if-eqz v1, :primary
iget-object v1, v1, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
if-eqz v1, :primary
iget-object v4, v1, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
if-eqz v4, :primary
invoke-virtual {v3, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :secondary
iget-object v0, v1, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
if-eqz v0, :primary
iget-object v0, v0, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
if-nez v0, :primary_process
move-object v0, v4
:primary_process
iget-object v1, v2, Landroid/content/pm/ComponentInfo;->processName:Ljava/lang/String;
if-eqz v1, :primary
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :primary
:secondary
const/4 v0, 1
return v0
:primary
const/4 v0, 0
return v0
.end method
'
	os.write_file(app, owner)!
	// bindService has already accepted this registration. Cancel delivery but
	// retain the request until the caller's normal unbind releases it.
	os.write_file(runner, dispatch)!
}
