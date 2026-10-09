// SPDX-License-Identifier: GPL-2.0-or-later
// Installed Mac CFNetwork is a read-only ABI/type reference. Vinix's explicit
// runtime proxy configuration is tested without contacting a proxy or server.
typedef const void *Object;
typedef unsigned long Type;
__attribute__((objc_root_class))
@interface NSNumber
- (long)integerValue;
@end
extern int puts(const char *), printf(const char *,...), strcmp(const char *,const char *), setenv(const char *,const char *,int), unsetenv(const char *);
extern Object CFNetworkCopySystemProxySettings(void), CFDictionaryGetValue(Object,Object), CFRetain(Object);
extern void CFRelease(Object);
extern Type CFGetTypeID(Object), CFDictionaryGetTypeID(void), CFStringGetTypeID(void), CFNumberGetTypeID(void);
extern unsigned char CFStringGetCString(Object,char *,long,unsigned);
extern const Object kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPPort, kCFNetworkProxiesHTTPProxy;
#define REQUIRE(test) do{if(!(test)){printf("IOS-PROXY FAIL: line %d: %s\n",__LINE__,#test);return 1;}}while(0)
static int text_equals(Object string,const char *expected) {
 char text[256]={0};return string && CFGetTypeID(string)==CFStringGetTypeID() && CFStringGetCString(string,text,sizeof text,0x08000100) && !strcmp(text,expected);
}
#ifndef IOS_PROXY_REFERENCE
static int check_enabled(Object settings,const char *host,long port) {
 REQUIRE(settings && CFGetTypeID(settings)==CFDictionaryGetTypeID());
 Object enabled=CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPEnable),number=CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPPort);
 REQUIRE(enabled && number && CFGetTypeID(enabled)==CFNumberGetTypeID() && CFGetTypeID(number)==CFNumberGetTypeID());
 REQUIRE([(NSNumber *)enabled integerValue]==1 && [(NSNumber *)number integerValue]==port);
 REQUIRE(text_equals(CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPProxy),host));
 return 0;
}
#endif
int main(int argc,char **argv) {
 REQUIRE(text_equals(kCFNetworkProxiesHTTPEnable,"HTTPEnable"));
 REQUIRE(text_equals(kCFNetworkProxiesHTTPPort,"HTTPPort"));
 REQUIRE(text_equals(kCFNetworkProxiesHTTPProxy,"HTTPProxy"));
#ifdef IOS_PROXY_REFERENCE
 (void)argc;(void)argv;
 Object settings=CFNetworkCopySystemProxySettings();
 if(settings) {
  REQUIRE(CFGetTypeID(settings)==CFDictionaryGetTypeID());
  Object enabled=CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPEnable),port=CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPPort),host=CFDictionaryGetValue(settings,kCFNetworkProxiesHTTPProxy);
  if(enabled)REQUIRE(CFGetTypeID(enabled)==CFNumberGetTypeID());
  if(port)REQUIRE(CFGetTypeID(port)==CFNumberGetTypeID());
  if(host)REQUIRE(CFGetTypeID(host)==CFStringGetTypeID());
  CFRetain(settings);CFRelease(settings);CFRelease(settings);
 }
#else
 if(argc>1 && !strcmp(argv[1],"invalid")) {
  REQUIRE(!setenv("VINIX_IOS_HTTP_PROXY","http://user:password@proxy.vinix.test:80",1));
  CFNetworkCopySystemProxySettings();return 2; // Must fail explicitly.
 }
 REQUIRE(!unsetenv("VINIX_IOS_HTTP_PROXY") && !CFNetworkCopySystemProxySettings());
 for(int repeat=0;repeat<8;repeat++) {
  REQUIRE(!setenv("VINIX_IOS_HTTP_PROXY","http://proxy.vinix.test:3128",1));
  Object first=CFNetworkCopySystemProxySettings();REQUIRE(!check_enabled(first,"proxy.vinix.test",3128));
  REQUIRE(!setenv("VINIX_IOS_HTTP_PROXY","http://127.0.0.1/",1));
  Object second=CFNetworkCopySystemProxySettings();REQUIRE(!check_enabled(second,"127.0.0.1",80));
  REQUIRE(!unsetenv("VINIX_IOS_HTTP_PROXY") && !CFNetworkCopySystemProxySettings());
  REQUIRE(!check_enabled(first,"proxy.vinix.test",3128)); // Owned snapshot, not borrowed getenv memory.
  CFRelease(first);CFRetain(second);CFRelease(second);CFRelease(second);
 }
#endif
 puts("IOS-PROXY: typed HTTP proxy constants, configuration snapshots and owned settings");return 0;
}
