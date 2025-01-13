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

macro save_number list {
    push rdi
    add rdi, rcx
    push rcx
    push rdx
    call stoi
    pop rdx
    pop rcx
    pop rdi
    if list = 1
        mov DWORD [r8], eax ; place result of stoi into list and add to r8 index
        add r8, 4
    else if list = 2
        mov DWORD [r9], eax
        add r9, 4
    end if
}

parse_lists: ; pass buffer pointer in rdi, size of buffer in rsi,
             ; number of digits in rdx
    stack_reserve 24

    xor rcx, rcx ; line index
    lea r8, [list_one]
    lea r9, [list_two]
.loop:
    cmp rcx, rsi ; if index >= buffer size, end
    jge .end

    save_number 1

    ; Move index forward by number of digits + 3 spaces
    add rcx, rdx
    add rcx, 3

    save_number 2

    ; Move index forward by number of digits + newline
    add rcx, rdx
    add rcx, 1

    jmp .loop
.end:
    sub r8, list_one
    sub r9, list_two

    shr r8, 2 ; size calculation (dividing by 4)
    shr r9, 2

    mov [list_one_size], r8
    mov [list_two_size], r9

    stack_restore 24
    ret

; slow O(n^2) solution bcs I'm lazy
macro calc_sim l1, l2, size {
    xor rcx, rcx ; counter
    xor rax, rax ; solution
    stack_reserve 8

.loop:
    xor rdx, rdx
    mov edx, DWORD [l1 + rcx*4]
    xor r8, r8 ; count # of matches

    push rcx ; save current counter
    xor rcx, rcx ; new counter
.inner_loop:
    mov r9d, DWORD [l2 + rcx*4]

    xor r10, r10 ; initialize 0 register
    mov r11, 1 ; and 1 register for cmove
    cmp edx, r9d ; if right list value = left list value
    cmove r10, r11 ; move 1 into r10
    add r8, r10 ; add r10 (0, or 1) to r8

    inc rcx
    cmp rcx, size
    jl .inner_loop
    pop rcx ; restore outer loop counter

    ; r8 now contains the number of occurences
    imul r8, rdx
    add rax, r8

    inc rcx
    cmp rcx, size
    jl .loop

    stack_restore 8
}

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

    mov rdi, buffer
    mov rsi, [buffer_len]
    mov rdx, 5 ; number of digits in each input number
    call parse_lists

    mov r12, list_one
    mov r13, list_two
    mov r14, [list_one_size]
    calc_sim r12, r13, r14

    mov rdi, rax
    call print

    ;write STDOUT_FILENO, list_one_name, list_name_len
    ;print_list 1, 6 ; size must be hardcoded for macro
    ;
    ;write STDOUT_FILENO, list_two_name, list_name_len
    ;print_list 2, 6 ; size must be hardcoded for macro

    exit 0

.fail_read_entire_file:
    write STDERR_FILENO, fail_read_entire_file_msg, fail_read_entire_file_msg_len

    exit 69

input_file_path: db "input", 0

message: file "message.txt"

test_msg: db "123", 0

ok_msg: db "👆🤓🐭", 10
ok_msg_len = $-ok_msg

fail_read_entire_file_msg: db "Could not read file", 10
fail_read_entire_file_msg_len = $-fail_read_entire_file_msg

buffer: rb 14*1024
buffer_cap = $-buffer
buffer_len: rq 1

list_one: rd 1000
list_one_size: rq 1
list_two: rd 1000
list_two_size: rq 1

list_one_name: db "List 1:", 10
list_two_name: db "List 2:", 10
list_name_len = $-list_two_name
