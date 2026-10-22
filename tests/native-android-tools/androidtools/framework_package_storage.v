// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_package_storage(smali string) ! {
	manager := smali + '/android/atl/ATLLoadedAppManager.smali'
	mut text := os.read_file(manager)!
	anchor := 'iput-object v4, v0, Landroid/content/pm/ApplicationInfo;->sourceDir:Ljava/lang/String;'
	if text.count(anchor) != 1 { return error('companion source directory assignment changed') }
	text = text.replace(anchor, anchor + '
iput-object v4, v0, Landroid/content/pm/ApplicationInfo;->publicSourceDir:Ljava/lang/String;
new-instance v6, Ljava/lang/StringBuilder;
invoke-direct {v6}, Ljava/lang/StringBuilder;-><init>()V
invoke-virtual {v6, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v4, "_"
invoke-virtual {v6, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v6
new-instance v4, Ljava/io/File;
sget-object v5, Landroid/atl/ATLPaths;->app_data_dir_base:Ljava/io/File;
invoke-direct {v4, v5, v6}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
invoke-virtual {v4}, Ljava/io/File;->mkdirs()Z
invoke-virtual {v4}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v4
iput-object v4, v0, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
')
	os.write_file(manager, text)!
	context := smali + '/android/content/Context.smali'
	text = framework_replace_method(os.read_file(context)!, 'getDataDirFile()Ljava/io/File;', '.method private getDataDirFile()Ljava/io/File;
.locals 2
iget-object v0, p0, Landroid/content/Context;->data_dir:Ljava/io/File;
if-nez v0, :ready
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v1, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
new-instance v0, Ljava/io/File;
invoke-direct {v0, v1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
iput-object v0, p0, Landroid/content/Context;->data_dir:Ljava/io/File;
:ready
return-object v0
.end method')!
	// Cache by the actual private file, with one instance across all contexts
	// for that package. Hold the shared map's monitor through construction.
	text = framework_replace_method(text, 'getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;', '.method public getSharedPreferences(Ljava/lang/String;I)Landroid/content/SharedPreferences;
.locals 4
invoke-virtual {p0, p1}, Landroid/content/Context;->getSharedPrefsFile(Ljava/lang/String;)Ljava/io/File;
move-result-object v0
invoke-virtual {v0}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v1
sget-object v2, Landroid/content/Context;->sharedPrefs:Ljava/util/Map;
monitor-enter v2
:try_start
invoke-interface {v2, v1}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v3
if-nez v3, :ready
new-instance v3, Landroid/app/SharedPreferencesImpl;
invoke-direct {v3, v0, p2}, Landroid/app/SharedPreferencesImpl;-><init>(Ljava/io/File;I)V
invoke-interface {v2, v1, v3}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
:ready
check-cast v3, Landroid/content/SharedPreferences;
monitor-exit v2
:try_end
.catchall {:try_start .. :try_end} :failed
return-object v3
:failed
move-exception v0
monitor-exit v2
throw v0
.end method')!
	os.write_file(context, text)!
}
