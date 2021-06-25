void exit(int exit_code) {
    (void)exit_code;
    lib__kpanic("Kernel has called exit()");
    __builtin_unreachable();
}
