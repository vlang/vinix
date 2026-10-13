// SPDX-License-Identifier: GPL-2.0-only
module nativepolicy

fn test_unused_stdio_pruning_preserves_live_and_unfamiliar_compiler_code() {
	block := 'static FILE* v3_eprint_begin(void) {\n\tfflush(stdout);\n\tfflush(stderr);\n\treturn stderr;\n}\nstatic void v3_eprint_end(void) {\n\tfflush(stderr);\n}\n#define v3_eprintf(...) do { fprintf(v3_eprint_begin(), __VA_ARGS__); v3_eprint_end(); } while (0)\nstatic void v3_eprint_lit(const char* s) {\n\tv3_eprintf("%s", s);\n}\nstatic void v3_eprintln_string(string s) {\n\tv3_eprintf("%.*s\\n", s.len, (char*)s.str);\n}\n'
	before := '/* header */\n'; after := '\nvoid init_main(void) {}\n'
	assert without_unused_stdio_printers(before + block + after) == before + after
	assert without_unused_stdio_printers(before + after) == before + after
	for reference in ['v3_eprint_lit("live");', 'v3_eprintln_string(message);', 'v3_eprintf("live");', 'v3_eprint_begin();'] {
		text := before + block + after + reference
		assert without_unused_stdio_printers(text) == text
	}
	unknown := before + block.replace('fflush(stdout);', 'new_runtime_flush(stdout);') + after
	assert without_unused_stdio_printers(unknown) == unknown
	duplicate := before + block + block + after
	assert without_unused_stdio_printers(duplicate) == duplicate
}
