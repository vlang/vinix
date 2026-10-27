// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn direct_boot_method(source string, signature string) !string {
	mut found := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if found != '' { return error('duplicate direct boot method: ' + signature) }
		end := block.index('.end method') or { return error('unterminated direct boot method') }
		found = '.method ' + block[..end + '.end method'.len]
	}
	if found == '' { return error('missing direct boot method: ' + signature) }
	return found
}

fn direct_boot_class(source string, name string, parent string) ! {
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public L' + name + ';']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super L' + parent + ';']
		|| source.count('.method ') != source.count('.end method')
		|| source.contains('directBootAware') || source.contains('vinixParseDirectBoot') {
		return error('unexpected or already extended direct boot class: ' + name)
	}
}

// Android exposes this metadata on ComponentInfo, inherited by all component
// kinds. The VM's zero default is false; copy constructors must preserve true.
pub fn framework_component_direct_boot(source string) !string {
	direct_boot_class(source, 'android/content/pm/ComponentInfo', 'android/content/pm/PackageItemInfo')!
	signature := '<init>(Landroid/content/pm/ComponentInfo;)V'
	body := direct_boot_method(source, signature)!
	if body.count('    .registers 3\n') != 1 || body.count('    return-void') != 1
		|| body.count('Landroid/content/pm/ComponentInfo;->exported:Z') != 3 {
		return error('unexpected ComponentInfo copy constructor')
	}
	copy := '    iget-boolean v0, p1, Landroid/content/pm/ComponentInfo;->directBootAware:Z\n' +
		'    iput-boolean v0, p0, Landroid/content/pm/ComponentInfo;->directBootAware:Z\n\n'
	return framework_replace_method(source, signature, body.replace('    return-void', copy + '    return-void'))! +
		'\n.field public directBootAware:Z\n'
}

// The retained parser predates the public directBootAware attribute. Read its
// canonical Android resource ID through TypedArray so boolean resources work,
// with the same false default as Android's component parsers. No user lock or
// component enablement state is changed by reading this metadata.
pub fn framework_parser_direct_boot(source string) !string {
	direct_boot_class(source, 'android/content/pm/PackageParser', 'java/lang/Object')!
	mut result := source
	for spec in [
		['parseActivity', 'Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;ZZ', 'Activity', 'v10', '22'],
		['parseService', 'Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;', 'Service', 'v10', '20'],
		['parseProvider', 'Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;', 'Provider', 'v5', '20'],
	] {
		signature := spec[0] + '(' + spec[1] + ')Landroid/content/pm/PackageParser$' + spec[2] + ';'
		body := direct_boot_method(result, signature)!
		anchor := '    invoke-direct {' + spec[3] + ', v1, v2}, Landroid/content/pm/PackageParser$' + spec[2] +
			';-><init>(Landroid/content/pm/PackageParser$ParseComponentArgs;Landroid/content/pm/' + spec[2] + 'Info;)V\n'
		if body.count('    .registers ' + spec[4] + '\n') != 1 || body.count(anchor) != 1 {
			return error('unexpected direct boot component parser: ' + spec[0])
		}
		read := '\n    move-object/from16 v0, p2\n    move-object/from16 v1, p4\n' +
			'    iget-object v2, ' + spec[3] + ', Landroid/content/pm/PackageParser$' + spec[2] + ';->info:Landroid/content/pm/' + spec[2] + 'Info;\n' +
			'    invoke-static {v0, v1, v2}, Landroid/content/pm/PackageParser;->vinixParseDirectBoot(Landroid/content/res/Resources;Landroid/util/AttributeSet;Landroid/content/pm/ComponentInfo;)V\n'
		result = framework_replace_method(result, signature, body.replace(anchor, anchor + read))!
	}
	alias_signature := 'parseActivityAlias(Landroid/content/pm/PackageParser$Package;Landroid/content/res/Resources;Lorg/xmlpull/v1/XmlPullParser;Landroid/util/AttributeSet;I[Ljava/lang/String;)Landroid/content/pm/PackageParser$Activity;'
	alias := direct_boot_method(result, alias_signature)!
	anchor := '    iput-object v14, v3, Landroid/content/pm/ActivityInfo;->targetActivity:Ljava/lang/String;\n'
	if alias.count('    .registers 22\n') != 1 || alias.count(anchor) != 1 {
		return error('unexpected direct boot activity alias parser')
	}
	copy := '\n    iget-object v4, v2, Landroid/content/pm/PackageParser$Activity;->info:Landroid/content/pm/ActivityInfo;\n' +
		'    iget-boolean v4, v4, Landroid/content/pm/ComponentInfo;->directBootAware:Z\n' +
		'    iput-boolean v4, v3, Landroid/content/pm/ComponentInfo;->directBootAware:Z\n'
	result = framework_replace_method(result, alias_signature, alias.replace(anchor, anchor + copy))!
	return result + '
.method private static vinixParseDirectBoot(Landroid/content/res/Resources;Landroid/util/AttributeSet;Landroid/content/pm/ComponentInfo;)V
    .locals 3
    const/4 v0, 0x1
    new-array v0, v0, [I
    const v1, 0x01010505
    const/4 v2, 0x0
    aput v1, v0, v2
    invoke-virtual {p0, p1, v0}, Landroid/content/res/Resources;->obtainAttributes(Landroid/util/AttributeSet;[I)Landroid/content/res/TypedArray;
    move-result-object v0
    invoke-virtual {v0, v2, v2}, Landroid/content/res/TypedArray;->getBoolean(IZ)Z
    move-result v1
    iput-boolean v1, p2, Landroid/content/pm/ComponentInfo;->directBootAware:Z
    invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
    return-void
.end method
'
}

fn framework_direct_boot(smali string) ! {
	component := smali + '/android/content/pm/ComponentInfo.smali'
	os.write_file(component, framework_component_direct_boot(os.read_file(component)!)!)!
	parser := smali + '/android/content/pm/PackageParser.smali'
	os.write_file(parser, framework_parser_direct_boot(os.read_file(parser)!)!)!
}
