#include <stdint.h>
#include <stddef.h>
#include <string>
#include <re2/re2.h>

// Fuzz the regex pattern itself: exercises re2's parser, compiler,
// NFA/DFA construction, and matching engine all in one input.
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    RE2::Options opts;
    opts.set_max_mem(1 << 20);  // 1 MB RE2 memory cap to avoid OOM
    opts.set_log_errors(false);

    std::string pattern(reinterpret_cast<const char *>(data), size);
    RE2 re(pattern, opts);
    if (re.ok()) {
        RE2::FullMatch("hello world 123", re);
        RE2::PartialMatch("test\ninput\t456", re);
    }
    return 0;
}
