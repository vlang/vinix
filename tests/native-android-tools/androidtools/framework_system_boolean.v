// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_system_boolean(smali string) ! {
	path := smali + '/android/os/SystemProperties.smali'
	// Android's public hidden API is static. Match its exact lowercase token
	// vocabulary; missing, empty and unrecognised values retain the default.
	// https://android.googlesource.com/platform/system/libbase/+/refs/heads/main/parsebool.cpp
	mut method := '.method public static getBoolean(Ljava/lang/String;Z)Z\n.locals 2\n'
	method += 'invoke-static {p0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nif-eqz v0, :default_value\n'
	for value, tokens in {'true_value': ['1', 'y', 'yes', 'on', 'true'], 'false_value': ['0', 'n', 'no', 'off', 'false']} {
		for token in tokens {
			method += 'const-string v1, "${token}"\ninvoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-nez v1, :${value}\n'
		}
	}
	method += ':default_value\nreturn p1\n:true_value\nconst/4 v0, 1\nreturn v0\n:false_value\nconst/4 v0, 0\nreturn v0\n.end method'
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'getBoolean(Ljava/lang/String;Z)Z', method)!)!
}
