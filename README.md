# tetris_x64_assembly
This is a tetris game written from scratch in NASM x64 assembly language for 64 bit Linux.
It uses `xlib` to handle all graphics.

Showcase Video:

## How To Play
After cloning or downloading this repo, build the program with `make` and then run it with `./tetris`.
The game will start automatically.

Press `left_arrow` and `right_arrow` to move the falling tetronimo left and right.

Press `up_arrow` and `down_arrow` to rotate tetronimo clockwise and counter clockwise.

Press `space` to perform soft drop (drop tetronimo faster).

Press `escape` at any time to quit the game.

The game ends when a tetronimo stops at the top of the screen.
Your score will be printed out to the console.
Press `space` to play again.

## Game Rules
The game mostly uses the classic tetris rules for rotations. This means there are no wall kicks or anything like that.

The randomization uses the modern tetris rules. This means a 'bag' of the 7 unique tetronimos is created,
and a random tetronimo is selected from the 'bag' until it is empty. Then the process repeats.

The gamespeed remains constant for the whole game. See `Configuration` for how to change it.

```
Scoring:

20 points for placing a tetronimo without clearing a line

100 points for clearing 1 line

250 points for clearing 2 lines

500 points for clearing 3 lines

900 points for clearing 4 lines
```

## Configuration
The value `tile_len` at the top of the `.data` section in `tetris.asm` stores the length of each tile in pixels.
The sizes of everything in the game including the window size are based on this value.
If you want to resize the game window to better fit your screen resolution, you should change this value.

The value `interval` near the top of the `.data` section in `tetris.asm` stores the number of milliseconds between gamestate updates.
If the value of `interval` is 500, then the game will drop the falling tetronimo by one tile every 0.5 seconds.
If you want to change the speed of the game you should change this value.

To change the scoring values, modify the values of, `block_placed`, `lineclear1`, `lineclear2`, `lineclear3` and/or `lineclear4` 
in the `.data` section in `tetris.asm`
