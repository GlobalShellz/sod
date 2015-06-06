/* FILENAME: server.c
 *
 * DESCRIPTION:
 *  SOD master/server
 *  Manages the SOD databasae, gives clients subnets to scan, etc.
 */

#define _DEFAULT_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <sys/epoll.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <pcre.h>
#include <stdint.h>

#include "sod.h"

#define MAXEVENTS 64

typedef struct cdata {
    char receiving; // currently receiving results
    uint8_t active[3]; // active subnet
    char *data;     // result buffer
    int datalen;    // size of data buffer
    char ip[46];    // client IP string
} cdata;

// Array of client data where fd-3 is the index
cdata clients[64];
// Database connection
static sqlite3 *db;
// Client response validation regex
pcre *re;

int handle(int client, char *buf);

/* Function: sod_server
 * --------------------
 *  Main server function incl. epoll event loop
 *
 *  addr: Listen address (IPv4 address string)
 */
int sod_server(char *addr) {
    int sfd;
    int efd;
    int flags;
    int client_sock;
    int c;
    int read_size;
    int erroffset;
    struct sockaddr_in server, client;
    struct in_addr *listen_addr = malloc(sizeof(struct in_addr));
    struct epoll_event event;
    struct epoll_event *events;
    const char *error;
    char client_addr[46]; // 45 is max length of an ipv6 address (with tunnel syntax)
    char buf[128] = {0}; // client command buffer

    if (sqlite3_open("sod.db", &db)) {
        s_log('E', "Cannot open database: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return EXIT_FAILURE;
    }

    re = pcre_compile("^"
            "(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})\\s+" // IPv4 address
            "(\\d+)\\s+"                                      // DNS response size
            "(\\d)$",                                         // Boolean (single-byte) recursion flag
            0,
            &error, &erroffset,
            NULL);

    if (inet_pton(AF_INET, addr, &(server.sin_addr)) <= 0) {
        s_log('E', "inet_pton error: %s", strerror(errno));
        return EXIT_FAILURE;
    }

    s_log('D', "Starting server on '%s'", addr);
    sfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sfd == -1) {
        s_log('E', "Unable to create socket: %s", strerror(errno));
        return EXIT_FAILURE;
    }

    server.sin_family = AF_INET;
    server.sin_port = htons(1027);

    if (bind(sfd, (struct sockaddr *)&server, sizeof(server)) < 0) {
        s_log('E', "Bind failed: %s", strerror(errno));
        return EXIT_FAILURE;
    }

    s_log('I', "Listening on %s:%d", addr, ntohs(server.sin_port));

    flags = fcntl(sfd, F_GETFL, 0);
    if (flags == -1) {
        s_log('E', "fcntl: %s", strerror(errno));
        return EXIT_FAILURE;
    }
    flags |= O_NONBLOCK;
    if (fcntl(sfd, F_SETFL, flags) == -1) {
        s_log('E', "fcntl: %s", strerror(errno));
        return EXIT_FAILURE;
    }

    if (listen(sfd, SOMAXCONN) == -1) {
        s_log('E', "listen: %s", strerror(errno));
        return EXIT_FAILURE;
    }

    efd = epoll_create1(0);
    event.data.fd = sfd;
    event.events = EPOLLIN | EPOLLET;
    epoll_ctl(efd, EPOLL_CTL_ADD, sfd, &event);

    events = calloc(MAXEVENTS, sizeof(event));

    c = sizeof(struct sockaddr_in);

    s_log('D', "Entering event loop");
    while (1) {
        int n = epoll_wait(efd, events, MAXEVENTS, -1);

        if (n == -1) {
            s_log('E', "epoll_wait: %s", strerror(errno));
            return EXIT_FAILURE;
        }

        for (int i=0; i<n; i++) {
            if ((events[i].events & EPOLLERR) ||
                (events[i].events & EPOLLHUP) ||
                (!(events[i].events & EPOLLIN)))
               {
                   // Error condition
                   s_log('E', "epoll error, closing fd %d", events[i].data.fd);
                   close(events[i].data.fd);
                   continue;
               }

            else if (sfd == events[i].data.fd) {
                // Incoming connection(s)
                while (1) {
                    client_sock = accept(sfd, (struct sockaddr *)&client, (socklen_t *)&c);
                    if (client_sock == -1) {
                        if (errno != EAGAIN && errno != EWOULDBLOCK)
                            s_log('D', "accept error: %s", strerror(errno));
                        break;
                    }

                    inet_ntop(AF_INET, &(client.sin_addr), client_addr, 45);
                    s_log('I', "Connection accepted from %s -> fd:%d", client_addr, sfd);
                    // TODO: This is copied from above. Make a function, idiot.
                    flags = fcntl(client_sock, F_GETFL, 0);
                    if (flags == -1) {
                        s_log('E', "fcntl: %s", strerror(errno));
                        return EXIT_FAILURE;
                    }
                    flags |= O_NONBLOCK;
                    if (fcntl(client_sock, F_SETFL, flags) == -1) {
                        s_log('E', "fcntl: %s", strerror(errno));
                        return EXIT_FAILURE;
                    }

                    event.data.fd = client_sock;
                    event.events = EPOLLIN | EPOLLET;
                    epoll_ctl(efd, EPOLL_CTL_ADD, client_sock, &event);

                    strncat(clients[client_sock-3].ip, client_addr, 45);
                }
                continue;
            }
            else {
                // We have some data to read
                int done = 0;

                while (1) {
                    int count = read(events[i].data.fd, buf, 127);
                    if (count == -1) {
                        if (errno != EAGAIN)
                            done = 1;
                        break;
                    }
                    else if (count == 0) { // Connection closed
                        done = 1;
                        s_log('I', "Client %s|%d disconnected", clients[events[i].data.fd-3].ip, events[i].data.fd);
                        break;
                    }

                    handle(events[i].data.fd, buf);
                    // echo
                    //write(events[i].data.fd, buf, count);
                    memset(buf, '\0', 128);
                }
                if (done) {
                    s_log('D', "Closing fd %d", events[i].data.fd);
                    memset(&(clients[events[i].data.fd-3]), 0, sizeof(cdata));
                    close(events[i].data.fd);
                }
            }
        }
    }


    free(events);
    close(sfd);

    return EXIT_SUCCESS;
}

/* Function: next_target
 * ---------------------
 *  Check for and return a previously missed subnet, or generate
 *  the next one in line. Keeps the database up to date.
 *
 *  ip: char[3] allocated for the result
 *
 *  Returns: 1 on success, 0 on failure
 */
int next_target(uint8_t *ip) {
    int c;
    sqlite3_stmt *res;

    c = sqlite3_prepare_v2(db,
            "SELECT a, b, c, id FROM missed LIMIT 1",
            35, // length of above statement including null
            &res, NULL);
    if (c != SQLITE_OK) {
        s_log('E', "SQLite error %d", c);
        return 0;
    }

    if (sqlite3_step(res) == SQLITE_ROW) {
        ip[0] = (uint8_t)sqlite3_column_int(res, 0);
        ip[1] = (uint8_t)sqlite3_column_int(res, 1);
        ip[2] = (uint8_t)sqlite3_column_int(res, 2);
        c = sqlite3_column_int(res, 3);
        sqlite3_finalize(res);
        sqlite3_prepare_v2(db,
                "DELETE FROM missed WHERE id=?",
                30, &res, NULL);
        sqlite3_bind_int(res, 1, c);
        sqlite3_step(res);
        sqlite3_finalize(res);
        return 1;
    }
    else
        sqlite3_finalize(res);

    c = sqlite3_prepare_v2(db,
            "SELECT a, b, c FROM track WHERE id=1",
            37, &res, NULL);
    if (c != SQLITE_OK) {
        s_log('E', "SQLite error %d", c);
        return 0;
    }

    if (sqlite3_step(res) == SQLITE_ROW) {
        ip[0] = (uint8_t)sqlite3_column_int(res, 0);
        ip[1] = (uint8_t)sqlite3_column_int(res, 1);
        ip[2] = (uint8_t)sqlite3_column_int(res, 2);
        sqlite3_finalize(res);

        if (ip[1] > 254) {
            ip[0]++;
            ip[1] = 0;
        }
        else if (ip[2] > 254) {
            ip[1]++;
            ip[2] = 0;
        }
        else {
            ip[2]++;
        }

        if (ip[0] > 223) // >223 is reserved for multicast
            return 0;    // TODO: Better end-of-internet handling - maybe
                         // restart from the beginning?

        // TODO: Check for subnet reservations
        sqlite3_prepare_v2(db,
                "UPDATE track SET a=?, b=?, c=? WHERE id=1",
                43, &res, NULL);
        sqlite3_bind_int(res, 1, ip[0]);
        sqlite3_bind_int(res, 2, ip[1]);
        sqlite3_bind_int(res, 3, ip[2]);
        sqlite3_step(res);
        sqlite3_finalize(res);
        return 1;
    }

    sqlite3_finalize(res);
    return 0;
}


/* Function: handle
 * ----------------
 *  Handle all input from clients
 *
 *  client: File descriptor for client connection
 *  buf: 128-byte data buffer of client input
 */
int handle(int client, char *buf) {
    int l = strlen(buf);
    int dl = 0;
    char *line;
    int ovector[12];
    int rc;

    char *sip;
    uint8_t ip[4];
    int size;
    char recursive;
    sqlite3_stmt *res = NULL;

    // Add input to the client's data buffer if in receiving mode
    if (clients[client-3].receiving && (buf[0] != '.' || l > 3)) {
        // If buffer is too small, grow by 1024
        if (clients[client-3].datalen <= (strlen(clients[client-3].data) + l)) {
            // TODO: Check for allocation errors!
            clients[client-3].datalen += 1024*sizeof(char);
            clients[client-3].data = realloc(clients[client-3].data, clients[client-3].datalen);
        }
        strncat(clients[client-3].data, buf, l);
        return 0;
    }

    // Kill the CRLF
    buf[l-2]=0;
    l -= 2;

    s_log('D', "Received from client %s|%d: [%s]", clients[client-3].ip, client, buf);

    /* READY command
     * Client is ready to receive a subnet target. Fetch a previously missed
     * target, or generate the next in line.
     */
    if (strncmp(buf, "READY", l) == 0) {
        // TODO: Generate this sensibly, i.e. next_target()
        if(!next_target(ip)) {
            s_log('E', "Error generating next target");
            write(client, "ERROR: Unable to generate target\r\n", 34);
            return 0;
        }
        clients[client-3].active[0] = ip[0];
        clients[client-3].active[1] = ip[1];
        clients[client-3].active[2] = ip[2];
        dprintf(client, "SCAN %d.%d.%d.0/24\r\n", ip[0], ip[1], ip[2]);
    }

    /* DONE command
     * Client completed a subnet scan, and is about to send results.
     * Switch to data receiving mode and allocate the client's data buffer.
     */
    else if (strncmp(buf, "DONE", l) == 0) {
        clients[client-3].receiving = 1;
        clients[client-3].data = malloc(1024*sizeof(char));
        clients[client-3].datalen = 1024*sizeof(char);
        s_log('D', "Ready to receive data from %s|%d", clients[client-3].ip, client);
    }

    /* NONE command
     * Client completed a subnet scan, and has no results to report.
     */
    else if (strncmp(buf, "NONE", l) == 0) {
        write(client, "THANKS\r\n", 8);
        memset(clients[client-3].active, 0, 3);
    }

    /* DOT (.) command
     * Signifies end of data. Switch back to command mode and process
     * the client's data buffer.
     */
    else if (buf[0] == '.' && l == 1 && clients[client-3].receiving) {
        clients[client-3].receiving = 0;
        dl = strlen(clients[client-3].data);
        if (dl > 0) {
            s_log('D', "received %d bytes (%d buffer):", dl, clients[client-3].datalen);
            for (line = strtok(clients[client-3].data, "\r\n"); line; line = strtok(NULL, "\r\n")) {
                rc = pcre_exec(re,
                        NULL,
                        line,
                        strlen(line),
                        0, 0,
                        ovector,
                        12);
                if (rc < 0) { // Not valid; skip
                    s_log('D', "Invalid data line from %s|%d: [%s]",
                            clients[client-3].ip, client, line);
                    continue;
                }
                // null between captured groups to use them separately
                line[ovector[3]] = 0; // ip
                line[ovector[5]] = 0; // size
                line[ovector[7]] = 0; // recursive
                for (char *sip = line+ovector[2], i=0;
                        sip != NULL && i<4;
                        ip[i++]=atoi(strsep(&sip, ".")));
                size = atoi(line+ovector[4]);
                recursive = atoi(line+ovector[6]);
                s_log('D', "ip: %d.%d.%d.%d, size: %d, recursive: %d",
                        ip[0],ip[1],ip[2],ip[3], size, recursive);

                // FIXME: Retain `created` column with another embedded select
                sqlite3_prepare_v2(db,
                        "INSERT OR REPLACE INTO ips (id, a, b, c, d, open,"
                        " recursive, size) VALUES ((SELECT id FROM ips"
                        " WHERE a=:a AND b=:b AND c=:c AND d=:d), :a, :b, :c,"
                        " :d, :open, :rec, :size)",
                        171, &res, NULL);
                sqlite3_bind_int(res, 1, ip[0]);
                sqlite3_bind_int(res, 2, ip[1]);
                sqlite3_bind_int(res, 3, ip[2]);
                sqlite3_bind_int(res, 4, ip[3]);
                sqlite3_bind_int(res, 5, (size > 25) || recursive ? 1 : 0);
                sqlite3_bind_int(res, 6, recursive);
                sqlite3_bind_int(res, 7, size);
                sqlite3_step(res);
                sqlite3_finalize(res);
            }
        }
        write(client, "THANKS\r\n", 8);
        memset(clients[client-3].active, 0, 3);
        clients[client-3].data = 0;
        free(clients[client-3].data);
    }

    /* ERROR report
     * Client encountered an error processing a server request, and was unable
     * to complete its active scan. Report the error, and save the active
     * subnet for later.
     */
    else if (l > 6 && strncmp(buf, "ERROR:", 6) == 0) {
        s_log('E', "Client %s|%d reported error: %s", clients[client-3].ip, client, buf+7);
        sqlite3_prepare_v2(db,
                "INSERT INTO missed VALUES (NULL, ?, ?, ?, 0, NULL)",
                51, &res, NULL);
        sqlite3_bind_int(res, 1, clients[client-3].active[0]);
        sqlite3_bind_int(res, 2, clients[client-3].active[1]);
        sqlite3_bind_int(res, 3, clients[client-3].active[2]);
        sqlite3_step(res);
        sqlite3_finalize(res);
        memset(clients[client-3].active, 0, 3);
    }

    /* LISTCLIENTS command
     * When called from IPv4 localhost, report the addresses of all connected
     * clients.
     */
    else if (strncmp(buf, "LISTCLIENTS", l) == 0
            && strncmp(clients[client-3].ip, "127.0.0.1", 9) == 0) {
        for (int i=0; i<64; i++) {
            if(clients[i].ip[0])
                dprintf(client, "%s\r\n", clients[i].ip);
        }
        write(client, ".\r\n", 3);
    }

    /* UNKNOWN
     * Any unknown input in command mode is rejected with the message
     * 'UNKNOWN'.
     */
    else {
        write(client, "UNKNOWN\r\n", 9);
    }
}

/* Function: server_quit
 * ---------------------
 *  Safely stop the server, saving to database first.
 *
 *  sig: signal number, if called as a signal handler
 */
void server_quit(int sig) {
    sqlite3_stmt *res = NULL;

    s_log('I', "Shutting down due to signal %d.", sig);
    for (int i=0; i<64; i++) {
        if (clients[i].ip[0]) {
            sqlite3_finalize(res);
            sqlite3_prepare_v2(db,
                    "INSERT INTO missed VALUES (NULL, ?, ?, ?, 0, NULL)",
                    51, &res, NULL);
            sqlite3_bind_int(res, 1, clients[i].active[0]);
            sqlite3_bind_int(res, 2, clients[i].active[1]);
            sqlite3_bind_int(res, 3, clients[i].active[2]);
            sqlite3_step(res);
        }
    }
    sqlite3_close(db);
    log_close();
    exit(0);
}
