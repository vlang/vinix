// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn broadcast_permission_methods(source string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := source.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len || ends.any(it != '.end method') {
		return error('balanced canonical broadcast permission methods required')
	}
	mut result := map[string]string{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if header.trim_space() != header || !name.contains('(') || name in result
			|| block.count('.end method') != 1 {
			return error('unique complete broadcast permission methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn broadcast_permission_class(source string, declaration string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [declaration]
		|| lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != ['.super Ljava/lang/Object;']
		|| source.contains('vinixBroadcast') || source.contains('VinixBroadcastPolicy') {
		return error('canonical unextended broadcast permission class required')
	}
	return broadcast_permission_methods(source)!
}

pub fn framework_broadcast_permission_context_source(original string) !string {
	methods := broadcast_permission_class(original, '.class public abstract Landroid/content/Context;')!
	if (methods['sendBroadcast(Landroid/content/Intent;)V'] or { '' }) !=
		'.method public native sendBroadcast(Landroid/content/Intent;)V\n.end method'
		|| methods.keys().any(it.starts_with('sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)')) {
		return error('one retained native broadcast and absent permission overload required')
	}
	return original + '\n.method public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
.registers 3
invoke-static {p0, p1, p2}, Landroid/atl/VinixBroadcastPolicy;->send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V
return-void
.end method\n'
}

pub fn framework_broadcast_permission_loaded_source(original string) !string {
	methods := broadcast_permission_class(original, '.class public final Landroid/atl/ATLLoadedApp;')!
	constructor := '<init>(Landroid/content/res/Resources;Ljava/lang/ClassLoader;Landroid/content/pm/PackageParser$Package;)V'
	old := methods[constructor] or { return error('loaded application constructor required') }
	anchor := '    iput-object p3, p0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;'
	if old.all_before('\n') != '.method constructor ' + constructor || !old.contains('    .registers 6\n')
		|| old.count(anchor) != 1 {
		return error('canonical unpublished loaded application constructor required')
	}
	// The primary APK path verifies its certificates before constructing this
	// holder. Other holders cannot replace the primary instance's private set.
	loader := methods['loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;'] or {
		return error('verified primary application loader required')
	}
	verification := '    invoke-virtual {v2, v1, v7}, Landroid/content/pm/PackageParser;->collectCertificates(Landroid/content/pm/PackageParser$Package;I)Z'
	creation := '    :cond_5a\n    new-instance v2, Landroid/atl/ATLLoadedApp;\n\n    invoke-direct {v2, v3, v0, v1}, Landroid/atl/ATLLoadedApp;->' + constructor
	if loader.count(verification) != 1 || loader.count(creation) != 1
		|| !loader.all_after(verification).contains('    if-nez v2, :cond_5a\n')
		|| !loader.all_after(verification).contains('    const-string v4, "APK signature verification failed"\n') {
		return error('certificate success must precede primary holder construction')
	}
	patched := old.replace(anchor, anchor + '\n\n    invoke-static {p3}, Landroid/atl/VinixBroadcastPolicy;->snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;\n\n    move-result-object v0\n\n    iput-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;')
	return original.replace(old, patched) + '\n.field private final vinixBroadcastPermissions:Ljava/util/Set;
.method public final vinixHasBroadcastPermission(Ljava/lang/String;)Z
.registers 3
iget-object v0, p0, Landroid/atl/ATLLoadedApp;->vinixBroadcastPermissions:Ljava/util/Set;
invoke-interface {v0, p1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z
move-result v0
return v0
.end method\n'
}

pub fn framework_broadcast_permission_classes() map[string]string {
	// Broadcast transport is process-local. Only permissions requested and
	// defined as signature permissions by this same authenticated APK qualify.
	// This is not a package-wide grant database or cross-process authority.
	return {
		'android/atl/VinixBroadcastPolicy': '.class public final Landroid/atl/VinixBroadcastPolicy;
.super Ljava/lang/Object;

.method public static snapshot(Landroid/content/pm/PackageParser$Package;)Ljava/util/Set;
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
.end method

.method public static send(Landroid/content/Context;Landroid/content/Intent;Ljava/lang/String;)V
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
.end method
'
	}
}

pub fn framework_broadcast_permission(smali string) ! {
	context := smali + '/android/content/Context.smali'
	loaded := smali + '/android/atl/ATLLoadedApp.smali'
	patched_context := framework_broadcast_permission_context_source(os.read_file(context)!)!
	patched_loaded := framework_broadcast_permission_loaded_source(os.read_file(loaded)!)!
	classes := framework_broadcast_permission_classes()
	for name, _ in classes {
		path := smali + '/' + name + '.smali'
		if os.exists(path) || os.is_link(path) {
			return error('broadcast permission helper collision')
		}
	}
	os.write_file(context, patched_context)!
	os.write_file(loaded, patched_loaded)!
	for name, source in classes {
		path := smali + '/' + name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
}
