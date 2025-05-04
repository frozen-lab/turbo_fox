global _start

;; Sys Calls
%define SYS_READ 0x00
%define SYS_WRITE 0x01
%define SYS_CLOSE 0x03
%define SYS_MMAP 0x09
%define SYS_MUNMAP 0x0B
%define SYS_SOCKET 0x29
%define SYS_ACCEPT 0x2B
%define SYS_BIND 0x31
%define SYS_LISTEN 0x32
%define SYS_SETSOCKOPT 0x36
%define SYS_EXIT 0x3C

;; Constants
%define SOMAXCONN 0x80
%define AF_INET 0x02
%define SOCK_STREAM 0x01
%define SOL_SOCKET 0x01
%define SO_REUSEADDR 0x02

;; Log Levels
%define LL_DEBUG 0x00
%define LL_INFO  0x01
%define LL_WARN  0x02
%define LL_ERROR 0x03

;; Response Id's

%define RES_OK       0xC8       ; 200
%define RES_CREATED  0xC9       ; 201
%define RES_DELETED  0xCA       ; 202
%define RES_UPDATED  0xCB       ; 203

%define RES_NOTFOUND 0xD3       ; 211
%define RES_ERROR    0xD4       ; 212
%define RES_UNKNOWN  0xD5       ; 213

;; Request Id's

%define REQ_SET 0x00            ; 0
%define REQ_GET 0x01            ; 1
%define REQ_DEL 0x02            ; 2

;; Macro to print the logs
;;
;; args -> level, ptr
%macro LOG 2
  push    rax
  push    rdx

  section .data
  align 0x08                    ; align to 8 bytes

  %%msg: db %2, 0x0a
  %%msg_len equ $ - %%msg

  section .text
  align 0x10                    ; align to 16 bytes

  mov     dil, %1   ; level (rdi)
  lea     rsi, [rel %%msg]
  mov     rdx, %%msg_len
  call    f_log_msg

  ;; FIXME: how to handle write error?

  pop     rdx
  pop     rax
%endmacro

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

section .bss
  log_level resb 0x01              ; 0=DEBUG,1=INFO,2=WARN,3=ERROR

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
  ;; set default log level to debug
  mov al, LL_DEBUG
  mov [log_level], al

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

  LOG LL_DEBUG, "[DEBUG] created socket"

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

  LOG LL_DEBUG, "[DEBUG] binding socket to wildcard (0.0.0.0) addr"

  ;; listen on the server socket
  ;; w/ `listen(server_fd, SOMAXCONN)`
  mov rax, SYS_LISTEN
  mov rdi, [server_fd]
  mov rsi, SOMAXCONN
  syscall

  ;; check for listen errors (rax != 0)
  test rax, rax
  jnz .listen_err

  LOG LL_DEBUG, "[DEBUG] listening on server_fd"

  LOG LL_DEBUG, "[DEBUG] server loop init"
  jmp server_loop
.socket_err:
  LOG LL_ERROR, "[ERROR] socket error"
  jmp l_server_exit
.bind_err:
  LOG LL_ERROR, "[ERROR] bind error"
  jmp l_server_exit
.listen_err:
  LOG LL_ERROR, "[ERROR] listen error"
  jmp l_server_exit

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
;;
;; following are supported cmds,
;; - set (0)
;; - get (1)
;; - del (2)
handle_commands:
  ;; read req id from buf
  mov al, [read_buffer]

  cmp al, REQ_SET
  je handle_set

  cmp al, REQ_GET
  je handle_get

  cmp al, REQ_DEL
  je handle_del

  ;; if none of the cmds match,
  ;; return w/ not found res id
  jmp handle_unknown_cmd

;; close the connection to clients fd
;; w/ `close(client_fd)`
close_client:
  mov rax, SYS_CLOSE
  mov rdi, [client_fd]
  syscall

  jmp server_loop               ; continue to accept new connections

handle_unknown_cmd:
  LOG LL_WARN, "[WARN] Received unknown cmd from client"

  ;; response id
  mov al, RES_UNKNOWN
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client

;; handle set cmd
;;
;; protocol,
;; req - {id}{key_size}{key}{val_size}{val}
;; res - {id}
;;
;; res id's -> CREATED or ERROR
handle_set:
  ;; READ KEY

  ;; read key length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  test rax, rax
  jnz .unknown_error

  mov r9, rdx                   ; cache key's len

  ;; read key from `client_fd`
  ;; key's length is stored in `rdx`
  lea rsi, [key_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  test rax, rax
  js .unknown_error

  ;; check if we read the full key here
  ;; FIXME: This should return w/ response ID
  ;; TODO: key error
  cmp rax, r9
  jne .unknown_error

  ;; cache sizeof(key) into buf
  mov [key_len], r9

  ;; READ VALUE

  ;; read value length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  test rax, rax
  jnz .unknown_error

  mov r9, rdx                   ; cache val's len

  ;; read value from `client_fd`
  ;; val's length is stored in `rdx`
  lea rsi, [val_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  test rax, rax
  js .unknown_error

  ;; check if we read the full value here
  ;; FIXME: Need a value error here
  ;; TODO: Value error
  cmp rax, r9
  jne .unknown_error

  ;; cache sizeof(key) into buf
  mov [val_len], r9

  ;; INSERT NODE
  call insert_node

  ;; check for insert error (rax == -1)
  ;; FIXME: Should return w/ well defined error here
  ;; TODO: insert error
  test rax, rax
  js .unknown_error

  ;; WRITE RESPONSE

  ;; response id
  mov al, RES_CREATED
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; check for write errors (rax < 0)
  test rax, rax
  js .unknown_error

  ;; close the conn if everything went right
  jmp close_client
.unknown_error:
  LOG LL_ERROR, "[ERROR] Unknown error in SET command"

  ;; response id
  mov al, RES_ERROR
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client

;; handle read cmd
;;
;; protocol,
;; req - {id}{key_len}{key}
;; res - {id}{val_len}{val}
;;
;; res id's -> OK or ERROR
handle_get:
  ;; READ KEY

  ;; read key length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  test rax, rax
  jnz .unknown_error

  mov r9, rdx                   ; cache key's len

  ;; read key from `client_fd`
  ;; key's length is stored in `rdx`
  lea rsi, [key_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  test rax, rax
  js .unknown_error

  ;; check if we read the full key here
  ;; TODO: key error
  cmp rax, r9
  jne .unknown_error

  ;; cache sizeof(key) into buf
  mov [key_len], r9

  ;; find node in list
  call get_node                 ; returns `rax` (sizeof val buf)

  test rax, rax
  jz .not_found

  ;; we found the KV pair, now let's write back to the client_fd

  mov r10, rax                  ; cache sizeof val buf

  ;; write response id to the client_fd

  mov al, RES_OK
  mov [write_buffer], al

  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; check for write error (rax == -1)
  test rax, rax
  js .unknown_error

  ;; write value len to client_fd

  mov eax, r10d                 ; load lower 32 bits of size
  bswap eax                     ; convert size to network endian

  lea rdi, [write_buffer]
  mov [rdi], eax

  mov rdx, 0x04                 ; size is u32 number
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; check for write error (rax == -1)
  test rax, rax
  js .unknown_error

  ;; write value back to the client

  lea rsi, [val_buf]
  mov rdi, [client_fd]
  mov rdx, r10                  ; r10 holds sizeof val buf
  call write_full

  ;; check for write error (rax == -1)
  test rax, rax
  js .unknown_error

  ;; close client after success
  jmp close_client
.not_found:
  ;; response id
  mov al, RES_NOTFOUND
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client
.unknown_error:
  LOG LL_ERROR, "[ERROR] Unknown error in GET command"

  ;; response id
  mov al, RES_ERROR
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client

;; handle del cmd
;;
;; protocol,
;; req - {id}{key_len}{key}
;; res - {id}
;;
;; res id's -> DELETED, NOTFOUND or ERROR
handle_del:
  ;; READ KEY

  ;; read key length from `client_fd`
  mov r8, 128                   ; max key len allowed
  call read_len                 ; returns `rdx` (read length)

  ;; check for read error
  ;; TODO: key error
  test rax, rax
  jnz .unknown_error

  mov r9, rdx                   ; cache key's len

  ;; read key from `client_fd`
  ;; key's length is stored in `rdx`
  lea rsi, [key_buf]
  mov rdi, [client_fd]
  mov rdx, r9
  call read_full

  ;; check for read errors
  test rax, rax
  js .unknown_error

  ;; check if we read the full key here
  ;; TODO: key error
  cmp rax, r9
  jne .unknown_error

  ;; cache sizeof(key) into buf
  mov [key_len], r9

  ;; delete the node
  call del_node                 ; returns `rax` w/ deletion status

  test rax, rax
  jnz .not_found

  ;; write ok response id to the client_fd

  mov al, RES_DELETED
  mov [write_buffer], al

  ;; check for write error
  test rax, rax
  js .unknown_error

  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  ;; check for write error
  test rax, rax
  js .unknown_error

  jmp close_client
.not_found:
  ;; write not found response id to the client_fd

  mov al, RES_NOTFOUND
  mov [write_buffer], al

  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

  jmp close_client
.unknown_error:
  LOG LL_ERROR, "[ERROR] Unknown error for DEL command"

  ;; response id
  mov al, RES_ERROR
  mov [write_buffer], al

  ;; write response to the client_fd
  mov rdx, 0x01
  lea rsi, [write_buffer]
  mov rdi, [client_fd]
  call write_full

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

;; find and delete a node in the list
;;
;; ret,
;; rax - `0` on success, `1` otherwise
del_node:
  push r12
  push r13
  push r14

  xor r12, r12                  ; prev_node = Null
  mov rbx, [node_head]          ; curr_node = head

  test rbx, rbx
  jz .not_found
.loop:
  ;; compare key lengths

  mov rax, [rbx + 8]            ; rax = node->key_len
  mov rcx, [key_len]

  cmp rax, rcx
  jne .next_node

  ;; compare key buffers

  lea rdi, [key_buf]
  lea rsi, [rbx + 24]
  mov rdx, rax                  ; rax holds key's len from node
  call compare_bytes

  test rax, rax
  jnz .next_node

  ;; we found the node

  mov r14, rbx                  ; save "curr" node pointer to unmap mem
  mov r13, [rbx]                ; next_node = curr->next

  cmp r12, 0x00
  jnz .unlink_prev

  mov [node_head], r13
  jmp .check_tail
.unlink_prev:
  mov [r12], r13                ; prev->next = next
.check_tail:
  test r13, r13
  jnz .found

  mov [node_tail], r12
  jmp .found
.next_node:
  mov r12, rbx                  ; prev = cur
  mov rbx, [rbx]                ; curr = curr->next

  ;; check if we reach the end
  test rbx, rbx
  jz .not_found

  jmp .loop
.found:
  xor rax, rax

  ;; fall through and unmap the memory
.mem_unmap:
  mov   rsi, [r14 + 8]          ; key_len
  add   rsi, [r14 + 16]         ; + val_len
  add   rsi, 24                 ; + header (next,key_len,val_len)

  mov rax, SYS_MUNMAP
  mov rdi, r14                  ; addr = pointer to deleted node
  syscall

  ;; check for unmap error (rax < 0)
  test rax, rax
  js .unmap_error

  jmp .ret
.not_found:
  mov rax, 0x01

  jmp .ret
.unmap_error:
  LOG LL_ERROR, "[ERROR] error while un-mapping memory for discarded node"
.ret:
  pop r14
  pop r13
  pop r12

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

;; print log msg to stdout
;;
;; 📝 NOTE: If provided log level is lower then global level,
;; then logging is skipped
;;
;; args,
;; rdi - log level (0-3)
;; rsi - pointer to buf w/ newline
;; rdx - sizeof write buf
;;
;; ret,
;; rax - `0` on success, `1` otherwise
f_log_msg:
  mov     al, [log_level]

  ;; Check if log level is smaller then global level
  ;; `dil (rdi) < al (rax)`
  cmp     dil, al
  jb      .done

  mov     rax, SYS_WRITE
  mov     rdi, 0x01
  ;; rsi & rdx are used from args
  syscall

  test rax, rax
  js .err

  jmp .done
.err:
  mov rax, 0x01
  jmp .ret
.done:
  xor rax, rax
.ret:
  ret

;; shutdown app cause of server error
;; w/ exit(2)
l_server_exit:
  mov rax, SYS_EXIT
  mov rdi, 0x02
  syscall

;; shutdown app cause of unknown error
;; w/ exit(1)
error_exit:
  mov rax, SYS_EXIT
  mov rdi, 0x01
  syscall

;; normal shutdown
l_shutdown:
  mov rax, SYS_EXIT
  mov rdi, 0x00
  syscall
