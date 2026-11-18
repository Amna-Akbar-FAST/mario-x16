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
;Purpose:    Placeholder for game loop execution.
;Inputs:  None | Outputs: None | Registers Preserved: ALL
MainLoop:
    push ax
    call RenderPaletteScreen        ; Draw Module 2 color validation screen
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