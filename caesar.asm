	section .data
;;; CONSTANTS
BUFSIZE:equ 8192 ; The size of the string buffer.
SYS_READ:equ 0	 ; System call number for the read syscall
SYS_WRITE:equ 1	 ; System call number for the write syscall
STDIN_FD:equ 0
STDOUT_FD:equ 1
	
	section .bss
	;; The string buffer for reading a string.
strbuf: resb BUFSIZE
	
	section .text

	global _start
_start:
	;; while (read_str() > 0) { write_str(); }
	call read_str
	call strbuf_to_integer
	mov rdi, rax
	jmp exit_program

;;; str_length: get the length of a zero-terminated string.
;;; Not including zero-terminator.
;;; Said zero-terminated string is pointed to by RDI.
str_length:
	mov rax, rdi		; rax = rdi;
.loop_begin:
	cmp byte [rax], 0	; while (*rax != '\0')
	je .loop_end
	inc rax			; 	rax++;
	jmp .loop_begin
.loop_end:
	sub rax, rdi		; return rax - rdi;
	ret

;;; Procedure read_str:
;;; Read a zero-terminated string into strbuf.
;;; If zero bytes are read (EOF reached), then return -1;
;;; If some other error occurs, then exit the program with error code 1.
;;; otherwise, return the length of the string,
;;; 	not including the zero-terminating byte.
read_str:
	push rbp
	mov rbp, rsp
	sub rsp, 8		; keep stack 16-byte aligned

	mov eax, SYS_READ	; Assigning to eax zero-extends to rax.
	mov edi, STDIN_FD	; Ditto for other registers.
	lea rsi, [rel strbuf]	; Use rip-relative addressing.
	mov edx, BUFSIZE - 1	; leave space for zero-terminator.
	syscall
	
	test rax, rax
	jz .eof_reached
	js .read_fail

	;; Successful read:
	;; rax holds the number of bytes read, and it's not zero.
	lea rsi, [rel strbuf]
	mov byte [rsi + rax], 0 ; add zero-terminator
	leave
	ret

.eof_reached:
	mov rax, -1
	leave
	ret
	
.read_fail: 			; failed to read a line: do "exit(1)"
	mov edi, 1
	jmp exit_program	; no return: do tail-call optimization.

;;; Procedure write_str:
;;; Write zero-terminated string in strbuf to stdout.
;;; Precondition: strbuf contains a zero-terminated string.
write_str:
	push rbp
	mov rbp, rsp
	sub rsp, 8
	
	lea rdi, [rel strbuf]
	call str_length
	mov [rsp], rax		; save the string's length

	
	;; Write the string in strbuf, no matter
	;; how many syscalls it takes.
.write_loop_start:
	cmp qword [rsp], 0
	je .write_loop_end

	mov eax, SYS_WRITE
	mov edi, STDOUT_FD
	lea rsi, [rel strbuf]
	mov rdx, [rsp]
	syscall

	cmp rax, -1
	je .write_failure

	sub qword [rsp], rax ; subtract bytes written from string length

	jmp .write_loop_start
.write_loop_end:
	
	leave
	ret
.write_failure:
	mov edi, 1
	jmp exit_program


;;; Procedure exit_program:
;;; Exit the program with the return code in RDI.
exit_program:
	mov eax, 60
	syscall


;;; Procedure strbuf_to_integer:
;;; Convert the zero-terminated string in strbuf to
;;; a signed 64-bit integer.
;;; Preconditions:
;;; - The string in strbuf is zero-terminated
;;; - Strbuf definitely contains an integer.
strbuf_to_integer:
	;; rax stores n, the result with which to return from the function
	;; rdi stores p, the pointer iterator through the array
	;; r8 stores tmp1
	;; r9 stores tmp2
	;; r10 holds the sign
	xor eax, eax
	xor r8d, r8d
	xor r9d, r9d
	lea rdi, [rel strbuf]

	cmp byte [rdi], '-'
	je .negative
	mov r10, 1
	jmp .loop_begin
.negative:
	mov r10, -1
	inc rdi
.loop_begin:
	cmp byte [rdi], '0'
	jb .loop_end
	cmp byte [rdi], '9'
	ja .loop_end

	movsx r8, byte [rdi]
	sub r8, '0'

	lea r9, [rax + rax * 8]	; r9 = rax * 10
	add r9, rax

	lea rax, [r8 + r9]
	inc rdi
	jmp .loop_begin
.loop_end:
	imul r10
	ret			; return n * sign; // (rax holds n's value)
	

;; char strbuf[BUFSIZE];
;; int64_t strbuf_to_integer(void) {
;;         int64_t n, tmp1, tmp2, sign;
;;         char *p;
;;         n = 0;
;;         p = &strbuf[0];
;;         if (*p != '-') sign = 1;
;;         else { sign = -1; p++; }
;; loop:
;;         if (*p < '0') goto loop_end;
;;         if (*p > '9') goto loop_end;
;;         {       
;;                 tmp1 = *p;
;;                 tmp1 -= '0';
;;         }
;;         {
;;                 tmp2 = n * 10;
;;         }
;;         n = tmp1 + tmp2;
;;         p++;
;;         goto loop;
;; loop_end:
;;         return n;
;; }
