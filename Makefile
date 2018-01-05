build-win:
	cmd "/C for /R projects %F in (*) do copy /Y %F dist"

build-linux:
	rm -r ./dist/*
	find ./projects/ -not -name '*.bin' -type f -exec cp {} ./dist \;

