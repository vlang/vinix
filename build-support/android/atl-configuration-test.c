// Exercise actual ATL objects and the patched androidfw C facade on the builder.
#define _LARGEFILE64_SOURCE
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <androidfw/androidfw_c_api.h>

typedef void AConfiguration;
extern AConfiguration *AConfiguration_new(void);
extern void AConfiguration_delete(AConfiguration *);
extern void AConfiguration_fromAssetManager(AConfiguration *, struct AssetManager *);
extern void AConfiguration_copy(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_diff(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_match(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_getDensity(AConfiguration *);
extern int32_t AConfiguration_getScreenWidthDp(AConfiguration *);
extern int32_t AConfiguration_getScreenHeightDp(AConfiguration *);
extern int32_t AConfiguration_getSmallestScreenWidthDp(AConfiguration *);
extern int32_t AConfiguration_getSdkVersion(AConfiguration *);
extern int32_t AConfiguration_getScreenSize(AConfiguration *);
extern int32_t AConfiguration_getNavHidden(AConfiguration *);
extern void AConfiguration_getLanguage(AConfiguration *, char *);
extern void AConfiguration_getCountry(AConfiguration *, char *);
extern void AConfiguration_setOrientation(AConfiguration *, int32_t);

int main(void)
{
    struct AssetManager *manager = AssetManager_new();
    AConfiguration *first = AConfiguration_new(), *second = AConfiguration_new();
    assert(manager != NULL && first != NULL && second != NULL);
    struct ResTable_config config = {
        .size = sizeof(config), .density = 160, .orientation = 2,
        .screenWidthDp = 800, .screenHeightDp = 600, .smallestScreenWidthDp = 600,
        .sdkVersion = 34, .screenLayout = 3, .inputFlags = 2 << 2,
        .language = {'e', 'n'}, .country = {'G', 'B'},
    };
    AssetManager_lock(manager);
    AssetManager_setConfiguration(manager, &config);
    AssetManager_unlock(manager);
    AConfiguration_fromAssetManager(first, manager);
    assert(AConfiguration_getDensity(first) == 160);
    assert(AConfiguration_getScreenWidthDp(first) == 800);
    assert(AConfiguration_getScreenHeightDp(first) == 600);
    assert(AConfiguration_getSmallestScreenWidthDp(first) == 600);
    assert(AConfiguration_getSdkVersion(first) == 34);
    assert(AConfiguration_getScreenSize(first) == 3 && AConfiguration_getNavHidden(first) == 2);
    char language[2], country[2];
    AConfiguration_getLanguage(first, language);
    AConfiguration_getCountry(first, country);
    assert(memcmp(language, "en", 2) == 0 && memcmp(country, "GB", 2) == 0);
    config.screenWidthDp = 1024;
    config.screenHeightDp = 768;
    config.density = 240;
    AssetManager_lock(manager);
    AssetManager_setConfiguration(manager, &config);
    AssetManager_unlock(manager);
    AConfiguration_fromAssetManager(second, manager);
    assert(AConfiguration_getScreenWidthDp(first) == 800); // owned snapshot
    assert(AConfiguration_getScreenWidthDp(second) == 1024);
    assert(AConfiguration_getScreenHeightDp(second) == 768 && AConfiguration_getDensity(second) == 240);
    assert(AConfiguration_diff(first, second) != 0);
    AConfiguration_copy(first, second);
    assert(AConfiguration_diff(first, second) == 0 && AConfiguration_match(first, second));
    AConfiguration_setOrientation(first, 1);
    assert(!AConfiguration_match(first, second));
    AConfiguration_delete(first);
    AConfiguration_delete(second);
    puts("ATL-CONFIGURATION-PASS snapshot=asset-manager owned-copy=verified matching=androidfw");
    return 0;
}
