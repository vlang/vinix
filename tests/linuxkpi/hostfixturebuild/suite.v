// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixturebuild

import encoding.hex
import fixturehost
import hosttest
import json2
import os

pub struct HostFailure {
pub:
	kind string
	message string
}
pub fn (e HostFailure) msg() string { return e.message }
pub fn (e HostFailure) code() int { return 0 }

pub const groups = [
	['hostmodel', 'host_model_v_contract.h'], ['hostbase', 'hostbase_v_contract.h'],
	['hosttask', 'hosttask_v_contract.h'], ['hostseq', 'hostseq_v_contract.h'],
	['hosttaskflag', 'hosttaskflag_v_contract.h'], ['hostio', 'hostio_v_contract.h'],
	['hostwork', 'hostwork_v_contract.h'], ['synchost', 'synchost_v_contract.h'],
	['wwhost', 'wwhost_v_contract.h'], ['timehost', 'timehost_v_contract.h'],
	['timerhost', 'timerhost_v_contract.h'], ['usleephost', 'usleephost_v_contract.h'],
	['waithost', 'waithost_v_contract.h'], ['policyhostsuite', 'policyhost_v_contract.h'],
	['stringhelpershost', 'stringhelpershost_v_contract.h'], ['bitmaphost', 'bitmaphost_v_contract.h'],
	['cachehost', 'cachehost_v_contract.h'], ['kstrtoxhost', 'kstrtoxhost_v_contract.h'],
	['stringtokenshost', 'stringtokenshost_v_contract.h'], ['formathost', 'formathost_v_contract.h'],
	['loghost', 'loghost_v_contract.h'],
]

pub fn environment(encoded string) !map[string]string {
	bytes := hex.decode(encoded)!
	mut result := map[string]string{}
	for item in bytes.bytestr().split('\x00') {
		if item == '' { continue }
		index := item.index('=') or { return error('Invalid inherited environment record') }
		result[item[..index].clone()] = item[index + 1..].clone()
	}
	return result
}

// Match the complete original word-boundary expression, including Python's
// Unicode 13 word characters and Darwin's optional leading underscore.
pub fn suite_allocation(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['memdup', 'v_malloc'] || name.starts_with('new_array') { return true }
		word = ''
	}
	return false
}

fn directory(tests string, name string) string {
	return tests + '/' + if name == 'hostmodel' { 'hostmodel' } else { 'hostfixtures/' + name }
}

fn argument_path(value string) string {
	prefix := if value.starts_with('//') && !value.starts_with('///') { '//' } else if value.starts_with('/') { '/' } else { '' }
	parts := value.split('/').filter(it != '' && it != '.')
	if parts.len == 0 { return if prefix == '' { '.' } else { prefix } }
	return prefix + parts.join('/')
}

fn argument_prefix(value string) string {
	return if value == '.' { '' } else if value in ['/', '//'] { value } else { value + '/' }
}

pub fn build_suite(work string, arch string, sanitize bool, inherited_environment map[string]string, host_arch string) ! {
	root := hosttest.root()
	tests := root + '/tests/linuxkpi'
	source := argument_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157'))
	source_prefix := argument_prefix(source)
	work_prefix := argument_prefix(work)
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	contracts := work_prefix + 'host-contracts'
	os.mkdir(contracts) or {
		if !os.is_dir(contracts) { return hosttest.ModuleFileError{contracts, err.code(), err.msg()} }
	}
	for group in groups {
		header := group[1]
		mut contract := ''
		for candidate in [directory(tests, group[0]) + '/' + header, tests + '/' + header] {
			if os.exists(candidate) { contract = candidate; break }
		}
		if contract == '' { return HostFailure{'FileNotFoundError', header} }
		hosttest.module_copy_file(contract, contracts + '/' + header)!
	}
	fixturehost.inherited_command_environment_preferred(['python3', root + '/kernel/linuxkpi/generate-abi.py',
		tests + '/host_percpu_abi.json', contracts + '/host_percpu_abi.h'], inherited_environment, host_arch)!
	mut flags := [...compiler, '-std=gnu11', '-fgnu89-inline', if sanitize { '-O1' } else { '-O2' }, '-g',
		'-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections',
		'-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function', '-Wno-unused-label',
		'-Wno-deprecated-declarations', '-D_FORTIFY_SOURCE=0']
	flags << if sanitize { ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] } else { ['-fno-stack-protector', '-D_GNU_SOURCE'] }
	flags << ['-pthread', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-DVINIX_LINUXKPI_FORMAT_HOST_TEST', '-D__KERNEL__',
		'-include', tests + '/host_types.h', '-include', 'linux/kconfig.h', '-include', source_prefix + 'include/linux/compiler_types.h',
		'-iquote', root + '/kernel/c', '-I' + contracts, '-I' + work_prefix + 'include', '-I' + root + '/kernel/linuxkpi/include',
		'-I' + source_prefix + 'include', '-I' + source_prefix + 'include/uapi', '-I' + source_prefix + 'arch/x86/include',
		'-I' + source_prefix + 'arch/x86/include/uapi', '-I' + source_prefix + 'drivers/gpu/drm/i915']
	mut objects := []string{}
	for group in groups {
		name := group[0]
		generated := work_prefix + name + '.c'
		object := work_prefix + name + '.o'
		compiled := generate(directory(tests, name), generated, arch, name != 'hostmodel')!
		print(compiled.stdout); eprint(compiled.stderr)
		fixturehost.inherited_command_environment_preferred([...flags, '-D__sputc=vmh_' + name + '_sputc', '-c', generated, '-o', object], inherited_environment, host_arch)!
		undefined := fixturehost.capture_preferred([hosttest.env_default('NM', 'nm'), '-u', object], '', inherited_environment, false, host_arch)!
		hosttest.module_write_text(work_prefix + name + '.undefined.txt', undefined)!
		if suite_allocation(undefined) { return HostFailure{'RuntimeError', 'Implicit V allocation in ' + name + ': ' + undefined} }
		objects << object
	}
	for name in ['host_model_tls', 'formathost_abi', 'loghost_abi'] {
		object := work_prefix + name + '.o'
		fixturehost.inherited_command_environment_preferred([...compiler, '-x', 'assembler-with-cpp', '-c', tests + '/' + name + '.S', '-o', object], inherited_environment, host_arch)!
		objects << object
	}
	quoted := objects.map(json2.encode(json2.Any(it), escape_unicode: true))
	hosttest.module_write_text(work_prefix + 'host-fixtures.rsp', quoted.join('\n') + '\n')!
	println('LinuxKPI: independent native V host fixtures compiled without implicit V allocations')
}
