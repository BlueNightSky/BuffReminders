.PHONY: all lint format check typecheck locales deps

all: deps typecheck lint format locales

deps:
	@scripts/fetch-libs.sh

lint:
	luacheck .

format:
	stylua --glob '!ignored/**' --glob '*.lua' .

typecheck:
	lua-language-server --check . --checklevel=Warning

locales:
	@scripts/check-locales.sh

check: deps typecheck lint locales
	stylua --check --glob '!ignored/**' --glob '*.lua' .
