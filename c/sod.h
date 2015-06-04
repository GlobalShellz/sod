extern int _s_log(char level, const char *msg, ...);
#define s_log(level, msg, ...) _s_log(level, msg"\n", ##__VA_ARGS__)
