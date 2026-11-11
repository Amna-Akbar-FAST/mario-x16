; File:mario.asm
; Author:Amna
; Module:1-Program Skeleton & DOS Setup
; Description:Single-segment 16-bit COM setup without section directives.
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
    push ax        ; Skeleton setup: Reserved for Video Mode & Interrupt setup in future phases
    pop ax
    ret

;Subroutine: MainLoop
;Purpose:    Placeholder for game loop execution.
;Inputs:  None | Outputs: None | Registers Preserved: ALL
MainLoop:
    ret     ; Game state execution will be called here

; Subroutine: CleanExit
; Purpose:    Safely restores execution state and returns control to DOS.
; Inputs:     None | Outputs: None | Registers Changed: None (Exits)

CleanExit:
    mov ah, 4Ch                     ; INT 21h, AH=4Ch: Terminate Program
    mov al, 00h                     ; Return Code 0 (Clean exit)
    int 21h

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