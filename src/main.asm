global _start

;; sys calls
%define SYS_READ 0x00
%define SYS_WRITE 0x01
%define SYS_CLOSE 0x03
%define SYS_MMAP 0x09
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
  read_buffer resb 0x80            ; buf to read from client (128 bytes)
  write_buffer resb 0x80           ; buf to write to client (128 bytes)

  key_buf resb 0x40                ; buf to cache key (64 bytes)
  val_buf resb 0x40                ; buf to cache value (64 bytes)

  key_len resq 0x01                ; sizeof key buf
  val_len resq 0x01                ; sizeof val buf

  node_head resq 0x01              ; pointer to first node
  node_tail resq 0x01              ; pointer to last node

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

  cmp al, 0x00
  je handle_set

  cmp al, 0x01
  je handle_get

  jmp close_client

;; close the connection to clients fd
;; w/ `close(client_fd)`
close_client:
  mov rax, SYS_CLOSE
  mov rdi, [client_fd]
  syscall

  jmp server_loop               ; continue to accept new connections

handle_set:
  ;; READ KEY

  ;; read key length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  ;; TODO add logging here
  test rax, rax
  jnz close_client

  mov r9, rdx                   ; cache key's len

  ;; read key from `client_fd`
  ;; key's length is stored in `rdx`
  lea rsi, [key_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  ;; TODO add logging here
  test rax, rax
  js close_client

  ;; check if we read the full key here
  ;; TODO add logging here
  cmp rax, r9
  jne close_client

  ;; cache sizeof(key) into buf
  mov [key_len], r9

  ;; READ VALUE

  ;; read value length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  ;; TODO add logging here
  test rax, rax
  jnz close_client

  mov r9, rdx                   ; cache val's len

  ;; read key from `client_fd`
  ;; val's length is stored in `rdx`
  lea rsi, [val_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  ;; TODO add logging here
  test rax, rax
  js close_client

  ;; check if we read the full key here
  ;; TODO add logging here
  cmp rax, r9
  jne close_client

  ;; cache sizeof(key) into buf
  mov [val_len], r9

  ;; INSERT NODE
  call insert_node

  ;; check for insert error (rax == -1)
  ;;
  ;; TODO add logging here
  ;; HACK should return with resonable response code
  test rax, rax
  js close_client

  ;; WRITE RESPONSE

  ;; response id
  mov al, 100
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client

handle_get:
  ;; READ KEY

  ;; read key length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  ;; TODO add logging here
  test rax, rax
  jnz close_client

  mov r9, rdx                   ; cache key's len

  ;; read key from `client_fd`
  ;; key's length is stored in `rdx`
  lea rsi, [key_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  ;; TODO add logging here
  test rax, rax
  js close_client

  ;; check if we read the full key here
  ;; TODO add logging here
  cmp rax, r9
  jne close_client

  ;; cache sizeof(key) into buf
  mov [key_len], r9

  ;; find node in list
  call get_node                 ; returns `rax` (sizeof val buf)

  test rax, rax
  jz .not_found

  ;; we found the KV pair, now let's write back to the client_fd

  mov r10, rax                  ; cache sizeof val buf

  ;; write response id to the client_fd

  mov al, 200
  mov [write_buffer], al

  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; write value len to client_fd

  mov eax, r10d                 ; load lower 32 bits of size
  bswap eax                     ; convert size to network endian

  lea rdi, [write_buffer]
  mov [rdi], eax

  mov rdx, 0x04                 ; size is u32 number
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; write value back to the client

  lea rsi, [val_buf]
  mov rdi, [client_fd]
  mov rdx, r10                  ; r10 holds sizeof val buf
  call write_full

  jmp .done
.not_found:
  ;; response id
  mov al, 104
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; fall through and close the connection
.done:
  jmp close_client

;; read 4 byte (C integer) length from `client_fd`
;;
;; args,
;; r8 - max length allowed, e.g. 128
;;
;; ret,
;; edx - 4 bytes length (u32)
;; rax - -1 on error, 0 otherwise
read_len:
  mov rdx, 0x04
  lea rsi, [read_buffer]
  mov rdi, [client_fd]
  call read_full

  cmp rax, 0x04
  jne .read_err

  ;; read length stored as first 4 bytes from buf
  mov edx, [read_buffer]

  ;; convert from network byte order to host byte
  ;; order (little endian)
  bswap edx

  ;; avoid buffer overflow
  cmp rdx, r8
  jg .len_err

  jmp .done
.read_err:
  mov rax, 0x01
  jmp .ret
.len_err:
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

;; insert a new Node into the list
;;
;; ret,
;; rax - pointer to the node or -1 on err
insert_node:
  ;; create a new node
  call create_node_block

  test rax, rax
  js .err

  ;; check if head == null
  mov rdx, [node_head]

  test rdx, rdx
  jz .insert_empty              ; head & tail are null

  ;; update the tail w/ new node
  mov rbx, [node_tail]          ; old_tail
  mov [rbx], rax                ; old_tail->pointer = new_node
  mov [node_tail], rax

  jmp .ret
.insert_empty:
  mov [node_head], rax
  mov [node_tail], rax

  jmp .ret
.err:
  mov rax, -1
.ret:
  ret

;; find kv pair from the list
;;
;; ret,
;; rax - sizeof value stored in value_buf, 0 if not found
get_node:
  xor rdx, rdx                  ; init size w/ 0

  mov rbx, [node_head]

  ;; check if list is empty
  test rbx, rbx
  jz .not_found
.loop:
  ;; `rbx` - holds pointer to current node

  ;; read the key len and compare
  mov rax, [rbx + 8]            ; rax = node->key_len
  mov rcx, [key_len]

  ;; comp len of two keys
  cmp rax, rcx
  jne .next_node

  lea rdi, [key_buf]
  lea rsi, [rbx + 24]
  mov rdx, rax                  ; rax holds key's len from node
  call compare_bytes

  ;; check if key's are not same (rax != 0)
  test rax, rax
  jnz .next_node

  ;; we've found the pair, now copy bytes from node to
  ;; value buf

  mov rcx, [rbx + 8]            ; rcx = node->key_len
  mov rdx, [rbx + 16]           ; rdx = node->val_len

  ;; src = node + 24 + key_len,
  ;; dest = val_buf, count = val_len

  lea rsi, [rbx + 24 + rcx]     ; src to copy from
  lea rdi, [val_buf]            ; dest to copy to
  mov rcx, rdx                  ; size of buf to copy into dest
  rep movsb

  jmp .found
.next_node:
  mov rbx, [rbx]                ; rbx = node->next

  ;; check if pointer is not null
  test rbx, rbx
  jnz .loop

  ;; if rbx == Nulll, fall through and return not_equal
.not_found:
  xor rax, rax

  jmp .ret
.found:
  mov rax, rdx                  ; success
.ret:
  ret

;; create a mem block for a new node
;;
;; ret,
;; rax - pointer to the mem block or -1 on err
create_node_block:
  push r12

  ;; structure of the Node
  ;;
  ;; - 8 bytes = pointer
  ;; - 8 bytes = size of key
  ;; - 8 bytes = size of value
  ;; - n bytes = key (at position [8 * 3])
  ;; - m bytes = value (at position [8 * 3 + n])
  ;;
  ;; size - 24 (8 * 3) + n + m

  ;; Calculate size of Node
  ;;
  ;; size (r12) = m (no. of key bytes) + n (no. of val bytes)
  ;;     + 24  (pointer + key len + val len)
  mov r12, [key_len]
  mov rax, [val_len]
  add r12, rax
  add r12, 24

  ;; allocate mem using `mmap` syscall
  mov rax, SYS_MMAP          ; mmap syscall
  mov rdi, 0x00              ; addr = Null (kernal chooses the addr)
  mov rsi, r12               ; size of mem to allocate
  mov rdx, 0x03              ; prot = PROT_READ | PROT_WRITE (1 | 2 = 3)
  mov r8, -1                 ; fd = -1 (not backed by any file)
  mov r9, 0x00               ; offset = 0
  mov r10, 0x22              ; flags = MAP_PRIVATE | MAP_ANONYMOUS (0x02 | 0x20)
  syscall

  ;; check for `mmap` errors (rax < 0)
  test rax, rax
  js .err

  ;; Now `rax` holds the pointer to the mem block

  ;; STORE POINTER (Null)
  mov qword [rax], 0x00         ; null pointer

  ;; STORE KEY w/ LEN

  mov rdx, [key_len]
  mov [rax + 8], rdx            ; store key len

  lea rdi, [rax + 24]           ; offset to store the key
  lea rsi, [key_buf]
  mov rcx, rdx
  rep movsb

  ;; STORE VALUE w/ LEN

  mov rbx, [val_len]
  mov [rax + 16], rbx           ; store val len

  lea rdi, [rax + rdx + 24]     ; offset to store val (24 + n)
  lea rsi, [val_buf]
  mov rcx, rbx
  rep movsb

  jmp .ret
.err:
  mov rax, -1
.ret:
  pop r12
  ret

;; helper func to match two bufs
;;
;; args,
;; rsi - pointer to source buf
;; rdi - pointer to destination buf
;; rdx - size of source buf
;;
;; ret,
;; rax - `0` if equal otherwise `1`
compare_bytes:
  xor rax, rax

  test rdx, rdx
  jz .done
.loop:
  mov al, [rsi]

  cmp al, [rdi]
  jne .not_equal

  inc rsi
  inc rdi

  dec rdx
  jnz .loop
.done:
  xor rax, rax
  jmp .ret
.not_equal:
  mov rax, 0x01
.ret:
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
