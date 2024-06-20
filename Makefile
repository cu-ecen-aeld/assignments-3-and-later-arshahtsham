CC = gcc
CFLAGS = -Wall -Werror -g
TARGET = writer
SRC = finder-app/writer.c

.PHONY: all clean cross-compile

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f $(TARGET) *.o

# Cross-compilation support
CROSS_COMPILE ?=
CC = $(CROSS_COMPILE)gcc

cross-compile:
	$(MAKE) all CROSS_COMPILE=$(CROSS_COMPILE)

