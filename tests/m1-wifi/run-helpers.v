// SPDX-License-Identifier: ISC
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

const original_revision = '700039f0203b626f067794d17d0209c7f5ed2bc1'
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv', '-fno-strict-aliasing']

struct Config {
	env map[string]string
	text_encoding string
	root string
	work string
	host_arch string
	caller_arch string
	arch string
	timeout string
	provider string
	header string
	build_only bool
	kernel string
	guest string
}

fn join(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

// POSIX Path preserves literal backslashes in caller-supplied paths.
fn append_path(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

fn (c Config) path(name string) string { return append_path(c.root, name) }
fn (c Config) output(name string) string { return append_path(c.work, name) }

fn (c Config) inherited(argv []string) ! {
	fixturehost.inherited_command_environment_preferred(argv, c.env, c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	closed_stdout := C.fcntl(1, C.F_GETFD) < 0
	if closed_stdout {
		descriptor := C.open(c'/dev/null', C.O_WRONLY)
		if descriptor < 0 { return error('Cannot reserve captured stdout') }
		if descriptor != 1 {
			if C.dup2(descriptor, 1) < 0 {
				C.close(descriptor)
				return error('Cannot reserve captured stdout')
			}
			C.close(descriptor)
		}
		if C.fcntl(1, C.F_SETFD, C.FD_CLOEXEC) != 0 {
			C.close(1)
			return error('Cannot isolate captured stdout reservation')
		}
	}
	defer { if closed_stdout { C.close(1) } }
	return fixturehost.capture_in_preferred(argv, '', c.env, false, directory, binary, c.caller_arch)!
}

fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }
fn hashes(path string) !string { return hosttest.sha(path)! }
const hooks = ['-Dtcgetattr=wifi_helper_tcgetattr', '-Dtcsetattr=wifi_helper_tcsetattr']
fn json_write(path string, value json2.Any) ! {
	fixturehost.write(path, json2.encode(value,
		prettify: true
		indent_string: '  '
		escape_unicode: true
	) + '\n')!
}

fn text_lines(text string) []string {
	mut values := []string{}
	mut value := ''
	mut skip_lf := false
	for ch in text.runes() {
		if skip_lf && ch == `\n` { skip_lf = false; continue }
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133), rune(0x2028), rune(0x2029)] {
			values << value
			value = ''
			skip_lf = ch == `\r`
		} else { value += ch.str() }
	}
	if value != '' { values << value }
	return values
}

// Preserve the original regex's Unicode word boundaries and optional single
// leading underscore, including new_array followed by zero or more word chars.
fn imports_forbidden(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'realloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') || name in ['calloc', 'free'] { return true }
		word = ''
	}
	return false
}

fn (c Config) audit(path string, nm string) !json2.Any {
	// Preserve Python text=True default locale, UTF-8 mode and newline decoding.
	// Only the allocation policy below is native; this decoding leaf is zero credit.
	decode := 'import json,subprocess,sys;value=subprocess.check_output(sys.argv[2:],text=True,encoding=sys.argv[1]);sys.stdout.buffer.write(json.dumps(value).encode("ascii"))'
	wire := c.capture(['python3', '-c', decode, c.text_encoding, nm, '-u', path], '', true)!
	imports := hosttest.decode_json(wire)!.str()
	if imports_forbidden(imports) { return error('Allocator imports: ' + imports) }
	return strings(text_lines(imports))
}


// Keep the established Python module producer's text/error leaves intact.
fn (c Config) generate(source string, output string, arch string, guest bool) ! {
 script := 'import runpy,sys,json;from pathlib import Path;runpy.run_path(sys.argv[1])["generate"](Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],tuple(json.loads(sys.argv[5])))'
 defines := if guest { ['nofloat', 'wifi_helper_guest'] } else { ['nofloat'] }
 c.inherited(['python3','-c',script,c.path('build-support/compile-v-module.py'),source,output,arch,json2.encode(defines)])!
}

fn (c Config) prepare() !map[string]json2.Any {
 original := c.output('original')
 os.mkdir(original)!
 raw := c.capture(['git','show',original_revision+':tools/m1-wifi/wifi_v.h'],c.root,true)!
 fixturehost.write(append_path(original,'wifi_v.h'),raw)!
 hosttest.module_copy_file(c.header,c.output('wifi_v.h'))!
 provider := c.output('wificli')
 // copytree retains the original provider metadata, symlink and failure policy.
 c.inherited(['python3','-c','import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2])',c.provider,provider])!
 mut sources := map[string]json2.Any{}
 for name in os.ls(provider)! {
  if name.ends_with('.v') { sources[name] = hashes(append_path(provider,name))! }
 }
 return {'receipt':json2.Any({'original_revision':json2.Any(original_revision),'original_header_sha256':json2.Any(hashes(append_path(original,'wifi_v.h'))!),'provider_header_sha256':json2.Any(hashes(c.header)!),'V_sources':json2.Any(sources)})}
}

fn (c Config) build(native bool, state map[string]json2.Any) !map[string]json2.Any {
 suffix := if native { '-native' } else { '' }
 arch := if native { if c.arch=='aarch64' { 'arm64' } else { 'amd64' } } else { c.host_arch }
 fixture := c.output('fixture'+suffix+'.c')
 core := c.output('core'+suffix+'.c')
 c.generate(c.path('tests/m1-wifi/helperfixture'),fixture,arch,native)!
 c.generate(c.output('wificli'),core,arch,false)!
 // Keep default Python text encoding/newline and partial-write error semantics.
 prefix := 'from pathlib import Path;import sys;p=Path(sys.argv[1]);p.write_text(sys.argv[2]+p.read_text(encoding=sys.argv[3]),encoding=sys.argv[3])'
 c.inherited(['python3','-c',prefix,core,'#define _POSIX_C_SOURCE 200809L\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n',c.text_encoding])!
 mut cc := []string{}
 if native && c.arch=='aarch64' {
  gcc_root:=c.path('build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl')
  mut versions:=os.ls(gcc_root)!
  versions.sort()
  if versions.len==0 {return error('No AArch64 GCC runtime')}
  cc=[hosttest.env_default('CC_AARCH64','/opt/homebrew/opt/llvm/bin/clang'),'--target=aarch64-linux-musl','--sysroot='+c.path('build-aarch64-userland/sysroot'),'--gcc-install-dir='+append_path(gcc_root,versions.last())]
 } else if native {
  cc=[hosttest.env_default('CC_AMD64','/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
 } else {
  cc=[hosttest.env_default('CC','clang')]
  $if darwin { cc<<['-arch',if arch=='arm64' {'arm64'} else {'x86_64'}] }
 }
 mut flags:=join(['-std=gnu11','-O2','-g','-Wall','-Wextra','-Werror'],quiet)
 if !native {flags<<['-fsanitize=address,undefined','-fno-omit-frame-pointer']}
 quotes:= ['-iquote',c.work,'-iquote',c.path('tests/m1-wifi'),'-iquote',c.path('kernel/c')]
 mut objects:=map[string]string{}
 mut imports:=map[string]json2.Any{}
 for name in ['core','fixture','original'] {
  source:=if name=='core' {core} else {fixture}
  extra:=if name=='core' {join(['-Dmain=wifi_unused_cli_main'],hooks)} else if name=='original' {hooks} else {[]string{}}
  include:=if name=='original' {['-iquote',c.output('original')]} else {[]string{}}
  obj:=c.output(name+suffix+'.o')
  c.inherited(join(cc,flags,include,quotes,extra,['-c',source,'-o',obj]))!
  imports[name]=c.audit(obj,if native {'/opt/homebrew/opt/llvm/bin/llvm-nm'} else {'nm'})!
  objects[name]=obj
 }
 mut serial:=[]string{}
 if native {
  path:=c.output('serial.o')
  script:='import runpy,sys,json;from pathlib import Path;runpy.run_path(sys.argv[1])["compile_serial"](Path(sys.argv[2]),sys.argv[3],json.loads(sys.argv[4]))'
  c.inherited(['python3','-c',script,c.path('tests/kernel-gaps/compile-v-fixture.py'),path,c.arch,json2.encode(join(cc,flags))])!
  serial<<path
 }
 mut executables:=map[string]string{}
 for name in ['original','v'] {
  executable:=c.output(name+suffix+'-init')
  obj:=objects[if name=='original' {'original'} else {'fixture'}]
  link:=if native {if c.arch=='aarch64' {['-static','-fuse-ld=lld']} else {['-static']}} else {[]string{}}
  core_object:=if name=='v' {[objects['core']]} else {[]string{}}
  c.inherited(join(cc,flags,link,[obj],core_object,serial,['-o',executable]))!
  executables[name]=executable
 }
 mut receipt:=state['receipt']!.as_map()
 if native {
  mut command:= ['python3',c.path('tests/kernel-gaps/run.py'),'--arch',c.arch,'--prebuilt-init',executables['v'],'--kernel-dir',c.kernel,'--state-dir',c.guest,'--no-network','--timeout',c.timeout,'--expect','VINIX_WIFI_HELPERS_PASS']
  receipt['native']=json2.Any({'arch':json2.Any(c.arch),'imports':json2.Any(imports),'fixture_sha256':json2.Any(hashes(executables['v'])!),'original_fixture_sha256':json2.Any(hashes(executables['original'])!),'kernel_sha256':json2.Any(hashes(append_path(c.kernel,'bin/vinix'))!),'command':strings(command)})
  if !c.build_only {c.inherited(command)!}
  return {'receipt':json2.Any(receipt),'text':json2.Any('PASS strict native Wi-Fi SDK helper objects/ELFs '+c.arch)}
 }
 mut env:=c.env.clone()
 env['UBSAN_OPTIONS']='halt_on_error=1'
 mut statuses:=[]int{}
 mut outputs:=[]string{}
 mut errors:=[]string{}
 for name in ['original','v'] {
  result:=fixturehost.capture_both_preferred([executables[name]],env,c.caller_arch)!
  fixturehost.write(c.output(name+'.stdout'),result.stdout)!
  fixturehost.write(c.output(name+'.stderr'),result.stderr)!
  statuses<<result.status
  outputs<<result.stdout
  errors<<result.stderr
 }
 if statuses.any(it!=0) {return error('Wi-Fi SDK helper fixture failed')}
 if outputs[0]!=outputs[1] || errors[0]!=errors[1] {return error('Original/V Wi-Fi SDK helper output mismatch')}
 if !outputs[1].contains('VINIX_WIFI_HELPERS_PASS') {return error('Missing Wi-Fi SDK helper pass marker')}
 receipt['host']=json2.Any({'arch':json2.Any(arch),'imports':json2.Any(imports),'stdout_sha256':json2.Any(hashes(c.output('v.stdout'))!)})
 return {'receipt':json2.Any(receipt),'text':json2.Any('PASS original/V Wi-Fi SDK helpers ASan/UBSan '+arch)}
}

fn (c Config) phase(name string,state map[string]json2.Any) !map[string]json2.Any {
 if name=='prepare' {return c.prepare()!}
 if name=='host' || name=='native' {return c.build(name=='native',state)!}
 if name=='finish' {json_write(c.output('validation.json'),state['receipt']!)!;return map[string]json2.Any{}}
 return error('Unknown Wi-Fi helper phase')
}
fn main() {
	parsed := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--phase', true, ['prepare', 'host', 'native', 'finish']}, hosttest.Option{'--parent-stdin', true, []}, hosttest.Option{'--parent-stdout', true, []},
		hosttest.Option{'--root', true, []}, hosttest.Option{'--work', true, []},
		hosttest.Option{'--host-arch', true, ['arm64', 'amd64']}, hosttest.Option{'--caller-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--timeout', true, []}, hosttest.Option{'--provider-source', true, []}, hosttest.Option{'--provider-header', true, []}, hosttest.Option{'--arch', true, ['aarch64', 'x86_64']}, hosttest.Option{'--build-only', false, []},
		hosttest.Option{'--kernel-dir', true, []}, hosttest.Option{'--guest-state-dir', true, []},
	], 0, 'Wi-Fi native tool helper controller', 'Validated original argparse frontend options') or { eprintln(err); exit(2) }
	v := parsed.options
	if '--root' !in v || '--work' !in v { eprintln('Missing root/work directory'); exit(2) }
	input := fixturehost.read('/dev/stdin') or {
		eprintln(err.msg())
		exit(1)
	}
	decoded := hosttest.decode_json(input) or {
		eprintln(err.msg())
		exit(1)
	}
	row := decoded.as_map()
	state := row['state']!.as_map()
	mut caller_env := map[string]string{}
	for value in row['environment']!.as_array() {
		pair := value.as_array()
		key := hex.decode(pair[0].str()) or { eprintln(err.msg()); exit(1) }
		data := hex.decode(pair[1].str()) or { eprintln(err.msg()); exit(1) }
		caller_env[key.bytestr()] = data.bytestr()
	}
	c := Config{env: caller_env, text_encoding: row['text_encoding']!.str(), root: v['--root'], work: v['--work'], host_arch: v['--host-arch'], caller_arch: v['--caller-arch'], arch: v['--arch'], timeout: v['--timeout'], provider: v['--provider-source'], header: v['--provider-header'], build_only: '--build-only' in v, kernel: v['--kernel-dir'], guest: v['--guest-state-dir']}
	protocol := C.fcntl(1, C.F_DUPFD_CLOEXEC, 3)
	if protocol < 0 {
		eprintln('Unable to retain response descriptor')
		exit(1)
	}
	defer { C.close(protocol) }
	for number, name in ['--parent-stdin', '--parent-stdout'] {
		descriptor := (v[name] or {
			eprintln('Missing parent descriptor')
			exit(2)
		}).int()
		if descriptor >= 0 {
			if C.dup2(i32(descriptor), i32(number)) < 0 {
				eprintln('Unable to restore parent descriptor')
				exit(1)
			}
			C.close(i32(descriptor))
		} else {
			C.close(i32(number))
		}
	}
	phase := v['--phase'] or {
		eprintln('Missing phase')
		exit(2)
	}
	result := c.phase(phase, state) or {
		eprintln(err.msg())
		exit(1)
	}
	response := json2.encode(json2.Any(result))
	mut offset := 0
	for offset < response.len {
		count := C.write(protocol, unsafe { response.str + offset }, usize(response.len - offset))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			eprintln('Unable to write controller response')
			exit(1)
		}
		if count == 0 {
			eprintln('Empty controller response write')
			exit(1)
		}
		offset += int(count)
	}
}
