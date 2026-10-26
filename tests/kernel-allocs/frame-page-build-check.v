@[has_globals]
module main

import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <signal.h>
fn C.getpgid(i32) i32

__global interrupted = i32(0)
fn interrupt(_ os.Signal) { interrupted = 1 }

const revision = '9acefa77bee69247c837e97987a2377536aa41cc'
const repository = '/Users/alex/code/vinix'
const compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const archiver = '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar'
// Keep this spelling: the LLD multicall executable selects ELF from argv[0].
const linker = '/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld'

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn tree(path string, ancestors []string, mut result map[string]string) ! {
	if ancestors.len > 128 { return error('input nesting limit: ' + path) }
	info := os.lstat(path)!
	kind := info.mode & 0o170000
	result['mode:' + path] = (info.mode & 0o177777).str()
	if kind == 0o120000 {
		result['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if resolved == '' || resolved == path || resolved in ancestors { return error('dangling/cyclic input link: ' + path) }
		result['resolved:' + path] = resolved
		tree(resolved, ancestors, mut result)!
	} else if kind == 0o040000 {
		resolved := os.real_path(path)
		if resolved in ancestors { return error('cyclic directory: ' + path) }
		mut next := ancestors.clone(); next << resolved
		mut names := os.ls(path)!; names.sort()
		for name in names { tree(path + '/' + name, next, mut result)! }
	} else if kind == 0o100000 { result[path] = digest(path)! }
	else { return error('unsupported input type: ' + path) }
}

fn checked(argv []string) !string {
	result := os.exec(argv)
	if result.exit_code != 0 { return error('command refused: ' + argv.str() + '\n' + result.output) }
	return result.output
}

fn relative_tree(root string) !map[string]string {
	mut values := map[string]string{}
	tree(root, [], mut values)!
	mut result := map[string]string{}
	for key, value in values { result[key.replace(root, '@ROOT')] = value.replace(root, '@ROOT') }
	return result
}

fn budget(root string, parent string, admission bool) !string {
	output := checked(['/bin/df', '-k', root])!
	lines := output.trim_space().split_into_lines()
	if lines.len != 2 || lines[1].fields().len < 4 { return error('unexpected df output') }
	minimum := if admission { i64(2097152) } else { i64(1048576) }
	if lines[1].fields()[3].i64() < minimum { return error('actual df below required floor:\n' + output) }
	usage := checked(['/usr/bin/du', '-sk', root, parent])!
	mut total := i64(0)
	for line in usage.trim_space().split_into_lines() {
		fields := line.fields()
		if fields.len < 2 { return error('unexpected du output') }
		total += fields[0].i64()
	}
	if total > 524288 { return error('observed 512MiB worktree+state budget exceeded:\n' + usage) }
	return output + '\n' + usage
}

fn snapshot(root string) !map[string]string {
	mut result := map[string]string{}
	if checked(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'])!.trim_space() != revision { return error('frame baseline changed') }
	for relative in checked(['/usr/bin/git', '-C', root, 'diff', '--name-only', 'HEAD'])!.split_into_lines() {
		if relative !in ['kernel/alloctrack/track_d_alloc_track.v', 'kernel/file/locks.v', 'kernel/memory/slab.v'] {
			return error('unexpected tracked change: ' + relative)
		}
	}
	// GNUmakefile uses find -L, including ignored/untracked sources. Bind all
	// kernel inputs, and refuse additional source roots outside declared deps.
	for relative in checked(['/usr/bin/git', '-C', root, 'ls-files', '--others', '-z', '--', 'kernel'])!.split('\x00') {
		if relative == '' || relative == 'kernel/alloctrack/frame_page.v' { continue }
		mut allowed := false
		for name in ['freestnd-c-hdrs', 'cc-runtime', 'cc-runtime-x86_64', 'cc-runtime-aarch64',
			'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h', 'obj', 'bin'] {
			prefix := 'kernel/' + name
			if relative == prefix || relative.starts_with(prefix + '/') { allowed = true; break }
		}
		if !allowed { return error('unexpected untracked kernel input: ' + relative) }
	}
	files := checked(['/usr/bin/git', '-C', root, 'ls-files', '-z'])!
	for relative in files.split('\x00') {
		if relative == '' { continue }
		path := root + '/' + relative
		if os.exists(path) || os.is_link(path) { tree(path, [], mut result)! }
	}
	for relative in ['kernel/alloctrack/frame_page.v', 'tests/kernel-allocs/frame-page-check.v',
		'tests/kernel-allocs/frame-page-host-check.v', 'tests/kernel-allocs/frame-page-build-check.v'] {
		tree(root + '/' + relative, [], mut result)!
	}
	for name in os.ls(root + '/kernel')! {
		if name in ['obj', 'bin', 'cc-runtime-x86_64', 'cc-runtime-aarch64'] { continue }
		tree(root + '/kernel/' + name, [], mut result)!
	}
	tree(repository + '/kernel/cc-runtime', [], mut result)!
	tree(os.dir(compiler), [], mut result)!
	host_clang := checked(['/usr/bin/xcrun', '--find', 'clang'])!.trim_space()
	host_sdk := checked(['/usr/bin/xcrun', '--show-sdk-path'])!.trim_space()
	if host_clang != '/Library/Developer/CommandLineTools/usr/bin/clang'
		|| host_sdk != '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk' { return error('unexpected host developer tools') }
	result['provenance:host-clang-version'] = checked([host_clang, '--version'])!
	result['provenance:host-sdk-version'] = checked(['/usr/bin/xcrun', '--show-sdk-version'])!
	tree(host_clang, [], mut result)!
	tree('/Library/Developer/CommandLineTools/usr/bin/ld', [], mut result)!
	tree(host_sdk + '/SDKSettings.json', [], mut result)!
	tree(host_sdk + '/SDKSettings.plist', [], mut result)!
	tree(checked([host_clang, '-print-resource-dir'])!.trim_space() + '/include', [], mut result)!
	for path in [clang, archiver, linker, '/usr/bin/make', '/bin/sh', '/usr/bin/cc',
		'/usr/bin/arch', '/usr/bin/file', '/usr/bin/uname', '/usr/bin/find', '/usr/bin/sort',
		'/usr/bin/sed', '/usr/bin/grep', '/bin/cp', '/bin/mv', '/bin/ln', '/bin/mkdir', '/bin/rm',
		'/bin/df', '/usr/bin/du', '/usr/bin/git', '/usr/bin/xcrun', '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm', os.executable()] { tree(path, [], mut result)! }
	for key in ['PATH', 'V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'VMODULES', 'VTMP', 'TMPDIR', 'SDKROOT',
		'CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'VFLAGS', 'MAKEFLAGS', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH',
		'LIBRARY_PATH', 'DEVELOPER_DIR'] {
		if value := os.getenv_opt(key) { result['env:' + key] = value }
		else { result['absent-env:' + key] = 'absent' }
	}
	for path, hash in {
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		archiver: '20bf95222345e846483af09868180d0005a83f70e7df3503e25df9280333e33e'
		os.real_path(linker): '745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b'
		root + '/kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
		root + '/kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
		root + '/kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
		root + '/kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
	} { if result[path] != hash { return error('input digest mismatch: ' + path) } }
	return result
}

fn group_present(pid int) !bool {
	if pid <= 1 || pid == C.getpgid(0) { return error('invalid child group') }
	if C.kill(-pid, 0) == 0 { return true }
	if C.errno == C.ESRCH { return false }
	if C.errno == C.EPERM { return true }
	return error('group probe failed')
}

fn cleanup(mut child os.Process) ! {
	if child.pid <= 1 || child.pid == C.getpgid(0) { return error('invalid cleanup scope') }
	start := time.sys_mono_now()
	for {
		if group_present(child.pid)! { if C.kill(-child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return error('kill group failed') } }
		if child.status !in [.exited, .aborted] || child.code < 0 {
			if C.kill(child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH { return error('kill child failed') }
		}
		alive := child.is_alive()
		if !alive && child.status in [.exited, .aborted] && child.code >= 0 && !group_present(child.pid)! {
			mut status := i32(0)
			if C.waitpid(child.pid, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD { child.wait(); return }
		}
		if time.sys_mono_now() - start > 5_000_000_000 { return error('cleanup deadline') }
		time.sleep(20 * time.millisecond)
	}
}

fn invoke(argv []string, root string, out string, parent string) ! {
	os.write_file(out + '/build.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	mut complete := false
	defer { if !complete && child.pid > 1 { cleanup(mut child) or { eprintln(err) } }; child.close() }
	mut log := os.create(out + '/build.log')!
	defer { log.close() }
	child.set_args(argv[1..]); child.set_work_folder(root)
	child.set_redirect_stdio_merged(); child.use_pgroup = true; child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.sys_mono_now()
	mut confirmed := false
	for _ in 0 .. 100 {
		if C.getpgid(i32(child.pid)) == i32(child.pid) { confirmed = true; break }
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	mut reason := if confirmed { '' } else { 'group not observed' }
	mut total := 0
	mut last_budget := start
	for reason == '' {
		for _ in 0 .. 32 {
			chunk := child.stdout_read(); if chunk.len == 0 { break }
			total += chunk.len
			if total > 32 * 1024 * 1024 { reason = 'log limit'; break }
			log.write_string(chunk)!
		}
		if interrupted != 0 { reason = 'interrupted' }
		if time.sys_mono_now() - start > 900_000_000_000 { reason = '15 minute deadline' }
		if time.sys_mono_now() - last_budget > 5_000_000_000 {
			observation := budget(root, parent, false) or { reason = err.msg(); '' }
			os.write_file(out + '/budget-' + time.sys_mono_now().str() + '.log', observation)!
			last_budget = time.sys_mono_now()
		}
		if reason != '' { break }
		if !child.is_alive() { if group_present(child.pid)! { reason = 'leader exited with descendants' }; break }
		time.sleep(20 * time.millisecond)
	}
	cleanup(mut child)!; complete = true
	for _ in 0 .. 32 {
		chunk := child.stdout_read(); if chunk.len == 0 { break }
		total += chunk.len
		if total > 32 * 1024 * 1024 { reason = 'log limit'; break }
		log.write_string(chunk)!
	}
	os.write_file(out + '/build.status.json', json2.encode({'exit_code': child.code.str(),
		'reason': reason, 'cleanup': 'leader reaped; group absent',
		'elapsed_ms': ((time.sys_mono_now() - start) / 1_000_000).str()}) + '\n')!
	if reason != '' || child.code != 0 { return error('kernel build failed; attempt preserved: ' + out) }
}

fn preserve_outputs(root string, step string, arch string) ! {
	for name in ['obj', 'bin', 'cc-runtime-' + arch] {
		path := root + '/kernel/' + name
		if os.exists(path) || os.is_link(path) {
			if os.exists(step + '/' + name) || os.is_link(step + '/' + name) { return error('duplicate preserved output: ' + name) }
			os.mv(path, step + '/' + name)!
		}
	}
}

fn generated_body(source string, signature string) !string {
	// Pin the definition, rather than accepting a declaration or a dead string.
	start := source.index(signature) or { return error('generated definition absent: ' + signature) }
	mut depth := 1
	for offset := start + signature.len; offset < source.len; offset++ {
		if source[offset] == `{` { depth++ }
		if source[offset] == `}` {
			depth--
			if depth == 0 { return source[start..offset + 1] }
		}
	}
	return error('unterminated generated definition')
}

fn check_generated(source string) ! {
	mut compact := source.replace(' ', '').replace('\t', '').replace('\n', '').replace('\r', '')
	helper := generated_body(compact, 'alloctrack__frame_page_chain(u64*frame,u64minimum){')!
	track := generated_body(compact, 'alloctrack__track_enter(void*pointer,u64size,u64*frame){')!
	// This check is specific to the captured compiler. Keep the complete refusal
	// and both breaks in order, so a late or inverted bound cannot pass.
	guard := helper.replace('(', '').replace(')', '')
	core := 'for;i<10;i++{ifcurrent<minimum||current&7!=0||u64u64current>>12!=u64u64origin>>12||current&0xfff>0xff0{break;}{u64*fp=u64*current;pcs[i]=fp[1];u64next=fp[0];ifnext<=current{break;}current=next;}}'
	if guard.count('>>12') != 2 || !guard.contains(core) {
		return error('generated frame complete guard/read/break ordering changed')
	}
	if !track.contains('alloctrack__frame_page_chain(frame,alloctrack__kernel_address_min())') {
		return error('enabled tracker does not call guarded walker')
	}
	lock_body := generated_body(compact, 'file__set_record_lock(file__Handle*handle,file__Flock*flock,boolblocking,boolofd,file__LockRangerange){')!
	if !lock_body.contains('__if_val_0=(u64)(handle);') || lock_body.count('file__Handle') != 1 {
		return error('OFD owner does not retain the borrowed Handle pointer')
	}
	partial := generated_body(compact, 'memory__Slab__add_partial(memory__Slab*this,memory__SlabHeader*hdr){')!
	if partial != 'memory__Slab__add_partial(memory__Slab*this,memory__SlabHeader*hdr){hdr->prev=0;hdr->next=this->partial;if(this->partial!=0){memory__SlabHeader*next=(memory__SlabHeader*)(this->partial);next->prev=(u64)(hdr);}this->partial=(u64)(hdr);}' {
		return error('slab insertion does not retain the exact borrowed pointer operations')
	}
	for name in ['memdup(', 'malloc(', 'memcpy(', 'memmove(', 'new_array', 'builtin__memdup'] {
		if lock_body.contains(name) { return error('unexpected Handle copy or allocation: ' + name) }
	}
	unsafe { compact.free() }
}

fn check_generated_controls(source string) ! {
	check_generated(source)!
	compact := source.replace(' ', '').replace('\t', '').replace('\n', '').replace('\r', '')
	mut checks := 0
	for original, replacement in {
		'current<minimum': 'current<0'
		'current&7': 'current&3'
		'current&0xfff': 'current&0x1fff'
		'>0xff0': '>0xff8'
		'i<10': 'i<11'
		'next<=current': 'next==current'
		'pcs[i]=(fp)[1]': 'pcs[i]=(fp)[0]'
		'alloctrack__frame_page_chain(frame,': 'alloctrack__unchecked_chain(frame,'
		'__if_val_0=(u64)(handle);': '__if_val_0=(u64)(*handle);'
		'next->prev=(u64)(hdr);': 'next->prev=(u64)(*hdr);'
		'this->partial=(u64)(hdr);': 'this->partial=(u64)(*hdr);'
		'>>(12)))!=': '>>(12)))=='
		'{break;}{u64*fp': '{}{u64*fp'
		'if(next<=current){break;}': 'if(next<=current){}'
	} {
		changed := compact.replace(original, replacement)
		if changed == compact { return error('generated-C control did not mutate: ' + original) }
		mut refused := false
		check_generated(changed) or { refused = true }
		if !refused { return error('generated-C negative control accepted: ' + original) }
		checks++
	}
	for bound in ['current<minimum', '(current&7)!=0',
		'((u64)(((u64)(current))>>(12)))!=((u64)(((u64)(origin))>>(12)))',
		'(current&0xfff)>0xff0'] {
		changed := compact.replace(bound, '0').replace('pcs[i]=(fp)[1];',
			'pcs[i]=(fp)[1];if(' + bound + '){break;}')
		if !compact.contains(bound) || changed == compact { return error('late-bound control did not mutate') }
		mut refused := false
		check_generated(changed) or { refused = true }
		if !refused { return error('late generated bound accepted: ' + bound) }
		checks++
	}
	if checks != 18 { return error('incomplete generated-C controls') }
}

fn qualify_arch(root string, step string, parent string, arch string, before map[string]string) !map[string]string {
	os.write_file(step + '/budget-before.log', budget(root, parent, true)!)!
	argv := ['/usr/bin/make', '-C', root + '/kernel', '-j2', 'ARCH=' + arch, 'ALLOC_TRACK=1',
		'PROD=true', 'LIMINE_MP=' + if arch == 'aarch64' { '1' } else { '0' }, 'LINUXKPI=0',
		'PCI_CONFIG_TEST=0', 'PCI_TOPOLOGY_TEST=0', 'ACPI_SYNC_TEST=0', 'STACK_GUARD_TEST=0',
		'KERNEL_LINK_RANDOMIZE=0', 'V=' + compiler, 'CC=' + clang, 'AR=' + archiver,
		'LD_X86_64=' + linker, 'LD_AARCH64=' + linker]
	invoke(argv, root, step, parent)!
	after := snapshot(root)!; os.write_file(step + '/inputs-after.json', json2.encode(after) + '\n')!
	if before != after { return error('source/tool/dependency input changed') }
	generated := os.read_file(root + '/kernel/obj/blob.c')!
	check_generated_controls(generated)!
	os.write_file(step + '/generated-checks.log', 'actual helper/callsite/borrowed pointers PASS; 18 mutated-C refusals PASS\n')!
	elf := root + '/kernel/bin/vinix'
	header := checked(['/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf', '-h', elf])!
	if !header.contains(if arch == 'aarch64' { 'AArch64' } else { 'Advanced Micro Devices X86-64' }) { return error('wrong ELF machine') }
	os.write_file(step + '/elf-header.log', header)!
	symbols := checked(['/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm', elf])!
	if !symbols.contains('alloctrack__track_enter') { return error('ALLOCTRACK symbol absent') }
	os.write_file(step + '/symbols.log', symbols)!
	preserve_outputs(root, step, arch)!
	mut artifacts := map[string]string{}; tree(step, [], mut artifacts)!
	os.write_file(step + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(step + '/budget-after.log', budget(root, parent, false)!)!
	return {arch + '_elf': digest(step + '/bin/vinix')!, arch + '_c': digest(step + '/obj/blob.c')!}
}

fn run() ! {
	if os.args.len != 2 { return error('usage: frame-page-build-check NEW-ABSOLUTE-OUT') }
	root := os.dir(os.dir(os.dir(@FILE)))
	out := os.args[1]
	if !out.starts_with('/') || os.exists(out) || os.is_link(out) { return error('fresh absolute output required') }
	if checked(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'])!.trim_space() != revision { return error('wrong frame baseline') }
	parent := os.dir(out)
	if !os.is_dir(parent) { return error('create dedicated parent first') }
	admission := budget(root, parent, true)!
	os.mkdir(out)!; os.mkdir(out + '/tmp')!; os.mkdir(out + '/modules')!
	os.write_file(out + '/budget-admission.log', admission)!
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	for key in ['CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'VFLAGS', 'MAKEFLAGS', 'CPATH', 'C_INCLUDE_PATH',
		'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'SDKROOT', 'VHOME', 'V_MACOS_V3_CALLER_VCHILD'] { os.unsetenv(key) }
	for key, value in {'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VMODULES': out + '/modules',
		'VTMP': out + '/tmp', 'TMPDIR': out + '/tmp', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'} { os.setenv(key, value, true) }
	for relative in ['freestnd-c-hdrs', 'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h'] {
		path := root + '/kernel/' + relative
		if !os.exists(path) && !os.is_link(path) { os.symlink(repository + '/kernel/' + relative, path)! }
		if !os.is_link(path) || os.readlink(path)! != repository + '/kernel/' + relative { return error('unexpected dependency destination: ' + path) }
	}
	if !os.exists(root + '/kernel/cc-runtime') { os.cp_all(repository + '/kernel/cc-runtime', root + '/kernel/cc-runtime', false)! }
	if relative_tree(root + '/kernel/cc-runtime')! != relative_tree(repository + '/kernel/cc-runtime')! {
		return error('local cc-runtime differs from pinned original')
	}
	for name in ['obj', 'bin', 'cc-runtime-x86_64', 'cc-runtime-aarch64'] {
		if os.exists(root + '/kernel/' + name) || os.is_link(root + '/kernel/' + name) { return error('fresh kernel output required: ' + name) }
	}
	before := snapshot(root)!
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	os.write_file(out + '/source-revision.txt', revision + '\n')!
	os.write_file(out + '/source-status.txt', checked(['/usr/bin/git', '-C', root, 'status', '--short'])!)!
	os.write_file(out + '/source.patch', checked(['/usr/bin/git', '-C', root, 'diff', '--',
		'kernel/alloctrack/track_d_alloc_track.v', 'kernel/file/locks.v', 'kernel/memory/slab.v'])!)!
	for relative in ['kernel/alloctrack/frame_page.v', 'tests/kernel-allocs/frame-page-build-check.v'] {
		os.mkdir_all(out + '/source/' + os.dir(relative))!; os.cp(root + '/' + relative, out + '/source/' + relative)!
	}
	mut results := map[string]string{}
	for arch in ['x86_64', 'aarch64'] {
		step := out + '/' + arch; os.mkdir(step)!
		qualified := qualify_arch(root, step, parent, arch, before) or {
			failure := err.msg()
			os.write_file(step + '/failure.txt', failure + '\n')!
			if current := snapshot(root) {
				os.write_file(step + '/inputs-after-failure.json', json2.encode(current) + '\n')!
			} else {
				os.write_file(step + '/input-failure.txt', err.msg() + '\n')!
			}
			preserve_outputs(root, step, arch) or {
				os.write_file(step + '/preservation-failure.txt', err.msg() + '\n')!
			}
			return error(failure)
		}
		for key, value in qualified { results[key] = value }
		println('FRAME-PAGE KERNEL BUILD PASS ' + arch)
	}
	os.write_file(out + '/qualification.json', json2.encode(results) + '\n')!
	println('FRAME-PAGE BOTH KERNELS PASS ' + digest(out + '/qualification.json')!)
}

fn main() { run() or { eprintln(err); exit(1) } }
