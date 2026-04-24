include ./Makefile.Common

BASE_SPACE:=$(shell pwd)
BUILD_SPACE:=$(BASE_SPACE)/build
OTELCOL_VERSION="UNSET" # run recipe set-otelcol-version to get this
GIT_SHA=$(shell git rev-parse HEAD)
GOARCH ?= amd64
GOBUILD=GO111MODULE=on CGO_ENABLED=0 installsuffix=cgo go build -trimpath$(if ${BUILDTAGS}, -tags "${BUILDTAGS}",)
BUILD_INFO_IMPORT_PATH=main

LDFLAGS=-ldflags "-s -w -X $(BUILD_INFO_IMPORT_PATH).GitHash=$(GIT_SHA) -X $(BUILD_INFO_IMPORT_PATH).Version=$(OTELCOL_VERSION) \
-X github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awsxrayexporter.collectorDistribution=opentelemetry-collector-lambda"

TOOLS_MOD_DIR := ./internal/tools
ALL_GO_MOD_DIRS := $(shell find . -type f -name 'go.mod' -exec dirname {} \; | sort)
OTEL_GO_MOD_DIRS := $(filter-out $(TOOLS_MOD_DIR), $(ALL_GO_MOD_DIRS))
GOMODULES = $(OTEL_GO_MOD_DIRS) $(PWD)
TIDY_MODULES = $(ALL_GO_MOD_DIRS) $(PWD)
MODULES ?= $(GOMODULES)

# Define a delegation target for each module
.PHONY: $(GOMODULES)
$(GOMODULES):
	@echo "Running target '$(TARGET)' in module '$@'"
	$(MAKE) -C $@ $(TARGET)

# Triggers each module's delegation target, continuing through all modules even on failure
.PHONY: for-all-target
for-all-target:
	@if [ -z "$(TARGET)" ]; then echo "ERROR: TARGET is empty; specify a target to run across modules" >&2; exit 1; fi; \
	err=0; for dir in $(MODULES); do \
		echo "Running target '$(TARGET)' in module '$$dir'"; \
		$(MAKE) -C $$dir $(TARGET) || err=$$?; \
	done; exit $$err

.PHONY: clean
clean:
	rm -rf build/

.PHONY: build
build: clean set-otelcol-version
	@echo Building otel collector extension
	mkdir -p $(BUILD_SPACE)/extensions
	GOOS=linux GOARCH=$(GOARCH) $(GOBUILD) $(LDFLAGS) -o $(BUILD_SPACE)/extensions .

.PHONY: package-extend
package-extend: build
	@echo Packaging Extend collector layer
	mkdir -p $(BUILD_SPACE)/collector-config
	cp ../extend/collector-config-cx-only.yaml     $(BUILD_SPACE)/collector-config/config.yaml
	cp ../extend/collector-config-cx-arize.yaml    $(BUILD_SPACE)/collector-config/
	cp ../extend/collector-config-cx-arize-s3.yaml $(BUILD_SPACE)/collector-config/
	cd $(BUILD_SPACE) && zip -r opentelemetry-collector-layer-$(GOARCH).zip collector-config extensions

.PHONY: set-otelcol-version
set-otelcol-version:
	@OTELCOL_VERSION=$$(grep "go.opentelemetry.io/collector/otelcol v" go.mod | awk '{print $$2; exit}'); \
	echo $$OTELCOL_VERSION > VERSION; \

.PHONY: gotidy
gotidy:
	@$(MAKE) for-all-target TARGET="tidy" MODULES="$(TIDY_MODULES)"

.PHONY: gotest
gotest:
	@$(MAKE) for-all-target TARGET="test"

.PHONY: goporto
goporto: install-tools
	porto -w --include-internal ./

.PHONY: golint
golint: install-tools
	@$(MAKE) for-all-target TARGET="lint"

.PHONY: golintfix
golintfix: install-tools
	@$(MAKE) for-all-target TARGET="lintfix"

.PHONY: gofmt
gofmt: install-tools
	@$(MAKE) for-all-target TARGET="fmt"

.PHONY: install-tools
install-tools:
	cd $(TOOLS_MOD_DIR) && $(GOCMD) install github.com/golangci/golangci-lint/cmd/golangci-lint
	cd $(TOOLS_MOD_DIR) && $(GOCMD) install golang.org/x/tools/cmd/goimports
	cd $(TOOLS_MOD_DIR) && $(GOCMD) install github.com/jcchavezs/porto/cmd/porto
	$(GOCMD) install golang.org/x/vuln/cmd/govulncheck@v1.3.0

.PHONY: govulncheck
govulncheck: install-tools
	@err=0; for dir in $(OTEL_GO_MOD_DIRS); do \
		echo "Running govulncheck in module '$$dir'"; \
		(cd $$dir && govulncheck ./...) || err=$$?; \
	done; exit $$err
