; Brainfuck interpreter
; FreeBSD x86_64 / Linux x86_64 (syscall番号を変更)
; Intel syntax (axx)
;
; build (FreeBSD):
;   python3 axx.py x86_64.axx bf.s -o bf.o --osabi FreeBSD && ld -o bf bf.o
;
; build (Linux):
;   syscall番号を Linux 用 (下記参照) に変更してから:
;   python3 axx.py x86_64.axx bf.s -o bf.o && ld -o bf bf.o
;
; ===== テープアクセスの方針 =====
; tape_a: .equ tape::abs32 と定義し、
; x86_64.axx の [!s\+r] パターンが 4バイト disp32 フィールドに
; R_X86_64_32 (絶対32bitアドレス) リロケーションを生成する。
;
; これにより [symbol+register] SIBアドレッシングが使用でき、
; r15 をテープインデックス (0オリジン) として扱える。
;
; レジスタ割り当て:
;   r12 = fd (ファイルオープン時のみ)
;   r13 = プログラム長 (バイト数)
;   r14 = 命令ポインタ (prog_buf インデックス)
;   r15 = テープインデックス (tape[r15] が現在セル)

.global _start

; --- FreeBSD syscall番号 ---
; (Linux: EXIT=60, READ=0, WRITE=1, OPEN=2, CLOSE=3)
SYS_EXIT:  .equ  1
SYS_READ:  .equ  3
SYS_WRITE: .equ  4
SYS_OPEN:  .equ  5
SYS_CLOSE: .equ  6

; SIB abs32 エイリアス:
;   INCB/DECB/CMPB [tape_a+r15] が R_X86_64_32 リロケーションを生成する
tape_a: .equ tape::abs32

.section .text

_start:
    ; System V AMD64 ABI (FreeBSD/Linux 共通):
    ;   プロセスエントリ時 RSP → argc, RSP+8 → argv[0], RSP+16 → argv[1]
    mov  r8, rsp
    mov dword eax, [r8]         ; eax = argc
    cmp dword eax, 2
    jge  _open_file

    ; 引数不足: 使い方を stderr に表示して終了
    mov rax, SYS_WRITE
    mov rdi, 2
    lea rsi, [RIP+usage]
    mov rdx, usage_len
    syscall
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

_open_file:
    mov rax, r8
    add rax, 16            ; &argv[1]
    mov rdi, [rax]         ; argv[1] = ファイル名ポインタ
    mov rax, SYS_OPEN
    xor rsi, rsi           ; O_RDONLY = 0
    xor rdx, rdx
    syscall
    js  exit_error         ; FreeBSD: SF=1(負値)=エラー (Linux も同様)
    mov r12, rax           ; r12 = fd

    ; ファイルを prog_buf に一括読み込み
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [RIP+prog_buf]
    mov rdx, 1048576
    syscall
    mov r13, rax           ; r13 = プログラム長

    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    ; 初期化
    xor r14, r14           ; 命令ポインタ = 0
    xor r15, r15           ; テープインデックス = 0

main_loop:
    cmp r14, r13
    jge exit

    ; 現在の BF 命令を al に読み込む
    lea rax, [RIP+prog_buf]
    add rax, r14
    mov byte al, [rax]

    cmp byte al, '>'
    je   op_inc_ptr
    cmp byte al, '<'
    je   op_dec_ptr
    cmp byte al, '+'
    je   op_inc_val
    cmp byte al, '-'
    je   op_dec_val
    cmp byte al, '.'
    je   op_output
    cmp byte al, ','
    je   op_input
    cmp byte al, '['
    je   op_loop_start
    cmp byte al, ']'
    je   op_loop_end

next:
    inc r14
    jmp main_loop

; ===== Brainfuck 命令実装 =====

op_inc_ptr:
    inc r15                ; > : テープポインタを+1
    jmp next

op_dec_ptr:
    dec r15                ; < : テープポインタを-1
    jmp next

op_inc_val:
    inc byte [tape_a+r15]      ; + : 現在セルをインクリメント [SIB R_X86_64_32]
    jmp next

op_dec_val:
    dec byte [tape_a+r15]      ; - : 現在セルをデクリメント [SIB R_X86_64_32]
    jmp next

op_output:
    ; . : write(1, &tape[r15], 1)
    ; rsi = tape の絶対アドレス + r15 (インデックス)
    mov rsi, tape_a        ; rsi = tape の絶対アドレス (imm64, R_X86_64_64)
    add rsi, r15
    mov rdx, 1
    mov rax, SYS_WRITE
    mov rdi, 1
    syscall
    jmp next

op_input:
    ; , : read(0, &tape[r15], 1)
    mov rsi, tape_a
    add rsi, r15
    mov rdx, 1
    mov rax, SYS_READ
    xor rdi, rdi
    syscall
    cmp rax, 0
    jle exit               ; EOF またはエラー
    jmp next

op_loop_start:
    ; [ : 現在セルが 0 なら対応する ']' の直後へジャンプ
    cmp byte [tape_a+r15], 0   ; [SIB R_X86_64_32]
    jne  next

    mov rcx, 1             ; ネスト深度
.find_end:
    inc r14
    cmp r14, r13
    jge exit
    lea rax, [RIP+prog_buf]
    add rax, r14
    mov byte al, [rax]
    cmp byte al, '['
    je   .inc_depth
    cmp byte al, ']'
    je   .dec_depth
    jmp  .find_end
.inc_depth:
    inc rcx
    jmp .find_end
.dec_depth:
    dec rcx
    cmp rcx, 0
    jne .find_end
    jmp next

op_loop_end:
    ; ] : 現在セルが 0 でなければ対応する '[' の直後へ戻る
    cmp byte [tape_a+r15], 0   ; [SIB R_X86_64_32]
    je   next

    mov rcx, 1             ; ネスト深度
.find_start:
    cmp r14, 0
    jle exit
    dec r14
    lea rax, [RIP+prog_buf]
    add rax, r14
    mov byte al, [rax]
    cmp byte al, ']'
    je   .inc_depth2
    cmp byte al, '['
    je   .dec_depth2
    jmp  .find_start
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

.section .data
usage:     .ascii "Usage: bf <file>",10
usage_len: .equ $$ - usage
.endsection

.section .bss
tape:     .zero 65536
prog_buf: .resb 1048576
.endsection

