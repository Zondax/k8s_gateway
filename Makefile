# The binary to build (just the basename).
BIN := $(shell basename $$PWD)

# Version from git tag
VERSION ?= $(shell git describe --tags --always --dirty)
COMMIT_ID_SHORT := $(shell git rev-parse --short HEAD)
COMMIT_ID = $(shell git rev-parse HEAD)
LDFLAGS := "-s -w -X github.com/coredns/coredns/coremain.GitCommit=$(COMMIT_ID_SHORT)"
# Image URL to use all building/pushing image targets
REGISTRY ?= registry-1.docker.io
IMG_NAME ?= $(BIN)
IMG_PREFIX ?= $(REGISTRY)/rawmind
IMG ?= ${IMG_PREFIX}/${IMG_NAME}:${VERSION}
DOCKERHUB_USER ?= rawmind
FLUXAPP_NAME ?= ${IMG_NAME}-fluxapp
FLUXAPP_IMG ?= $(IMG_PREFIX)/${FLUXAPP_NAME}
FLUXAPP_VERSION ?= $(shell cat deploy/fluxapp/version)

THIS_MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

KUBECONFORM_EXTRA_CRD_VERSION := main
KUBECONFORM_EXTRA_CRD_URL := https://raw.githubusercontent.com/datreeio/CRDs-catalog/$(KUBECONFORM_EXTRA_CRD_VERSION)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ Development

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: linter
linter:
	golangci-lint run --timeout=5m0s

.PHONY: run
run:
	go run ./cmd/coredns.go

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: fmt vet ## Run tests.
	go test -race ./... -short

##@ Build

.PHONY: build
build:
	goreleaser build --single-target --snapshot --clean

.PHONY: build-all
build-all:
	goreleaser build --clean

##@ Docker

.PHONY: docker-build
docker-build:
	goreleaser release --snapshot --clean

.PHONY: docker-login
docker-login:
	@echo ${DOCKERHUB_TOKEN} | docker login -u ${DOCKERHUB_USER} --password-stdin

.PHONY: docker-push
docker-push: ## Push docker image.
	@docker push ${IMG}

##@ Helm

.PHONY: helm-login
helm-login:
	@echo Login helm to $(REGISTRY)
	@echo ${DOCKERHUB_TOKEN} | helm registry login $(REGISTRY) -u ${DOCKERHUB_USER} --password-stdin

.PHONY: helm-template
helm-template:
	@echo Templating helm chart ./dist/chart/output
	@if [ -d "$(THIS_MAKEFILE_DIR)/dist/chart/output" ]; then \
		rm -r $(THIS_MAKEFILE_DIR)/dist/chart/output; \
	fi
	@cd deploy/chart; helm template test ./ --output-dir $(THIS_MAKEFILE_DIR)/dist/chart/output; cd $(THIS_MAKEFILE_DIR)

.PHONY: helm-package
helm-package: helm-template
	@echo Packaging helm chart
	@if [ -d "$(THIS_MAKEFILE_DIR)/dist/chart" ]; then \
		rm $(THIS_MAKEFILE_DIR)/dist/chart/*.tgz > /dev/null 2>&1 || echo 1 > /dev/null ; \
	fi
	@cd deploy/chart; helm package . -d $(THIS_MAKEFILE_DIR)/dist/chart; cd $(THIS_MAKEFILE_DIR)
	@echo Kubeconforming helm chart template
	@kubeconform \
		-schema-location default \
		-schema-location '$(KUBECONFORM_EXTRA_CRD_URL)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-ignore-missing-schemas \
		-n 16 \
		-summary $(THIS_MAKEFILE_DIR)/dist/chart/output

.PHONY: helm-push
helm-push:
	@for i in $(shell find $(THIS_MAKEFILE_DIR)/dist/chart/*.tgz); do \
		echo Pushing $$i to oci://$(IMG_PREFIX); \
		helm push $$i oci://$(IMG_PREFIX); \
		if [ $$? -ne 0 ]; then echo "[ERROR] running $$i"; exit 1; fi; \
	done

.PHONY: helm-release
helm-release: helm-login helm-package helm-push
	@echo Helm released

##@ Flux app

.PHONY: flux-template
flux-template:
	@echo Templating fluxapp $(FLUXAPP_VERSION) to ./dist/fluxapp
	@if [ ! -d "$(THIS_MAKEFILE_DIR)/dist/fluxapp" ]; then \
		mkdir -p $(THIS_MAKEFILE_DIR)/dist/fluxapp; \
	fi
	@if [ -f "$(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml" ]; then \
		rm $(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml; \
	fi
	@kustomize build $(THIS_MAKEFILE_DIR)/deploy/fluxapp > $(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml

.PHONY: flux-unpack
flux-unpack:
	@echo Pulling oci://$(FLUXAPP_IMG):$(FLUXAPP_VERSION) to ./dist/fluxapp/apps.yaml
	@if [ ! -d "$(THIS_MAKEFILE_DIR)/dist/fluxapp" ]; then \
		mkdir -p $(THIS_MAKEFILE_DIR)/dist/fluxapp; \
	fi
	@if [ -f "$(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml" ]; then \
		rm $(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml; \
	fi
	@flux pull artifact oci://$(FLUXAPP_IMG):$(FLUXAPP_VERSION) --output $(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml

.PHONY: flux-package
flux-package: flux-template
	@echo Kubeconforming flux app template
	kubeconform \
		-schema-location default \
		-schema-location '$(KUBECONFORM_EXTRA_CRD_URL)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-ignore-missing-schemas \
		-n 16 \
		-summary $(THIS_MAKEFILE_DIR)/dist/fluxapp

.PHONY: flux-push
flux-push:
	@echo Pushing fluxapp oci://$(FLUXAPP_IMG):$(COMMIT_ID_SHORT) - oci://$(FLUXAPP_IMG):$(FLUXAPP_VERSION)
	@flux push artifact oci://$(FLUXAPP_IMG):$(COMMIT_ID_SHORT) \
		--source="$(shell git config --get remote.origin.url)" \
		--revision="$(shell git tag --points-at HEAD)@sha1:$(COMMIT_ID)" \
		--path $(THIS_MAKEFILE_DIR)/dist/fluxapp/apps.yaml \
		--creds zondax:${DOCKERHUB_TOKEN}
	@flux tag artifact oci://$(FLUXAPP_IMG):$(COMMIT_ID_SHORT) \
		--tag $(FLUXAPP_VERSION) \
		--creds zondax:${DOCKERHUB_TOKEN}

.PHONY: flux-release
flux-release: flux-package flux-push
	@echo Fluxapp released

##@ Release

.PHONY: release
release: docker-login
	goreleaser release --clean

.PHONY: snapshot
snapshot: ## Create a snapshot release.
	goreleaser release --snapshot --clean

setup:
	./test/kind-with-registry.sh

up:
	tilt up

down:
	tilt down

nuke:
	./test/teardown-kind-with-registry.sh

clean:
	go clean
	rm -f coredns

# From: https://gist.github.com/klmr/575726c7e05d8780505a
help:
	@echo "$$(tput sgr0)";sed -ne"/^## /{h;s/.*//;:d" -e"H;n;s/^## //;td" -e"s/:.*//;G;s/\\n## /---/;s/\\n/ /g;p;}" ${MAKEFILE_LIST}|awk -F --- -v n=$$(tput cols) -v i=15 -v a="$$(tput setaf 6)" -v z="$$(tput sgr0)" '{printf"%s%*s%s ",a,-i,$$1,z;m=split($$2,w," ");l=n-i;for(j=1;j<=m;j++){l-=length(w[j])+1;if(l<= 0){l=n-i-length(w[j])-1;printf"\n%*s ",-i," ";}printf"%s ",w[j];}printf"\n";}'
