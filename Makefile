all:
	odin build . -out:./hot_dead_pixel_detect_correct.exe --debug

opti:
	odin build . -out:./hot_dead_pixel_detect_correct.exe -o:speed -no-bounds-check -disable-assert

clean:
	rm ./hot_dead_pixel_detect_correct.exe

run:
	./hot_dead_pixel_detect_correct.exe



