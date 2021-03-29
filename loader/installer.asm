;
; (c) Copyright 2021 by Tobias Bindhammer. All rights reserved.
;
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are met:
;     * Redistributions of source code must retain the above copyright
;       notice, this list of conditions and the following disclaimer.
;     * Redistributions in binary form must reproduce the above copyright
;       notice, this list of conditions and the following disclaimer in the
;       documentation and/or other materials provided with the distribution.
;     * The name of its author may not be used to endorse or promote products
;       derived from this software without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
; DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
; (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
; ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;

!src "../config.inc"
!convtab pet
!cpu 6510

.dc_src		= $fc
.dc_dst		= $fe
.mydrive	= $fb

.listen		= $ffb1
.listen_sa	= $ff93
.iecout		= $ffa8
.unlisten	= $ffae

		* = CONFIG_INSTALLER_ADDR
		!src "loader_acme.inc"
.init_inst
!if (CONFIG_AUTODETECT = 1) {
		!src "detect.asm"
}
		lda #$37
		sta <CONFIG_LAX_ADDR
!if (CONFIG_AUTODETECT = 0) {
		sta $01
		lda #$00
		sta $d015
}
		lda $ba
		sta .mydrive

		ldx #8
-
		stx $ba
		jsr .open_w_15
		bmi .not_present
		jsr .unlisten
		;ldx $ba
		cpx .mydrive
		beq .not_present
		jsr .install_responder
.not_present
		inx
		cpx #$0c
		bne -
.do_install
		lda .mydrive
		sta $ba

		;install bootloader with fast m-w and onetime loader-init
		jsr .install_bootstrap
		sei

		lda #$c3		;XXX TODO, needed? $03 would suffice?
		sta $dd00

		lda #$3f
		sta $dd02

.cnt = * + 1
		lda #(>.drivecode_size) + 1

                bit $dd00		;wait until drive bootloader is active
                bmi *-3

		lda #$37
		sta $dd02

-
.dc_data = * + 1
		lda .drivecode_start
                sec
                ror
		sta .dc_src
		;transfer like this?
                lda #$2f
.s_loop
                and #$2f                        ;clear bit 4 and 0..2 and waste some cycles here
                adc #$00                        ;on carry set, clear bit 4, else keep
		eor #$30
                ora #$0f

                sta $dd02
		pha				;make NTSC machines happy
		pla
                lsr .dc_src
                bne .s_loop

		inc .dc_data
		bne +
		inc .dc_data+1
+
		lda .dc_data
		cmp #<.drivecode_end
		bne -
		lda .dc_data+1
		cmp #>.drivecode_end
		bne -

		lda #$37			;raise atn to signal end of transfer
		sta $dd02

!if (CONFIG_RESIDENT_AUTOINST != 0) {
!if (bitfire_resident_size) < 256 {
		;better force to 8 bit, label might be defined as 16 bit
		ldx #<(bitfire_resident_size)
-
		lda .res_start,x
		sta CONFIG_RESIDENT_ADDR,x
		dex
	!if bitfire_resident_size >= $80 {
		cpx #$ff
		bne -
	} else {
		bpl -
	}
} else {
		;copy resident part
		ldx #$00
-
		lda .res_start,x
		sta CONFIG_RESIDENT_ADDR,x
		lda .res_start + ((bitfire_resident_size) - $100),x
		sta CONFIG_RESIDENT_ADDR + ((bitfire_resident_size) - $100),x
		dex
		bne -
}
}

.l1		lda $d012
.l2		cmp $d012
		beq .l2
		bmi .l1
		cmp #$20
		bcs .nontsc

		lda #$0d
		sta bitfire_ntsc0
		lda #$1d		;ora $xxxx,x
		sta bitfire_ntsc1
		lda #$3d		;and $xxxx,x
		sta bitfire_ntsc2
		lda #$7d		;adc $xxxx,x
		sta bitfire_ntsc3

		lda #$00
		sta bitfire_ntsc0 + 1
		lda #-$37
		sta bitfire_ntsc1 + 1
		sta bitfire_ntsc3 + 1
		lda #-$3f
		sta bitfire_ntsc2 + 1

		lda #$dd
		sta bitfire_ntsc0 + 2
		lda #$dc
		sta bitfire_ntsc1 + 2
		sta bitfire_ntsc2 + 2
		sta bitfire_ntsc3 + 2

		;adopt branch to point to bmi and waste another 2 cycles, bmi will always fall through, as two lsr happened before
		lda #bitfire_ntsc5 - bitfire_ntsc4 - 2
		sta bitfire_ntsc4 + 1
.nontsc
		lda #$3f			;drop atn to signal end of transfer
		sta $dd02

		;wait until floppy is ready
		;wait for drive to initialize XXX TODO maybe wait for special signal on $dd00?

;		sei
;		ldx #$10
;wait
;-
;		bit $d011
;		bpl *-3
;		bit $d011
;		bmi *-3
;		dex
;		bpl -
-
		lda $dd00
		bpl -
		rts

.open_w_15
		lda $ba
		jsr .listen
		lda #$00
		sta $90
		lda #$6f
		jmp .listen_sa

.install_bootstrap
		jsr .open_w_15
		lda #'i'
		jsr .iecout
		jsr .unlisten
		;ldx #$10
		;jsr wait
		;install first routines via m-w

		ldx #$00
.bs_loop

		stx .mw_code + 3

		jsr .open_w_15
		ldy #$00
-
		lda .mw_code,y
		jsr .iecout
		iny
		cpy #$06
		bne -
-
		lda .bootstrap_start,x
		jsr .iecout
		inx
		txa
		and #$1f
		bne -

		jsr .unlisten

		cpx #.bootstrap_size
		bcc .bs_loop

		;now execute bootstrap
		jsr .open_w_15
		ldy #$00
-
		lda .me_code,y
		jsr .iecout
		iny
		cpy #$05
		bne -
		jmp .unlisten

.install_responder
		jsr .open_w_15
		ldy #$00
.datalo		lda .atnlo,y
		jsr .iecout
		iny
		cpy #.atnlo_end - .atnlo
		bne .datalo
		jsr .unlisten

		jsr .open_w_15
		ldy #$00
.datahi		lda .atnhi,y
		jsr .iecout
		iny
		cpy #.atnhi_end - .atnhi
		bne .datahi
		jsr .unlisten

		jsr .open_w_15
		ldy #$00
.exec		lda .responder,y
		jsr .iecout
		iny
		cpy #.responder_end - .responder
		bne .exec
		jmp .unlisten

;XXX TODO keep current drive in $ba? kill all other drives beforehand, then upload code to #8
.responder_code	= $0205
.atnlo_code	= $0400
.atnhi_code	= .atnlo_code + $80

.mw_code
		!text "m-w"
		!word .bootstrap_run
		!byte $20
.me_code
		!text "m-e"
		!word .bootstrap_run

.responder
		!text "m-e"
		!word .responder_code
!pseudopc .responder_code {
		sei
		lda #$ff
		sta $1803
		ldx #$04
		stx $1801
		lsr		;lda #$7f
		sta $1802
		ldy #$00
		ldx #$10
		sty $1800
		jmp ($1800)
}
.responder_end

.atnlo		!text "m-w"
		!word .atnlo_code
		!byte .atnlo_end - .atnlo_start
.atnlo_start
!pseudopc .atnlo_code {
;00
		jmp ($1800)
		* = .atnlo_code + $10
;10
		sty $1800
		jmp ($1800)
}
.atnlo_end

.atnhi		!text "m-w"
		!word .atnhi_code
		!byte .atnhi_end - .atnhi_start
.atnhi_start
!pseudopc .atnhi_code {
;80
		;stx $1800
		;top
;84
		;bne .reset_check	;BRA
		;jmp ($1800)
		stx $1800
		jmp ($1800)		;get $84 free, set $1801 to $7a and check if really $84?
		* = .atnhi_code + $10
;90
		jmp ($1800)
}
.atnhi_end

!if (CONFIG_RESIDENT_AUTOINST != 0) {
.res_start
!bin "resident",,2
}

!src "drivecode.asm"