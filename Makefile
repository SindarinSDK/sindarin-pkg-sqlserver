# Sindarin SQL Server Package - Makefile

.PHONY: all test hooks build-libs install-libs clean help

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

test: hooks $(TEST_BINS)
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

FREETDS_SRC   := /tmp/freetds-src
FREETDS_BUILD := /tmp/freetds-build
FREETDS_INST  := /tmp/freetds-install

build-libs:
	@echo "Building FreeTDS from source for $(PLATFORM)..."
	@if [ ! -d "$(FREETDS_SRC)" ]; then \
	    git clone --depth=1 --branch Branch-1_4 https://github.com/FreeTDS/freetds.git $(FREETDS_SRC); \
	fi
	@cmake -S $(FREETDS_SRC) -B $(FREETDS_BUILD) \
	    -G Ninja \
	    -DCMAKE_BUILD_TYPE=Release \
	    -DCMAKE_INSTALL_PREFIX=$(FREETDS_INST) \
	    -DBUILD_SHARED_LIBS=OFF \
	    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	    -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON \
	    -DENABLE_ODBC=OFF
	@cmake --build $(FREETDS_BUILD) -j
	@cmake --install $(FREETDS_BUILD)
	@cmake -S . -B build/package \
	    -DFREETDS_INSTALL_PREFIX=$(FREETDS_INST)
	@cmake --build build/package
	@echo "Libraries built in libs/$(PLATFORM)/"

install-libs:
	@bash scripts/install.sh

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BIN_DIR) .sn
	@echo "Clean complete."

#------------------------------------------------------------------------------
# hooks - Configure git to use tracked pre-commit hooks
#------------------------------------------------------------------------------
hooks:
	@git config core.hooksPath .githooks 2>/dev/null || true

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
