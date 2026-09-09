books := 1 2 3 4 5 6
bookZips := $(foreach num,$(books),book$(num).zip)
illuZips := $(foreach num,$(books),illus$(num).zip)

.PHONY: build clean koreader-plugin check-koreader-content check-koreader-compatibility check-koreader-reachability check-koreader-lua

build: flands.jar $(bookZips) $(illuZips)

flands.jar:
	javac flands/*.java
	jar cfm0 flands.jar MANIFEST.MF flands/*.class flands/resources/*.class flands/resources/*.properties

%.zip:
	zip -jq $@ $(subst .zip,/*,$@)

clean:
	rm -f flands.jar **/*.class flands/resources/*.class *.zip
	rm -rf dist

check-koreader-content:
	python3 tools/validate-koreader-content.py

check-koreader-compatibility:
	python3 tools/generate-koreader-compatibility.py --check

check-koreader-reachability:
	python3 tools/audit-koreader-reachability.py

check-koreader-lua:
	sh tools/run-koreader-lua-tests.sh

koreader-plugin: check-koreader-content check-koreader-compatibility check-koreader-reachability
	sh tools/package-koreader-plugin.sh
