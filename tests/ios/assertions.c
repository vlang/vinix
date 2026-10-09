// SPDX-License-Identifier: GPL-2.0-or-later
extern void __assert_rtn(const char *,const char *,int,const char *) __attribute__((noreturn));
extern int puts(const char *),strcmp(const char *,const char *);
int main(int argc,char **argv) {
 if(argc>1) {
  const char *function=strcmp(argv[1],"no-function")?"fixture":0;
  __assert_rtn(function,"synthetic.c",17,"1 == 2");
 }
 void (*volatile assertion)(const char *,const char *,int,const char *)=__assert_rtn;
 if(!assertion)return 1;
 puts("IOS-ASSERT: native assertion import");
 return 0;
}
