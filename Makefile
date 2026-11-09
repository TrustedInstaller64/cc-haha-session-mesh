SWIFT ?= swift
CONFIGURATION ?= release

RUNTIME_DIR := $(HOME)/.claude/session-mesh
BIN_DIR := $(RUNTIME_DIR)/bin
INSTALLED_BINARY := $(BIN_DIR)/session-mesh
BUILD_BINARY := .build/$(CONFIGURATION)/session-mesh

.PHONY: build test install uninstall doctor

build:
	$(SWIFT) build -c $(CONFIGURATION)

test:
	$(SWIFT) test

install: build
	install -d -m 700 "$(BIN_DIR)"
	install -m 755 "$(BUILD_BINARY)" "$(INSTALLED_BINARY)"
	@echo "Installed $(INSTALLED_BINARY)"
	@echo "Hooks were not modified; run 'session-mesh install' to merge them."

uninstall:
	@echo "Removing $(INSTALLED_BINARY); hooks are left unchanged."
	@echo "Run 'session-mesh uninstall' before this step if hooks should be reverted."
	rm -f "$(INSTALLED_BINARY)"

doctor: build
	$(BUILD_BINARY) doctor
