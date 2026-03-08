#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "sqlite3.h"

#ifdef __cplusplus
extern "C"
#endif

// This is the connection between the fuzzer and target (sqlite)
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    sqlite3 *db;
    char *zErrMsg = 0;
    
    // Open a temporary in-memory database
    if (sqlite3_open(":memory:", &db) != SQLITE_OK) {
        return 0;
    }

    // Convert fuzzer data to a null-terminated SQL string
    char *sql = sqlite3_mprintf("%.*s", (int)size, data);

    // Execute the fuzzed SQL
    sqlite3_exec(db, sql, NULL, NULL, &zErrMsg);

    // Cleanup
    sqlite3_free(zErrMsg);
    sqlite3_free(sql);
    sqlite3_close(db);

    return 0;
}