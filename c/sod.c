/* FILENAME: sod.c
 *
 * DESCRIPTION:
 *  Main SOD code - option handling, etc.
 */

#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>
#include <errno.h>
#include <string.h>
#include <stdarg.h>
#include <time.h>
#include <signal.h>

#include "client.h"
#include "server.h"

char  verbose = 0;
float delay   = 0.0;
static FILE *log;

void sod_help(char *name) {
    printf("Usage: %s -[vscd] ADDR\n"
            "  -h\tThis help\n"
            "  -s\tRun in server mode, provide listen address\n"
            "  -c\tRun in client mode, provide server address\n"
            "  -v\tIncrease verbosity\n"
            "  -d\tSet delay between scans in seconds\n"
            "  -l\tSpecify a log file (default stdout)\n",
            name);
}

/* Function: _s_log
 * ---------------
 *  Log to a file or stdout
 *
 *  level: 'E' for error, 'I' for info, 'D' for debug (verbose)
 *  msg:   Message to log
 *
 *  Returns: value of fprintf, or 1 if message was ignored
 */
int _s_log(char level, const char *msg, ...) {
    va_list arg;
    char fmt[1024];
    time_t t = time(NULL);
    char *ts = ctime(&t);
    ts[strlen(ts)-1] = 0;

    if (level != 'D' || verbose) {
        va_start(arg, msg);
        vsnprintf(fmt, 1023, msg, arg);
        va_end(arg);
        return fprintf(log, "%c:[%s] %s", level, ts, fmt);
    }
    else
        return 1;
}

/* Function: log_close
 * -------------------
 *  Close the log file for shutdown
 */
void log_close(void) {
    fclose(log);
}

int main(int argc, char **argv) {
    char c;
    char *end;
    char *client = NULL;
    char *server = NULL;
    log = stdout;

    while ((c = getopt (argc, argv, "hvs:c:d:l:")) != -1) {
        switch (c) {
            case 'h':
                sod_help(argv[0]);
                return 0;
            case 'v':
                verbose = 1;
                break;
            case 's':
                server = optarg;
                break;
            case 'c':
                client = optarg;
                break;
            case 'd':
                delay = strtof(optarg, &end);
                if (*end != 0 || errno != 0 || delay < 0) {
                    fprintf(stderr,
                            "Invalid argument to -d. Give a float > 0.\n");
                    return 1;
                }
                break;
            case 'l':
                log = fopen(optarg, "a");
                if (!log) {
                    perror(optarg);
                    return 1;
                }
                _s_log('I', "Log file opened.");
                break;
            case '?':
                fprintf(stderr,
                        "Unknown option: %c\n",
                        optopt);
                return 1;
            default:
                abort();
        }
    }

    if (client) {
        //signal(SIGINT, client_quit);
        return sod_client(client);
    }
    else if (server) {
        signal(SIGINT, server_quit);
        signal(SIGTERM, server_quit);
        return sod_server(server);
    }

    printf("Must have either -s or -c.\n");
    return 1;
}
