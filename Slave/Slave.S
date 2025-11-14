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
    MOVLW 0x00 ;AN1 is analog input (pins 3)
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
    ;MOVLW 0x81
    ;MOVWF SPBRG
    ;CLRF SPBRGH
    ;MOVLW 0x00
    ;MOVWF TXSTA
    MOVLW 0X02
    MOVWF TRISA 
    MOVLW 0X00 ;Put bits into register
    MOVWF TRISB ;The bits moved in make PortB all outputs
    MOVLW 0x18
    MOVWF TRISC ;ALL outputs
    MOVLW 0X02 ;02 22
    MOVWF PIE1
    BCF PIE1,3
    MOVLW 0X88
    MOVWF PR2 ;Timer 2 stuff
    MOVLW 0x00
    MOVWF ADCON1
    MOVLW 0x00 ;Input Data sampled at the end of data output time and Standard Speed
    MOVWF SSPSTAT
    MOVLW 0x00 ;
    MOVWF SSPCON2
    MOVLW 0x40
    MOVWF SSPADD

    ;Bank 0 (for INTCON, ports, peripherals)
    BCF STATUS, 5 ;Go to Bank 0
    BCF STATUS, 6 ; Go to Bank 0
    ;MOVLW 0x00 ;AN1 Selected. Go is enabled. A
    ;MOVWF ADCON0
    MOVLW 0XC0 ;C0
    MOVWF INTCON ;Controls interrupts (GIE=1, RBIE=1)
    CLRF PIR1
    CLRF CCP1CON ; Disables PWM
    MOVLW 0x00
    MOVWF PORTA
    CLRF PORTB ;Clears the bits in PortB
    MOVLW 0x18
    MOVWF PORTC
    ;MOVLW 0x00 ;Disables Serial Comms
    ;MOVWF RCSTA
    
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
    Servo1_DATA EQU 0x29 ; Temp
    Servo2_DATA EQU 0x30 ; Temp
    Servo3_DATA EQU 0x31 ; Temp
    CurrentServo_DATA EQU 0x32 ;
    DidFinish EQU 0x33 ;Prevents Overwriting
    Count1 EQU 0x34
 
    MOVLW 0X00
    MOVWF TIMER_COUNT
    CLRF PR2_PulseWidth
    CLRF PR2_PulseSpace
    CLRF PulseSelect
    CLRF RECEIVED_DATA
    MOVLW 0x01
    MOVWF ServoSelect
    MOVLW 0X4C
    MOVWF T2CON

    GOTO MainLoop
;-------------------------------------------------------------------------------
;Main Program Loop (Loops forever)
MainLoop:
    CLRF INTCON
    BTFSS PIR1,3
    GOTO $-1
    MOVF SSPBUF,0
    MOVWF RECEIVED_DATA
    BANKSEL SSPSTAT
    BTFSC SSPSTAT,0
    GOTO $-1
    BCF STATUS,5
    BCF STATUS,6
    
    BTFSC SSPCON,6
    GOTO $-1
    BSF SSPCON,4
    BCF PIR1,3
    
    MOVLW 0xC0
    MOVWF INTCON

    MOVF RECEIVED_DATA,0
    
    BTFSC RECEIVED_DATA,0
    MOVWF Servo1_DATA

    BTFSC RECEIVED_DATA,1
    MOVWF Servo2_DATA

    BTFSC RECEIVED_DATA,2
    MOVWF Servo3_DATA

    MOVLW 0x68 ;58
    MOVWF Count1
    DECFSZ Count1
    GOTO $-1
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
    
    BTFSC PIR1,1
    GOTO Timer2
    BTFSC PIR1,3
    GOTO Comms
    GOTO SecretThirdThing
    
    Comms:
    ;MOVF PORTB,0
    ;XORLW 0x40
    ;MOVWF PORTB
    BCF PIR1,3 ;Comms
    GOTO INTERRUPT_END ;???
    
    SecretThirdThing:
    ;MOVF PORTB,0
    ;XORLW 0x20
    ;MOVWF PORTB
    GOTO INTERRUPT_END ;???

    Timer2:
    DECFSZ TIMER_COUNT,F
    GOTO INTERRUPT_END ; If counter not zero, exit

    MOVF ServoSelect,0
    XORLW 0x01
    BTFSC STATUS,2
    GOTO Servo1
    
    MOVF ServoSelect,0
    XORLW 0x02
    BTFSC STATUS,2
    GOTO Servo2
    GOTO Servo3
    
Servo1:
    MOVF Servo1_DATA,0
    MOVWF CurrentServo_DATA
    
    BTFSC PulseSelect,1
    BSF PulseSelect,0 ;1 PW
    BTFSS PulseSelect,1
    BCF PulseSelect,0 ;0 PS
    
    GOTO PWMSelect
    
Servo2:
    MOVF Servo2_DATA,0
    MOVWF CurrentServo_DATA
    
    BTFSC PulseSelect,2
    BSF PulseSelect,0 ;1 PW
    BTFSS PulseSelect,2
    BCF PulseSelect,0 ;0 PS
    
    GOTO PWMSelect
    
Servo3:
    MOVF Servo3_DATA,0
    MOVWF CurrentServo_DATA
    
    BTFSC PulseSelect,3
    BSF PulseSelect,0 ;1 PW
    BTFSS PulseSelect,3
    BCF PulseSelect,0 ;0 PS
    
    GOTO PWMSelect

PWMSelect:
    ;SEARCHING FOR THE RIGHT BITS
    MOVLW 0xF0
    ANDWF CurrentServo_DATA,1
    SWAPF CurrentServo_DATA
    
    MOVF CurrentServo_DATA,0
    XORLW 0x00
    BTFSC STATUS,2
    GOTO Bx0000
    
    MOVF CurrentServo_DATA,0
    XORLW 0x01
    BTFSC STATUS,2
    GOTO Bx0001
    
    MOVF CurrentServo_DATA,0
    XORLW 0x02
    BTFSC STATUS,2
    GOTO Bx0010
    
    MOVF CurrentServo_DATA,0
    XORLW 0x03
    BTFSC STATUS,2
    GOTO Bx0011
    
    MOVF CurrentServo_DATA,0
    XORLW 0x04
    BTFSC STATUS,2
    GOTO Bx0100
    
    MOVF CurrentServo_DATA,0
    XORLW 0x05
    BTFSC STATUS,2
    GOTO Bx0101

    MOVF CurrentServo_DATA,0
    XORLW 0x06
    BTFSC STATUS,2
    GOTO Bx0110
    
    MOVF CurrentServo_DATA,0
    XORLW 0x07
    BTFSC STATUS,2
    GOTO Bx0111
    
    MOVF CurrentServo_DATA,0
    XORLW 0x08
    BTFSC STATUS,2
    GOTO Bx1000
    
    MOVF CurrentServo_DATA,0
    XORLW 0x09
    BTFSC STATUS,2
    GOTO Bx1001
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0A
    BTFSC STATUS,2
    GOTO Bx1010
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0B
    BTFSC STATUS,2
    GOTO Bx1011
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0C
    BTFSC STATUS,2
    GOTO Bx1100
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0D
    BTFSC STATUS,2
    GOTO Bx1101
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0E
    BTFSC STATUS,2
    GOTO Bx1110
    
    MOVF CurrentServo_DATA,0
    XORLW 0x0F
    BTFSC STATUS,2
    GOTO Bx1111
    
    ;MOVF PORTB,0
    ;XORLW 0x10 ;somehow no matches
    ;MOVWF PORTB
    
    GOTO INTERRUPT_END

;SETTING THE RIGHGT TIMES FOR THE SELECTED BITS
    ;Control Z to this point
Bx0000:
    MOVLW 0x32 ;50
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;195 changing it to 65
    MOVWF PR2_PulseSpace    
    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0001:
    MOVLW 0x3C ;70 ;;64
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;194
    MOVWF PR2_PulseSpace   
    
    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0010:
    MOVLW 0x46 ;80 ;;96
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;193
    MOVWF PR2_PulseSpace   

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0011:
    MOVLW 0x50 ;90 ;;C8
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;192
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0100:
    MOVLW 0x5A ;100 ;FA
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;191
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Bx0101:
    MOVLW 0x64 ;110 ;;C8
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;190
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0110:
    MOVLW 0x6E ;120 ;;96
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;189
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx0111:
    MOVLW 0x78 ; 82 ;64
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;188
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1000:
    MOVLW 0x82 ;140 82
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;187
    MOVWF PR2_PulseSpace  

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1001:
    MOVLW 0x8C ;140 8C
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;186
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0

Bx1010:
    MOVLW 0x96 ;150
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;185
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1011:
    MOVLW 0xA0 ;160
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;184
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1100:
    MOVLW 0xAA ;170
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;183
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1101:
    MOVLW 0xB4 ;180
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;182
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1110:
    MOVLW 0xBE ;190
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;181
    MOVWF PR2_PulseSpace

    BTFSC PulseSelect, 0
    GOTO PulseWidthTime ;1
    GOTO PulseSpaceTime ;0
    
Bx1111:
    MOVLW 0xC8 ;200
    MOVWF PR2_PulseWidth
    MOVLW 0x41 ;180
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
    
    MOVF ServoSelect,0
    XORLW 0x01
    BTFSC STATUS,2
    BSF PORTB,1
    MOVF ServoSelect,0
    XORLW 0x01
    BTFSC STATUS,2
    BCF PulseSelect,1
    
    MOVF ServoSelect,0
    XORLW 0x02
    BTFSC STATUS,2
    BSF PORTB,3
    MOVF ServoSelect,0
    XORLW 0x02
    BTFSC STATUS,2
    BCF PulseSelect,2
    
    MOVF ServoSelect,0
    XORLW 0x03
    BTFSC STATUS,2
    BSF PORTB,5
    MOVF ServoSelect,0
    XORLW 0x03
    BTFSC STATUS,2
    BCF PulseSelect,3
    
    CLRF TMR2 ;Clears TMR2
    MOVLW 0x4C
    MOVWF T2CON
    GOTO INTERRUPT_END
    
PulseSpaceTime:
    MOVF PR2_PulseSpace
    BSF STATUS,5
    MOVWF PR2
    BCF STATUS,5
    MOVLW 0x05
    MOVWF TIMER_COUNT
    
    MOVF ServoSelect,0
    XORLW 0x01
    BTFSC STATUS,2
    BCF PORTB,1
    MOVF ServoSelect,0
    XORLW 0x01
    BTFSC STATUS,2
    BSF PulseSelect,1
    
    MOVF ServoSelect,0
    XORLW 0x02
    BTFSC STATUS,2
    BCF PORTB,3
    MOVF ServoSelect,0
    XORLW 0x02
    BTFSC STATUS,2
    BSF PulseSelect,2
    
    MOVF ServoSelect,0
    XORLW 0x03
    BTFSC STATUS,2
    BCF PORTB,5
    MOVF ServoSelect,0
    XORLW 0x03
    BTFSC STATUS,2
    BSF PulseSelect,3
    MOVF ServoSelect,0
    XORLW 0x03
    BTFSC STATUS,2
    CLRF ServoSelect
    
    INCF ServoSelect
    CLRF TMR2 ;Clears TMR2

    MOVLW 0x25
    MOVWF T2CON
    GOTO INTERRUPT_END

INTERRUPT_END:
    BCF STATUS,5
    BCF PIR1,1 ;Clears TMR2 to PR2 Interupt Flag
    
    MOVLW 0xC0 ;Reenable interrupts
    MOVWF INTCON
    
    ;Load the W stuff
    MOVF STATS_SAVE,0
    MOVWF STATUS
    MOVF W_SAVE,0
    
    RETFIE
END ;End of code. This is required