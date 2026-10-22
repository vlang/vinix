// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Enumerate staged APKs through the existing visibility-aware package loader.
// Parsing metadata must not instantiate companion Applications or services.
fn framework_package_enumeration(smali string) ! {
	path := smali + '/android/content/pm/PackageManager.smali'
	mut text := os.read_file(path)!
	text = framework_replace_method(text, 'getInstalledPackages(I)Ljava/util/List;', '.method public getInstalledPackages(I)Ljava/util/List;
.locals 8
new-instance v0, Ljava/util/LinkedHashSet;
invoke-direct {v0}, Ljava/util/LinkedHashSet;-><init>()V
iget-object v1, p0, Landroid/content/pm/PackageManager;->package_info:Landroid/content/pm/PackageInfo;
iget-object v1, v1, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/util/LinkedHashSet;->add(Ljava/lang/Object;)Z
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v1
iget-object v1, v1, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
iget-object v1, v1, Landroid/content/pm/PackageParser$Package;->packageName:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/util/LinkedHashSet;->add(Ljava/lang/Object;)Z
sget-object v1, Landroid/atl/ATLPaths;->installed_apks_dir:Ljava/io/File;
invoke-virtual {v1}, Ljava/io/File;->listFiles()[Ljava/io/File;
move-result-object v1
if-eqz v1, :parse
invoke-static {v1}, Ljava/util/Arrays;->sort([Ljava/lang/Object;)V
const/4 v2, 0
:files
array-length v3, v1
if-ge v2, v3, :parse
aget-object v3, v1, v2
add-int/lit8 v2, v2, 1
invoke-virtual {v3}, Ljava/io/File;->isFile()Z
move-result v4
if-eqz v4, :files
invoke-virtual {v3}, Ljava/io/File;->getName()Ljava/lang/String;
move-result-object v3
const-string v4, ".apk"
invoke-virtual {v3, v4}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v4
if-eqz v4, :files
invoke-virtual {v3}, Ljava/lang/String;->length()I
move-result v4
add-int/lit8 v4, v4, -4
if-lez v4, :files
const/4 v5, 0
invoke-virtual {v3, v5, v4}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v3
invoke-virtual {v0, v3}, Ljava/util/LinkedHashSet;->add(Ljava/lang/Object;)Z
goto :files
:parse
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V
invoke-virtual {v0}, Ljava/util/LinkedHashSet;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Ljava/lang/String;
:lookup
invoke-virtual {p0, v2, p1}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v2
:lookup_end
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:lookup .. :lookup_end} :missing
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
goto :next
:missing
move-exception v2
goto :next
:done
return-object v1
.end method')!
	text = framework_replace_method(text, 'getInstalledApplications(I)Ljava/util/List;', '.method public getInstalledApplications(I)Ljava/util/List;
.locals 3
invoke-virtual {p0, p1}, Landroid/content/pm/PackageManager;->getInstalledPackages(I)Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/content/pm/PackageInfo;
iget-object v2, v2, Landroid/content/pm/PackageInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
if-eqz v2, :next
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
goto :next
:done
return-object v1
.end method')!
	text = framework_replace_method(text, 'getPackagesForUid(I)[Ljava/lang/String;', '.method public getPackagesForUid(I)[Ljava/lang/String;
.locals 4
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/content/pm/PackageManager;->getInstalledApplications(I)Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v2
if-eqz v2, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/content/pm/ApplicationInfo;
iget v3, v2, Landroid/content/pm/ApplicationInfo;->uid:I
if-ne v3, p1, :next
iget-object v2, v2, Landroid/content/pm/ApplicationInfo;->packageName:Ljava/lang/String;
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
goto :next
:done
invoke-virtual {v1}, Ljava/util/ArrayList;->isEmpty()Z
move-result v0
if-eqz v0, :array
const/4 v0, 0
return-object v0
:array
invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
move-result v0
new-array v0, v0, [Ljava/lang/String;
invoke-virtual {v1, v0}, Ljava/util/ArrayList;->toArray([Ljava/lang/Object;)[Ljava/lang/Object;
move-result-object v0
check-cast v0, [Ljava/lang/String;
return-object v0
.end method')!
	os.write_file(path, text)!
}
