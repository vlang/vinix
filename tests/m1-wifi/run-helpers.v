// SPDX-License-Identifier: ISC
module main

import fixturehost
import hosttest
import applehost
import json2
import os


const original_revision = '700039f0203b626f067794d17d0209c7f5ed2bc1'
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv', '-fno-strict-aliasing']

struct Config {
	env map[string]string
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
	applehost.inherited(argv, c.env, c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	return applehost.capture(argv, c.env, c.caller_arch, directory, binary)!
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
	imports := c.capture([nm, '-u', path], '', false)!
	if imports_forbidden(imports) { return error('Allocator imports: ' + imports) }
	return strings(text_lines(imports))
}


fn (c Config) generate(source string, output string, arch string, guest bool) ! {
	applehost.generate(source, output, arch, if guest { ['nofloat', 'wifi_helper_guest'] } else { ['nofloat'] })!
}

fn (c Config) prepare() !map[string]json2.Any {
 original := c.output('original')
 os.mkdir(original)!
 raw := c.capture(['git','show',original_revision+':tools/m1-wifi/wifi_v.h'],c.root,true)!
 fixturehost.write(append_path(original,'wifi_v.h'),raw)!
 hosttest.module_copy_file(c.header,c.output('wifi_v.h'))!
 provider := c.output('wificli')
 // copytree retains the original provider metadata, symlink and failure policy.
 hosttest.module_copy_tree(c.provider, provider)!
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
  fixturehost.write(core, '#define _POSIX_C_SOURCE 200809L\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n' + hosttest.module_read_text(core)!.replace('\r\n', '\n').replace('\r', '\n'))!
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
	applehost.serial(path, c.arch, join(cc, flags))!
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
  command := applehost.guest_command(c.root, executables['v'], c.arch, c.kernel, c.guest, c.timeout, ['VINIX_WIFI_HELPERS_PASS'], []string{})
	receipt['native']=json2.Any({'arch':json2.Any(c.arch),'imports':json2.Any(imports),'fixture_sha256':json2.Any(hashes(executables['v'])!),'original_fixture_sha256':json2.Any(hashes(executables['original'])!),'kernel_sha256':json2.Any(hashes(append_path(c.kernel,'bin/vinix'))!),'command':strings(command)})
  if !c.build_only {applehost.guest(executables['v'], c.arch, c.kernel, c.guest, c.timeout, ['VINIX_WIFI_HELPERS_PASS'], []string{})!}
  return {'receipt':json2.Any(receipt),'text':json2.Any('PASS strict native Wi-Fi SDK helper objects/ELFs '+c.arch)}
 }
 mut env:=c.env.clone()
 env['UBSAN_OPTIONS']='halt_on_error=1'
 mut statuses:=[]int{}
 mut outputs:=[]string{}
 mut errors:=[]string{}
 for name in ['original','v'] {
  result:=applehost.capture_result([executables[name]],env,c.caller_arch, '')!
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
fn run() ! {
	r := applehost.runtime('wifi-helpers', os.args[1..])!
	defer { r.close() or { eprintln(err.msg()) } }
	c := Config{ root: r.root, work: r.work, caller_arch: r.caller_arch, arch: r.arch, kernel: r.kernel, guest: r.guest, host_arch: r.host_arch, build_only: r.build_only, timeout: r.timeout, env: applehost.environment(), provider: r.options['--provider-source'] or { r.root + '/tools/m1-wifi/core' }, header: r.options['--provider-header'] or { r.root + '/tools/m1-wifi/wifi_v.h' } }
	mut state := c.prepare()!
	state = c.build(false, state)!
	println(state['text'].str())
	if c.arch != '' { state = c.build(true, state)!; println(state['text'].str()) }
	c.phase('finish', state)!
}

fn main() { run() or { applehost.report(err) } }
