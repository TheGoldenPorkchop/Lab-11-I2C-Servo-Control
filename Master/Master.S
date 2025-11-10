;HEADER STUFF
;ANGEL NAVA
;RCET 3375
;Semester 5
;LAB11_Master I2C Servo Control
;Github URL

;Device Setup
;-------------------------------------------------------------------------------
    
;Configuration
    ; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

// config statements should precede project file includes.

;Include Statements
#include <xc.inc>
;Code Section
;-------------------------------------------------------------------------------
 
;Start of Program
PSECT resetVect,class=CODE,delta=2 ;Reset vector address -Wl,-presetVect=00h
    GOTO Setup

;Interrupt is called
PSECT isrVect,class=CODE,delta=2 ;isr or something
    GOTO Interrupt

;Setup Code that runs once at the power up/reset
PSECT code,class=CODE,delta=2 ;-Wl,-pcode=08h
    
Setup:
    ;Bank 3 (for ANSELH)
    BSF STATUS, 5 ; Go to Bank 3
    BSF STATUS, 6 ; Go to Bank 3
    MOVLW 0x02 ;AN1 is analog input (pin 3)
    MOVWF ANSEL
    CLRF ANSELH; 13:8 are digital inputs
    CLRF OPTION_REG
    MOVLW 0x00
    MOVWF BAUDCTL

    ;BANK 2
    BSF STATUS,5
    BSF STATUS,6
    CLRF CM2CON1
    CLRF CM2CON0

    ;Bank 1 (for TRISB, WPUB, IOCB, OPTION_REG, TRISC)
    BSF STATUS, 5
    BCF STATUS, 6 ; Go to Bank 1
    CLRF WPUB
    CLRF IOCB
    CLRF WPUB
    CLRF IOCB
    CLRF OPTION_REG ; Clears OPTION_REG (enables pull-ups globally, etc.)
    CLRF PSTRCON ;Disable PWM
    CLRF PCON ;Cleared power control register
    MOVLW 0x81
    MOVWF SPBRG
    CLRF SPBRGH
    MOVLW 0x00
    MOVWF TXSTA
    MOVLW 0X02
    MOVWF TRISA 
    MOVLW 0XFF ;Put bits into register
    MOVWF TRISB ;The bits moved in make PortB all inputs
    MOVLW 0x18
    MOVWF TRISC ;ALL outputs
    MOVLW 0X22 ;02
    MOVWF PIE1
    MOVLW 0X88
    MOVWF PR2 ;Timer 2 stuff
    MOVLW 0x80
    MOVWF ADCON1
    MOVLW 0xC0 ;Input Data sampled at the end of data output time and Standard Speed
    MOVWF SSPSTAT
    MOVLW 0x60 ;Acknowledge not received and Not acknowledge
    MOVWF SSPCON2

    ;Bank 0 (for INTCON, ports, peripherals)
    BCF STATUS, 5 ;Go to Bank 0
    BCF STATUS, 6 ; Go to Bank 0
    MOVLW 0x45 ;AN1 Selected. Go is enabled. A
    MOVWF ADCON0
    MOVLW 0X00 ;C0
    MOVWF INTCON ;Controls interrupts (GIE=1, RBIE=1)
    CLRF PIR1
    CLRF CCP1CON ; Disables PWM
    MOVLW 0x00
    MOVWF PORTA
    CLRF PORTB ;Clears the bits in PortB
    MOVLW 0x18
    MOVWF PORTC
    MOVLW 0x00 ;Disables Serial Comms
    MOVWF RCSTA
    
    CLRF CCP2CON ;Disables the second PWM function
    ;CLRF RCSTA ;Turns off the control register
    CLRF SSPCON ;Turns off the serial control port
    CLRF T1CON ;Turns off the timer register
    CLRF PSTRCON ;Disables PWM pulse steering
    CLRF CM2CON1 ;Disables Comparator 2
    MOVLW 0X00
    MOVWF TMR2
    MOVLW 0X00
    MOVWF T2CON
    MOVLW 0x38 ;38 Enables SDA and SCL,Release Clock, and I2C Master Mode
    MOVWF SSPCON
    
    ;Registers Setup
    STATS_SAVE EQU 0x20
    W_SAVE EQU 0x21
    C_SAVE EQU 0x22
    TIMER_COUNT EQU 0X23 ;Software counter for overflows
    PR2_PulseWidth EQU 0x24 ;Time On
    PR2_PulseSpace EQU 0x25 ;Time Off
    PulseSelect EQU 0x26 ;Will Help Determine Pulse Width/Space
    PreRC EQU 0x27 ;Saves RC Data
    DidHandShake EQU 0x28 ;Did the hand shake?
    OneTimeADC EQU 0x29 ;This will make sure we only send 2 bits of data
 
    MOVLW 0X00
    MOVWF TIMER_COUNT
    CLRF PR2_PulseWidth
    CLRF PR2_PulseSpace
    CLRF PulseSelect
    MOVLW 0x04
    MOVWF OneTimeADC
    MOVLW 0X4C
    MOVWF T2CON

    GOTO MainLoop
;-------------------------------------------------------------------------------
;Main Program Loop (Loops forever)
MainLoop:
    CLRF SSPBUF ;Clears buffer
    BTFSS PORTB,0 
    GOTO MainLoop
    
    BSF STATUS,5 ;Bank 1
    BSF SSPCON2,0 ;Enables Start Condition
    BCF STATUS,5 ;Bank 0
    MOVLW 0x40
    MOVWF SSPBUF ;Moves Address we want
    BSF STATUS,5 ;Bank 1
    BTFSC SSPSTAT,0 ;Checks to see if the buffer is still full.
    GOTO $-1
    ;BSF SSPCON2,2 ;Initiates Stop Condition
    
    BCF STATUS, 5 ;Bank 0
    MOVLW 0x88
    MOVWF SSPBUF ;Moves Data we want
    BSF STATUS,5 ;Bank 1
    BTFSC SSPSTAT,0 ;Checks to see if the buffer is still full.
    GOTO $-1
    BSF STATUS,5
    BSF SSPCON2,2 ;Initiates Stop Condition
 
    BTFSS SSPCON2,6;Small Testing
    GOTO Light
    BCF STATUS,5
    GOTO Debounce
    
    Light:
    BCF STATUS,5
    BSF PORTC,0
    GOTO Debounce
    
    Debounce:
    BCF STATUS,5
    BTFSC PORTB,0
    GOTO Debounce
    GOTO MainLoop
;-------------------
;-------------------------------------------------------------------------------
;Interrupt Service Routine
Interrupt:
    MOVWF W_SAVE
    MOVF STATUS, 0
    MOVWF STATS_SAVE
    
    BTFSS PIR1,5 ;RC or Timer?
    GOTO TimerCountCheck ;Timer
    GOTO RCSerialCheck
    
TimerCountCheck:
    DECFSZ TIMER_COUNT,F
    GOTO INTERRUPT_END ; If counter not zero, exit
    BTFSC PulseSelect,0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
RCSerialCheck:
    BCF PIE1,2 ;Disables Timer Interrupts
    MOVF RCREG,0
    MOVWF PreRC
    
    MOVF PreRC,0
    XORLW 0x24 ;$ Handshake
    BTFSC STATUS,2
    GOTO Dollar
    
    MOVF PreRC,0
    XORLW 0x23 ;# GRAB ADC Data
    BTFSC STATUS,2
    GOTO HashTag
    
    MOVF PreRC,0
    XORLW 0x21 ;! No Grab ADC Data
    BTFSC STATUS,2
    GOTO NoADCData
    
    BTFSC DidHandShake,0
    GOTO AcceptData ;1
    GOTO INTERRUPT_END
    
Dollar:
    MOVLW 0x24
    MOVWF TXREG
    BSF DidHandShake,0 ;Will Allow data to be processed in Interrupt
    BSF DidHandShake,1 ;Send4Bytes
    GOTO INTERRUPT_END
    
HashTag:
    BCF DidHandShake,0 ;Clears Dollar Hand Shake
    BSF DidHandShake,3;# Indicator
    GOTO INTERRUPT_END
    
NoADCData:
    MOVF PreRC,0
    MOVWF TXREG
    BCF DidHandShake,0
    BSF DidHandShake,1 ;Send4Bytes
    GOTO INTERRUPT_END
    
AcceptData:    
    MOVF PreRC,0
    XORLW 0x05
    BTFSC STATUS,2
    GOTO Hx05
    
    MOVF PreRC,0
    XORLW 0x06
    BTFSC STATUS,2
    GOTO Hx06
    
    MOVF PreRC,0
    XORLW 0x07
    BTFSC STATUS,2
    GOTO Hx07
    
    MOVF PreRC,0
    XORLW 0x08
    BTFSC STATUS,2
    GOTO Hx08
    
    MOVF PreRC,0
    XORLW 0x09
    BTFSC STATUS,2
    GOTO Hx09
    
    MOVF PreRC,0
    XORLW 0x0A
    BTFSC STATUS,2
    GOTO Hx0A
    
    MOVF PreRC,0
    XORLW 0x0B
    BTFSC STATUS,2
    GOTO Hx0B
    
    MOVF PreRC,0
    XORLW 0x0C
    BTFSC STATUS,2
    GOTO Hx0C
    
    MOVF PreRC,0
    XORLW 0x0D
    BTFSC STATUS,2
    GOTO Hx0D
    
    MOVF PreRC,0
    XORLW 0x0E
    BTFSC STATUS,2
    GOTO Hx0E
    
    MOVF PreRC,0
    XORLW 0x0F
    BTFSC STATUS,2
    GOTO Hx0F
    
    MOVF PreRC,0
    XORLW 0x10
    BTFSC STATUS,2
    GOTO Hx10
    
    MOVF PreRC,0
    XORLW 0x11
    BTFSC STATUS,2
    GOTO Hx11
    
    MOVF PreRC,0
    XORLW 0x12
    BTFSC STATUS,2
    GOTO Hx12
    
    MOVF PreRC,0
    XORLW 0x13
    BTFSC STATUS,2
    GOTO Hx13
    
    MOVF PreRC,0
    XORLW 0x14
    BTFSC STATUS,2
    GOTO Hx14
    
    MOVF PreRC,0
    XORLW 0x15
    BTFSC STATUS,2
    GOTO Hx15
    
    MOVF PreRC,0
    XORLW 0x16
    BTFSC STATUS,2
    GOTO Hx16
    
    MOVF PreRC,0
    XORLW 0x17
    BTFSC STATUS,2
    GOTO Hx17
    
    MOVF PreRC,0
    XORLW 0x18
    BTFSC STATUS,2
    GOTO Hx18
    
    MOVF PreRC,0
    XORLW 0x19
    BTFSC STATUS,2
    GOTO Hx19
    GOTO INTERRUPT_END
    
Hx05:
    MOVLW 0x32 ;50
    MOVWF PR2_PulseWidth
    MOVLW 0xC3 ;195
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx06:
    MOVLW 0x3C ;60
    MOVWF PR2_PulseWidth
    MOVLW 0xC2 ;194
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx07:
    MOVLW 0x46 ;70
    MOVWF PR2_PulseWidth
    MOVLW 0xC1 ;193
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx08:
    MOVLW 0x50 ;80
    MOVWF PR2_PulseWidth
    MOVLW 0xC0 ;192
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx09:
    MOVLW 0x5A ;80
    MOVWF PR2_PulseWidth
    MOVLW 0xBF ;191
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Hx0A:
    MOVLW 0x64 ;100
    MOVWF PR2_PulseWidth
    MOVLW 0xBE ;190
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx0B:
    MOVLW 0x6E ;110
    MOVWF PR2_PulseWidth
    MOVLW 0xBD ;189
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx0C:
    MOVLW 0x78 ;120
    MOVWF PR2_PulseWidth
    MOVLW 0xBC ;188
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx0D:
    MOVLW 0x82 ;130
    MOVWF PR2_PulseWidth
    MOVLW 0xBB ;187
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx0E:
    MOVLW 0x8C ;140
    MOVWF PR2_PulseWidth
    MOVLW 0xBA ;186
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Hx0F:
    MOVLW 0x96 ;150
    MOVWF PR2_PulseWidth
    MOVLW 0xB9 ;185
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx10:
    MOVLW 0xA0 ;160
    MOVWF PR2_PulseWidth
    MOVLW 0xB8 ;184
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx11:
    MOVLW 0xAA ;170
    MOVWF PR2_PulseWidth
    MOVLW 0xB7 ;183
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx12:
    MOVLW 0xB4 ;180
    MOVWF PR2_PulseWidth
    MOVLW 0xB6 ;182
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx13:
    MOVLW 0xBE ;190
    MOVWF PR2_PulseWidth
    MOVLW 0xB5 ;181
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx14:
    MOVLW 0xC8 ;200
    MOVWF PR2_PulseWidth
    MOVLW 0xB4 ;180
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx15:
    MOVLW 0xD2 ;210
    MOVWF PR2_PulseWidth
    MOVLW 0xB3 ;179
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx16:
    MOVLW 0xDC ;220
    MOVWF PR2_PulseWidth
    MOVLW 0xB2 ;178
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Hx17:
    MOVLW 0xE6 ;230
    MOVWF PR2_PulseWidth
    MOVLW 0xB1 ;177
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx18:
    MOVLW 0xF0 ;240
    MOVWF PR2_PulseWidth
    MOVLW 0xB0 ;176
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Hx19:
    MOVLW 0xFA ;250
    MOVWF PR2_PulseWidth
    MOVLW 0xAF ;175
    MOVWF PR2_PulseSpace
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

PulseWidthTime:
    MOVF PR2_PulseWidth,0
    BSF STATUS,5
    MOVWF PR2
    BCF STATUS,5
    MOVLW 0x05
    MOVWF TIMER_COUNT ;x5
    BSF PORTB,1
    BCF PulseSelect, 0
    MOVLW 0x4C ;TMR2ON and x10
    MOVWF T2CON
    GOTO INTERRUPT_END
    
PulseSpaceTime:
    MOVF PR2_PulseSpace,0
    BSF STATUS,5
    MOVWF PR2
    BCF STATUS,5
    MOVLW 0x19 ;x25
    MOVWF TIMER_COUNT
    BCF PORTB,1
    BSF PulseSelect, 0
    MOVLW 0x25 ;25
    MOVWF T2CON ;TMR2ON and x20
    GOTO INTERRUPT_END
    
INTERRUPT_END:
    BCF STATUS,5
    BCF PIR1,1 ;Clears TMR2 to PR2 Interupt Flag
    BSF PIE1,2
    
    ;Load the W stuff
    MOVF STATS_SAVE,0
    MOVWF STATUS
    MOVF W_SAVE,0

    RETFIE
END ;End of code. This is required