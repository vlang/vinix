// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const classes = ['android/content/pm/ApplicationInfo', 'android/content/Context',
	'android/app/ContextImpl', 'android/atl/ATLLoadedAppManager']

fn write_classes(directory string, sources map[string]string) ! {
	for name, source in sources {
		path := directory + '/' + name + '.smali'
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
}

fn main() {
	assert os.args.len in [2, 4], 'usage: check-protected-storage BASELINE_SMALI [TOOLS JAVA]'
	work := os.temp_dir() + '/vinix-protected-storage-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	mut sources := map[string]string{}
	for name in classes { sources[name] = os.read_file(os.args[1] + '/' + name + '.smali')! }
	write_classes(work, sources)!
	androidtools.framework_protected_storage(work)!
	info := os.read_file(work + '/' + classes[0] + '.smali')!
	for field in ['credentialProtectedDataDir', 'deviceProtectedDataDir'] {
		assert info.count('.field public ' + field + ':Ljava/lang/String;') == 1
		assert info.count('iget-object v0, p1, Landroid/content/pm/ApplicationInfo;->' + field + ':Ljava/lang/String;') == 1
	}
	assert info.contains('move-object v0, p1\nif-eqz p1, :store')
	assert info.contains('const-string v1, "device_protected"')
	assert info.contains('iput-object p1, p0, Landroid/content/pm/ApplicationInfo;->credentialProtectedDataDir:Ljava/lang/String;')
	context := os.read_file(work + '/' + classes[1] + '.smali')!
	assert context.contains('invoke-virtual {p0}, Landroid/content/Context;->isDeviceProtectedStorage()Z\nmove-result v2\nif-eqz v2, :credential')
	assert context.contains('->deviceProtectedDataDir:Ljava/lang/String;\ngoto :path')
	assert context.contains('->credentialProtectedDataDir:Ljava/lang/String;\nif-nez v2, :credential_path')
	assert context.contains('invoke-direct {p0, v0, v1}, Landroid/content/Context;->vinixEnsurePrivateDirectory(Ljava/io/File;I)Ljava/io/File;')
	assert !context.contains('iput-object v2, v1, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;')
	impl := os.read_file(work + '/' + classes[2] + '.smali')!
	assert impl.contains('iget v4, p0, Landroid/app/ContextImpl;->atl_flags:I\nnew-instance v0, Landroid/app/ContextImpl;')
	manager := os.read_file(work + '/' + classes[3] + '.smali')!
	assert manager.count('invoke-virtual {v0, v4}, Landroid/content/pm/ApplicationInfo;->vinixSetDataDirectory(Ljava/lang/String;)V') == 2
	mut rejected := 0
	androidtools.framework_protected_storage(work) or { rejected++ }
	assert rejected == 1
	for name in classes {
		mut invalid := sources.clone()
		invalid[name] = match name {
			'android/content/pm/ApplicationInfo' { sources[name] + '\n.field public deviceProtectedDataDir:Ljava/lang/String;\n' }
			'android/content/Context' { sources[name].replace('getDataDirFile()Ljava/io/File;', 'missingDataDir()Ljava/io/File;') }
			'android/app/ContextImpl' { sources[name].replace('createConfigurationContext(', 'missingConfigurationContext(') }
			else { sources[name].replace('iput-object v4, v0, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;', 'nop') }
		}
		write_classes(work, invalid)!
		androidtools.framework_protected_storage(work) or { rejected++; }
		for unchanged, original in invalid { assert os.read_file(work + '/' + unchanged + '.smali')! == original }
	}
	assert rejected == 5
	if os.args.len == 4 {
		write_classes(work, sources)!
		androidtools.framework_protected_storage(work)!
		androidtools.framework_assemble(work, work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-PROTECTED-STORAGE-ASSEMBLY-PASS')
	}
	println('ANDROID-PROTECTED-STORAGE-GENERATOR-PASS fields copy null roots flags atomic-rejections=5')
}
