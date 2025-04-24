global _start

;; sys calls
%define SYS_READ 0x00
%define SYS_WRITE 0x01
%define SYS_CLOSE 0x03
%define SYS_SOCKET 0x29
%define SYS_ACCEPT 0x2B
%define SYS_BIND 0x31
%define SYS_LISTEN 0x32
%define SYS_SETSOCKOPT 0x36
%define SYS_EXIT 0x3C

;; constants
%define SOMAXCONN 0x80
%define AF_INET 0x02
%define SOCK_STREAM 0x01
%define SOL_SOCKET 0x01
%define SO_REUSEADDR 0x02

section .data
  reuseaddr_val: dd 0x01

  ;; sockaddr_in struct (16 bytes) for IPv4,
  ;; port 6969 and INADDR_ANY
  sockaddr_in:
      dw 0x02                      ; AF_INET
      dw 0x391B                    ; port (6969) in network byte order
      dd 0x00                      ; protocol(0)
      dq 0x00                      ; padding of 8 bytes

  ;; error messages for logging 16 bytes long each
  socket_err_msg db  "(err) socket   ", 0x0a
  bind_err_msg   db  "(err) bind     ", 0x0a
  listen_err_msg db  "(err) listen   ", 0x0a

section .bss
  server_fd resq 0x01              ; server fd
  client_fd resq 0x01              ; current client's fd
  read_buffer resb 0x80            ; buf to read from client
  write_buffer resb 0x80           ; buf to write to client

section .text
_start:
  ;; create a listening socket,
  ;; w/ `socket(AF_INET, SOCK_STREAM, 0)`
  mov rax, SYS_SOCKET
  mov rdi, AF_INET
  mov rsi, SOCK_STREAM
  xor rdx, rdx
  syscall

  ;; check for socket errors (rax < 0)
  test rax, rax
  js .socket_err

  ;; store servers socket fd
  mov [server_fd], rax

  ;; set socket options for server fd
  ;; w/ `setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_val, 4)`
  mov rax, SYS_SETSOCKOPT
  mov rdi, [server_fd]
  mov rsi, SOL_SOCKET
  mov rdx, SO_REUSEADDR
  lea r10, [reuseaddr_val]
  mov r8, 0x04
  syscall

  ;; bind to an address
  ;; w/ `bind(server_fd, sockaddr_in, 16)`
  mov rax, SYS_BIND
  mov rdi, [server_fd]
  lea rsi, [sockaddr_in]
  mov rdx, 0x10                 ; size of struct `16`
  syscall

  ;; check for bind errors (rax != 0)
  test rax, rax
  jnz .bind_err

  ;; listen on the server socket
  ;; w/ `listen(server_fd, SOMAXCONN)`
  mov rax, SYS_LISTEN
  mov rdi, [server_fd]
  mov rsi, SOMAXCONN
  syscall

  ;; check for listen errors (rax != 0)
  test rax, rax
  jnz .listen_err

  jmp server_loop
.socket_err:
  lea rsi, [socket_err_msg]
  jmp log_error
.bind_err:
  lea rsi, [bind_err_msg]
  jmp log_error
.listen_err:
  lea rsi, [listen_err_msg]
  jmp log_error

server_loop:
  ;; accept new connection
  ;; w/ `accept(server_fd, 0/null, 0/null)`
  mov rax, SYS_ACCEPT
  mov rdi, [server_fd]
  xor rsi, rsi
  xor rdx, rdx
  syscall

  ;; check for accept errors (rax < 0)
  test rax, rax
  js server_loop                ; skip this & accept new connections

  ;; now `rax` holds the client's fd
  mov [client_fd], rax

  ;; read user's cmd from the buf,
  ;; first byte (u8 representing id of the command)
  mov rdx, 1                    ; just one byte (u8)
  lea rsi, [read_buffer]
  mov rdi, [client_fd]
  call read_full

  ;; fall through and handle user's cmd

;; handle user's cmd, represented by a `u8` number
;; following are supported cmds,
;; - set (0)
;; - get (1)
;; - del (2)
handle_commands:
  ;; read cmd id from buf
  mov al, [read_buffer]

  cmp al, '0'
  je handle_set

  jmp close_client

;; close the connection to clients fd
;; w/ `close(client_fd)`
close_client:
  mov rax, SYS_CLOSE
  mov rdi, [client_fd]
  syscall

  jmp server_loop               ; continue to accept new connections

handle_set:
  call read_len                 ; returns `edx` (key's length)

  test rax, rax
  jnz close_client

  ;; read key from `client_fd`
  ;; key's length is stored in `edx`
  lea rsi, [read_buffer]
  mov rdi, [client_fd]
  call read_full

  ;; check for read errors
  test rax, rax
  js close_client


  jmp close_client

;; read 4 byte (C integer) length from `client_fd`
;;
;; ret,
;; edx - 4 bytes length (u32)
;; rax - -1 on error, 0 otherwise
read_len:
  mov rdx, 0x04
  lea rsi, [read_buffer]
  mov rdi, [client_fd]
  call read_full

  test rax, rax
  js .err

  mov edx, [read_buffer]

  ;; avoid buffer overflow
  cmp edx, 128
  jg .err

  jmp .ret
.err:
  mov rax, 0x01
  jmp .ret
.done:
  mov rax, 0x00
.ret:
  ret

;; read from the client fd
;; w/ `read(client_fd, read_buffer, sizeof(read_buffer))`
;;
;; args,
;; rdi - clients fd to read from
;; rsi - pointer to read buf
;; rdx - size of the read buf
;;
;; ret,
;; rax - no. of bytes read or `-1` on error
;;
;; TODO - If `0` bytes are read from the client, this does not
;; always means EOF!
read_full:
  ;; counter to store no. of bytes read
  push r12
  xor r12, r12                  ; init the counter to `0`
.read_loop:
  ;; loop termination condition, (rdx <= 0)
  cmp rdx, 0
  jle .ret

  ;; read from the client
  ;;
  ;; registers used from params,
  ;; - rdi (clients fd)
  ;; - rsi (pointer to read buf)
  ;; - rdx (sizeof read buf)
  mov rax, SYS_READ
  syscall

  ;; check for read errors (rax < 0) or EOF (rax == 0)
  test rax, rax
  js .check_eintr
  jz .ret

  ;; now `rax` holds no. of bytes read into read buf

  add rsi, rax                  ; advance pointer to read buf
  sub rdx, rax                  ; update no. of bytes to read
  add r12, rax                  ; update the counter

  jmp .read_loop
.check_eintr:
  cmp rax, -4
  je .read_loop

  ;; fall through and return error
.err:
  mov rax, -1
.ret:
  mov rax, r12                  ; load counter val to return
  pop r12

  ret

;; write to client fd
;; w/ `write(client_fd, write_buf, sizeof(write_buf))`
;;
;; args,
;; rdi - client's fd
;; rsi - pointer to write buf
;; rdx - sizeof write buf
;;
;; ret,
;; rax - no. of bytes written, or `-1` on error
;;
;; FIXME: If `0` bytes are written repetedly the func can
;; get stuck in an infinite loop
write_full:
  ;; counter to store no. of bytes written
  push r12
  xor r12, r12
.write_loop:
  ;; loop termination condition, (rdx <= 0)
  test rdx, rdx
  jz .ret
  js .ret

  ;; write to the client
  ;;
  ;; registers used from params,
  ;; rdi - clients fd
  ;; rsi - pointer to write buf
  ;; rdx - sizeof write buf
  mov rax, SYS_WRITE
  syscall

  ;; check for write errors (rax < 0)
  test rax, rax
  js .check_eintr

  ;; now `rax` holds no. of bytes wrote into write buf

  add rsi, rax                  ; advance pointer to write buf
  sub rdx, rax                  ; update no. of bytes to write
  add r12, rax                  ; update the counter

  jmp .write_loop
.check_eintr:
  cmp rax, -4
  je .write_loop

  ;; fall through and return error
.err:
  mov rax, -1
.ret:
  mov rax, r12                  ; load counter val to return
  pop r12

  ret

;; log error and shutdown with exit(1)
;;
;; 📝 NOTE: Log msg must be `16` bytes long (including line break)
;;
;; args,
;; rsi - pointer to log msg buf
log_error:
  ;; log error msg
  mov rax, SYS_WRITE
  mov rdi, 0x01
  mov rdx, 0x10                 ; 16 bytes
  syscall

  jmp error_exit

;; shutdown app w/ exit(1)
error_exit:
  mov rax, SYS_EXIT
  mov rdi, 0x01
  syscall

shutdown:
  mov rax, SYS_EXIT
  mov rdi, 0x00                 ; graceful shutdown
  syscall
