# FreeRTOS Feature Demos

Simple demonstrations of FreeRTOS features running on the custom RISC-V CPU.

## Available Demos

### 1. Mutex Demo (`main_mutex_demo.c`)
Demonstrates **mutex** for shared resource protection.
- Two tasks compete for UART access
- Mutex ensures clean, non-garbled output
- Shows `xSemaphoreCreateMutex()`, `xSemaphoreTake()`, `xSemaphoreGive()`

### 2. Queue Demo (`main_queue_demo.c`)
Demonstrates **queue** for inter-task communication.
- Producer task sends data to queue
- Consumer task receives and processes
- Shows `xQueueCreate()`, `xQueueSend()`, `xQueueReceive()`

## Building

To build a demo, copy the desired `main_*.c` to `../main.c` and run the build:

```bash
# From firmware/ directory:
cp demos/main_mutex_demo.c main.c
./build_debug.sh freertos

# Or for queue demo:
cp demos/main_queue_demo.c main.c
./build_debug.sh freertos
```

## Expected Output

### Mutex Demo
```
================================
  FreeRTOS MUTEX Demo
  Custom RISC-V CPU
================================

[OK] Mutex created!

[A] Mutex acquired! Count: 0
[B] Mutex acquired! Count: 0
[A] Mutex acquired! Count: 1
[B] Mutex acquired! Count: 1
...
```

### Queue Demo
```
================================
  FreeRTOS QUEUE Demo
  Custom RISC-V CPU
================================

[OK] Queue created (5 slots)!

[Consumer] Received from P: 0
[Consumer] Received from P: 1
[Consumer] Received from P: 2
...
```

## Features Used

| Feature | API | Demo |
|---------|-----|------|
| Mutex | `xSemaphoreCreateMutex()` | ✅ Mutex Demo |
| Binary Semaphore | `xSemaphoreCreateBinary()` | (similar to mutex) |
| Queue | `xQueueCreate()` | ✅ Queue Demo |
| Tasks | `xTaskCreate()` | ✅ Both |
| Yielding | `taskYIELD()` | ✅ Both |

