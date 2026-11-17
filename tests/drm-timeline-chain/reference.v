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

fn function(source string, start string) string {
	begin := source.index(start) or { panic(start) }
	end := source.index_after('\n}\n', begin) or { panic(start) }
	return source[begin..end + 3]
}

fn main() {
	assert os.args.len == 4, 'usage: reference PINNED_LINUX NATIVE_CHECK_BINARY FRESH_EXTERNAL_STATE'
	root := os.abs_path(os.args[1]); state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(os.getwd() + '/')
	assert run('git', ['-C', root, 'rev-parse', 'HEAD'])!.trim_space() == 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	os.mkdir_all(state)!
	path := 'drivers/dma-buf/dma-fence-chain.c'
	source := os.read_file(root + '/' + path)!
	assert source == run('git', ['-C', root, 'show', 'HEAD:' + path])!
	assert sha256.sum(source.bytes()).hex() == 'cea55b4d2210efabd30765be890b1b67ccb24e554ca2a7e2ec158c784c7b511e'
	os.write_file(state + '/dma-fence-chain.c', source)!
	header := run('git', ['-C', root, 'show', 'HEAD:include/linux/dma-fence.h'])!
	assert header.contains('return f1 > f2;')
	os.write_file(state + '/dma-fence.h', header)!
	// Compile the three unchanged upstream bodies. Refcount/RCU/lockdep are
	// single-thread host stubs; actual link skipping remains the upstream C.
	mut c := '#include <assert.h>\n#include <errno.h>\n#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdio.h>\n' +
		'struct dma_fence { uint64_t context, seqno; bool chain, signaled; int inline_lock; };\n' +
		'struct dma_fence_chain { struct dma_fence base; struct dma_fence *prev, *fence; uint64_t prev_seqno; };\n' +
		'static struct dma_fence_chain *to_dma_fence_chain(struct dma_fence *f) { return f && f->chain ? (struct dma_fence_chain *)f : NULL; }\n' +
		'static void dma_fence_put(struct dma_fence *f) { (void)f; }\n' +
		'static struct dma_fence *dma_fence_chain_get_prev(struct dma_fence_chain *f) { return f->prev; }\n' +
		'static bool dma_fence_is_signaled(struct dma_fence *f) { return f->signaled; }\n' +
		'#define unrcu_pointer(x) (x)\n#define RCU_INITIALIZER(x) (x)\n#define cmpxchg(ptr,old,value) ((*(ptr)==(old)) ? (*(ptr)=(value),(old)) : *(ptr))\n' +
		'#define rcu_assign_pointer(ptr,value) ((ptr)=(value))\n#define max(a,b) ((a)>(b)?(a):(b))\n' +
		'struct lock_class_key { int x; };\n#define lockdep_set_class(lock,key) ((void)(lock),(void)(key))\n' +
		'#define WARN_ON(x) assert(!(x))\n#define dma_fence_is_chain(f) ((f)->chain)\n' +
		'static bool __dma_fence_is_later(struct dma_fence *f, uint64_t a, uint64_t b) { (void)f; return a>b; }\n' +
		'static uint64_t dma_fence_context_alloc(int n) { static uint64_t next=1; uint64_t ret=next; next+=n; return ret; }\n' +
		'static int dma_fence_chain_ops;\nstatic void dma_fence_init64(struct dma_fence *f, int *ops, void *lock, uint64_t context, uint64_t seqno) { (void)ops; (void)lock; f->context=context; f->seqno=seqno; f->chain=true; }\n'
	c += function(source, 'struct dma_fence *dma_fence_chain_walk(')
	c += '#define dma_fence_chain_for_each(iter,head) for ((iter)=(head); (iter); (iter)=dma_fence_chain_walk(iter))\n'
	c += function(source, 'int dma_fence_chain_find_seqno(')
	c += function(source, 'void dma_fence_chain_init(')
	c += 'static bool ready(struct dma_fence *f) { while(f) { if(!f->chain) return f->signaled; struct dma_fence_chain *c=(void *)f; if(!c->fence->signaled) return false; f=c->prev; } return true; }\n'
	c += 'int main(void) { const uint64_t values[]={0,1,2,3,UINT64_C(1)<<63,UINT64_MAX}; const uint64_t queries[]={0,1,2,3,4,(UINT64_C(1)<<63)-1,UINT64_C(1)<<63,UINT64_MAX};\n'
	c += 'for(int a=0;a<6;a++) for(int b=0;b<6;b++) for(int c=0;c<6;c++) for(int pred=0;pred<3;pred++) for(int mask=0;mask<8;mask++) {\n'
	c += 'struct dma_fence binary={.context=UINT64_MAX,.signaled=pred==2}, leaves[3]={0}; struct dma_fence_chain nodes[3]={0}; uint64_t points[]={values[a],values[b],values[c]};\n'
	c += 'for(int i=0;i<3;i++) dma_fence_chain_init(&nodes[i],i?&nodes[i-1].base:(pred?&binary:NULL),&leaves[i],points[i]);\n'
	c += 'for(int i=0;i<3;i++) leaves[i].signaled=!!(mask&(1<<i));\n'
	c += 'for(int q=0;q<8;q++) { struct dma_fence *f=&nodes[2].base; int id=-2; bool done=false; if(!dma_fence_chain_find_seqno(&f,queries[q])) { id=-1; if(f==&binary) id=3; for(int i=0;i<3;i++) if(f==&nodes[i].base) id=i; done=ready(f); } printf("%d %d\\n",id,done); }\n}\nreturn 0;\n}\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
		state + '/oracle.c', '-o', state + '/oracle'])!
	oracle := run(state + '/oracle', [])!
	native := run(os.abs_path(os.args[2]), ['--trace'])!
	os.write_file(state + '/oracle.log', oracle)!
	os.write_file(state + '/native.log', native)!
	assert oracle == native
	assert oracle.count('\n') == 41472
	println('41472 production lookups/readiness results match unchanged pinned upstream init/walk/find C bodies across all triples of six boundary values, all completion masks, nil/pending/completed binary predecessors and eight queries. Refcount/RCU/lockdep are host stubs; Linux concurrency/reclamation is not qualified.')
}
