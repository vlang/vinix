// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import crypto.sha256
import dylibclosure
import json2
import os
import strings
import time

#flag -I @DIR
#include "abi.h"
#include <errno.h>
#include <signal.h>
@[typedef]
struct C.vinix_peer_child_info { si_pid i32 si_code i32 si_status i32 }
fn C.getpgid(i32) i32
fn C.waitid(i32, u32, &C.vinix_peer_child_info, i32) i32

__global interrupted = i32(0)
__global inventory_deadline = i64(0)
__global inventory_entries = int(0)
__global inventory_active = false
__global owner_deadline = i64(0)
fn interrupt(_ os.Signal) { interrupted = 1 }

const revision = '9acefa77bee69247c837e97987a2377536aa41cc'
// This checkout adds reports/tests only; its tracked kernel must still equal revision.
const frame_baseline_revision = 'b262bf48f44b6cd1e9f3b73a7d8b0a079bc98943'
const repository = '/Users/alex/code/vinix'
const frame_baseline_root = repository + '/build/package-alloc-track-frame-worktree'
const compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const bootstrap_compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
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
		if inventory_active && time.sys_mono_now() > inventory_deadline { return error('input inventory deadline') }
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn tree(path string, ancestors []string, mut result map[string]string) ! {
	inventory_entries++
	if inventory_entries > 250000 || inventory_active && time.sys_mono_now() > inventory_deadline {
		return error('input inventory entry/deadline limit')
	}
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

struct ChildExit { exited bool code int }

// Observe without reaping, reserving the leader PID until group retirement.
fn observed_exit(pid int) !ChildExit {
	mut info := C.vinix_peer_child_info{}
	for {
		if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	return ChildExit{info.si_pid == pid,
		if info.si_code == C.CLD_EXITED { int(info.si_status) } else { 128 + int(info.si_status) }}
}

fn checked_bounded(argv []string, timeout i64, limit int) !string {
	if argv.len == 0 || argv.any(it.contains('\x00')) || timeout <= 0 || limit <= 0 {
		return error('invalid probe command/bounds')
	}
	mut child := os.new_process(argv[0])
	mut complete := false
	defer { if !complete && child.pid > 1 { cleanup(mut child) or { eprintln(err) } }; child.close() }
	child.set_args(argv[1..]); child.set_redirect_stdio_merged(); child.use_pgroup = true; child.run()
	if child.pid <= 1 { return error('probe did not start: ' + argv.str()) }
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	mut output := strings.new_builder(8192)
	defer { unsafe { output.free() } }
	start := time.sys_mono_now()
	for {
		if interrupted != 0 { return error('probe interrupted: ' + argv.str()) }
		if time.sys_mono_now() - start > timeout
			|| inventory_active && time.sys_mono_now() > inventory_deadline
			|| owner_deadline > 0 && time.sys_mono_now() > owner_deadline {
			return error('probe deadline: ' + argv.str())
		}
		for _ in 0 .. 32 {
			chunk := child.stdout_read(); if chunk.len == 0 { break }
			if output.len > limit - chunk.len { return error('probe output limit: ' + argv.str()) }
			output.write_string(chunk)
		}
		if observed_exit(child.pid)!.exited { break }
		time.sleep(10 * time.millisecond)
	}
	cleanup(mut child)!; complete = true
	for _ in 0 .. 32 {
		chunk := child.stdout_read(); if chunk.len == 0 { break }
		if output.len > limit - chunk.len { return error('probe output limit: ' + argv.str()) }
		output.write_string(chunk)
	}
	if child.code != 0 { return error('command refused: ' + argv.str() + '\n' + output.str()) }
	return output.str()
}

fn checked(argv []string) !string {
	return checked_bounded(argv, 10_000_000_000, 8 * 1024 * 1024)
}

fn relative_tree(root string) !map[string]string {
	mut values := map[string]string{}
	tree(root, [], mut values)!
	mut result := map[string]string{}
	for key, value in values { result[key.replace(root, '@ROOT')] = value.replace(root, '@ROOT') }
	return result
}

fn budget(root string, parent string, admission bool) !string {
	output := checked(['/bin/df', '-k', parent])!
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

fn snapshot(root string, frame_baseline bool) !map[string]string {
	inventory_entries = 0
	inventory_deadline = time.sys_mono_now() + 120_000_000_000
	inventory_active = true
	defer { inventory_active = false }
	mut result := map[string]string{}
	result['revision'] = checked(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'])!.trim_space()
	if result['revision'] != if frame_baseline { frame_baseline_revision } else { revision } {
		return error('reviewed checkout changed')
	}
	if frame_baseline {
		if checked(['/usr/bin/git', '-C', root, 'diff', revision, 'HEAD', '--', 'kernel'])! != '' {
			return error('frame baseline tracked kernel differs from source base')
		}
		result['kernel-source-base'] = revision
	}
	result['tracked-kernel-patch'] = checked(['/usr/bin/git', '-C', root, 'diff', 'HEAD', '--', 'kernel'])!
	changed := checked(['/usr/bin/git', '-C', root, 'diff', '--name-only', 'HEAD'])!
	if frame_baseline && changed != 'kernel/alloctrack/track_d_alloc_track.v\nkernel/file/locks.v\nkernel/memory/slab.v\n' {
		return error('frame baseline requires exactly the three reviewed tracked frame edits')
	}
	for relative in changed.split_into_lines() {
		if relative !in ['kernel/alloctrack/track_d_alloc_track.v', 'kernel/file/locks.v', 'kernel/memory/slab.v',
			'kernel/socket/public/public.v', 'kernel/socket/socket.v', 'kernel/socket/unix/unix.v'] {
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
		'tests/kernel-allocs/frame-page-host-check.v'] {
		tree(root + '/' + relative, [], mut result)!
	}
	// The baseline checkout predates the controller. Bind its maintained source
	// at the controller checkout separately from all baseline checkout inputs.
	controller_root := if frame_baseline { os.dir(os.dir(os.dir(@FILE))) } else { root }
	if frame_baseline {
		result['controller-root'] = controller_root
		result['controller-revision'] = checked(['/usr/bin/git', '-C', controller_root, 'rev-parse', 'HEAD'])!.trim_space()
	}
	tree(controller_root + '/tests/socket-peer-login', [], mut result)!
	for name in os.ls(root + '/kernel')! {
		if name in ['obj', 'bin', 'cc-runtime-x86_64', 'cc-runtime-aarch64'] { continue }
		tree(root + '/kernel/' + name, [], mut result)!
	}
	tree(repository + '/kernel/cc-runtime', [], mut result)!
	tree(os.dir(compiler), [], mut result)!
	// The controller uses the corrected host os.Process ABI, while target
	// kernels intentionally retain the qualified original compiler closure.
	tree(os.dir(bootstrap_compiler), [], mut result)!
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
	host_git := checked(['/usr/bin/xcrun', '--find', 'git'])!.trim_space()
	if host_git != '/Library/Developer/CommandLineTools/usr/bin/git' { return error('unexpected host git') }
	loaded := dylibclosure.closure([compiler, bootstrap_compiler, os.executable(), clang,
		archiver, linker, '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm', host_clang, host_git,
		'/Library/Developer/CommandLineTools/usr/bin/ld'], checked)!
	for path in loaded.paths { tree(path, [], mut result)! }
	for key, value in loaded.metadata { result['dylib:' + key] = value }
	for path in [clang, archiver, linker, '/usr/bin/make', '/bin/sh', '/usr/bin/cc',
		'/usr/bin/arch', '/usr/bin/file', '/usr/bin/uname', '/usr/bin/find', '/usr/bin/sort',
		'/usr/bin/sed', '/usr/bin/grep', '/bin/cp', '/bin/mv', '/bin/ln', '/bin/mkdir', '/bin/rm',
		'/bin/df', '/usr/bin/du', '/usr/bin/git', '/usr/bin/xcrun', '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm', os.executable()] { tree(path, [], mut result)! }
	for key, value in os.environ() { result['env:' + key] = value }
	for path, hash in {
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		bootstrap_compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		archiver: '20bf95222345e846483af09868180d0005a83f70e7df3503e25df9280333e33e'
		os.real_path(linker): '745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b'
		root + '/kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
		root + '/kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
		root + '/kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
		root + '/kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
		root + '/kernel/socket/public/public.v': if frame_baseline { 'fd712e3ba325aef0f35294e99a66b478f1d8793efb27e650b4bf9a09eaf8fa61' } else { '19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a' }
		root + '/kernel/socket/socket.v': if frame_baseline { '35fd58065b385cea8e0d29cf3aba2438230a3340f369679065f15221525b71cb' } else { '98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8' }
		root + '/kernel/socket/unix/unix.v': if frame_baseline { '5a133bfc68668f4dff1d21e4dea02ac2146d0f12ab6e96d2e0289c98bc5c3656' } else { 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810' }
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
	if child.status in [.exited, .aborted] {
		mut status := i32(0)
		if C.waitpid(child.pid, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('completed leader not reaped') }
		if group_present(child.pid)! { return error('group remained after reap; refusing reused-ID signal') }
		return
	}
	start := time.sys_mono_now()
	// Retire while waitid still reserves the leader PID. Never signal an
	// already reaped PID/group, which could belong to another owner by then.
	if C.kill(-child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH {
		code := C.errno
		// Darwin can refuse a signal to an already dead, unreaped leader.
		// Accept this only after WNOWAIT confirms exit, then require absence.
		if code != C.EPERM || !observed_exit(child.pid)!.exited { return error('kill group failed: errno=' + code.str()) }
	}
	if C.kill(child.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH {
		code := C.errno
		if code != C.EPERM || !observed_exit(child.pid)!.exited { return error('kill child failed: errno=' + code.str()) }
	}
	for {
		if observed_exit(child.pid)!.exited { break }
		if time.sys_mono_now() - start > 5_000_000_000 { return error('cleanup deadline') }
		time.sleep(20 * time.millisecond)
	}
	child.wait()
	mut status := i32(0)
	if C.waitpid(child.pid, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('leader not reaped exactly once') }
	for group_present(child.pid)! {
		if time.sys_mono_now() - start > 5_000_000_000 { return error('group absence deadline') }
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
	owner_deadline = i64(start) + 900_000_000_000
	defer { owner_deadline = 0 }
	mut confirmed := false
	for _ in 0 .. 100 {
		if C.getpgid(i32(child.pid)) == i32(child.pid) { confirmed = true; break }
		if observed_exit(child.pid)!.exited { confirmed = true; break }
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
		if observed_exit(child.pid)!.exited { break }
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

fn required_offset(body string, token string) !int {
	return body.index(token) or { return error('generated token absent: ' + token) }
}

// Pin the new public record and the actual cached scalar operations. These
// are compiler/source checks; runtime peer identity and lifetimes need guests.
fn check_generated_peer(source string) ! {
	compact := source.replace(' ', '').replace('\t', '').replace('\n', '').replace('\r', '')
	defer { unsafe { compact.free() } }
	if !compact.contains('#definepublic__so_peerlogin(0x564c)')
		|| !compact.contains('structpublic__PeerLogin{u32login_uid;u32login_session;};') {
		return error('cached peer public constant/two-u32 ABI changed')
	}
	peer := generated_body(compact, '__v_option_public__PeerLoginunix__UnixSocket__peer_login(unix__UnixSocket*this){')!
	if !peer.contains('katomic__load_T_u32(&this->peer_login_state)!=unix__peer_login_connected')
		|| !peer.contains('errno__set(errno__enotconn)')
		|| !peer.contains('u64identity=katomic__load_T_u64(&this->peer_login_value);') {
		return error('peer identity does not return the cached connected tuple')
	}
	flat_peer := peer.replace('(', '').replace(')', '')
	if !flat_peer.contains('.login_uid=u32identity,') || !flat_peer.contains('.login_session=u32')
		|| !flat_peer.contains('identity>>32') { return error('peer packed tuple decode changed') }
	for name in ['proc__', 'memdup(', 'malloc(', 'new_array'] {
		if peer.contains(name) { return error('peer getter lookup/allocation changed: ' + name) }
	}
	publish := generated_body(compact, 'voidunix__UnixSocket__publish_peer_login(unix__UnixSocket*this,u32uid,u32session){')!
	store := 'katomic__store_T_u64(&this->peer_login_value,(u64)(uid)|((u64)(((u64)((u64)(session)))<<(32))));'
	barrier := 'katomic__sync();'
	commit := 'katomic__cas_T_u32(&this->peer_login_state,unix__peer_login_connecting,unix__peer_login_connected);'
	if !publish.contains(store) || !publish.contains(barrier) || !publish.contains(commit)
		|| required_offset(publish, store)! >= required_offset(publish, barrier)!
		|| required_offset(publish, barrier)! >= required_offset(publish, commit)! {
		return error('peer atomic packing/publication order changed')
	}
	close := generated_body(compact, 'voidunix__UnixSocket__close_endpoint(unix__UnixSocket*this){')!
	if !close.contains('katomic__store_T_u32(&this->peer_login_state,unix__peer_login_closed);') {
		return error('close does not permanently retire peer identity')
	}
	syscall := generated_body(compact, 'multi_return_u64_u64socket__syscall_getsockopt(void*_0,i64fdnum,i64level,i64optname,u64optval,u64optlen){')!
	option := generated_body(syscall, 'if((level==public__sol_socket)&&(optname==public__so_peerlogin)){')!
	for token in ['capacity<sizeof(public__PeerLogin)', 'errno__einval', 'unix__UnixSocket__peer_login(',
		'u32written=(u32)(sizeof(public__PeerLogin));',
		'usercopy__copy_to_user(optval,(void*)(&identity),sizeof(public__PeerLogin))',
		'usercopy__copy_to_user(optlen,(void*)(&written),sizeof(u32))', 'errno__efault', 'errno__enoprotoopt'] {
		if !option.contains(token) { return error('peer option copy/refusal changed: ' + token) }
	}
	connect := generated_body(compact, '__v_optionunix__UnixSocket__connect(unix__UnixSocket*this,void*_handle,void*_addr,u32addrlen){')!
	for token in ['.owner_login_uid=socket->owner_login_uid', '.owner_login_session=socket->owner_login_session',
		'unix__UnixSocket__publish_peer_login(connection_socket,login_uid,login_session);',
		'unix__UnixSocket__publish_peer_login(this,socket->owner_login_uid,socket->owner_login_session);',
		'.peer_login_state=unix__peer_login_connecting',
		'katomic__cas_T_u32(&this->peer_login_state,unix__peer_login_idle,unix__peer_login_connecting)',
		'katomic__cas_T_u32(&this->peer_login_state,unix__peer_login_connecting,unix__peer_login_idle)',
		'errno__eisconn', 'errno__ealready', 'errno__econnrefused'] {
		if !connect.contains(token) { return error('connect cached identity changed: ' + token) }
	}
	if connect.count('proc__login_identity(client->pid)') != 1
		|| connect.contains('client->login_uid') || connect.contains('client->login_session')
		|| required_offset(connect, 'proc__login_identity(client->pid)')! >= required_offset(connect, 'unix__lookup_bound(')!
		|| required_offset(connect, 'unix__peer_login_idle,unix__peer_login_connecting')! >= required_offset(connect, 'unix__lookup_bound(')!
		|| required_offset(connect, 'unix__UnixSocket__publish_peer_login(this,')! >= required_offset(connect, 'this->connected=true;')!
		|| required_offset(connect, 'this->connected=true;')! >= required_offset(connect, 'array_push(&socket->backlog')! {
		return error('connect snapshot/claim/publication order changed')
	}
	create := generated_body(compact, '__v_option_unix__UnixSocketptrunix__create(i64_v_type){')!
	pair := generated_body(compact, '__v_option_multi_return_unix__UnixSocketptr_unix__UnixSocketptrunix__create_pair(i64_v_type){')!
	for body in [create, pair] {
		if body.count('proc__login_identity(process->pid)') != 1 || body.contains('process->login_uid')
			|| body.contains('process->login_session') { return error('socket creation snapshot is not coherent once per operation') }
	}
	for token in ['.owner_login_uid=login_uid', '.owner_login_session=login_session'] {
		if create.count(token) != 1 || pair.count(token) != 2 { return error('socket creation identity snapshot changed') }
	}
	for token in ['unix__UnixSocket__publish_peer_login(a,b->owner_login_uid,b->owner_login_session);',
		'unix__UnixSocket__publish_peer_login(b,a->owner_login_uid,a->owner_login_session);'] {
		if !pair.contains(token) { return error('socketpair cached identity changed: ' + token) }
	}
	if pair.count('.peer_login_state=unix__peer_login_connecting') != 2 { return error('socketpair publication ownership changed') }
	identity := generated_body(compact, 'multi_return_u32_u32proc__login_identity(i64pid){')!
	if !identity.contains('proc__lock_table();') || !identity.contains('proc__unlock_table();')
		|| !identity.contains('process->login_uid,process->login_session')
		|| required_offset(identity, 'proc__lock_table();')! >= required_offset(identity, 'process->login_uid,process->login_session')! {
		return error('process identity snapshot lost its table lock')
	}
}

fn check_generated_peer_controls(source string) ! {
	check_generated_peer(source)!
	compact := source.replace(' ', '').replace('\t', '').replace('\n', '').replace('\r', '')
	defer { unsafe { compact.free() } }
	mut checks := 0
	for original, replacement in {
		'#definepublic__so_peerlogin(0x564c)': '#definepublic__so_peerlogin(0x564d)'
		'u32login_session;};': 'u64login_session;};'
		'katomic__load_T_u32(&this->peer_login_state)': '((u32)(2))'
		'katomic__load_T_u64(&this->peer_login_value)': '((u64)(0))'
		'u64identity=katomic__load_T_u64': 'u32identity=katomic__load_T_u64'
		'>>': '<<'
		'katomic__store_T_u64(&this->peer_login_value,': 'katomic__store_T_u32(&this->peer_login_value,'
		'katomic__sync();': ''
		'(u64)(uid)|': '(u64)(session)|'
		'<<(32)': '<<(31)'
		'unix__peer_login_connecting,unix__peer_login_connected': 'unix__peer_login_idle,unix__peer_login_connected'
		'katomic__store_T_u32(&this->peer_login_state,unix__peer_login_closed);': ''
		'capacity<sizeof(public__PeerLogin)': 'capacity<0'
		'u32written=(u32)(sizeof(public__PeerLogin));': 'u32written=4;'
		'usercopy__copy_to_user(optval,(void*)(&identity),sizeof(public__PeerLogin))': 'usercopy__copy_to_user(optval,(void*)(&identity),sizeof(u32))'
		'unix__UnixSocket__publish_peer_login(connection_socket,login_uid,login_session);': ''
		'unix__UnixSocket__publish_peer_login(this,socket->owner_login_uid,socket->owner_login_session);': ''
		'unix__peer_login_idle,unix__peer_login_connecting': 'unix__peer_login_idle,unix__peer_login_connected'
		'unix__peer_login_connecting,unix__peer_login_idle': 'unix__peer_login_connected,unix__peer_login_idle'
		'proc__login_identity(client->pid)': 'proc__login_identity(0)'
		'proc__login_identity(process->pid)': 'proc__login_identity(0)'
		'.owner_login_uid=login_uid': '.owner_login_uid=process->euid'
		'.owner_login_session=login_session': '.owner_login_session=0'
		'unix__UnixSocket__publish_peer_login(a,b->owner_login_uid,b->owner_login_session);': ''
		'unix__UnixSocket__publish_peer_login(b,a->owner_login_uid,a->owner_login_session);': ''
		'.peer_login_state=unix__peer_login_connecting': '.peer_login_state=unix__peer_login_connected'
		'proc__lock_table();': ''
	} {
		changed := compact.replace(original, replacement)
		if changed == compact { return error('peer generated-C control did not mutate: ' + original) }
		mut refused := false
		check_generated_peer(changed) or { refused = true }
		if !refused { return error('peer generated-C negative control accepted: ' + original) }
		checks++
	}
	publish := generated_body(compact, 'voidunix__UnixSocket__publish_peer_login(unix__UnixSocket*this,u32uid,u32session){')!
	barrier := 'katomic__sync();'
	opening := required_offset(publish, '{')! + 1
	without_barrier := publish.replace(barrier, '')
	// Move the barrier inside the real function body: both wrong orderings
	// retain a barrier, so absence alone cannot satisfy these controls.
	for reordered in [without_barrier[..opening] + barrier + without_barrier[opening..],
		without_barrier[..without_barrier.len - 1] + barrier + '}'] {
		changed := compact.replace(publish, reordered)
		if changed == compact { return error('peer publication-order control did not mutate') }
		mut refused := false
		check_generated_peer(changed) or { refused = true }
		if !refused { return error('peer publication-order control accepted') }
		checks++
	}
	if checks != 29 { return error('incomplete peer generated-C controls') }
}

fn generated_controls(path string, out string) ! {
	if !path.starts_with('/') || os.real_path(path) != path || os.lstat(path)!.mode & 0o170000 != 0o100000
		|| os.file_size(path) > 32 * 1024 * 1024 { return error('canonical regular generated C within32MiB required') }
	if !out.starts_with('/') || os.exists(out) || os.is_link(out) { return error('fresh absolute replay output required') }
	before := digest(path)!
	source := os.read_file(path)!
	check_generated_controls(source)!
	check_generated_peer_controls(source)!
	if digest(path)! != before { return error('generated C changed during replay') }
	os.mkdir(out)!
	os.write_file(out + '/generated-controls.json', json2.encode({'generated_c': path,
		'generated_c_sha256': before, 'frame_mutation_refusals': '18', 'peer_mutation_refusals': '29',
		'scope': 'Compiler-bound retained generated-C replay only; no new kernel build qualification'}) + '\n')!
	println('MATCHED GENERATED-C REPLAY PASS ' + digest(out + '/generated-controls.json')!)
}

fn require_text_symbol(symbols string, name string) ! {
	mut matches := 0
	for line in symbols.split_into_lines() {
		fields := line.fields()
		if fields.len == 3 && fields[2] == name && fields[1] in ['T', 't'] { matches++ }
	}
	if matches != 1 { return error('exact defined text symbol absent/duplicated: ' + name) }
}

fn qualify_arch(root string, step string, parent string, arch string, before map[string]string, frame_baseline bool) !map[string]string {
	os.write_file(step + '/budget-before.log', budget(root, parent, true)!)!
	argv := ['/usr/bin/make', '-C', root + '/kernel', '-j2', 'ARCH=' + arch, 'ALLOC_TRACK=1',
		'PROD=true', 'LIMINE_MP=' + if arch == 'aarch64' { '1' } else { '0' }, 'LINUXKPI=0',
		'PCI_CONFIG_TEST=0', 'PCI_TOPOLOGY_TEST=0', 'ACPI_SYNC_TEST=0', 'STACK_GUARD_TEST=0',
		'KERNEL_LINK_RANDOMIZE=0', 'VFLAGS=-nocache', 'V=' + compiler, 'CC=' + clang, 'AR=' + archiver,
		'LD_X86_64=' + linker, 'LD_AARCH64=' + linker]
	invoke(argv, root, step, parent)!
	after := snapshot(root, frame_baseline)!; os.write_file(step + '/inputs-after.json', json2.encode(after) + '\n')!
	if before != after { return error('source/tool/dependency input changed') }
	generated := os.read_file(root + '/kernel/obj/blob.c')!
	check_generated_controls(generated)!
	mut generated_checks := 'actual frame helper/callsite/borrowed pointers PASS; 18 mutated-C refusals PASS\n'
	if frame_baseline {
		generated_checks += 'frame-only baseline: peer sources equal reviewed source base; no peer ABI qualification claimed\n'
	} else {
		check_generated_peer_controls(generated)!
		generated_checks += 'actual peer ABI/coherent snapshots/atomic lifecycle/refusals PASS; 29 mutated-C refusals PASS\n'
	}
	os.write_file(step + '/generated-checks.log', generated_checks)!
	elf := root + '/kernel/bin/vinix'
	header := checked(['/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf', '-h', elf])!
	if !header.contains(if arch == 'aarch64' { 'AArch64' } else { 'Advanced Micro Devices X86-64' }) { return error('wrong ELF machine') }
	os.write_file(step + '/elf-header.log', header)!
	symbols := checked(['/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm', elf])!
	require_text_symbol(symbols, 'alloctrack__track_enter')!
	// The candidate cached getter may be inlined; require the actual linked
	// syscall in both profiles, with candidate-only peer C checks above.
	require_text_symbol(symbols, 'socket__syscall_getsockopt')!
	os.write_file(step + '/symbols.log', symbols)!
	preserve_outputs(root, step, arch)!
	mut artifacts := map[string]string{}; tree(step, [], mut artifacts)!
	os.write_file(step + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(step + '/budget-after.log', budget(root, parent, false)!)!
	return {arch + '_elf': digest(step + '/bin/vinix')!, arch + '_c': digest(step + '/obj/blob.c')!}
}

fn run() ! {
	frame_baseline := os.args.len == 3 && os.args[1] == '--frame-baseline'
	if !frame_baseline && os.args.len != 2 {
		return error('usage: guarded-build-check [--frame-baseline] NEW-ABSOLUTE-OUT')
	}
	controller_root := os.dir(os.dir(os.dir(@FILE)))
	root := if frame_baseline { frame_baseline_root } else { controller_root }
	out := os.args[if frame_baseline { 2 } else { 1 }]
	if !out.starts_with('/') || os.exists(out) || os.is_link(out) { return error('fresh absolute output required') }
	if checked(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'])!.trim_space()
		!= if frame_baseline { frame_baseline_revision } else { revision } {
		return error('wrong reviewed checkout')
	}
	parent := os.dir(out)
	if !os.is_dir(parent) || os.real_path(parent) != parent || parent == root || parent.starts_with(root + '/')
		|| root.starts_with(parent + '/') { return error('canonical dedicated parent outside worktree required') }
	admission := budget(root, parent, true)!
	os.mkdir(out)!; os.mkdir(out + '/tmp')!; os.mkdir(out + '/modules')!; os.mkdir(out + '/cache')!
	os.write_file(out + '/budget-admission.log', admission)!
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	for key in os.environ().keys() { if key !in ['HOME', 'USER', 'LOGNAME'] { os.unsetenv(key) } }
	for key, value in {'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VMODULES': out + '/modules',
		'V3CACHE': out + '/cache', 'XDG_CACHE_HOME': out + '/cache',
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
	before := snapshot(root, frame_baseline)!
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	os.write_file(out + '/source-revision.txt', revision + '\n')!
	os.write_file(out + '/source-status.txt', checked(['/usr/bin/git', '-C', root, 'status', '--short'])!)!
	os.write_file(out + '/source.patch', checked(['/usr/bin/git', '-C', root, 'diff', '--',
		'kernel/alloctrack/track_d_alloc_track.v', 'kernel/file/locks.v', 'kernel/memory/slab.v',
		'kernel/socket/public/public.v', 'kernel/socket/socket.v', 'kernel/socket/unix/unix.v'])!)!
	for relative in ['kernel/alloctrack/frame_page.v', 'kernel/alloctrack/track_d_alloc_track.v',
		'kernel/file/locks.v', 'kernel/memory/slab.v', 'kernel/socket/public/public.v',
		'kernel/socket/socket.v', 'kernel/socket/unix/unix.v',
		'tests/kernel-allocs/frame-page-check.v', 'tests/kernel-allocs/frame-page-host-check.v',
		'tests/socket-peer-login/guarded-build-check.v', 'tests/socket-peer-login/abi.h',
		'tests/socket-peer-login/dylibclosure/core.v', 'tests/socket-peer-login/dylibclosure/core_test.v'] {
		source_root := if frame_baseline && relative.starts_with('tests/socket-peer-login/') { controller_root } else { root }
		os.mkdir_all(out + '/source/' + os.dir(relative))!; os.cp(source_root + '/' + relative, out + '/source/' + relative)!
	}
	mut results := map[string]string{}
	if frame_baseline {
		results['profile'] = 'frame-baseline'
		results['architectures'] = 'x86_64'
		results['source-base'] = revision
		results['checkout-revision'] = frame_baseline_revision
	}
	architectures := if frame_baseline { ['x86_64'] } else { ['x86_64', 'aarch64'] }
	for arch in architectures {
		step := out + '/' + arch; os.mkdir(step)!
		qualified := qualify_arch(root, step, parent, arch, before, frame_baseline) or {
			failure := err.msg()
			os.write_file(step + '/failure.txt', failure + '\n')!
			if current := snapshot(root, frame_baseline) {
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
		println(if frame_baseline { 'FRAME BASELINE GUARDED KERNEL BUILD PASS ' + arch } else { 'MATCHED PEER GUARDED KERNEL BUILD PASS ' + arch })
	}
	os.write_file(out + '/qualification.json', json2.encode(results) + '\n')!
	println((if frame_baseline { 'FRAME BASELINE GUARDED X86_64 KERNEL PASS ' } else { 'MATCHED PEER GUARDED BOTH KERNELS PASS ' }) + digest(out + '/qualification.json')!)
}

fn host_controls(out string) ! {
	if !out.starts_with('/') || os.exists(out) || os.is_link(out) { return error('fresh absolute host-control output required') }
	os.mkdir(out)!
	mut evidence := map[string]string{}
	require_text_symbol('0000000000000010 T target\n', 'target')!
	for refused in ['0000000000000010 T target_suffix\n', '                 U target\n',
		'0000000000000010 D target\n', '0000000000000010 T target\n0000000000000020 t target\n'] {
		mut rejected := false
		require_text_symbol(refused, 'target') or { rejected = true }
		if !rejected { return error('invalid linked symbol accepted') }
	}
	evidence['defined-text-symbol'] = 'PASS exact definition; suffix/undefined/data/duplicate refusals'
	if checked(['/bin/echo', 'bounded-probe'])! != 'bounded-probe\n' { return error('positive probe mismatch') }
	evidence['positive'] = 'PASS'
	for label in ['nonzero', 'timeout', 'output-limit', 'interrupted', 'inventory-deadline', 'descendant'] {
		start := time.sys_mono_now()
		mut argv := ['/bin/sleep', '5']
		mut timeout := i64(100_000_000)
		limit := 8192
		mut expected := 'probe deadline'
		if label == 'nonzero' { argv = ['/usr/bin/false']; expected = 'command refused' }
		if label == 'output-limit' { argv = ['/usr/bin/yes']; timeout = 2_000_000_000; expected = 'probe output limit' }
		if label == 'interrupted' { interrupted = 1; expected = 'probe interrupted' }
		if label == 'inventory-deadline' {
			inventory_active = true; inventory_deadline = start + 50_000_000; timeout = 2_000_000_000
		}
		if label == 'descendant' { argv = [os.executable(), '--fixture-child', out + '/descendant.pid']; timeout = 250_000_000 }
		mut refusal := ''
		checked_bounded(argv, timeout, limit) or { refusal = err.msg(); '' }
		interrupted = 0; inventory_active = false
		if !refusal.contains(expected) { return error(label + ' did not refuse as expected: ' + refusal) }
		elapsed := time.sys_mono_now() - start
		if elapsed > 6_000_000_000 { return error(label + ' exceeded bounded cleanup') }
		if label == 'descendant' {
			pid := os.read_file(out + '/descendant.pid')!.trim_space().int()
			if pid <= 1 || C.kill(pid, 0) == 0 || C.errno != C.ESRCH { return error('descendant still present') }
		}
		evidence[label] = refusal + '; elapsed_ms=' + (elapsed / 1_000_000).str()
	}
	mut status := i32(0)
	if C.waitpid(-1, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('unreaped host-control child') }
	evidence['sole-reap'] = 'PASS raw i32 waitpid ECHILD; every private group absent'
	os.write_file(out + '/host-controls.json', json2.encode(evidence) + '\n')!
	println('MATCHED BUILD PROBE HOST CONTROLS PASS ' + digest(out + '/host-controls.json')!)
}

fn dispatch() ! {
	$if !prod { return error('compile this qualification driver with -prod for embedded source binding') }
	if os.read_file(@FILE)! != $embed_file('guarded-build-check.v').to_string()
		|| os.read_file(os.dir(@FILE) + '/abi.h')! != $embed_file('abi.h').to_string()
		|| os.read_file(os.dir(@FILE) + '/dylibclosure/core.v')! != $embed_file('dylibclosure/core.v').to_string() {
		return error('qualification source differs from compiled driver')
	}
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
	if os.args.len == 3 && os.args[1] == '--fixture-child' {
		mut child := os.new_process('/bin/sleep'); child.set_args(['20']); child.run()
		os.write_file(os.args[2], child.pid.str() + '\n')!
		child.wait(); child.close(); return
	}
	if os.args.len == 3 && os.args[1] == '--host-controls' { return host_controls(os.args[2]) }
	if os.args.len == 4 && os.args[1] == '--generated-controls' { return generated_controls(os.args[2], os.args[3]) }
	if os.args.len == 3 && os.args[1] == '--closure-controls' {
		out := os.args[2]
		if !out.starts_with('/') || os.exists(out) || os.is_link(out) { return error('fresh absolute closure output required') }
		os.mkdir(out)!
		loaded := dylibclosure.closure([compiler, bootstrap_compiler, os.executable(), clang,
			archiver, linker, '/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
			'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm'], checked)!
		mut evidence := loaded.metadata.clone()
		for path in loaded.paths { evidence['sha256:' + path] = digest(path)! }
		os.write_file(out + '/closure.json', json2.encode(evidence) + '\n')!
		println('MATCHED DYLIB CLOSURE PASS ' + digest(out + '/closure.json')!); return
	}
	run()!
}

fn main() { dispatch() or { eprintln(err); exit(1) } }
