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
  js error_exit

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
  jnz error_exit

  ;; listen on the server socket
  ;; w/ `listen(server_fd, SOMAXCONN)`
  mov rax, SYS_LISTEN
  mov rdi, [server_fd]
  mov rsi, SOMAXCONN
  syscall

  ;; check for listen errors (rax != 0)
  test rax, rax
  jnz error_exit

  jmp shutdown

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
  ;; preserve stack pointer
  push rbp
  mov rbp, rsp

  ;; counter to store no. of bytes read
  push r12
  xor r12, r12                  ; init the counter to `0`
.read_loop:
  ;; loop termination condition, (rdx <= 0)
  test rdx, rdx
  jz .ret
  js .ret

  ;; read from the client
  ;;
  ;; registers used from params,
  ;; rdi - clients fd
  ;; rsi - pointer to read buf
  ;; rdx - sizeof read buf
  mov rax, SYS_READ
  syscall

  ;; check for read errors (rax < 0) or EOF (rax == 0)
  test rax, rax
  js .err
  jz .ret                       ; rax == 0, i.e. EOF

  ;; now `rax` holds no. of bytes read into read buf

  add rsi, rax                  ; advance pointer to read buf
  sub rdx, rax                  ; update no. of bytes to read

  jmp .read_loop
.err:
  mov rax, -1
.ret:
  mov rsp, rbp                  ; restore stack pointer
  mov rax, r12                  ; load counter val to return

  pop rbp
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
  ;; preserve stack pointer
  push rbp
  mov rbp, rsp

  ;; counter to store no. of bytes written
  push r12
  xor r12, r12
.write_loop:
  ;; loop termination condition, (rdx <= 0)
  test rax, rax
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
  js .err

  ;; now `rax` holds no. of bytes wrote into write buf

  add rsi, rax                  ; advance pointer to write buf
  sub rdx, rax                  ; update no. of bytes to write

  jmp .write_loop
.err:
  mov rax, -1
.ret:
  mov rsp, rbp                  ; restore stack pointer
  mov rax, r12                  ; load counter val to return

  pop rbp
  pop r12

  ret

error_exit:
  mov rax, SYS_EXIT
  mov rdi, 0x01
  syscall

shutdown:
  mov rax, SYS_EXIT
  mov rdi, 0x00                 ; graceful shutdown
  syscall
