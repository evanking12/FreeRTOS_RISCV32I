#!/usr/bin/env python3
"""
UART Firmware Uploader for RISC-V Bootloader
Usage: python upload.py <COM_PORT> <firmware.bin>
Example: python upload.py COM3 app.bin
"""

import serial
import sys
import time
import struct

def main():
    if len(sys.argv) < 3:
        print("Usage: python upload.py <COM_PORT> <firmware.bin>")
        print("Example: python upload.py COM3 app.bin")
        sys.exit(1)
    
    port = sys.argv[1]
    firmware_path = sys.argv[2]
    
    # Read firmware
    print(f"Reading firmware from {firmware_path}...")
    with open(firmware_path, "rb") as f:
        firmware = f.read()
    
    size = len(firmware)
    print(f"Firmware size: {size} bytes ({size/1024:.1f} KB)")
    
    if size > 124 * 1024:
        print("ERROR: Firmware too large! Max 124KB")
        sys.exit(1)
    
    # Open serial port
    print(f"Opening {port} at 115200 baud...")
    try:
        ser = serial.Serial(port, 115200, timeout=1)
    except Exception as e:
        print(f"ERROR: Could not open {port}: {e}")
        sys.exit(1)
    
    # Clear any pending data
    ser.reset_input_buffer()
    time.sleep(0.1)
    
    # Send sync byte
    print("Sending sync byte 'U' (0x55)...")
    ser.write(b'U')
    
    # Wait for ACK
    print("Waiting for ACK...")
    ack = ser.read(1)
    if ack != b'\x06':
        print(f"ERROR: Expected ACK (0x06), got: {ack.hex() if ack else 'nothing'}")
        print("Make sure the FPGA is running the bootloader!")
        ser.close()
        sys.exit(1)
    print("Got ACK!")
    
    # Send length (4 bytes, little endian)
    print(f"Sending length: {size} bytes...")
    ser.write(struct.pack('<I', size))
    
    # Wait for ACK
    ack = ser.read(1)
    if ack != b'\x06':
        print(f"ERROR: Length ACK failed, got: {ack.hex() if ack else 'nothing'}")
        ser.close()
        sys.exit(1)
    print("Length acknowledged!")
    
    # Send firmware
    print("Uploading firmware...")
    start_time = time.time()
    
    chunk_size = 256
    for i in range(0, size, chunk_size):
        chunk = firmware[i:i+chunk_size]
        ser.write(chunk)
        
        # Progress bar
        progress = (i + len(chunk)) / size * 100
        bar_len = 40
        filled = int(bar_len * (i + len(chunk)) / size)
        bar = '=' * filled + '-' * (bar_len - filled)
        print(f"\r[{bar}] {progress:5.1f}%", end='', flush=True)
        
        # Small delay to avoid buffer overflow
        time.sleep(0.001)
    
    print()
    
    # Wait for final ACK
    print("Waiting for completion ACK...")
    ack = ser.read(1)
    if ack != b'\x06':
        print(f"WARNING: Final ACK not received, got: {ack.hex() if ack else 'nothing'}")
    else:
        print("Upload complete!")
    
    elapsed = time.time() - start_time
    print(f"Transfer time: {elapsed:.2f}s ({size/elapsed/1024:.1f} KB/s)")
    
    # Read any output from the firmware
    print("\n--- Firmware Output ---")
    try:
        while True:
            data = ser.read(100)
            if data:
                print(data.decode('utf-8', errors='replace'), end='', flush=True)
            else:
                time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n\nUpload session ended.")
    
    ser.close()

if __name__ == "__main__":
    main()

