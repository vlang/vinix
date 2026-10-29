// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn service_lifecycle_method(source string, signature string) !string {
	mut found := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if found != '' || block.all_before('\n') != 'public ' + signature {
			return error('unique public Service callback required: ' + signature)
		}
		end := block.index('.end method') or { return error('unterminated Service callback') }
		found = '.method ' + block[..end + '.end method'.len]
	}
	if found == '' { return error('missing Service callback: ' + signature) }
	return found
}

fn service_lifecycle_lines(source string) string {
	return source.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
}

// Accept only the retained diagnostic implementation. Callback calls, state,
// constructors and all other source bytes remain outside these replacements.
pub fn framework_service_lifecycle_source(original string) !string {
	if original.split_into_lines().filter(it.starts_with('.class ')) != ['.class public abstract Landroid/app/Service;']
		|| original.split_into_lines().filter(it.starts_with('.super ')) != ['.super Landroid/content/ContextWrapper;'] {
		return error('canonical Service class required for lifecycle cleanup')
	}
	mut source := original
	for signature in ['attachBaseContext(Landroid/content/Context;)V', 'onCreate()V', 'onDestroy()V'] {
		found := service_lifecycle_method(original, signature)!
		mut expected := '.method public ' + signature + '\n'
		if signature.starts_with('attachBaseContext(') {
			expected += '.registers 5\n' + service_lifecycle_attach_diagnostic
		} else {
			name := signature.all_before('(')
			expected += '.registers 3\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
				'const-string v1, "Service.' + name + '() called"\n' +
				'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n'
		}
		expected += '.end method'
		if service_lifecycle_lines(found) != service_lifecycle_lines(expected) {
			return error('unexpected Service lifecycle implementation: ' + signature)
		}
		body := if signature.starts_with('attachBaseContext(') {
			'.registers 2\ninvoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V\nreturn-void'
		} else { '.registers 1\nreturn-void' }
		source = source.replace(found, '.method public ' + signature + '\n' + body + '\n.end method')
	}
	return source
}

pub fn framework_service_lifecycle(smali string) ! {
	path := smali + '/android/app/Service.smali'
	patched := framework_service_lifecycle_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}

const service_lifecycle_attach_diagnostic = '
invoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
new-instance v1, Ljava/lang/StringBuilder;
invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
const-string v2, "Service.attachBaseContext("
invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
move-result-object v1
invoke-virtual {v1, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
move-result-object v1
const-string v2, ") called"
invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
'
