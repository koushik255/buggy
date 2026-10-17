.PHONY: test build app

test:
	swift test

build:
	swift build

app:
	./Scripts/make-app.sh
