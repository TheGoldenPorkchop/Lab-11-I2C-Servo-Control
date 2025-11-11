;HEADER STUFF
;ANGEL NAVA
;RCET 3375
;Semester 5
;LAB11_Slave I2C Servo Control
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
    MOVLW 0x02 ;AN1 is analog input (pins 3)
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
    MOVLW 0X00 ;Put bits into register
    MOVWF TRISB ;The bits moved in make PortB all outputs
    MOVLW 0x18
    MOVWF TRISC ;ALL outputs
    MOVLW 0X0E ;02 22
    MOVWF PIE1
    MOVLW 0X88
    MOVWF PR2 ;Timer 2 stuff
    MOVLW 0x80
    MOVWF ADCON1
    MOVLW 0xC0 ;Input Data sampled at the end of data output time and Standard Speed
    MOVWF SSPSTAT
    MOVLW 0x00 ;
    MOVWF SSPCON2
    MOVLW 0x40
    MOVWF SSPADD

    ;Bank 0 (for INTCON, ports, peripherals)
    BCF STATUS, 5 ;Go to Bank 0
    BCF STATUS, 6 ; Go to Bank 0
    MOVLW 0x45 ;AN1 Selected. Go is enabled. A
    MOVWF ADCON0
    MOVLW 0XC0 ;C0
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
    MOVLW 0x36 ;36 Enables SDA and SCL,Release Clock, and I2C 7 bit Slave Mode
    MOVWF SSPCON
    
    ;Registers Setup
    STATS_SAVE EQU 0x20
    W_SAVE EQU 0x21
    C_SAVE EQU 0x22
    TIMER_COUNT EQU 0X23 ;Software counter for overflows
    PR2_PulseWidth EQU 0x24 ;Time On
    PR2_PulseSpace EQU 0x25 ;Time Off
    PulseSelect EQU 0x26 ;Will Help Determine Pulse Width/Space
    ServoSelect EQU 0x27 ;Determines the servo
    RECEIVED_DATA EQU 0x28 ; Temp
 
    MOVLW 0X00
    MOVWF TIMER_COUNT
    CLRF PR2_PulseWidth
    CLRF PR2_PulseSpace
    CLRF PulseSelect
    CLRF RECEIVED_DATA
    MOVLW 0X06
    MOVWF T2CON

    GOTO MainLoop
;-------------------------------------------------------------------------------
;Main Program Loop (Loops forever)
MainLoop:
    
    ;BTFSS PIR1,3
    ;GOTO $-1
    ;MOVF SSPBUF,0
    ;MOVWF RECEIVED_DATA
    ;CLRF SSPBUF
    ;BANKSEL SSPSTAT
    ;BCF SSPSTAT,0
    ;BCF STATUS,5
    ;BCF STATUS,6
    
    ;BCF PIR1,3
    NOP
    GOTO MainLoop
    
;-------------------
;-------------------------------------------------------------------------------
;Interrupt Service Routine
Interrupt:
    MOVWF W_SAVE
    MOVF STATUS, 0
    MOVWF STATS_SAVE
    
    CLRF INTCON
    
    BTFSS PIR1,3 ;RC or Timer?
    GOTO TimerCountCheck ;Timer
    GOTO GrabData
    
TimerCountCheck:
    DECFSZ TIMER_COUNT,F
    GOTO INTERRUPT_END ; If counter not zero, exit
    BTFSC PulseSelect,0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
GrabData:
    MOVF SSPBUF,0
    MOVWF RECEIVED_DATA
    CLRF SSPBUF
    BANKSEL SSPSTAT
    BCF SSPSTAT,0
    BCF STATUS,5
    BCF STATUS,6
    
    GOTO PWMSelect
    
    
PWMSelect:
    ;SEARCHING FOR THE RIGHT BITS
    BTFSC RECEIVED_DATA,7
    GOTO Bx1UUU
    BTFSC RECEIVED_DATA,6
    GOTO Bx01UU
    BTFSC RECEIVED_DATA,5
    GOTO Bx001U
    BTFSC RECEIVED_DATA,4
    GOTO Bx0001 ;Full Register
    GOTO Bx0000 ;Full Register
    
Bx1UUU:
    BTFSC RECEIVED_DATA,6
    GOTO Bx11UU
    BTFSC RECEIVED_DATA,5
    GOTO Bx101U
    BTFSC RECEIVED_DATA,4
    GOTO Bx1001 ;Full Register
    GOTO Bx1000 ;Full Register
    
Bx11UU:
    BTFSC RECEIVED_DATA,5
    GOTO Bx111U
    BTFSC RECEIVED_DATA,4
    GOTO Bx1101 ;Full Register
    GOTO Bx1100 ;Full Register
    
Bx101U:
    BTFSC RECEIVED_DATA,4
    GOTO Bx1011 ;Full Register
    GOTO Bx1010 ;Full Register
    
Bx111U:
    BTFSC RECEIVED_DATA,4
    GOTO Bx1111 ;Full Register
    GOTO Bx1110 ;Full Register
    
Bx01UU:
    BTFSC RECEIVED_DATA,5
    GOTO Bx011U
    BTFSC RECEIVED_DATA,4
    GOTO Bx0101 ;Full Register
    GOTO Bx0100 ;Full Register
    
Bx011U:
    BTFSC RECEIVED_DATA,4
    GOTO Bx0111 ;Full Register
    GOTO Bx0110 ;Full Register
    
Bx001U:
    BTFSC RECEIVED_DATA,4
    GOTO Bx0011 ;Full Register
    GOTO Bx0010 ;Full Register
    
;SETTING THE RIGHGT TIMES FOR THE SELECTED BITS
Bx0000:
    MOVLW 0x32 ;50
    MOVWF PR2_PulseWidth
    MOVLW 0xC3 ;195
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0001:
    MOVLW 0x3C ;60
    MOVWF PR2_PulseWidth
    MOVLW 0xC2 ;194
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0010:
    MOVLW 0x46 ;70
    MOVWF PR2_PulseWidth
    MOVLW 0xC1 ;193
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0011:
    MOVLW 0x50 ;80
    MOVWF PR2_PulseWidth
    MOVLW 0xC0 ;192
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0100:
    MOVLW 0x5A ;80
    MOVWF PR2_PulseWidth
    MOVLW 0xBF ;191
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Bx0101:
    MOVLW 0x64 ;100
    MOVWF PR2_PulseWidth
    MOVLW 0xBE ;190
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0110:
    MOVLW 0x6E ;110
    MOVWF PR2_PulseWidth
    MOVLW 0xBD ;189
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0111:
    MOVLW 0x78 ;120
    MOVWF PR2_PulseWidth
    MOVLW 0xBC ;188
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1000:
    MOVLW 0x82 ;130
    MOVWF PR2_PulseWidth
    MOVLW 0xBB ;187
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1001:
    MOVLW 0x8C ;140
    MOVWF PR2_PulseWidth
    MOVLW 0xBA ;186
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Bx1010:
    MOVLW 0x96 ;150
    MOVWF PR2_PulseWidth
    MOVLW 0xB9 ;185
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1011:
    MOVLW 0xA0 ;160
    MOVWF PR2_PulseWidth
    MOVLW 0xB8 ;184
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1100:
    MOVLW 0xAA ;170
    MOVWF PR2_PulseWidth
    MOVLW 0xB7 ;183
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1101:
    MOVLW 0xB4 ;180
    MOVWF PR2_PulseWidth
    MOVLW 0xB6 ;182
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1110:
    MOVLW 0xBE ;190
    MOVWF PR2_PulseWidth
    MOVLW 0xB5 ;181
    MOVWF PR2_PulseSpace    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1111:
    MOVLW 0xC8 ;200
    MOVWF PR2_PulseWidth
    MOVLW 0xB4 ;180
    MOVWF PR2_PulseSpace  
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
PulseWidthTime:
    MOVF PR2_PulseWidth,0
    BSF STATUS,5
    MOVWF PR2
    BCF STATUS,5
    MOVLW 0x01
    MOVWF TIMER_COUNT
    
    BTFSC RECEIVED_DATA,0
    BSF PORTB,1
    BTFSC RECEIVED_DATA,1
    BSF PORTB,2
    BTFSC RECEIVED_DATA,2
    BSF PORTB,3
    
    BCF PulseSelect, 0
    MOVLW 0x4C
    MOVWF T2CON
    GOTO INTERRUPT_END
    
PulseSpaceTime:
    MOVF PR2_PulseSpace,0
    BSF STATUS,5
    MOVWF PR2
    BCF STATUS,5
    MOVLW 0x05
    MOVWF TIMER_COUNT
    
    BTFSC RECEIVED_DATA,0
    BCF PORTB,1
    BTFSC RECEIVED_DATA,1
    BCF PORTB,2
    BTFSC RECEIVED_DATA,2
    BCF PORTB,3

    BSF PulseSelect, 0
    MOVLW 0x25
    MOVWF T2CON
    GOTO INTERRUPT_END
    
    
    
INTERRUPT_END:
    BCF STATUS,5
    BCF PIR1,1 ;Clears TMR2 to PR2 Interupt Flag
    BSF PIE1,2
    BSF PIE1,3
    BCF PIR1,3
    CLRF TMR2 ;Clears TMR2
    MOVLW 0XC0
    MOVWF INTCON
    
    ;Load the W stuff
    MOVF STATS_SAVE,0
    MOVWF STATUS
    MOVF W_SAVE,0

    RETFIE
END ;End of code. This is required