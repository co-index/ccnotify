VERSION ?= dev
PREFIX ?= /usr/local
APP = dist/ccnotify.app
BINARY = $(APP)/Contents/MacOS/ccnotify

.PHONY: build install uninstall clean

build: $(BINARY)

$(BINARY): Sources/main.swift Resources/Info.plist assets/ccnotify.icns Makefile
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	cp assets/ccnotify.icns $(APP)/Contents/Resources/ccnotify.icns
	swiftc -O -o $(BINARY) Sources/main.swift
	codesign --force --sign - $(APP)

install: build
	mkdir -p $(DESTDIR)$(PREFIX)/libexec $(DESTDIR)$(PREFIX)/bin
	rm -rf $(DESTDIR)$(PREFIX)/libexec/ccnotify.app
	cp -R $(APP) $(DESTDIR)$(PREFIX)/libexec/ccnotify.app
	printf '#!/bin/bash\nexec "%s/libexec/ccnotify.app/Contents/MacOS/ccnotify" "$$@"\n' '$(PREFIX)' > $(DESTDIR)$(PREFIX)/bin/ccnotify
	chmod +x $(DESTDIR)$(PREFIX)/bin/ccnotify

uninstall:
	rm -rf $(DESTDIR)$(PREFIX)/libexec/ccnotify.app
	rm -f $(DESTDIR)$(PREFIX)/bin/ccnotify

clean:
	rm -rf dist
