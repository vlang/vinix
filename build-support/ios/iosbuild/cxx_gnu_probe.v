// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

pub const gnu_cxx_probe_words = 48
pub const gnu_cxx_probe_bytes = 192

// A generated binding adapter for public C++ types that V cannot instantiate.
// It reports observations through plain buffers; the runtime fixture owns all
// expected-value and canary assertions. This object is never part of the app
// runtime libraries. Its generated C++ file belongs with external evidence.
pub fn gnu_cxx_abi_probe_source() string {
	return '#include <cwchar>
#include <cstdio>
#include <cstring>
#include <cstddef>
#include <cstdint>
#include <locale>
#include <sstream>
#include <string>

extern "C" int vinix_ios_gnu_cxx_abi_probe(std::uint64_t* result,
    std::uint64_t count, unsigned char* bytes, std::uint64_t capacity) {
  if (!result || !bytes || count != 48 || capacity != 192) return 2;
  std::memset(result, 0, 48 * sizeof(*result));
  std::memset(bytes, 0, 192);
  try {
    const std::uint64_t canary = UINT64_C(0x129ae174ff3682cd);
    struct State { std::uint64_t before; std::mbstate_t state; std::uint64_t after; };
    struct Position { std::uint64_t before; std::fpos_t position; std::uint64_t after; };
    State guarded{canary, {}, canary};
    Position position{canary, {}, canary};
    result[0] = sizeof(std::mbstate_t);
    result[1] = alignof(std::mbstate_t);
    result[2] = sizeof(std::fpos_t);
    result[3] = sizeof(State);
    result[4] = offsetof(State, state);
    result[5] = sizeof(Position);
    if (sizeof(State) != 144 || sizeof(Position) != 32 || sizeof(std::mbstate_t) != 128) return 4;
    // Only the native eight-byte prefix belongs to glibc. Check that the
    // opaque Apple tail remains untouched by every conversion below.
    std::memset(reinterpret_cast<unsigned char*>(&guarded.state) + 8, 0xa5, 120);
    wchar_t wide[8]{};
    wchar_t scalar{};
    char encoded[16]{};
    result[6] = std::mbrtowc(&scalar, "Z", 1, &guarded.state);
    result[7] = scalar;
    result[8] = std::wcrtomb(encoded, L\'Q\', &guarded.state);
    result[9] = static_cast<unsigned char>(encoded[0]);
    const char* input = "ABC";
    result[10] = std::mbsrtowcs(wide, &input, 8, &guarded.state);
    result[11] = input == nullptr;
    result[12] = wide[0]; result[13] = wide[1]; result[14] = wide[2];
    const wchar_t* wide_input = L"XYZ";
    result[15] = std::wcsrtombs(encoded, &wide_input, sizeof(encoded), &guarded.state);
    result[16] = wide_input == nullptr;
    result[17] = std::mbrtowc(&scalar, "N", 1, nullptr);
    result[18] = scalar;
    result[19] = std::wcrtomb(encoded, L\'R\', nullptr);
    result[20] = static_cast<unsigned char>(encoded[0]);
    input = "hi";
    result[21] = std::mbsrtowcs(wide, &input, 8, nullptr);
    result[22] = input == nullptr;
    result[23] = wide[0]; result[24] = wide[1];
    result[25] = std::mbsinit(&guarded.state);
    result[26] = std::mbrlen("K", 1, &guarded.state);

    std::wstringstream stream;
    stream << L"native " << (UINT64_C(1) << 40);
    result[27] = stream.str().size();
    std::wstring word;
    unsigned long long number{};
    stream >> word >> number;
    result[28] = number;
    result[29] = word.size();
    result[30] = word == L"native";

    const auto& facet = std::use_facet<std::codecvt<wchar_t, char, std::mbstate_t>>(std::locale::classic());
    const char text[] = "cat";
    const char* next_input{};
    wchar_t* next_wide{};
    result[31] = facet.in(guarded.state, text, text + 3, next_input, wide, wide + 8, next_wide);
    result[32] = next_input - text;
    result[33] = next_wide - wide;
    result[34] = wide[0]; result[35] = wide[1]; result[36] = wide[2];
    const wchar_t* next_output{};
    char* next_encoded{};
    result[37] = facet.out(guarded.state, wide, wide + 3, next_output, encoded, encoded + sizeof(encoded), next_encoded);
    result[38] = next_output - wide;
    result[39] = next_encoded - encoded;

    char contents[] = "Zero";
    FILE* file = ::fmemopen(contents, 4, "r");
    if (!file) return 3;
    result[40] = std::fgetpos(file, &position.position);
    result[41] = std::fgetc(file);
    result[42] = std::fsetpos(file, &position.position);
    result[43] = std::fgetc(file);
    result[44] = std::fclose(file);
    result[45] = std::mbsinit(&guarded.state);
    result[46] = std::mbsinit(nullptr);
    result[47] = sizeof(__vinix_gnu_native_mbstate_t);
    std::memcpy(bytes, &guarded, sizeof(guarded));
    std::memcpy(bytes + 144, &position, sizeof(position));
    std::memcpy(bytes + 176, encoded, 3);
    return 0;
  } catch (...) {
    return 1;
  }
}
'
}

// Trigger actual downstream checks without encoding their expected outcomes.
// The V driver requires the valid result and marker, and independently checks
// the failing exit and diagnostic from each negative child process.
pub fn gnu_cxx_sanitizer_control_source() string {
	return '#include <cstdio>
#include <cstring>

struct VinixCxxControlBase {
  virtual ~VinixCxxControlBase() = default;
  virtual int read() const { return 17; }
};
struct VinixCxxControlOther {
  virtual ~VinixCxxControlOther() = default;
  virtual int read() const { return 23; }
};
extern "C" __attribute__((noinline)) int vinix_cxx_control_virtual(const VinixCxxControlBase* object) {
  return object->read();
}
extern "C" __attribute__((noinline)) int vinix_cxx_control_function(int value) {
  return value + 3;
}
extern "C" __attribute__((noinline)) void (*vinix_cxx_control_address())() {
  return reinterpret_cast<void (*)()>(&vinix_cxx_control_function);
}
int main(int argc, char** argv) {
  if (argc != 2) { std::fputs("expected valid, vptr or function mode\\n", stderr); return 64; }
  if (std::strcmp(argv[1], "valid") == 0) {
    VinixCxxControlBase object;
    auto function = reinterpret_cast<int (*)(int)>(vinix_cxx_control_address());
    int result = vinix_cxx_control_virtual(&object) + function(17);
    std::puts("IOS-CXX-SANITIZER-CONTROL: valid virtual and function calls");
    return result;
  }
  if (std::strcmp(argv[1], "vptr") == 0) {
    VinixCxxControlOther object;
    return vinix_cxx_control_virtual(reinterpret_cast<const VinixCxxControlBase*>(&object));
  }
  if (std::strcmp(argv[1], "function") == 0) {
    auto function = reinterpret_cast<int (*)(double)>(vinix_cxx_control_address());
    return function(1.0);
  }
  std::fputs("unknown sanitizer control mode\\n", stderr);
  return 64;
}
'
}
