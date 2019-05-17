debug:
	swift build | tee .build/last_build.log

release:
	swift build -c release | tee .build/last_build.log

run:
	swift run | tee .build/last_build.log
