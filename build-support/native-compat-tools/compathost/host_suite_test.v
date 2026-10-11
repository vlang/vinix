// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

fn test_hypervisor_diagnostic_inventory_rejects_missing_reordered_checks() {
	control := '#define CHECK(x) x\n CHECK(a);\n CHECK(b);\n'
	assert host_assertion_lines(control, 'check(a, 2)\ncheck(b, 3)\n')! == [2, 3]
	// The original pattern is greedy across each line and requires a word boundary.
	assert host_assertion_lines('CHECK(a);\n', 'recheck(a, 9)\ncheck(a, 9); check(b, 1)\n')! == [1]
	for port in ['check(a, 3)\ncheck(b, 2)', 'check(a, 2)', 'check(a, 2)\nrecheck(b, 3)', 'écheck(a, 2)\ncheck(b, 3)'] {
		mut rejected := false
		host_assertion_lines(control, port) or { rejected = true }
		assert rejected
	}
}

fn test_append_dispatch_allocation_guard_selects_actual_definition() {
	prefix := 'int main__append_write(void* x);\nvoid other(void) { malloc(8); }\n'
	for name in ['append_write', 'main__append_write'] {
		body := '{\n if (x) { return 1; }\n return 0;\n}'
		text := prefix + 'int ' + name + '(void* x) ' + body + '\nvoid after(void) { memdup(0, 0); }'
		assert append_dispatch_body(text)! == body
		append_dispatch_check(text)!
		for marker in ['memdup', 'malloc', 'new_array_from_c_array', 'string__substr'] {
			mut rejected := false
			append_dispatch_check(text.replace('return 0;', marker + '(0);')) or { rejected = true }
			assert rejected
		}
	}
	for text in [prefix, 'int append_write(void* x) {\n if (x) { }\n', 'append_write(void* x) { }'] {
		mut rejected := false
		append_dispatch_body(text) or { rejected = true }
		assert rejected
	}
}

fn test_attribute_source_slice_keeps_exact_original_boundary() {
	function := 'fn (mut x Thing) operation() ? {\n x.value = 3\n}\n// next operation\n'
	text := 'module example\n' + function + '\nfn next() {}\n'
	assert original_function_slice(text, 'fn (mut x Thing) operation(')! == function
	for signature in ['fn missing(', 'fn next('] {
		mut rejected := false
		original_function_slice(text, signature) or { rejected = true }
		assert rejected
	}
}
