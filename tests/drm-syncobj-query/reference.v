// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string) !string {
	mut p := os.new_process(program)
	p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	assert p.code == 0, program + ': ' + out
	p.close()
	return out
}

fn function(source string, name string) string {
	start := source.index(name) or { panic(name) }
	end := source.index_after('\n}\n', start) or { panic(name) }
	return source[start..end + 3]
}

fn main() {
	assert os.args.len == 4, 'usage: reference PINNED_LINUX NATIVE_DRM_BINARY FRESH_EXTERNAL_STATE'
	root := os.abs_path(os.args[1]); state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(os.getwd() + '/')
	assert run('git', ['-C', root, 'rev-parse', 'HEAD'])!.trim_space() == 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	os.mkdir_all(state)!
	for path in ['drivers/dma-buf/dma-fence-chain.c', 'drivers/gpu/drm/drm_syncobj.c', 'drivers/gpu/drm/asahi/driver.rs', 'include/uapi/drm/drm.h'] {
		text := os.read_file(root + '/' + path)!
		assert text == run('git', ['-C', root, 'show', 'HEAD:' + path])!
		os.write_file(state + '/' + os.file_name(path), text)!
		println(path + ' sha256 ' + sha256.sum(text.bytes()).hex())
	}
	assert os.read_file(state + '/driver.rs')!.contains('const FEAT_SYNCOBJ_TIMELINE: bool = true;')
	header := os.read_file(state + '/drm.h')!
	assert header.contains('#define DRM_SYNCOBJ_QUERY_FLAGS_LAST_SUBMITTED (1 << 0)')
	assert header.contains('DRM_IOWR(0xCB, struct drm_syncobj_timeline_array)')
	// Reuse the prior complete oracle's plumbing only after its original full
	// bundle passes its unchanged checker. Function bodies are compared again
	// with the pinned Linux tree, rather than accepting a hand-written model.
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-timeline-chain-20261117'
	log := run(prior + '/bundle/archive-check', ['check-archive-root', prior + '/bundle.tar.gz',
		'0c9d92e39b3cf9bf48a2bfffc86cb3f51e6f840d64aba3ed3113bb20f822b3bc', prior + '/bundle'])!
	os.write_file(state + '/prior-check.log', log)!
	old := os.read_file(prior + '/bundle/qualified/reference/oracle.c')!
	os.write_file(state + '/prior-oracle.c', old)!
	chain := os.read_file(state + '/dma-fence-chain.c')!
	mut c := old.all_before('static bool ready(')
	for name in ['struct dma_fence *dma_fence_chain_walk(', 'int dma_fence_chain_find_seqno(', 'void dma_fence_chain_init('] {
		assert function(c, name) == function(chain, name)
	}
	stub := 'static bool dma_fence_is_signaled(struct dma_fence *f) { return f->signaled; }'
	assert c.count(stub) == 1
	c = c.replace(stub, 'static bool dma_fence_chain_signaled(struct dma_fence *fence);\n' +
		'static bool dma_fence_is_signaled(struct dma_fence *f) { return f->chain ? dma_fence_chain_signaled(f) : f->signaled; }')
	c += '#include <string.h>\n#include <inttypes.h>\n' +
		'static struct dma_fence *dma_fence_get(struct dma_fence *f) { return f; }\n' +
		'static struct dma_fence *dma_fence_chain_contained(struct dma_fence *f) { return f->chain ? ((struct dma_fence_chain *)f)->fence : f; }\n'
	c += function(chain, 'static bool dma_fence_chain_signaled(')
	c += '#define DRIVER_SYNCOBJ_TIMELINE 1\n#define DRM_SYNCOBJ_QUERY_FLAGS_LAST_SUBMITTED 1\n#define __user\n' +
		'#define u64_to_user_ptr(value) ((void *)(uintptr_t)(value))\n' +
		'struct drm_device { int unused; }; struct drm_file { int unused; };\n' +
		'struct drm_syncobj { struct dma_fence *fence; };\n' +
		'struct drm_syncobj_timeline_array { uint64_t handles, points; uint32_t count_handles, flags; };\n' +
		'static struct drm_syncobj *objects[1];\n' +
		'static bool drm_core_check_feature(struct drm_device *d,int flag) { (void)d; (void)flag; return true; }\n' +
		'static int drm_syncobj_array_find(struct drm_file *f,void *h,uint32_t n,struct drm_syncobj ***out) { (void)f; (void)h; assert(n==1); *out=objects; return 0; }\n' +
		'static void drm_syncobj_array_free(struct drm_syncobj **o,uint32_t n) { (void)o; (void)n; }\n' +
		'static struct dma_fence *drm_syncobj_fence_get(struct drm_syncobj *o) { return o->fence; }\n' +
		'static int copy_to_user(void *out,const void *in,size_t n) { memcpy(out,in,n); return 0; }\n'
	c += function(os.read_file(state + '/drm_syncobj.c')!, 'int drm_syncobj_query_ioctl(')
	c += 'int main(void) { const uint64_t v[]={0,1,2,3,UINT64_C(1)<<63,UINT64_MAX};\n'
	c += 'for(int a=0;a<6;a++) for(int b=0;b<6;b++) for(int c=0;c<6;c++) for(int pred=0;pred<3;pred++) for(int mask=0;mask<8;mask++) {\n'
	c += 'struct dma_fence binary={.context=UINT64_MAX,.signaled=pred==2}, leaves[3]={0}; struct dma_fence_chain nodes[3]={0}; uint64_t points[]={v[a],v[b],v[c]};\n'
	c += 'for(int i=0;i<3;i++) dma_fence_chain_init(&nodes[i],i?&nodes[i-1].base:(pred?&binary:NULL),&leaves[i],points[i]);\n'
	c += 'for(int i=0;i<3;i++) leaves[i].signaled=!!(mask&(1<<i)); struct drm_syncobj obj={.fence=&nodes[2].base}; objects[0]=&obj;\n'
	c += 'for(int flags=0;flags<2;flags++) { uint64_t point=0; struct drm_syncobj_timeline_array args={.points=(uintptr_t)&point,.count_handles=1,.flags=flags}; assert(drm_syncobj_query_ioctl(NULL,&args,NULL)==0); printf("%" PRIu64 "\\n",point); }\n}\nreturn 0;\n}\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	expected := run(state + '/oracle', [])!
	actual := run(os.abs_path(os.args[2]), ['--query-trace'])!
	os.write_file(state + '/oracle.log', expected)!
	os.write_file(state + '/native.log', actual)!
	assert expected == actual && actual.count('\n') == 10368
	println('10368 production QUERY values match unchanged pinned drm_syncobj_query_ioctl and chain init/walk/signaled bodies; allocator/refcount/RCU/driver/usercopy plumbing are single-thread host stubs. Capability remains unadvertised pending other timeline operations.')
}
