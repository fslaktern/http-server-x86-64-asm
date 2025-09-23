build:
	as -o server.o server.S && ld -o server server.o

run: build
	./server &
	ss -tlpn
	@echo -n "PID: "
	@pidof server
