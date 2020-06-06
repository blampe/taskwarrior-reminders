BINARY=task-reminders-sync
BUILD_FLAGS=-g -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
DEBUG_PREFIX=.build/debug
RELEASE_PREFIX=.build/release
INSTALL_PREFIX=/usr/local/bin

debug:
	swift build $(BUILD_FLAG)

release: clean
	swift build $(BUILD_FLAGS) --configuration release

# We embed Info.plist in the binary but tccd still has trouble finding it when
# running under launchd. As a workaround it will use the Info.plist sitting
# next to the binary, so symlink /usr/local/bin to point to this directory.
install: release uninstall
	cp $(RELEASE_PREFIX)/$(BINARY) $(BINARY)
	ln -Fs $(PWD)/$(BINARY) $(INSTALL_PREFIX)/$(BINARY)
	cp com.blampe.task-reminders-sync.plist ~/Library/LaunchAgents/.
	launchctl load -w ~/Library/LaunchAgents/com.blampe.task-reminders-sync.plist

uninstall:
	rm -f $(INSTALL_PREFIX)/$(BINARY)
	launchctl remove com.blampe.task-reminders-sync || true

run: debug
	$(DEBUG_PREFIX)/$(BINARY)

clean:
	swift package clean
	rm -rf .build
