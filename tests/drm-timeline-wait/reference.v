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
	assert os.read_file(state + '/drm.h')!.contains('DRM_IOWR(0xCA, struct drm_syncobj_timeline_wait)')
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-timeline-signal-20261117'
	os.write_file(state + '/prior-check.log', run(prior + '/bundle/archive-check', ['check-archive-root', prior + '/bundle.tar.gz',
		'96e7024b318cfeebe29ff6225e5977a1f876cbdbd8d790156569852544b992f9', prior + '/bundle'])!)!
	old := os.read_file(prior + '/bundle/host-first/reference/oracle.c')!
	os.write_file(state + '/prior-oracle.c', old)!
	mut c := old.all_before('int main(void) {')
	chain := os.read_file(state + '/dma-fence-chain.c')!
	for name in ['struct dma_fence *dma_fence_chain_walk(', 'int dma_fence_chain_find_seqno(', 'void dma_fence_chain_init(',
		'static bool dma_fence_chain_signaled(struct dma_fence *fence)\n{'] {
		assert function(c, name) == function(chain, name)
	}
	// Compile unchanged upstream wait bodies. Only host infrastructure is stubbed;
	// schedule_timeout must never run in the zero-timeout comparison matrix.
	c += '#undef ETIME\n#define ETIME 62\n#define DRM_SYNCOBJ_WAIT_FLAGS_WAIT_ALL 1\n#define DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT 2\n#define DRM_SYNCOBJ_WAIT_FLAGS_WAIT_AVAILABLE 4\n#define DRM_SYNCOBJ_WAIT_FLAGS_WAIT_DEADLINE 8\n#define ERESTARTSYS 512\n#define TASK_INTERRUPTIBLE 1\n#define TASK_RUNNING 0\n'
	c += 'typedef int64_t ktime_t;\nstruct drm_syncobj_wait { uint64_t handles; int64_t timeout_nsec; uint32_t count_handles,flags,first_signaled,pad; };\nstruct drm_syncobj_timeline_wait { uint64_t handles,points; int64_t timeout_nsec; uint32_t count_handles,flags,first_signaled,pad; uint64_t deadline_nsec; };\n'
	c += 'struct dma_fence_cb { void (*func)(struct dma_fence *,struct dma_fence_cb *); };\nstruct syncobj_wait_entry { void *task; uint64_t point; struct dma_fence *fence; struct dma_fence_cb fence_cb; };\n'
	c += '#define current NULL\n#define might_sleep() ((void)0)\n#define lockdep_assert_none_held_once() ((void)0)\n#define kzalloc_objs(value,n) calloc((n),sizeof(value))\n'
	c += 'static void drm_syncobj_fence_add_wait(struct drm_syncobj *o,struct syncobj_wait_entry *e) { if(e->fence) return; struct dma_fence *f=o->fence; if(!f || dma_fence_chain_find_seqno(&f,e->point)) return; e->fence=f?f:dma_fence_get_stub(); }\n'
	c += 'static void drm_syncobj_remove_wait(struct drm_syncobj *o,struct syncobj_wait_entry *e) { (void)o; (void)e; }\n'
	c += 'static void dma_fence_set_deadline(struct dma_fence *f,ktime_t t) { (void)f;(void)t; }\nstatic unsigned int drm_syncobj_wait_hint(struct drm_file *f) { (void)f; return 0; }\nstatic unsigned int sched_util_min_scope_enter(unsigned int n) { (void)n; return 0; }\nstatic void sched_util_min_scope_exit(unsigned int n) { (void)n; }\n'
	c += 'static void set_current_state(int n) { (void)n; }\n#define __set_current_state set_current_state\nstatic bool signal_pending(void *t) { (void)t; return false; }\nstatic long schedule_timeout(long n) { (void)n; assert(false); return 0; }\n'
	c += 'static void syncobj_wait_fence_func(struct dma_fence *f,struct dma_fence_cb *cb) { (void)f;(void)cb; }\nstatic int dma_fence_add_callback(struct dma_fence *f,struct dma_fence_cb *cb,void (*fn)(struct dma_fence *,struct dma_fence_cb *)) { if(dma_fence_is_signaled(f)) return -1; cb->func=fn; return 0; }\nstatic void dma_fence_remove_callback(struct dma_fence *f,struct dma_fence_cb *cb) { (void)f; cb->func=NULL; }\n'
	c += 'static long drm_timeout_abs_to_jiffies(int64_t n) { assert(n==0); return 0; }\nstatic ktime_t ns_to_ktime(uint64_t n) { return (ktime_t)n; }\n'
	drm := os.read_file(state + '/drm_syncobj.c')!
	c += function(drm, 'static signed long drm_syncobj_array_wait_timeout(')
	c += function(drm, 'static int drm_syncobj_array_wait(')
	c += function(drm, 'int\ndrm_syncobj_timeline_wait_ioctl(')
	c += 'int main(void) { for(int a=0;a<7;a++) { for(int b=0;b<7;b++) { for(int c=0;c<7;c++) { for(int pattern=0;pattern<4;pattern++) {\n'
	c += 'struct drm_syncobj obj[3]={0}; struct dma_fence leaves[6]={0}; struct dma_fence_chain nodes[6]={0}; int states[]={a,b,c}; uint64_t points[3];\n'
	c += 'for(int i=0;i<3;i++) { objects[i]=&obj[i]; int s=states[i]; struct dma_fence *leaf=&leaves[2*i]; leaf->signaled=s==2||s==4; if(s==1||s==2) obj[i].fence=leaf; else if(s) { if(s==5) { leaves[2*i+1].signaled=true; dma_fence_chain_init(&nodes[2*i+1],NULL,&leaves[2*i+1],1); obj[i].fence=&nodes[2*i+1].base; } dma_fence_chain_init(&nodes[2*i],obj[i].fence,leaf,s==6?UINT64_MAX:3); obj[i].fence=&nodes[2*i].base; } points[i]=pattern==0?0:pattern==1?(uint64_t)(i+1):pattern==2?(i==1?UINT64_MAX:1):UINT64_MAX; }\n'
	c += 'for(uint32_t flags=0;flags<16;flags++) { struct drm_syncobj_timeline_wait args={.points=(uintptr_t)points,.count_handles=3,.flags=flags,.first_signaled=123,.pad=UINT32_MAX,.deadline_nsec=UINT64_MAX}; int ret=drm_syncobj_timeline_wait_ioctl(NULL,&args,NULL); printf("%d %u\\n",ret,args.first_signaled); }\n} } } } return 0; }\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	expected := run(state + '/oracle', [])!
	actual := run(os.abs_path(os.args[2]), ['--timeline-wait-trace'])!
	os.write_file(state + '/oracle.log', expected)!
	os.write_file(state + '/native.log', actual)!
	assert expected == actual && actual.count('\n') == 21952
	println('21952 production timeline WAIT outcomes match unchanged pinned wait/array/ioctl and chain init/walk/find/signaled bodies: empty/binary/chain/retired-prefix/MAX heads, point triples, ANY/ALL, SUBMIT/AVAILABLE/DEADLINE flags. Zero-timeout only; publication/callback/refcount/RCU/usercopy/scheduler infrastructure are host stubs. Native scripted races are separate evidence; scheduling and hardware are unqualified.')
}
