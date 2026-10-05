/* Distinct 4 KiB x86 code/data pages in one 16 KiB native Vinix page. */
SECTIONS
{
    .smc_code 0x410000 : { *(.smc_code) }
    .smc_data 0x412000 : { *(.smc_data) }
}
INSERT BEFORE .text;
