// SPDX-License-Identifier: GPL-2.0-or-later
// The same public-header fixture runs against the installed Mac reference and
// the Vinix iOS runtime. ELF mode additionally checks native exception helpers;
// catching exceptions through Mach-O frames is deliberately not claimed.
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cxxabi.h>
#include <future>
#include <iostream>
#include <memory>
#include <new>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

static_assert(sizeof(std::string) == 24 && sizeof(std::vector<int>) == 24);
static_assert(sizeof(std::random_device) == 4 && alignof(std::random_device) == 4);
static_assert(sizeof(std::promise<void>) == 8 && sizeof(std::future<void>) == 8);
static_assert(sizeof(std::weak_ptr<int>) == 16);
static_assert(sizeof(std::ostream) == 160 && sizeof(std::stringbuf) == 104);
static_assert(sizeof(std::stringstream) == 280 && sizeof(std::ostringstream) == 264);

#ifdef __APPLE__
#define ABI_NAME(name) "_" name
#else
#define ABI_NAME(name) name
#endif
#define STRING_NAME "_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE"
extern "C" {
void string_init(void *, const char *, size_t) __asm__(ABI_NAME(STRING_NAME "6__initEPKcm"));
void string_fill(void *, size_t, char) __asm__(ABI_NAME(STRING_NAME "6__initEmc"));
void string_grow(void *, size_t, size_t, size_t, size_t, size_t, size_t, const char *)
    __asm__(ABI_NAME(STRING_NAME "21__grow_by_and_replaceEmmmmmmPKc"));
void string_substring(void *, const void *, size_t, size_t, const void *)
    __asm__(ABI_NAME(STRING_NAME "C1ERKS5_mmRKS4_"));
void string_substring_base(void *, const void *, size_t, size_t, const void *)
    __asm__(ABI_NAME(STRING_NAME "C2ERKS5_mmRKS4_"));
void string_destroy_base(void *) __asm__(ABI_NAME(STRING_NAME "D2Ev"));
int string_compare(const void *, size_t, size_t, const char *, size_t)
    __asm__(ABI_NAME("_ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7compareEmmPKcm"));
void sort_int(int *, int *, const void *) __asm__(ABI_NAME("_ZNSt3__16__sortIRNS_6__lessIiiEEPiEEvT0_S5_T_"));
void sort_long(long *, long *, const void *) __asm__(ABI_NAME("_ZNSt3__16__sortIRNS_6__lessIllEEPlEEvT0_S5_T_"));
void sort_short(unsigned short *, unsigned short *, const void *)
    __asm__(ABI_NAME("_ZNSt3__16__sortIRNS_6__lessIttEEPtEEvT0_S5_T_"));
void vector_length(const void *) __asm__(ABI_NAME("_ZNKSt3__120__vector_base_commonILb1EE20__throw_length_errorEv"));
void vector_range(const void *) __asm__(ABI_NAME("_ZNKSt3__120__vector_base_commonILb1EE20__throw_out_of_rangeEv"));
[[noreturn]] void verbose_abort(const char *, ...) __asm__(ABI_NAME("_ZNSt3__122__libcpp_verbose_abortEPKcz"));
}

#define CHECK(expression) do { if (!(expression)) { \
    std::printf("IOS-CXX-EXTENDED: failed at line %d: %s\n", __LINE__, #expression); return 1; } } while (0)

static int strings() {
    const char binary[] = {'a', '\0', 'b', 'c'};
    std::string short_string;
    string_init(&short_string, binary, sizeof(binary));
    CHECK(short_string.size() == 4 && !std::memcmp(short_string.data(), binary, 4));
    CHECK(string_compare(&short_string, 1, 3, binary + 1, 3) == 0);
    CHECK(string_compare(&short_string, 1, 3, "\0bd", 3) < 0);
    std::string filled;
    string_fill(&filled, 100, 'x');
    CHECK(filled == std::string(100, 'x'));
    const std::string source("a heap-backed string to exercise both substring constructors");
    std::allocator<char> allocator;
    alignas(std::string) unsigned char storage[sizeof(std::string)];
    string_substring(storage, &source, 7, 31, &allocator);
    CHECK(*reinterpret_cast<std::string *>(storage) == source.substr(7, 31));
    string_destroy_base(storage);
    string_substring_base(storage, &source, 3, 5, &allocator);
    CHECK(*reinterpret_cast<std::string *>(storage) == source.substr(3, 5));
    string_destroy_base(storage);
    std::string grown("0123456789012345678901234567890123456789");
    const std::string insert(80, 'z');
    auto expected = grown;
    expected.replace(7, 3, insert);
    string_grow(&grown, grown.capacity(), 80, grown.size(), 7, 3, insert.size(), insert.data());
    CHECK(grown == expected && grown.data()[grown.size()] == '\0');
    // The helper must finish copying aliased source bytes before freeing the
    // old string buffer. This catches ABI/lifetime errors in legacy growth.
    expected.replace(10, 2, grown.substr(5, 12));
    string_grow(&grown, grown.capacity(), 32, grown.size(), 10, 2, 12, grown.data() + 5);
    CHECK(grown == expected && grown.data()[grown.size()] == '\0');
    CHECK(std::to_string(1099511627776L) == "1099511627776");
    return 0;
}

static int integer_sorts() {
    unsigned char comparator = 0;
    int integers[] = {123, 8, -7, 8, 0, -2147483647, 2147483647, 456};
    sort_int(integers + 1, integers + 7, &comparator);
    CHECK(integers[0] == 123 && integers[7] == 456 && std::is_sorted(integers + 1, integers + 7));
    long longs[] = {123, 1099511627776L, -1099511627776L, 0, 42, 42, 456};
    sort_long(longs + 1, longs + 6, &comparator);
    CHECK(longs[0] == 123 && longs[6] == 456 && std::is_sorted(longs + 1, longs + 6));
    unsigned short shorts[] = {123, 65535, 0, 32768, 1, 1, 456};
    sort_short(shorts + 1, shorts + 6, &comparator);
    CHECK(shorts[0] == 123 && shorts[6] == 456 && std::is_sorted(shorts + 1, shorts + 6));
    sort_int(integers + 1, integers + 1, &comparator);
    sort_short(shorts + 1, shorts + 2, &comparator);
    return 0;
}

static int futures_and_ownership() {
    std::promise<void> promises[8];
    std::future<void> futures[8];
    std::thread workers[8];
    for (int i = 0; i < 8; ++i) {
        futures[i] = promises[i].get_future();
        workers[i] = std::thread([&promises, i] { promises[i].set_value(); });
    }
    for (auto &future : futures) { future.wait(); future.get(); CHECK(!future.valid()); }
    for (auto &worker : workers) worker.join();
    auto owner = std::make_shared<std::string>(80, 'v');
    std::weak_ptr<std::string> weak(owner);
    { auto held = weak.lock(); CHECK(held && *held == *owner && held.use_count() == 2); }
    owner.reset();
    CHECK(weak.expired() && !weak.lock());
    std::ostringstream output;
    output << 1099511627776L << ':' << std::string(80, 'v');
    CHECK(output.str() == "1099511627776:" + std::string(80, 'v'));
    std::stringstream input(output.str());
    long value = 0;
    char separator = 0;
    input >> value >> separator;
    CHECK(value == 1099511627776L && separator == ':');
    std::cerr << "IOS-CXX-EXTENDED: long ostream " << value << '\n';
    int status = -1;
    char *demangled = abi::__cxa_demangle("_ZNSt3__19to_stringEl", nullptr, nullptr, &status);
    CHECK(demangled && status == 0 && !std::strcmp(demangled, "std::__1::to_string(long)"));
    std::free(demangled);
    std::bad_alloc allocation;
    CHECK(typeid(allocation) == typeid(std::bad_alloc));
    void (*volatile length_helper)(const void *) = vector_length;
    void (*volatile range_helper)(const void *) = vector_range;
    CHECK(length_helper != nullptr && range_helper != nullptr);
#if defined(IOS_CXX_NATIVE) || defined(IOS_CXX_REFERENCE)
    bool length = false, range = false;
    try { vector_length(nullptr); }
    catch (const std::length_error &error) { length = !std::strcmp(error.what(), "vector"); }
    try { vector_range(nullptr); }
    catch (const std::out_of_range &error) { range = !std::strcmp(error.what(), "vector"); }
    CHECK(length && range);
    puts("IOS-CXX-EXTENDED: native vector exception types and messages");
#endif
    return 0;
}

static int random_devices() {
#ifndef IOS_CXX_NATIVE
    for (const char *token : {"/dev/urandom", "/dev/random", "default", "unknown", "", "a long token that is not a filename or a supported Linux random device"}) {
        struct Guarded {
            uint32_t before;
            alignas(std::random_device) unsigned char bytes[sizeof(std::random_device)];
            uint32_t after;
        } guarded{0x01234567, {0x89, 0xab, 0xcd, 0xef}, 0xfedcba98};
        auto *device = new (guarded.bytes) std::random_device(token);
        CHECK(device->entropy() == 32.0);
        const auto first = (*device)();
        bool different = false;
        for (int i = 0; i < 128; ++i) if ((*device)() != first) different = true;
        CHECK(different);
        device->~random_device();
        const unsigned char unchanged[] = {0x89, 0xab, 0xcd, 0xef};
        CHECK(guarded.before == 0x01234567 && guarded.after == 0xfedcba98 &&
              !std::memcmp(guarded.bytes, unchanged, sizeof(unchanged)));
    }
#endif
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && !std::strcmp(argv[1], "abort")) {
        verbose_abort("IOS-CXX-ABORT: %s %d %ld %.3f %p\n", "stack", 17, 1099511627776L, 2.5, reinterpret_cast<void *>(0x1234));
    }
    if (int result = strings()) return result;
    if (int result = integer_sorts()) return result;
    if (int result = futures_and_ownership()) return result;
    if (int result = random_devices()) return result;
#ifdef IOS_CXX_NATIVE
    puts("IOS-CXX-EXTENDED: legacy strings, integer sorts, futures and weak ownership");
#else
    puts("IOS-CXX-EXTENDED: legacy strings, integer sorts, futures, weak ownership and Darwin entropy");
#endif
    return 0;
}
