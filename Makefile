.PHONY: all lint format check typecheck i18n ascii-clean

all: typecheck lint ascii-clean format

lint:
	luacheck .

# Strip the AI-tell punctuation (em dash, ellipsis, right arrow) from sources.
ascii-clean:
	@rg -l --glob '*.{lua,md,sh}' -g '!Libs' -g '!Locales' '—|…|→' \
		| xargs -r sed -i 's/—/-/g; s/…/.../g; s/→/->/g'

format:
	stylua .

typecheck:
	lua-language-server --check . --checklevel=Warning

i18n:
	@scripts/check-locales.sh $(ARGS)

check: typecheck lint
	stylua --check .
