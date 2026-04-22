#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "cJSON.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char *buf = (char *)malloc(size + 1);
    if (!buf) return 0;
    memcpy(buf, data, size);
    buf[size] = '\0';

    cJSON *json = cJSON_Parse(buf);
    if (json) {
        char *printed = cJSON_PrintUnformatted(json);
        free(printed);
        cJSON_Delete(json);
    }

    free(buf);
    return 0;
}
