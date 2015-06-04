#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <sys/epoll.h>
#include <fcntl.h>

#include "sod.h"

#define MAXEVENTS 64

typedef struct cdata {
    char receiving; // currently receiving results
    char active[3]; // active subnet
    char *data;     // result buffer
    int datalen;    // size of data buffer
    char ip[46];    // client IP string
} cdata;

// Array of client data where fd-3 is the index
cdata clients[64];

int handle(int client, char *buf);

int sod_server(char *addr) {
    int sfd;
    int efd;
    int flags;
    int client_sock;
    int c;
    int read_size;
    struct sockaddr_in server, client;
    struct in_addr *listen_addr = malloc(sizeof(struct in_addr));
    struct epoll_event event;
    struct epoll_event *events;
    char client_addr[46]; // 45 is max length of an ipv6 address (with tunnel syntax)
    char buf[128] = {0}; // client command buffer

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
            s_log('D', "event on fd: %d", events[i].data.fd);
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

int handle(int client, char *buf) {
    int l = strlen(buf);
    int dl = 0;

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
    if (strncmp(buf, "READY", l) == 0) {
        // TODO: Generate this sensibly, i.e. next_target()
        clients[client-3].active[0] = '\1';
        clients[client-3].active[1] = '\0';
        clients[client-3].active[2] = '\0';
        dprintf(client, "SCAN %s\r\n", "1.0.0.0/24");
    }
    else if (strncmp(buf, "DONE", l) == 0) {
        clients[client-3].receiving = 1;
        clients[client-3].data = malloc(1024*sizeof(char));
        clients[client-3].datalen = 1024*sizeof(char);
        s_log('D', "Ready to receive data from %s|%d", clients[client-3].ip, client);
    }
    else if (strncmp(buf, "NONE", l) == 0) {
        write(client, "THANKS\r\n", 8);
        memset(clients[client-3].active, 0, 3);
    }
    else if (buf[0] == '.' && l == 1) {
        clients[client-3].receiving = 0;
        dl = strlen(clients[client-3].data);
        if (dl > 0) {
            s_log('D', "received %d bytes (%d buffer):\n%s", dl, clients[client-3].datalen, clients[client-3].data);
            // Process data
        }
        write(client, "THANKS\r\n", 8);
        memset(clients[client-3].active, 0, 3);
        clients[client-3].data = 0;
        free(clients[client-3].data);
    }
    else if (l > 6 && strncmp(buf, "ERROR:", 6) == 0) {
        s_log('E', "Client %s|%d reported error: %s", clients[client-3].ip, client, buf+7);
    }
    else if (strncmp(buf, "LISTCLIENTS", l) == 0
            && strncmp(clients[client-3].ip, "127.0.0.1", 9) == 0) {
        for (int i=0; i<64; i++) {
            if(clients[i].ip[0])
                dprintf(client, "%s\r\n", clients[i].ip);
        }
        write(client, ".\r\n", 3);
    }
    else {
        write(client, "UNKNOWN\r\n", 9);
    }
}
