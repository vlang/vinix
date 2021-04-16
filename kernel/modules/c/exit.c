void exit(int exit_code) {
    (void)exit_code;
    lib__kpanic(char_vstring("exit is a stub"));
    __builtin_unreachable();
}
