    .section .boot, "ax"
    .globl _boot_start
    .globl _boot_entry

# ============================================================================
#  UART Bootloader for RISC-V
#  - Waits for firmware upload via UART
#  - Writes to RAM starting at 0x1000
#  - Jumps to firmware
# ============================================================================

.equ UART_TX_ADDR,    0xFFFFFFF0
.equ UART_STAT_ADDR,  0xFFFFFFF4
.equ FIRMWARE_BASE,   0x00001000
.equ FIRMWARE_MAX,    0x0001F000   # 124KB max firmware

_boot_start:
    # Initialize stack
    lui     sp, 0x20              # sp = 0x20000

    # Print boot message
    la      a0, boot_msg
    jal     uart_puts
    
    # Print "Waiting for upload..."
    la      a0, wait_msg
    jal     uart_puts

    # Wait for sync byte (0x55 = 'U')
wait_sync:
    jal     uart_getc             # a0 = received byte
    li      t0, 0x55              # 'U' sync byte
    bne     a0, t0, wait_sync
    
    # Got sync, send ACK
    li      a0, 0x06              # ACK
    jal     uart_putc
    
    # Receive 4-byte length (little endian)
    jal     uart_getc
    mv      s0, a0                # s0 = byte 0
    jal     uart_getc
    slli    t0, a0, 8
    or      s0, s0, t0            # s0 |= byte1 << 8
    jal     uart_getc
    slli    t0, a0, 16
    or      s0, s0, t0            # s0 |= byte2 << 16
    jal     uart_getc
    slli    t0, a0, 24
    or      s0, s0, t0            # s0 |= byte3 << 24
    
    # s0 = firmware length in bytes
    # Validate length
    li      t0, FIRMWARE_MAX
    bgtu    s0, t0, length_error
    beqz    s0, length_error
    
    # Send ACK for length
    li      a0, 0x06
    jal     uart_putc
    
    # Print "Receiving..."
    la      a0, recv_msg
    jal     uart_puts
    
    # Receive firmware
    li      s1, FIRMWARE_BASE     # s1 = destination pointer
    mv      s2, s0                # s2 = bytes remaining
    
receive_loop:
    beqz    s2, receive_done
    
    jal     uart_getc             # a0 = byte
    sb      a0, 0(s1)             # store byte
    addi    s1, s1, 1             # ptr++
    addi    s2, s2, -1            # remaining--
    
    # Progress indicator every 1KB
    andi    t0, s1, 0x3FF
    bnez    t0, receive_loop
    li      a0, '.'
    jal     uart_putc
    j       receive_loop

receive_done:
    # Send final ACK
    li      a0, 0x06
    jal     uart_putc
    
    # Print success
    la      a0, done_msg
    jal     uart_puts
    
    # Print "Jumping to firmware..."
    la      a0, jump_msg
    jal     uart_puts
    
    # Small delay for UART to finish
    li      t0, 100000
delay:
    addi    t0, t0, -1
    bnez    t0, delay
    
    # Jump to firmware!
    li      t0, FIRMWARE_BASE
    jr      t0

length_error:
    la      a0, err_msg
    jal     uart_puts
    j       wait_sync             # Try again

# ============================================================================
#  UART Functions
# ============================================================================

# uart_putc: Send byte in a0
uart_putc:
    li      t1, UART_STAT_ADDR
1:  lw      t2, 0(t1)             # read status
    andi    t2, t2, 0x3           # check TX busy/full
    bnez    t2, 1b
    li      t1, UART_TX_ADDR
    sw      a0, 0(t1)
    ret

# uart_puts: Send string at a0
uart_puts:
    mv      t3, ra                # save return address
    mv      t4, a0                # save string pointer
1:  lbu     a0, 0(t4)
    beqz    a0, 2f
    jal     uart_putc
    addi    t4, t4, 1
    j       1b
2:  mv      ra, t3
    ret

# uart_getc: Receive byte, return in a0
uart_getc:
    li      t1, UART_STAT_ADDR
1:  lw      t2, 0(t1)
    andi    t2, t2, 0x4           # check RX valid bit
    beqz    t2, 1b
    li      t1, 0xFFFFFFF8        # UART RX data address
    lw      a0, 0(t1)
    andi    a0, a0, 0xFF
    ret

# ============================================================================
#  Strings
# ============================================================================
    .section .rodata
boot_msg:
    .asciz "\r\n\r\n=== RISC-V UART Bootloader v1.0 ===\r\n"
wait_msg:
    .asciz "Waiting for firmware upload (send 'U' to start)...\r\n"
recv_msg:
    .asciz "Receiving firmware"
done_msg:
    .asciz "\r\nUpload complete!\r\n"
jump_msg:
    .asciz "Jumping to firmware at 0x1000...\r\n"
err_msg:
    .asciz "\r\nERROR: Invalid length!\r\n"

