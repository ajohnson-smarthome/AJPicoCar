CC = cc
CFLAGS = -I../main -Wall -Wextra -Werror -std=c11
LDLIBS = -lm

all: test_mixer test_motors

test_mixer: test_mixer.c ../main/mixer.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test_motors: test_motors.c ../main/motors.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

run: all
	./test_mixer && ./test_motors

clean:
	rm -f test_mixer test_motors
