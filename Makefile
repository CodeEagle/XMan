BINARY?=xman
BUILD_FOLDER?=.build
ROOT?=$(PWD)
OS?=sierra
PREFIX?=/usr/local
PROJECT?=XMan
RELEASE_BINARY_FOLDER?=$(BUILD_FOLDER)/release/$(PROJECT)
TEST_FOLDER=/
release:
	swift build -c release -Xswiftc -static-stdlib
build:
	swift build  -Xswiftc "-D" -Xswiftc "DEBUG"
test:
	make build
	OLDPWD=$(PWD)
	cd $(TEST_FOLDER) && $(ROOT)/$(BUILD_FOLDER)/debug/$(PROJECT)
	cd $(OLDPWD)
restore:
	make build
	OLDPWD=$(PWD)
	cd $(TEST_FOLDER) && $(ROOT)/$(BUILD_FOLDER)/debug/$(PROJECT) restore
	cd $(OLDPWD)
clean:
	swift package clean
	rm -rf $(BUILD_FOLDER) $(PROJECT).xcodeproj
xcode:
	swift package generate-xcodeproj
install:
	make xcode
	make release
	mkdir -p $(PREFIX)/bin
	if [ -f "/usr/local/bin/$(BINARY)" ]; then rm /usr/local/bin/$(BINARY); fi
	cp -f $(RELEASE_BINARY_FOLDER) $(PREFIX)/bin/$(BINARY)
	$(BINARY) help

#Maybe you have a file/directory named test in the directory. If this directory exists, and has no dependencies that are more recent, then this target is not rebuild.
#To force rebuild on these kind of not-file-related targets, you should make them phony as follows:
.PHONY: release
