%ifndef LOGGER
%define LOGGER

extern f_print_log

;; Print logs to `stdout`
;;
;; * Arguments
;;   [Log Level, Pointer to out buffer]
;;
%macro LOG 2
  push    rax
  push    rdx

  section .data
  align 0x08                    ; align to 8 bytes

  %%msg: db %2, 0x0a
  %%msg_len equ $ - %%msg

  section .text
  align 0x10                    ; align to 16 bytes

  mov     dil, %1               ; level (rdi)
  lea     rsi, [rel %%msg]
  mov     rdx, %%msg_len
  call    f_print_log

  pop     rdx
  pop     rax
%endmacro

%endif
