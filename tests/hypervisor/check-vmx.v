// SPDX-License-Identifier: GPL-2.0-only
module main

import fixturehost
import hosttest
import json2
import encoding.hex
import os

fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...i32) i32
fn C.mkdir(&char, u32) i32
fn C.access(&char, i32) i32
fn C.confstr(i32, &char, usize) usize

struct Config {
	root     string
	work     string
	caller   string
	compiler string
	python   string
	v        string
	encoding string
	env      map[string]string
}

struct CheckError {
	kind    string = 'RuntimeError'
	message string
	fields  map[string]json2.Any
}

fn (e CheckError) msg() string { return e.message }

fn (e CheckError) code() int { return 0 }

fn join(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

fn (c Config) path(name string) string { return join(c.root, name) }

fn (c Config) output(name string) string { return join(c.work, name) }

fn combine(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

fn (c Config) common() []string {
	return [c.compiler, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror']
}

fn generated_flags() []string {
	return ['-Wno-unused-function', '-ffreestanding', '-fno-builtin', '-fno-strict-aliasing',
		'-DVINIX_V_RUNTIME']
}

fn (c Config) cross() []string {
	return [c.compiler, '-target', 'x86_64-unknown-none-elf', '-std=gnu11', '-O2', '-Wall', '-Wextra',
		'-Werror', '-mno-red-zone', '-ffreestanding', '-fno-builtin', '-fno-strict-aliasing', '-I',
		c.path('kernel/c')]
}

fn (c Config) inherited(argv []string) ! {
	// Popen searches empty argv[0] through PATH; posix_spawnp short-circuits it.
	// This invalid executable never runs: retain the actual subprocess error.
	if argv.len > 0 && argv[0] == '' {
		c.text_command(argv)!
		return
	}
	fixturehost.inherited_command_environment_preferred(argv, c.env, c.caller)!
}

// A capture pipe must never temporarily turn an originally closed stdout into
// its read end. This local reservation is closed before the next inherited call.
fn (c Config) capture(argv []string) !string {
	closed := C.fcntl(1, C.F_GETFD) < 0
	if closed {
		fd := C.open(c'/dev/null', C.O_WRONLY)
		if fd < 0 { return error('Cannot reserve closed stdout') }
		if fd != 1 {
			if C.dup2(fd, 1) < 0 {
				C.close(fd)
				return error('Cannot reserve closed stdout')
			}
			C.close(fd)
		}
		if C.fcntl(1, C.F_SETFD, C.FD_CLOEXEC) < 0 {
			C.close(1)
			return error('Cannot protect stdout reservation')
		}
	}
	defer { if closed { C.close(1) } }
	return fixturehost.capture_in_preferred(argv, '', c.env, false, '', true, c.caller)!
}

// Actual subprocess text decoding is mechanical and receives zero migration
// credit. Python retains its invoking codec; V owns the checks on this text.
fn (c Config) text_command(argv []string) !string {
	leaf := 'import json,os,subprocess,sys\ntry:\n value={"text":subprocess.check_output(sys.argv[2:],text=True,encoding=sys.argv[1])}\nexcept UnicodeDecodeError as e:\n value={"error":{"kind":"UnicodeDecodeError","encoding":e.encoding,"object":e.object.hex(),"start":e.start,"end":e.end,"reason":e.reason}}\nexcept subprocess.CalledProcessError as e:\n value={"error":{"kind":"command","status":e.returncode,"argv_bytes":[os.fsencode(value).hex() for value in e.cmd],"output":e.output}}\nexcept OSError as e:\n value={"error":{"kind":"os","number":e.errno,"message":e.strerror,"filename_bytes":None if e.filename is None else os.fsencode(e.filename).hex()}}\nsys.stdout.buffer.write(json.dumps(value).encode("ascii"))'
	reply := hosttest.decode_json(c.capture(combine([c.python, '-c', leaf, c.encoding], argv))!)!.as_map()
	if value := reply['error'] {
		row := value.as_map()
		return CheckError{ kind: row['kind']!.str(), fields: row }
	}
	return reply['text']!.str()
}

fn forbidden(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) {
			word += ch.str()
			continue
		}
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup'] || name.starts_with('new_array') {
			return true
		}
		word = ''
	}
	return false
}

fn (c Config) audit(path string) ! {
	imports := c.text_command(['nm', '-u', path])!
	if forbidden(imports) {
		return CheckError{ message: 'VMX unexpectedly imports an allocator:\n' + imports }
	}
}

fn (c Config) generate(name string, files []string, arch string, model bool) !string {
	source := c.output(name)
	if C.mkdir(source.str, u32(0o777)) != 0 {
		return fixturehost.FileError{ filename: source, number: int(C.errno), message: os.get_error_msg(C.errno) }
	}
	fixturehost.write(join(source, 'v.mod'), "Module { name: 'vinix_vmx_tests' }\n")!
	for i, filename in files {
		hosttest.module_copy_file(c.path('kernel/lib/' + filename), join(source, 'source' + i.str() + '.v'))!
	}
	output := c.output(name + '.c')
	mut argv := [c.v, '-shared', '-no-builtin', '-os', 'vinix', '-arch', arch, '-target-libc-headers',
		'-nofloat', '-gc', 'none', '-manualfree']
	if model { argv << ['-d', 'vmx_test'] }
	mut env := c.env.clone()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	fixturehost.inherited_command_environment_preferred(combine(argv, ['-o', output, source]), env, c.caller)!
	return output
}

fn (c Config) host() !map[string]json2.Any {
	sanitizer := ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	include_ := ['-iquote', c.path('kernel/c')]
	for name in ['control', 'unsupported'] {
		model := name == 'control'
		files := if model { ['vmx.v', 'vmx_controls_amd64.v'] } else { ['vmx.v', 'vmx_arm64.v'] }
		source := c.generate(name, files, if model { 'amd64' } else { 'arm64' }, model)!
		obj := c.output(name + '.o')
		c.inherited(combine(c.common(), sanitizer, include_, generated_flags(), ['-c', source,
			'-o', obj]))!
		c.audit(obj)!
		binary := c.output(name + '/test')
		define := if model { ['-DVMX_TEST_PORTS'] } else { []string{} }
		c.inherited(combine(c.common(), sanitizer, include_, define, [
			c.path('tests/hypervisor/vmx_test.c'),
			obj,
			'-o',
			binary,
		]))!
		c.inherited([binary])!
	}
	c.generate('privileged', ['vmx.v', 'vmx_controls_amd64.v', 'vmx_state_amd64.v'], 'amd64', false)!
	return {
		'fx_assert':         json2.Any('\n_Static_assert(sizeof(lib__VmxFxState) == 512, "FXSAVE area");\n')
		'descriptor_assert': json2.Any('_Static_assert(sizeof(struct vinix_vmx_descriptor) == 10, "GDTR/IDTR area");\n')
	}
}

fn text_lines(text string) []string {
	mut result := []string{}
	mut current := ''
	mut cr := false
	for ch in text.runes() {
		if cr && ch == `\n` {
			cr = false
			continue
		}
		cr = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133),
			rune(0x2028), rune(0x2029)] {
			result << current
			current = ''
			cr = ch == `\r`
		} else {
			current += ch.str()
		}
	}
	if current != '' { result << current }
	return result
}

fn control_blocks(text string) []string {
	mut result := []string{}
	mut remaining := text
	for {
		begin := remaining.index('__asm__ volatile (') or { break }
		remaining = remaining[begin + '__asm__ volatile ('.len..]
		end := remaining.index(');') or { break }
		block := remaining[..end]
		for prefix in ['"vmxon', '"vmxoff', '"vmclear', '"vmptrld', '"vmwrite', '"vmread'] {
			if block.contains(prefix) {
				result << block
				break
			}
		}
		remaining = remaining[end + 2..]
	}
	return result
}

fn check_instructions(assembly string, text string) ! {
	for pair in [['on', 'vmxon'], ['off', 'vmxoff'], ['clear', 'vmclear'], ['load', 'vmptrld'],
		['write', 'vmwriteq'], ['read', 'vmreadq']] {
		marker := '<vinix_vmx_' + pair[0] + '>:'
		offset := assembly.index(marker) or { return CheckError{ kind: 'IndexError', message: 'list index out of range' } }
		suffix := assembly[offset + marker.len..]
		function := suffix.all_before('\n\n')
		mut instructions := []string{}
		for line in text_lines(function) {
			if tab := line.index('\t') { instructions << line[tab + 1..] }
		}
		mut position := -1
		for i, line in instructions {
			if line.starts_with(pair[1]) {
				position = i
				break
			}
		}
		if position < 0 { return CheckError{ kind: 'StopIteration' } }
		if position + 1 >= instructions.len {
			return CheckError{ kind: 'IndexError', message: 'list index out of range' }
		}
		if !instructions[position + 1].starts_with('setbe') {
			return CheckError{ message: pair[1] + ' must immediately capture CF/ZF' }
		}
	}
	if !text.contains('"vmwrite %[value], %[field]') {
		return CheckError{ message: 'VMWRITE operand order changed' }
	}
	if !text.contains('"vmread %[field], %[result]') {
		return CheckError{ message: 'VMREAD operand order changed' }
	}
	controls := control_blocks(text)
	if controls.len != 6 { return CheckError{ message: 'VMX flags/memory clobbers changed' } }
	for block in controls {
		if !block.contains('"cc"') || !block.contains('"memory"') {
			return CheckError{ message: 'VMX flags/memory clobbers changed' }
		}
	}
}

fn (c Config) objdump_path() string {
	path := c.env['PATH'] or {
		size := C.confstr(C._CS_PATH, unsafe { nil }, 0)
		if size == 0 {
			'/bin:/usr/bin'
		} else {
			mut buffer := []u8{len: int(size)}
			count := C.confstr(C._CS_PATH, &char(buffer.data), size)
			if count == 0 || count > size {
				'/bin:/usr/bin'
			} else {
				buffer[..int(count) - 1].bytestr()
			}
		}
	}
	if path == '' { return '/opt/homebrew/opt/llvm/bin/llvm-objdump' }
	mut seen := map[string]bool{}
	for directory in path.split(':') {
		if directory in seen { continue }
		seen[directory] = true
		candidate := if directory == '' {
			'llvm-objdump'
		} else {
			directory + if directory.ends_with('/') { '' } else { '/' } + 'llvm-objdump'
		}
		if os.exists(candidate) && C.access(candidate.str, 1) == 0 && !os.is_dir(candidate) {
			return candidate
		}
	}
	return '/opt/homebrew/opt/llvm/bin/llvm-objdump'
}

fn (c Config) phase(name string, state map[string]json2.Any) !map[string]json2.Any {
	match name {
		'host' { return c.host()! }
		'instructions' {
			obj := c.output('privileged.o')
			c.inherited(combine(c.cross(), generated_flags(), ['-c', c.output('privileged.c'),
				'-o', obj]))!
			c.audit(obj)!
			mut objdump := c.env['LLVM_OBJDUMP'] or { '' }
			if objdump == '' { objdump = c.objdump_path() }
			assembly := c.text_command([objdump, '-d', '--no-show-raw-insn', obj])!
			check_instructions(assembly, state['text']!.str())!
		}
		'entry' {
			c.inherited(combine(c.cross(), ['-c', c.path('kernel/asm/x86_64/vmx.S'), '-o',
				c.output('entry.o')]))!
		}
		'reference' {
			c.inherited(combine(c.cross(), ['-c', hex.decode(state['original']!.str())!.bytestr(),
				'-o', c.output('original.o')]))!
		}
		'compare' {
			old := hex.decode(state['old']!.str())!
			new := hex.decode(state['new']!.str())!
			if old.len == 0 || old != new { return CheckError{ message: 'VM entry bytes changed' } }
			return {
				'length': json2.Any(new.len)
			}
		}
		else { return error('Unknown private VMX phase') }
	}
	return map[string]json2.Any{}
}

fn response_error(err IError) map[string]json2.Any {
	mut row := map[string]json2.Any{}
	if err is CheckError {
		row = err.fields.clone()
		row['kind'] = err.kind
		row['message'] = err.message
	} else if err is fixturehost.CommandError {
		row = {
			'kind':       json2.Any('command')
			'status':     json2.Any(err.status)
			'argv_bytes': json2.Any(hosttest.strings(err.argv.map(hex.encode(it.bytes()))))
		}
	} else if err is fixturehost.FileError {
		row = {
			'kind':           json2.Any('os')
			'number':         json2.Any(err.number)
			'filename_bytes': if err.filename == '' {
				json2.Any(json2.Null{})
			} else {
				json2.Any(hex.encode(err.filename.bytes()))
			}
			'message':        json2.Any(err.message)
		}
	} else if err is hosttest.ModuleFileError {
		row = {
			'kind':           json2.Any('os')
			'number':         json2.Any(err.number)
			'filename_bytes': if err.filename == '' {
				json2.Any(json2.Null{})
			} else {
				json2.Any(hex.encode(err.filename.bytes()))
			}
			'message':        json2.Any(err.message)
		}
	} else {
		row = {
			'kind':    json2.Any('RuntimeError')
			'message': json2.Any(err.msg())
		}
	}
	return {
		'error': json2.Any(row)
	}
}

fn main() {
	options := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--root', true, []},
		hosttest.Option{'--work', true, []},
		hosttest.Option{'--caller-arch', true, []},
		hosttest.Option{'--phase', true, []},
		hosttest.Option{'--parent-stdin', true, []},
		hosttest.Option{'--parent-stdout', true, []},
	], 0, 'VMX private controller', 'Frontend-owned source and temporary owner') or {
		eprintln(err)
		exit(2)
	}
	v := options.options
	request := hosttest.decode_json(fixturehost.read('/dev/stdin') or {
		eprintln(err)
		exit(1)
	}) or {
		eprintln(err)
		exit(1)
	}
	row := request.as_map()
	mut env := map[string]string{}
	for value in row['environment']!.as_array() {
		pair := value.as_array()
		env[hex.decode(pair[0].str())!.bytestr()] = hex.decode(pair[1].str())!.bytestr()
	}
	protocol := C.fcntl(1, C.F_DUPFD_CLOEXEC, 3)
	if protocol < 0 {
		eprintln('Cannot retain response')
		exit(1)
	}
	defer { C.close(protocol) }
	for number, name in ['--parent-stdin', '--parent-stdout'] {
		fd := v[name].int()
		if fd >= 0 {
			if C.dup2(i32(fd), i32(number)) < 0 {
				eprintln('Cannot restore inherited descriptor')
				exit(1)
			}
			C.close(i32(fd))
		} else {
			C.close(i32(number))
		}
	}
	c := Config{ root: v['--root'], work: v['--work'], caller: v['--caller-arch'], compiler: hex.decode(row['compiler']!.str())!.bytestr(), python: hex.decode(row['python']!.str())!.bytestr(), v: row['v']!.str(), encoding: row['text_encoding']!.str(), env: env }
	state := if value := row['state'] { value.as_map() } else { map[string]json2.Any{} }
	reply := c.phase(v['--phase'], state) or { response_error(err) }
	output := json2.encode(json2.Any(reply))
	mut offset := 0
	for offset < output.len {
		count := C.write(protocol, unsafe { output.str + offset }, usize(output.len - offset))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			exit(1)
		}
		if count == 0 { exit(1) }
		offset += int(count)
	}
}
