// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn build_abis_methods(source string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := source.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len || ends.any(it != '.end method') {
		return error('balanced canonical Build ABI methods required')
	}
	mut methods := map[string]string{}
	for block in blocks {
		name := block.all_before('\n').all_after_last(' ')
		if name in methods || block.count('.end method') != 1 {
			return error('unique complete Build ABI methods required')
		}
		methods[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return methods
}

pub fn framework_build_abis_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.starts_with('.class ')) != ['.class public Landroid/os/Build;']
		|| lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| lines.filter(it.starts_with('.field ')).any(it.contains('SUPPORTED_64_BIT_ABIS:') || it.contains('SUPPORTED_32_BIT_ABIS:'))
		|| lines.filter(it == '.field public static final SUPPORTED_ABIS:[Ljava/lang/String;').len != 1 {
		return error('original Build ABI surface required')
	}
	methods := build_abis_methods(original)!
	if methods.keys().any(it.starts_with('getStringList(')) || '<clinit>()V' !in methods {
		return error('original Build initializer and absent list helper required')
	}
	initializer := methods['<clinit>()V']
	anchor := 'sput-object v0, Landroid/os/Build;->SUPPORTED_ABIS:[Ljava/lang/String;'
	if initializer.count(anchor) != 1 || !initializer.contains('    .registers 4\n') {
		return error('canonical Build ABI initializer required')
	}
	insert := '
const-string v0, "ro.product.cpu.abilist64"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
const-string v0, "ro.product.cpu.abilist32"
const-string v1, ","
invoke-static {v0, v1}, Landroid/os/Build;->getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
sput-object v0, Landroid/os/Build;->SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;'
	patched := original.replace(initializer, initializer.replace(anchor, anchor + insert))
	return patched + '
.field public static final SUPPORTED_64_BIT_ABIS:[Ljava/lang/String;
.field public static final SUPPORTED_32_BIT_ABIS:[Ljava/lang/String;

.method private static getStringList(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/String;
.registers 4
const-string v0, ""
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
return-object v0
.end method
'
}

pub fn framework_build_abi_properties_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.starts_with('.class ')) != ['.class public Landroid/os/SystemProperties;']
		|| lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| original.contains('ro.product.cpu.abilist64') || original.contains('ro.product.cpu.abilist32') {
		return error('original SystemProperties ABI surface required')
	}
	methods := build_abis_methods(original)!
	if '<clinit>()V' !in methods { return error('SystemProperties initializer required') }
	initializer := methods['<clinit>()V']
	anchor := '    const-string v1, "ro.product.cpu.abilist"\n\n    const-string v2, "arm64-v8a"\n\n    invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
	if initializer.count(anchor) != 1 || !initializer.contains('    .registers 3\n')
		|| initializer.count('const-string v1, "aarch64"') != 1 {
		return error('canonical aarch64-only SystemProperties initializer required')
	}
	insert := '
const-string v1, "ro.product.cpu.abilist64"
const-string v2, "arm64-v8a"
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abilist32"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
const-string v1, "ro.product.cpu.abi2"
const-string v2, ""
invoke-virtual {v0, v1, v2}, Ljava/util/Properties;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;'
	return original.replace(initializer, initializer.replace(anchor, anchor + insert))
}

pub fn framework_build_abis(smali string) ! {
	build := smali + '/android/os/Build.smali'
	properties := smali + '/android/os/SystemProperties.smali'
	patched_build := framework_build_abis_source(os.read_file(build)!)!
	patched_properties := framework_build_abi_properties_source(os.read_file(properties)!)!
	os.write_file(build, patched_build)!
	os.write_file(properties, patched_properties)!
}
