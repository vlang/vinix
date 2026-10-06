// SPDX-License-Identifier: GPL-2.0-or-later
#include <memory>
#include <regex>
#include <sstream>
#include <string>
extern "C" int puts(const char *);

static std::string global("a native iOS C++ constructor with a heap-backed string");
static std::string destructor_marker;

struct Lifetime {
    ~Lifetime() {
        if (destructor_marker == "finished") puts("IOS-CXX: destructor");
    }
} lifetime;

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
    destructor_marker = "finished";
    puts("IOS-CXX: native strings, streams, regex and shared ownership");
    return 0;
}
