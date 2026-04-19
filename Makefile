.PHONY: build test lint format format-check install-hooks ci

build:
	swift build

test:
	swift test

lint:
	swift package plugin --allow-writing-to-package-directory swiftlint

format:
	swift package plugin --allow-writing-to-package-directory swiftformat

format-check:
	swift package plugin --allow-writing-to-package-directory swiftformat --lint

install-hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "✅ Pre-commit hook installed."

ci: format-check lint build test
