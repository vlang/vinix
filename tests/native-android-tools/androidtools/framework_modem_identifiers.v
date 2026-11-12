// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_modem_identifiers(smali string) ! {
	path := smali + '/android/telephony/TelephonyManager.smali'
	mut text := os.read_file(path)!
	// The native runtime has no modem, radio identity backend or SIM slots.
	// Never fabricate a persistent identifier or expose a host identifier.
	for name in ['getImei', 'getMeid'] {
		for argument in ['', 'I'] {
			text = framework_replace_method(text, name + '(' + argument + ')Ljava/lang/String;',
				'.method public ' + name + '(' + argument + ')Ljava/lang/String;\n.locals 1\nconst/4 v0, 0\nreturn-object v0\n.end method')!
		}
	}
	os.write_file(path, text)!
}
