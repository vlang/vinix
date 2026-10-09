// SPDX-License-Identifier: GPL-2.0-or-later
// Shared Mac reference / iOS Mach-O fixture. Nodes stay mapped through every
// concurrent dequeue, as required by the public OSAtomicQueue contract.
#ifdef IOS_QUEUE_REFERENCE
#include <libkern/OSAtomicQueue.h>
#include <pthread.h>
typedef pthread_t QueueThread;
#else
typedef volatile struct {
 void *opaque1;
 long opaque2;
} __attribute__((aligned(16))) OSQueueHead;
#define OS_ATOMIC_QUEUE_INIT {0,0}
extern void OSAtomicEnqueue(OSQueueHead *,void *,unsigned long);
extern void *OSAtomicDequeue(OSQueueHead *,unsigned long);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *);
extern int pthread_join(unsigned long,void **);
typedef unsigned long QueueThread;
#endif
extern int puts(const char *),printf(const char *,...);
#define REQUIRE(expression) do { if (!(expression)) { \
 printf("IOS-ATOMIC-QUEUE FAIL: line %d: %s\n",__LINE__,#expression);return 1; } } while(0)
struct Item { unsigned long id; void *next; unsigned long guard; };
struct Other { unsigned long guard1,guard2; void *next; unsigned long guard3; };
static OSQueueHead concurrent=OS_ATOMIC_QUEUE_INIT;
static struct Item items[8];
struct Worker { struct Item *held; int error; };
static struct Worker workers[8];
static void *worker(void *context) {
 struct Worker *state=context;
 struct Item *held=state->held;
 for(int repeat=0;repeat<4096;repeat++) {
  OSAtomicEnqueue(&concurrent,held,__builtin_offsetof(struct Item,next));
  held=OSAtomicDequeue(&concurrent,__builtin_offsetof(struct Item,next));
  // Only one of the eight permanent nodes may be returned, once per owner.
  int known=0;
  for(int i=0;i<8;i++)if(held==&items[i])known=1;
  if(!known || held->id>=8 || held->guard!=0x0123456789abcdefUL) {
   state->error=1;return 0;
  }
 }
 state->held=held;
 return 0;
}
int main(void) {
 REQUIRE(sizeof(OSQueueHead)==16 && _Alignof(OSQueueHead)==16);
 OSQueueHead queue=OS_ATOMIC_QUEUE_INIT,other=OS_ATOMIC_QUEUE_INIT;
 struct Item a={1,0,11},b={2,0,22};
 struct Other c={33,44,0,55};
 REQUIRE(!OSAtomicDequeue(&queue,__builtin_offsetof(struct Item,next)) && queue.opaque2==0);
 OSAtomicEnqueue(&queue,&a,__builtin_offsetof(struct Item,next));
 REQUIRE(queue.opaque1==&a && queue.opaque2==1 && !a.next);
 OSAtomicEnqueue(&queue,&b,__builtin_offsetof(struct Item,next));
 OSAtomicEnqueue(&other,&c,__builtin_offsetof(struct Other,next));
 REQUIRE(queue.opaque1==&b && queue.opaque2==2 && b.next==&a && !c.next);
 REQUIRE(OSAtomicDequeue(&queue,__builtin_offsetof(struct Item,next))==&b);
 REQUIRE(queue.opaque1==&a && queue.opaque2==3 && b.next==&a);
 REQUIRE(OSAtomicDequeue(&queue,__builtin_offsetof(struct Item,next))==&a);
 REQUIRE(!queue.opaque1 && queue.opaque2==4);
 REQUIRE(!OSAtomicDequeue(&queue,__builtin_offsetof(struct Item,next)) && queue.opaque2==4);
 REQUIRE(OSAtomicDequeue(&other,__builtin_offsetof(struct Other,next))==&c && other.opaque2==2);
 REQUIRE(a.id==1 && a.guard==11 && b.id==2 && b.guard==22 && c.guard1==33 && c.guard2==44 && c.guard3==55);
 QueueThread threads[8];
 for(int i=0;i<8;i++) {
  items[i].id=(unsigned long)i;items[i].guard=0x0123456789abcdefUL;workers[i].held=&items[i];
  REQUIRE(!pthread_create(&threads[i],0,worker,&workers[i]));
 }
 for(int i=0;i<8;i++)REQUIRE(!pthread_join(threads[i],0));
 unsigned long seen=0;
 for(int i=0;i<8;i++) {
  REQUIRE(!workers[i].error && workers[i].held);
  unsigned long bit=1UL<<workers[i].held->id;
  REQUIRE(!(seen&bit));seen|=bit;
 }
 REQUIRE(seen==255 && !concurrent.opaque1 && concurrent.opaque2==65536);
 REQUIRE(!OSAtomicDequeue(&concurrent,__builtin_offsetof(struct Item,next)) && concurrent.opaque2==65536);
 puts("IOS-ATOMIC-QUEUE: LIFO, generation, independent offsets and eight-thread node reuse");
 return 0;
}
