build-win:
	cmd "/C for /R projects %F in (*) do copy /Y %F dist"

modbuilder:
	ModBuilder ./projects ./dist

modbuilder-watch:
	ModBuilder ./projects ./dist -w
build-linux:
	rm -r ./dist/*
	find ./projects/ -not -name '*.bin' -type f -exec cp {} ./dist \;

