.PHONY: build test run app setup-all smoke clean

build:
	swift build

test:
	swift test

run:
	swift run OCRGUI

app:
	zsh scripts/make-app.sh

setup-all:
	zsh scripts/setup_all.sh

smoke:
	zsh scripts/smoke_paddle_classic.sh

clean:
	swift package clean
	rm -rf dist
