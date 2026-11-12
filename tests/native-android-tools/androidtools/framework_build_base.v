// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_build_base(smali string) ! {
	path := smali + r'/android/os/Build$VERSION.smali'
	mut text := os.read_file(path)!
	if text.contains('BASE_OS:Ljava/lang/String;') { return error('base OS metadata already present') }
	body := direct_boot_method(text, '<clinit>()V')!
	if body.count('    .registers 4\n') != 1 || body.count('    return-void') != 1 {
		return error('Build.VERSION initializer shape differs')
	}
	read := r'    const-string v0, "ro.build.version.base_os"
    const-string v1, ""
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/os/Build$VERSION;->BASE_OS:Ljava/lang/String;
'
	text = framework_replace_method(text, '<clinit>()V', body.replace('    return-void', read + '\n    return-void'))!
	os.write_file(path, text + '\n.field public static final BASE_OS:Ljava/lang/String;\n')!
}
