void lib__kpanicc(char *message);

void exit(int exit_code) {
    (void)exit_code;
    lib__kpanicc("Execution terminated.");
    __builtin_unreachable();
}
