// SPDX-License-Identifier: GPL-2.0-or-later
struct calendar {
    int second, minute, hour, day, month, year, weekday, yearday, daylight;
    long offset; char *zone;
};
extern long mktime(struct calendar *),clock(void);
extern struct calendar *localtime_r(const long *,struct calendar *);
extern void tzset(void);extern char *tzname[2];
extern int setenv(const char *,const char *,int),unsetenv(const char *),*__error(void);
extern char *getenv(const char *);extern void *malloc(unsigned long);
extern void free(void *);extern int strcmp(const char *,const char *),puts(const char *),printf(const char *,...);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *),pthread_join(unsigned long,void **);
#define CHECK(value,code) do { if(!(value)){printf("IOS-CALENDAR: failure %d errno %d\n",code,*__error());return code;} } while(0)
struct example { struct calendar input,output;long timestamp; };
static const struct example utc_examples[]={
    {{0,0,0,1,0,70,0,0,-1,0,0},{0,0,0,1,0,70,4,0,0,0,"UTC"},0},
    {{59,59,23,31,11,69,0,0,-1,0,0},{59,59,23,31,11,69,3,364,0,0,"UTC"},-1},
    {{58,59,23,31,11,69,0,0,-1,0,0},{58,59,23,31,11,69,3,364,0,0,"UTC"},-2},
    {{56,34,12,29,1,100,0,0,-1,0,0},{56,34,12,29,1,100,2,59,0,0,"UTC"},951827696},
    {{120,-90,25,0,13,124,0,0,-1,0,0},{0,32,23,31,0,125,5,30,0,0,"UTC"},1738366320},
    {{8,14,3,19,0,138,0,0,-1,0,0},{8,14,3,19,0,138,2,18,0,0,"UTC"},2147483648L},
    {{0,0,0,1,0,2147483647,0,0,-1,0,0},{0,0,0,1,0,2147483647,3,0,0,0,"UTC"},67768036160140800L}
};
static const struct example winter={
    {0,0,12,15,0,124,0,0,-1,0,0},{0,0,12,15,0,124,1,14,0,-18000,"EST"},1705338000
};
static const struct example summer={
    {0,0,12,15,6,124,0,0,-1,0,0},{0,0,12,15,6,124,1,196,1,-14400,"EDT"},1721059200
};
static int equal(const struct calendar *actual,const struct calendar *expected) {
    return actual->second==expected->second && actual->minute==expected->minute && actual->hour==expected->hour &&
        actual->day==expected->day && actual->month==expected->month && actual->year==expected->year &&
        actual->weekday==expected->weekday && actual->yearday==expected->yearday && actual->daylight==expected->daylight &&
        actual->offset==expected->offset && actual->zone && !strcmp(actual->zone,expected->zone);
}
static int convert(const struct example *example) {
    struct {unsigned long before[2];struct calendar value;unsigned long after[2];} guard;
    guard.before[0]=guard.before[1]=guard.after[0]=guard.after[1]=0xabcdef0123456789UL;
    guard.value=example->input;
    *__error()=177;long result=mktime(&guard.value);
    if(result!=example->timestamp || *__error()!=177)
        printf("IOS-CALENDAR: input year %d result %ld expected %ld errno %d\n",example->input.year,result,example->timestamp,*__error());
    CHECK(result==example->timestamp && *__error()==177,1);
    CHECK(equal(&guard.value,&example->output),2);
    CHECK(guard.before[0]==0xabcdef0123456789UL && guard.before[1]==0xabcdef0123456789UL &&
        guard.after[0]==0xabcdef0123456789UL && guard.after[1]==0xabcdef0123456789UL,3);
    struct calendar roundtrip;
    CHECK(localtime_r(&result,&roundtrip)==&roundtrip && equal(&roundtrip,&example->output),4);
    return 0;
}
struct job {int error;};
static void *worker(void *argument) {
    struct job *job=argument;
    for(int i=0;i<32;i++){job->error=convert(i&1?&summer:&winter);if(job->error)break;}
    return 0;
}
static int calendars(int native_darwin) {
    CHECK(sizeof(struct calendar)==56,5);
    CHECK(setenv("TZ","UTC0",1)==0,6);tzset();CHECK(tzname[0] && !strcmp(tzname[0],"UTC"),7);
    *__error()=36;tzset();CHECK(*__error()==36,8);
    for(unsigned i=0;i<sizeof utc_examples/sizeof *utc_examples;i++) {
        int error=convert(&utc_examples[i]);if(error)return error;
    }
    struct calendar huge={0,0,0,1,12,2147483647,0,0,-1,0,0};
    *__error()=177;CHECK(mktime(&huge)==-1 && *__error()==(native_darwin?177:84),9);
    if(!native_darwin)CHECK(mktime(0)==-1 && *__error()==14,11);
    CHECK(setenv("TZ","VIN-3",1)==0,13);tzset();
    struct example east=utc_examples[0];east.timestamp=-10800;east.output.offset=10800;east.output.zone="VIN";
    int error=convert(&east);if(error)return error;
    CHECK(tzname[0] && !strcmp(tzname[0],"VIN"),14);
    CHECK(setenv("TZ","EST5EDT,M3.2.0,M11.1.0",1)==0,15);tzset();
    CHECK(tzname[0] && tzname[1] && !strcmp(tzname[0],"EST") && !strcmp(tzname[1],"EDT"),16);
    error=convert(&winter);if(error)return error;error=convert(&summer);if(error)return error;
    unsigned long threads[8];struct job jobs[8]={0};int started=0,failed=0;
    for(int i=0;i<8;i++){if(pthread_create(&threads[i],0,worker,&jobs[i])!=0)break;started++;}
    for(int i=0;i<started;i++)if(pthread_join(threads[i],0)!=0 || jobs[i].error)failed=1;
    CHECK(started==8 && !failed,17);
    *__error()=177;long first=clock();CHECK(first>=0 && *__error()==177,18);
    volatile unsigned long work=1;for(unsigned long i=0;i<8000000;i++)work=work*33+i;
    *__error()=177;long second=clock();CHECK(second>first && *__error()==177,19);
    return 0;
}
int main(int argc,char **argv) {
    char *previous=getenv("TZ"),*saved=0;
    if(previous){unsigned long length=0;while(previous[length])length++;saved=malloc(length+1);CHECK(saved,20);for(unsigned long i=0;i<=length;i++)saved[i]=previous[i];}
    int error=calendars(argc>1 && !strcmp(argv[1],"--native-darwin"));
    int restored=saved?setenv("TZ",saved,1):unsetenv("TZ");free(saved);tzset();
    if(error)return error;CHECK(restored==0,21);
    puts("IOS-CALENDAR: signed timestamps, normalization, timezone names, DST, guarded layouts, process clocks and eight threads");
    return 0;
}
