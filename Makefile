.PHONY: test run

# Arch's lua51-busted installs the CLI under the luarocks tree without
# symlinking into /usr/bin. Resolve the path dynamically so a busted
# version bump doesn't break this rule.
BUSTED := $(firstword $(wildcard /usr/lib/luarocks/rocks-5.1/busted/*/bin/busted))

test:
	@luajit $(BUSTED) spec/

run:
	@love .
