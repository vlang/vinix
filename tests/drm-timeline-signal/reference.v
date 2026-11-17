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
	for path in ['drivers/dma-buf/dma-fence-chain.c', 'drivers/dma-buf/dma-fence.c',
		'drivers/gpu/drm/drm_syncobj.c', 'include/uapi/drm/drm.h'] {
		text := os.read_file(root + '/' + path)!
		assert text == run('git', ['-C', root, 'show', 'HEAD:' + path])!
		os.write_file(state + '/' + os.file_name(path), text)!
		println(path + ' sha256 ' + sha256.sum(text.bytes()).hex())
	}
	assert os.read_file(state + '/drm.h')!.contains('DRM_IOWR(0xCD, struct drm_syncobj_timeline_array)')
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-syncobj-query-20261117'
	log := run(prior + '/bundle/archive-check', ['check-archive-root', prior + '/bundle.tar.gz',
		'a5c8eb6c05be0408926704c2444a514736ab6f16ae521bae5b4b696817276c67', prior + '/bundle'])!
	os.write_file(state + '/prior-check.log', log)!
	old := os.read_file(prior + '/bundle/host-final/reference/oracle.c')!
	os.write_file(state + '/prior-oracle.c', old)!
	mut c := old.all_before('int main(void) {')
	chain := os.read_file(state + '/dma-fence-chain.c')!
	for name in ['struct dma_fence *dma_fence_chain_walk(', 'int dma_fence_chain_find_seqno(', 'void dma_fence_chain_init(',
		'static bool dma_fence_chain_signaled(struct dma_fence *fence)\n{'] {
		assert function(c, name) == function(chain, name)
	}
	c = c.replace('objects[1];', 'objects[3];').replace('assert(n==1);', 'assert(n==3);')
	c += '#include <stdlib.h>\n#define GFP_KERNEL 0\n' +
		'static struct dma_fence_chain *allocated[3]; static int allocated_count;\n' +
		'static void *kmalloc_array(size_t n,size_t s,int g) { (void)g; void *p=malloc(n*s); assert(p); return p; }\n' +
		'static void kfree(void *p) { free(p); }\n' +
		'static int copy_from_user(void *out,const void *in,size_t n) { memcpy(out,in,n); return 0; }\n' +
		'static struct dma_fence_chain *dma_fence_chain_alloc(void) { struct dma_fence_chain *p=calloc(1,sizeof(*p)); assert(p && allocated_count<3); allocated[allocated_count++]=p; return p; }\n' +
		'static void dma_fence_chain_free(struct dma_fence_chain *p) { free(p); }\n' +
		'static struct dma_fence shared_stub={.signaled=true};\n'
	c += function(os.read_file(state + '/dma-fence.c')!, 'struct dma_fence *dma_fence_get_stub(').replace('dma_fence_stub', 'shared_stub')
	c += 'static void drm_syncobj_add_point(struct drm_syncobj *o,struct dma_fence_chain *c,struct dma_fence *f,uint64_t point) { dma_fence_chain_init(c,o->fence,f,point); o->fence=&c->base; }\n'
	c += function(os.read_file(state + '/drm_syncobj.c')!, 'int\ndrm_syncobj_timeline_signal_ioctl(')
	c += 'int main(void) { const uint64_t v[]={0,1,2,3,UINT64_C(1)<<63,UINT64_MAX};\n'
	c += 'for(int a=0;a<6;a++) for(int b=0;b<6;b++) for(int c=0;c<6;c++) for(int pred=0;pred<3;pred++) for(int nulls=0;nulls<2;nulls++) for(int separate=0;separate<2;separate++) {\n'
	c += 'struct dma_fence binary={.context=UINT64_MAX,.signaled=pred==2}; struct drm_syncobj obj[3]={0}; for(int i=0;i<3;i++) { obj[i].fence=pred?&binary:NULL; objects[i]=&obj[separate?i:0]; }\n'
	c += 'uint64_t values[]={v[a],v[b],v[c]}; struct drm_syncobj_timeline_array args={.points=nulls?0:(uintptr_t)values,.count_handles=3}; allocated_count=0; assert(drm_syncobj_timeline_signal_ioctl(NULL,&args,NULL)==0);\n'
	c += 'for(int phase=0;phase<2;phase++) { if(phase) binary.signaled=true; for(int i=0;i<3;i++) { for(int j=0;j<3;j++) objects[j]=&obj[i]; uint64_t point[3]; args.points=(uintptr_t)point; args.flags=0; assert(drm_syncobj_query_ioctl(NULL,&args,NULL)==0); uint64_t done=point[0]; args.flags=1; assert(drm_syncobj_query_ioctl(NULL,&args,NULL)==0); printf("%d %" PRIu64 " %" PRIu64 "\\n",obj[i].fence?dma_fence_is_signaled(obj[i].fence):1,done,point[0]); } }\n'
	c += 'for(int i=0;i<allocated_count;i++) free(allocated[i]);\n}\nreturn 0;\n}\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	expected := run(state + '/oracle', [])!
	actual := run(os.abs_path(os.args[2]), ['--timeline-signal-trace'])!
	os.write_file(state + '/oracle.log', expected)!
	os.write_file(state + '/native.log', actual)!
	assert expected == actual && actual.count('\n') == 15552
	println('15552 production timeline SIGNAL/QUERY readiness/progress results match pinned SIGNAL and QUERY handlers plus unchanged chain init/walk/signaled bodies, across unsigned triples, null points, duplicate/distinct objects and binary predecessors. Allocation/refcount/RCU/usercopy and add-point publication plumbing are host stubs; timestamps and real concurrency are unqualified.')
}
