/*
 *
 * Scanner for Open DNSs - client
 *
 * brabo 2013
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <netdb.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <arpa/inet.h>

#define PORT "53" // the port client will be connecting to 

#define MAXDATASIZE 500 // max number of bytes we can get at once 

// get sockaddr, IPv4 or IPv6:
void *get_in_addr(struct sockaddr *sa)
{
	if (sa->sa_family == AF_INET) {
		return &(((struct sockaddr_in*)sa)->sin_addr);
	}
	return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

int main(int argc, char *argv[])
{
	int sockfd, numbytes;  
	char buf[MAXDATASIZE];
//	int buf;
	struct addrinfo hints, *servinfo, *p;
	int rv;
	char s[INET6_ADDRSTRLEN];

	if (argc != 2) {
		fprintf(stderr,"usage: client hostname\n");
		exit(1);
	}

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;

	if ((rv = getaddrinfo(argv[1], PORT, &hints, &servinfo)) != 0) {
		fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(rv));
		return 1;
	}

	// loop through all the results and connect to the first we can
	for(p = servinfo; p != NULL; p = p->ai_next) {
		if ((sockfd = socket(p->ai_family, p->ai_socktype,
			p->ai_protocol)) == -1) {
				perror("client: socket");
				continue;
		}
		if (connect(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
			close(sockfd);
			perror("client: connect");
			continue;
		}

		break;
	}

	if (p == NULL) {
		fprintf(stderr, "client: failed to connect\n");
		return 2;
	}

	inet_ntop(p->ai_family, get_in_addr((struct sockaddr *)p->ai_addr),
		s, sizeof s);
	printf("client: connecting to %s\n", s);

	freeaddrinfo(servinfo); // all done with this structure

//	if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
//		perror("recv");
//		exit(1);
//	}

	char sc[] = "\x00\x25\x64\xe8\xe7\x8e\x5c\x35\x3b\x7d\x57\x46\x08\x00\x45\x00\x00\x34\x33\xb7\x00\x00\x2e\x06\x87\x8f\x08\x08\x08\x08\xc0\xa8\x00\xc6\x00\x35\x80\x18\x20\xbc\x4f\x43\xf8\x9d\xad\x85\x80\x10\x03\xcf\xa1\xb4\x00\x00\x01\x01\x08\x0a\x2b\x02\x1c\x0a\x00\x6c\x21\xd3";
	char SYN[] = "\x5c\x35\x3b\x7d\x57\x46\x00\x25\x64\xe8\xe7\x8e\x08\x00\x45\x00\x00\x3c\x8c\xa7\x40\x00\x40\x06\xdc\x96\xc0\xa8\x00\xc6\x08\x08\x08\x08\x80\x18\x00\x35\xf8\x9d\xad\x69\x00\x00\x00\x00\xa0\x02\x39\x08\xd1\xac\x00\x00\x02\x04\x05\xb4\x04\x02\x08\x0a\x00\x6c\x21\xce\x00\x00\x00\x00\x01\x03\x03\x06";
	char ACK[] = "\x5c\x35\x3b\x7d\x57\x46\x00\x25\x64\xe8\xe7\x8e\x08\x00\x45\x00\x00\x34\x8c\xa8\x40\x00\x40\x06\xdc\x9d\xc0\xa8\x00\xc6\x08\x08\x08\x08\x80\x18\x00\x35\xf8\x9d\xad\x6a\x20\xbc\x4f\x43\x80\x10\x00\xe5\xd1\xa4\x00\x00\x01\x01\x08\x0a\x00\x6c\x21\xd3\x2b\x02\x1b\xf3";

//	char QUERY[] = "\x5c\x35\x3b\x7d\x57\x46\x00\x25\x64\xe8\xe7\x8e\x08\x00\x45\x00\x00\x4f\x8c\xa9\x40\x00\x40\x06\xdc\x81\xc0\xa8\x00\xc6\x08\x08\x08\x08\x80\x18\x00\x35\xf8\x9d\xad\x6a\x20\xbc\x4f\x43\x80\x18\x00\xe5\xd1\xbf\x00\x00\x01\x01\x08\x0a\x00\x6c\x21\xd3\x2b\x02\x1b\xf3\x00\x19
	char QUERY[] = "\xa6\x22\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x03\x69\x73\x63\x03\x6f\x72\x67\x00\x00\xff\x00\x01";


	send(sockfd, SYN, strlen(SYN), 0);
	sleep(1);
	send(sockfd, ACK, strlen(ACK), 0);
	send(sockfd, QUERY, strlen(QUERY), 0);
//	if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
//		sleep(5);
//	}
//	if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
//		sleep(5);
//	}
//	if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
//		sleep(5);
//	}
//	if ((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == -1) {
//		exit(5);
//	}
	int retries = 10;
	while(1) {
		if((numbytes = recv(sockfd, buf, MAXDATASIZE-1, 0)) == 0 ) {
//			exit(0);
			if ((retries = 0)) {
				printf("No reply received.. aborting!\n");
				exit(10);
			} else {
				sleep(1);
				retries--;
				continue;
			}
		}
		printf("Received data :  %s\n\n", buf);
	}


	close(sockfd);

	return 0;
}

