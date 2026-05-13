; Brainfuck interpreter
; FreeBSD x86_64
; Pure syscall
; Intel syntax (axx)

; build:
;   python3 axx.py x86_64.axx bf.s -o bf.o --osabi FreeBSD
;   ld -o bf bf.o

.global _start

SYS_EXIT:  .equ   1
SYS_READ:  .equ   3
SYS_WRITE: .equ   4
SYS_OPEN:  .equ   5
SYS_CLOSE: .equ   6

.section .data
usage:      .ascii "Usage: bf <file>",10
usage_len:  .equ $$ - usage
.endsection

.section .bss
tape:      .zero 65536
prog_buf:  .zero 1048576
.endsection

.section .text

_start:
    mov  r8, rdi               ; r8 = &argc
    movd  eax, [r8]            ; eax = argc
    cmpd  eax, 2
    jge   _open_file
    mov rax, SYS_WRITE
    mov rdi, 2                 ; stderr
    lea rsi,[RIP+usage]
    mov rdx, usage_len
    syscall

    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

_open_file:
    mov rax, r8
    add rax, 16                ; r8+8=argv[0], r8+16=argv[1]
    mov rdi, [rax]             ; rdi = argv[1]
    mov rax, SYS_OPEN
    xor rsi, rsi               ; O_RDONLY = 0
    xor rdx, rdx               ; mode = 0
    syscall
    jc  exit_error
    mov r12, rax               ; r12 = fd

    ; ファイルを丸ごと読み込む
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, prog_buf
    mov rdx, 1048576
    syscall
    mov r13, rax

    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    ; 初期化
    xor r14, r14
    lea r15, [RIP+tape]
main_loop:
    cmp r14, r13
    jge exit

    mov rax, prog_buf
    add rax, r14
    movb al, [rax]

    cmpb al, '>'
    je op_inc_ptr
    cmpb al, '<'
    je op_dec_ptr
    cmpb al, '+'
    je op_inc_val
    cmpb al, '-'
    je op_dec_val
    cmpb al, '.'
    je op_output
    cmpb al, ','
    je op_input
    cmpb al, '['
    je op_loop_start
    cmpb al, ']'
    je op_loop_end

next:
    inc r14
    jmp main_loop

; ----- operations -----

op_inc_ptr:
    inc r15
    jmp next

op_dec_ptr:
    dec r15
    jmp next

op_inc_val:
    incb [r15]
    jmp next

op_dec_val:
    decb [r15]
    jmp next

op_output:
    mov rax, SYS_WRITE
    mov rdi, 1                 ; stdout
    mov rsi, r15
    mov rdx, 1
    syscall
    jmp next

op_input:
    mov rax, SYS_READ
    mov rdi, 0                 ; stdin
    mov rsi, r15
    mov rdx, 1
    syscall
    cmp rax, 0
    jle exit
    jmp next

; ----- loops -----

op_loop_start:
    cmpb [r15], 0
    jne next

    mov rcx, 1
.find_end:
    inc r14
    cmp r14, r13
    jge exit

    mov rax, prog_buf
    add rax, r14
    movb al, [rax]
    cmpb al, '['
    je .inc_depth
    cmpb al, ']'
    je .dec_depth
    jmp .find_end

.inc_depth:
    inc rcx
    jmp .find_end

.dec_depth:
    dec rcx
    cmp rcx, 0
    jne .find_end
    jmp next

op_loop_end:
    cmpb [r15], 0
    je next

    mov rcx, 1
.find_start:
    cmp r14, 0
    jle exit
    dec r14
    mov rax, prog_buf
    add rax, r14
    movb al, [rax]
    cmpb al, ']'
    je .inc_depth2
    cmpb al, '['
    je .dec_depth2
    jmp .find_start

.inc_depth2:
    inc rcx
    jmp .find_start

.dec_depth2:
    dec rcx
    cmp rcx, 0
    jne .find_start
    jmp next

exit_error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
