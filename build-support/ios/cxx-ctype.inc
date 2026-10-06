// Darwin's public ctype_base ABI: uint32_t masks and _CTYPE_* bit values.
// libc++'s generated ASCII rune table remains portable; only its representation
// changes. Musl's wide-character functions still provide character conversion.
#if defined(VINIX_IOS_CXX_ABI)
  typedef unsigned int mask;
  static const mask space = 0x4000;
  static const mask print = 0x40000;
  static const mask cntrl = 0x200;
  static const mask upper = 0x8000;
  static const mask lower = 0x1000;
  static const mask alpha = 0x100;
  static const mask digit = 0x400;
  static const mask punct = 0x2000;
  static const mask xdigit = 0x10000;
  static const mask blank = 0x20000;
  static const mask __regex_word = 0x80;
#elif defined(_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE)
