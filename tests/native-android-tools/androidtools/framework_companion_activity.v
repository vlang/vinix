// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn companion_activity_method(signature string, locals int, body string) string {
	return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn companion_activity_original(source string, signature string) !string {
	mut result := ''
	for block in source.split('.method ')[1..] {
		declaration := block.all_before('\n')
		if !declaration.ends_with(' ' + signature) { continue }
		if result != '' { return error('duplicate Activity routing method: ' + signature) }
		end := block.index('.end method') or { return error('unterminated routing method: ' + signature) }
		result = '.method ' + block[..end + '.end method'.len]
	}
	if result == '' { return error('missing Activity routing method: ' + signature) }
	return result
}

pub fn framework_companion_activity_class_names() []string {
	return ['android/app/Activity', 'android/atl/ATLLoadedAppManager', 'android/app/Activity$2']
}

fn companion_activity_validate_class(source string, declaration string, parent string) ! {
	classes := source.split_into_lines().filter(it.starts_with('.class '))
	supers := source.split_into_lines().filter(it.starts_with('.super '))
	if classes != [declaration] || supers != ['.super ' + parent] {
		return error('unexpected companion Activity input class: ' + declaration)
	}
	if source.count('.method ') != source.count('.end method') {
		return error('unbalanced companion Activity input methods')
	}
}

// Preserve the old primary bootstrap API. Explicit launches instead resolve
// using the actual caller's package before consulting cached companion apps.
// The pinned parser has no <queries> model; its existing package policy is
// retained. Parent recreation while a child result is pending is outside this
// patch: recreation preserves a child's own caller and cached result instead.
pub fn framework_companion_activity_sources(activity string, manager string, finish_task string) !(string, string, string) {
	companion_activity_validate_class(activity, '.class public Landroid/app/Activity;', 'Landroid/view/ContextThemeWrapper;')!
	companion_activity_validate_class(manager, '.class public final Landroid/atl/ATLLoadedAppManager;', 'Ljava/lang/Object;')!
	companion_activity_validate_class(finish_task, '.class Landroid/app/Activity$2;', 'Ljava/lang/Object;')!
	for source in [activity, manager, finish_task] {
		for reserved in ['vinixCreateActivity', 'vinixRecreateActivity', 'vinixGetActivityApplication',
			'vinixDispatchActivityResult', 'vinixResult', 'vinixLoadActivityApplication',
			'vinixActivityPackageVisible', 'vinixStartImplicitActivityForResult'] {
			if source.contains(reserved) {
				return error('companion Activity routing already exists: ' + reserved)
			}
		}
	}
	// Replacing an absent framework method silently adds one. These methods are
	// required input contracts, so reject drift before generating any output.
	for signature in [
		'startActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V',
		'setResult(ILandroid/content/Intent;)V',
		'finish()V',
		'getCallingPackage()Ljava/lang/String;',
		'internalCreateActivity(Ljava/lang/String;JLandroid/content/Intent;)Landroid/app/Activity;',
	] {
		companion_activity_original(activity, signature)!
	}
	for name in ['resultActivity:Landroid/app/Activity;', 'resultRequestCode:I', 'finishing:Z'] {
		declarations := activity.split_into_lines().filter(it.starts_with('.field ') && it.ends_with(' ' + name))
		if declarations != ['.field private ' + name] {
			return error('unexpected Activity routing field: ' + name)
		}
	}
	for field in [
		'.field private static final always_visible_packages:Ljava/util/HashSet;',
		'.field private static final always_allow_query_all_packages:Ljava/util/HashSet;',
	] {
		name := field.all_after_last(' ')
		declarations := manager.split_into_lines().filter(it.starts_with('.field ') && it.ends_with(' ' + name))
		if declarations != [field] { return error('unexpected Activity package policy field') }
	}
	owners := finish_task.split_into_lines().filter(it.starts_with('.field ') && it.ends_with(' this$0:Landroid/app/Activity;'))
	if owners != ['.field final synthetic this$0:Landroid/app/Activity;'] {
		return error('unexpected Activity finish owner field')
	}
	mut app := activity + '\n.field private vinixResultCode:I\n.field private vinixResultData:Landroid/content/Intent;\n.field private vinixResultDelivered:Z\n'
	app += companion_activity_method('public static vinixCreateActivity(Landroid/app/Activity;Landroid/content/Intent;J)Landroid/app/Activity;', 7, '
invoke-static {p0}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :missing
invoke-virtual {p0}, Landroid/app/Activity;->get_atl_loaded_app()Landroid/atl/ATLLoadedApp;
move-result-object v1
invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-static {v1, v2}, Landroid/atl/ATLLoadedAppManager;->vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;
move-result-object v2
if-eqz v2, :missing
iget-object v3, v2, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v4, v3, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget-boolean v4, v4, Landroid/content/pm/ApplicationInfo;->enabled:Z
if-eqz v4, :missing
invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v0
iget-object v3, v3, Landroid/content/pm/PackageParser$Package;->activities:Ljava/util/ArrayList;
invoke-virtual {v3}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v3
:next
invoke-interface {v3}, Ljava/util/Iterator;->hasNext()Z
move-result v4
if-eqz v4, :missing
invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/content/pm/PackageParser$Activity;
iget-object v5, v4, Landroid/content/pm/PackageParser$Activity;->className:Ljava/lang/String;
invoke-virtual {v0, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :next
iget-object v4, v4, Landroid/content/pm/PackageParser$Activity;->info:Landroid/content/pm/ActivityInfo;
iget-boolean v5, v4, Landroid/content/pm/ComponentInfo;->enabled:Z
if-eqz v5, :missing
if-eq v1, v2, :allowed
iget-boolean v5, v4, Landroid/content/pm/ComponentInfo;->exported:Z
if-eqz v5, :denied
iget-object v5, v4, Landroid/content/pm/ActivityInfo;->permission:Ljava/lang/String;
if-eqz v5, :allowed
invoke-virtual {v5}, Ljava/lang/String;->isEmpty()Z
move-result v5
if-eqz v5, :denied
:allowed
new-instance v3, Landroid/content/Intent;
invoke-direct {v3, p1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
invoke-virtual {v2}, Landroid/atl/ATLLoadedApp;->vinixEnsureApplicationStarted()V
invoke-virtual {v2, v0, v3}, Landroid/atl/ATLLoadedApp;->createActivity(Ljava/lang/String;Landroid/content/Intent;)Landroid/app/Activity;
move-result-object v0
iget-object v1, v0, Landroid/app/Activity;->window:Landroid/view/Window;
invoke-virtual {v1, p2, p3}, Landroid/view/Window;->set_native_window(J)V
return-object v0
:missing
new-instance v0, Landroid/content/ActivityNotFoundException;
const-string v1, "Explicit activity is unavailable"
invoke-direct {v0, v1}, Landroid/content/ActivityNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
:denied
new-instance v0, Ljava/lang/SecurityException;
const-string v1, "Cross-package activity access is denied"
invoke-direct {v0, v1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
throw v0')
	app += companion_activity_method('public static vinixRecreateActivity(Landroid/app/Activity;J)Landroid/app/Activity;', 5, '
invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
move-result-object v0
new-instance v1, Landroid/content/Intent;
if-eqz v0, :empty
invoke-direct {v1, v0}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
goto :component
:empty
invoke-direct {v1}, Landroid/content/Intent;-><init>()V
:component
invoke-virtual {p0}, Landroid/app/Activity;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v3
invoke-virtual {v3}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v3
invoke-virtual {v1, v2, v3}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
invoke-static {p0, v1, p1, p2}, Landroid/app/Activity;->vinixCreateActivity(Landroid/app/Activity;Landroid/content/Intent;J)Landroid/app/Activity;
move-result-object v0
return-object v0')
	start_signature := 'startActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V'
	original := companion_activity_original(activity, start_signature)!
	// Preserve the existing external URI/file chooser path, without its leading
	// Intent/extras log. Its explicit-component branch is replaced in full.
	fallback_anchor := '    :cond_62\n'
	if original.count(fallback_anchor) != 1 || original.count(':goto_57') < 2 {
		return error('unexpected implicit Activity launch fallback')
	}
	fallback := original.all_after(fallback_anchor).all_before_last('.end method')
	app += companion_activity_method('private vinixStartImplicitActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V', 5,
		'const/4 v4, 0\n' + fallback + '\n:goto_57\nreturn-void')
	app = framework_replace_method(app, start_signature, companion_activity_method('public ' + start_signature, 5, '
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-nez v0, :explicit
invoke-direct {p0, p1, p2, p3}, Landroid/app/Activity;->vinixStartImplicitActivityForResult(Landroid/content/Intent;ILandroid/os/Bundle;)V
return-void
:explicit
invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;
move-result-object v0
iget-wide v2, v0, Landroid/view/Window;->native_window:J
:create
invoke-static {p0, p1, v2, v3}, Landroid/app/Activity;->vinixCreateActivity(Landroid/app/Activity;Landroid/content/Intent;J)Landroid/app/Activity;
move-result-object v0
:created
.catch Ljava/lang/ReflectiveOperationException; {:create .. :created} :creation_failed
iput p2, v0, Landroid/app/Activity;->resultRequestCode:I
iput-object p0, v0, Landroid/app/Activity;->resultActivity:Landroid/app/Activity;
new-instance v1, Landroid/app/Activity$1;
invoke-direct {v1, p0, v0}, Landroid/app/Activity$1;-><init>(Landroid/app/Activity;Landroid/app/Activity;)V
invoke-virtual {p0, v1}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V
return-void
:creation_failed
move-exception v0
new-instance v1, Landroid/content/ActivityNotFoundException;
const-string v2, "Explicit activity could not be constructed"
invoke-direct {v1, v2}, Landroid/content/ActivityNotFoundException;-><init>(Ljava/lang/String;)V
throw v1'))!
	app = framework_replace_method(app, 'setResult(ILandroid/content/Intent;)V', companion_activity_method('public synchronized setResult(ILandroid/content/Intent;)V', 1, '
iget-boolean v0, p0, Landroid/app/Activity;->finishing:Z
if-nez v0, :done
iput p1, p0, Landroid/app/Activity;->vinixResultCode:I
iput-object p2, p0, Landroid/app/Activity;->vinixResultData:Landroid/content/Intent;
:done
return-void'))!
	app = framework_replace_method(app, 'finish()V', companion_activity_method('public synchronized finish()V', 2, '
iget-boolean v0, p0, Landroid/app/Activity;->finishing:Z
if-nez v0, :done
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/Activity;->finishing:Z
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v1, Landroid/app/Activity$2;
invoke-direct {v1, p0}, Landroid/app/Activity$2;-><init>(Landroid/app/Activity;)V
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
:done
return-void'))!
	app += companion_activity_method('public synchronized vinixDispatchActivityResult()V', 4, '
iget-boolean v0, p0, Landroid/app/Activity;->vinixResultDelivered:Z
if-nez v0, :done
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/Activity;->vinixResultDelivered:Z
iget-object v0, p0, Landroid/app/Activity;->resultActivity:Landroid/app/Activity;
if-eqz v0, :done
iget v1, p0, Landroid/app/Activity;->resultRequestCode:I
if-ltz v1, :done
iget v2, p0, Landroid/app/Activity;->vinixResultCode:I
iget-object v3, p0, Landroid/app/Activity;->vinixResultData:Landroid/content/Intent;
invoke-virtual {v0, v1, v2, v3}, Landroid/app/Activity;->onActivityResult(IILandroid/content/Intent;)V
:done
return-void')
	app = framework_replace_method(app, 'getCallingPackage()Ljava/lang/String;', companion_activity_method('public getCallingPackage()Ljava/lang/String;', 1, '
iget v0, p0, Landroid/app/Activity;->resultRequestCode:I
if-ltz v0, :none
iget-object v0, p0, Landroid/app/Activity;->resultActivity:Landroid/app/Activity;
if-eqz v0, :none
invoke-virtual {v0}, Landroid/app/Activity;->getPackageName()Ljava/lang/String;
move-result-object v0
return-object v0
:none
const/4 v0, 0
return-object v0'))!
	// Reuse the installed-APK loader, but remove its primary-caller visibility
	// gate. The only entry point to this private copy validates the actual caller
	// before both cache lookup and loading.
	loader := companion_activity_original(manager, 'loadApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;')!
	loader_anchor := '    :cond_10\n'
	if loader.count(loader_anchor) != 1 || !loader.contains('    :goto_f\n    return-object v1') {
		return error('unexpected Activity application loader')
	}
	mut packages := manager + companion_activity_method('private static vinixLoadActivityApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 7,
		'const/4 v1, 0\ngoto :cond_10\n:goto_f\nreturn-object v1\n:cond_10\n' + loader.all_after(loader_anchor).all_before_last('.end method'))
	packages += companion_activity_method('private static vinixActivityPackageVisible(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Z', 3, '
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v1, v0, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :visible
iget-object v2, v0, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget v2, v2, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
const/16 v0, 30
if-lt v2, v0, :visible
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v0, v0, Landroid/content/pm/PackageParser$Package;->requestedPermissions:Ljava/util/ArrayList;
const-string v2, "android.permission.QUERY_ALL_PACKAGES"
invoke-virtual {v0, v2}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :visible
sget-object v0, Landroid/atl/ATLLoadedAppManager;->always_visible_packages:Ljava/util/HashSet;
invoke-virtual {v0, p1}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :visible
sget-object v0, Landroid/atl/ATLLoadedAppManager;->always_allow_query_all_packages:Ljava/util/HashSet;
invoke-virtual {v0, v1}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z
move-result v0
return v0
:visible
const/4 v0, 1
return v0')
	packages += companion_activity_method('public static vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 2, '
invoke-static {p0, p1}, Landroid/atl/ATLLoadedAppManager;->vinixActivityPackageVisible(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Z
move-result v0
if-eqz v0, :missing
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v0, v0, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :companion
return-object p0
:companion
invoke-static {p1}, Landroid/atl/ATLLoadedAppManager;->peekAppFromPackageName(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;
move-result-object v0
if-nez v0, :found
invoke-static {p1}, Landroid/atl/ATLLoadedAppManager;->vinixLoadActivityApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;
move-result-object v0
:found
return-object v0
:missing
const/4 v0, 0
return-object v0')
	// The finish runnable sends the cached result before nativeFinish resumes the
	// parent, including cancellation when setResult was never called.
	finish := companion_activity_original(finish_task, 'run()V')!
	anchor := '    const-wide/16 v4, 0x0'
	if finish.count(anchor) != 1 { return error('unexpected Activity finish runnable') }
	task := finish_task.replace(anchor, '    iget-object v0, p0, Landroid/app/Activity$2;->this$0:Landroid/app/Activity;\n    invoke-virtual {v0}, Landroid/app/Activity;->vinixDispatchActivityResult()V\n\n' + anchor)
	return app, packages, task
}

fn framework_companion_activities(smali string) ! {
	activity := smali + '/android/app/Activity.smali'
	manager := smali + '/android/atl/ATLLoadedAppManager.smali'
	task := smali + '/android/app/Activity$2.smali'
	app, packages, finish := framework_companion_activity_sources(os.read_file(activity)!, os.read_file(manager)!, os.read_file(task)!)!
	os.write_file(activity, app)!
	os.write_file(manager, packages)!
	os.write_file(task, finish)!
}
