	section .rodata
;;; CONSTANTS
BUFSIZE:equ 8192 ; The size of the string buffer.
SYS_READ:equ 0	 ; System call number for the read syscall
SYS_WRITE:equ 1	 ; System call number for the write syscall
STDIN_FD:equ 0
STDOUT_FD:equ 1
	
shift_val_prompt: db "Enter a shift value between -25 and 25 (included)", 10, 0
string_prompt: db "Enter a string greater than 8 characters", 10, 0

cur_message: db "Current message: ", 0
edited_message: db "Edited message: ", 0

	section .bss
	;; The string buffer for reading a string.
strbuf: resb BUFSIZE
strbuf_end: resq 1 ; zero terminator for strbuf if BUFSIZE bytes are read

shift_val: resq 1
	
	section .text

	global main
main:
	lea rdi, [rel strbuf_end] ;; Initialize zero-terminator after strbuf.
	mov qword [rdi], 0
.get_shift_val:
	lea rdi, [rel shift_val_prompt]
	call write_str
	call read_str		; Read string into strbuf.
	cmp rax, -1
	je .done

	call test_has_number
	test rax, rax
	jz .get_shift_val	; User didn't input a number.
	call strbuf_to_integer	; Otherwise, parse it as an integer.
	mov rdi, rax
	mov r12, rax		; Save integer in R12 for later.
	call bounds_check
	test rax, rax
	jz .get_shift_val	; Ask again if it's not in bounds.
	;; it's in bounds

.get_string:
	lea rdi, [rel string_prompt]
	call write_str
	call read_str		; Read string into strbuf.
	cmp rax, -1
	je .done

	cmp rax, 8
	jbe .get_string		; String must be at least 8 characters.

	;; Print "Current message: [string in strbuf]"
	lea rdi, [rel cur_message]
	call write_str
	lea rdi, [rel strbuf]
	call write_str

	lea rdi, [rel edited_message] ; Print "Edited message: "
	call write_str

	;; Do the Caesar shift
	lea rdi, [rel strbuf]
	mov rsi, r12
	call shift_str

	lea rdi, [rel strbuf] ; Print what's in strbuf
	call write_str

.done:
	xor edi, edi
	jmp exit_program

;;; Procedure shift_strbuf
;;; Shift alphabetic characters in string
;;; pointed at by RDI by the number of characters
;;; indicated in RSI.
shift_str:
	lea rdi, [rel strbuf]
.loop:
	cmp byte [rdi], 0
	je .done
	call shift_char
	inc rdi
	jmp .loop
.done:
	ret

;;; Procedure shift_char:
;;; Subroutine of shift_str.
;;; If the character pointed to by RDI is alphabetic:
;;; Then said character is shifted left or right
;;; by the number of characters indicated by RSI.
;;; Trashes RCX and RAX and RSI and R11 and RDX.
;;; Preserves RDI.
shift_char:
	;; Store the character in RCX.
	;; Store the shift value in RSI.
	;; Store the pointer in [RSP].
	;; Store a temporary in R11.
	push rbp
	mov rbp, rsp
	sub rsp, 24
	mov [rsp], rdi ; [RSP] holds the pointer to our character

	call char_type
	test eax, eax
	jz .done	; If it's not alphabetic, we're done.

	movzx rcx, byte [rdi]	; Otherwise, store the letter in RCX.
	dec eax
	test eax, eax
	jz .is_upper
	jmp .is_lower
.is_upper:
	mov r11, 'A'
	jmp .join
.is_lower:
	mov r11, 'a'
.join:
	;; r11 = 'a' or 'A'
	;; result = ((ch - r11 + shift) % 26 + r11)
	sub rcx, r11	; subtract r11
	add rcx, rsi	; add shift
	mov [rsp + 8], r11
	mov rdi, rcx
	call mod_26
	mov r11, [rsp + 8]
	;; RAX holds (ch - R11 + shift % 26)
	test rax, rax
	jge .positive ; jump if rax >= 0
	add rax, 26
.positive:
	add rax, r11 ; ...so add R11.
	mov rdi, [rsp]
	mov byte [rdi], al ; Now we're done.
.done:
	leave
	ret

;;; Procedure mod_26:
;;; Return RDI % 26 in RAX.
;;; Also trashes registers RCX and RDX.
mod_26:
	mov rax, rdi
	mov ecx, 26
	cqo		; (Copies sign bit of RAX into every bit of RDX).
	idiv rcx
	mov rax, rdx
	ret

;;; Procedure char_type:
;;; If the character pointed to by RDI is uppercase, return 1.
;;; If said character is lowercase, return 2.
;;; Otherwise, return 0.
char_type:
.if_upper:
	cmp byte [rdi], 'A'
	jb .elif_lower
	cmp byte [rdi], 'Z'
	ja .elif_lower
	mov eax, 1
	jmp .done
.elif_lower:
	cmp byte [rdi], 'a'
	jb .else
	cmp byte [rdi], 'z'
	ja .else
	mov eax, 2
	jmp .done
.else:
	xor eax, eax
.done:
	ret

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
	mov edx, BUFSIZE
	syscall
	
	test rax, rax
	jz .eof_reached
	js .read_fail

	;; Successful read:
	;; rax holds the number of bytes read, and it's not zero.
	lea rsi, [rel strbuf]
	mov byte [rsi + rax], 0 ; add zero-terminator
	jmp .done

.eof_reached:
	mov rax, -1
.done:
	leave
	ret
	
.read_fail: 			; failed to read a line: do "exit(1)"
	mov edi, 1
	jmp exit_program	; no return: do tail-call optimization.

;;; Procedure write_str:
;;; Write zero-terminated string in RDI to stdout.
;;; Precondition: RDI points to a zero-terminated string.
write_str:
	push rbp
	mov rbp, rsp
	sub rsp, 24

	mov [rsp + 8], rdi	; save the string pointer
	call str_length
	mov [rsp], rax		; save the string's length

	
	;; Write the string in strbuf, no matter
	;; how many syscalls it takes.
.write_loop_start:
	cmp qword [rsp], 0
	je .write_loop_end

	mov eax, SYS_WRITE
	mov edi, STDOUT_FD
	mov rsi, [rsp + 8]
	mov rdx, [rsp]
	syscall

	cmp rax, -1
	je .write_failure

	add qword [rsp + 8], rax ; advance the pointer by the number of bytes written
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
;;; a signed 64-bit integer. Skips leading whitespace.
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
	lea rdi, [rel strbuf]
	call skip_spaces_rdi

	cmp byte [rdi], '-'
	je .negative
	xor r10d, r10d
	jmp .loop_begin
.negative:
	mov r10d, 1
	inc rdi
.loop_begin:
	cmp byte [rdi], '0'
	jb .loop_end
	cmp byte [rdi], '9'
	ja .loop_end

	movsx r8, byte [rdi]
	sub r8, '0'

	;; r9 = rax * 10
	lea r9, [rax + rax * 8]
	add r9, rax

	lea rax, [r8 + r9]
	inc rdi
	jmp .loop_begin
.loop_end:
	test r10d, r10d
	jz .done
	neg rax
.done:
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
;;         return n * sign;
;; }

;;; Procedure skip_spaces_rdi:
;;; If the string pointed to by RDI has spaces,
;;; increment RDI until it points to a non-space character.
;;; i.e., `while (*rdi == ' ' || (*rdi >= 9 || *rdi <= 13)) { rdi++; }`
skip_spaces_rdi:
.loop:
	cmp byte [rdi], ' '
	je .continue
	cmp byte [rdi], `\t` ; '\t' has ASCII value 9
	jb .done
	cmp byte [rdi], `\r` ; '\r' has ASCII value 13
	ja .done
.continue:
	inc rdi
	jmp .loop
.done:
	ret

;;; Procedure test_has_number:
;;; First, it ignores leading whitespace.
;;; Then, it returns 1 in RAX if strbuf starts with a byte between '0' and '9',
;;; or if it starts with a '-' and then a byte between '0' and '9'.
;;; Returns 0 otherwise.
test_has_number:
	xor eax, eax
	lea rdi, [rel strbuf]
	call skip_spaces_rdi
	cmp byte [rdi], '-'
	jne .test_num
	inc rdi
.test_num:
	cmp byte [rdi], '0'
	jb .no
	cmp byte [rdi], '9'
	ja .no
	inc eax
.no:
	ret

;;; Procedure bounds_check:
;;; If the number in RDI is within range [-25, 25] (inclusive),
;;; return 1 in RAX. Otherwise, return 0.
bounds_check:
	xor eax, eax
	cmp rdi, 25
	jg .no
	cmp rdi, -25
	jl .no
	inc eax ; within range
.no:
	ret
