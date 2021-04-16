void exit(int exit_code) {
    (void)exit_code;
    kpanic("exit is a stub");
    for (;;);
}
