books := 1 2 3 4 5 6
bookZips := $(foreach num,$(books),book$(num).zip)
illuZips := $(foreach num,$(books),illus$(num).zip)

.PHONY: build clean koreader-plugin check-koreader-content check-koreader-compatibility

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

koreader-plugin: check-koreader-content check-koreader-compatibility
	sh tools/package-koreader-plugin.sh
