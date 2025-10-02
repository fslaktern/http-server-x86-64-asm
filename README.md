# HTTP server in x86-64 assembly

The provided `server.S` is (very) roughly equivalent to the following C code:

```c
#define req_buf_max_size 4095
#define res_body_max_size 4095

char req_buf[4096];
char res_body[4096];
char http_path[256];
char http_verb[8];

short res_body_size;
short req_header_size;
short req_body_size;

int strlen(char *input) {
    for (int i = 0; *(input + i) != 0; i++)
    return i;
}

int strntok(char *input, char *output, char delimiter, int max_count) {
    for (int i = 0; i < max_count && *(input + i) != delimiter; i++) {
        *(output + i) = *(input + i);
    }
    return i;
}

bool strcmp(char *input_a, char *input_b) {
    for (int i = 0; *(input_a + i) != 0; i++) {
        if (*(input_a + i) != *(input_b + i)) {
            return false;
        }
    }
    return true;
}

int strstr(char *substr, char *input) {
    int i = 0;
    int j = 0;
    while (1) {
        if (*(input + j) == *(substr + i)) {
            i++;
            continue;
        }
        
        if (*(substr + i) == 0) {
            return j - i;
        }

        if (*(input + j) == 0) {
            return -1;
        }

        if (i == 0) {
            j += 1;
        }

        i = 0;
    }
    return 
}

int main() {
    struct sockaddr_in sockaddr = {
        sa_family: AF_INET,
        sin_port: htons(80),
        sin_addr: 0 // 0.0.0.0
    };
    socklen_t sockaddr_len = 16;

    int sock_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    bind(sock_fd, sockaddr, sockaddr_len);

    backlog = 0;
    listen(sock_fd, backlog);
    
    while (1) {
        // doesn't actually use sockaddr, so listens and accepts on a random port since port == 0
        int client_fd = accept(sock_fd, NULL, NULL);

        pid_t pid = fork();
        if (pid > 0) {
            // parent specific
            close(client_fd);
            continue;
        } else {
            // child specific
            close(sock_fd);
        }

        read(client_fd, req_buf, req_buf_max_size);
        int token_length = strntok(req_buf, http_verb, ' ', 7);
        strntok(req_buf + token_length + 1, http_path, ' ', 256);

        if (req_buf == "GET") {
            int file_fd = open(http_path, O_RDONLY, 0000);
            res_body_size = read(file_fd, res_body, res_body_max_size);
        } else if (req_buf == "POST") {
            req_header_size = strstr("\r\n\r\n\0", req_buf);
            req_body_size = strlen(req_buf + req_header_size + 4);

            int file_fd = open(http_path, O_WRONLY | O_CREAT, 0777);
            write(file_fd, req_buf + req_header_size + 4, req_body_size);
        } else {
            goto done;
        }

        close(file_fd);
        write(client_fd, res_header, res_header_size);
        write(client_fd, res_body, res_body_size);

        done:
        close(client_fd);
        exit(0);
    }
}
```

## Bugs I will not fix

- The server uses a `sockaddr_in` with port set to `htons(80)` (just to bind to port 80), but in `accept(...)` it just uses any port. Either that or `bind(...)` is called with an improper `sockaddr` 
- The `memcpy` helper in `server.S` does an out-of-bounds read and then an out-of-bounds write due to a double off-by-one error; reads from 1 to n, instead of 0 to n - 1
