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
	// PackageManager normally fills the default application process after
	// parsing. ATL exposes parsed metadata directly, including to companions.
	// Use the package name before parsing components so they inherit it too;
	// explicit global/private process names still use buildProcessName.
	parser := smali + '/android/content/pm/PackageParser.smali'
	mut parsed := os.read_file(parser)!
	anchor := '    iget-object v2, v8, Landroid/content/pm/ApplicationInfo;->packageName:Ljava/lang/String;\n\n    const/4 v3, 0x0\n\n    move-object/from16 v0, p0\n\n    iget-object v6, v0, Landroid/content/pm/PackageParser;->mSeparateProcesses:[Ljava/lang/String;'
	if parsed.count(anchor) != 1 { return error('application process default anchor changed') }
	parsed = parsed.replace(anchor, anchor.replace('const/4 v3, 0x0', 'move-object v3, v2'))
	os.write_file(parser, parsed)!
}
