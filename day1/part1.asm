format ELF64 executable

STDIN_FILENO  = 0
STDOUT_FILENO = 1
STDERR_FILENO = 2

O_RDONLY = 0
O_WRONLY = 1
O_RDWR   = 2
O_CREAT  = 4
O_TRUNC  = 8

SYS_read  = 0
SYS_write = 1
SYS_open  = 2
SYS_close = 3
SYS_exit  = 60

macro null {
    db 0
}

macro syscall1 number, arg1 {
    mov rax, number
    mov rdi, arg1
    syscall
}

macro syscall2 number, arg1, arg2 {
    mov rax, number
    mov rdi, arg1
    mov rsi, arg2
    syscall
}

macro syscall3 number, arg1, arg2, arg3 {
    mov rax, number
    mov rdi, arg1
    mov rsi, arg2
    mov rdx, arg3
    syscall
}

macro stack_reserve space {
    push rbp
    mov rbp, rsp
    sub rsp, space
}

macro stack_restore space {
    add rsp, space
    pop rbp
}

macro write fd, buf, len {
    syscall3 SYS_write, fd, buf, len
}

macro safe_write fd, buf, len {
    stack_reserve 32
    push rax
    push rdi
    push rsi
    push rdx
    syscall3 SYS_write, fd, buf, len
    pop rdx
    pop rsi
    pop rdi
    pop rax
    stack_restore 32
}

macro exit code {
    syscall1 SYS_exit, code
}

; from C for debugging and printing solution
; https://gitlab.com/tsoding/porth/-/raw/master/bootstrap/porth-linux-x86_64.fasm
print:
    mov     r9, -3689348814741910323
    sub     rsp, 40
    mov     BYTE [rsp+31], 10
    lea     rcx, [rsp+30]
.L2:
    mov     rax, rdi
    lea     r8, [rsp+32]
    mul     r9
    mov     rax, rdi
    sub     r8, rcx
    shr     rdx, 3
    lea     rsi, [rdx+rdx*4]
    add     rsi, rsi
    sub     rax, rsi
    add     eax, 48
    mov     BYTE [rcx], al
    mov     rax, rdi
    mov     rdi, rdx
    mov     rdx, rcx
    sub     rcx, 1
    cmp     rax, 9
    ja      .L2
    lea     rax, [rsp+32]
    mov     edi, 1
    sub     rdx, rax
    xor     eax, eax
    lea     rsi, [rsp+32+rdx]
    mov     rdx, r8
    mov     rax, 1
    syscall
    add     rsp, 40
    ret

stoi: ; value passed in rdi
    xor rax, rax
    mov rcx, rdi

.loop_start:
    mov dl, BYTE [rcx]

    cmp dl, 0x30
    jl .end
    cmp dl, 0x39
    jg .end

    imul rax, rax, 10

    sub dl, 0x30
    add rax, rdx

    inc rcx

    jmp .loop_start

.end:
    ret


read_entire_file: ; filename pointer passed in rdi
    stack_reserve 8

    syscall3 SYS_open, rdi, O_RDONLY, 0
    cmp rax, 0
    jl .failed

    mov [rbp-8], rax

    syscall3 SYS_read, [rbp-8], buffer, buffer_cap
    cmp rax, 0
    jl .failed

    mov [buffer_len], rax
    mov rdi, rax

    syscall1 SYS_close, [rbp-8]
.failed:
    stack_restore 8
    ret

parse_lists: ; pass buffer pointer in rdi, size of buffer in rsi,
             ; # of digits in rdx
    stack_reserve 16

    xor rcx, rcx ; line index
    lea r8, [list_one]
    lea r9, [list_two]
.loop:
    cmp rcx, rsi ; if index < buffer size
    jge .end

    ;safe_write STDERR_FILENO, ok_msg, ok_msg_len

    push rdi
    add rdi, rcx
    push rcx
    ;call stoi
    pop rcx
    pop rdi
    mov DWORD [r8], eax

    add rcx, rdx
    add rcx, 3

    jmp .loop
.end:
    stack_restore 16
    ret

entry _start
_start:
    mov rdi, input_file_path
    call read_entire_file ; move file into buffer
    cmp rax, 0
    jl .fail_read_entire_file

    mov rdi, buffer
    call parse_lists
    write STDERR_FILENO, ok_msg, ok_msg_len

    exit 0

.fail_read_entire_file:
    write STDERR_FILENO, fail_read_entire_file_msg, fail_read_entire_file_msg_len

    exit 69

input_file_path: db "input_example", 0

message: file "message.txt"

test_msg: db "123", 0

ok_msg: db "👆🤓🐭", 10
ok_msg_len = $-ok_msg

fail_read_entire_file_msg: db "Could not read file", 10
fail_read_entire_file_msg_len = $-fail_read_entire_file_msg

buffer: rb 20*1024
buffer_cap = $-buffer
buffer_len: rq 1

list_one: rd 1000
list_two: rd 1000
