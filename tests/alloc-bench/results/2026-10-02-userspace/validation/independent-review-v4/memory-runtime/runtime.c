#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

void *vinix_memcpy(void *restrict, const void *restrict, size_t);
void *vinix_memset(void *, int, size_t);
void *vinix_memmove(void *, const void *, size_t);
static size_t cases;
static void check(int ok, const char *where, size_t n, size_t a, size_t b) {
    if (!ok) { fprintf(stderr, "FAIL %s n=%zu a=%zu b=%zu\n", where,n,a,b); exit(1); }
}
static unsigned char pattern(size_t i) { return (unsigned char)(i*131u+(i>>4)*17u+23u); }
static void copy_case(unsigned char *dst, const unsigned char *src,
                      size_t whole, size_t d, size_t s, size_t n) {
    for (size_t i=0;i<whole;i++) dst[i]=0xa5;
    check(vinix_memcpy(dst+d,src+s,n)==dst+d,"memcpy return",n,d,s);
    for (size_t i=0;i<whole;i++)
        check(dst[i]==(i>=d&&i-d<n?src[s+i-d]:0xa5),"memcpy content/bounds",n,d,s);
    cases++;
}
static void set_case(unsigned char *dst, size_t whole, size_t d, size_t n, int value) {
    for (size_t i=0;i<whole;i++) dst[i]=0xa5;
    check(vinix_memset(dst+d,value,n)==dst+d,"memset return",n,d,(size_t)value);
    for (size_t i=0;i<whole;i++)
        check(dst[i]==(i>=d&&i-d<n?(unsigned char)value:0xa5),"memset content/bounds",n,d,(size_t)value);
    cases++;
}
static void move_case(unsigned char *dst, size_t whole, size_t d, size_t s, size_t n) {
    for (size_t i=0;i<whole;i++) dst[i]=pattern(i);
    check(vinix_memmove(dst+d,dst+s,n)==dst+d,"memmove return",n,d,s);
    for (size_t i=0;i<whole;i++)
        check(dst[i]==pattern(i>=d&&i-d<n?s+i-d:i),"memmove content/bounds",n,d,s);
    cases++;
}
int main(void) {
    size_t page=(size_t)sysconf(_SC_PAGESIZE);
    unsigned char *sm=mmap(NULL,page*3,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    unsigned char *dm=mmap(NULL,page*3,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    check(sm!=MAP_FAILED&&dm!=MAP_FAILED,"mmap",0,0,0);
    unsigned char *src=sm+page,*dst=dm+page;
    check(!mprotect(src,page,PROT_READ|PROT_WRITE)&&!mprotect(dst,page,PROT_READ|PROT_WRITE),"mprotect",0,0,0);
    for(size_t i=0;i<page;i++) src[i]=pattern(i);
    check(!mprotect(src,page,PROT_READ),"source read-only",0,0,0);
    for(size_t d=0;d<16;d++) for(size_t s=0;s<16;s++) for(size_t n=0;n<=257;n++)
        copy_case(dst,src,512,d,s,n);
    for(size_t d=0;d<16;d++) for(size_t s=0;s<16;s++) for(size_t n=0;n<=257;n++)
        move_case(dst,512,d,s,n);
    const int values[]={0,1,127,128,255,-1,-256,0x1234};
    for(size_t d=0;d<16;d++) for(size_t n=0;n<=257;n++)
        for(size_t c=0;c<sizeof(values)/sizeof(values[0]);c++)
            set_case(dst,512,d,n,values[c]);
    // Requests end precisely at a guard page: any widened final access faults.
    for(size_t n=0;n<=page;n++) {
        copy_case(dst,src,page,page-n,page-n,n);
        if(n<=page-7) copy_case(dst,src,page,page-n,7,n);
        set_case(dst,page,page-n,n,-1);
        set_case(dst,page,0,n,0);
        const size_t distances[]={1,7,8,64};
        for(size_t j=0;j<sizeof(distances)/sizeof(distances[0]);j++) {
            size_t distance=distances[j];
            if(n<=page-distance) {
                move_case(dst,page,distance,0,n);
                move_case(dst,page,0,distance,n);
            }
        }
    }
    // Both pointers can name protected memory for a zero-length operation.
    check(vinix_memcpy(dm,sm,0)==dm,"zero memcpy",0,0,0);
    check(vinix_memset(dm,0,0)==dm,"zero memset",0,0,0);
    check(vinix_memmove(dm,sm,0)==dm,"zero memmove",0,0,0);
    check(!munmap(sm,page*3)&&!munmap(dm,page*3),"munmap",0,0,0);
    printf("KERNEL MEMORY CHECK: PASS cases=%zu page=%zu\n",cases,page);
    return 0;
}
