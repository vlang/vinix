// SPDX-License-Identifier: GPL-2.0-or-later
// Run the same CRUD/query calls on Vinix and an isolated Mac test keychain.
typedef const void *CFTypeRef, *CFStringRef, *CFDictionaryRef, *CFDataRef, *CFArrayRef;
typedef unsigned long CFTypeID;
extern int puts(const char *), printf(const char *,...), strcmp(const char *,const char *), memcmp(const void *,const void *,unsigned long);
extern CFStringRef CFStringCreateWithCString(const void *,const char *,unsigned);
extern CFDataRef CFDataCreate(const void *,const unsigned char *,long);
extern CFTypeRef CFNumberCreate(const void *,long,const void *);
extern CFDictionaryRef CFDictionaryCreate(const void *,const void **,const void **,long,const void *,const void *);
extern CFTypeRef CFDictionaryGetValue(CFDictionaryRef,const void *);
extern CFArrayRef CFArrayCreate(const void *,const void **,long,const void *);
extern long CFArrayGetCount(CFArrayRef), CFDataGetLength(CFDataRef);
extern const void *CFArrayGetValueAtIndex(CFArrayRef,long);
extern const unsigned char *CFDataGetBytePtr(CFDataRef);
extern unsigned char CFEqual(CFTypeRef,CFTypeRef);
extern void CFRelease(CFTypeRef);
extern CFTypeID CFGetTypeID(CFTypeRef), CFDataGetTypeID(void), CFArrayGetTypeID(void), CFDictionaryGetTypeID(void);
extern const char kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks, kCFTypeArrayCallBacks;
extern const CFTypeRef kCFBooleanTrue, kCFBooleanFalse;
extern const CFStringRef kSecClass, kSecClassGenericPassword, kSecAttrService, kSecAttrAccount, kSecAttrType, kSecAttrDescription, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock, kSecValueData, kSecReturnData, kSecReturnAttributes, kSecMatchLimit, kSecMatchLimitAll, kSecMatchLimitOne, kSecUseAuthenticationUI, kSecUseAuthenticationUISkip;
extern int SecItemAdd(CFDictionaryRef,CFTypeRef *), SecItemCopyMatching(CFDictionaryRef,CFTypeRef *), SecItemUpdate(CFDictionaryRef,CFDictionaryRef), SecItemDelete(CFDictionaryRef);
#ifdef IOS_KEYCHAIN_REFERENCE
extern int SecKeychainSetUserInteractionAllowed(unsigned char), SecKeychainCreate(const char *,unsigned,const void *,unsigned char,void *,void **), SecKeychainDelete(const void *);
extern const CFStringRef kSecUseKeychain, kSecMatchSearchList;
extern int snprintf(char *,unsigned long,const char *,...), rmdir(const char *);
extern char *mkdtemp(char *);
static void *chain;
static CFArrayRef search;
#endif
#define REQUIRE(x) do { if(!(x)) { printf("IOS-KEYCHAIN FAIL: line %d: %s\n",__LINE__,#x);return 1; } } while(0)
static const unsigned char secret[]={0x76,0x69,0x6e,0x69,0x78,0,0xff,0x41,0x42};
static const unsigned char replacement[]={1,0,2,0,3,0,4};
static CFDictionaryRef dict(const void **keys,const void **values,long count) {
 return CFDictionaryCreate(0,keys,values,count,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
}
static CFStringRef string(const char *text) { return CFStringCreateWithCString(0,text,0x08000100); }
static CFDictionaryRef query(const char *account,int type,int add,int data,int attrs,int all) {
 CFStringRef service=string("vinix-keychain-fixture"), acct=account?string(account):0, desc=string("EOS credential fixture");
 CFTypeRef number=CFNumberCreate(0,3,&type);
 CFDataRef bytes=CFDataCreate(0,secret,sizeof secret);
 const void *keys[16],*values[16];long count=0;
#define PUT(k,v) do { keys[count]=(k);values[count++]=(v); } while(0)
 PUT(kSecClass,kSecClassGenericPassword);PUT(kSecAttrService,service);
 if(acct)PUT(kSecAttrAccount,acct);
 if(type>=0)PUT(kSecAttrType,number);
 if(add) { PUT(kSecAttrDescription,desc);PUT(kSecValueData,bytes);PUT(kSecAttrAccessible,kSecAttrAccessibleAfterFirstUnlock); }
 else PUT(kSecUseAuthenticationUI,kSecUseAuthenticationUISkip);
 if(data)PUT(kSecReturnData,kCFBooleanTrue);
 if(attrs)PUT(kSecReturnAttributes,kCFBooleanTrue);
 if(all>=0)PUT(kSecMatchLimit,all?kSecMatchLimitAll:kSecMatchLimitOne);
#ifdef IOS_KEYCHAIN_REFERENCE
 if(add)PUT(kSecUseKeychain,chain);else PUT(kSecMatchSearchList,search);
#endif
 CFDictionaryRef result=dict(keys,values,count);
 CFRelease(service);if(acct)CFRelease(acct);CFRelease(desc);CFRelease(number);CFRelease(bytes);
 return result;
#undef PUT
}
static int data_equals(CFTypeRef value,const unsigned char *bytes,long length) {
 return value && CFGetTypeID(value)==CFDataGetTypeID() && CFDataGetLength(value)==length && !memcmp(CFDataGetBytePtr(value),bytes,(unsigned long)length);
}
static int match(const char *account,int type,const unsigned char *expected,long length) {
 CFDictionaryRef q=query(account,type,0,1,0,0);CFTypeRef out=(CFTypeRef)0x1234;
 REQUIRE(SecItemCopyMatching(q,&out)==0 && data_equals(out,expected,length));CFRelease(q);CFRelease(out);return 0;
}
static int fixture(void) {
 CFDictionaryRef q=query(0,-1,0,0,0,-1);
 // Queries are restricted to the isolated reference chain or Vinix fixture app.
 int status=SecItemDelete(q);REQUIRE(status==0 || status==-25300);CFRelease(q);
 q=query("one",123,0,1,0,0);CFTypeRef out=(CFTypeRef)0x1234;
 REQUIRE(SecItemCopyMatching(q,&out)==-25300 && !out);CFRelease(q);
 for(int repeat=0;repeat<8;repeat++) {
  q=query("one",123,1,1,0,-1);out=(CFTypeRef)0x1234;
  REQUIRE(SecItemAdd(q,&out)==0 && data_equals(out,secret,sizeof secret));CFRelease(out);
  out=(CFTypeRef)0x1234;REQUIRE(SecItemAdd(q,&out)==-25299 && !out);CFRelease(q);
  q=query("one",124,1,0,0,-1);REQUIRE(SecItemAdd(q,0)==-25299);CFRelease(q);
  REQUIRE(!match("one",123,secret,sizeof secret));
  q=query("one",124,0,1,0,0);out=(CFTypeRef)0x1234;
  REQUIRE(SecItemCopyMatching(q,&out)==-25300 && !out);CFRelease(q);
  // Result shapes and ownership: returned data/dictionaries survive their queries.
  q=query("one",123,0,1,1,0);out=0;
  REQUIRE(SecItemCopyMatching(q,&out)==0);CFRelease(q);
  REQUIRE(CFGetTypeID(out)==CFDictionaryGetTypeID());
  REQUIRE(data_equals(CFDictionaryGetValue(out,kSecValueData),secret,sizeof secret));
  CFStringRef expected=string("one");REQUIRE(CFEqual(expected,CFDictionaryGetValue(out,kSecAttrAccount)));CFRelease(expected);CFRelease(out);
  q=query("one",123,0,0,1,0);out=0;REQUIRE(SecItemCopyMatching(q,&out)==0);
  REQUIRE(CFGetTypeID(out)==CFDictionaryGetTypeID() && !CFDictionaryGetValue(out,kSecValueData));CFRelease(q);CFRelease(out);
  q=query("one",123,0,0,0,0);out=(CFTypeRef)0x1234;
  REQUIRE(SecItemCopyMatching(q,&out)==0);
#ifdef IOS_KEYCHAIN_REFERENCE
  // The Mac legacy keychain supplies a default item reference. iOS has none.
  if(out)CFRelease(out);
#else
  REQUIRE(!out);
#endif
  REQUIRE(SecItemCopyMatching(q,0)==0);CFRelease(q);
  q=query("two",123,1,0,0,-1);REQUIRE(SecItemAdd(q,0)==0);CFRelease(q);
  q=query(0,123,0,0,1,1);out=0;
  REQUIRE(SecItemCopyMatching(q,&out)==0 && CFGetTypeID(out)==CFArrayGetTypeID() && CFArrayGetCount(out)==2);
  REQUIRE(CFGetTypeID(CFArrayGetValueAtIndex(out,0))==CFDictionaryGetTypeID() && CFGetTypeID(CFArrayGetValueAtIndex(out,1))==CFDictionaryGetTypeID());CFRelease(q);CFRelease(out);
  // A colliding update must preserve both records.
  expected=string("two");const void *keys[]={kSecAttrAccount},*values[]={expected};
  CFDictionaryRef changes=dict(keys,values,1);CFRelease(expected);
  q=query("one",123,0,0,0,-1);REQUIRE(SecItemUpdate(q,changes)==-25299);CFRelease(changes);CFRelease(q);
  REQUIRE(!match("one",123,secret,sizeof secret));REQUIRE(!match("two",123,secret,sizeof secret));
  CFDataRef bytes=CFDataCreate(0,replacement,sizeof replacement);
  const void *data_keys[]={kSecValueData},*data_values[]={bytes};changes=dict(data_keys,data_values,1);CFRelease(bytes);
  q=query("one",123,0,0,0,-1);REQUIRE(SecItemUpdate(q,changes)==0);CFRelease(q);
  REQUIRE(!match("two",123,secret,sizeof secret));
  q=query("two",123,0,0,0,-1);REQUIRE(SecItemUpdate(q,changes)==0);CFRelease(changes);CFRelease(q);
  REQUIRE(!match("one",123,replacement,sizeof replacement));REQUIRE(!match("two",123,replacement,sizeof replacement));
  q=query("one",123,0,0,0,-1);REQUIRE(SecItemDelete(q)==0);REQUIRE(SecItemDelete(q)==-25300);CFRelease(q);
  q=query("two",123,0,0,0,-1);REQUIRE(SecItemDelete(q)==0);REQUIRE(SecItemDelete(q)==-25300);
  out=(CFTypeRef)0x1234;REQUIRE(SecItemCopyMatching(q,&out)==-25300 && !out);CFRelease(q);
 }
 return 0;
}
int main(int argc,char **argv) { @autoreleasepool {
#ifdef IOS_KEYCHAIN_REFERENCE
 char directory[]="/tmp/vinix-keychain-XXXXXX",path[256];
 REQUIRE(mkdtemp(directory));snprintf(path,sizeof path,"%s/fixture.keychain",directory);
 REQUIRE(!SecKeychainSetUserInteractionAllowed(0));
 REQUIRE(!SecKeychainCreate(path,5,"vinix",0,0,&chain));
 const void *value=chain;search=CFArrayCreate(0,&value,1,&kCFTypeArrayCallBacks);
#endif
 int result=0;
 if(argc>1 && !strcmp(argv[1],"race")) {
  REQUIRE(argc>2);
  CFDictionaryRef q=query(argv[2],123,1,0,0,-1);REQUIRE(SecItemAdd(q,0)==0);CFRelease(q);
  puts("IOS-KEYCHAIN: concurrent credential writer completed");
 } else if(argc>1 && !strcmp(argv[1],"read-race")) {
  for(int i=0;i<2;i++) {
   const char *account=i?"writer-two":"writer-one";
   REQUIRE(!match(account,123,secret,sizeof secret));
   CFDictionaryRef q=query(account,123,0,0,0,-1);REQUIRE(SecItemDelete(q)==0);CFRelease(q);
  }
  puts("IOS-KEYCHAIN: concurrent credentials preserved");
 } else if(argc>1) {
  CFDictionaryRef q=query("persist",123,!strcmp(argv[1],"write"),0,0,-1);
  if(!strcmp(argv[1],"write")) { REQUIRE(SecItemAdd(q,0)==0); }
  else if(!strcmp(argv[1],"read")) { REQUIRE(!match("persist",123,secret,sizeof secret)); }
  else { REQUIRE(!strcmp(argv[1],"delete") && SecItemDelete(q)==0); }
  CFRelease(q);
  puts("IOS-KEYCHAIN: credential persisted across process restart");
 } else { result=fixture();if(!result)puts("IOS-KEYCHAIN: generic passwords, duplicate/update/delete, binary data, one/all results and ownership"); }
#ifdef IOS_KEYCHAIN_REFERENCE
 CFRelease(search);REQUIRE(!SecKeychainDelete(chain));CFRelease(chain);REQUIRE(!rmdir(directory));
#endif
 return result;
}}
