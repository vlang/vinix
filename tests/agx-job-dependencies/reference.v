// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string) !string {
 mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
 out := p.stdout_slurp(); p.wait(); assert p.code == 0, out; p.close(); return out
}
fn function(source string, start string) string {
 begin := source.index(start) or { panic(start) }
 end := source.index_after('\n}\n', begin) or { panic(start) }
 return source[begin..end + 3]
}
fn main() {
 assert os.args.len == 4, 'usage: reference PINNED_LINUX NATIVE_TRACE_BINARY FRESH_STATE'
 linux := os.abs_path(os.args[1]); state := os.abs_path(os.args[3]); assert !os.exists(state); os.mkdir_all(state)!
 pin := 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
 assert run('git', ['-C', linux, 'rev-parse', 'HEAD'])!.trim_space() == pin
 mut sources := map[string]string{}; mut pins := ['Linux-Aurora ' + pin]
 for path in ['drivers/gpu/drm/scheduler/sched_main.c', 'drivers/gpu/drm/scheduler/sched_entity.c', 'include/linux/dma-fence.h', 'rust/kernel/dma_fence.rs', 'rust/kernel/drm/sched.rs', 'drivers/gpu/drm/asahi/queue/mod.rs', 'drivers/gpu/drm/scheduler/sched_fence.c', 'drivers/dma-buf/dma-fence.c'] {
  source := run('git', ['-C', linux, 'show', pin + ':' + path])!
  name := os.file_name(path)
  sources[name] = source; os.write_file(state + '/' + name, source)!
  pins << path + ' sha256 ' + sha256.sum(source.bytes()).hex()
 }
 os.write_file(state + '/pins.txt', pins.join('\n') + '\n')!
 compare := function(sources['dma-fence.h'], 'static inline bool __dma_fence_is_later(') + function(sources['dma-fence.h'], 'static inline bool dma_fence_is_later(')
 add := function(sources['sched_main.c'], 'int drm_sched_job_add_dependency(')
 ready := function(sources['sched_entity.c'], 'static bool drm_sched_entity_add_dependency_cb(')
 // The primary bodies above stay unchanged. Stubs model xarray storage,
 // refcounts, callback registration and generic (non-scheduler-wrapper) fences.
 stub := '#include <stdint.h>\n#include <stdbool.h>\n#include <stdio.h>\n#include <assert.h>\n#include <stddef.h>\ntypedef uint64_t u64; typedef uint32_t u32;\n' +
  'struct dma_fence {u64 context,seqno; unsigned long flags; int error; unsigned ordinal;};\n' +
  '#define DMA_FENCE_FLAG_SIGNALED_BIT 0\n#define DMA_FENCE_FLAG_SEQNO64_BIT 1\n#define DRM_SCHED_FENCE_DONT_PIPELINE 2\n#define GFP_KERNEL 0\n#define xa_limit_32b 0\n#define lower_32_bits(x) ((u32)(x))\n#define WARN_ON(x) (x)\n' +
  'static bool test_bit(unsigned n,const unsigned long *flags){return (*flags >> n)&1;}\n' +
  'struct xarray {struct dma_fence *entries[4]; unsigned count;}; struct drm_gpu_scheduler {int unused;}; struct drm_sched_rq {struct drm_gpu_scheduler *sched;};\n' +
  'struct drm_sched_job {struct xarray dependencies;}; struct drm_sched_fence {struct drm_gpu_scheduler *sched; struct dma_fence scheduled;}; struct callback {int unused;}; struct drm_sched_entity {struct drm_sched_rq *rq; struct dma_fence *dependency; u64 fence_context; struct callback cb;};\n' +
  '#define xa_for_each(xa,index,entry) for((index)=0;(index)<(xa)->count && (((entry)=(xa)->entries[index]),1);++(index))\n' +
  'static void xa_store(struct xarray *xa,unsigned long index,struct dma_fence *f,int flags){(void)flags;xa->entries[index]=f;}\n' +
  'static int xa_alloc(struct xarray *xa,u32 *id,struct dma_fence *f,int limit,int flags){(void)limit;(void)flags;assert(xa->count<4);*id=xa->count;xa->entries[xa->count++]=f;return 0;}\n' +
  'static void dma_fence_put(struct dma_fence *f){(void)f;} static struct dma_fence *dma_fence_get(struct dma_fence *f){return f;}\n' +
  'static struct drm_sched_fence *to_drm_sched_fence(struct dma_fence *f){(void)f;return NULL;}\n' +
  'static void drm_sched_entity_wakeup(struct dma_fence *f,struct callback *cb){(void)f;(void)cb;}\n' +
  'static int dma_fence_add_callback(struct dma_fence *f,struct callback *cb,void (*fn)(struct dma_fence *,struct callback *)){(void)cb;(void)fn;return (f->flags&1)?-2:0;}\n' +
  'static bool trace_drm_sched_job_unschedulable_enabled(void){return false;}\n#define trace_drm_sched_job_unschedulable(job,fence) ((void)(job),(void)(fence))\n'
 mut main_code := 'int main(void){const u64 contexts[4][4]={{0,0,0,0},{1,2,1,2},{UINT64_MAX,1,UINT64_MAX,0},{1,2,3,4}}; const u64 sequences[4][4]={{0,1,UINT64_MAX,2},{UINT64_MAX,UINT64_MAX,1,1},{1,1,1,1},{UINT64_C(0x7fffffffffffffff),UINT64_C(0x8000000000000000),0,UINT64_MAX}};\n' +
  'for(unsigned c=0;c<4;++c)for(unsigned s=0;s<4;++s)for(unsigned nils=0;nils<16;++nils)for(unsigned done=0;done<16;++done){struct drm_sched_job job={0};struct dma_fence leaves[4];for(unsigned i=0;i<4;++i){leaves[i]=(struct dma_fence){.context=contexts[c][i],.seqno=sequences[s][i],.flags=2|((done>>i)&1),.error=-5,.ordinal=i+1};assert(drm_sched_job_add_dependency(&job,(nils&(1u<<i))?NULL:&leaves[i])==0);}\n' +
  'unsigned ready=1; struct drm_gpu_scheduler scheduler={0};struct drm_sched_rq rq={.sched=&scheduler};struct drm_sched_entity entity={.rq=&rq,.fence_context=UINT64_MAX-2};printf("%u %u %u",nils,done,job.dependencies.count);for(unsigned i=0;i<job.dependencies.count;++i){printf(" %u",job.dependencies.entries[i]->ordinal);entity.dependency=job.dependencies.entries[i];if(drm_sched_entity_add_dependency_cb(&entity,&job))ready=0;}printf(" ready=%u\\n",ready);}return 0;}\n'
 main_code = main_code.replace('++c)for', '++c){for').replace('++s)for', '++s){for').replace('++nils)for', '++nils){for').replace('}return 0;}', '} } } } return 0;}')
 os.write_file(state + '/oracle.c', stub + compare + add + ready + main_code)!
 _ = run('cc', ['-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
 oracle := run(state + '/oracle', [])!; native := run(os.abs_path(os.args[2]), [])!
 os.write_file(state + '/oracle.log', oracle)!; os.write_file(state + '/native.log', native)!
 assert oracle == native && native.split_into_lines().len == 4096
 println('4096 dependency selections and generic-fence readiness outcomes match unchanged pinned scheduler add/callback and 64-bit comparator bodies; xarray/refcount/callback plumbing modeled.')
}
