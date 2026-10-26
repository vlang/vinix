// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Vinix has one private app root, without a separate Android unlock/encryption
// lifecycle. Keep ordinary app data there and isolate device-protected data in
// a private child. Metadata and Context must select the same directory.
pub fn framework_protected_storage(smali string) ! {
	info_path := smali + '/android/content/pm/ApplicationInfo.smali'
	mut info := os.read_file(info_path)!
	for field in ['credentialProtectedDataDir', 'deviceProtectedDataDir'] {
		if info.contains('.field public ' + field + ':') {
			return error('protected storage field already exists: ' + field)
		}
		info += '\n.field public ' + field + ':Ljava/lang/String;\n'
	}
	if info.contains('vinixSetDataDirectory(') { return error('protected storage helper already exists') }
	signature := '.method public constructor <init>(Landroid/content/pm/ApplicationInfo;)V'
	start := info.index(signature) or { return error('ApplicationInfo copy constructor missing') }
	end := start + info[start..].index('.end method') or { return error('ApplicationInfo copy constructor end missing') }
	body := info[start..end]
	if body.count('    return-void') != 1 { return error('ApplicationInfo copy constructor return changed') }
	mut copy := ''
	for field in ['credentialProtectedDataDir', 'deviceProtectedDataDir'] {
		copy += '    iget-object v0, p1, Landroid/content/pm/ApplicationInfo;->' + field + ':Ljava/lang/String;\n' +
			'    iput-object v0, p0, Landroid/content/pm/ApplicationInfo;->' + field + ':Ljava/lang/String;\n'
	}
	info = info[..start] + body.replace('    return-void', copy + '    return-void') + info[end..]
	info += '
.method public final vinixSetDataDirectory(Ljava/lang/String;)V
.locals 2
iput-object p1, p0, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
iput-object p1, p0, Landroid/content/pm/ApplicationInfo;->credentialProtectedDataDir:Ljava/lang/String;
move-object v0, p1
if-eqz p1, :store
new-instance v0, Ljava/io/File;
const-string v1, "device_protected"
invoke-direct {v0, p1, v1}, Ljava/io/File;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v0
:store
iput-object v0, p0, Landroid/content/pm/ApplicationInfo;->deviceProtectedDataDir:Ljava/lang/String;
return-void
.end method
'
	manager_path := smali + '/android/atl/ATLLoadedAppManager.smali'
	manager := os.read_file(manager_path)!
	assignment := 'iput-object v4, v0, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;'
	if manager.count(assignment) != 2 { return error('application data directory assignments changed') }
	patched_manager := manager.replace(assignment,
		'invoke-virtual {v0, v4}, Landroid/content/pm/ApplicationInfo;->vinixSetDataDirectory(Ljava/lang/String;)V')
	context_path := smali + '/android/content/Context.smali'
	mut context := os.read_file(context_path)!
	if context.count('.method private getDataDirFile()Ljava/io/File;') != 1 {
		return error('Context data directory method changed')
	}
	initial := 'iput-object v2, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;'
	if context.count(initial) != 1 { return error('primary Context data directory assignment changed') }
	context = context.replace(initial,
		'invoke-virtual {v1, v2}, Landroid/content/pm/ApplicationInfo;->vinixSetDataDirectory(Ljava/lang/String;)V')
	context = framework_replace_method(context, 'getDataDirFile()Ljava/io/File;', '.method private getDataDirFile()Ljava/io/File;
.locals 3
iget-object v0, p0, Landroid/content/Context;->data_dir:Ljava/io/File;
if-nez v0, :ready
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
invoke-virtual {p0}, Landroid/content/Context;->isDeviceProtectedStorage()Z
move-result v2
if-eqz v2, :credential
iget-object v1, v1, Landroid/content/pm/ApplicationInfo;->deviceProtectedDataDir:Ljava/lang/String;
goto :path
:credential
iget-object v2, v1, Landroid/content/pm/ApplicationInfo;->credentialProtectedDataDir:Ljava/lang/String;
if-nez v2, :credential_path
iget-object v2, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
:credential_path
move-object v1, v2
:path
if-nez v1, :create
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "Application data directory is unavailable"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:create
new-instance v0, Ljava/io/File;
invoke-direct {v0, v1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
const/4 v1, 0
invoke-direct {p0, v0, v1}, Landroid/content/Context;->vinixEnsurePrivateDirectory(Ljava/io/File;I)Ljava/io/File;
move-result-object v0
iput-object v0, p0, Landroid/content/Context;->data_dir:Ljava/io/File;
:ready
return-object v0
.end method')!
	impl_path := smali + '/android/app/ContextImpl.smali'
	original_impl := os.read_file(impl_path)!
	if original_impl.count('.method public createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;') != 1 ||
		original_impl.count('.method private constructor <init>(Landroid/content/res/Resources;Landroid/atl/ATLLoadedApp;Landroid/content/res/Resources$Theme;I)V') != 1 {
		return error('ContextImpl configuration context or flags constructor changed')
	}
	impl := framework_replace_method(original_impl,
		'createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;',
		'.method public createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;
.locals 5
iget-object v0, p0, Landroid/app/ContextImpl;->atl_loaded_app:Landroid/atl/ATLLoadedApp;
const/4 v1, 0
invoke-virtual {v0, v1, p1}, Landroid/atl/ATLLoadedApp;->createResources(Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)Landroid/content/res/Resources;
move-result-object v1
iget-object v2, p0, Landroid/app/ContextImpl;->atl_loaded_app:Landroid/atl/ATLLoadedApp;
invoke-virtual {p0}, Landroid/app/ContextImpl;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v3
iget v4, p0, Landroid/app/ContextImpl;->atl_flags:I
new-instance v0, Landroid/app/ContextImpl;
invoke-direct {v0, v1, v2, v3, v4}, Landroid/app/ContextImpl;-><init>(Landroid/content/res/Resources;Landroid/atl/ATLLoadedApp;Landroid/content/res/Resources$Theme;I)V
return-object v0
.end method')!
	// Validate every anchor before writing any class, so a rejected baseline
	// cannot leave an apparently usable partial extension.
	os.write_file(info_path, info)!
	os.write_file(manager_path, patched_manager)!
	os.write_file(context_path, context)!
	os.write_file(impl_path, impl)!
}
