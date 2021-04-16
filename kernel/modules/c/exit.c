void exit(int exit_code) {
    (void)exit_code;
    lib__kpanic(char_vstring("Execution terminated."));
    __builtin_unreachable();
}
