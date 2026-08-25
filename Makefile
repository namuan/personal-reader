SWIFT ?= swift

.PHONY: help resolve build release test lint format check update dependencies clean reset open

help:
	@printf '%s\n' \
		'make resolve       Resolve Swift package dependencies' \
		'make build         Build the package in debug mode' \
		'make release       Build the package in release mode' \
		'make test          Run all tests' \
		'make lint          Check Swift formatting' \
		'make format        Format Swift sources in place' \
		'make check         Run lint, build, and tests' \
		'make update        Update Swift package dependencies' \
		'make dependencies  Show resolved dependency graph' \
		'make clean         Remove SwiftPM build artifacts' \
		'make reset         Remove build artifacts and Package.resolved' \
		'make open          Open the package in Xcode'

resolve:
	$(SWIFT) package resolve

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

lint:
	$(SWIFT) format lint --recursive --parallel --strict Sources Tests Package.swift

format:
	$(SWIFT) format format --in-place --recursive --parallel Sources Tests Package.swift

check: lint build test

update:
	$(SWIFT) package update

dependencies:
	$(SWIFT) package show-dependencies

clean:
	$(SWIFT) package clean
	rm -rf .build

reset: clean
	rm -f Package.resolved

open:
	open Package.swift
