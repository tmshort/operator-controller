###########################
# Configuration Variables #
###########################
# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL := /usr/bin/env bash -o pipefail
.SHELLFLAGS := -ec
export ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

GOLANG_VERSION := $(shell sed -En 's/^go (.*)$$/\1/p' "go.mod")
# Image URL to use all building/pushing image targets
ifeq ($(origin IMAGE_REPO), undefined)
IMAGE_REPO := quay.io/operator-framework/operator-controller
endif
export IMAGE_REPO

ifeq ($(origin IMAGE_TAG), undefined)
IMAGE_TAG := devel
endif
export IMAGE_TAG

IMG := $(IMAGE_REPO):$(IMAGE_TAG)

# Define dependency versions (use go.mod if we also use Go code from dependency)
export CERT_MGR_VERSION := v1.15.3
export CATALOGD_VERSION := $(shell go list -mod=mod -m -f "{{.Version}}" github.com/operator-framework/catalogd)
export WAIT_TIMEOUT := 60s

# Install default ClusterCatalogs
export INSTALL_DEFAULT_CATALOGS := true

# By default setup-envtest will write to $XDG_DATA_HOME, or $HOME/.local/share if that is not defined.
# If $HOME is not set, we need to specify a binary directory to prevent an error in setup-envtest.
# Useful for some CI/CD environments that set neither $XDG_DATA_HOME nor $HOME.
SETUP_ENVTEST_BIN_DIR_OVERRIDE=
ifeq ($(shell [[ $$HOME == "" || $$HOME == "/" ]] && [[ $$XDG_DATA_HOME == "" ]] && echo true ), true)
	SETUP_ENVTEST_BIN_DIR_OVERRIDE += --bin-dir /tmp/envtest-binaries
endif

# bingo manages consistent tooling versions for things like kind, kustomize, etc.
include .bingo/Variables.mk

ifeq ($(origin KIND_CLUSTER_NAME), undefined)
KIND_CLUSTER_NAME := operator-controller
endif

# Not guaranteed to have patch releases available and node image tags are full versions (i.e v1.28.0 - no v1.28, v1.29, etc.)
# The KIND_NODE_VERSION is set by getting the version of the k8s.io/client-go dependency from the go.mod
# and sets major version to "1" and the patch version to "0". For example, a client-go version of v0.28.5
# will map to a KIND_NODE_VERSION of 1.28.0
KIND_NODE_VERSION := $(shell go list -m k8s.io/client-go | cut -d" " -f2 | sed 's/^v0\.\([[:digit:]]\{1,\}\)\.[[:digit:]]\{1,\}$$/1.\1.0/')
KIND_CLUSTER_IMAGE := kindest/node:v$(KIND_NODE_VERSION)

ifneq (, $(shell command -v docker 2>/dev/null))
CONTAINER_RUNTIME := docker
else ifneq (, $(shell command -v podman 2>/dev/null))
CONTAINER_RUNTIME := podman
else
$(warning Could not find docker or podman in path! This may result in targets requiring a container runtime failing!)
endif

KUSTOMIZE_BUILD_DIR := config/overlays/cert-manager

# Disable -j flag for make
.NOTPARALLEL:

.DEFAULT_GOAL := build

#SECTION General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '#SECTION' and the
# target descriptions by '#HELP' or '#EXHELP'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: #HELP something, and then pretty-format the target and help. Then,
# if there's a line with #SECTION something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php
# The extended-help target uses '#EXHELP' as the delineator.

.PHONY: help
help: #HELP Display essential help.
	@awk 'BEGIN {FS = ":[^#]*#HELP"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_0-9-]+:.*#HELP / { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } ' $(MAKEFILE_LIST)

.PHONY: help-extended
help-extended: #HELP Display extended help.
	@awk 'BEGIN {FS = ":.*#(EX)?HELP"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*#(EX)?HELP / { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^#SECTION / { printf "\n\033[1m%s\033[0m\n", substr($$0, 10) } ' $(MAKEFILE_LIST)

#SECTION Development

.PHONY: lint
lint: $(GOLANGCI_LINT) #HELP Run golangci linter.
	$(GOLANGCI_LINT) run $(GOLANGCI_LINT_ARGS)

.PHONY: tidy
tidy: #HELP Update dependencies.
	# Force tidy to use the version already in go.mod
	$(Q)go mod tidy -go=$(GOLANG_VERSION)

.PHONY: manifests
manifests: $(CONTROLLER_GEN) #EXHELP Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/base/crd/bases output:rbac:artifacts:config=config/base/rbac

.PHONY: generate
generate: $(CONTROLLER_GEN) #EXHELP Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: verify
verify: tidy fmt vet generate manifests crd-ref-docs #HELP Verify all generated code is up-to-date.
	git diff --exit-code

.PHONY: fix-lint
fix-lint: $(GOLANGCI_LINT) #EXHELP Fix lint issues
	$(GOLANGCI_LINT) run --fix $(GOLANGCI_LINT_ARGS)

.PHONY: fmt
fmt: #EXHELP Formats code
	go fmt ./...

.PHONY: vet
vet: #EXHELP Run go vet against code.
	go vet ./...

.PHONY: bingo-upgrade
bingo-upgrade: $(BINGO) #EXHELP Upgrade tools
	@for pkg in $$($(BINGO) list | awk '{ print $$1 }' | tail -n +3); do \
		echo "Upgrading $$pkg to latest..."; \
		$(BINGO) get "$$pkg@latest"; \
	done

.PHONY: test
test: manifests generate fmt vet test-unit test-e2e #HELP Run all tests.

.PHONY: e2e
e2e: #EXHELP Run the e2e tests.
	go test -count=1 -v ./test/e2e/...

E2E_REGISTRY_NAME := docker-registry
E2E_REGISTRY_NAMESPACE := operator-controller-e2e

export REG_PKG_NAME := registry-operator
export LOCAL_REGISTRY_HOST := $(E2E_REGISTRY_NAME).$(E2E_REGISTRY_NAMESPACE).svc:5000
export CLUSTER_REGISTRY_HOST := localhost:30000
export E2E_TEST_CATALOG_V1 := e2e/test-catalog:v1
export E2E_TEST_CATALOG_V2 := e2e/test-catalog:v2
export CATALOG_IMG := $(LOCAL_REGISTRY_HOST)/$(E2E_TEST_CATALOG_V1)
.PHONY: test-ext-dev-e2e
test-ext-dev-e2e: $(OPERATOR_SDK) $(KUSTOMIZE) $(KIND) #HELP Run extension create, upgrade and delete tests.
	test/extension-developer-e2e/setup.sh $(OPERATOR_SDK) $(CONTAINER_RUNTIME) $(KUSTOMIZE) $(KIND) $(KIND_CLUSTER_NAME) $(E2E_REGISTRY_NAMESPACE)
	go test -count=1 -v ./test/extension-developer-e2e/...

.PHONY: test-unit
ENVTEST_VERSION := $(shell go list -m k8s.io/client-go | cut -d" " -f2 | sed 's/^v0\.\([[:digit:]]\{1,\}\)\.[[:digit:]]\{1,\}$$/1.\1.x/')
UNIT_TEST_DIRS := $(shell go list ./... | grep -v /test/)
COVERAGE_UNIT_DIR := $(ROOT_DIR)/coverage/unit
test-unit: $(SETUP_ENVTEST) #HELP Run the unit tests
	rm -rf $(COVERAGE_UNIT_DIR) && mkdir -p $(COVERAGE_UNIT_DIR)
	eval $$($(SETUP_ENVTEST) use -p env $(ENVTEST_VERSION) $(SETUP_ENVTEST_BIN_DIR_OVERRIDE)) && CGO_ENABLED=1 go test -count=1 -race -short $(UNIT_TEST_DIRS) -cover -coverprofile ${ROOT_DIR}/coverage/unit.out -test.gocoverdir=$(ROOT_DIR)/coverage/unit

image-registry: ## Setup in-cluster image registry
	./hack/test/image-registry.sh $(E2E_REGISTRY_NAMESPACE) $(E2E_REGISTRY_NAME)

build-push-e2e-catalog: ## Build the testdata catalog used for e2e tests and push it to the image registry
	./hack/test/build-push-e2e-catalog.sh $(E2E_REGISTRY_NAMESPACE) $(LOCAL_REGISTRY_HOST)/$(E2E_TEST_CATALOG_V1)
	./hack/test/build-push-e2e-catalog.sh $(E2E_REGISTRY_NAMESPACE) $(LOCAL_REGISTRY_HOST)/$(E2E_TEST_CATALOG_V2)

# When running the e2e suite, you can set the ARTIFACT_PATH variable to the absolute path
# of the directory for the operator-controller e2e tests to store the artifacts, which
# may be helpful for debugging purposes after a test run.
#
# for example: ARTIFACT_PATH=/tmp/artifacts make test-e2e
.PHONY: test-e2e
test-e2e: KIND_CLUSTER_NAME := operator-controller-e2e
test-e2e: KUSTOMIZE_BUILD_DIR := config/overlays/e2e
test-e2e: GO_BUILD_FLAGS := -cover
test-e2e: run image-registry build-push-e2e-catalog registry-load-bundles e2e e2e-coverage kind-clean #HELP Run e2e test suite on local kind cluster

.PHONY: extension-developer-e2e
extension-developer-e2e: KUSTOMIZE_BUILD_DIR := config/overlays/cert-manager
extension-developer-e2e: KIND_CLUSTER_NAME := operator-controller-ext-dev-e2e  #EXHELP Run extension-developer e2e on local kind cluster
extension-developer-e2e: export INSTALL_DEFAULT_CATALOGS := false  #EXHELP Run extension-developer e2e on local kind cluster
extension-developer-e2e: run image-registry test-ext-dev-e2e kind-clean

.PHONY: run-latest-release
run-latest-release:
	curl -L -s https://github.com/operator-framework/operator-controller/releases/latest/download/install.sh | bash -s

.PHONY: pre-upgrade-setup
pre-upgrade-setup:
	./hack/test/pre-upgrade-setup.sh $(CATALOG_IMG) $(TEST_CLUSTER_CATALOG_NAME) $(TEST_CLUSTER_EXTENSION_NAME)

.PHONY: post-upgrade-checks
post-upgrade-checks:
	go test -count=1 -v ./test/upgrade-e2e/...

.PHONY: test-upgrade-e2e
test-upgrade-e2e: KIND_CLUSTER_NAME := operator-controller-upgrade-e2e
test-upgrade-e2e: export TEST_CLUSTER_CATALOG_NAME := test-catalog
test-upgrade-e2e: export TEST_CLUSTER_EXTENSION_NAME := test-package
test-upgrade-e2e: kind-cluster run-latest-release image-registry build-push-e2e-catalog registry-load-bundles pre-upgrade-setup docker-build kind-load kind-deploy post-upgrade-checks kind-clean #HELP Run upgrade e2e tests on a local kind cluster

.PHONY: e2e-coverage
e2e-coverage:
	COVERAGE_OUTPUT=./coverage/e2e.out ./hack/test/e2e-coverage.sh

.PHONY: kind-load
kind-load: $(KIND) #EXHELP Loads the currently constructed image onto the cluster.
	$(CONTAINER_RUNTIME) save $(IMG) | $(KIND) load image-archive /dev/stdin --name $(KIND_CLUSTER_NAME)

.PHONY: kind-deploy
kind-deploy: export MANIFEST="./operator-controller.yaml"
kind-deploy: manifests $(KUSTOMIZE) #EXHELP Install controller and dependencies onto the kind cluster.
	$(KUSTOMIZE) build $(KUSTOMIZE_BUILD_DIR) > operator-controller.yaml
	envsubst '$$CATALOGD_VERSION,$$CERT_MGR_VERSION,$$INSTALL_DEFAULT_CATALOGS,$$MANIFEST' < scripts/install.tpl.sh | bash -s

.PHONY: kind-cluster
kind-cluster: $(KIND) #EXHELP Standup a kind cluster.
	-$(KIND) delete cluster --name $(KIND_CLUSTER_NAME)
	$(KIND) create cluster --name $(KIND_CLUSTER_NAME) --image $(KIND_CLUSTER_IMAGE) --config ./kind-config.yaml
	$(KIND) export kubeconfig --name $(KIND_CLUSTER_NAME)

.PHONY: kind-clean
kind-clean: $(KIND) #EXHELP Delete the kind cluster.
	$(KIND) delete cluster --name $(KIND_CLUSTER_NAME)

registry-load-bundles: ## Load selected e2e testdata container images created in kind-load-bundles into registry
	testdata/bundles/registry-v1/build-push-e2e-bundle.sh ${E2E_REGISTRY_NAMESPACE} $(LOCAL_REGISTRY_HOST)/bundles/registry-v1/prometheus-operator:v1.0.0 prometheus-operator.v1.0.0 prometheus-operator.v1.0.0
	testdata/bundles/registry-v1/build-push-e2e-bundle.sh ${E2E_REGISTRY_NAMESPACE} $(LOCAL_REGISTRY_HOST)/bundles/registry-v1/prometheus-operator:v1.0.1 prometheus-operator.v1.0.1 prometheus-operator.v1.0.0
	testdata/bundles/registry-v1/build-push-e2e-bundle.sh ${E2E_REGISTRY_NAMESPACE} $(LOCAL_REGISTRY_HOST)/bundles/registry-v1/prometheus-operator:v1.2.0 prometheus-operator.v1.2.0 prometheus-operator.v1.0.0
	testdata/bundles/registry-v1/build-push-e2e-bundle.sh ${E2E_REGISTRY_NAMESPACE} $(LOCAL_REGISTRY_HOST)/bundles/registry-v1/prometheus-operator:v2.0.0 prometheus-operator.v2.0.0 prometheus-operator.v1.0.0

#SECTION Build

ifeq ($(origin VERSION), undefined)
VERSION := $(shell git describe --tags --always --dirty)
endif
export VERSION

ifeq ($(origin CGO_ENABLED), undefined)
CGO_ENABLED := 0
endif
export CGO_ENABLED

export GIT_REPO := $(shell go list -m)
export VERSION_PATH := ${GIT_REPO}/internal/version
export GO_BUILD_ASMFLAGS := all=-trimpath=$(PWD)
export GO_BUILD_GCFLAGS := all=-trimpath=$(PWD)
export GO_BUILD_FLAGS :=
export GO_BUILD_LDFLAGS := -s -w \
    -X '$(VERSION_PATH).version=$(VERSION)' \

BINARIES=manager

$(BINARIES):
	go build $(GO_BUILD_FLAGS) -tags '$(GO_BUILD_TAGS)' -ldflags '$(GO_BUILD_LDFLAGS)' -gcflags '$(GO_BUILD_GCFLAGS)' -asmflags '$(GO_BUILD_ASMFLAGS)' -o $(BUILDBIN)/$@ ./cmd/$@

.PHONY: build-deps
build-deps: manifests generate fmt vet

.PHONY: build go-build-local
build: build-deps go-build-local #HELP Build manager binary for current GOOS and GOARCH. Default target.
go-build-local: BUILDBIN := bin
go-build-local: $(BINARIES)

.PHONY: build-linux go-build-linux
build-linux: build-deps go-build-linux #EXHELP Build manager binary for GOOS=linux and local GOARCH.
go-build-linux: BUILDBIN := bin/linux
go-build-linux: export GOOS=linux
go-build-linux: export GOARCH=amd64
go-build-linux: $(BINARIES)

.PHONY: run
run: docker-build kind-cluster kind-load kind-deploy #HELP Build the operator-controller then deploy it into a new kind cluster.

.PHONY: docker-build
docker-build: build-linux #EXHELP Build docker image for operator-controller with GOOS=linux and local GOARCH.
	$(CONTAINER_RUNTIME) build -t $(IMG) -f Dockerfile ./bin/linux

#SECTION Release
ifeq ($(origin ENABLE_RELEASE_PIPELINE), undefined)
ENABLE_RELEASE_PIPELINE := false
endif
ifeq ($(origin GORELEASER_ARGS), undefined)
GORELEASER_ARGS := --snapshot --clean
endif

export ENABLE_RELEASE_PIPELINE
export GORELEASER_ARGS

.PHONY: release
release: $(GORELEASER) #EXHELP Runs goreleaser for the operator-controller. By default, this will run only as a snapshot and will not publish any artifacts unless it is run with different arguments. To override the arguments, run with "GORELEASER_ARGS=...". When run as a github action from a tag, this target will publish a full release.
	$(GORELEASER) $(GORELEASER_ARGS)

.PHONY: quickstart
quickstart: export MANIFEST := https://github.com/operator-framework/operator-controller/releases/download/$(VERSION)/operator-controller.yaml
quickstart: $(KUSTOMIZE) manifests #EXHELP Generate the installation release manifests and scripts.
	$(KUSTOMIZE) build $(KUSTOMIZE_BUILD_DIR) | sed "s/:devel/:$(VERSION)/g" > operator-controller.yaml
	envsubst '$$CATALOGD_VERSION,$$CERT_MGR_VERSION,$$INSTALL_DEFAULT_CATALOGS,$$MANIFEST' < scripts/install.tpl.sh > install.sh

##@ Docs

.PHONY: crd-ref-docs
API_REFERENCE_FILENAME := operator-controller-api-reference.md
crd-ref-docs: $(CRD_REF_DOCS)
	rm -f $(ROOT_DIR)/docs/refs/api/$(API_REFERENCE_FILENAME)
	$(CRD_REF_DOCS) --source-path=$(ROOT_DIR)/api \
	--config=$(ROOT_DIR)/config/base/crd/bases/olm.operatorframework.io_clusterextensions.yaml \
	--renderer=markdown \
	--output-path=$(ROOT_DIR)/docs/refs/api/$(API_REFERENCE_FILENAME)

VENVDIR := $(abspath docs/.venv)

.PHONY: build-docs
build-docs: venv
	. $(VENV)/activate; \
	mkdocs build

.PHONY: serve-docs
serve-docs: venv
	. $(VENV)/activate; \
	mkdocs serve

.PHONY: deploy-docs
deploy-docs: venv
	. $(VENV)/activate; \
	mkdocs gh-deploy --force

include Makefile.venv
