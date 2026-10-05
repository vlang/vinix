// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_fixed_argument_libsystem_calls() {
	assert darwin_strlen(c'') == 0
	assert darwin_strlen(c'calculator') == 10
	assert darwin_strcmp(c'123', c'123') == 0
	assert darwin_strcmp(c'123', c'124') < 0
	assert darwin_strcmp(c'124', c'123') > 0
	assert darwin_strcmp(c'', c'a') < 0
	assert darwin_atoi(c' \t\n-42') == -42
	assert darwin_atoi(c'+123x') == 123
	assert darwin_atoi(c'2147483647') == 2147483647
	assert darwin_atoi(c'-2147483648') == int(-2147483647 - 1)
	assert darwin_atoi(c'999999999999999999999999') == 2147483647
	assert darwin_atoi(c'-999999999999999999999999') == int(-2147483647 - 1)
	assert darwin_atoi(c'hello') == 0
	assert libsystem_symbol('/usr/lib/libSystem.B.dylib', '_puts')! != 0
	if _ := libsystem_symbol('/usr/lib/libSystem.B.dylib', '_printf') {
		assert false
	}
	if _ := libsystem_symbol('/usr/lib/libobjc.A.dylib', '_puts') {
		assert false
	}
}
