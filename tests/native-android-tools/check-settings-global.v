// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	work := os.temp_dir() + '/vinix-settings-global-' + os.getpid().str()
	defer { os.rmdir_all(work) or {} }
	name := 'android/provider/Settings$Global.smali'
	old := os.read_file(os.args[1] + '/' + name)!
	new := androidtools.framework_settings_global_put_int(old)!
	method := androidtools.framework_settings_global_put_int_method()
	assert new == old + '\n' + method + '\n'
	assert new.count('.method ') == 11 && new.count('.field ') == 2
	assert method.contains('Ljava/lang/Integer;->toString(I)Ljava/lang/String;')
	assert method.count('Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V') == 2
	assert method.contains('Landroid/provider/Settings$Global;->CONTENT_URI:Landroid/net/Uri;')
	assert method.count('Landroid/content/ContentResolver;->insert(') == 1
	assert method.contains('if-eqz v0, :failed')
	assert method.count('.catch ') == 1 && method.contains('.catch Landroid/database/SQLException;')
	assert !method.contains('.catchall') && !method.contains('SecurityException')
	for rejected in [
		new,
		old.replace('.method public static getInt(', '.method private static getInt('),
		old.replace('.super Landroid/provider/Settings$NameValueTable;', '.super Ljava/lang/Object;'),
		old.replace('.field public static final CONTENT_URI:', '.field private CONTENT_URI:'),
		old + '\n.method public static bogus()V\n.locals 0\nreturn-void\n.end method\n',
	] {
		if _ := androidtools.framework_settings_global_put_int(rejected) {
			panic('accepted unexpected or already transformed Settings.Global')
		}
	}
	println('ANDROID-SETTINGS-GLOBAL-TRANSFORM-PASS one added putInt, ten original methods and two fields preserved; real provider result and SQLException boundary')
	if os.args.len == 4 {
		path := work + '/smali/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, new)!
		assembled := os.exec([os.args[3], '-cp', os.real_path(os.args[2]) + '/*',
			'org.jf.smali.Main', 'assemble', '--jobs', '2', work + '/smali', '-o', work + '/classes.dex'])
		assert assembled.exit_code == 0, assembled.output
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-SETTINGS-GLOBAL-ASSEMBLY-PASS Settings.Global produces DEX; ART not executed')
	}
}
