%include "constants.inc"
%include "logger.inc"

extern LOG
extern f_print_log

global f_init_listening_server

section .data
  ;; constant value buf to set socket options
  reuseaddr_val: dd 0x01

  ;; sockaddr_in struct (16 bytes) for IPv4,
  ;; port 6969 and INADDR_ANY
  sockaddr_in:
      dw 0x02                      ; AF_INET
      dw 0x391B                    ; port (6969) in network byte order
      dd 0x00                      ; protocol(0)
      dq 0x00                      ; padding of 8 bytes

section .text

;; Create and Initialize TCP (Listening) server
;;
;; * Returns
;;   rax - fd of listening socket or -1 on error
f_init_listening_server:
  push r12

  ;; create a listening socket,
  ;; w/ `socket(AF_INET, SOCK_STREAM, 0)`
  mov rax, SYS_SOCKET
  mov rdi, AF_INET
  mov rsi, SOCK_STREAM
  xor rdx, rdx
  syscall

  ;; check for socket errors (rax < 0)
  test rax, rax
  js .err_socket

  ;; TODO - Log more info shuch as FD of the listening socket
  LOG LL_INFO, "[INFO] Created listening socket"

  ;; cache listening socket's `fd`
  mov r12, rax

  ;; set socket options for listening socket
  ;; w/ `setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_val, 4)`
  mov rax, SYS_SETSOCKOPT
  mov rdi, r12
  mov rsi, SOL_SOCKET
  mov rdx, SO_REUSEADDR
  lea r10, [reuseaddr_val]
  mov r8, 0x04                  ; sizeof(reuseaddr_val)
  syscall

  LOG LL_INFO, "[INFO] Socket options set for listening socket"

  ;; bind listening socket to wildcard (0.0.0.0) address
  ;; w/ `bind(server_fd, sockaddr_in, 16)`
  mov rax, SYS_BIND
  mov rdi, r12
  lea rsi, [sockaddr_in]
  mov rdx, 0x10                 ; size of struct (`16`)
  syscall

  ;; check for bind errors (rax != 0)
  test rax, rax
  jnz .err_bind

  LOG LL_INFO, "[INFO] Listening socket is binded to wildcard (0.0.0.0) address"

  ;; start listening on the listening socket
  ;; w/ `listen(server_fd, SOMAXCONN)`
  mov rax, SYS_LISTEN
  mov rdi, r12
  mov rsi, SOMAXCONN
  syscall

  ;; check for listen errors (rax != 0)
  test rax, rax
  jnz .err_listen

  LOG LL_INFO, "[INFO] Listening on the listening socket ..."

  ;; prepare to exit gracefully
  mov rax, r12                  ; fd of the listening socket
  jmp .ret                      ; exit gracefully
.err_socket:
  LOG LL_ERROR, "[ERROR] Unabel to create the listening socket"
  jmp .error
.err_bind:
  LOG LL_ERROR, "[ERROR] Unabel to bind listening socket"
  jmp .error
.err_listen:
  LOG LL_ERROR, "[ERROR] Unabel to start listening on the listening socket"
  jmp .error
.error:
  mov rax, -1
.ret:
  pop r12
  ret
