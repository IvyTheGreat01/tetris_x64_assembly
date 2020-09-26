# Ivan Bystrov
# 24 September 2020
#
# Makefile for this nasm assmebly tetris game
# Only works on 64 bit Linux

tetris: tetris.o
	gcc -o tetris tetris.o -lX11 -no-pie

tetris.o: tetris.asm
	nasm -felf64 -o tetris.o tetris.asm

.PHONY: clean

clean:
	rm *.o tetris

