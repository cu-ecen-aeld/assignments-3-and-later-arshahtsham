CC = gcc
CFLAGS = -Wall -Werror -g
TARGET = writer
SRC = writer.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
    $(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f $(TARGET) *.o

