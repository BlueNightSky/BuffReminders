.PHONY: all lint format check typecheck locales

all: typecheck lint format locales

lint:
	luacheck .

format:
	stylua --glob '!ignored/**' --glob '*.lua' .

typecheck:
	lua-language-server --check . --checklevel=Warning

locales:
	@scripts/check-locales.sh

check: typecheck lint locales
	stylua --check --glob '!ignored/**' --glob '*.lua' .
