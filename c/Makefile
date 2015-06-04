CC=gcc
CFLAGS=-I. --std=c99
DEPS=sod.h client.h server.h
OBJ=sod.o client.o server.o
LDFLAGS=-L/usr/lib
LDLIBS=-lsqlite3 -lpcre

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

sod: $(OBJ)
	$(CC) -o $@ $(OBJ) $(CFLAGS) $(LDFLAGS) $(LDLIBS)
	rm -f *.o

clean:
	rm -f *.o sod

