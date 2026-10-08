// SPDX-License-Identifier: GPL-2.0-only
module stagehost

fn test_original_v_literal_vectors() {
	assert v_string('') == "''"
	assert v_string("quote'\\dollar\$\t\r\n") == "'quote\\'\\\\dollar\\\$\\t\\r\n'"
	assert v_string('中文 ') == "'中文 '"
}
