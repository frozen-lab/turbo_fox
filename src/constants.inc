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
