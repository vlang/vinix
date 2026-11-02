// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// This target has no autofill service. Match Android's absent-service query
// without advertising a provider or changing the existing notification paths.
pub fn framework_autofill_service_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public Landroid/view/autofill/AutofillManager;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Ljava/lang/Object;',
	] {
		return error('canonical AutofillManager class required')
	}
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end'
		&& it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len
		|| ends.any(it != '.end method') {
		return error('balanced canonical AutofillManager methods required')
	}
	mut signatures := map[string]bool{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if header.trim_space() != header || !name.contains('(') || name in signatures
			|| block.count('.end method') != 1 {
			return error('unique complete AutofillManager methods required')
		}
		if name.all_before('(') == 'getAutofillServiceComponentName' {
			return error('autofill component query already exists')
		}
		signatures[name] = true
	}
	return original + '\n.method public getAutofillServiceComponentName()Landroid/content/ComponentName;\n.registers 2\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
}
