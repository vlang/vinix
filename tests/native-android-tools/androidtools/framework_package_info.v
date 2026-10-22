// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_application_info(smali string) ! {
	path := smali + '/android/content/pm/ApplicationInfo.smali'
	mut text := os.read_file(path)!
	// Standalone APKs have no split names. Keep the normal null default;
	// do not invent split packages or paths to satisfy a caller.
	text += '\n.field public splitNames:[Ljava/lang/String;\n'
	signature := '.method public constructor <init>(Landroid/content/pm/ApplicationInfo;)V'
	start := text.index(signature) or { return error('ApplicationInfo copy constructor missing') }
	end := start + text[start..].index('.end method') or { return error('ApplicationInfo constructor end missing') }
	body := text[start..end]
	if body.count('    return-void') != 1 { return error('ApplicationInfo constructor return changed') }
	mut copy := ''
	for name in ['splitNames', 'splitSourceDirs', 'splitPublicSourceDirs'] {
		copy += '    iget-object v0, p1, Landroid/content/pm/ApplicationInfo;->' + name + ':[Ljava/lang/String;\n' +
			'    iput-object v0, p0, Landroid/content/pm/ApplicationInfo;->' + name + ':[Ljava/lang/String;\n'
	}
	text = text[..start] + body.replace('    return-void', copy + '    return-void') + text[end..]
	os.write_file(path, text)!
}
