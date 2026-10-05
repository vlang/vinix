#include <jni.h>

JNIEXPORT jint JNICALL Java_org_vinix_tests_AndroidSplitApkProbe_nativeSentinel(JNIEnv *env, jclass cls)
{
    (void)env;
    (void)cls;
    return 0xA64;
}
