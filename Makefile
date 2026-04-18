# panda-hide KPM 模块 Makefile
#
# 使用前需设置以下环境变量（或通过命令行传入）：
#   TARGET_COMPILE  — AArch64 交叉编译工具链前缀
#   KP_DIR          — KernelPatch 源码目录
#
# 示例：
#   make TARGET_COMPILE=aarch64-none-elf- KP_DIR=/path/to/KernelPatch
#   make push    # adb push 到手机

TARGET_COMPILE ?= aarch64-none-elf-
KP_DIR         ?= ../../KernelPatch

CC = $(TARGET_COMPILE)gcc
LD = $(TARGET_COMPILE)ld

INCLUDE_DIRS := . include patch/include linux/include linux/arch/arm64/include linux/tools/arch/arm64/include
INCLUDE_FLAGS := $(foreach dir,$(INCLUDE_DIRS),-I$(KP_DIR)/kernel/$(dir)) -I./src

CFLAGS += -std=gnu11 -O2

SRCS += ./src/main.c
SRCS += ./src/debugger_hide.c
SRCS += ./src/frida_hide.c
SRCS += ./src/openat_hide.c
SRCS += ./src/net_hide.c
SRCS += ./src/mem_hide.c

OBJS := $(SRCS:.c=.o)

all: panda-hide.kpm

push: panda-hide.kpm
	adb push panda-hide.kpm /sdcard/Download/

panda-hide.kpm: ${OBJS}
	${CC} -r -o $@ $^
	find . -name "*.o" | xargs rm -f

%.o: %.c
	${CC} $(CFLAGS) $(INCLUDE_FLAGS) -c -o $@ $<

.PHONY: clean all push
clean:
	rm -rf *.kpm
	find . -name "*.o" | xargs rm -f
