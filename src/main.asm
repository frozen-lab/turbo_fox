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
  ;; fall through and shutdown

shutdown:
  mov rax, SYS_EXIT
  mov rdi, 0x00                 ; graceful shutdown
  syscall
