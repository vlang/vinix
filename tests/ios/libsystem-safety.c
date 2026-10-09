// SPDX-License-Identifier: GPL-2.0-or-later
// Identical explicit ABI calls run against installed Mac libraries and Vinix.
typedef unsigned long size_t;
extern int puts(const char *),strcmp(const char *,const char *);
extern void *memset(void *,int,size_t);
extern int memcmp(const void *,const void *,size_t);
extern void *malloc(size_t);
extern void free(void *);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *);
extern int pthread_join(unsigned long,void **);
extern int __darwin_check_fd_set_overflow(int,const void *,int);
extern void *__memcpy_chk(void *,const void *,size_t,size_t);
extern void *__memmove_chk(void *,const void *,size_t,size_t);
extern void *__memset_chk(void *,int,size_t,size_t);
extern char *__strncpy_chk(char *,const char *,size_t,size_t);
extern char *__strcat_chk(char *,const char *,size_t);

static int (*volatile fd_check)(int,const void *,int)=__darwin_check_fd_set_overflow;
static void *(*volatile copy_check)(void *,const void *,size_t,size_t)=__memcpy_chk;
static void *(*volatile move_check)(void *,const void *,size_t,size_t)=__memmove_chk;
static void *(*volatile fill_check)(void *,int,size_t,size_t)=__memset_chk;
static char *(*volatile ncopy_check)(char *,const char *,size_t,size_t)=__strncpy_chk;
static char *(*volatile cat_check)(char *,const char *,size_t)=__strcat_chk;
static unsigned global_set[32];

static int descriptor_sets(void) {
 struct { unsigned long before; unsigned bits[64]; unsigned long after; } set={0};
 set.before=set.after=0x3141592653589793UL;
 int descriptors[]={(-2147483647-1),-1,0,31,32,1023,1024,2047,2147483647};
 int flags[]={0,1,-1};
 for(unsigned i=0;i<sizeof(descriptors)/sizeof(*descriptors);i++)
  for(unsigned j=0;j<sizeof(flags)/sizeof(*flags);j++) {
   int fd=descriptors[i],flag=flags[j];
   int expected=fd>=0&&(fd<1024||flag!=0);
   if(fd_check(fd,set.bits,flag)!=expected||fd_check(fd,0,flag)!=(fd>=0))return 1;
  }
 // Reproduce SDK FD_SET/FD_CLR/FD_ISSET using Darwin's 32-bit words.
 int indices[]={-1,0,31,32,1023,1024,2047};
 for(unsigned i=0;i<sizeof(indices)/sizeof(*indices);i++) {
  int fd=indices[i];
  if(fd_check(fd,set.bits,1))set.bits[(unsigned)fd/32]|=1U<<((unsigned)fd%32);
 }
 if(set.bits[0]!=0x80000001U||set.bits[1]!=1||set.bits[31]!=0x80000000U||
    set.bits[32]!=1||set.bits[63]!=0x80000000U)return 2;
 unsigned before=set.bits[32];
 if(fd_check(1024,set.bits,0))set.bits[32]=0;
 if(set.bits[32]!=before)return 3;
 for(unsigned i=0;i<sizeof(indices)/sizeof(*indices);i++) {
  int fd=indices[i];
  if(fd_check(fd,set.bits,1)) {
   unsigned mask=1U<<((unsigned)fd%32);
   if(!(set.bits[(unsigned)fd/32]&mask))return 4;
   set.bits[(unsigned)fd/32]&=~mask;
  }
 }
 for(unsigned i=0;i<64;i++)if(set.bits[i])return 5;
 if(set.before!=0x3141592653589793UL||set.after!=set.before)return 6;
 void *heap=malloc(128);
 if(!heap)return 7;
 int heap_allowed=fd_check(1024,heap,0);
 free(heap);
 if(heap_allowed!=1||fd_check(1024,global_set,0)!=1)return 8;
 // Native containment reports an overflowing address range as an error,
 // which the Darwin predicate treats as contained and rejects in strict mode.
 if(fd_check(1024,(void *)((size_t)-1-63),0)!=0)return 9;
 return 0;
}

static void *worker(void *context) { *(int *)context=descriptor_sets();return 0; }

int main(int argc,char **argv) {
 char buffer[18];memset(buffer,0xa7,sizeof buffer);
 if(argc>1) {
  if(!strcmp(argv[1],"memcpy"))copy_check(0,0,3,2);
  else if(!strcmp(argv[1],"memmove"))move_check(0,0,3,2);
  else if(!strcmp(argv[1],"memset"))fill_check(0,1,3,2);
  else if(!strcmp(argv[1],"strncpy"))ncopy_check(0,0,3,2);
  else if(!strcmp(argv[1],"strcat")) {buffer[0]='a';buffer[1]=0;cat_check(buffer,"bc",3);}
  else if(!strcmp(argv[1],"unterminated"))cat_check(buffer,"",3);
  else if(!strcmp(argv[1],"zero-capacity"))cat_check(buffer,"",0);
  else return 90;
  return 91; // Each overflowing operation must terminate before returning.
 }
 if(descriptor_sets())return 1;
 unsigned long threads[8];int errors[8]={0};
 for(int i=0;i<8;i++)if(pthread_create(&threads[i],0,worker,&errors[i]))return 14;
 for(int i=0;i<8;i++)if(pthread_join(threads[i],0)||errors[i])return 15;
 char *out=buffer+1;
 if(copy_check(out,"abcdefg",8,16)!=out||strcmp(out,"abcdefg"))return 2;
 if(move_check(out+1,out,8,15)!=out+1||memcmp(out,"aabcdefg",9))return 3;
 if(move_check(out,out+1,8,16)!=out||strcmp(out,"abcdefg"))return 4;
 if(fill_check(out,0,16,16)!=out)return 5;
 if(ncopy_check(out,"abcd",3,16)!=out||memcmp(out,"abc\0",4))return 6;
 if(ncopy_check(out,"x",16,16)!=out||out[0]!='x')return 7;
 for(unsigned i=1;i<16;i++)if(out[i])return 8;
 if(ncopy_check(out,"ignored",0,0)!=out||strcmp(out,"x"))return 9;
 if(cat_check(out,"yz",4)!=out||strcmp(out,"xyz"))return 10;
 if(cat_check(out,"",4)!=out||strcmp(out,"xyz"))return 11;
 if(cat_check(out,"123",(size_t)-1)!=out||strcmp(out,"xyz123"))return 12;
 if((unsigned char)buffer[0]!=0xa7||(unsigned char)buffer[17]!=0xa7)return 13;
 puts("IOS-LIBSYSTEM-SAFETY: descriptor limits, unlimited bitmaps, overlap, padding and fortified strings");
 return 0;
}
