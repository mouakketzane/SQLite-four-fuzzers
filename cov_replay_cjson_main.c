#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        if (!f) continue;
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        rewind(f);
        if (sz > 0) {
            uint8_t *buf = (uint8_t *)malloc(sz);
            if (buf) {
                fread(buf, 1, sz, f);
                LLVMFuzzerTestOneInput(buf, sz);
                free(buf);
            }
        }
        fclose(f);
    }
    return 0;
}
