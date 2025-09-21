.intel_syntax noprefix
.globl _start

.section .bss

req_buf:
    .skip 4096

res_body:
    .skip 4096

res_body_size:
    .skip 2

http_path:
    .skip 256

http_verb:
    .skip 8

req_header_size:
    .skip 2

req_body_size:
    .skip 2

.section .rodata
    .equ sys_read, 0
    .equ sys_write, 1
    .equ sys_open, 2
    .equ sys_close, 3
    .equ sys_getpid, 39
    .equ sys_socket, 41
    .equ sys_accept, 43
    .equ sys_bind, 49
    .equ sys_listen, 50
    .equ sys_fork, 57
    .equ sys_exit, 60

    .equ req_buf_max_size, 4095
    .equ res_body_max_size, 4095

http_verb_get:
    .asciz "GET"

http_verb_post:
    .asciz "POST"

http_separator:
    .byte 0xd, 0xa, 0xd, 0xa, 0

res_header:
    .ascii "HTTP/1.0 200 OK"
    .byte 0xd, 0xa, 0xd, 0xa

res_header_size:
    .quad 19

sockaddr:
    .word 2         # sa_family: AF_INET
    .word 0x5000    # sin_port: Port 80 (in network byte order)
    .long 0         # sin_addr.s_addr: INADDR_ANY
    .quad 0         # Zero padding to match size of sockaddr_in (16 bytes)

sockaddr_end:
    .equ sockaddr_len, sockaddr_end - sockaddr


# rsp: stack pointer (bottom of stack)
# rbp: base pointer (top of stack)

# rax: syscalls and return values
# rdi: arg #0
# rsi: arg #1
# rdx: arg #2
# r10: arg #3
# r9:  arg #4
# r8:  arg #5

# r15: sock_fd
# r14: client_fd
# r13: http_path_fd
# r12:
# r11:
# rbx:
# rcx: loop counter

.section .text
_start:
    push rbp
    mov rbp, rsp

socket:
    mov rax, sys_socket
    xor edi, edi
    mov di, [sockaddr]          # domain: AF_INET (IPv4)
    mov rsi, 1                  # type: SOCK_STREAM
    xor edx, edx                # protocol: IPPROTO_IP
    syscall
    mov r15, rax                # Save the file descriptor (sockfd)

bind:
    mov rax, sys_bind
    mov rdi, r15                # sockfd: sock_fd
    lea rsi, [sockaddr]         # addr: const struct sockaddr *
    mov rdx, sockaddr_len       # addrlen: socklen_t: sizeof(struct sockaddr)
    syscall

listen:
    mov rax, sys_listen
    mov rdi, r15                # fd: sock_fd
    xor esi, esi                # backlog: 0 (number of pending requests to let live in queue)
    syscall

serve_loop:
accept:
    mov rax, sys_accept
    mov rdi, r15                # fd: sock_fd
    xor esi, esi                # sockaddr: NULL
    xor edx, edx                # addrlen: NULL
    syscall
    mov r14, rax                # save client_fd

fork:
    mov rax, sys_fork
    syscall

    cmp rax, 0
    jne parent_specific
    jmp child_specific

parent_specific:
    mov rax, sys_close
    mov rdi, r14
    syscall                     # close client_fd for parent
    jmp serve_loop              # parent continues listening for new connections

child_specific:
    mov rax, sys_close
    mov rdi, r15
    syscall                     # close sock_fd for child

handle_request:
    mov rax, sys_read
    mov rdi, r14                # fd: client_fd
    lea rsi, [req_buf]          # buf: char *
    mov rdx, req_buf_max_size   # count: rcx
    syscall

get_http_verb:
    lea rdi, [req_buf]          # char *input
    lea rsi, [http_verb]        # char *output
    mov rdx, 0x20               # char delimiter
    mov r8, 7                   # int max_read_size
    call strntok
    mov byte ptr [http_verb + rax], 0 # end with null byte

get_http_path:
    lea rdi, [req_buf + rax + 1] # char *input + offset + 1 to skip space
    lea rsi, [http_path]        # char *output
    mov rdx, 0x20               # char delimiter
    mov r8, 256                 # int max_read_size
    call strntok
    mov byte ptr [http_path + rax], 0 # end with null byte

branch_on_http_verb:
    lea rsi, [http_verb]
    lea rdi, [http_verb_get]
    call strcmp
    test al, al
    je handle_get

    lea rdi, [http_verb_post]
    call strcmp
    test al, al
    je handle_post

    jmp close_client_fd

handle_get:
open_requested_file_r:
    mov rax, sys_open
    lea rdi, [http_path]        # const char *filename
    xor esi, esi                # flags: 0
    xor edx, edx                # mode: 0 (read)
    syscall

read_requested_file:
    mov rdi, rax                # fd: opened file
    mov rax, sys_read
    lea rsi, [res_body]         # char *buf: static header size
    mov rdx, res_body_max_size  # count: bytes to read
    syscall
    mov [res_body_size], rax    # set response body size (Content-Length)

handle_get_done:
    jmp close_requested_file

handle_post:
extract_data:
    lea rdi, [http_separator]   # substr: \r\n\r\n
    lea rsi, [req_buf]          # haystack: req_buf
    call strstr
    mov [req_header_size], rax

    lea rdi, [req_buf + rax + 4] # skip header + separator
    call strlen
    mov [req_body_size], rax

open_requested_file_w:
    mov rax, sys_open
    lea rdi, [http_path]        # const char *filename
    mov rsi, 0x41               # flags: 0x1 (O_WRONLY) | 0x40 (O_CREAT)
    mov rdx, 0777               # mode: 0777 (rwxrwxrwx)
    syscall

write_requested_file:
    xor ecx, ecx
    mov cx, [req_header_size]

    lea rsi, [req_buf]          # buf: request body
    add rsi, rcx                # skip header
    add rsi, 4                  # skip separator

    mov rdi, rax                # fd: opened file
    mov rax, sys_write
    mov rdx, [req_body_size]    # count: body size
    syscall

close_requested_file:
    mov rax, sys_close
    syscall

send_res_header:
    xor edx, edx

    mov rax, sys_write
    mov rdi, r14                # fd: client_fd
    lea rsi, [res_header]       # buf: const char *
    mov dx, [res_header_size]  # count: header size
    syscall

send_res_body:
    xor edx, edx

    mov rax, sys_write
    mov rdi, r14                # fd: client_fd
    lea rsi, [res_body]         # buf: const char *
    mov dx, [res_body_size]    # count: body size
    syscall

close_client_fd:
    mov rax, sys_close
    mov rdi, r14                # fd: client_fd
    syscall

client_done:
    mov rdi, r15                # restore sock_fd

exit:
    mov rsp, rbp                # restore stack
    mov rax, sys_exit
    xor rdi, rdi                # status: 0
    syscall


# --- HELPERS ---

# copies N bytes from A to B in reverse order, filling up right-to-left
# rdi: char *input
# rsi: char *output
# rdx: size_t count
memcpy:
    push rax
.memcpy_loop:
    cmp rdx, 0
    jbe .memcpy_done
    mov al, [rdi + rdx]
    mov [rsi + rdx], al
    dec rdx
    jmp .memcpy_loop
.memcpy_done:
    pop rax
    ret

# counts number of bytes until null byte
# rax: string length
# rdi: char *input
strlen:
    push rcx                    # save rcx
    xor ecx, ecx                # i = 0

.strlen_loop:
    cmp byte ptr [rdi + rcx], 0
    je .strlen_done
    inc rcx                     # i += 1
    jmp .strlen_loop

.strlen_done:
    mov rax, rcx                # return value in rax
    pop rcx                     # restore rcx
    ret


# reads bytes from input to output until input[i] == delimiter
# rdi: char *input
# rsi: char *output
# rdx: char delimiter
# r8: max count
strntok:
    push rcx
    push r9
    xor ecx, ecx

.strntok_loop:
    mov r9b, byte ptr [rdi + rcx]
    cmp r9b, dl                     # if input[i] == delim:
    je .strntok_done                 #    return i

    cmp rcx, r8                     # if i is too large:
    jae .strntok_done                #    return i

    mov byte ptr [rsi + rcx], r9b   # output[i] = input[i]
    inc ecx                         # i += 1
    jmp .strntok_loop

.strntok_done:
    mov rax, rcx
    pop r9
    pop rcx
    ret

# rax: bool different (true = 1, false = 0)
# rdi: char *input_a
# rsi: char *input_b
strcmp:
    xor eax, eax	# make sure top bits are zeroed
.strcmp_loop:
    mov al, [rdi]
    cmp al, [rsi]	# if rdi[i] != rsi[i]
    jne .strcmp_diff	#   return 1

    test al, al		# if rdi[i] == 0
    je .strcmp_similar	#   return 0

    inc rdi		# i += 1
    inc rsi
    jmp .strcmp_loop	# continue

.strcmp_diff:
    mov eax, 1		# return 1
    jmp .strcmp_done

.strcmp_similar:
    xor eax, eax	# return 0

.strcmp_done:
    ret

# locate substring in char *
# rdi: char *substr
# rsi: char *input
strstr:
    push rbx                # save rbx
    push rcx                # save rcx
    xor eax, eax            # char a = 0
    xor ebx, ebx            # i = 0
    xor ecx, ecx            # j = 0
    jmp .strstr_loop        # skip incrementing before first iteration

.strstr_increment:
    inc rbx                 # i += 1
.strstr_increment_only_j:
    inc rcx                 # j += 1

.strstr_loop:
    mov al, [rdi + rbx]     # a = substr[i]
    cmp al, [rsi + rcx]     # if a == input[j]
    je .strstr_increment    #   i += 1
			    #   j += 1
			    #   continue

    test al, al             # if a == 0
    je .strstr_done         #   return j - i

    cmp byte ptr [rsi + rcx], 0 # if input[j] == 0
    je .strstr_fail             #   return -1

    test rbx, rbx               # if i == 0
    je .strstr_increment_only_j #     j += 1
				#     continue 
.strstr_restart:
    xor ebx, ebx	    # i = 0
    jmp .strstr_loop        # continue

.strstr_fail:		    # return -1: needs to be handled properly by callee
    xor eax, eax
    dec rax
    pop rcx
    pop rbx
    ret

.strstr_done:		    # return j - i: return index of start of substr in haystack
    mov rax, rcx
    sub rax, rbx
    pop rcx
    pop rbx
    ret
