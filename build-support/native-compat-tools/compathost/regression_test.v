// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

fn test_original_done_policy() {
	for prefix in ['CPU', 'JOB', 'MSG'] {
		assert regression_pass(prefix + '-CHECK DONE failures=0\r\n', prefix) or { panic(err) }
		assert !(regression_pass(prefix + '-CHECK DONE failures=00', prefix) or { panic(err) })
		assert !(regression_pass(prefix + '-CHECK DONE failures=90000000000000000000000000000000000000', prefix) or { panic(err) })
		assert !(regression_pass(prefix + '-CHECK DONE failures=1\n' + prefix + '-CHECK DONE failures=0', prefix) or { panic(err) })
		assert !(regression_pass(prefix + '-CHECK DONE failures=0\n' + prefix + '-CHECK FAIL late', prefix) or { panic(err) })
		assert !(regression_pass(prefix + '-CHECK DONE', prefix) or { panic(err) })
		// The original final predicate does not independently reject this text.
		assert regression_pass('KERNEL PANIC\n' + prefix + '-CHECK DONE failures=0', prefix) or { panic(err) }
	}
}

fn test_llvm_attribute_requirements() {
	ir := 'define i32 @protected() #12 {\n}\nattributes #12 = { noinline nounwind sspstrong }\n'
	attributes := llvm_function_attributes(ir, 'protected') or { panic(err) }
	assert stack_protected(attributes)
	assert !stack_protected('nounwind nossp sspstronger')
	assert stack_protected('sspreq')
	assert stack_protected('ssp')
	if _ := llvm_function_attributes(ir, 'missing') { assert false }
	assert greeting.split_into_lines().len == 4
}

fn test_kernel_retention_rows() {
	for arch in ['aarch64', 'x86_64'] {
		mut text := ''
		for op in ['dir', 'proc'] {
			for index in 0 .. if arch == 'aarch64' { 18 } else { 14 } {
				text += 'PERF-RETENTION op=' + op + ' class=' + index.str() + ' objects=-000 bytes=0\n'
			}
			text += 'PERF-RETENTION op=' + op + ' large-pages=0\n'
		}
		inspection_report(text, 'kernel-retention', arch) or { panic(err) }
		for broken in [text.replace_once('bytes=0', 'bytes=184467440737095516160'),
			text.replace_once('objects=-000', 'objects=-1'), text.replace_once('large-pages=0', 'large-pages=1'),
			text + 'PERF-RETENTION op=dir large-pages=0\n'] {
			if _ := inspection_report(broken, 'kernel-retention', arch) { assert false }
		}
	}
}
