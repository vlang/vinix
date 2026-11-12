// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_sandbox_metadata(smali string) ! {
	info_path := smali + '/android/content/pm/ApplicationInfo.smali'
	mut info := os.read_file(info_path)!
	if info.contains('targetSandboxVersion:I') { return error('sandbox metadata already installed') }
	copy_signature := '<init>(Landroid/content/pm/ApplicationInfo;)V'
	copy := direct_boot_method(info, copy_signature)!
	if copy.count('    .registers 4\n') != 1 || copy.count('return-void') != 1 {
		return error('ApplicationInfo copy constructor shape differs')
	}
	info = framework_replace_method(info, copy_signature, copy.replace('return-void',
		'iget v0, p1, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I\niput v0, p0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I\nreturn-void'))!
	info += '\n.field public targetSandboxVersion:I\n'

	// The retained manifest TypedArray already includes the canonical attribute.
	// Read it before recycle, including resource references; omitted defaults to1.
	style := os.read_file(smali + r'/com/android/internal/R$styleable.smali')!
	if !style.contains('.field public static final AndroidManifest_targetSandboxVersion:I = 0x7')
		|| !style.contains('0x101054c') { return error('manifest sandbox attribute missing') }
	parser_path := smali + '/android/content/pm/PackageParser.smali'
	mut parser := os.read_file(parser_path)!
	signature := 'parsePackage(Landroid/content/res/Resources;Landroid/content/res/XmlResourceParser;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Package;'
	body := direct_boot_method(parser, signature)!
	anchor := '    iput v4, v5, Landroid/content/pm/PackageParser$Package;->installLocation:I\n\n    invoke-virtual {v6}, Landroid/content/res/TypedArray;->recycle()V'
	if body.count('    .registers 27\n') != 1 || body.count(anchor) != 1 {
		return error('manifest parser register lifetime differs')
	}
	read := r'
    sget v7, Lcom/android/internal/R$styleable;->AndroidManifest_targetSandboxVersion:I
    const/4 v8, 0x1
    invoke-virtual {v6, v7, v8}, Landroid/content/res/TypedArray;->getInteger(II)I
    move-result v7
    iget-object v8, v5, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
    iput v7, v8, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
'
	parser = framework_replace_method(parser, signature, body.replace(anchor,
		anchor.replace('    invoke-virtual {v6}', read + '\n    invoke-virtual {v6}')))!
	os.write_file(info_path, info)!
	os.write_file(parser_path, parser)!
}
