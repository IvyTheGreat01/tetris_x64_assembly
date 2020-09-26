; Ivan Bystrov
; 13 September 2020
;
; Simple Tetris game written in NASM assembly, using Xlib, for 64 bit Linux

	; X11 functions
	extern 	XOpenDisplay
	extern 	XDefaultScreen
	extern 	XBlackPixel
	extern	XWhitePixel
	extern 	XDefaultRootWindow
	extern 	XCreateSimpleWindow
	extern	XSelectInput
	extern 	XMapWindow
	extern 	XCheckWindowEvent
	extern 	XDrawRectangle
	extern	XFillRectangle
	extern	XCreateGC
	extern	XDefaultColormap
	extern	XAllocNamedColor
	extern	XSetForeground
	extern 	XCloseDisplay
	extern 	XkbKeycodeToKeysym
	
	; libc functions
	extern	clock
	extern	printf
	extern	getrandom


; ========== bss ==========
section .bss
; Xlib handles and ints
display:	resb 8
screen: 	resb 4
black:		resb 4
white:		resb 4
r_win:		resb 8
win:		resb 8
gc_black:	resb 8
gc_color:	resb 8
colormap:	resb 8
keysym:		resb 8

; Xlib structures
xgcvals_white: 	resb 128
xgcvals_black:	resb 128
xevent:		resb 192

; Time values
clock_start:	resb 8
clock_end:	resb 8

; XColor structures
xcols:	
	struc xcol_struct
		.teal:		resb 16
		.blue:		resb 16
		.orange:	resb 16
		.yellow:	resb 16
		.green:		resb 16
		.red:		resb 16
		.purple:	resb 16
		.temp:		resb 16
	endstruc

; xcols seems to overwrite into gamemap, past its last struct
; no idea why
buffer:		resb 256

; Each byte represents one tile of the gameboard
; Must always be equal to [width] * [height]
gamemap:	resb 220



; ========== data ==========
	section .data
; Length of tiles in pixels
; ========== CHANGE THIS VALUE TO CHANGE THE GAME SIZE =========
tile_len:	dd 60

; Number of milliseconds between next game state update
; When interval == 500, tetronimos drop one tile every 0.5 seconds
; ========== CHANGE THIS VALUE TO CHANGE THE GAME SPEED ========
interval:	dd 500

; Width and height of the game board in tiles
; IF YOU CHANGE THESE VALUES YOU MUST CHANGE gamemap:
width:		dd 10
height: 	dd 22
gamemap_len:	dd 10 * 22

; Xlib constants
ExposureMask:	dq 32768
KeyPressMask:	dq 1
Expose:		dd 12
gc_foreground:	dq 4
KeyPress:	dd 2

XK_Escape:	dd 65307
XK_Left:	dd 65361
XK_Right:	dd 65363
XK_Up:		dd 65362
XK_Down:	dd 65364
XK_space:	dd 32

; time.h constants
CLOCKS_PER_SEC:	dq 1000000 ; 1 million
CLOCKS_PER_SEC_thousandths:
		dq 1000

; Masks
colormask:	db 11111110b
statusmask:	db 00000001b
fallmask:	db 00000001b
tealmask:	db 00000010b
bluemask:	db 00000100b
orangemask:	db 00001000b
yellowmask:	db 00010000b
greenmask:	db 00100000b
redmask:	db 01000000b
purplemask:	db 10000000b

; Color names
teal:		db "teal", 0
blue:		db "blue", 0
orange:		db "orange", 0
yellow:		db "yellow", 0
green:		db "green", 0
red:		db "red", 0
purple:		db "purple", 0

; Rotation vals
pivot_index:	dd 0
old_indicies:	dd 0, 0, 0, 0
new_indicies:	dd 0, 0, 0, 0
old_vals	db 0, 0, 0, 0

; Score values
total_score:	dd 0
block_placed:	dd 20
lineclear1:	dd 100
lineclear2:	dd 250
lineclear3:	dd 500
lineclear4:	dd 900

; Other vals (init to 0 each game)
softdrop:	dd 0
quit_game:	dd 0
wait_restart	dd 0

; Randomizer values
stock_array:	db 0, 1, 2, 3, 4, 5, 6
rand_array:	db 0, 0, 0, 0, 0, 0, 0
rand_val:	dd 0
global_index:	dd 7

; Strings
string:		db "hello", 10, 0
val_string:	db "val: %u", 10
score_string:	db "Score: %d", 10, 0
test_string:	db "test: %d %d", 10, 0
start_string:	db "============================", 10, "========== Tetris ==========", 10, 10, 0
end_string:	db "============================", 10, 10, 0


; ========== text ==========
	section .text
	global	main

; ---------- Spawns a new tetronimo ----------
; void SpawnTetronimo()
SpawnTetronimo:
	push	rbp
	mov	rbp, rsp
	push	rbx

	; If global index of the rand array is 7 then re-randomize
	mov	r9d, [global_index]	; r9d = global index of rand array
	xor	r11d, r11d
	cmp	r9d, 7
	cmove	r9d, r11d
	jl	spawnNextTetronimo
	
	; Store the stock_array in the rand array
	xor	ebx, ebx	; ebx = index into the arrays
initRandArrayStart:
	mov	cl, [stock_array + ebx]
	mov	[rand_array + ebx], cl
	inc	ebx
	cmp	ebx, 7
	jl	initRandArrayStart

	; Randomize the array of tetronimo ids
	xor	ebx, ebx	; ebx = index into the arrays
randomizeArrayStart:
	; getrandom(&rand_val, 4, 0)
	push	r9
	mov	rdi, rand_val
	mov	rsi, 4
	xor	rdx, rdx
	call	getrandom
	pop	r9
	; rand_val now has some random int
	mov	eax, [rand_val]
	mov	r8d, 7
	xor	rdx, rdx
	div	r8d			; edx = rand_val % 7
	mov	cl, [rand_array + ebx]	; ecx = rand_array[index]
	mov	r8b, [rand_array + edx]	; r8d = rand_array[random_index]
	mov	[rand_array + edx], cl	; store val of current index at random index
	mov	[rand_array + ebx], r8b	; store val or random index at current index
	; increment index
	inc	ebx
	cmp	ebx, 7
	jl	randomizeArrayStart
	
	; Spawn the next tetronimo onto the gamemap
spawnNextTetronimo:
	mov	r8b, [rand_array + r9d]

	; Spawn I tetronimo
	cmp	r8b, 0
	jne	endSpawnI
	mov	byte [gamemap + 3], 3
	mov	byte [gamemap + 4], 3
	mov	byte [gamemap + 5], 3
	mov	byte [gamemap + 6], 3
	mov	dword [pivot_index], 4
	jmp	returnSpawnTetronimo
endSpawnI:

	; Spawn J tetronimo
	cmp	r8b, 1
	jne	endSpawnJ
	mov	byte [gamemap + 14], 5
	mov	byte [gamemap + 15], 5
	mov	byte [gamemap + 16], 5
	mov	byte [gamemap + 4], 5
	mov	dword [pivot_index], 15
	jmp	returnSpawnTetronimo
endSpawnJ:

	; Spawn L tetronimo
	cmp	r8b, 2
	jne	endSpawnL
	mov	byte [gamemap + 14], 9
	mov	byte [gamemap + 15], 9
	mov	byte [gamemap + 16], 9
	mov	byte [gamemap + 6], 9
	mov	dword [pivot_index], 15
	jmp	returnSpawnTetronimo
endSpawnL:

	; Spawn O tetronimo
	cmp	r8b, 3
	jne	endSpawnO
	mov	byte [gamemap + 4], 17
	mov	byte [gamemap + 5], 17
	mov	byte [gamemap + 14], 17
	mov	byte [gamemap + 15], 17
	mov	dword [pivot_index], -1
	jmp	returnSpawnTetronimo
endSpawnO:

	; Spawn S tetronimo
	cmp	r8b, 4
	jne	endSpawnS
	mov	byte [gamemap + 5], 33
	mov	byte [gamemap + 6], 33
	mov	byte [gamemap + 14], 33
	mov	byte [gamemap + 15], 33
	mov	dword [pivot_index], 15
	jmp	returnSpawnTetronimo
endSpawnS:

	; Spawn Z tetronimo
	cmp	r8b, 5
	jne	endSpawnZ
	mov	byte [gamemap + 4], 65
	mov	byte [gamemap + 5], 65
	mov	byte [gamemap + 15], 65
	mov	byte [gamemap + 16], 65
	mov	dword [pivot_index], 15
	jmp	returnSpawnTetronimo
endSpawnZ:

	; Spawn T tetronimo
	cmp	r8b, 6
	jne	endSpawnT
	mov	byte [gamemap + 14], 129
	mov	byte [gamemap + 15], 129
	mov	byte [gamemap + 16], 129
	mov	byte [gamemap + 5], 129
	mov	dword [pivot_index], 15
	jmp	returnSpawnTetronimo
endSpawnT:
		
returnSpawnTetronimo:
	; Increment the global index
	inc	r9d
	mov	[global_index], r9d
	
	; Return
	pop	rbx
	pop	rbp
	ret
; ---------- Spawns a new tetronimo ----------


; ---------- Rotates all falling tiles if possible ----------
; void Rotate(dir)
; dir = -1 rotate clockwise
; dir = 1 rotate counter clockwise
Rotate:
	push	rbp
	mov	rbp, rsp
	push	rbx
	push	r12
	push	r13
	push	r14
	push	r15
	
	; If pivot == -1 don't rotate because its the O tetronimo
	mov	eax, [pivot_index]	; eax = pivot index
	cmp	eax, -1
	je	rotateReturn

	; Get the global x, y coordinates of the pivot
	xor	rdx, rdx
	mov	r8d, [width]		; r8d = width
	div	r8d			
	mov	r9d, edx		; r9d = global x of pivot
	mov	r10d, eax		; r10d = global y of pivot

	xor	r13d, r13d		; r13d = index into old/new indicies array
	xor	r14d, r14d		; r14d = index into old values array

	; Loop over the buffer and calculate rotation for each falling tile
	xor	ebx, ebx		; ebx = index of current tile
calculateRotateStart:
	; Check if this tile is falling
	xor	rcx, rcx
	mov	cl, [gamemap + ebx]	; cl = tile val
	and	cl, [statusmask]
	cmp	cl, 1
	jne	calculateRotateInc

	; Calculate the global x, y coordinates of the current tile
	xor	rdx, rdx
	mov	eax, ebx
	div	r8d
	; eax = index / width (global y coord current tile)
	; edx = index % width (global x coord current tile)
	
	; Calculate the local x, y coordinates of current tile with respect to pivot
	sub	edx, r9d
	sub	eax, r10d
	mov	r11d, edx		; r11d = local x coordinate of current tile
	mov	r12d, eax		; r12d = local y coordinate of current tile

	; Calculate new local x, y coordinates of current tile after rotation
	mov	eax, r12d
	mul	edi
	mov	r15d, eax		; r15d = temp rotated local x coordinate
	mov	eax, r11d
	push	rdi
	neg	edi
	mul	edi
	pop	rdi
	mov	r12d, eax		; r12d = rotated local y coordinate of current tile
	mov	r11d, r15d		; r11d = rotated local x coordinate of current tile
	
	; Calculate new global x, y coordinates of current tile after rotation
	add	r11d, r9d		; r11d = rotated global x coordinate of current tile
	add	r12d, r10d		; r12d = rotated global y coordinate of current tile

	; Calculate new index of rotated tile
	mov	eax, r12d
	mov	edx, [width]
	mul	edx
	add	eax, r11d		; eax = rotated index of current tile

	; Check if the rotated tile index is valid
	cmp	r11d, 0
	jl	rotateReturn		; don't rotate if rotated global x < 0
	cmp	r11d, [width]
	jge	rotateReturn		; don't rotate if rotated global x >= width
	cmp	r12d, 0
	jl	rotateReturn		; don't rotate if rotated global y < 0
	cmp	r12d, [height]
	jge	rotateReturn		; don't rotate if rotated global y >= height
	; Don't rotate if rotated index is on a stopped tile
	xor	r15b, r15b
	mov	r15b, [gamemap + eax]	; r15b = current value of new tile
	cmp	r15b, 0
	je	canRotateTile		; rotate if new tile is empty
	mov	dl, r15b
	and	dl, [statusmask]
	cmp	dl, 1
	je	canRotateTile		; rotate if new tile is falling
	jmp	rotateReturn		; don't rotate if new tile is stopped

	; This tile can be rotated so save original and new indicies for it
	; as well as the old tile val
canRotateTile:
	mov	[old_indicies + r13d], ebx
	mov	[new_indicies + r13d], eax
	add	r13d, 4
	xor	rcx, rcx
	mov	cl, [gamemap + ebx]
	mov	[old_vals + r14d], cl
	inc	r14d
	
	; Increment loop
calculateRotateInc:
	inc	ebx
	cmp	ebx, [gamemap_len]
	jl	calculateRotateStart

	; Calculated all rotations so clear all old tiles
	xor	r13d, r13d 		; index of old_indicies
clearOldTilesStart:
	mov	ebx, [old_indicies + r13d]
	mov	byte [gamemap + ebx], 0
	add	r13d, 4
	cmp	r13d, 4 * 4
	jl	clearOldTilesStart

	; Set new rotated tiles
	xor	r13d, r13d		; index of new_indicies
	xor	r14d, r14d		; index of new tile val
setNewTilesStart:
	mov	ebx, [new_indicies + r13d]
	add	r13d, 4
	mov	r8b, [old_vals + r14d]
	mov	[gamemap + ebx], r8b
	inc	r14d
	cmp	r13d, 4 * 4
	jl	setNewTilesStart

	; return
rotateReturn:
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	pop	rbp
	pop	rbp
	ret
; ---------- Rotates all falling tiles if possible


; ---------- Moves all falling tiles left or right if possible ----------
; void MoveLeftRight(dir)
; dir = -1, move left if possible
; dir = 1, move right if possible
MoveLeftRight:
	push	rbp
	mov	rbp, rsp
	push	rbx
	push	r12
	push	r13
	
	mov	r13d, 1 		; used for cmov

	; r8d = 0 if direction = -1, otherwise r8d = 1 (used for edge detection)
	xor	r8d, r8d
	cmp	edi, 1
	cmove	r8d, edi

	; Check to see if any falling tiles can't move in the right direction
	mov	ecx, [gamemap_len]
	xor	rbx, rbx		; ebx = index
canMoveLeftRightStart:
	mov	r10b, [gamemap + ebx]	; r10b = value of tile at index
	; Check if current tile is falling
	and	r10b, [statusmask]
	cmp	r10b, 1
	jne	canMoveLeftRightInc
	; Current tile is falling so check if it can move
	mov	r10b, [gamemap + ebx]
	mov	eax, ebx
	add	eax, r8d		; eax = index or eax = index + 1
	mov	r11d, [width]		; r11d = width
	xor	rdx, rdx
	div	r11d			; edx = (index + dirmod) % width
	cmp	edx, 0
	je	returnMoveLeftRight	; tile can't move because its on incompatible edge
	; Check if tile to the left/right of it is stopped
	mov	r11d, ebx
	add	r11d, edi
	mov	r10b, [gamemap + r11d]	; r10b = value of tile curr tile will move into
	xor	r11d, r11d
	cmp	r10b, 0
	cmovne	r11d, r13d		; r11d = 1 if side tile is not empty
	and	r10b, [statusmask]
	xor	r12, r12
	cmp	r10b, 0
	cmove	r12d, r13d		; r12d = 1 if side tile is not falling
	and	r11d, r12d		; r11d = 1 if side tile is stopped
	cmp	r11d, 1
	je	returnMoveLeftRight	; tile can't move because it will move on stopped tile
canMoveLeftRightInc:
	inc	ebx
	cmp	ebx, ecx
	jl	canMoveLeftRightStart
canMoveLeftRightEnd:

	; All tiles can move so move them all
	mov	ebx, 1
	mov	r11d, 1
	mov	r9d, -1
	cmp	edi, 1
	cmove	ebx, ecx		; ebx = index
	cmove	r11d, r9d		; r9d = index incrementor or decrementor
	dec	ebx			
	; if moving right, index starts at end and decrements
	; if moving left, index starts at start and increments
doMoveStart:
	mov	r10b, [gamemap + ebx]	; r10b = value of tile at index
	; Check if current tile is falling
	and	r10b, [statusmask]
	cmp	r10b, 1
	jne	doMoveIncDec
	; Current tile is falling so move it
	mov	r10b, [gamemap + ebx]
	mov	byte [gamemap + ebx], 0
	add	ebx, edi		; move the index left or right
	mov	byte [gamemap + ebx], r10b
doMoveIncDec:
	add	ebx, r11d
	cmp	ebx, ecx
	je	doMoveEnd
	cmp	ebx, -1
	je	doMoveEnd
	jmp	doMoveStart
doMoveEnd:

	; All tiles moved so also move pivot if its non negative
	mov	ecx, [pivot_index]
	cmp	ecx, 0
	jl	returnMoveLeftRight
	add	ecx, edi
	mov	[pivot_index], ecx

	; Return
returnMoveLeftRight:
	pop	r13
	pop	r12
	pop	rbx
	pop	rbp
	ret
; ---------- Moves all falling tiles left or right if possible ----------


; ---------- Clears all rows that are full, and updates score ----------
; int ClearRows()
; return 1 if stopped tile found on top two rows (game end)
; else return 0
ClearRows:
	push	rbp
	mov	rbp, rsp
	push	rbx
	push	r12
	push	r13
	push	r14
	push	r15

	mov	r14d, 1			; used for cmovs
	 
	; Loop over each row from bottom to top
	xor	r12d, r12d		;r12d = number of rows cleared
	mov	ebx, [height]		; ebx = row (checking rows loop)
	dec	ebx
loopRowsStart:
	; Loop over each column in current row
	xor	ecx, ecx		; ecx = col
	xor	r8d, r8d		; r8d = number of stopped tiles per row
	mov	eax, [width]
	mul	ebx			; eax = (width * row)
loopColsStart:
	; Get the value of the current tile
	mov	r9b, [gamemap + eax]	; r9b = value of current tile
	inc	eax
	; Check if this tile is stopped
	xor	r10d, r10d
	cmp	r9b, 0
	cmovne	r10d, r14d		; r10d = 1 if tile is not empty
	and	r9b, [statusmask]
	xor	r11d, r11d
	cmp	r9b, 1
	cmovne	r11d, r14d		; r11d = 1 if tile is not falling
	and	r10d, r11d		; r10d = 1 if tile is stopped
	cmp	r10d, 1
	jne	loopColsInc
	; Increment number of stopped tiles in this row if tile is stopped
	inc	r8d

	; Return 1 if this tile is stopped on the top two rows
	mov	r15d, [width]
	add	r15d, r15d		; 15d = smallest non game ending stopped index
	inc	r15d
	cmp	eax, r15d
	jge	loopColsInc
	mov	eax, 1
	jmp	returnClearRows

loopColsInc:
	inc	ecx
	cmp	ecx, [width]
	jl	loopColsStart

	; Check if stopped == width for this row
	cmp	r8d, [width]
	jne	loopRowsDec
	; Increment number of rows cleared
	inc	r12d

	; Clear current row
	xor	ecx, ecx
	mov	eax, [width]
	mul	ebx			; eax = (row * width)
clearRowStart:
	mov	byte [gamemap + eax], 0	; clear this tile
	inc	eax
clearRowInc:
	inc	ecx
	cmp	ecx, [width]
	jl	clearRowStart

	; Drop every tile of every row down by one, starting at row above current row
	mov	r13d, ebx		; r13d = row (dropping rows loop)
	dec	r13d
dropRowsStart:
	; Loop over each column of this row and drop the tile down by one
	xor	ecx, ecx
	mov	eax, [width]
	mul	r13d			; eax = (row * width)
dropColsStart:
	mov	r9b, [gamemap + eax]
	mov	byte [gamemap + eax], 0	; clear current tile
	mov	edx, eax
	add	edx, [width]		; edx = (row * width) + width ie. one tile down
	mov	[gamemap + edx], r9b	; drop current tile down one row
	inc	eax
dropColsInc:
	inc	ecx
	cmp	ecx, [width]
	jl	dropColsStart

dropRowsDec:
	dec	r13d
	cmp	r13d, 0
	jge	dropRowsStart

	inc	ebx			; check this row again because we dropped above row into it	
loopRowsDec:
	dec	ebx
	cmp	ebx, 0
	jge	loopRowsStart
	
	; Update score
	mov	ecx, [total_score]
	xor	edx, edx
	; Add correct score if cleared no lines
	cmp	r12d, 0
	mov	ebx, [block_placed]
	cmove	edx, ebx
	; Add correct score if cleared exactly one line
	cmp	r12d, 1
	mov	ebx, [lineclear1]
	cmove	edx, ebx
	; Add correct score if cleared exactly two lines
	cmp	r12d, 2
	mov	ebx, [lineclear2]
	cmove	edx, ebx
	; Add correct score if cleared exactly three lines
	cmp	r12d, 3
	mov	ebx, [lineclear3]
	cmove	edx, ebx
	; Add correct score if cleared exactly four lines
	cmp	r12d, 4
	mov	ebx, [lineclear4]
	cmove	edx, ebx

	; Add to the total score
	add	ecx, edx
	mov	[total_score], ecx
	
	; Return
	xor	eax, eax
returnClearRows:
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	pop	rbx
	pop	rbp
	ret
; ---------- Clears all rows that are full, and updates score ----------


; ---------- Stops all falling tiles if at least one should be stopped, otherwise drops all falling down one tile ----------
; int StopDropAllFalling()
; output = 1 if falling were stopped
; output = 0 if falling were not stopped
StopDropAllFalling:
	push	rbp
	mov	rbp, rsp
	push	rbx

	; Loop over the buffer
	xor	r9d, r9d
	mov	ecx, [gamemap_len]
	mov	ebx, 0
	mov	eax, 1
checkFallingLoopStart:		
	mov	dl, [gamemap + ebx]
	and	dl, [statusmask]
	cmp	dl, 0
	je	checkFallingLoopInc	; Next index if dl isn't a falling tile

	; This is a falling tile
	mov	r8d, ecx
	sub	r8d, [width]
	cmp	r8d, ebx
	cmovle	r9d, eax		; Stop all falling if this tile is on last row
	jl	checkFallingLoopEnd
	mov	r10d, ebx
	add	r10d, [width]
	mov	r8b, [gamemap + r10d]
	xor	r10d, r10d
	cmp	r8b, 0
	cmovne	r10d, eax		; r10d = 1 if tile below is not empty
	and	r8b, [statusmask]
	xor	r11d, r11d
	cmp	r8b, 0
	cmove	r11d, eax		; r11d = 1 if tile below is not falling
	and	r10d, r11d		; r10d = 1 if tile below this is stopped
	cmp	r10d, 1
	cmove	r9d, eax
	je	checkFallingLoopEnd	; Stop all falling if there is stopped tile below this tile
checkFallingLoopInc:
	inc	ebx
	cmp	ebx, ecx
	jne	checkFallingLoopStart
checkFallingLoopEnd:
	
	; If we must, loop over the gamemap and stop all falling tiles
	cmp	r9d, 0	
	je	stopFallingLoopEnd
	mov	ebx, ecx
	dec	ebx
stopFallingLoopStart:
	mov	dl, [gamemap + ebx]
	and	dl, [statusmask]
	cmp	dl, 0
	je	stopFallingLoopDec	; Next index if dl is not falling	
	; This tile is falling, so stop it
	mov	dl, [gamemap + ebx]
	dec	dl
	mov	[gamemap + ebx], dl
stopFallingLoopDec:
	dec	ebx
	cmp	ebx, 0
	jge	stopFallingLoopStart
stopFallingLoopEnd:
	
	; If we don't stop falling tiles, loop over gamemap (from bottom up) and drop all falling by one
	cmp	r9d, 1
	je	dropFallingLoopEnd
	mov	ebx, ecx
	dec	ebx
dropFallingLoopStart:
	mov	dl, [gamemap + ebx]
	and	dl, [statusmask]
	cmp	dl, 0
	je	dropFallingLoopDec	; Next index if dl is not falling
	; This tile is falling so drop it
	mov	dl, [gamemap + ebx]
	mov	byte [gamemap + ebx], 0
	mov	eax, ebx
	add	eax, [width]
	mov	[gamemap + eax], dl
dropFallingLoopDec:
	dec	ebx
	cmp	ebx, 0
	jge	dropFallingLoopStart
dropFallingLoopEnd:
	
	; Return
	mov	eax, r9d
	pop	rbx
	pop	rbp
	ret
; ---------- Stops all falling tiles if at least one should be stopped, otherwise drops all falling down one tile ----------


; ---------- Allocates all XColor structs
; void AllocateColors()
AllocateColors:
	push	rbp
	mov	rbp, rsp
	
	; XAllocNamedColor(display, colormap, "teal", xcol_struct.teal, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, teal
	mov	rcx, xcols
	add	rcx, xcol_struct.teal
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor
	
	; XAllocNamedColor(display, colormap, "blue", xcol_struct.blue, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, blue
	mov	rcx, xcols
	add	rcx, xcol_struct.blue
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor

	; XAllocNamedColor(display, colormap, "orange", xcol_struct.orange, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, orange
	mov	rcx, xcols
	add	rcx, xcol_struct.orange
	mov	r8, xcols
	add 	r8, xcol_struct.temp
	call	XAllocNamedColor

	; XAllocNamedColor(display, colormap, "yellow", xcol_struct.yellow, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, yellow
	mov	rcx, xcols
	add	rcx, xcol_struct.yellow
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor

	; XAllocNamedColor(display, colormap, "green", xcol_struct.green, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, green
	mov	rcx, xcols
	add	rcx, xcol_struct.green
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor

	; XAllocNamedColor(display, colormap, "red", xcol_struct.red, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, red
	mov	rcx, xcols
	add	rcx, xcol_struct.red
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor

	; XAllocNamedColor(display, colormap, "purple", xcol_struct.purple, xcol_struct.temp)
	mov	rdi, [display]
	mov	rsi, [colormap]
	mov	rdx, purple
	mov	rcx, xcols
	add	rcx, xcol_struct.purple
	mov	r8, xcols
	add	r8, xcol_struct.temp
	call	XAllocNamedColor

	; return
	pop	rbp
	ret
; ---------- Allocates all XColor structs ----------


; ---------- Draws gamemap to screen ----------
; void DrawGamemap()
DrawGamemap:
	push	rbp
	mov	rbp, rsp
	push	r12
	push	r13
	push	r14
	push	r15
	push	rbx

	; constant r12d = length of gamemap
	mov	r12d, [gamemap_len]

	; ebx = index (skips first two rows of gamemap)
	mov	ebx, [width]
	add	ebx, ebx

	; Loop over the buffer and draw the correct colour at the right pixels
	; Skip first two rows of gamemap because they are above the screen
drawingLoopStart:
	; r13d = x_pxl
	mov	eax, [width]
	mov	ecx, [tile_len]
	mul	ecx
	mov	ecx, eax		; ecx = width * tile_len
	mov	eax, ebx
	mov	r8d, [tile_len]
	mul	r8d			; eax = index * tile_len
	xor	rdx, rdx
	div	ecx			; edx = (index * tile_len) % (width * tile_len)
	mov	r13d, edx		; r13d = (index * tile_len) % (width * tile_len)

	; r14d = y_pxl
	mov	eax, 2
	mov	ecx, [tile_len]
	mul	ecx
	mov	ecx, eax		; ecx = 2 * tile_len
	mov	eax, ebx
	mov	r8d, [width]
	xor	rdx, rdx
	div	r8d			; eax = index / width
	mov	r8d, [tile_len]
	mul	r8d			; eax = (index / width) * tile_len
	sub	eax, ecx		; eax = ((index / width) * tile_len) - (2 * tile_len)
	mov	r14d, eax		; r14d = ((index / width) * tile_len) - (2 * tile_len)

	; If gamemap[index] == 0 draw with gc_black, Else draw with gc_color
	mov	r15d, [gc_color]
	mov	cl, [gamemap + ebx]
	cmp	cl, 0
	cmove	r15d, [gc_black]
	je	draw

	; If gamemap[index] != 0, set r11 to correct offset multiple into xcols struct
	mov	dl, cl
	and	dl, [tealmask]
	cmp	dl, 0
	mov	eax, 0
	cmovne	r11d, eax		; Set r11 to 0 if tile teal
	jne	setColor

	mov	dl, cl
	and	dl, [bluemask]
	cmp	dl, 0
	mov	eax, 1
	cmovne	r11d, eax		; Set r11 to 1 if tile blue
	jne	setColor

	mov	dl, cl
	and	dl, [orangemask]
	cmp	dl, 0
	mov	eax, 2
	cmovne	r11d, eax		; Set r11 to 2 if tile orange
	jne	setColor

	mov	dl, cl
	and	dl, [yellowmask]
	cmp	dl, 0
	mov	eax, 3
	cmovne	r11d, eax		; Set r11 to 3 if tile yellow
	jne	setColor

	mov	dl, cl
	and	dl, [greenmask]
	cmp	dl, 0
	mov	eax, 4
	cmovne	r11d, eax		; Set r11 to 4 if tile green
	jne	setColor

	mov	dl, cl
	and	dl, [redmask]
	cmp	dl, 0
	mov	eax, 5
	cmovne	r11d, eax		; Set r11 to 5 if tile red
	jne	setColor

	mov	dl, cl
	and	dl, [purplemask]
	cmp	dl, 0				
	mov	eax, 6
	cmovne	r11d, eax		; Set r11 to 6 if tile purple

setColor:
	; void XSetForeground(display, gc_draw, XColor.pixel)
	mov	eax, 16
	mul	r11d
	mov	rdi, [display]
	mov	rsi, r15
	mov	rdx, [xcols + eax]	; offsetof(XColor, pixel) == 0
	sub	rsp, 8
	call	XSetForeground
	add	rsp, 8

draw:
	; void XDrawRectangle(display, window, gc, x_pxl, y_pxl, tile_len, tile_len)
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, r15
	mov	rcx, r13
	mov	r8, r14
	mov	r9, [tile_len]
	push	r9
	call	XDrawRectangle
	pop	r9

	; void XFillRectangle(display, window, gc, x_pxl, y_pxl, tile_len, tile_len)
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, r15
	mov	rcx, r13
	mov	r8, r14
	mov	r9, [tile_len]
	push	r9
	call	XFillRectangle
	pop	r9
	
	; Increment index and check if its still valid
	inc	ebx
	cmp	ebx, r12d
	jl	drawingLoopStart
	
	; Restore preserved registers and return
	pop	rbx
	pop	r15
	pop	r14
	pop	r13
	pop	r12
	pop	rbp
	ret
; ---------- Draws gamemap to screen ---------


; ---------- Starting point of the program ----------
main:
	; Print start string
	mov	rdi, start_string
	sub	rsp, 8
	call	printf
	add	rsp, 8

	; Display* XOpenDisplay(NULL)
	mov	rdi, 0
	sub	rsp, 8
	call 	XOpenDisplay
	mov	[display], rax
	add	rsp, 8

	; int XDefaultScreen(display)
	mov	rdi, [display]
	sub	rsp, 8
	call	XDefaultScreen
	mov	[screen], eax
	add	rsp, 8

	; int XBlackPixel(display, screen)
	mov	rdi, [display]
	mov	rsi, [screen]
	sub	rsp, 8
	call	XBlackPixel
	mov	[black], eax
	add	rsp, 8

	; int XWhitePixel(display, screen)
	mov	rdi, [display]
	mov	rsi, [screen]
	sub	rsp, 8
	call	XWhitePixel
	mov	[white], eax
	add	rsp, 8

	; Window XDefaultRootWindow(display)
	mov	rdi, [display]
	sub	rsp, 8
	call	XDefaultRootWindow
	mov	[r_win], rax
	add	rsp, 8

	; Window XCreateSimpleWindow(display, r_win, 0, 0, width * tilelen, (height - 2) * tile_len, 0, black, black)
	mov	rdi, [display]
	mov	rsi, [r_win]
	mov	rdx, 0
	mov	rcx, 0

	mov	ebx, [tile_len]
	mov	eax, [width]
	mul	ebx
	mov	r8d, eax
	mov	eax, [height]
	sub	eax, 2
	mul	ebx
	mov 	r9d, eax

	mov	rax, 0
	push	rax
	mov	eax, [black]
	push	rax
	push 	rax

	call	XCreateSimpleWindow
	mov	[win], rax
	add	rsp, 24

	; GC XCreateGC(display, win, GCForeground, &values_white)
	mov	ecx, [white]
	mov	[xgcvals_white + 16], ecx	; offsetof(XGCValues, foreground) == 16
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, [gc_foreground]
	mov	rcx, xgcvals_white
	sub	rsp, 8
	call	XCreateGC
	mov	[gc_color], rax
	add	rsp, 8

	; GC XCreateGC(display, win, GCForeground, &values_black)
	mov	ecx, [black]
	mov	[xgcvals_black + 16], ecx	; offsetof(XGCValues, foreground) == 16
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, [gc_foreground]
	mov	rcx, xgcvals_black
	sub	rsp, 8
	call	XCreateGC
	mov	[gc_black], rax
	add	rsp, 8

	; Colormap XDefaultColormap(display, screen)
	mov	rdi, [display]
	mov	esi, [screen]
	sub	rsp, 8
	call	XDefaultColormap
	mov	[colormap], rax
	add	rsp, 8

	; Allocate all colors
	sub	rsp, 8
	call	AllocateColors
	add	rsp, 8	

	; void XSelectInput(display, win, ExposureMask | KeyPressMask)
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, [ExposureMask]
	or	rdx, [KeyPressMask]
	sub	rsp, 8
	call	XSelectInput
	add	rsp, 8
	
	; void XMapWindow(display, win)
	mov	rdi, [display]
	mov	rsi, [win]
	sub	rsp, 8
	call	XMapWindow
	add	rsp, 8
	
	; Start the game
startGame:
	; Reset some core values
	mov	dword [quit_game], 0
	mov	dword [global_index], 7
	mov	dword [wait_restart], 0
	mov	dword [total_score], 0
	
	; Clear gamemap at start of game
	xor	ebx, ebx
clearGamemapStart:
	mov	byte [gamemap + ebx], 0
	inc	ebx
	cmp	ebx, [gamemap_len]
	jl	clearGamemapStart

	; Spawn first tetronimo
	sub	rsp, 8
	call	SpawnTetronimo
	add	rsp, 8
	
	; clock_start = clock()
	sub	rsp, 8
	call	clock
	mov	[clock_start], rax
	add	rsp, 8

	; Infinite Game loop
gameLoop:
	; ----- Process Events -----
	; bool XCheckWindowEvent(display, win, ExposureMask | KeyPressMask, &xevent)
	mov	rdi, [display]
	mov	rsi, [win]
	mov	rdx, [ExposureMask]
	or	rdx, [KeyPressMask]
	mov	rcx, xevent
	sub	rsp, 8
	call	XCheckWindowEvent
	add	rsp, 8

	; if (XCheckWindowEvent)
	cmp	rax, 1
	jne	endProcessEvents

	; if (xevent.type == Expose)
	mov	ecx, [xevent + 0] 	; offsetof(Xevent, type) == 0
	cmp	ecx, [Expose]
	jne	endProcessExpose
	
	; Draw the gamemap to the screen	
	sub	rsp, 8	
	call	DrawGamemap
	add	rsp, 8
	jmp	endProcessEvents
endProcessExpose:

	; if (xevent.type == KeyPress)
	mov	ecx, [xevent + 0]	; offsetof(Xevent, type) == 0
	cmp	ecx, [KeyPress]
	jne	endProcessKeyPress
	
	; KeySym XkbKeycodeToKeysym(dpy, keycode, 0, 0)
	mov	rdi, [display]
	mov	esi, [xevent + 84]	; offsetof(Xevent, xkey) == 0
	mov	rdx, 0			; offsetof(Xevent.xkey, keycode) == 84
	mov	rcx, 0
	sub	rsp, 8
	call	XkbKeycodeToKeysym
	mov	[keysym], rax	
	add	rsp, 8
	
	mov	ecx, [keysym]

	; if (keysym == XK_Escape) exit
	cmp	ecx, [XK_Escape]
	jne	endProcessEscape	
		
	mov	dword [quit_game], 1
	jmp	gameEnd
endProcessEscape:

	; if wait_restart == 1 and (keysym == XK_space) restart the game
	cmp	dword [wait_restart], 1
	jne	endWaitRestart
	cmp	ecx, [XK_space]
	je	startGame
	jmp	gameLoop	
endWaitRestart:
	
	; if (keysym == XK_Left) move left
	cmp	ecx, [XK_Left]
	jne	endProcessLeft
	
	; Move all falling tiles left if possible
	mov	rdi, -1
	sub	rsp, 8
	call	MoveLeftRight
	add	rsp, 8
endProcessLeft:

	; if (keysym == XK_Right) move right
	cmp	ecx, [XK_Right]
	jne	endProcessRight
	
	; Move all falling tiles right if possible
	mov	rdi, 1
	sub	rsp, 8
	call	MoveLeftRight
	add	rsp, 8
endProcessRight:

	; if (keysym == XK_Down) rotate counter clockwise
	cmp	ecx, [XK_Down]
	jne	endProcessDown
	
	; Rotate falling tetronimo counter clockwise
	mov	rdi, 1
	sub	rsp, 8
	call	Rotate
	add	rsp, 8	
endProcessDown:
	
	; if (keysym == XK_Up) rotate clockwise
	cmp	ecx, [XK_Up]
	jne	endProcessUp

	; Rotate falling tetronimo clockwise
	mov	rdi, -1
	sub	rsp, 8
	call	Rotate
	add	rsp, 8
endProcessUp:

	; if (keysym == XK_space) soft drop
	cmp	ecx, [XK_space]
	jne	endProcessSpace
	mov	dword [softdrop], 1	
endProcessSpace:

endProcessKeyPress:

	; Draw the gamemap to the screen after processing keypress
	sub	rsp, 8
	call	DrawGamemap
	add	rsp, 8

endProcessEvents:
	; ----- Process Events -----

	; ----- Process next gamestate -----
	; only process gamestate if not waiting for restart
	cmp	dword [wait_restart], 1
	je	gameLoop

	; clock_end = clock()
	sub	rsp, 8
	call	clock
	mov	[clock_end], rax
	add	rsp, 8

	; if ((clock_end - clock_start) >= interval * CLOCKS_PER_SEC) || softdrop == true
	xor	r9d, r9d
	xor	r10d, r10d
	mov	r11d, 1
	mov	rcx, [clock_end]
	sub	rcx, [clock_start]
	mov	rax, [CLOCKS_PER_SEC_thousandths]
	mov	edx, [interval]
	mul	rdx
	cmp	rcx, rax
	cmovl	r9d, r11d		; r9d = 1 if not yet time for process
	cmp	dword [softdrop], 0
	cmove	r10d, r11d		; r10d = 1 if not softdrop
	and	r9d, r10d		; r9d = 1 if don't process
	cmp	r9d, 1
	je	endProcessGameState
	
	mov	dword [softdrop], 0

	; clock_start = clock()
	sub	rsp, 8
	call	clock
	mov	[clock_start], rax
	add	rsp, 8

	; Stop all falling tiles if at least one falling tile is on last row or on top of stopped tile
	sub	rsp, 8
	call	StopDropAllFalling
	add	rsp, 8
	
	; If didn't stop all falling tiles, then drop pivot index by 1 if its non negative
	cmp	eax, 0
	jne	endDecrementPivot
	mov	ecx, [pivot_index]
	cmp	ecx, 0
	jl	endDecrementPivot
	add	ecx, [width]
	mov	[pivot_index], ecx
endDecrementPivot:

	; if stopped falling tiles, clear rows if possible
	cmp	eax, 0
	je	skipClearRows
	sub	rsp, 8
	call	ClearRows
	add	rsp, 8

	; If ClearRows returned 1, end the game
	cmp	eax, 1
	je	gameEnd

	; Since tiles were stopped spawn a new tetronimo
	sub	rsp, 8
	call	SpawnTetronimo
	add	rsp, 8
skipClearRows:
	
	; Draw gamemap to the screen
	sub	rsp, 8
	call	DrawGamemap
	add	rsp, 8
endProcessGameState:
	; ----- Process next gamestate -----

	jmp	gameLoop 

	; Game is over
gameEnd:
	; If player wants to quit let them exit
	cmp	dword [quit_game], 1
	je	return
	
	; Print out score at end of game
	mov	rdi, score_string
	mov	esi, [total_score]
	sub	rsp, 8
	call	printf
	add	rsp, 8

	; Wait until restart
	mov	dword [wait_restart], 1
	jmp	gameLoop

	; Quit the game
return:
	; Print end string
	mov	rdi, end_string
	sub	rsp, 8
	call	printf
	add	rsp, 8

	; XCloseDisplay(display)
	mov	rdi, [display]
	sub	rsp, 8
	call	XCloseDisplay
	add	rsp, 8
	
	; return 0
	mov	rax, 0
	ret
