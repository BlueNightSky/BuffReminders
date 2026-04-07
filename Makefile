.PHONY: all lint format check typecheck i18n

all: typecheck lint format

lint:
	luacheck .

format:
	stylua --glob '!ignored/**' --glob '*.lua' .

typecheck:
	lua-language-server --check . --checklevel=Warning

i18n:
	@scripts/check-locales.sh $(ARGS)

check: typecheck lint
	stylua --check --glob '!ignored/**' --glob '*.lua' .
