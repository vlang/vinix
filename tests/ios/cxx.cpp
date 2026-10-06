// SPDX-License-Identifier: GPL-2.0-or-later
#include <memory>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <regex>
#include <sstream>
#include <string>
extern "C" int puts(const char *);
extern "C" void dispatch_once_f(long *, void *, void (*)(void *));

static std::string global("a native iOS C++ constructor with a heap-backed string");
static std::string destructor_marker;

struct Lifetime {
    ~Lifetime() {
        if (destructor_marker == "finished") puts("IOS-CXX: destructor");
    }
} lifetime;

static std::mutex mutex;
static std::recursive_mutex recursive;
static std::condition_variable condition;
static std::once_flag once;
static int counter, once_count;
static bool ready;
static long dispatch_predicate;
static int dispatch_count;
static void dispatch_callback(void *context) { ++*static_cast<int *>(context); }

static void worker() {
    dispatch_once_f(&dispatch_predicate, &dispatch_count, dispatch_callback);
    std::call_once(once, [] { ++once_count; });
    std::lock_guard<std::recursive_mutex> outer(recursive);
    std::lock_guard<std::recursive_mutex> inner(recursive);
    std::unique_lock<std::mutex> guard(mutex);
    ++counter;
    if (counter == 8) { ready = true; condition.notify_one(); }
}

static int test_threads() {
    std::thread threads[8];
    for (auto &thread : threads) thread = std::thread(worker);
    {
        std::unique_lock<std::mutex> guard(mutex);
        if (!condition.wait_for(guard, std::chrono::seconds(5), [] { return ready; })) return 16;
    }
    for (auto &thread : threads) thread.join();
    if (counter != 8 || once_count != 1 || dispatch_count != 1 || dispatch_predicate != -1 || !mutex.try_lock()) return 17;
    mutex.unlock();
    return 0;
}

int main(int argc, char **) {
    if (argc > 1) throw 42; // Diagnose unsupported Mach-O unwinding explicitly.
    if (global != "a native iOS C++ constructor with a heap-backed string") return 10;
    std::string short_string("arm64");
    for (int i = 0; i < 100; i++) short_string.append(" Vinix");
    if (short_string.size() != 605 || short_string.find("Vinix") != 6) return 11;
    short_string.erase(5);
    if (short_string != "arm64") return 12;
    std::stringstream stream;
    stream << short_string << ' ' << 42;
    std::string text;
    int number = 0;
    stream >> text >> number;
    if (text != "arm64" || number != 42) return 13;
    std::regex expression("[a-z]+[0-9]+");
    if (!std::regex_match(text, expression)) return 14;
    auto shared = std::make_shared<std::string>(global);
    auto other = shared;
    if (other.use_count() != 2 || *other != global) return 15;
    if (int result = test_threads()) return result;
    puts("IOS-CXX: native pthread and C++ synchronization");
    destructor_marker = "finished";
    puts("IOS-CXX: native strings, streams, regex and shared ownership");
    return 0;
}
