; File:mario.asm
; Author:Talia
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
; Purpose: Initializes system components and variable structures.
; Inputs: None | Outputs: None | Registers Preserved: ALL

SetupProgram:
    call InitVideoMode13h           ; Switch to VGA Mode 13h (320x200)
    ret

;Subroutine: MainLoop
;Purpose:    Initializes working map and renders Module 3 level test screen.
;Inputs:     None | Outputs: None | Registers Preserved: ALL
MainLoop:
    push ax
    call ResetMap                   ; Copy original map into working map

    push 0                          ; start_col = 0 (first 20 columns; change to 20 or 40 to test scrolling windows)
    call DrawMap                    ; Render visible 20x12 tile window

    mov ah, 00h                     ; Wait for any keypress so screen stays visible
    int 16h
    pop ax
    ret

; Subroutine: CleanExit
; Purpose:    Safely restores execution state and returns control to DOS.
; Inputs:     None | Outputs: None | Registers Changed: None (Exits)

CleanExit:
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

    ; Set ES to VGA segment 0A000h
    mov di, VGA_SEGMENT
    mov es, di

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
    mov ax, VGA_SEGMENT
    mov es, ax
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

    ; Dispatch based on tile_code
    cmp al, TILE_SKY
    je drawtile_exit                ; Sky is already drawn

    cmp al, TILE_GROUND
    je drawtile_ground

    cmp al, TILE_BRICK
    je drawtile_brick

    cmp al, TILE_QBLOCK_COIN
    je drawtile_qblock

    cmp al, TILE_QBLOCK_MUSH
    je drawtile_qblock

    cmp al, TILE_EMPTY_BLOCK
    je drawtile_empty

    cmp al, TILE_PIPE_TL
    je drawtile_pipe_top

    cmp al, TILE_PIPE_TR
    je drawtile_pipe_top

    cmp al, TILE_PIPE_BL
    je drawtile_pipe_body

    cmp al, TILE_PIPE_BR
    je drawtile_pipe_body

    cmp al, TILE_STAIR
    je drawtile_stair

    cmp al, TILE_COIN
    je drawtile_coin

    cmp al, TILE_FLAGPOLE
    je drawtile_flagpole

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
; Placed at the end of the program to prevent execution as instructions.


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

;Keyboard Input Table 
key_states          times 128 db 0  ;128-byte lookup array (1=pressed,0=released)
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