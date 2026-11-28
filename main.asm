; File:mario.asm
; Author:Amna
; Module:1-Program Skeleton & DOS Setup
; Description:Video Mode 13h & Display Primitives 
; Target:NASM Assembler -> DOSBox (16-bit Real Mode)
[org 0x100]    

;                        SYSTEM CONSTANTS & DEFINITIONS (EQU Statements)

;1.Display & Grid Constants 
SCREEN_WIDTH  equ 320         ; VGA Mode 13h width in pixels
SCREEN_HEIGHT  equ 200         ; VGA Mode 13h height in pixels
TILE_SIZE      equ 16          ; Standard tile dimensions (16x16)
GRID_COLS      equ 20          ; Visible tile columns per screen
GRID_ROWS      equ 12          ; Visible tile rows per screen
HUD_HEIGHT     equ 16          ; Reserved top strip height (map row 0)
LEVEL_WIDTH_TILES  equ 60          ; Minimum level width in tiles
LEVEL_WIDTH_PX    equ 960         ; Level width in pixels (60 * 16)
MAX_CAMERA_X      equ 640         ; Camera max offset (LEVEL_WIDTH_PX - 320)
COLOR_TRANSPARENT  equ 0           ; Index 0 reserved for transparency

;2.Keyboard Scan Codes
KEY_LEFT     equ 4Bh         ; Left Arrow
KEY_RIGHT     equ 4Dh         ; Right Arrow
KEY_UP        equ 48h         ; Up Arrow
KEY_DOWN      equ 50h         ; Down Arrow
KEY_SPACE     equ 39h         ; Spacebar (Jump)
KEY_LSHIFT    equ 2Ah         ; Left Shift (Run)
KEY_P         equ 19h         ; 'P' Key (Pause)
KEY_ENTER     equ 1Ch         ; Enter Key
KEY_ESC        equ 01h         ; Escape Key

;3.Game Limits & Rules
START_LIVES    equ 3           ; Default starting lives
MAX_LIVES      equ 99          ; Maximum life cap
HP_SMALL       equ 1           ; Small Mario health
HP_SUPER      equ 2           ; Super Mario max health
START_TIME    equ 300         ; Level timer countdown (seconds)
MAX_SCORE      equ 999999      ; Maximum score cap
MAX_ACTIVE_ENEMIES  equ 8           ; Max active on-screen enemies
CAMERA_MID_X   equ 160         ; Mid-screen boundary for camera scroll

;4.Physics Constants in 8.8 Fixed-Point Format 
PHYS_ACCEL     equ 0020h       ; Walk acceleration (0.125 px/frame)
PHYS_FRICTION   equ 0010h       ; Friction decel (0.0625 px/frame)
PHYS_MAX_WALK   equ 0180h       ; Max walk speed (1.5 px/frame)
PHYS_MAX_RUN    equ 0280h       ; Max run speed (2.5 px/frame)
PHYS_GRAVITY     equ 0040h       ; Gravity per frame (0.25 px/frame)
PHYS_JUMP_START  equ 0FA80h      ; Initial jump speed (-5.5 px/frame)
PHYS_JUMP_CUTOFF  equ 0FE00h      ; Variable jump cut-off (-2.0 px/frame)
PHYS_MAX_FALL     equ 0400h       ; Max terminal fall speed (4.0 px/frame)
PHYS_STOMP_BOUNCE equ 0FD00h      ; Stomp bounce speed (-3.0 px/frame)




; PROGRAM ENTRY POINT & CODE LOGIC
start:
    call SetupProgram
    call MainLoop
    call CleanExit                  ; Returns to DOS safely

; Subroutine:SetupProgram
; Purpose: Initializes system components, off-screen frame buffer, and variables.
; Inputs: None | Outputs: None | Registers Preserved: ALL
SetupProgram:
    call InitVideoMode13h           ; Switch to VGA Mode 13h (320x200)
    call InitFrameBuffer            ; Allocate off-screen render buffer
    call HookKeyboardISR            ; Hook INT 09h custom keyboard handler
    ret

;Subroutine: MainLoop
;Purpose:    Tests Module 5 double buffering and Module 6 smooth camera scrolling.
;Inputs:     None | Outputs: None | Registers Preserved: ALL
MainLoop:
    push ax
    push cx

    call ResetMap                   ; Copy original map into working map

   push COLOR_SKY
    call ClearFrameBuffer           ; Fill off-screen buffer with sky blue

    call DrawScrolledMap            ; Render scrolled map into off-screen buffer
    call FlipFrameBuffer            ; Copy off-screen buffer to VGA screen (0A000h)

    jmp test_kbd_loop               ; Run concurrent key test (ESC exits cleanly)

; Subroutine: CleanExit
; Purpose:    Safely restores execution state and returns control to DOS.
; Inputs:     None | Outputs: None | Registers Changed: None (Exits)

test_kbd_loop:
    ; Concurrent key test: Hold RIGHT + LSHIFT + SPACE simultaneously, press ESC to exit
    cmp byte [key_states + KEY_ESC], 1
    je test_kbd_done

    ; Visual feedback on top-left HUD bar (row 0) for concurrent presses:
    ; Square 1 (x=4): Left Arrow | Square 2 (x=20): Right Arrow
    ; Square 3 (x=36): Left Shift | Square 4 (x=52): Spacebar
    xor ah, ah
    mov al, [key_states + KEY_LEFT]
    shl al, 2                       ; Color 0 (black) if released, 4 (red) if pressed
    push 4
    push 4
    push 8
    push 8
    push ax
    call FillRect

    xor ah, ah
    mov al, [key_states + KEY_RIGHT]
    shl al, 1                       ; Color 0 if released, 2 (green) if pressed
    push 20
    push 4
    push 8
    push 8
    push ax
    call FillRect

    cmp byte [key_states + KEY_LSHIFT], 1
    mov ax, 0
    jne .draw_shift
    mov ax, 14
.draw_shift:
    push 36
    push 4
    push 8
    push 8
    push ax
    call FillRect

    cmp byte [key_states + KEY_SPACE], 1
    mov ax, 0
    jne .draw_space
    mov ax, 15                      ; Color 15 (white) if pressed
.draw_space:
    push 52
    push 4
    push 8
    push 8
    push ax
    call FillRect

    jmp test_kbd_loop

test_kbd_done:
    pop ax
    ret
CleanExit:
    call UnhookKeyboardISR          ; Restore original INT 09h vector BEFORE exit
    call RestoreTextMode            ; Restore 80x25 text mode before exit
    mov ah, 4Ch                     ; INT 21h, AH=4Ch: Terminate Program
    mov al, 00h                     ; Return Code 0 (Clean exit)
    int 21h

; ==============================================================================
; MODULE 2: VIDEO MODE 13h & DISPLAY PRIMITIVES
; Author: Talia
; ==============================================================================

; Color Palette Constants
VGA_SEGMENT         equ 0A000h      ; VGA Mode 13h video memory segment
COLOR_BLACK         equ 00h         ; HUD background & outlines
COLOR_SKY           equ 35h         ; Sky blue background
COLOR_GROUND_TOP    equ 02h         ; Grass green layer
COLOR_GROUND_DIRT   equ 06h         ; Brown dirt layer
COLOR_BRICK         equ 2Ah         ; Brick block color
COLOR_QBLOCK        equ 2Ch         ; Question block yellow
COLOR_EMPTY_BLOCK   equ 16h         ; Empty/used block color
COLOR_PIPE_LIGHT    equ 2Fh         ; Pipe bright green
COLOR_PIPE_DARK     equ 02h         ; Pipe dark green
COLOR_COIN          equ 2Ch         ; Coin gold
COLOR_MARIO_RED     equ 28h         ; Mario hat & shirt
COLOR_MARIO_BLUE    equ 20h         ; Mario overalls
COLOR_MARIO_SKIN    equ 59h         ; Mario skin tone
COLOR_GOOMBA        equ 06h         ; Goomba brown
COLOR_KOOPA         equ 2Fh         ; Koopa shell green
COLOR_STAIR         equ 2Bh         ; Stair block tan
COLOR_FLAG          equ 0Ah         ; Flag pole green
COLOR_HUD_TEXT      equ 0Fh         ; White HUD text
COLOR_HEART         equ 28h         ; Red health heart
PALETTE_TEST_COUNT  equ 16          ; Number of colors in validation screen

; Procedure: InitVideoMode13h
; Purpose:   Switches display to VGA 320x200 256-color graphics mode (Mode 13h).
; Inputs:    None
; Outputs:   None
; Registers: Preserves ALL
InitVideoMode13h:
    push ax
    mov ah, 00h                     ; BIOS Set Video Mode
    mov al, 13h                     ; 320x200, 256 colors
    int 10h
    pop ax
    ret

; Procedure: RestoreTextMode
; Purpose:   Restores display to standard 80x25 text mode (Mode 03h).
; Inputs:    None
; Outputs:   None
; Registers: Preserves ALL
RestoreTextMode:
    push ax
    mov ah, 00h                     ; BIOS Set Video Mode
    mov al, 03h                     ; 80x25 color text mode
    int 10h
    pop ax
    ret

; Procedure: PutPixel
; Purpose:   Draws a single pixel at (x, y) using fast shift offset math.
; Inputs:    Stack parameters:
;              [bp+8] = x (0..319)
;              [bp+6] = y (0..199)
;              [bp+4] = color (0..255)
; Outputs:   Writes 1 byte to video memory 0A000h:(y*320 + x)
; Registers: Preserves ALL (cleans 6 bytes from stack)
PutPixel:
    push bp
    mov bp, sp
    push ax
    push bx
    push di
    push es

    ; Bounds check (unsigned compare handles negative and out-of-range values)
    mov ax, [bp+8]                  ; AX = x
    cmp ax, SCREEN_WIDTH
    jae putpixel_exit
    mov bx, [bp+6]                  ; BX = y
    cmp bx, SCREEN_HEIGHT
    jae putpixel_exit

    ; Set ES to active off-screen render buffer segment
    mov es, [render_target_seg]

    ; Offset = (y * 320) + x = (y << 8) + (y << 6) + x
    mov di, bx                      ; DI = y
    shl di, 8                       ; DI = y * 256
    shl bx, 6                       ; BX = y * 64
    add di, bx                      ; DI = y * 320
    add di, ax                      ; DI = y * 320 + x

    ; Write pixel color
    mov ax, [bp+4]                  ; AL = color
    mov [es:di], al

putpixel_exit:
    pop es
    pop di
    pop bx
    pop ax
    pop bp
    ret 6

; Procedure: FillRect
; Purpose:   Draws a solid filled rectangle of width w and height h at (x, y).
; Inputs:    Stack parameters:
;              [bp+12] = x (top-left X)
;              [bp+10] = y (top-left Y)
;              [bp+8]  = w (width in pixels)
;              [bp+6]  = h (height in pixels)
;              [bp+4]  = color (0..255)
; Outputs:   Writes w*h bytes to video memory
; Registers: Preserves ALL (cleans 10 bytes from stack)
FillRect:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    ; Check for valid positive width and height
    mov cx, [bp+8]                  ; CX = w
    cmp cx, 0
    jle fillrect_exit
    mov dx, [bp+6]                  ; DX = h
    cmp dx, 0
    jle fillrect_exit

    ; Set ES to VGA segment 0A000h and clear direction flag
    mov es, [render_target_seg]
    cld

    ; Starting offset: DI = (y << 8) + (y << 6) + x
    mov bx, [bp+10]                 ; BX = y
    mov di, bx                      ; DI = y
    shl di, 8                       ; DI = y * 256
    shl bx, 6                       ; BX = y * 64
    add di, bx                      ; DI = y * 320
    add di, [bp+12]                 ; DI = y * 320 + x

    mov al, [bp+4]                  ; AL = color

fillrect_row_loop:
    push di                         ; Save start of current row
    mov cx, [bp+8]                  ; CX = width
    rep stosb                       ; Fill row with color in AL
    pop di                          ; Restore start of current row
    add di, SCREEN_WIDTH            ; Move down one row (+320 bytes)
    dec dx                          ; Decrement remaining rows
    jnz fillrect_row_loop

fillrect_exit:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 10

; Procedure: RenderPaletteScreen
; Purpose:   Displays solid blocks of all 16 game colors and a pixel border
;            to verify Mode 13h initialization, FillRect, and PutPixel.
; Inputs:    None
; Outputs:   Draws validation screen to VGA memory
; Registers: Preserves ALL
RenderPaletteScreen:
    push ax
    push bx
    push cx
    push dx
    push si

    ; 1. Fill screen with sky blue background
    push 0                          ; x = 0
    push 0                          ; y = 0
    push SCREEN_WIDTH               ; w = 320
    push SCREEN_HEIGHT              ; h = 200
    push COLOR_SKY                  ; color
    call FillRect

    ; 2. Draw top black HUD strip (row 0, height 16)
    push 0                          ; x = 0
    push 0                          ; y = 0
    push SCREEN_WIDTH               ; w = 320
    push HUD_HEIGHT                 ; h = 16
    push COLOR_BLACK                ; color
    call FillRect

    ; 3. Draw 16 framed color swatches (4 columns x 4 rows)
    xor si, si                      ; SI = table index (0..15)
    mov dx, 28                      ; DX = starting Y

palette_row_loop:
    mov cx, 32                      ; CX = starting X

palette_col_loop:
    ; Outer black border (52x32)
    push cx
    push dx
    push 52
    push 32
    push COLOR_BLACK
    call FillRect

    ; Inner color block (48x28)
    mov ax, cx
    add ax, 2
    push ax                         ; x + 2
    mov ax, dx
    add ax, 2
    push ax                         ; y + 2
    push 48                         ; w = 48
    push 28                         ; h = 28
    xor ah, ah
    mov al, [palette_test_table + si]
    push ax                         ; color
    call FillRect

    inc si
    cmp si, PALETTE_TEST_COUNT
    jae palette_pixel_line

    add cx, 68                      ; Next column X
    cmp cx, 300
    jb palette_col_loop

    add dx, 40                      ; Next row Y
    jmp palette_row_loop

    ; 4. Test PutPixel by drawing a white horizontal line at y = 190
palette_pixel_line:
    xor cx, cx                      ; CX = x (0..319)

palette_pixel_loop:
    push cx                         ; x
    push 190                        ; y
    push COLOR_HUD_TEXT             ; white color
    call PutPixel

    inc cx
    cmp cx, SCREEN_WIDTH
    jb palette_pixel_loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; ==============================================================================
; MODULE 3: LEVEL MAP AND TILE DRAWING
; Author: Rayyan
; ==============================================================================

; Tile Code Constants (Appendix A.2)
TILE_SKY            equ 00h         ; Empty sky (non-solid)
TILE_GROUND         equ 01h         ; Ground block (solid)
TILE_BRICK          equ 02h         ; Breakable brick block (solid)
TILE_QBLOCK_COIN    equ 03h         ; Question block with coin (solid)
TILE_QBLOCK_MUSH    equ 04h         ; Question block with mushroom (solid)
TILE_EMPTY_BLOCK    equ 05h         ; Used/empty block (solid)
TILE_PIPE_TL        equ 06h         ; Pipe top-left (solid)
TILE_PIPE_TR        equ 07h         ; Pipe top-right (solid)
TILE_PIPE_BL        equ 08h         ; Pipe body-left (solid)
TILE_PIPE_BR        equ 09h         ; Pipe body-right (solid)
TILE_STAIR          equ 0Ah         ; Stair / flagpole base block (solid)
TILE_COIN           equ 0Bh         ; Free-floating coin (non-solid)
TILE_FLAGPOLE       equ 0Ch         ; Flagpole segment (non-solid, win trigger)

LEVEL_MAP_BYTES     equ LEVEL_WIDTH_TILES * GRID_ROWS ; 60 * 12 = 720 bytes

; Procedure: ResetMap
; Purpose:   Restores the working level map from the untouched original level map
;            using a fast block memory transfer (REP MOVSB).
; Inputs:    None
; Outputs:   Overwrites level_map_work with level_map_orig (720 bytes)
; Registers: Preserves ALL
ResetMap:
    push ax
    push cx
    push si
    push di
    push ds
    push es

    mov ax, cs
    mov ds, ax                      ; Ensure DS = CS (.COM single segment)
    mov es, ax                      ; Ensure ES = CS
    cld                             ; Forward direction

    mov si, level_map_orig          ; Source: original level layout
    mov di, level_map_work          ; Destination: active working level layout
    mov cx, LEVEL_MAP_BYTES         ; 720 bytes (60 cols x 12 rows)
    rep movsb                       ; Copy entire map in one block instruction

    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; Procedure: GetTile
; Purpose:   Looks up the tile code in level_map_work at world pixel coordinates (px, py).
; Inputs:    Stack parameters:
;              [bp+6] = px (world X in pixels, 0..959)
;              [bp+4] = py (world Y in pixels, 0..191)
; Outputs:   AL = tile code at (px / 16, py / 16) (returns TILE_SKY if out of bounds)
; Registers: Modifies AX (return value in AL); preserves all other registers (cleans 4 bytes)
GetTile:
    push bp
    mov bp, sp
    push bx
    push cx
    push si

    ; Validate world pixel coordinates
    mov ax, [bp+6]                  ; AX = px
    cmp ax, LEVEL_WIDTH_PX          ; Must be < 960
    jae gettile_out_of_bounds

    mov bx, [bp+4]                  ; BX = py
    cmp bx, 192                     ; Must be < 192 (12 rows * 16 px)
    jae gettile_out_of_bounds

    ; Convert pixels to tile grid indices: col = px >> 4, row = py >> 4
    shr ax, 4                       ; AX = tile_col (0..59)
    shr bx, 4                       ; BX = tile_row (0..11)

    ; Compute 1D array offset: offset = (tile_row * 60) + tile_col
    ; Using shifts: row * 60 = (row * 64) - (row * 4) = (row << 6) - (row << 2)
    mov si, bx                      ; SI = tile_row
    shl si, 6                       ; SI = row * 64
    mov cx, bx
    shl cx, 2                       ; CX = row * 4
    sub si, cx                      ; SI = row * 60
    add si, ax                      ; SI = row * 60 + tile_col

    xor ah, ah
    mov al, [level_map_work + si]   ; Fetch tile byte from working map
    jmp gettile_done

gettile_out_of_bounds:
    mov ax, TILE_SKY                ; Default non-solid sky outside map bounds

gettile_done:
    pop si
    pop cx
    pop bx
    pop bp
    ret 4

; Procedure: DrawTile
; Purpose:   Renders a 16x16 tile graphic at screen coordinates (screen_x, screen_y)
;            based on the given tile code using FillRect primitives.
; Inputs:    Stack parameters:
;              [bp+8] = screen_x (top-left X on screen)
;              [bp+6] = screen_y (top-left Y on screen)
;              [bp+4] = tile_code (00h..0Ch)
; Outputs:   Draws 16x16 tile pixels to VGA memory
; Registers: Preserves ALL (cleans 6 bytes from stack)
DrawTile:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx

    mov bx, [bp+8]                  ; BX = screen_x
    mov cx, [bp+6]                  ; CX = screen_y
    mov ax, [bp+4]                  ; AL = tile_code

    ; 1. Fill base 16x16 tile background with sky blue first
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_SKY
    call FillRect

       ; Dispatch based on tile_code.
    ; Conditional jumps stay nearby; JMP handles the longer destination.

    cmp al, TILE_SKY
    jne .check_ground
    jmp drawtile_mid_exit

.check_ground:
    cmp al, TILE_GROUND
    jne .check_brick
    jmp drawtile_ground

.check_brick:
    cmp al, TILE_BRICK
    jne .check_qblock_coin
    jmp drawtile_brick

.check_qblock_coin:
    cmp al, TILE_QBLOCK_COIN
    je .draw_qblock
    cmp al, TILE_QBLOCK_MUSH
    jne .check_empty
.draw_qblock:
    jmp drawtile_qblock

.check_empty:
    cmp al, TILE_EMPTY_BLOCK
    jne .check_pipe_tl
    jmp drawtile_empty

.check_pipe_tl:
    cmp al, TILE_PIPE_TL
    je .draw_pipe_top
    cmp al, TILE_PIPE_TR
    jne .check_pipe_bl
.draw_pipe_top:
    jmp drawtile_pipe_top

.check_pipe_bl:
    cmp al, TILE_PIPE_BL
    je .draw_pipe_body
    cmp al, TILE_PIPE_BR
    jne .check_stair
.draw_pipe_body:
    jmp drawtile_pipe_body

.check_stair:
    cmp al, TILE_STAIR
    jne .check_coin
    jmp drawtile_stair

.check_coin:
    cmp al, TILE_COIN
    jne .check_flagpole
    jmp drawtile_coin

.check_flagpole:
    cmp al, TILE_FLAGPOLE
    jne .unknown_tile
    jmp drawtile_flagpole

.unknown_tile:
    jmp drawtile_exit
drawtile_ground:
    ; Top 4px grass strip
    push bx
    push cx
    push TILE_SIZE
    push 4
    push COLOR_GROUND_TOP
    call FillRect
    ; Bottom 12px brown dirt
    mov ax, cx
    add ax, 4
    push bx
    push ax
    push TILE_SIZE
    push 12
    push COLOR_GROUND_DIRT
    call FillRect
    jmp drawtile_exit

drawtile_brick:
    ; Outer dark outline
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_BLACK
    call FillRect
    ; Inner brick face (14x14)
    mov ax, bx
    inc ax
    push ax
    mov ax, cx
    inc ax
    push ax
    push 14
    push 14
    push COLOR_BRICK
    call FillRect
    ; Horizontal mortar line across middle
    mov ax, cx
    add ax, 7
    push bx
    push ax
    push TILE_SIZE
    push 1
    push COLOR_BLACK
    call FillRect
    jmp drawtile_exit

drawtile_qblock:
    ; Outer black border
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_BLACK
    call FillRect
    ; Inner yellow block (14x14)
    mov ax, bx
    inc ax
    push ax
    mov ax, cx
    inc ax
    push ax
    push 14
    push 14
    push COLOR_QBLOCK
    call FillRect
    ; Simple '?' emblem in center (white)
    mov ax, bx
    add ax, 6
    push ax
    mov ax, cx
    add ax, 4
    push ax
    push 4
    push 5
    push COLOR_HUD_TEXT
    call FillRect
    mov ax, bx
    add ax, 7
    push ax
    mov ax, cx
    add ax, 10
    push ax
    push 2
    push 2
    push COLOR_HUD_TEXT
    call FillRect
    jmp drawtile_exit

drawtile_empty:
    ; Outer black border
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_BLACK
    call FillRect
    ; Inner muted empty block (14x14)
    mov ax, bx
    inc ax
    push ax
    mov ax, cx
    inc ax
    push ax
    push 14
    push 14
    push COLOR_EMPTY_BLOCK
    call FillRect
drawtile_mid_exit:
    jmp drawtile_exit

drawtile_pipe_top:
    ; Dark green base
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_PIPE_DARK
    call FillRect
    ; Bright green highlight rim
    mov ax, bx
    inc ax
    push ax
    mov ax, cx
    inc ax
    push ax
    push 14
    push 14
    push COLOR_PIPE_LIGHT
    call FillRect
    jmp drawtile_exit

drawtile_pipe_body:
    ; Narrower pipe shaft (inset by 1px)
    mov ax, bx
    inc ax
    push ax
    push cx
    push 14
    push TILE_SIZE
    push COLOR_PIPE_DARK
    call FillRect
    mov ax, bx
    add ax, 2
    push ax
    push cx
    push 12
    push TILE_SIZE
    push COLOR_PIPE_LIGHT
    call FillRect
    jmp drawtile_exit

drawtile_stair:
    ; Outer black border
    push bx
    push cx
    push TILE_SIZE
    push TILE_SIZE
    push COLOR_BLACK
    call FillRect
    ; Inner tan stair block (14x14)
    mov ax, bx
    inc ax
    push ax
    mov ax, cx
    inc ax
    push ax
    push 14
    push 14
    push COLOR_STAIR
    call FillRect
    jmp drawtile_exit

drawtile_coin:
    ; Centered 8x12 gold coin oval
    mov ax, bx
    add ax, 4
    push ax
    mov ax, cx
    add ax, 2
    push ax
    push 8
    push 12
    push COLOR_COIN
    call FillRect
    jmp drawtile_exit

drawtile_flagpole:
    ; Centered 4x16 green vertical pole
    mov ax, bx
    add ax, 6
    push ax
    push cx
    push 4
    push TILE_SIZE
    push COLOR_FLAG
    call FillRect

drawtile_exit:
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6

; Procedure: DrawMap
; Purpose:   Draws a visible 20-column by 12-row window of level_map_work
;            starting at tile column start_col (0..40). Row 0 is skipped (HUD).
; Inputs:    Stack parameters:
;              [bp+4] = start_col (first visible tile column, 0..40)
; Outputs:   Renders visible map tiles to screen
; Registers: Preserves ALL (cleans 2 bytes from stack)
DrawMap:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Draw black HUD bar across row 0 (y = 0..15)
    push 0
    push 0
    push SCREEN_WIDTH
    push HUD_HEIGHT
    push COLOR_BLACK
    call FillRect

    ; Clamp start_col so start_col + 20 <= 60
    mov di, [bp+4]                  ; DI = start_col
    cmp di, LEVEL_WIDTH_TILES - GRID_COLS
    jbe drawmap_start_ok
    mov di, LEVEL_WIDTH_TILES - GRID_COLS

drawmap_start_ok:
    mov dx, 1                       ; DX = current row (1..11; row 0 is HUD)

drawmap_row_loop:
    ; Calculate row base offset: row * 60 = (row << 6) - (row << 2)
    mov si, dx
    shl si, 6                       ; SI = row * 64
    mov ax, dx
    shl ax, 2                       ; AX = row * 4
    sub si, ax                      ; SI = row * 60
    add si, di                      ; SI = row * 60 + start_col

    xor cx, cx                      ; CX = visible screen column (0..19)

drawmap_col_loop:
    ; Calculate screen_x = visible_col * 16
    mov ax, cx
    shl ax, 4
    push ax                         ; Param 1: screen_x

    ; Calculate screen_y = row * 16
    mov ax, dx
    shl ax, 4
    push ax                         ; Param 2: screen_y

    ; Fetch tile code from working map
    xor ah, ah
    mov al, [level_map_work + si]
    push ax                         ; Param 3: tile_code
    call DrawTile

    inc si                          ; Next map column
    inc cx                          ; Next screen column
    cmp cx, GRID_COLS               ; Drawn all 20 visible columns?
    jb drawmap_col_loop

    inc dx                          ; Next row
    cmp dx, GRID_ROWS               ; Drawn rows 1..11?
    jb drawmap_row_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 2
; GAME DATA & VARIABLES
; ==============================================================================
; MODULE 4 (PART B): SPRITE RENDERING ENGINE
; Author: Amna (Phase 2 - Step 2)
; ==============================================================================

; Procedure: DrawSprite
; Purpose:   Renders a 16x16 or 16x32 sprite at signed screen coordinates (x, y)
;            with 00h transparency, horizontal mirroring, invulnerability blink,
;            and strict VGA 0A000h boundary clipping.
; Inputs:    Stack parameters:
;              [bp+10] = x (signed screen X coordinate)
;              [bp+8]  = y (signed screen Y coordinate)
;              [bp+6]  = address (offset of sprite bitmap in CS/DS)
;              [bp+4]  = flags (bit 0: flip_h, bit 1: tall 16x32, bit 2: blink)
; Outputs:   Writes non-transparent sprite pixels to VGA segment 0A000h
; Registers: Preserves ALL (cleans 8 bytes from stack)
DrawSprite:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es

    ; Ensure DS = CS (.COM single segment) and ES = VGA_SEGMENT (0A000h)
    mov ax, cs
    mov ds, ax
    mov es, [render_target_seg]

    mov dx, [bp+4]                  ; DX = flags

    ; 1. Blink Effect: If SPR_FLAG_BLINK is set, skip drawing on odd timer ticks
    test dx, SPR_FLAG_BLINK
    jz drawsprite_check_height
    test byte [mario_invuln_timer], 01h
    jnz drawsprite_early_exit         ; Alternate-frame skip for 2s invulnerability

drawsprite_check_height:
    ; 2. Determine sprite height (16 or 32 rows)
    mov cx, SPRITE_H_SMALL          ; Default height = 16
    test dx, SPR_FLAG_TALL
    jz drawsprite_check_bounds
    mov cx, SPRITE_H_SUPER          ; Tall sprite height = 32

drawsprite_check_bounds:
    ; 3. Quick trivial-rejection bounds check (completely off-screen)
    mov ax, [bp+10]                 ; AX = start_x (signed)
    cmp ax, SCREEN_WIDTH
    jge drawsprite_early_exit            ; Completely off right edge (x >= 320)
    cmp ax, -SPRITE_W
    jle drawsprite_early_exit          ; Completely off left edge (x <= -16)

    mov bx, [bp+8]                  ; BX = start_y (signed)
    cmp bx, SCREEN_HEIGHT
    jge drawsprite_early_exit           ; Completely off bottom edge (y >= 200)
    mov di, cx
    neg di                          ; DI = -height (-16 or -32)
    cmp bx, di
    jle drawsprite_early_exit            ; Completely off top edge (y <= -height)

    ; Initialize row loop counters
    mov si, [bp+6]                  ; SI = pointer to current row in sprite bitmap
    ; BX = current screen_y (starts at [bp+8])
    ; CX = remaining rows to process (16 or 32)
    jmp drawsprite_row_loop         ; Jump over trampoline into loop
drawsprite_early_exit:
    jmp drawsprite_exit

drawsprite_row_loop:
    ; Vertical edge clipping for current row
    cmp bx, 0
    jl drawsprite_next_row          ; Row is above top of screen (y < 0), skip
    cmp bx, SCREEN_HEIGHT
    jge drawsprite_early_exit    ; Reached bottom of screen (y >= 200), done

    ; Compute VGA row base offset: DI = (y * 320) = (y << 8) + (y << 6)
    mov di, bx
    shl di, 8                       ; DI = y * 256
    mov ax, bx
    shl ax, 6                       ; AX = y * 64
    add di, ax                      ; DI = y * 320

    push cx                         ; Save outer row counter
    push bx                         ; Save current screen_y

    mov bx, [bp+10]                 ; BX = current screen_x (starts at start_x)
    xor cx, cx                      ; CX = column index (0..15)

drawsprite_col_loop:
    ; Horizontal edge clipping for current pixel
    cmp bx, 0
    jl drawsprite_next_col          ; Pixel is left of screen (x < 0), skip
    cmp bx, SCREEN_WIDTH
    jge drawsprite_row_done         ; Past right edge (x >= 320), finish row early

    ; Fetch pixel color (normal vs horizontally flipped)
    push bx                         ; Temporarily free BX for source indexing
    mov bx, cx                      ; BX = col (0..15)
    test word [bp+4], SPR_FLAG_FLIP_H
    jz drawsprite_read_pixel
    mov bx, 15
    sub bx, cx                      ; Mirror index: 15 - col

drawsprite_read_pixel:
    mov al, [si + bx]               ; AL = sprite pixel color
    pop bx                          ; Restore screen_x

    ; Skip transparent pixels (color 00h)
    cmp al, COLOR_TRANSPARENT
    je drawsprite_next_col

    ; Write pixel to VGA memory at ES:[DI + screen_x]
    push di
    add di, bx                      ; DI = y * 320 + screen_x
    mov [es:di], al
    pop di

drawsprite_next_col:
    inc bx                          ; screen_x++
    inc cx                          ; col++
    cmp cx, SPRITE_W
    jb drawsprite_col_loop

drawsprite_row_done:
    pop bx                          ; Restore current screen_y
    pop cx                          ; Restore outer row counter

drawsprite_next_row:
    add si, SPRITE_W                ; Advance bitmap pointer by 16 bytes (next row)
    inc bx                          ; screen_y++
    dec cx                          ; rows_remaining--
    jnz drawsprite_row_loop

drawsprite_exit:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 8

; ==============================================================================
; MODULE 5 & MODULE 6: FRAME BUFFER & SCROLLING CAMERA
; Author: Rayyan (Phase 2 - Step 3)
; ==============================================================================

; Frame Buffer & Sprite Constants
FRAME_BUFFER_BYTES  equ 64000       ; 320 * 200 bytes for full Mode 13h screen
FRAME_BUFFER_WORDS  equ 32000       ; 64,000 / 2 words for REP STOSW / REP MOVSW
FRAME_BUFFER_PARAS  equ 4000        ; 64,000 / 16 paragraphs for DOS INT 21h alloc
VISIBLE_DRAW_COLS   equ 21          ; 20 visible columns + 1 partial edge column


; Procedure: InitFrameBuffer
; Purpose:   Allocates a secondary 64,000-byte (4,000-paragraph) memory segment
;            above the .COM program for flicker-free off-screen rendering.
;            Falls back to CS + 1000h if DOS MCB covers all conventional memory.
; Inputs:    None
; Outputs:   Sets [frame_buffer_seg] and [render_target_seg]
; Registers: Preserves ALL
InitFrameBuffer:
    push ax
    push bx

    ; Shrink .COM memory block to 64 KB (1000h paragraphs) so DOS can allocate above it
    mov ax, cs
    mov es, ax
    mov ah, 4Ah                     ; DOS Modify Memory Block
    mov bx, 1000h                   ; Keep 64 KB for .COM code, data, and stack
    int 21h

    ; Request 4,000 paragraphs (64,000 bytes) from DOS
    mov ah, 48h                     ; DOS Allocate Memory Block
    mov bx, FRAME_BUFFER_PARAS
    int 21h
    jnc initfb_store_seg            ; Carry clear = AX holds allocated segment

    ; Fallback: Use next 64 KB segment immediately above .COM segment (CS + 1000h)
    mov ax, cs
    add ax, 1000h

initfb_store_seg:
    mov [frame_buffer_seg], ax
    mov [render_target_seg], ax     ; Direct all drawing primitives to off-screen buffer

    pop bx
    pop ax
    ret

; Procedure: ClearFrameBuffer
; Purpose:   Fills the entire 64,000-byte off-screen frame buffer with a single
;            background color using fast word string operations (REP STOSW).
; Inputs:    Stack parameters:
;              [bp+4] = fill color (0..255)
; Outputs:   Writes 32,000 words (64,000 bytes) to [frame_buffer_seg]
; Registers: Preserves ALL (cleans 2 bytes from stack)
ClearFrameBuffer:
    push bp
    mov bp, sp
    push ax
    push cx
    push di
    push es

    mov es, [frame_buffer_seg]      ; Target off-screen frame buffer segment
    xor di, di                      ; Start at offset 0000h
    cld                             ; Forward direction

    mov al, [bp+4]                  ; AL = background color byte
    mov ah, al                      ; AX = two identical color bytes for word fill
    mov cx, FRAME_BUFFER_WORDS      ; 32,000 words = 64,000 bytes
    rep stosw                       ; Clear entire off-screen buffer in one block fill

    pop es
    pop di
    pop cx
    pop ax
    pop bp
    ret 2

; Procedure: FlipFrameBuffer
; Purpose:   Copies the completed 64,000-byte off-screen frame buffer into VGA
;            video memory (0A000h) in one fast block transfer (REP MOVSW).
; Inputs:    None
; Outputs:   Updates VGA screen (0A000h:0000h..F9FFh) without flicker
; Registers: Preserves ALL
FlipFrameBuffer:
    push ax
    push cx
    push si
    push di
    push ds
    push es

    mov ax, VGA_SEGMENT
    mov es, ax                      ; Destination: VGA Mode 13h video memory (0A000h)
    mov ds, [cs:frame_buffer_seg]   ; Source: off-screen frame buffer segment

    xor si, si                      ; Source offset = 0
    xor di, di                      ; Destination offset = 0
    cld                             ; Forward direction
    mov cx, FRAME_BUFFER_WORDS      ; 32,000 words = 64,000 bytes
    rep movsw                       ; Blit entire buffer to VGA memory

    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; Procedure: UpdateCamera
; Purpose:   Updates camera_x according to Section 5.3 scrolling rules:
;            - Follows Mario right once screen_x > 160
;            - Never scrolls left (camera_x only increases)
;            - Clamps camera_x at MAX_CAMERA_X (640 for 60-tile level)
;            - Enforces invisible left wall at world_x >= camera_x and right level edge
; Inputs:    Reads/updates [mario_world_x], [mario_vx], and [camera_x]
; Outputs:   Updated [camera_x] and clamped [mario_world_x]
; Registers: Preserves ALL
UpdateCamera:
    push ax
    push bx

    ; Extract whole-pixel world X from 8.8 fixed-point mario_world_x (high byte)
    mov ax, [mario_world_x]
    mov al, ah
    xor ah, ah                      ; AX = mario_world_px (0..959)
    mov bx, [camera_x]              ; BX = current camera_x (0..640)

    ; 1. Compute screen_x = mario_world_px - camera_x
    sub ax, bx                      ; AX = screen_x (signed)

    ; 2. If screen_x > 160 (CAMERA_MID_X), compute new_camera = mario_world_px - 160
    cmp ax, CAMERA_MID_X
    jle updatecam_check_walls

    mov ax, [mario_world_x]
    mov al, ah
    xor ah, ah                      ; AX = mario_world_px
    sub ax, CAMERA_MID_X            ; AX = candidate new_camera

    ; 3. Clamp new_camera <= MAX_CAMERA_X (640)
    cmp ax, MAX_CAMERA_X
    jbe updatecam_check_monotonic
    mov ax, MAX_CAMERA_X

updatecam_check_monotonic:
    ; 4. Never decrease camera_x: camera_x = max(camera_x, new_camera)
    cmp ax, bx
    jbe updatecam_check_walls
    mov [camera_x], ax
    mov bx, ax                      ; BX = updated camera_x

updatecam_check_walls:
    ; 5. Left edge invisible wall: if mario_world_px < camera_x, clamp to camera_x
    mov ax, [mario_world_x]
    mov al, ah
    xor ah, ah                      ; AX = mario_world_px
    cmp ax, bx
    jge updatecam_check_right_end

    mov ah, bl                      ; Set whole-pixel part = camera_x
    xor al, al                      ; Clear fractional byte
    mov [mario_world_x], ax
    mov word [mario_vx], 0          ; Stop horizontal velocity against left edge
    jmp updatecam_done

updatecam_check_right_end:
    ; 6. Right end of level: prevent Mario from walking past LEVEL_WIDTH_PX - 16 (944)
    cmp ax, LEVEL_WIDTH_PX - TILE_SIZE
    jbe updatecam_done

    mov ax, ((LEVEL_WIDTH_PX - TILE_SIZE) << 8) & 0FFFFh
    mov [mario_world_x], ax
    mov word [mario_vx], 0

updatecam_done:
    pop bx
    pop ax
    ret

; Procedure: WorldToScreenX
; Purpose:   Translates a whole-pixel world X coordinate to a signed screen X
;            coordinate (screen_x = world_x - camera_x) and checks visibility.
; Inputs:    Stack parameters:
;              [bp+4] = world_x (whole pixels)
; Outputs:   AX = signed screen_x; CF = 0 if visible (-16 < screen_x < 320), CF = 1 if culled
; Registers: Modifies AX and FLAGS; preserves all other registers (cleans 2 bytes)
WorldToScreenX:
    push bp
    mov bp, sp

    mov ax, [bp+4]                  ; AX = world_x
    sub ax, [camera_x]              ; AX = screen_x = world_x - camera_x

    ; Check visibility range: -16 < screen_x < 320
    cmp ax, -TILE_SIZE
    jle worldtoscreen_hidden
    cmp ax, SCREEN_WIDTH
    jge worldtoscreen_hidden

    clc                             ; Visible on screen
    jmp worldtoscreen_exit

worldtoscreen_hidden:
    stc                             ; Off-screen (culled)

worldtoscreen_exit:
    pop bp
    ret 2

; Procedure: DrawScrolledMap
; Purpose:   Renders the 20 visible tile columns plus 1 partial edge column with
;            pixel-level horizontal scrolling:
;              first_col = camera_x >> 4
;              pixel_offset = camera_x & 0Fh
;            Clips left and right edge columns cleanly so tiles never wrap.
; Inputs:    Reads [camera_x] and [level_map_work]
; Outputs:   Draws visible scrolled tiles into [render_target_seg]
; Registers: Preserves ALL
DrawScrolledMap:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, [camera_x]              ; AX = camera_x (0..640)
    mov di, ax
    shr di, 4                       ; DI = first_col = camera_x / 16
    and ax, 000Fh                   ; AX = fine_scroll_x = camera_x mod 16 (0..15)
    mov [scroll_fine_x], ax         ; Save fine pixel offset

    mov dx, 1                       ; DX = map row (1..11; row 0 is HUD)

scrolledmap_row_loop:
    ; Compute row base offset: row * 60 = (row << 6) - (row << 2)
    mov si, dx
    shl si, 6                       ; SI = row * 64
    mov ax, dx
    shl ax, 2                       ; AX = row * 4
    sub si, ax                      ; SI = row * 60
    add si, di                      ; SI = row * 60 + first_col

    xor cx, cx                      ; CX = screen column counter (0..20)
    mov bx, [scroll_fine_x]
    neg bx                          ; BX = screen_x = -(camera_x mod 16) (-15..0)

scrolledmap_col_loop:
    ; Stop if map column reaches or exceeds LEVEL_WIDTH_TILES (60)
    mov ax, di
    add ax, cx
    cmp ax, LEVEL_WIDTH_TILES
    jae scrolledmap_next_row

    ; Stop if screen_x >= SCREEN_WIDTH (320)
    cmp bx, SCREEN_WIDTH
    jge scrolledmap_next_row

    ; Fetch tile code from working map
    xor ah, ah
    mov al, [level_map_work + si]

    ; Skip drawing sky tiles since ClearFrameBuffer already filled sky blue
    cmp al, TILE_SKY
    je scrolledmap_advance_col

    ; If tile is partially off left edge (screen_x < 0) or right edge (screen_x > 304),
    ; draw clipped columns safely; otherwise draw full 16x16 tile via DrawTile
    cmp bx, 0
    jl scrolledmap_clipped_tile
    cmp bx, SCREEN_WIDTH - TILE_SIZE
    jg scrolledmap_clipped_tile

    ; Full on-screen tile (0 <= screen_x <= 304)
    push bx                         ; screen_x
    mov ax, dx
    shl ax, 4
    push ax                         ; screen_y = row * 16
    xor ah, ah
    mov al, [level_map_work + si]
    push ax                         ; tile_code
    call DrawTile
    jmp scrolledmap_advance_col

scrolledmap_clipped_tile:
    ; Clipped edge tile: draw only visible horizontal slice [clip_x, clip_w]
    push bx                         ; screen_x (may be -15..-1 or 305..319)
    mov ax, dx
    shl ax, 4
    push ax                         ; screen_y = row * 16
    xor ah, ah
    mov al, [level_map_work + si]
    push ax                         ; tile_code
    call DrawClippedEdgeTile

scrolledmap_advance_col:
    inc si                          ; Next map column
    inc cx                          ; Next screen column index
    add bx, TILE_SIZE               ; screen_x += 16
    cmp cx, VISIBLE_DRAW_COLS       ; Process up to 21 columns (20 + 1 partial)
    jb scrolledmap_col_loop

scrolledmap_next_row:
    inc dx                          ; Next row
    cmp dx, GRID_ROWS               ; Rows 1..11
    jb scrolledmap_row_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Procedure: DrawClippedEdgeTile
; Purpose:   Safely renders a tile that straddles the left (x < 0) or right
;            (x + 16 > 320) screen boundary without writing out of bounds.
; Inputs:    Stack parameters:
;              [bp+8] = screen_x (signed)
;              [bp+6] = screen_y (0..176)
;              [bp+4] = tile_code
; Outputs:   Draws visible clipped slice of tile into [render_target_seg]
; Registers: Preserves ALL (cleans 6 bytes from stack)
DrawClippedEdgeTile:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx

    mov bx, [bp+8]                  ; BX = screen_x (signed)
    mov cx, TILE_SIZE               ; CX = visible width (starts at 16)

    ; Clip left edge if screen_x < 0
    cmp bx, 0
    jge clipedge_check_right
    add cx, bx                      ; visible_width = 16 + screen_x (since bx < 0)
    xor bx, bx                      ; clamped screen_x = 0

clipedge_check_right:
    ; Clip right edge if bx + cx > SCREEN_WIDTH (320)
    mov ax, bx
    add ax, cx
    cmp ax, SCREEN_WIDTH
    jle clipedge_select_color
    mov cx, SCREEN_WIDTH
    sub cx, bx                      ; visible_width = 320 - bx

clipedge_select_color:
    cmp cx, 0
    jle clipedge_exit               ; Nothing visible

    ; Pick representative tile color for clean edge slice
    mov ax, [bp+4]                  ; AL = tile_code
    mov dl, COLOR_BRICK
    cmp al, TILE_GROUND
    jne clipedge_not_ground
    mov dl, COLOR_GROUND_DIRT
    jmp clipedge_draw
clipedge_not_ground:
    cmp al, TILE_QBLOCK_COIN
    je clipedge_qblock
    cmp al, TILE_QBLOCK_MUSH
    jne clipedge_not_qblock
clipedge_qblock:
    mov dl, COLOR_QBLOCK
    jmp clipedge_draw
clipedge_not_qblock:
    cmp al, TILE_EMPTY_BLOCK
    jne clipedge_not_empty
    mov dl, COLOR_EMPTY_BLOCK
    jmp clipedge_draw
clipedge_not_empty:
    cmp al, TILE_PIPE_TL
    je clipedge_pipe
    cmp al, TILE_PIPE_TR
    je clipedge_pipe
    cmp al, TILE_PIPE_BL
    je clipedge_pipe
    cmp al, TILE_PIPE_BR
    jne clipedge_not_pipe
clipedge_pipe:
    mov dl, COLOR_PIPE_LIGHT
    jmp clipedge_draw
clipedge_not_pipe:
    cmp al, TILE_STAIR
    jne clipedge_not_stair
    mov dl, COLOR_STAIR
    jmp clipedge_draw
clipedge_not_stair:
    cmp al, TILE_COIN
    jne clipedge_not_coin
    mov dl, COLOR_COIN
    jmp clipedge_draw
clipedge_not_coin:
    cmp al, TILE_FLAGPOLE
    jne clipedge_draw
    mov dl, COLOR_FLAG

clipedge_draw:
    push bx                         ; clamped x
    push word [bp+6]                ; y
    push cx                         ; clipped width
    push TILE_SIZE                  ; height = 16
    xor dh, dh
    push dx                         ; color
    call FillRect

clipedge_exit:
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    ret 6
; Placed at the end of the program to prevent execution as instructions.


; ==============================================================================
; MODULE 5: CUSTOM KEYBOARD INTERRUPT HANDLER (INT 09h)
; Author: Amna (Phase 3 - Step 1)
; Course Alignment: Week 14 (Hooking an Interrupt, Hardware Interrupts, I/O Ports)
; ==============================================================================

; Hardware I/O Ports & PIC Constants
KBD_DATA_PORT       equ 60h         ; 8042 Keyboard Controller Scan Code Port
PIC_CMD_PORT        equ 20h         ; 8259A Master PIC Command Port
PIC_EOI             equ 20h         ; Non-Specific End-Of-Interrupt (EOI) command
SCAN_EXTENDED_E0    equ 0E0h        ; Extended scan code prefix (Arrow keys, etc.)
SCAN_RELEASE_MASK   equ 80h         ; Bit 7 = 1 indicates key release (Break code)
SCAN_CODE_MASK      equ 7Fh         ; Lower 7 bits = base scan code (0..127)

; Procedure: HookKeyboardISR
; Purpose:   Saves the original BIOS INT 09h interrupt vector using DOS service
;            INT 21h / AH=35h and installs our custom KeyboardISR via AH=25h.
; Inputs:    None
; Outputs:   old_int09_offset and old_int09_segment populated; IVT updated
; Registers: Preserves ALL
HookKeyboardISR:
    push ax
    push bx
    push dx
    push ds
    push es

    mov ax, cs
    mov ds, ax                      ; Ensure DS = CS (.COM single segment)

    ; 1. Get existing INT 09h vector (ES:BX = current handler address)
    mov ah, 35h                     ; DOS Get Interrupt Vector
    mov al, 09h                     ; IRQ1 Keyboard Hardware Interrupt
    int 21h
    mov [old_int09_offset], bx
    mov [old_int09_segment], es

    ; 2. Install custom INT 09h vector (DS:DX = KeyboardISR)
    cli                             ; Disable interrupts while modifying IVT
    mov dx, KeyboardISR
    mov ah, 25h                     ; DOS Set Interrupt Vector
    mov al, 09h
    int 21h
    sti                             ; Re-enable hardware interrupts

    pop es
    pop ds
    pop dx
    pop bx
    pop ax
    ret

; Procedure: UnhookKeyboardISR
; Purpose:   Restores the original BIOS INT 09h interrupt vector before program exit.
; Inputs:    None
; Outputs:   Original INT 09h vector restored in IVT
; Registers: Preserves ALL
UnhookKeyboardISR:
    push ax
    push dx
    push ds

    ; Guard check: only restore if vector was actually hooked
    cmp word [old_int09_segment], 0
    je .unhook_done

    cli                             ; Disable interrupts during IVT restoration
    mov dx, [cs:old_int09_offset]
    mov ds, [cs:old_int09_segment]
    mov ah, 25h                     ; DOS Set Interrupt Vector
    mov al, 09h
    int 21h
    sti

.unhook_done:
    pop ds
    pop dx
    pop ax
    ret

; Interrupt Service Routine: KeyboardISR
; Purpose:   Hardware IRQ1 handler for INT 09h. Reads raw make/break scan codes
;            from Port 60h, filters E0h extended prefixes, updates the 128-byte
;            key_states array for multi-key rollover, acknowledges PIC (EOI),
;            and returns via IRET.
; Inputs:    Hardware interrupt from keyboard controller (Port 60h)
; Outputs:   Updates [cs:key_states + scan_code] (1 = pressed, 0 = released)
; Registers: Preserves ALL (critical for asynchronous hardware interrupts)
KeyboardISR:
    push ax
    push bx
    push ds

    ; Hardware interrupts can fire when DS points to video memory (0A000h) or DOS
    mov ax, cs
    mov ds, ax                      ; Point DS to our .COM code/data segment

    ; 1. Read raw scan code directly from keyboard I/O port 60h
    in al, KBD_DATA_PORT

    ; 2. Filter extended prefix byte (E0h sent before Left/Right/Up/Down arrows)
    cmp al, SCAN_EXTENDED_E0
    je .send_eoi                    ; Ignore E0h prefix; next IRQ carries actual code

    ; 3. Separate make/break flag (bit 7) from 7-bit scan code index
    mov bl, al
    and bl, SCAN_CODE_MASK          ; BL = base scan code (0..127)
    xor bh, bh                      ; BX = 16-bit index into key_states

    test al, SCAN_RELEASE_MASK      ; Check Bit 7 (1 = Break/Release, 0 = Make/Press)
    jnz .key_released

.key_pressed:
    mov byte [key_states + bx], 1   ; Mark key as currently held down
    jmp .send_eoi

.key_released:
    mov byte [key_states + bx], 0   ; Mark key as released

.send_eoi:
    ; 4. Send End-Of-Interrupt (EOI) signal to 8259A PIC (Port 20h)
    mov al, PIC_EOI
    out PIC_CMD_PORT, al

    pop ds
    pop bx
    pop ax
    iret                            ; Interrupt return (restores IP, CS, and FLAGS)

;Hero (Mario) Data Structure
mario_world_x  dw  0020h       ; World X position (8.8 fixed-point, 32px start)
mario_world_y  dw  0090h       ; World Y position (8.8 fixed-point, standing on row 9)
mario_vx       dw  0000h       ; Horizontal velocity (8.8 fixed-point)
mario_vy       dw  0000h       ; Vertical velocity (8.8 fixed-point)
mario_hp       db  HP_SMALL    ; Current health points (1 = Small, 2 = Super)
mario_form     db  0           ; 0 = Small Mario, 1 = Super Mario
mario_on_ground  db  0           ; 1 = Standing on solid floor, 0 = Airborne
mario_invuln_timer db  0           ; Invulnerability tick counter
mario_stomp_chain  db  0           ; Consecutive enemy stomp counter

;Game & Environment State 
game_state  db  0           ; 0=Title, 1=Playing, 2=Paused, etc.
lives       db  START_LIVES ; Remaining lives
coins       db  0           ; Accumulated coins (0-99)
level_time  dw  START_TIME  ; Time remaining in seconds
score_low   dw  0000h       ; Lower 16 bits of 32-bit score
score_high  dw  0000h       ; Upper 16 bits of 32-bit score
camera_x    dw  0000h       ; Camera horizontal pixel offset (0-640)
;Module 5 & 6: Frame Buffer & Camera Variables
frame_buffer_seg    dw  0A000h      ; Allocated off-screen 64,000-byte segment
render_target_seg   dw  0A000h      ; Active draw target (off-screen buffer)
scroll_fine_x       dw  0000h       ; Fine horizontal scroll offset (camera_x mod 16)

;Keyboard Input Table 
key_states          times 128 db 0  ;128-byte lookup array (1=pressed,0=released)
old_int09_offset    dw  0000h
old_int09_segment   dw  0000h
;Module 2 Palette Verification Data
palette_test_table:
    db COLOR_SKY,        COLOR_GROUND_TOP, COLOR_GROUND_DIRT, COLOR_BRICK
    db COLOR_QBLOCK,     COLOR_EMPTY_BLOCK,COLOR_PIPE_LIGHT,  COLOR_COIN
    db COLOR_MARIO_RED,  COLOR_MARIO_BLUE, COLOR_MARIO_SKIN,  COLOR_GOOMBA
    db COLOR_KOOPA,      COLOR_STAIR,      COLOR_FLAG,        COLOR_HUD_TEXT

; ==============================================================================
; MODULE 3: LEVEL MAP DATA (60 Columns x 12 Rows = 720 Bytes)
; Tile Codes: 0=Sky, 1=Ground, 2=Brick, 3=?Coin, 4=?Mushroom, 5=Empty,
;             6=PipeTL, 7=PipeTR, 8=PipeBL, 9=PipeBR, 10=Stair, 11=Coin, 12=Flag
; ==============================================================================
level_map_orig:
    ; Row 0: Reserved for HUD (16px top strip)
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0
    ; Row 1: Upper sky
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0
    ; Row 2: Flagpole top (col 56, row 2)
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,12,0,0,0
    ; Row 3: High ?-block (col 15) + Flagpole
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,3,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,12,0,0,0
    ; Row 4: Flagpole
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,12,0,0,0
    ; Row 5: Free coins above pits (cols 21-24 & 39-41) + Flagpole
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,11,11,11,11,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,11, 11,11,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,12,0,0,0
    ; Row 6: Early Mushroom ?-block (col 8), Brick/Coin Group 1 (cols 13-17), Group 2 (cols 30-32, 44-46), Top Stair (col 52) + Flagpole
    db 0,0,0,0,0,0,0,0,4,0, 0,0,0,2,3,2,3,2,0,0, 0,0,0,0,0,0,0,0,0,0, 2,4,2,0,0,0,0,0,0,0, 0,0,0,0,2,2,2,0,0,0, 0,0,10,0,0,0,12,0,0,0
    ; Row 7: 3-tile Pipe Top (cols 35-36), Stair step 3 (cols 51-52) + Flagpole
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,6,7,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,10,10,0,0,0,12,0,0,0
    ; Row 8: 2-tile Pipe Top (cols 27-28), Pipe 2 Body (cols 35-36), Free coins (cols 30-32), Stair step 2 (cols 50-52) + Flagpole bottom (row 8)
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,6,7,0, 11,11,11,0,0,8,9,0,0,0, 0,0,0,0,0,0,0,0,0,0, 10,10,10,0,0,0,12,0,0,0
    ; Row 9: Ground surface level — Pipe 1 Body (cols 27-28), Pipe 2 Body (cols 35-36), Free coins (cols 45-46), Stair step 1 (cols 49-52), Flag base block (col 56)
    db 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,8,9,0, 0,0,0,0,0,8,9,0,0,0, 0,0,0,0,0,11,11,0,0,10, 10,10,10,0,0,0,10,0,0,0
    ; Row 10: Ground top layer (Pit 1 at cols 22-23, Pit 2 at cols 39-41)
    db 1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1, 1,1,0,0,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,0, 0,0,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1
    ; Row 11: Ground bottom layer (Pit 1 at cols 22-23, Pit 2 at cols 39-41)
    db 1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1, 1,1,0,0,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,0, 0,0,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1

; Working copy of the level map (modified during gameplay, restored by ResetMap)
level_map_work:
    times LEVEL_MAP_BYTES db 0

; ==============================================================================
; MODULE 4 (PART A): SPRITE BITMAPS & ASSET CREATION
; Author: Talia (Phase 2 - Step 1)
; ==============================================================================

SPRITE_W            equ 16          ; Standard sprite width in pixels
SPRITE_H_SMALL      equ 16          ; Small Mario, Enemies, & Items height
SPRITE_H_SUPER      equ 32          ; Super Mario height
; Sprite Rendering Flags (Bitmask for DrawSprite 'flags' parameter)
SPR_FLAG_FLIP_H     equ 01h         ; Bit 0: 1 = Flip horizontally (face left), 0 = Normal (face right)
SPR_FLAG_TALL       equ 02h         ; Bit 1: 1 = 16x32 Super Mario, 0 = 16x16 standard sprite
SPR_FLAG_BLINK      equ 04h         ; Bit 2: 1 = Invulnerability blink active (skips drawing if odd frame)
; ------------------------------------------------------------------------------
; 1. SMALL MARIO - STANDING (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_mario_small_stand:
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,00h,00h,00h,00h,00h,00h,00h ; Row 0: Hat top
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h ; Row 1: Hat brim
    db 00h,00h,00h,06h,06h,06h,59h,59h,06h,59h,00h,00h,00h,00h,00h,00h ; Row 2: Hair & eyes
    db 00h,00h,06h,59h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h,00h ; Row 3: Face & nose
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h ; Row 4: Face
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,00h,00h,00h,00h ; Row 5: Mustache
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h ; Row 6: Chin
    db 00h,00h,00h,28h,28h,20h,28h,28h,28h,20h,00h,00h,00h,00h,00h,00h ; Row 7: Shirt/straps
    db 00h,00h,28h,28h,28h,20h,28h,28h,20h,28h,28h,28h,00h,00h,00h,00h ; Row 8: Arms/chest
    db 00h,28h,28h,28h,28h,20h,20h,20h,20h,28h,28h,28h,28h,00h,00h,00h ; Row 9: Overalls top
    db 00h,59h,59h,28h,20h,2Ch,20h,20h,2Ch,20h,28h,59h,59h,00h,00h,00h ; Row 10: Hands & buttons
    db 00h,59h,59h,59h,20h,20h,20h,20h,20h,20h,59h,59h,59h,00h,00h,00h ; Row 11: Overalls waist
    db 00h,59h,59h,00h,20h,20h,20h,20h,20h,20h,00h,59h,59h,00h,00h,00h ; Row 12: Overalls hips
    db 00h,00h,00h,20h,20h,20h,00h,00h,20h,20h,20h,00h,00h,00h,00h,00h ; Row 13: Legs
    db 00h,00h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,00h,00h,00h,00h ; Row 14: Boots top
    db 00h,06h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,06h,00h,00h,00h ; Row 15: Boots sole

; ------------------------------------------------------------------------------
; 2. SMALL MARIO - RUNNING (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_mario_small_run:
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h
    db 00h,00h,00h,06h,06h,06h,59h,59h,06h,59h,00h,00h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,00h,00h,00h,00h
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h
    db 00h,00h,28h,28h,28h,20h,28h,28h,20h,28h,00h,00h,00h,00h,00h,00h
    db 00h,28h,28h,28h,28h,20h,20h,28h,20h,28h,28h,59h,59h,00h,00h,00h ; Forward arm swing
    db 59h,59h,28h,28h,20h,20h,2Ch,20h,20h,20h,28h,59h,59h,00h,00h,00h ; Back arm swing
    db 59h,59h,00h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h,00h
    db 00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,06h,00h,00h,00h,00h ; Stride apart
    db 00h,20h,20h,20h,00h,00h,00h,20h,20h,20h,06h,06h,00h,00h,00h,00h
    db 06h,20h,20h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h,00h,00h
    db 06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 3. SMALL MARIO - JUMPING (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_mario_small_jump:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,59h,59h,59h,00h,00h ; Raised fist
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,00h,00h,28h,28h,28h,00h,00h ; Hat + raised arm
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h,00h
    db 00h,00h,00h,06h,06h,06h,59h,59h,06h,59h,00h,28h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,00h,00h,00h,00h
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h
    db 00h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,00h,00h,00h,00h,00h
    db 59h,59h,28h,28h,28h,20h,20h,20h,20h,28h,00h,00h,00h,00h,00h,00h
    db 59h,59h,00h,20h,20h,2Ch,20h,20h,2Ch,20h,20h,00h,00h,00h,00h,00h
    db 00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,06h,00h,00h,00h,00h
    db 00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,06h,06h,00h,00h,00h,00h
    db 06h,20h,20h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h,00h,00h
    db 06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 4. SUPER MARIO - STANDING (16x32 = 512 bytes)
; ------------------------------------------------------------------------------
spr_mario_super_stand:
    db 00h,00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h,00h ; Row 0
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h ; Row 1
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h ; Row 2
    db 00h,00h,00h,06h,06h,06h,59h,59h,59h,06h,59h,00h,00h,00h,00h,00h ; Row 3
    db 00h,00h,06h,59h,06h,59h,59h,59h,59h,06h,59h,59h,00h,00h,00h,00h ; Row 4
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h ; Row 5
    db 00h,00h,06h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h ; Row 6
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h ; Row 7
    db 00h,00h,00h,06h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h,00h ; Row 8
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h ; Row 9
    db 00h,00h,00h,00h,00h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h,00h ; Row 10: Neck
    db 00h,00h,00h,28h,28h,28h,20h,28h,28h,20h,28h,28h,00h,00h,00h,00h ; Row 11: Shoulders
    db 00h,00h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,28h,00h,00h,00h ; Row 12
    db 00h,28h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,28h,28h,00h,00h ; Row 13
    db 00h,28h,28h,28h,28h,28h,20h,20h,20h,20h,28h,28h,28h,28h,00h,00h ; Row 14
    db 00h,28h,28h,28h,28h,20h,20h,20h,20h,20h,20h,28h,28h,28h,00h,00h ; Row 15
    db 00h,59h,59h,28h,28h,20h,2Ch,20h,20h,2Ch,20h,28h,28h,59h,59h,00h ; Row 16: Buttons
    db 00h,59h,59h,59h,28h,20h,20h,20h,20h,20h,20h,28h,59h,59h,59h,00h ; Row 17: Hands
    db 00h,59h,59h,59h,00h,20h,20h,20h,20h,20h,20h,00h,59h,59h,59h,00h ; Row 18
    db 00h,59h,59h,00h,20h,20h,20h,20h,20h,20h,20h,20h,00h,59h,59h,00h ; Row 19: Overalls
    db 00h,00h,00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h ; Row 20
    db 00h,00h,00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h ; Row 21
    db 00h,00h,00h,20h,20h,20h,20h,00h,00h,20h,20h,20h,20h,00h,00h,00h ; Row 22: Thighs
    db 00h,00h,00h,20h,20h,20h,20h,00h,00h,20h,20h,20h,20h,00h,00h,00h ; Row 23
    db 00h,00h,00h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,00h,00h,00h ; Row 24
    db 00h,00h,00h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,00h,00h,00h ; Row 25: Knees
    db 00h,00h,00h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,00h,00h,00h ; Row 26
    db 00h,00h,00h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,00h,00h,00h ; Row 27: Shins
    db 00h,00h,06h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,06h,00h,00h ; Row 28: Boots top
    db 00h,00h,06h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,06h,00h,00h ; Row 29
    db 00h,06h,06h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,06h,06h,00h ; Row 30
    db 00h,06h,06h,06h,06h,06h,00h,00h,00h,00h,06h,06h,06h,06h,06h,00h ; Row 31: Boots sole

; ------------------------------------------------------------------------------
; 5. SUPER MARIO - RUNNING (16x32 = 512 bytes)
; ------------------------------------------------------------------------------
spr_mario_super_run:
    db 00h,00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h
    db 00h,00h,00h,06h,06h,06h,59h,59h,59h,06h,59h,00h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,59h,59h,59h,59h,06h,59h,59h,00h,00h,00h,00h
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h
    db 00h,00h,06h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h
    db 00h,00h,00h,06h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h,00h
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,28h,28h,28h,20h,28h,28h,20h,28h,00h,00h,00h,00h,00h
    db 00h,00h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,00h,00h,00h,00h
    db 00h,28h,28h,28h,28h,28h,20h,20h,28h,20h,28h,28h,59h,59h,00h,00h
    db 00h,28h,28h,28h,28h,20h,20h,20h,20h,20h,28h,59h,59h,59h,00h,00h
    db 59h,59h,28h,28h,20h,20h,2Ch,20h,20h,20h,20h,59h,59h,00h,00h,00h
    db 59h,59h,59h,28h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h,00h
    db 59h,59h,00h,00h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h,00h
    db 00h,00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h
    db 00h,00h,20h,20h,20h,20h,00h,00h,20h,20h,20h,20h,20h,00h,00h,00h
    db 00h,20h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,20h,06h,00h,00h
    db 00h,20h,20h,20h,00h,00h,00h,00h,00h,00h,20h,20h,06h,06h,00h,00h
    db 06h,20h,20h,00h,00h,00h,00h,00h,00h,00h,00h,20h,06h,06h,00h,00h
    db 06h,06h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h
    db 06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h
    db 06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 06h,06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 6. SUPER MARIO - JUMPING (16x32 = 512 bytes)
; ------------------------------------------------------------------------------
spr_mario_super_jump:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,59h,59h,59h,00h ; Raised hand
    db 00h,00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,00h,59h,59h,59h,00h
    db 00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h
    db 00h,00h,00h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,00h,00h
    db 00h,00h,00h,06h,06h,06h,59h,59h,59h,06h,59h,00h,28h,28h,00h,00h
    db 00h,00h,06h,59h,06h,59h,59h,59h,59h,06h,59h,59h,28h,28h,00h,00h
    db 00h,00h,06h,59h,06h,06h,59h,59h,59h,06h,59h,59h,59h,00h,00h,00h
    db 00h,00h,06h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h
    db 00h,00h,06h,06h,59h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h
    db 00h,00h,00h,06h,59h,59h,59h,06h,06h,06h,06h,06h,00h,00h,00h,00h
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h
    db 00h,00h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,00h,00h,00h,00h
    db 00h,28h,28h,28h,28h,28h,20h,28h,28h,20h,28h,28h,00h,00h,00h,00h
    db 59h,59h,28h,28h,28h,20h,20h,20h,20h,20h,28h,00h,00h,00h,00h,00h
    db 59h,59h,59h,28h,20h,20h,2Ch,20h,20h,2Ch,20h,00h,00h,00h,00h,00h
    db 59h,59h,00h,00h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h,00h
    db 00h,00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h,00h
    db 00h,00h,20h,20h,20h,20h,20h,20h,20h,20h,20h,20h,20h,00h,00h,00h
    db 00h,20h,20h,20h,20h,00h,00h,00h,00h,20h,20h,20h,20h,06h,00h,00h
    db 00h,20h,20h,20h,00h,00h,00h,00h,00h,00h,20h,20h,06h,06h,00h,00h
    db 06h,20h,20h,00h,00h,00h,00h,00h,00h,00h,00h,20h,06h,06h,00h,00h
    db 06h,06h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h
    db 06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,06h,00h,00h
    db 06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 06h,06h,06h,06h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 7. GOOMBA - WALKING (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_goomba_walk:
    db 00h,00h,00h,00h,00h,00h,06h,06h,06h,06h,00h,00h,00h,00h,00h,00h ; Row 0
    db 00h,00h,00h,00h,00h,06h,06h,06h,06h,06h,06h,00h,00h,00h,00h,00h ; Row 1
    db 00h,00h,00h,00h,06h,06h,06h,06h,06h,06h,06h,06h,00h,00h,00h,00h ; Row 2
    db 00h,00h,00h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,00h,00h,00h ; Row 3
    db 00h,00h,06h,06h,01h,01h,06h,06h,06h,06h,01h,01h,06h,06h,00h,00h ; Row 4: Eyebrows
    db 00h,06h,06h,06h,0Fh,01h,06h,06h,06h,06h,01h,0Fh,06h,06h,06h,00h ; Row 5: Eyes
    db 00h,06h,06h,06h,0Fh,01h,06h,06h,06h,06h,01h,0Fh,06h,06h,06h,00h ; Row 6: Eyes
    db 06h,06h,06h,06h,0Fh,0Fh,06h,06h,06h,06h,0Fh,0Fh,06h,06h,06h,06h ; Row 7
    db 06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h ; Row 8
    db 00h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,00h ; Row 9
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h ; Row 10: Stem
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h ; Row 11: Stem
    db 00h,00h,01h,01h,01h,59h,59h,59h,59h,59h,59h,01h,01h,01h,00h,00h ; Row 12: Feet
    db 00h,01h,01h,01h,01h,01h,00h,00h,00h,00h,01h,01h,01h,01h,01h,00h ; Row 13: Feet
    db 00h,01h,01h,01h,01h,01h,00h,00h,00h,00h,01h,01h,01h,01h,01h,00h ; Row 14: Feet
    db 00h,00h,01h,01h,01h,00h,00h,00h,00h,00h,00h,01h,01h,01h,00h,00h ; Row 15: Soles

; ------------------------------------------------------------------------------
; 8. GOOMBA - FLATTENED (16x16 = 256 bytes, bottom-aligned)
; ------------------------------------------------------------------------------
spr_goomba_flat:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,00h,00h ; Squashed cap
    db 06h,06h,06h,0Fh,01h,06h,06h,06h,06h,06h,06h,01h,0Fh,06h,06h,06h ; Squashed eyes
    db 06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h
    db 00h,00h,01h,01h,59h,59h,59h,59h,59h,59h,59h,59h,01h,01h,00h,00h
    db 00h,01h,01h,01h,01h,59h,59h,59h,59h,59h,59h,01h,01h,01h,01h,00h
    db 00h,01h,01h,01h,00h,00h,00h,00h,00h,00h,00h,00h,01h,01h,01h,00h

; ------------------------------------------------------------------------------
; 9. KOOPA TROOPA - WALKING (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_koopa_walk:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,2Ch,2Ch,2Ch,00h,00h,00h,00h ; Row 0: Head top
    db 00h,00h,00h,00h,00h,00h,00h,00h,2Ch,2Ch,0Fh,01h,2Ch,00h,00h,00h ; Row 1: Eye
    db 00h,00h,00h,00h,00h,00h,00h,00h,2Ch,2Ch,0Fh,01h,2Ch,2Ch,00h,00h ; Row 2: Beak
    db 00h,00h,00h,00h,00h,00h,00h,00h,2Ch,2Ch,2Ch,2Ch,2Ch,00h,00h,00h ; Row 3: Chin
    db 00h,00h,00h,00h,02h,02h,02h,02h,2Ch,2Ch,00h,00h,00h,00h,00h,00h ; Row 4: Neck + shell
    db 00h,00h,00h,02h,2Fh,2Fh,2Fh,2Fh,02h,2Ch,00h,00h,00h,00h,00h,00h ; Row 5: Shell top
    db 00h,00h,02h,2Fh,2Fh,0Fh,2Fh,2Fh,2Fh,02h,00h,00h,00h,00h,00h,00h ; Row 6: Shell pattern
    db 00h,02h,2Fh,2Fh,2Fh,2Fh,2Fh,0Fh,2Fh,2Fh,02h,00h,00h,00h,00h,00h ; Row 7
    db 00h,02h,2Fh,0Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,02h,2Ch,2Ch,00h,00h,00h ; Row 8: Shell + arm
    db 00h,02h,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,02h,2Ch,2Ch,00h,00h,00h,00h ; Row 9
    db 00h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,00h,00h,00h,00h,00h,00h ; Row 10: White rim
    db 00h,00h,0Fh,0Fh,2Ch,2Ch,2Ch,2Ch,0Fh,0Fh,00h,00h,00h,00h,00h,00h ; Row 11: Belly
    db 00h,00h,00h,2Ch,2Ch,00h,00h,2Ch,2Ch,00h,00h,00h,00h,00h,00h,00h ; Row 12: Legs
    db 00h,00h,00h,2Ch,2Ch,00h,00h,2Ch,2Ch,00h,00h,00h,00h,00h,00h,00h ; Row 13: Legs
    db 00h,00h,2Ch,2Ch,2Ch,2Ch,00h,2Ch,2Ch,2Ch,2Ch,00h,00h,00h,00h,00h ; Row 14: Feet
    db 00h,00h,2Ch,2Ch,2Ch,2Ch,00h,2Ch,2Ch,2Ch,2Ch,00h,00h,00h,00h,00h ; Row 15: Feet

; ------------------------------------------------------------------------------
; 10. KOOPA SHELL (16x16 = 256 bytes, bottom-aligned)
; ------------------------------------------------------------------------------
spr_koopa_shell:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,02h,02h,02h,02h,02h,02h,00h,00h,00h,00h,00h ; Shell dome
    db 00h,00h,00h,02h,02h,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,02h,02h,00h,00h,00h
    db 00h,00h,02h,2Fh,2Fh,0Fh,2Fh,2Fh,2Fh,2Fh,0Fh,2Fh,2Fh,02h,00h,00h
    db 00h,02h,2Fh,2Fh,2Fh,2Fh,2Fh,0Fh,0Fh,2Fh,2Fh,2Fh,2Fh,2Fh,02h,00h
    db 00h,02h,2Fh,0Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,0Fh,2Fh,02h,00h
    db 00h,02h,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,2Fh,02h,00h
    db 00h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,00h ; White rim
    db 00h,00h,0Fh,0Fh,01h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,01h,0Fh,0Fh,00h,00h ; Underside
    db 00h,00h,00h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,00h,00h,00h
    db 00h,00h,00h,00h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 11. SUPER MUSHROOM POWER-UP (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_mushroom:
    db 00h,00h,00h,00h,00h,28h,28h,28h,28h,28h,28h,00h,00h,00h,00h,00h ; Row 0
    db 00h,00h,00h,28h,28h,28h,0Fh,0Fh,0Fh,0Fh,28h,28h,28h,00h,00h,00h ; Row 1: Top spot
    db 00h,00h,28h,28h,28h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,28h,28h,28h,00h,00h ; Row 2
    db 00h,28h,28h,28h,28h,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,28h,28h,28h,28h,00h ; Row 3
    db 00h,28h,0Fh,0Fh,28h,28h,0Fh,0Fh,0Fh,0Fh,28h,28h,0Fh,0Fh,28h,00h ; Row 4: Side spots
    db 28h,0Fh,0Fh,0Fh,0Fh,28h,28h,28h,28h,28h,28h,0Fh,0Fh,0Fh,0Fh,28h ; Row 5
    db 28h,0Fh,0Fh,0Fh,0Fh,28h,28h,28h,28h,28h,28h,0Fh,0Fh,0Fh,0Fh,28h ; Row 6
    db 28h,28h,0Fh,0Fh,28h,28h,28h,28h,28h,28h,28h,28h,0Fh,0Fh,28h,28h ; Row 7
    db 28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h,28h ; Row 8
    db 00h,28h,28h,28h,59h,59h,59h,59h,59h,59h,59h,59h,28h,28h,28h,00h ; Row 9: Cap rim
    db 00h,00h,00h,59h,59h,59h,01h,59h,59h,01h,59h,59h,59h,00h,00h,00h ; Row 10: Stem eyes
    db 00h,00h,00h,59h,59h,59h,01h,59h,59h,01h,59h,59h,59h,00h,00h,00h ; Row 11
    db 00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h ; Row 12
    db 00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h ; Row 13
    db 00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h ; Row 14
    db 00h,00h,00h,00h,00h,59h,59h,59h,59h,59h,59h,00h,00h,00h,00h,00h ; Row 15

; ------------------------------------------------------------------------------
; 12. GOLD COIN SPRITE (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_coin:
    db 00h,00h,00h,00h,00h,00h,01h,01h,01h,01h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,01h,2Ch,2Ch,2Ch,2Ch,01h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,2Ch,2Ch,01h,00h,00h,00h,00h
    db 00h,00h,00h,00h,01h,2Ch,0Fh,2Ch,01h,2Ch,2Ch,01h,00h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,01h,2Ch,0Fh,2Ch,2Ch,01h,2Ch,2Ch,2Ch,01h,00h,00h,00h
    db 00h,00h,00h,00h,01h,2Ch,2Ch,2Ch,01h,2Ch,2Ch,01h,00h,00h,00h,00h
    db 00h,00h,00h,00h,01h,2Ch,2Ch,2Ch,2Ch,2Ch,2Ch,01h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,01h,2Ch,2Ch,2Ch,2Ch,01h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,01h,01h,01h,01h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------------------
; 13. FLAGPOLE TOP & PENNANT FLAG (16x16 = 256 bytes)
; ------------------------------------------------------------------------------
spr_flagpole_flag:
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h ; Finial ball
    db 00h,00h,00h,00h,00h,00h,0Ah,0Ah,0Ah,0Ah,00h,00h,00h,00h,00h,00h ; Finial ball
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h ; Flag top
    db 00h,00h,00h,0Fh,0Fh,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,0Fh,0Fh,0Fh,02h,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h ; Flag emblem
    db 0Fh,0Fh,0Fh,02h,02h,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,0Fh,0Fh,0Fh,02h,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,0Fh,0Fh,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,0Fh,0Fh,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h ; Flag bottom
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h ; Pole shaft
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,0Ah,0Ah,00h,00h,00h,00h,00h,00h,00h