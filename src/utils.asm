%include "constants.inc"

extern LOG_LEVEL

global f_print_log

section .text

;; print log msg to `stdout`
;;
;; 📝 NOTE: If provided log level is lower then global level,
;; then logging is skipped
;;
;; * Arguments,
;;   rdi - log level (0-3)
;;   rsi - pointer to buf w/ newline
;;   rdx - sizeof write buf
;;
;; * Returns,
;;   rax - `0` on success, `1` otherwise
f_print_log:
  mov     al, [LOG_LEVEL]

  ;; Check if log level is smaller then global level
  ;; `dil (rdi) < al (rax)`
  cmp     dil, al
  jb      .done

  ;; rsi & rdx are used from args
  mov     rax, SYS_WRITE
  mov     rdi, 0x01
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
