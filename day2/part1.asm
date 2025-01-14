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

macro safe_write fd, buf, len { ; for debugging
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

macro save_all { ; saves all volitile registers, useful for debugging
    stack_reserve 9*8
    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    push r10
    push r11
}

macro restore_all { ; restores all volitile registers
    pop rax
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r8
    pop r9
    pop r10
    pop r11
    stack_restore 9*8
}

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

get_report: ; pointer to report string at rsi
    xor rcx, rcx
    xor rax, rax
    dec rsi
.loop:
    inc rsi
    mov dil, BYTE [rsi]
    cmp dil, 0x0a ; new line -> goto end
    je .end
    cmp dil, 0x20 ; ' ' -> we are done w/t current number
    je .space

    imul rax, 10
    sub dil, 0x30
    add rax, rdi

    jmp .loop

.space:
    mov [report+rcx], al
    inc rcx
    xor rax, rax
    jmp .loop
.end:
    mov [report+rcx], al
    inc rcx
    inc rsi ; inc rsi to now align w/t the next report
    mov BYTE [report_len], cl
    ret

macro print_list list, list_size {
    i = 0
    repeat list_size ; this creates binaries w/t 1000s of repreated lines lol
        if list = 1
            mov edi, DWORD [list_one + i*4]
        else if list = 2
            mov edi, DWORD [list_two + i*4]
        end if
        call print
        i = i + 1
    end repeat
}

entry _start
_start:
    mov rdi, input_file_path
    call read_entire_file ; move file into buffer
    cmp rax, 0
    jl .fail_read_entire_file

    lea rsi, [buffer]
    xor rbx, rbx ; <- solution counter
    mov r15, [buffer_len]
    lea r15, [rsi+r15]
    ; here we loop over file buffer
.file_loop:
    call get_report
    ; get_report updates rsi to point at the next line
    xor rcx, rcx
    xor rax, rax
    xor r8, r8
    mov r14b, BYTE [report_len]
    sub r14b, 1
.report_loop:
    mov al, BYTE [report+rcx]
    mov dl, BYTE [report+rcx+1]

    sub al, dl
    ; check for difference > 3
    cmp al, -3
    jl .incorrect_report
    cmp al, 3
    jg .incorrect_report
    test al, al
    jz .incorrect_report
    ; check for continuous increment or decrement
    shr al, 7   ; will result in 0b1... -> 0x01 or 0b0... -> 0x00
    sub r8b, al ; if it was negative, -1
    test al, al ; test to set ZF flag
    setz al     ; if al is 0, it becomes 1, else it becomes 0
    add r8b, al ; add if it was 0 (aka positive), 1

    inc rcx
    cmp cl, r14b
    jl .report_loop
.end_report_loop:
    ; we expect to increment or decrement (report_len - 1) times
    mov r9b, r8b
    neg r8b
    cmovs r8w, r9w ; abs(r8b)

    add r8b, 1
    cmp r8b, [report_len]
    jne .incorrect_report


    inc rbx ; we have a correct report
.incorrect_report:
    cmp rsi, r15
    jl .file_loop

    mov rdi, rbx
    call print

    exit 0

.fail_read_entire_file:
    write STDERR_FILENO, fail_read_entire_file_msg, fail_read_entire_file_msg_len

    exit 69

input_file_path: db "input", 0

ok_msg: db "👆🤓🐭", 10
ok_msg_len = $-ok_msg

fail_read_entire_file_msg: db "Could not read file", 10
fail_read_entire_file_msg_len = $-fail_read_entire_file_msg

incorrect: db "Incorrect", 10
incorrect_len = $-incorrect

buffer: rb 20*1024
buffer_cap = $-buffer
buffer_len: rq 1

report: rb 10
report_len: rb 1
