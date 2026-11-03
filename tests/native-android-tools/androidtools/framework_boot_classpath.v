// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Framework classes are bootstrap-defined, while the resource-only framework
// APK remains on the ordinary system class path. Resolve resources through that
// system loader, and retain it as the parent of each application's code loader.
fn framework_boot_loader_source(original string, declaration string, signature string,
	method_count int, registers int, parameters int, register string, owner string) !string {
	mut lines := original.split('\n')
	clean := lines.map(it.all_before('#').trim_space())
	if clean.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [declaration]
		|| clean.filter(it.fields().len > 0 && it.fields()[0] == '.super') != ['.super Ljava/lang/Object;']
		|| clean.any(it.fields().len > 0 && it.fields()[0] == '.implements') {
		return error('exact framework resource-loader class declaration required')
	}
	mut methods := map[string]bool{}
	mut current := ''
	mut first := -1
	mut last := -1
	mut ended := 0
	for index, line in clean {
		parts := line.fields()
		if parts.len == 0 { continue }
		if parts[0] == '.method' {
			name := parts.last()
			if current != '' || !line.starts_with('.method ') || !name.contains('(') || name in methods {
				return error('unique complete framework methods required before loader replacement')
			}
			methods[name] = true
			current = name
			if name == signature {
				if line != '.method public static ' + signature { return error('exact public static framework loader method required') }
				first = index
			}
		} else if parts[0] == '.end' && parts.len >= 2 && parts[1] == 'method' {
			if current == '' || line != '.end method' { return error('balanced framework method terminators required') }
			if current == signature { last = index }
			current = ''
			ended++
		}
	}
	if current != '' || methods.len != method_count || ended != method_count || first < 0 || last <= first {
		return error('exact complete framework method membership required')
	}
	mut meaningful := []int{}
	for index in first .. last + 1 {
		if clean[index] != '' { meaningful << index }
	}
	method := meaningful.map(clean[it])
	register_directives := method.filter(it.starts_with('.registers ') || it.starts_with('.locals '))
	if register_directives != ['.registers ' + registers.str()]
		&& register_directives != ['.locals ' + (registers - parameters).str()] {
		return error('original framework loader register layout required')
	}
	if method.filter(it == 'const-class ' + register + ', L' + owner + ';').len != 1
		|| method.filter(it == 'invoke-virtual {' + register + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;').len != 1
		|| method.any(it.contains('Ljava/lang/ClassLoader;->getSystemClassLoader(')) {
		return error('original register layout and one unmodified framework defining-loader site required')
	}
	mut selected := -1
	for index, line in method {
		if line == 'const-class ' + register + ', L' + owner + ';' { selected = index }
	}
	if selected < 0 || selected + 2 >= method.len
		|| method[selected + 1] != 'invoke-virtual {' + register + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;'
		|| method[selected + 2] != 'move-result-object ' + register {
		return error('exact adjacent framework class/loader/result instructions required')
	}
	const_index, call_index := meaningful[selected], meaningful[selected + 1]
	indent := lines[call_index][..lines[call_index].len - lines[call_index].trim_left(' \t').len]
	lines[const_index] = if lines[const_index].ends_with('\r') { '\r' } else { '' }
	ending := if lines[call_index].ends_with('\r') { '\r' } else { '' }
	lines[call_index] = indent + 'invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()Ljava/lang/ClassLoader;' + ending
	return lines.join('\n')
}

pub fn framework_boot_resources_source(original string) !string {
	return framework_boot_loader_source(original, '.class public Landroid/content/res/Resources;',
		'getSystem()Landroid/content/res/Resources;', 81, 5, 0, 'v3', 'android/content/res/Resources')
}

pub fn framework_boot_loaded_source(original string) !string {
	return framework_boot_loader_source(original, '.class public final Landroid/atl/ATLLoadedApp;',
		'loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;',
		23, 12, 3, 'v1', 'android/atl/ATLLoadedApp')
}

pub fn framework_boot_classpath(smali string) ! {
	resources := smali + '/android/content/res/Resources.smali'
	loaded := smali + '/android/atl/ATLLoadedApp.smali'
	// Validate both classes before the first write, including refusals in the
	// second input. Each pure adapter preserves all unrelated original lines.
	new_resources := framework_boot_resources_source(os.read_file(resources)!)!
	new_loaded := framework_boot_loaded_source(os.read_file(loaded)!)!
	os.write_file(resources, new_resources)!
	os.write_file(loaded, new_loaded)!
}
