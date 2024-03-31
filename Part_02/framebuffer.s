.section .text
.global _start

# Макросы
.macro push reg
        sw      \reg, 0(sp)
        addi    sp, sp, 4
.endm

.macro pop reg
        addi    sp, sp, -4
        lw      \reg, 0(sp)
.endm

FRAMEBUFFER = 0x50000000    # Адрес кадрового буфера
VGA_MMIO    = 0x40000000    # Базовый адрес портов VGA адаптера
PCI_ADDR    = 0x30000000    # Адрес PCI
CONSOLE     = 0x10000000    # Адрес порта консоли
QEMU_VGA_ID = 0x11111234    # Vendor ID и Device ID для QEMU VGA адаптера

# VGA Mode X - 320*240@256 (8bpp)
SCREEN_X    = 320           # Ширина экрана
SCREEN_Y    = 240           # Высота экрана

COORD_X = (SCREEN_X - (message_end - message) * 8) / 2
COORD_Y = (SCREEN_Y - 8) / 2

_start:
        la      sp, stacks

        call    fb_setup

        la      t1, message
        call    print_console

        call    draw_strips

        la      t0, COORD_X + COORD_Y * SCREEN_X       # Сдвиг от начала фреймбуфера
        la      t2, message
        call    print_string

dead_loop:
        j       dead_loop

# Вывод строки символов в консоль
# t1 - адрес выводимого сообщения
print_console:
        push    ra
        li      t0, CONSOLE 	    # Загружаем адрес порта консоли
print_console_01:
        lb      t2, (t1)		    # Загружаем символ из сообщения
        beq     t2, zero, print_console_02	# Выходим из цикла, если текущий символ является маркером конца сообщения
        sb      t2, (t0)		    # Выводим символ в консоль
        addi    t1, t1, 1		    # Переходим на следующий символ
        j       print_console_01	# Переходим к следующему символу
print_console_02:
        pop     ra
        ret

# Заполняем экран вертикальными полосами
draw_strips:
        push    ra
        la      t0, FRAMEBUFFER

        li      t1, 0x00020406
        li      t3, 0x01030507

        li      t2, SCREEN_X / 8 * SCREEN_Y
draw_strips_01:
        sw      t1, 0x0(t0)
        addi    t0, t0, 4

        sw      t3, 0x0(t0)
        addi    t0, t0, 4

        addi    t2, t2, -1
        bne     t2, zero, draw_strips_01
        pop     ra
        ret

# Печать строки символов
# t2 - адрес сообщения
# t0 - адрес во frame buffer
print_string:
        push    ra
print_string_01:
        lb      t1, 0(t2)
        beq     t1, zero, print_string_02
        push    t0
        push    t2
        call    print_symbol
        pop     t2
        pop     t0
        addi    t0, t0, 8
        addi    t2, t2, 1
        j       print_string_01
print_string_02:
        pop     ra
        ret

# Печать отдельного символа
# t1 - код символа
# t0 - адрес во frame buffer
print_symbol:
        push    ra
        # Адрес символа в знакогенераторе
        slli    t1, t1, 3               # Код символа умножаем на 8
        la      t2, font - 32 * 8
        add     t1, t1, t2              # Получаем адрес символа в шрифте

        # Адрес во фреймбуфере
        la      t2, FRAMEBUFFER
        add     t0, t0, t2              # Получаем адрес, на котором начнём рисование символа

        li      t6, 8                   # Количество строк в символе
print_symbol_01:
        lb      t2, 0(t1)               # Загружаем очередной байт символа шрифта

        # Выводим один байт на экран
        addi    t0, t0, 7               # Перемещаемся на 7 пикселей вправо

        li      t5, 8                   # Количество пикселей в байте
print_symbol_02:
        mv      t3, t2
        and     t3, t3, 1               # Проверяем установлен ли бит в байте
        li      t4, 0x0A                # Цвет фона
        beq     t3, zero, print_symbol_03
        li      t4, 0x0E                # Цвет пикселей
print_symbol_03:
        sb      t4, (t0)                # Выводим пиксель на экран
        addi    t0, t0, -1              # Отступаем на один пиксель влево
        srli    t2, t2, 1               # Следующий пиксель в байте

        addi    t5, t5, -1              # Уменьшаем счётчик пикселей в байте
        bne     t5, zero, print_symbol_02

        addi    t0, t0, SCREEN_X + 1    # Следующая строка на экране
        addi    t1, t1, 1               # Следующая строка символа
        addi    t6, t6, -1              # Уменьшаем счётчик строк символа
        bne     t6, zero, print_symbol_01

        pop     ra
        ret

# Настройка frame buffer VGA адаптера
fb_setup:
        push    ra

        # Поиск секции нужного устройства в дереве PCI
        li      t4, PCI_ADDR
        mv      t3, zero                # Инициализируем счётчик нулём

fb_setup_01:
        add     t0, t4, t3
        lw      t5, 0(t0)               # Загружаем 4 байта заголовка PCI (Device ID + Vendor ID)

        li      t1, QEMU_VGA_ID
        beq     t5, t1, fb_setup_03     # Переход на инициализацию, если заголовок равен QEMU_VGA_ID

        li      t1, 4096                # Следующая секция PCI дерева
        add     t3, t3, t1              # Добавляем к счётчику 4096 байт
        li      t1, 0x10000000          # Максимальная длина всей секции PCI (4096 * 65536)
        beq     t3, t1, fb_setup_07     # Если счётчик достиг предела, уходим
        j       fb_setup_01             # Переходим на следующую итерацию цикла
fb_setup_03:

        # Нашли нужную секцию и узнали её адрес
        # В t0 - адрес секции QEMU_VGA_ID в дереве PCI устройств
        # Enable memory accesses for this device (обязательная процедура)
        lw      t1, 0x04(t0)
        ori     t1, t1, 0x02
        sw      t1, 0x04(t0)            # Устанавливаем бит 1

        la      t2, FRAMEBUFFER
        sw      t2, 0x10(t0)            # Заносим адрес frame buffer

        la      t2, VGA_MMIO
        sw      t2, 0x18(t0)            # Заносим адрес VGA MMIO

        # Enable LFB, enable 8-bit DAC (без этого тёмные цвета становятся ещё темнее)
        li      t1, 0x60
        sh      t1, 0x508(t2)           # Отправляем 0x60 в порт VGA_MMIO + 0x508

        # Инициализируем регистры VGA в режим Mode X (320x240 8bpp)
        la      t0, vga_registers
        addi    t1, t2, 0x400 - 0xC0    # VGA_MMIO + 0x400 - 0xC0
fb_setup_04:
		lbu     t3, 0(t0)               # Первый байт тройки (сдвиг для адреса VGA_MMIO)
		beq     t3, zero, fb_setup_05   # Завершаем, если конец данных
		add     t4, t1, t3              # VGA_MMIO + 0x400 - 0xC0 + первый байт тройки
		lb      t5, 1(t0)               # Второй байт тройки (данные для порта)
        sb      t5, 0(t4)               # Отправляем в порт второй байт тройки
		lbu     t5, 2(t0)               # Третий байт тройки (данные для порта)
        sb      t5, 1(t4)               # Отправляем в порт третий байт тройки
		addi    t0, t0, 3               # Переход к следующей тройке массива данных
        j       fb_setup_04

        # Загрузка палитры
fb_setup_05:
        sb      zero, 0x408(t2)         # Отправляем номер первого цвета палитры в порт
        li      t0, 16 * 3              # Счётчик: количество цветов * 3 байта
        la      t1, palette
fb_setup_06:
        lb      t3, 0(t1)               # Загружаем байт палитры
        sb      t3, 0x409(t2)           # Отправляем байт палитры в порт
        addi    t1, t1, 1               # Следующий байт палитры
        addi    t0, t0, -1              # Декремент счётчика
        bne     t0, zero, fb_setup_06   # Идём на следующую итерацию цикла

fb_setup_07:
        pop     ra
        ret

vga_registers:
        # Miscellaneous Output Register:
        # Just a single port.
        # But bit 0 determines whether we use 3Dx or 3Bx.
        # So we need to set this early.
        .byte   0xC2, 0xFF, 0xE3    # Mode 13h - 0x63

        # Sequencer:
        # Disable reset here.
        .byte   0xC4, 0x00, 0x00

        # Attributes:
        # - Read 3DA to reset flip-flop
        # - Write 3C0 for address
        # - Write 3C0 for data
        .byte   0xC0, 0x00, 0x00
        .byte   0xC0, 0x01, 0x02
        .byte   0xC0, 0x02, 0x08
        .byte   0xC0, 0x03, 0x0A
        .byte   0xC0, 0x04, 0x20
        .byte   0xC0, 0x05, 0x22
        .byte   0xC0, 0x06, 0x28
        .byte   0xC0, 0x07, 0x2A
        .byte   0xC0, 0x08, 0x15
        .byte   0xC0, 0x09, 0x17
        .byte   0xC0, 0x0A, 0x1D
        .byte   0xC0, 0x0B, 0x1F
        .byte   0xC0, 0x0C, 0x35
        .byte   0xC0, 0x0D, 0x37
        .byte   0xC0, 0x0E, 0x3D
        .byte   0xC0, 0x0F, 0x3F

        .byte   0xC0, 0x30, 0x41
        .byte   0xC0, 0x31, 0x00
        .byte   0xC0, 0x32, 0x0F
        .byte   0xC0, 0x33, 0x00
        .byte   0xC0, 0x34, 0x00

        # Graphics Mode
        .byte   0xCE, 0x00, 0x00
        .byte   0xCE, 0x01, 0x00
        .byte   0xCE, 0x02, 0x00
        .byte   0xCE, 0x03, 0x00
        .byte   0xCE, 0x04, 0x00
        .byte   0xCE, 0x05, 0x40
        .byte   0xCE, 0x06, 0x05
        .byte   0xCE, 0x07, 0x00
        .byte   0xCE, 0x08, 0xFF

        # CRTC
        .byte   0xD4, 0x11, 0x0E    # Do this to unprotect the registers

        .byte   0xD4, 0x00, 0x5F
        .byte   0xD4, 0x01, 0x4F
        .byte   0xD4, 0x02, 0x50
        .byte   0xD4, 0x03, 0x82
        .byte   0xD4, 0x04, 0x54
        .byte   0xD4, 0x05, 0x80
        .byte   0xD4, 0x06, 0x0D    # Mode 13h - 0xBF
        .byte   0xD4, 0x07, 0x3E    # Mode 13h - 0x1F
        .byte   0xD4, 0x08, 0x00
        .byte   0xD4, 0x09, 0x41
        .byte   0xD4, 0x0A, 0x20
        .byte   0xD4, 0x0B, 0x1F
        .byte   0xD4, 0x0C, 0x00
        .byte   0xD4, 0x0D, 0x00
        .byte   0xD4, 0x0E, 0xFF
        .byte   0xD4, 0x0F, 0xFF
        .byte   0xD4, 0x10, 0xEA    # Mode 13h - 0x9C
        .byte   0xD4, 0x11, 0xAC    # Mode 13h - 0x8E  Registers are now reprotected
        .byte   0xD4, 0x12, 0xDF    # Mode 13h - 0x8F
        .byte   0xD4, 0x13, 0x28
        .byte   0xD4, 0x14, 0x00    # Mode 13h - 0x40
        .byte   0xD4, 0x15, 0xE7    # Mode 13h - 0x96
        .byte   0xD4, 0x16, 0x06    # Mode 13h - 0xB9
        .byte   0xD4, 0x17, 0xE3    # Mode 13h - 0xA3

        # Sequencer
        .byte   0xC4, 0x01, 0x01
        .byte   0xC4, 0x02, 0x0F
        .byte   0xC4, 0x03, 0x00
        .byte   0xC4, 0x04, 0x06    # Mode 13h - 0x0E

        .byte   0x00                # Маркер конца массива

palette:
        #        R     G     B
        .byte   0x00, 0x00, 0x00    # 00 Black
        .byte   0x00, 0x00, 0xD8    # 01 Blue
        .byte   0xD8, 0x00, 0x00    # 02 Red
        .byte   0xD8, 0x00, 0xD8    # 03 Magenta
        .byte   0x00, 0xD8, 0x00    # 04 Green
        .byte   0x00, 0xD8, 0xD8    # 05 Cyan
        .byte   0xD8, 0xD8, 0x00    # 06 Yellow
        .byte   0xD8, 0xD8, 0xD8    # 07 White

        .byte   0x00, 0x00, 0x00    # 08 Black Bright On
        .byte   0x00, 0x00, 0xFF    # 09 Blue Bright On
        .byte   0xFF, 0x00, 0x00    # 0A Red Bright On
        .byte   0xFF, 0x00, 0xFF    # 0B Magenta Bright On
        .byte   0x00, 0xFF, 0x00    # 0C Green Bright On
        .byte   0x00, 0xFF, 0xFF    # 0D Cyan Bright On
        .byte   0xFF, 0xFF, 0x00    # 0E Yellow Bright On
        .byte   0xFF, 0xFF, 0xFF    # 0F White Bright On

message:
        .asciz "Hello, World!"
        # .byte   0x00            # Маркер конца сообщения
message_end:

font:
        .incbin "zxfont.bin"

# Начало стека
stacks:
	# .skip 1024,0
