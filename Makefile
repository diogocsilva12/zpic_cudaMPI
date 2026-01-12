# ---------------------------------------------------- #
# Makefile for CUDA implementation of ZPIC             #
# ---------------------------------------------------- #

BIN = zpic
CC = nvcc
LINKER = nvcc

SRC_DIR = src
LIB_DIR = lib
BUILD_DIR = build

# Host C files compiled via nvcc (as host code)
CFLAGS   = -O3 -g -std=c++11 -Wno-deprecated-gpu-targets -Xcompiler -Wall,-Wextra

# CUDA compilation flags
NCCFLAGS = -arch=sm_80 -O3 -Wno-deprecated-gpu-targets --use_fast_math -lineinfo -std=c++11 -Xcompiler -Wall,-Wextra

LDFLAGS = -lm
INC = -I$(LIB_DIR)

# Exclude the input directory from C_SOURCES
C_SOURCES  := $(shell find $(SRC_DIR) -type f -name '*.c'  ! -path "$(SRC_DIR)/input/*")
CU_SOURCES := $(shell find $(SRC_DIR) -type f -name '*.cu')
HEADERS    := $(shell find $(LIB_DIR) -type f -name '*.h')

C_OBJS  := $(patsubst $(SRC_DIR)/%.c,  $(BUILD_DIR)/%.o, $(C_SOURCES))
CU_OBJS := $(patsubst $(SRC_DIR)/%.cu, $(BUILD_DIR)/%.o, $(CU_SOURCES))

.PHONY: all clean run

all: $(BIN)

$(BIN): $(C_OBJS) $(CU_OBJS)
	$(LINKER) -o $@ $^ $(LDFLAGS)

$(BUILD_DIR)/%.o : $(SRC_DIR)/%.c $(HEADERS)
	@mkdir -p $(dir $@)
	$(CC) -c $< $(CFLAGS) $(INC) -o $@

$(BUILD_DIR)/%.o : $(SRC_DIR)/%.cu $(HEADERS)
	@mkdir -p $(dir $@)
	$(CC) -c $< $(NCCFLAGS) $(INC) -o $@

run:
	@{ \
		if command -v ml >/dev/null 2>&1; then \
			ml purge; \
			ml CUDA; \
		elif command -v module >/dev/null 2>&1; then \
			module purge; \
			module load CUDA; \
		else \
			echo "WARNING: module command not found; ensure CUDA module is loaded."; \
		fi; \
		$(MAKE) clean; \
		$(MAKE) all; \
		mkdir -p tests/results; \
		TIMESTAMP=$$(date +"%Y-%m-%d_%H-%M-%S"); \
		OUT="tests/results/run_$${TIMESTAMP}.txt"; \
		echo "----------------------------------------" | tee -a "$$OUT"; \
		echo "Running ./$(BIN) (log: $$OUT)" | tee -a "$$OUT"; \
		./$(BIN) 2>&1 | tee -a "$$OUT"; \
	}

clean:
	rm -rf $(BUILD_DIR) $(BIN)
