// SPDX-License-Identifier: GPL-2.0-only
module policyhost
import json2

const assembly_registers = ['rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'rbp', 'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']
const assembly_globals = ['vinix_x86_mitigation_policies', 'host_cpu_number', 'host_spec_value', 'host_spec_writes', 'host_ibpb', 'host_clears', 'host_registers', 'host_resume_sp']
fn remove_assembly_lines(source string, sizes bool) string {
	lines := source.split('\n'); mut result := []string{}
	for i, line in lines {
		if i < lines.len - 1 && (line.starts_with('.type ') || (sizes && line.starts_with('.size '))) { continue }
		result << line
	}; return result.join('\n')
}
pub fn assembly_content(header_input string, source string) !string {
	if header_input.count('mov %gs:0, %rax') != 1 || header_input.count('wrmsr') != 3 || header_input.count('verw ') != 1 { return failure('RuntimeError', 'hardware adapters require reinspection') }
	mut header := header_input.replace('mov %gs:0, %rax', 'mov _host_cpu_number(%rip), %rax').replace('    wrmsr', '    call _host_wrmsr_adapter').replace('    verw vinix_x86_verw_selector(%rip)', '    call _host_clear_adapter')
	start := index_required(source, '.macro RETPOLINE')!
	end := index_required(source, '/* Noreturn')!
	thunks := remove_assembly_lines(if start > end { '' } else { source[start..end] }, true).replace('__x86_indirect_thunk_', '___x86_indirect_thunk_')
	header = header.replace('vinix_x86_mitigation_policies', '_vinix_x86_mitigation_policies')
	mut probes := ['.global _host_probe', '_host_probe:', 'push %rbx', 'push %rbp', 'push %r12', 'push %r13', 'push %r14', 'push %r15', 'push %rdi']
	for index in 0 .. assembly_registers.len { probes << ['cmp $${index}, %rdi', 'je Lcase${index}'] }
	probes << 'ud2'
	for index, target in assembly_registers {
		probes << 'Lcase${index}:'
		for i, reg in assembly_registers { probes << 'mov $${0x12345678 + i}, %' + reg }
		probes << ['lea Ltarget(%rip), %' + target, 'call ___x86_indirect_thunk_' + target, 'jmp Ldone']
	}
	probes << 'Ltarget:'
	for i, reg in assembly_registers { probes << 'mov %' + reg + ', _host_registers+${i * 8}(%rip)' }
	probes << ['ret', 'Ldone:', 'pop %rdi', 'pop %r15', 'pop %r14', 'pop %r13', 'pop %r12', 'pop %rbp', 'pop %rbx', 'ret']
	resume_start := index_required(source, '.global vinix_x86_resume_context')!
	resume_end := index_required(source, '.size vinix_x86_resume_context')!
	mut resume := if resume_start > resume_end { '' } else { source[resume_start..resume_end] }
	if resume.count('    mov %eax, %ds') != 1 || resume.count('    mov %eax, %es') != 1 || resume.count('    swapgs') != 1 || resume.count('    iretq') != 1 { return failure('RuntimeError', 'scheduler port adapters require reinspection') }
	resume = remove_assembly_lines(resume.replace('vinix_x86_resume_context', '_vinix_x86_resume_context'), false).replace('    mov %eax, %ds', '    nop').replace('    mov %eax, %es', '    nop').replace('    swapgs', '    nop').replace('    iretq', '    jmp _host_resume_finish')
	mut finish := ['.global _host_resume_probe', '_host_resume_probe:', 'push %rbx', 'push %rbp', 'push %r12', 'push %r13', 'push %r14', 'push %r15', 'mov %rsp, _host_resume_sp(%rip)', 'jmp _vinix_x86_resume_context', '_host_resume_finish:']
	for i, reg in assembly_registers { finish << 'mov %' + reg + ', _host_registers+${i * 8}(%rip)' }
	finish << ['mov _host_resume_sp(%rip), %rsp', 'pop %r15', 'pop %r14', 'pop %r13', 'pop %r12', 'pop %rbp', 'pop %rbx', 'ret']
	mut data := '\n.align 8\n'
	for name in assembly_globals { data += '.global _' + name + '\n_' + name + ':\n.zero ' + (if name == 'host_registers' { '120' } else { '8' }) + '\n' }
	return '.text\n' + header + thunks + assembly_ports + probes.join('\n') + '\n' + resume + finish.join('\n') + data
}
fn assembly_fixture(data []u8, symbols map[string]string) !string {
	mut prefix := '#include <sys/mman.h>\n#include <string.h>\nstatic unsigned char *blob;\n'
	prefix += 'static const unsigned char code[]={' + data.map(it.str()).join(',') + '};\n'
	for name in assembly_globals {
		type_name := if name == 'vinix_x86_mitigation_policies' { 'struct policy *' } else { 'uint64_t' }
		offset := symbols['_' + name] or { return failure('KeyError', '_' + name) }
		prefix += if name == 'host_registers' { '#define ' + name + ' ((uint64_t *)(blob+' + offset + '))\n' } else { '#define ' + name + ' (*(' + type_name + ' *)(blob+' + offset + '))\n' }
	}
	for name in ['host_enter', 'host_leave', 'host_switch', 'host_rsb', 'host_probe', 'host_resume_probe'] {
		arg := if name == 'host_resume_probe' { 'uint64_t *, unsigned' } else if name in ['host_switch', 'host_probe'] { 'unsigned' } else { 'void' }
		offset := symbols['_' + name] or { return failure('KeyError', '_' + name) }
		prefix += '#define ' + name + ' ((void (*)(' + arg + '))(blob+' + offset + '))\n'
	}
	lines := assembly_c.replace('struct policy *vinix_x86_mitigation_policies = policies;', '').split('\n')
	mut retained := []string{}
	for i, line in lines { if i < lines.len - 1 && line.ends_with(';') && (line.starts_with('uint64_t host_') || line.starts_with('void host_')) { continue }; retained << line }
	return retained.join('\n').replace('int main(void) {', prefix + 'int main(void) {\nblob=mmap(NULL,sizeof(code),PROT_READ|PROT_WRITE|PROT_EXEC,MAP_PRIVATE|MAP_ANON,-1,0);\nassert(blob!=MAP_FAILED); memcpy(blob,code,sizeof(code));\nvinix_x86_mitigation_policies=policies;\n')
}
fn assembly_execute(directory string, assembly string) ! {
	write_text(directory + '/test.S', assembly)!
	run(['clang', '--target=x86_64-unknown-none', '-c', directory + '/test.S', '-o', directory + '/test.o'])!
	run(['ld.lld', '-m', 'elf_x86_64', '-Ttext=0', '--image-base=0', '--entry=_host_enter', directory + '/test.o', '-o', directory + '/test.elf'])!
	llvm := '/opt/homebrew/opt/llvm/bin'
	run([llvm + '/llvm-objcopy', '-O', 'binary', '--only-section=.text', directory + '/test.elf', directory + '/test.bin'])!
	listing := output([llvm + '/llvm-nm', directory + '/test.elf'])!
	mut symbols := map[string]string{}
	for line in split_lines(listing) {
		fields := whitespace_fields(line)
		if fields.len == 3 { symbols[fields[2]] = callback('integer', {'text': json2.Any(fields[0].bytes().hex()), 'base': json2.Any(16)})!.str() }
	}
	data := read_bytes(directory + '/test.bin')!
	write_text(directory + '/test.c', assembly_fixture(data, symbols)!)!
	run(['clang', '-target', 'x86_64-apple-darwin', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', directory + '/test.c', '-o', directory + '/test'])!
	run(['arch', '-x86_64', directory + '/test'])!
}
pub fn assembly_main(root string) !json2.Any {
	header := read_text(root + '/kernel/asm/x86_64/speculation.h')!
	// Preserve the original header check before opening its second input.
	if header.count('mov %gs:0, %rax') != 1 || header.count('wrmsr') != 3 || header.count('verw ') != 1 { return failure('RuntimeError', 'hardware adapters require reinspection') }
	source := read_text(root + '/kernel/asm/x86_64/speculation.S')!
	content := assembly_content(header, source)!
	directory := temporary('vinix-cpu-assembly-')!
	assembly_execute(directory, content) or { retire(directory)!; return err }
	retire(directory)!
	return json2.Any(0)
}
