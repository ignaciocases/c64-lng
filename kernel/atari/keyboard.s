;
; Atari keyboard handler
; Maciej 'YTM/Alliance' Witkowiak <ytm@friko.onet.pl>
; 25.12.2000
;

; - check keyboard maps & update for all extended functions & characters like `
; - OPTION=alt, START=ex1, SELECT=ex2, HELP=ex3, CAPS

#include <config.h>
#include <system.h>
#include MACHINE_H
#include <keyboard.h>
#include <zp.h>

		;; UNIX (ascii) decoding tables

#define dunno $7f
#define none_c		dunno
; other defines for special characters in tables below (later)
; internal codes $81-84 - cursors, $df/$f0 console toggle (prev/next), $f1-$f7 - goto console
; $e0-$ef internal flags for altflag toggle, $f8-$ff is reserved to maintain code similarity
; to c64 keyboard
#define break_c		$03		; break is equal to CTRL+C
#define help_c		$e1		; internal code -> keyb_ex3
#define esc_c		$1b
#define return_c	$0a
#define space_c		$20
#define bkspc_c		$08
#define tab_c		$09
#define caps_c		$e0		; internal code -> keyb_caps
#define inv_c		dunno
#define shelp_c		dunno
#define sesc_c		dunno
#define sreturn_c	dunno
#define sspace_c	dunno
#define clear_c		dunno
#define insert_c	dunno
#define del_c		$08
#define stab_c		dunno
#define sinv_c		dunno
#define scaps_c		dunno
#define backslash_c	"\\"

#define csr_up_c	$81		; internal code -> cursor up
#define csr_down_c	$82		; down
#define csr_left_c	$83		; left
#define csr_right_c	$84		; right

;	.byte "L", "J", ";", $03, $04, "K", "+", "*"
;	.byte "O", $09, "P", "U", return_c, "I", "-", "="
;	.byte "V", help_c, "C", $03, $04, "B", "X", "Z"
;	.byte "4", $09, "3", "6", esc_c, "5", "2", "1"
;	.byte ",", space_c, ".", "N", $04, "M", "/", caps_c
;	.byte "R", $09, "E", "Y", tab_c, "T", "W", "Q"
;	.byte "9", $01, "0", "7", bkspc_c, "8", "<", ">"
;	.byte "F", "H", "D", $0b, caps_c, "G", "S", "A"

_keytab_normal:
	.byte $6c, $6a, ";", none_c, none_c, $6b, "+", "*"
	.byte $6f, none_c, $70, $75, return_c, $69, "-", "="
	.byte $76, help_c, $63, none_c, none_c, $62, $78, $7a
	.byte "4", none_c, "3", "6", esc_c, "5", "2", "1"
	.byte ",", space_c, ".", $6e, none_c, $6d, "/", inv_c
	.byte $72, none_c, $65, $79, tab_c, $74, $77, $71
	.byte "9", none_c, "0", "7", bkspc_c, "8", "<", ">"
	.byte $66, $68, $64, none_c, caps_c, $67, $73, $61
_keytab_shift:
	.byte $4c, $4a, ":", none_c, none_c, $4b, backslash_c, "^"
	.byte $4f, none_c, $50, $55, sreturn_c, $49, "_", "|"
	.byte $56, shelp_c, $43, none_c, none_c, $42, $58, $5a
	.byte "$", none_c, "#", "&", sesc_c, "%", $22, "!"
	.byte "[", sspace_c, "]", $4e, none_c, $4d, "?", sinv_c
	.byte $52, none_c, $45, $59, stab_c, $54, $57, $51
	.byte "(", none_c, ")", "'", del_c, "@", clear_c, insert_c
	.byte $46, $48, $44, none_c, scaps_c, $47, $53, $41
_keytab_control:
	.byte $0c, $0a, ";", none_c, none_c, $0b, csr_left_c, csr_right_c
	.byte $0f, none_c, $10, $15, return_c, $09, csr_up_c, csr_down_c
	.byte $16, help_c, $03, none_c, none_c, $02, $18, $1a
	.byte "4", none_c, "3", "6", esc_c, "5", "2", "1"
	.byte ",", space_c, ".", $0e, none_c, $0d, "/", inv_c
	.byte $12, none_c, $05, $19, tab_c, $14, $17, $11
	.byte "9", none_c, "0", "7", bkspc_c, "8", "<", ">"
	.byte $06, $08, $04, none_c, caps_c, $07, $13, $01

; console (START+OPTION) modifiers - 'lock' keys
_cons_toggle:	; none, START, OPTION, START+OPTION
		.byte	0, keyb_ex1, keyb_ex2, keyb_ex1|keyb_ex2

; to speedup trigger translation
_trig_toggle:
		.byte	%11100000, %11110000

;;; ZEROpage: altflags 1
;;; ZEROpage: keycode 1
;altflags:		.buf 1			; altflags (equal to $28d in C64 ROM)
;keycode:		.buf 1			; keycode (equal to $cb in C64 ROM)

joy0result:		.byte $ff		; current state of joy0
joy1result:		.byte $ff		; current state of joy1

lastcons:		.byte 0
tmp:			.byte 0

		;; to save the time only this is called only on timer IRQ
.global joys_scan

joys_scan:
		;; joystick scanning, return the same values as C64
		;; (combine with trigger)
		lda GTIA_TRIG0
		and #%00000001
		tax
		lda PIA_PORTA
		pha
		and #%00001111
		ora _trig_toggle,x
		sta joy0result

		lda GTIA_TRIG1
		and #%00000001
		tax
		pla
		lsr a
		lsr a
		lsr a
		lsr a
		ora _trig_toggle,x
		sta joy1result

		;; console keys don't do keyboard IRQ and we must know their state
		lda GTIA_CONSOL
		cmp lastcons
		bne +				; something new!
		rts
	+	sta lastcons
		and #%00000111
		eor #%00000111
		pha
		and #%00000011			; only START+SELECT
		beq +				; none pressed?
		tax
		lda altflags
		eor _cons_toggle,x
		sta altflags

	+	pla
		and #%00000100			; OPTION is alt, no toggle but state driven
		beq +
		lda altflags			; set
		ora #keyb_alt
		bne ++
	+	lda altflags			; clear
		and #~keyb_alt
	+	sta altflags
		rts

keyb_scan:
		;; enter here with POKEY_IRQST in A
		;; keyboard scanning begins here
		;lda POKEY_IRQST
		tax
		bpl +				; was it a break?
		lda #break_c
		jmp _addkey
		;; we're here from BREAK|KEYB IRQ so it must has been a keypress
	+	lda POKEY_KBCODE

		tax				; save for key resolve
		and #%10000000			; CONTROL?
		beq +
		lda altflags			; set
		ora #keyb_ctrl
		bne ++
	+	lda altflags			; clear
		and #~keyb_ctrl
	+	sta altflags

		txa
		and #%01000000			; SHIFT?
		beq +
		lda altflags			; set
		ora #keyb_lshift|keyb_rshift
		bne ++
	+	lda altflags			; clear
		and #~(keyb_lshift|keyb_rshift)
	+	sta altflags

		lda _keytab_normal,x		; get keycode
		bpl to_normal
		cmp #$e0			; CAPS flag?
		bne +				; unknown - pass it through
		lda altflags			; toggle caps flag
		eor #keyb_caps
		sta altflags
		rts
	+	cmp #$e1			; ex3 flag?
		bne _addkey
		lda altflags
		eor #keyb_ex3
		sta altflags
		rts

to_normal:	lda altflags
		and #keyb_caps
		bne to_caps
		lda _keytab_normal,x
		jmp _addkey

to_caps:	lda  _keytab_normal,x		; CAPS
		cmp  #$61			; if >='a'
		bcc  _addkey
		cmp  #$7b			; and =<'z'+1
		bcs  _addkey
		and  #%11011111			; lower->UPPER
		;jmp  _addkey

		;; end of keyboard scan

		;;;;;;;;;;;;;
		;; common routines, should be moved to kernel code
		;;;;;;;;;;;;;
		;; adds a keycode to the keyboard buffer
		;; (has to expand csr-movement to esacape codes)

_addkey:
		cmp  #$80
		bcc  +
		cmp  #$f0
		bcs  to_toggle_console
		cmp  #$df
		beq  ++
		cmp  #$85				; $81/$82/$83/$84 - csr codes
		bcs  +
		;; generate 3byte escape sequence
		pha
		lda  #$1b
		jsr  console_passkey		; (console_passkey is define in fs_cons.s)
		lda  #$5b
		jsr  console_passkey
		pla
		eor  #$c0			; $8x becomes $4x
	+ 	jmp  console_passkey		; pass ascii code to console driver

	+	lda  #$88
		bne  +
to_toggle_console:
		and  #$07
	+	jmp  console_toggle		; call function of console driver
						; (console_toggle is defined is console.s)

		;; get state of keyboard
keyb_stat:
		lda  altflags				; bit2..0= CTRL,right_SHIFT,left_SHIFT
		rts

		;; get state of joystick 0
keyb_joy0:
		lda  joy0result
		eor  #$ff
		rts

		;; get state of joystick 1
keyb_joy1:
		lda  joy1result
		eor  #$ff
		rts
