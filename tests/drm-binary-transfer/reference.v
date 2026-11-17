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
	for path in ['drivers/dma-buf/dma-fence-chain.c', 'drivers/gpu/drm/drm_syncobj.c', 'include/uapi/drm/drm.h'] {
		text := os.read_file(root + '/' + path)!
		assert text == run('git', ['-C', root, 'show', 'HEAD:' + path])!
		os.write_file(state + '/' + os.file_name(path), text)!
		println(path + ' sha256 ' + sha256.sum(text.bytes()).hex())
	}
	assert os.read_file(state + '/drm.h')!.contains('DRM_IOWR(0xCC, struct drm_syncobj_transfer)')
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-timeline-wait-20261117'
	os.write_file(state + '/prior-check.log', run(prior + '/bundle/archive-check', ['check-archive-root', prior + '/bundle.tar.gz',
		'765a9fa50928b062fed47afe1696e294984519957f18bfd9b64041168a6e3e1a', prior + '/bundle'])!)!
	old := os.read_file(prior + '/bundle/host-final/reference/oracle.c')!
	os.write_file(state + '/prior-oracle.c', old)!
	mut c := old.all_before('#undef ETIME\n')
	c = c.replace('struct drm_syncobj { struct dma_fence *fence; };', 'struct list_head { void *next; }; struct drm_syncobj { struct dma_fence *fence; int lock; struct list_head cb_list; };')
	chain := os.read_file(state + '/dma-fence-chain.c')!
	for name in ['struct dma_fence *dma_fence_chain_walk(', 'int dma_fence_chain_find_seqno(', 'void dma_fence_chain_init(',
		'static bool dma_fence_chain_signaled(struct dma_fence *fence)\n{'] { assert function(c, name) == function(chain, name) }
	c += '#undef ETIME\n#define ETIME 62\n#define ERESTARTSYS 512\n#define DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT 2\n#define DRM_SYNCOBJ_WAIT_FOR_SUBMIT_TIMEOUT UINT64_C(5000000000)\n#define current NULL\n#define TASK_INTERRUPTIBLE 1\n#define TASK_RUNNING 0\n'
	c += 'typedef uint32_t u32; typedef uint64_t u64;\nstruct drm_syncobj_transfer { uint32_t src_handle,dst_handle; uint64_t src_point,dst_point; uint32_t flags,pad; };\nstruct syncobj_wait_entry { void *task; uint64_t point; struct dma_fence *fence; struct list_head node; };\n'
	c += '#define spin_lock(p) ((void)(p))\n#define spin_unlock(p) ((void)(p))\n#define rcu_dereference_protected(p,x) (p)\n#define might_sleep() ((void)0)\n#define lockdep_assert_none_held_once() ((void)0)\nstatic void list_add_tail(struct list_head *n,struct list_head *h) { n->next=h; }\n'
	c += 'static struct drm_syncobj *names[2];\nstatic struct drm_syncobj *drm_syncobj_find(struct drm_file *f,uint32_t h) { (void)f; return h>=1&&h<=2?names[h-1]:NULL; }\nstatic void drm_syncobj_put(struct drm_syncobj *o) { (void)o; }\nstatic uint64_t nsecs_to_jiffies64(uint64_t t) { assert(t==UINT64_C(5000000000)); return 1; }\nstatic void set_current_state(int n) { (void)n; }\n#define __set_current_state set_current_state\nstatic bool signal_pending(void *t) { (void)t; return false; }\nstatic uint64_t schedule_timeout(uint64_t n) { assert(n==1); return 0; }\n'
	c += 'static void drm_syncobj_remove_wait(struct drm_syncobj *o,struct syncobj_wait_entry *e) { (void)o; e->node.next=NULL; }\nstatic void drm_syncobj_replace_fence(struct drm_syncobj *o,struct dma_fence *f) { o->fence=f; }\n'
	drm := os.read_file(state + '/drm_syncobj.c')!
	c += function(drm, 'static void drm_syncobj_fence_add_wait(')
	c += function(drm, 'int drm_syncobj_find_fence(')
	c += function(drm, 'static int\ndrm_syncobj_transfer_to_binary(')
	// The unchanged dispatch never selects the deliberately unsupported host
	// timeline-destination branch in this binary-only matrix.
	c += 'static int drm_syncobj_transfer_to_timeline(struct drm_file *f,struct drm_syncobj_transfer *a) { (void)f;(void)a; assert(false); return -95; }\n'
	c += function(drm, 'int\ndrm_syncobj_transfer_ioctl(')
	c += 'int main(void) { const uint64_t points[]={0,1,2,3,UINT64_C(1)<<63,UINT64_MAX}; for(int s=0;s<7;s++) { for(int p=0;p<6;p++) { for(unsigned flags=0;flags<16;flags++) { for(int missing=0;missing<4;missing++) { for(int pad=0;pad<2;pad++) { for(int same=0;same<2;same++) {\n'
	c += 'struct drm_syncobj source={0},dest={0}; struct dma_fence leaf={.context=7,.signaled=s==2||s==4},prefix={.context=7,.seqno=1,.signaled=true}; struct dma_fence_chain node={0},before={0}; if(s==1||s==2) source.fence=&leaf; else if(s) { if(s==5) { dma_fence_chain_init(&before,NULL,&prefix,1); source.fence=&before.base; } dma_fence_chain_init(&node,source.fence,&leaf,s==6?UINT64_MAX:3); source.fence=&node.base; } names[0]=&source; names[1]=&dest; struct drm_syncobj *out=same?&source:&dest; struct drm_syncobj_transfer args={.src_handle=(missing&1)?UINT32_MAX:1,.dst_handle=(missing&2)?UINT32_MAX:same?1:2,.src_point=points[p],.flags=flags,.pad=(unsigned)pad};\n'
	c += 'int code=drm_syncobj_transfer_ioctl(NULL,&args,NULL); struct dma_fence *f=out->fence; printf("%d %d %d %" PRIu64 "\\n",code,f!=NULL,f?(dma_fence_is_signaled(f)?1:0):0,f?f->seqno:0);\n} } } } } } return 0; }\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	expected := run(state + '/oracle', [])!
	actual := run(os.abs_path(os.args[2]), ['--binary-transfer-trace'])!
	os.write_file(state + '/oracle.log', expected)!; os.write_file(state + '/native.log', actual)!
	assert expected == actual && actual.count('\n') == 10752
	println('10752 binary-destination TRANSFER outcomes match unchanged pinned dispatch, binary-transfer, find-fence, add-wait and chain bodies: head states, unsigned points, self-copy, absent names, pad and every flag combination. Refcount/RCU/usercopy/publication and one-step timeout scheduler are host stubs. Future publication/interruption races are separate native-fixture checks; timeline destinations and real scheduler/hardware behavior remain unqualified.')
}
