;
; Basic OS X calls to GLUT and OpenGL
;
; Example by Waitsnake
;
; compile with:
; nasm -g -f macho32 bspGLUT.asm
; xcrun gcc -framework GLUT -framework OpenGL -m32 -o bspGLUT.out bspGLUT.o
;

%include "gl.inc"
%include "glut.inc"
 
; static data
segment .data
 
window_name: db "OpenGL on OSX with nasm", 10, 0
fl_one: dd 1.0
fl_neg_one: dd -1.0
fl_zero: dd 0.0
fl_half: dd 0.5
fl_neg_half: dd -0.5
 
; code
segment .text
 
global _main

; the main function that init OpenGL and install the gl draw function (_display_func)
_main:
        ;alignment = 0

        lea  ecx, [esp+4]            ;load adress of argc in stack to ecx
        lea  edx, [esp+8]            ;load adress of argv in stack to edx

        push ebp ; setup the frame   ;alignment => 4
        mov  ebp, esp

        push edx                     ;alignment => 8
        push ecx                     ;alignment => 12
        call _glutInit               ;alignment => 16 -> alignment <= 12 (after backjump with "ret")
        add  esp, 8                  ;alignment <= 4 (caller has to clean call paras (8 byte))


        sub esp, 4                   ;alignment => 8 (correction need to get to 16 at next call !)
        mov eax, GLUT_RGB
        or  eax, GLUT_SINGLE
        push eax                     ;alignment => 12
        call _glutInitDisplayMode    ;alignment => 16 -> alignment <= 12
        add  esp, 4                  ;alignment <= 8 (caller has to clean call paras (4 byte))
        add  esp, 4                  ;alignment <= 4 (clean last the allignment correction)


        push dword 80                ;alignment => 8
        push dword 80                ;alignment => 12
        call _glutInitWindowPosition ;alignment => 16 -> alignment <= 12
        add  esp, 8                  ;alignment <= 4 (caller has to clean call paras (8 byte))


        push dword 300               ;alignment => 8
        push dword 400               ;alignment => 12
        call _glutInitWindowSize     ;alignment => 16 -> alignment <= 12
        add  esp, 8                  ;alignment <= 4 (caller has to clean call paras (8 byte))


        sub esp, 4                   ;alignment => 8 (correction need to get to 16 at next call !)
        mov  eax, dword window_name
        push eax                     ;alignment => 12
        call _glutCreateWindow       ;alignment => 16 -> alignment <= 12
        add  esp, 4                  ;alignment <= 8 (caller has to clean call paras (4 byte))
        add  esp, 4                  ;alignment <= 4 (clean last the allignment correction)


        sub esp, 4                   ;alignment => 8 (correction need to get to 16 at next call !)
        push dword _display_func     ;alignment => 12
        call _glutDisplayFunc        ;alignment => 16 -> alignment <= 12
        add  esp, 4                  ;alignment <= 8 (caller has to clean call paras (4 byte))
        add  esp, 4                  ;alignment <= 4 (clean last the allignment correction)


        sub esp, 8                   ;alignment => 12 (correction need to get to 16 at next call !)
        call _glutMainLoop           ;alignment => 16 -> alignment <= 12
        add  esp, 8                  ;alignment <= 4 (caller has to clean call paras (8 byte))

_pass_exit:
        pop  ebp                     ;alignment <= 0
        ret
         

; the gl draw function (here is the content of OpenGL
_display_func:
        pusha
        sub     esp,8
        push    dword GL_COLOR_BUFFER_BIT
        call    _glClear
        add     esp,12

        sub     esp,8
        push    dword GL_POLYGON
        call    _glBegin
        add     esp,12

        push    dword 0
        push    dword 0
        push    dword [fl_one]
        call    _glColor3f
        add     esp,12

        push    dword 0
        push    dword [fl_neg_half]
        push    dword [fl_neg_half]
        call    _glVertex3f
        add     esp,12

        push    dword 0
        push    dword [fl_one]
        push    dword 0
        call    _glColor3f
        add     esp,12

        push    dword 0
        push    dword [fl_neg_half]
        push    dword [fl_half]
        call    _glVertex3f
        add     esp,12

        push    dword [fl_one]
        push    dword 0
        push    dword 0
        call    _glColor3f
        add     esp,12

        push    dword 0
        push    dword [fl_half]
        push    dword 0
        call    _glVertex3f
        add     esp,12

        sub     esp,12
        call    _glEnd
        add     esp,12

        sub     esp,12
        call    _glFlush
        add     esp,12

        popa
        ret
