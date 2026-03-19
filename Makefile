# Sindarin SQL Server Package - Makefile

.PHONY: all test build-libs install-libs clean help

# Disable implicit rules for .sn.c files (compiled by the Sindarin compiler)
%.sn: %.sn.c
	@:

#------------------------------------------------------------------------------
# Platform Detection
#------------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
    PLATFORM := windows
    EXE_EXT  := .exe
    MKDIR    := mkdir
else
    UNAME_S := $(shell uname -s 2>/dev/null || echo Unknown)
    ifeq ($(UNAME_S),Darwin)
        PLATFORM := darwin
    else
        PLATFORM := linux
    endif
    EXE_EXT :=
    MKDIR   := mkdir -p
endif

#------------------------------------------------------------------------------
# vcpkg triplet / CMake preset (for build-libs)
#------------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
    VCPKG_TRIPLET := x64-mingw-static
    CMAKE_PRESET  := ci-windows
else ifeq ($(PLATFORM),darwin)
    ifeq ($(shell uname -m),arm64)
        VCPKG_TRIPLET := arm64-osx
        CMAKE_PRESET  := ci-darwin-arm64
    else
        VCPKG_TRIPLET := x64-osx
        CMAKE_PRESET  := ci-darwin
    endif
else
    ifeq ($(shell uname -m),aarch64)
        VCPKG_TRIPLET := arm64-linux
        CMAKE_PRESET  := ci-linux-arm64
    else
        VCPKG_TRIPLET := x64-linux
        CMAKE_PRESET  := ci-linux
    endif
endif

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
BIN_DIR := bin
SN      ?= sn

SRC_SOURCES := $(wildcard src/*.sn) $(wildcard src/*.sn.c)

TEST_SRCS := $(wildcard tests/test_*.sn)
TEST_BINS := $(patsubst tests/%.sn,$(BIN_DIR)/%$(EXE_EXT),$(TEST_SRCS))

#------------------------------------------------------------------------------
# Targets
#------------------------------------------------------------------------------
all: test

test: $(TEST_BINS)
	@echo "Running tests..."
	@failed=0; \
	for t in $(TEST_BINS); do \
	    printf "  %-50s" "$$t"; \
	    if $$t; then \
	        echo "PASS"; \
	    else \
	        echo "FAIL"; \
	        failed=1; \
	    fi; \
	done; \
	if [ $$failed -eq 0 ]; then \
	    echo "All tests passed."; \
	else \
	    echo "Some tests failed."; \
	    exit 1; \
	fi

$(BIN_DIR):
	@$(MKDIR) $(BIN_DIR)

$(BIN_DIR)/%$(EXE_EXT): tests/%.sn $(SRC_SOURCES) | $(BIN_DIR)
	@$(SN) $< -o $@ -l 1

build-libs:
	@echo "Building FreeTDS libraries for $(PLATFORM) ($(VCPKG_TRIPLET))..."
	@if [ ! -d "vcpkg" ]; then git clone https://github.com/microsoft/vcpkg.git; fi
	@./vcpkg/bootstrap-vcpkg.sh -disableMetrics
	@./vcpkg/vcpkg install --triplet=$(VCPKG_TRIPLET) \
	    --x-manifest-root=. \
	    --x-install-root=./vcpkg_installed
	@cmake --preset $(CMAKE_PRESET) \
	    -DVCPKG_TARGET_TRIPLET=$(VCPKG_TRIPLET) \
	    -DVCPKG_INSTALLED_DIR=$(shell pwd)/vcpkg_installed
	@cmake --build --preset $(CMAKE_PRESET)
	@echo "Libraries built in libs/$(PLATFORM)/"

install-libs:
	@bash scripts/install.sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BIN_DIR) .sn
	@echo "Clean complete."

help:
	@echo "Sindarin SQL Server Package"
	@echo ""
	@echo "Targets:"
	@echo "  make test          Build and run all tests"
	@echo "  make build-libs    Build FreeTDS libraries from source (requires cmake/vcpkg)"
	@echo "  make install-libs  Download pre-built libraries from GitHub releases"
	@echo "  make clean         Remove build artifacts"
	@echo "  make help          Show this help"
	@echo ""
	@echo "Platform: $(PLATFORM)"
