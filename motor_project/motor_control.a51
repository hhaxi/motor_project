ORG 0000H
LJMP MAIN
ORG 000BH        ; 定时器0中断入口
LJMP TIMER0_ISR

; 常量定义
MODE_STOP     EQU 0    ; 停止模式
MODE_CONSTANT EQU 1    ; 恒速模式
MODE_INCREMENT EQU 2   ; 风速递增模式
MODE_NATURAL  EQU 3    ; 自然风模式

; 变量定义
CURRENT_MODE DATA 20H  ; 当前模式
CURRENT_GEAR DATA 21H  ; 当前档位（恒速模式用）
TIMER_STATE  DATA 22H  ; 定时状态:0=未启动,1=设置中,2=运行中
TIMER_COUNT  DATA 23H  ; 定时倒计时(秒)
STEP_PTR     DATA 24H  ; 步进电机节拍指针
RAND_SEED    DATA 25H  ; 随机数种子
DISPLAY_TIMER DATA 26H ; 模式显示计时器
INC_TIMER    DATA 27H  ; 递增模式计时器
POWER_SAVE   DATA 28H  ; 节能标志（0:正常,1:节能）
OPER_TIMER   DATA 29H  ; 操作计时器（节能用）

; 主程序
ORG 0100H
MAIN:
    MOV SP, #60H        ; 设置堆栈指针
    MOV CURRENT_MODE, #MODE_STOP ; 初始模式：停止
    MOV CURRENT_GEAR, #1   ; 初始档位：1
    MOV TIMER_STATE, #0    ; 初始未启动定时
    MOV TIMER_COUNT, #0    ; 定时倒计时清零
    MOV STEP_PTR, #0       ; 步进指针初始化
    MOV RAND_SEED, #17     ; 随机数种子初始化
    MOV DISPLAY_TIMER, #0  ; 模式显示计时清零
    MOV INC_TIMER, #0      ; 递增计时清零
    MOV POWER_SAVE, #0     ; 节能模式关闭
    MOV OPER_TIMER, #0     ; 操作计时清零
    
    ; 初始化定时器0（50ms定时）
    MOV TMOD, #01H      ; 定时器0模式1（16位）
    MOV TH0, #3CH       ; 50ms定时初值（12MHz晶振）
    MOV TL0, #0B0H
    SETB EA             ; 开总中断
    SETB ET0            ; 允许定时器0中断
    SETB TR0            ; 启动定时器0
    
    ; 初始显示停止模式
    MOV P0, #0C0H       ; 显示"0"

MAIN_LOOP:
    LCALL KEY_SCAN      ; 扫描按键
    
    ; 检查定时状态
    MOV A, TIMER_STATE
    CJNE A, #2, NOT_TIMER_RUN
    MOV A, TIMER_COUNT
    JZ TIMER_ENDED      ; 定时结束
    
NOT_TIMER_RUN:
    ; 检查当前模式是否需要关闭电机
    MOV A, CURRENT_MODE
    JNZ NOT_STOP_MODE
STOP_MODE:
    ; 停止模式 - 确保完全停止
    MOV P2, #00H        ; 清除所有相位
    MOV STEP_PTR, #0    ; 重置步进指针
    LJMP MAIN_LOOP_END

TIMER_ENDED:
    ; 定时结束 - 停止电机
    MOV TIMER_STATE, #0    ; 重置定时状态
    MOV CURRENT_MODE, #MODE_STOP ; 进入停止模式
    MOV P2, #00H          ; 停止电机
    MOV STEP_PTR, #0      ; 重置步进指针
    SJMP MAIN_LOOP_END

NOT_STOP_MODE:
    ; 根据当前模式处理
    MOV A, CURRENT_MODE
    CJNE A, #MODE_CONSTANT, CHECK_INCREMENT
    LJMP CONSTANT_MODE  ; 恒速模式
    
CHECK_INCREMENT:
    CJNE A, #MODE_INCREMENT, NATURAL_MODE
    LJMP INCREMENT_MODE ; 风速递增模式
    
NATURAL_MODE:
    LJMP NATURAL_MODE_HANDLE ; 自然风模式

CONSTANT_MODE:
    ; 恒速模式 - 根据档位驱动
    LCALL SET_DELAY
    LCALL STEP_MOTOR
    LCALL DELAY
    LJMP MAIN_LOOP_END

INCREMENT_MODE:
    ; 风速递增模式 - 自动循环
    LCALL STEP_MOTOR
    LCALL SET_DELAY
    LCALL DELAY
    LJMP MAIN_LOOP_END

NATURAL_MODE_HANDLE:
    ; 自然风模式 - 随机延时
    LCALL GEN_RANDOM
    LCALL STEP_MOTOR
    LCALL DELAY
    LJMP MAIN_LOOP_END

MAIN_LOOP_END:
    ; 更新数码管显示
    MOV A, TIMER_STATE
    JNZ SHOW_TIMER_DISP ; 在定时状态时显示定时相关
    
    ; 非定时状态 - 显示模式内容
    MOV A, DISPLAY_TIMER
    JNZ SHOW_MODE_CHAR  ; 如果显示计时未结束，显示模式字符
    
    ; 显示计时结束，显示内容
    MOV A, CURRENT_MODE
    CJNE A, #MODE_CONSTANT, SHOW_DEFAULT
    ; 恒速模式显示档位
    MOV DPTR, #DIGIT_TABLE
    MOV A, CURRENT_GEAR
    DEC A               ; 档位1显示'1'
    MOVC A, @A+DPTR
    MOV P0, A
    SJMP DISPLAY_DONE
    
SHOW_DEFAULT:
    ; 其他模式显示相应字符
    MOV DPTR, #MODE_TABLE
    MOV A, CURRENT_MODE
    MOVC A, @A+DPTR
    MOV P0, A
    SJMP DISPLAY_DONE

SHOW_MODE_CHAR:
    ; 显示模式字符
    MOV DPTR, #MODE_TABLE
    MOV A, CURRENT_MODE
    MOVC A, @A+DPTR
    MOV P0, A
    SJMP DISPLAY_DONE

SHOW_TIMER_DISP:
    ; 定时状态 - 显示定时信息
    MOV A, TIMER_STATE
    CJNE A, #1, SHOW_COUNTDOWN
    
    ; 定时设置状态 - 显示设置值
    MOV A, TIMER_COUNT
    MOV DPTR, #DIGIT_TABLE
    MOVC A, @A+DPTR
    MOV P0, A
    SJMP DISPLAY_DONE

SHOW_COUNTDOWN:
    ; 定时运行状态 - 显示倒计时
    MOV A, TIMER_COUNT
    JZ SHOW_TIMER_END
    MOV DPTR, #DIGIT_TABLE
    MOVC A, @A+DPTR
    MOV P0, A
    SJMP DISPLAY_DONE
    
SHOW_TIMER_END:
    ; 定时结束状态 - 显示"0"
    MOV P0, #0C0H

DISPLAY_DONE:
    ; 节能模式处理（放在主循环最后）
    MOV A, POWER_SAVE
    JZ MAIN_LOOP_RESTART ; 非节能模式继续
    
    MOV A, OPER_TIMER
    CJNE A, #200, MAIN_LOOP_RESTART ; 200 * 50ms=10秒
    
    ; 节能模式下10秒无操作，关闭电机
    MOV P2, #00H
    MOV STEP_PTR, #0
    MOV CURRENT_MODE, #MODE_STOP
    MOV POWER_SAVE, #0 ; 可选：关闭节能模式
    
MAIN_LOOP_RESTART:
    LJMP MAIN_LOOP

; 步进电机驱动子程序
STEP_MOTOR:
    MOV DPTR, #STEP_TABLE
    MOV A, STEP_PTR
    MOVC A, @A+DPTR     ; 获取当前节拍
    MOV P2, A           ; 输出到电机
    INC STEP_PTR        ; 指向下一节拍
    MOV A, STEP_PTR
    CJNE A, #4, STEP_END
    MOV STEP_PTR, #0    ; 循环节拍
STEP_END:
    RET

; 按键扫描子程序
KEY_SCAN:
    ; KEY1 - 模式切换 (P1.0)
    JB P1.0, KEY2
    LCALL DELAY_20MS    ; 消抖
    JB P1.0, KEY2
    JNB P1.0, $         ; 等待释放
    ; 切换模式
    MOV OPER_TIMER, #0  ; 重置操作计时
    MOV TIMER_STATE, #0 ; 取消任何定时操作
    INC CURRENT_MODE    ; 模式+1
    MOV A, CURRENT_MODE
    CJNE A, #4, MODE_SWITCH_DONE ; 0-3模式
    MOV CURRENT_MODE, #0 ; 循环
MODE_SWITCH_DONE:
    MOV DISPLAY_TIMER, #40 ; 2秒模式显示
    RET

KEY2:
    ; KEY2 - 增加档位/定时设置 (P1.1)
    JB P1.1, KEY3
    LCALL DELAY_20MS
    JB P1.1, KEY3
    JNB P1.1, $
    MOV OPER_TIMER, #0  ; 重置操作计时
    
    MOV A, TIMER_STATE
    JNZ KEY2_TIMER_MODE ; 定时状态下处理定时设置
    
    ; 正常模式 - 仅在恒速模式下增加档位
    MOV A, CURRENT_MODE
    CJNE A, #MODE_CONSTANT, KEY2_END
    ; 恒速模式 - 增加档位
    INC CURRENT_GEAR
    MOV A, CURRENT_GEAR
    CJNE A, #4, KEY2_END ; 1-3档
    MOV CURRENT_GEAR, #1 ; 循环
KEY2_END:
    RET

KEY2_TIMER_MODE:
    ; 定时设置状态下增加定时时间
    MOV A, TIMER_COUNT
    INC A
    CJNE A, #10, SET_TIMER_VAL ; 1-9秒
    MOV A, #0           ; 到9后回到0
SET_TIMER_VAL:
    MOV TIMER_COUNT, A
    RET

KEY3:
    ; KEY3 - 定时功能 (P1.2)
    JB P1.2, KEY4
    LCALL DELAY_20MS
    JB P1.2, KEY4
    JNB P1.2, $
    MOV OPER_TIMER, #0  ; 重置操作计时
    
    ; 仅在非停止模式有效
    MOV A, CURRENT_MODE
    JZ KEY4             ; 停止模式无效
    
    ; 进入定时设置状态
    MOV TIMER_STATE, #1 ; 设置状态
    MOV TIMER_COUNT, #0 ; 初始化定时值
    RET

KEY4:
    ; KEY4 - 启动定时 (P1.3)
    JB P1.3, KEY5
    LCALL DELAY_20MS
    JB P1.3, KEY5
    JNB P1.3, $
    MOV OPER_TIMER, #0  ; 重置操作计时
    
    ; 仅在定时设置状态有效
    MOV A, TIMER_STATE
    CJNE A, #1, KEY5    ; 非设置状态无效
    
    ; 检查设置值是否有效 (1-9秒)
    MOV A, TIMER_COUNT
    JZ KEY5             ; 0秒无效
    
    ; 启动定时
    MOV TIMER_STATE, #2 ; 运行状态
    MOV INC_TIMER, #0   ; 清零定时计数
    RET

KEY5:
    ; KEY5 - 节能开关 (P1.4)
    JB P1.4, KEY_END
    LCALL DELAY_20MS
    JB P1.4, KEY_END
    JNB P1.4, $
    MOV OPER_TIMER, #0  ; 重置操作计时
    
    ; 切换节能模式
    MOV A, POWER_SAVE
    CPL A
    MOV POWER_SAVE, A
    JZ KEY_END          ; 关闭节能模式
    
    ; 开启节能模式 - 显示"E"2秒
    MOV P0, #86H        ; 显示"E"
    MOV DISPLAY_TIMER, #40 ; 2秒显示
    RET

KEY_END:
    RET

; 定时器0中断服务程序
TIMER0_ISR:
    CLR TR0
    MOV TH0, #3CH       ; 重装50ms初值
    MOV TL0, #0B0H
    SETB TR0
    
    ; 模式显示计时
    MOV A, DISPLAY_TIMER
    JZ CHECK_TIMER
    DEC DISPLAY_TIMER
    
CHECK_TIMER:
    ; 定时倒计时处理
    MOV A, TIMER_STATE
    CJNE A, #2, CHECK_INCREMENT_MODE ; 非运行状态跳过
    
    ; 每秒减少定时时间
    INC INC_TIMER
    MOV A, INC_TIMER
    CJNE A, #20, CHECK_INCREMENT_MODE ; 20 * 50ms=1秒
    MOV INC_TIMER, #0
    DEC TIMER_COUNT     ; 倒计时减1
    MOV A, TIMER_COUNT
    JNZ CHECK_INCREMENT_MODE
    ; 定时结束 - 跳回主循环处理
    RETI

CHECK_INCREMENT_MODE:
    ; 风速递增模式计时
    MOV A, CURRENT_MODE
    CJNE A, #MODE_INCREMENT, CHECK_OPER_TIME
    ; 每2秒切换档位
    INC INC_TIMER
    MOV A, INC_TIMER
    CJNE A, #40, CHECK_OPER_TIME ; 40 * 50ms=2秒
    MOV INC_TIMER, #0
    ; 切换档位
    INC CURRENT_GEAR
    MOV A, CURRENT_GEAR
    CJNE A, #4, CHECK_OPER_TIME
    MOV CURRENT_GEAR, #1 ; 1-3档循环

CHECK_OPER_TIME:
    ; 操作计时（节能用）
    MOV A, OPER_TIMER
    CJNE A, #200, NOT_OP_TIMEOUT
    MOV OPER_TIMER, #199  ; 重置为199（避免溢出）
    RETI
    
NOT_OP_TIMEOUT:
    INC OPER_TIMER
    RETI

; 设置延时参数
SET_DELAY:
    MOV A, CURRENT_GEAR
    ; 根据档位设置延时
    CJNE A, #1, DELAY_GEAR2
    MOV R6, #30         ; 1档延时参数
    MOV R7, #200
    RET
DELAY_GEAR2:
    CJNE A, #2, DELAY_GEAR3
    MOV R6, #20         ; 2档延时参数
    MOV R7, #150
    RET
DELAY_GEAR3:
    MOV R6, #10         ; 3档延时参数
    MOV R7, #100
    RET

; 随机数生成（用于自然风模式）
GEN_RANDOM:
    MOV A, RAND_SEED
    ADD A, #17          ; 伪随机算法
    MOV RAND_SEED, A
    ANL A, #0FH         ; 取低4位（0-15）
    ADD A, #5           ; 偏移量（5-20）
    MOV R6, A           ; 作为延时参数
    MOV R7, #150
    RET

; 延时子程序（参数在R6,R7）
DELAY:
    MOV R5, #10
DELAY_LOOP:
    MOV A, R6
    MOV R3, A
DELAY_INNER:
    MOV A, R7
    MOV R4, A
DELAY_INNER2:
    DJNZ R4, DELAY_INNER2
    DJNZ R3, DELAY_INNER
    DJNZ R5, DELAY_LOOP
    RET

; 20ms消抖延时
DELAY_20MS:
    MOV R7, #40
DL1:
    MOV R6, #250
DL2:
    DJNZ R6, DL2
    DJNZ R7, DL1
    RET

; 步进电机节拍表（双相四拍）
STEP_TABLE:
    DB 05H   ; A+B+ (0000 0101)
    DB 09H   ; A+B- (0000 1001)
    DB 0AH   ; A-B- (0000 1010)
    DB 06H   ; A-B+ (0000 0110)

; 模式显示表（共阳极）
MODE_TABLE:
    DB 0C0H  ; 0: 停止模式 (实际显示0,但在主循环中处理)
    DB 88H   ; 1: 恒速模式 "A"
    DB 83H   ; 2: 风速递增模式 "B"
    DB 0C6H  ; 3: 自然风模式 "C"

; 数字显示表（共阳极）
DIGIT_TABLE:
    DB 0C0H  ; 0
    DB 0F9H  ; 1
    DB 0A4H  ; 2
    DB 0B0H  ; 3
    DB 99H   ; 4
    DB 92H   ; 5
    DB 82H   ; 6
    DB 0F8H  ; 7
    DB 80H   ; 8
    DB 90H   ; 9

END