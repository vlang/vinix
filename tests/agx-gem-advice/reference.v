// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); assert p.code == 0, out; p.close(); return out
}
fn section(source string, start string, end string) string {
	begin := source.index(start) or { panic(start) }
	finish := source.index_after(end, begin + start.len) or { panic(end) }
	return source[begin..finish]
}
fn main() {
	assert os.args.len == 4, 'usage: reference PINNED_LINUX NATIVE_TRACE_BINARY FRESH_STATE'
	linux := os.abs_path(os.args[1]); state := os.abs_path(os.args[3])
	assert !os.exists(state); os.mkdir_all(state)!
	pin := 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	assert run('git', ['-C', linux, 'rev-parse', 'HEAD'])!.trim_space() == pin
	mut sources := map[string]string{}
	mut lines := ['Linux-Aurora ' + pin]
	for path in ['drivers/gpu/drm/asahi/file.rs', 'drivers/gpu/drm/asahi/gem.rs',
		'drivers/gpu/drm/drm_gem_shmem_helper.c', 'include/uapi/drm/asahi_drm.h'] {
		source := run('git', ['-C', linux, 'show', pin + ':' + path])!
		sources[os.file_name(path)] = source
		os.write_file(state + '/' + os.file_name(path), source)!
		lines << path + ' sha256 ' + sha256.sum(source.bytes()).hex()
	}
	os.write_file(state + '/pins.txt', lines.join('\n') + '\n')!
	helper := section(sources['drm_gem_shmem_helper.c'], 'int drm_gem_shmem_madvise_locked(', 'EXPORT_SYMBOL_GPL(drm_gem_shmem_madvise_locked);')
	wire := section(sources['asahi_drm.h'], 'struct drm_asahi_gem_madvise {', '\n};') + '\n};\n'
	code := '#include <stdint.h>\n#include <stddef.h>\n#include <stdio.h>\ntypedef uint32_t __u32;\n' + wire +
		'struct drm_gem_shmem_object { struct { void *resv; } base; int madv; };\n#define dma_resv_assert_held(x) ((void)(x))\n' + helper +
		'int main(void) { printf("wire %u %llu %llu %llu %llu\\n", (unsigned)sizeof(struct drm_asahi_gem_madvise), (unsigned long long)offsetof(struct drm_asahi_gem_madvise,handle), (unsigned long long)offsetof(struct drm_asahi_gem_madvise,madv), (unsigned long long)offsetof(struct drm_asahi_gem_madvise,retained), (unsigned long long)offsetof(struct drm_asahi_gem_madvise,pad));\n' +
		'for(unsigned initial=0; initial<2; ++initial) for(unsigned pattern=0; pattern<1024; ++pattern) { struct drm_gem_shmem_object object={.madv=(int)initial}; for(unsigned step=0; step<10; ++step) { int retained=drm_gem_shmem_madvise_locked(&object, (pattern >> step)&1); printf("%u %u %u %u %u\\n", initial,pattern,step,(unsigned)retained,(unsigned)object.madv); } } return 0; }\n'
	os.write_file(state + '/oracle.c', code)!
	_ = run('cc', ['-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	oracle := run(state + '/oracle', [])!
	native := run(os.abs_path(os.args[2]), [])!
	os.write_file(state + '/oracle.log', oracle)!
	os.write_file(state + '/native.log', native)!
	assert native == oracle && native.split_into_lines().len == 20481
	println('Pinned unchanged shmem advice helper and UAPI record match 2048 resident sequences / 20480 transitions and all wire offsets; reservation locking modeled, purged state excluded.')
}
