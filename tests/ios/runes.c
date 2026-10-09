// SPDX-License-Identifier: GPL-2.0-or-later
// Class values and full-domain fingerprints are measured against macOS.
extern int puts(const char *),strcmp(const char *,const char *);
extern unsigned long strlen(const char *);
extern char *strcpy(char *,const char *);
extern char *setlocale(int,const char *);
extern int __maskrune(int,unsigned long);
extern int isspace(int);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *);
extern int pthread_join(unsigned long,void **);
static int (*volatile rune_type)(int,unsigned long)=__maskrune;
static int (*volatile space_type)(int)=isspace;

static int masks(void) {
 int points[]={0,9,10,32,48,57,65,70,71,97,102,103,127,128,255,0xe9,0x301,
  0x3a9,0x200b,0x3000,0x3042,0x4e00,0xd800,0x1f600,0x10ffff};
 unsigned long masks[]={0,15,0xff,0x100,0x4200,0x400000,0xe0000000UL,0xffffffffUL,~0UL,1UL<<32};
 for(unsigned i=0;i<sizeof(points)/sizeof(*points);i++) {
  unsigned full=(unsigned)rune_type(points[i],0xffffffffUL);
  for(unsigned j=0;j<sizeof(masks)/sizeof(*masks);j++)
   if((unsigned)rune_type(points[i],masks[j])!=(full&(unsigned)masks[j]))return 1;
 }
 for(int point=-1;point<256;point++)
  if((space_type(point)!=0)!=(rune_type(point,0x4000)!=0))return 2;
 int invalid[]={(-2147483647-1),-1,0x110000,2147483647};
 for(unsigned i=0;i<sizeof(invalid)/sizeof(*invalid);i++)
  if(rune_type(invalid[i],~0UL))return 3;
 return 0;
}
static void *worker(void *context) { *(int *)context=masks();return 0; }

int main(void) {
 char saved[256];const char *current=setlocale(2,0);
 if(!current||strlen(current)>=sizeof saved)return 1;
 strcpy(saved,current);
 const char *locales[]={"C","en_US.UTF-8","C.utf8"};
 unsigned long expected[]={0xa9111c3e1e4f32b2UL,0xb9c3e5106c617ab2UL,0xb9c3e5106c617ab2UL};
 for(int index=0;index<3;index++) {
  if(!setlocale(2,locales[index])) { if(index==2)continue;return 2; }
  unsigned long digest=14695981039346656037UL;
  for(int point=0;point<0x110000;point++)
   digest=(digest^(unsigned)rune_type(point,0xffffffffUL))*1099511628211UL;
  if(digest!=expected[index]||masks())return 3;
  unsigned long threads[8];int errors[8]={0};
  for(int i=0;i<8;i++)if(pthread_create(&threads[i],0,worker,&errors[i]))return 4;
  for(int i=0;i<8;i++)if(pthread_join(threads[i],0)||errors[i])return 5;
 }
 // C and POSIX are aliases, with non-ASCII classes cleared.
 if(!setlocale(2,"POSIX")||rune_type(0xe9,~0UL)||rune_type('9',15)!=9)return 6;
 if(!setlocale(2,saved))return 7;
 puts("IOS-RUNES: full Unicode fingerprints, C/UTF-8 locales, masks, digit values, widths and eight threads");
 return 0;
}
