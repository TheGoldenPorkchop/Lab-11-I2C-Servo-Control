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
    MOVLW 0x00
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
    DataSend EQU 0x30 ;Send to Slave
 
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
    BSF ADCON0,1
    GOTO ADC_CHECK
    
ADC_CHECK:
    BTFSC ADCON0,1
    GOTO ADC_CHECK    

    MOVF ADRESH,0
    MOVWF DataSend
    CLRF SSPBUF ;Clears buffer
    ;BTFSS PORTB,0 
    ;GOTO MainLoop
    GOTO MainSend
    
MainSend:
    
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
    ;MOVLW 0x88
    MOVF DataSend,0
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