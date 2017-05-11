;
; Basic OS X calls to GLUT and OpenGL
;
; Example by Waitsnake
;
; compile with:
; nasm -g -f macho32 bspGLframBuff.asm
; xcrun gcc -framework GLUT -framework OpenGL -m32 -o bspGLframBuff.out bspGLframBuff.o
;

;inclut GLUT/OpenGL stuff
%include "gl.inc"
%include "glut.inc"

;glibc stuff
extern _clock, _malloc, _free, _usleep, _system

;different ways to use OpenGL (all should work)
;%define USE_TIMER_UPDATE 1
;%define USE_DEPTH_BUFFER 1
%define USE_DOUBLE_BUFFER 1
%define USE_VSYNC 1


; inside com.apple.glut.plist
; set GLUTSyncToVBLKey to true for vsync active in GLUT/OpenGL
;
; at terminal:
; defaults read com.apple.glut GLUTSyncToVBLKey
; defaults write com.apple.glut GLUTSyncToVBLKey 1

; frame buffer data
%define width         800
%define high          600
%define colordeep       4


; static data
segment .data

; enable/disable vertical retrace sync inside com.apple.glut.plist
; set GLUTSyncToVBLKey to true for vsync active in GLUT/OpenGL
;
; at terminal:
; defaults read com.apple.glut GLUTSyncToVBLKey
; defaults write com.apple.glut GLUTSyncToVBLKey 1
enable_glut_vsync_command: db "defaults write com.apple.glut GLUTSyncToVBLKey 1", 10, 0
disable_glut_vsync_command: db "defaults write com.apple.glut GLUTSyncToVBLKey 0", 10, 0

window_name: db "OpenGL frame buffer example", 10, 0
window_handle: dd 0
fl_one: dd 1.0
fl_neg_one: dd -1.0
fl_zero: dd 0.0
fl_half: dd 0.5
fl_neg_half: dd -0.5

; variables for random
seed1:   dd  0
seed2:   dd  0

; variables for argc/argv
argc:           dd  0
argv:           dd  0

; for pointer to frame buffer
fbuff:   dd  0

; code
segment .text
 
global _main

; the main function that init OpenGL and install the gl draw function (_display_func)
_main:
        lea     ecx, [esp+4]            ;load adress of argc in stack to ecx
        lea     edx, [esp+8]            ;load adress of argv in stack to edx

        push    ebp ; setup the frame 
        mov     ebp, esp

        sub     esp,24      ;add to get rid of 16-bit-alignment-problem (not 28 as normal since we allready push ebp)

%ifdef USE_VSYNC
        mov     [argv],edx
        mov     [argc],ecx
        ;force enable vsync support of GLUT in OSX
        mov     [esp],dword enable_glut_vsync_command
        call    _system
        mov     edx,[argv]
        mov     ecx,[argc]              ;ecx=argc is not longer saved by _system and this will cause problems in _glutInit and so we need to save and restore it now
%endif        

        ;init OpenGL with GLUT
        mov     [esp+4],edx             ;**argv        
        mov     [esp],ecx               ;&argc      
        call    _glutInit               

        ;Init Random numbers
        call    _randomize

        ;get memory for the gl-frame-buffer
        mov     eax,width*high*colordeep
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [fbuff],eax
         
        ;init display mode for OpenGL window
        mov     eax, GLUT_RGB
%ifdef USE_DOUBLE_BUFFER        
        or      eax, GLUT_DOUBLE 
%else
        or      eax, GLUT_SINGLE 
%endif
%ifdef USE_DEPTH_BUFFER
        or      eax, GLUT_DEPTH
%endif        
        mov     [esp], eax
        call    _glutInitDisplayMode    

        ;define posion of OpenGL window
        mov     [esp+4],dword 80                
        mov     [esp],dword 80                
        call    _glutInitWindowPosition 

        ;define OpenGL window size
        mov     [esp+4], dword high            
        mov     [esp], dword width           
        call    _glutInitWindowSize    

        ;create OpenGL window
        mov     eax, dword window_name
        mov     [esp], eax
        call    _glutCreateWindow  
        mov     dword [window_handle],eax

%ifdef USE_DEPTH_BUFFER
        ;enable depth buffer
        mov     [esp],dword GL_DEPTH_TEST
        call    _glEnable
%endif        

        ;add own draw function as call back
        mov     [esp], dword _display_func
        call    _glutDisplayFunc  

%ifdef USE_TIMER_UPDATE
        ;add call back that triggers draw update(timer based)
        mov     [esp+8], dword 0
        mov     [esp+4], dword _timer_func
        mov     [esp], dword 1
        call    _glutTimerFunc

%else
        ;add call back that triggers draw update(idle based)
        mov     [esp], dword _idle_func
        call    _glutIdleFunc
%endif

%ifdef USE_VSYNC
        ; disable glut vsync before main loop, since this loop will never terminate normaly
        ; it works if it was enabled while init of glut/OpenGL ;-)
        mov     [esp],dword disable_glut_vsync_command 
        call    _system
%endif

        ;start OpenGL main loop
        call    _glutMainLoop 

        ; free the malloc'd memory
        mov     eax, dword [fbuff]
        mov     [esp], eax
        call    _free

_pass_exit:
        add     esp,24
        pop     ebp         
        ret
         
_fail_exit:
%ifdef USE_VSYNC
        ;disable glut vsync in case we had an error
        mov     [esp],dword disable_glut_vsync_command 
        call    _system
%endif

        mov     eax, 1
        add     esp,24
        pop     ebp
        ret

;##############################################################################

; GL timer function to give GL draw function the command for redraw and also restart the timer
_timer_func:
        sub     esp,28

        ;select OpenGL window
        mov     eax, [window_handle]
        mov     [esp],eax 
        call    _glutSetWindow

        ;start redraw of OpenGL
        call    _glutPostRedisplay

        ;restart timer
        mov     [esp+8], dword 0
        mov     [esp+4], dword  _timer_func
        mov     [esp], dword 40 ;the timer
        call    _glutTimerFunc

        add     esp,28
        ret 

;##############################################################################

; GL idle function to give GL draw function the command for redraw
_idle_func:
        sub     esp,28

        ;just wait a few micro secs
        mov     [esp], dword 10
        call    _usleep

        ;select OpenGL window
        mov     eax,[window_handle]
        mov     [esp],eax 
        call    _glutSetWindow

        ;start redraw of OpenGL
        call    _glutPostRedisplay

        add     esp,28
        ret

;##############################################################################

; the gl draw function (here is the content of OpenGL
_display_func:
        pusha
        sub     esp,28 ;add to get rid of 16-bit-alignment-problem

        ;fill frame buffer with some content
        call    _draw_to_frame_buff

        ;defiene color for clear screen 
        mov     eax, dword [fl_one]
        mov     [esp+12],eax
        mov     eax, dword [fl_zero]
        mov     [esp+8],eax
        mov     [esp+4],eax
        mov     [esp],eax
        call    _glClearColor

        ;clear screen 
        mov     eax, dword GL_COLOR_BUFFER_BIT
%ifdef USE_DEPTH_BUFFER
        or      eax, dword GL_DEPTH_BUFFER_BIT
%endif        
        mov     [esp],eax 
        call    _glClear

        ;set position were _glDrawPixels will start
        mov     eax,dword [fl_neg_one]
        mov     [esp+4],eax
        mov     [esp],eax
        call    _glRasterPos2f
 
        ;draw frame buffer to screen
        mov     eax, dword [fbuff]
        mov     [esp+16],eax
        mov     [esp+12],dword GL_UNSIGNED_BYTE 
        mov     [esp+8],dword GL_RGBA
        mov     [esp+4],dword high
        mov     [esp],dword width
        call    _glDrawPixels

%ifdef USE_DOUBLE_BUFFER        
        ;do all actions and than change the buffer
        call    _glutSwapBuffers
%else
        ;so all actions in single buffer mode
        call    _glFlush
%endif

        add     esp,28
        popa
        ret

;##############################################################################

;here draw own content to frame buffer
_draw_to_frame_buff:
        sub     esp,28 ;add to get rid of 16-bit-alignment-problem

        ;get a random number
        mov     [esp],dword 0xFFFFFFFF
        call    _random ;eax has radom number

        ;fill complete frame buffer with a random color
        mov     edi,[fbuff]
        mov     ecx,width*high
        rep     stosd

        add     esp,28
        ret


;##############################################################################

;Init the random number seeds with system time
_randomize:
        ;parameter:
        ;none

        ;return value:
        ;none

        push	eax
        push    edx
        xor	    eax,eax
        sub     esp,4
        call    _clock  ;nach eax
        add     esp,4
        mov     [seed1],eax
        mov     edx,eax
        sub     esp,4
        call    _clock  ;nach eax
        add     esp,4
        xor     eax,edx
        mul     edx ;eax * edx nach edx:eax
        mov     [seed2],eax
        pop	    edx
        pop	    eax
        ret

;##############################################################################

;create a new random number
_random:
        ;parameter:
        ;EAX = w, range of random number: 0 - (w-1)

        ;return value:
        ;EAX = new random number

        push    ebx
        push    edx
        mov     ebx,eax
        mov     eax,[seed1]
        mov     edx,[seed2]
        mov     [seed2],eax
        add     eax,edx
        shld    eax,edx,9
        mov     [seed1],eax       
        xor     edx,edx
        div     ebx
        mov     eax,edx
        pop     edx
        pop     ebx
        ret


