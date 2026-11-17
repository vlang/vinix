// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); assert p.code == 0, program + ': ' + out; p.close(); return out
}
fn function(source string, name string) string {
	a := source.index(name) or { panic(name) }; b := source.index_after('\n}\n', a) or { panic(name) }; return source[a..b + 3]
}
fn main() {
	assert os.args.len == 4
	root := os.abs_path(os.args[1]); state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(os.getwd() + '/')
	assert run('git', ['-C', root, 'rev-parse', 'HEAD'])!.trim_space() == 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	os.mkdir_all(state)!
	for path in ['drivers/dma-buf/dma-fence-chain.c', 'drivers/dma-buf/dma-fence-array.c', 'drivers/dma-buf/dma-fence-unwrap.c', 'drivers/gpu/drm/drm_syncobj.c'] {
		s := os.read_file(root + '/' + path)!; assert s == run('git', ['-C', root, 'show', 'HEAD:' + path])!
		os.write_file(state + '/' + os.file_name(path), s)!; println(path + ' sha256 ' + sha256.sum(s.bytes()).hex())
	}
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-binary-transfer-20261117'
	os.write_file(state + '/prior-check.log', run(prior + '/bundle/archive-check', ['check-archive-root', prior + '/bundle.tar.gz', '7090e1958e191249bdc32ed4117b83e049cacf0ea7aa134f18f4a53d77ef7862', prior + '/bundle'])!)!
	old := os.read_file(prior + '/bundle/host-stack/reference/oracle.c')!
	os.write_file(state + '/prior-oracle.c', old)!
	mut c := old.all_before('static int drm_syncobj_transfer_to_timeline(')
	c = c.replace('shared_stub={.signaled=true}', 'shared_stub={.signaled=true,.stub=true}')
	c = c.replace('return f->chain ? ((struct dma_fence_chain *)f)->fence : f;', 'return f && f->chain ? ((struct dma_fence_chain *)f)->fence : f;')
	c = c.replace('bool chain, signaled; int inline_lock;', 'bool chain, signaled, array, stub; int error, inline_lock; uint64_t timestamp; unsigned long flags;')
	c = c.replace('static bool dma_fence_is_signaled(struct dma_fence *f)', 'static bool host_array_signaled(struct dma_fence *f);\nstatic bool dma_fence_is_signaled(struct dma_fence *f)')
	c = c.replace('return f->chain ? dma_fence_chain_signaled(f) : f->signaled;', 'return f->chain ? dma_fence_chain_signaled(f) : f->array ? host_array_signaled(f) : f->signaled;')
	c += 'typedef uint64_t ktime_t;\nstruct irq_work { int unused; }; struct dma_fence_array_cb { int unused; };\nstruct dma_fence_array { struct dma_fence base; unsigned num_fences; int num_pending; struct dma_fence **fences; struct irq_work work; struct dma_fence_array_cb callbacks[]; };\nstruct dma_fence_unwrap { struct dma_fence *chain,*array; unsigned index; };\n'
	c += '#define PENDING_ERROR 1\n#define DMA_FENCE_FLAG_ENABLE_SIGNAL_BIT 0\n#define atomic_read_acquire(p) (*(p))\n#define atomic_set(p,v) (*(p)=(v))\n#define test_bit(n,p) ((*(p)&(1ul<<(n)))!=0)\n#define init_irq_work(p,fn) ((void)(p))\n#define kzalloc_flex(value,member,n) calloc(1,sizeof(value)+(n)*sizeof((value).member[0]))\n#define kmalloc_objs(value,n) malloc((n)*sizeof(value))\n#define sort(p,n,s,cmp,priv) qsort(p,n,s,cmp)\n#define dma_fence_is_container(f) ((f)->chain||(f)->array)\n'
	c += 'static int dma_fence_array_ops; static struct dma_fence *fresh[4]; static int nfresh;\nstatic struct dma_fence_array *to_dma_fence_array(struct dma_fence *f) { return f&&f->array?(struct dma_fence_array *)f:NULL; }\nstatic void dma_fence_init(struct dma_fence *f,int *ops,void *lock,uint64_t ctx,unsigned seq) { (void)ops;(void)lock; f->array=true;f->context=ctx;f->seqno=seq; }\nstatic uint64_t ns_to_ktime(uint64_t n) { return n; }\nstatic bool ktime_after(ktime_t a,ktime_t b) { return a>b; }\nstatic ktime_t dma_fence_timestamp(struct dma_fence *f) { return f->timestamp; }\nstatic bool dma_fence_is_later(struct dma_fence *a,struct dma_fence *b) { return a->seqno>b->seqno; }\nstatic struct dma_fence *dma_fence_allocate_private_stub(ktime_t t) { struct dma_fence *f=calloc(1,sizeof(*f)); assert(f&&nfresh<4); f->stub=true;f->signaled=true;f->timestamp=t;fresh[nfresh++]=f;return f; }\n'
	array := os.read_file(state + '/dma-fence-array.c')!
	for name in ['static void dma_fence_array_clear_pending_error(', 'static bool dma_fence_array_signaled(', 'struct dma_fence_array *dma_fence_array_alloc(', 'void dma_fence_array_init(', 'struct dma_fence_array *dma_fence_array_create(', 'struct dma_fence *dma_fence_array_first(', 'struct dma_fence *dma_fence_array_next('] { c += function(array, name) }
	c += 'static bool host_array_signaled(struct dma_fence *f) { return f->signaled||dma_fence_array_signaled(f); }\n'
	unwrap := os.read_file(state + '/dma-fence-unwrap.c')!
	for name in ['static struct dma_fence *\n__dma_fence_unwrap_array(', 'struct dma_fence *dma_fence_unwrap_first(', 'struct dma_fence *dma_fence_unwrap_next(', 'static int fence_cmp(', 'int dma_fence_dedup_array('] { c += function(unwrap, name) }
	c += '#define dma_fence_unwrap_for_each(f,c,h) for((f)=dma_fence_unwrap_first((h),(c));(f);(f)=dma_fence_unwrap_next(c))\n'
	c += function(unwrap, 'struct dma_fence *__dma_fence_unwrap_merge(')
	c += 'static struct dma_fence *host_merge(struct dma_fence *head) { struct dma_fence_unwrap iter; struct dma_fence *r=__dma_fence_unwrap_merge(1,&head,&iter); if(r&&r->array) { assert(nfresh<4);fresh[nfresh++]=r; } return r; }\n#define dma_fence_unwrap_merge(f) host_merge(f)\n'
	drm := os.read_file(state + '/drm_syncobj.c')!
	c += function(drm, 'static int drm_syncobj_transfer_to_timeline(')
	c += function(drm, 'int\ndrm_syncobj_transfer_ioctl(')
	c += 'int main(void) { const uint64_t seqs[6][3]={{1,2,3},{3,2,1},{0,UINT64_MAX,1},{1,UINT64_C(1)<<63,UINT64_MAX},{UINT64_MAX,0,UINT64_MAX-1},{UINT64_MAX,UINT64_MAX,UINT64_MAX}};const uint64_t sp[]={0,1,2,3,UINT64_MAX},dp[]={0,1,UINT64_MAX};\n'
	c += 'for(int ctx=0;ctx<4;ctx++) { for(int sq=0;sq<6;sq++) { for(int mask=0;mask<8;mask++) { for(int s=0;s<5;s++) { for(int d=0;d<3;d++) { for(int pre=0;pre<3;pre++) {\n'
	c += 'struct drm_syncobj source={0},dest={0};struct dma_fence leaf[4]={0};struct dma_fence_chain nodes[4]={0};nfresh=allocated_count=0;for(int i=0;i<3;i++) { leaf[i].context=ctx==0?(uint64_t)(3-i):ctx==1?1:ctx==2?(uint64_t)(i%2):UINT64_MAX-(uint64_t)i;leaf[i].seqno=seqs[sq][i];leaf[i].signaled=(mask&(1<<i))!=0;dma_fence_chain_init(&nodes[i],source.fence,&leaf[i],(uint64_t)(i+1));source.fence=&nodes[i].base;}if(pre) { leaf[3].context=7;leaf[3].seqno=6;leaf[3].signaled=pre==2;dma_fence_chain_init(&nodes[3],NULL,&leaf[3],10);dest.fence=&nodes[3].base;}names[0]=&source;names[1]=&dest;struct drm_syncobj_transfer args={.src_handle=1,.dst_handle=2,.src_point=sp[s],.dst_point=dp[d]};int code=drm_syncobj_transfer_ioctl(NULL,&args,NULL);struct dma_fence *head=dest.fence,*payload=dp[d]&&code==0?dma_fence_chain_contained(head):head;int kind=!payload?0:payload->chain?3:payload->array?2:payload->stub?1:0;uint64_t submitted=head&&head->chain?head->seqno:0;printf("%d %d %d %" PRIu64 "\\n",code,kind,!head||dma_fence_is_signaled(head),submitted);if(payload) { struct dma_fence_unwrap it;struct dma_fence *f;dma_fence_unwrap_for_each(f,&it,payload) printf("%" PRIu64 " %" PRIu64 "\\n",f->context,f->seqno); }puts("end");for(int i=0;i<allocated_count;i++) free(allocated[i]);for(int i=0;i<nfresh;i++) { if(fresh[i]->array) free(((struct dma_fence_array *)fresh[i])->fences);free(fresh[i]); }\n} } } } } } return 0; }\n'
	os.write_file(state + '/oracle.c', c)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-sign-compare', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	expected := run(state + '/oracle', [])!; actual := run(os.abs_path(os.args[2]), ['--timeline-transfer-trace'])!
	os.write_file(state + '/oracle.log', expected)!; os.write_file(state + '/native.log', actual)!
	assert actual.count('end\n') == 8640 && actual == expected
	println('8640 timeline/binary destination outcomes match pinned TRANSFER, find-fence, chain, array init/lazy readiness, unwrap and merge bodies. Context/unsigned-seq dedup, retired points, pending destination prefixes and MAX points covered. Allocation/refcount/RCU/time/callback plumbing are host stubs; enabled array races and native timing remain separate qualification limits.')
}
