;
; Basic OS X calls to GLUT and OpenGL
;
; Example by Waitsnake
;
; compile with:
; nasm -g -f macho32 GLonFire.asm
; xcrun gcc -framework GLUT -framework OpenGL -m32 -o GLonFire.out GLonFire.o
;

;inclut GLUT/OpenGL stuff
%include "gl.inc"
%include "glut.inc"

;glibc stuff
extern _clock, _malloc, _free, _usleep, _system, _exit

;different ways to use OpenGL (all should work)
;%define USE_TIMER_UPDATE 1
;%define USE_DEPTH_BUFFER 1
;%define USE_DOUBLE_BUFFER 1
%define USE_VSYNC 1


; inside com.apple.glut.plist
; set GLUTSyncToVBLKey to true for vsync active in GLUT/OpenGL
;
; at terminal:
; defaults read com.apple.glut GLUTSyncToVBLKey
; defaults write com.apple.glut GLUTSyncToVBLKey 1

; screen defines
%define width               320
%define height              200
%define colordeep           4

;simulation defines
%define firepoints          10
%define firemaxdiff         50
%define fireminlevel        205
%define coolingpoints       4
%define coolingmaxdiff      40
%define coolingminlevel     10
%define cool_while_up       2
%define USE_SMOOTH_COOLING  1


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

;other variables
window_name:    db "GL on fire", 10, 0
window_handle:  dd 0
screen_height:  dd 0
screen_width:   dd 0
fullscreen:     dd 0
fl_scale_full_screen: dd 1.0
fl_one:         dd 1.0
fl_neg_one:     dd -1.0
fl_zero:        dd 0.0
fl_half:        dd 0.5
fl_neg_half:    dd -0.5
int_to_fl:      dd 0

; variables for random
seed1:          dd  0
seed2:          dd  0

; variables for argc/argv
argc:           dd  0
argv:           dd  0

; variables for fire sim
y_pos:          dd 0
fire:           dd 0

; for pointer to frame buffer
fbuff:          dd  0

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

        ;get memory for the fire simulation
        mov     eax,width*height
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [fire],eax

        ;clear new mem
        xor     al,al
        mov     ecx,width*height
        mov     edi,[fire]
        rep     stosb
        
        ;get memory for the gl-frame-buffer
        mov     eax,width*height*colordeep
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [fbuff],eax
        
        ;clear new mem
        xor     eax,eax
        mov     ecx,width*height*colordeep
        mov     edi,[fbuff]
        rep     stosb
        
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
        mov     [esp+4],dword 0                
        mov     [esp],dword 0                
        call    _glutInitWindowPosition 

        ;define OpenGL window size
        mov     [esp+4], dword height
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

        ;add own keybord handler as call back
        mov     [esp], dword _keybord_func
        call    _glutKeyboardFunc

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

        ;get screen proporties
        mov     [esp], dword GLUT_SCREEN_WIDTH
        call    _glutGet
        mov     [screen_width],eax
        mov     [esp], dword GLUT_SCREEN_HEIGHT
        call    _glutGet
        mov     [screen_height],eax

        ;calulate zoom factor for fullscrren depending on screen width and window width
        finit                                   ;init coprocessor for floting points
        fild    dword [screen_width]            ;load integer to st1
        mov     [int_to_fl],dword width
        fild    dword [int_to_fl]               ;load integer to st0
        fdivp   st1                             ;st1/st0 -> st0
        fstp    dword [fl_scale_full_screen]    ;store div as flot

        ;start OpenGL main loop (will never return ?)
        call    _glutMainLoop 

        ; free the malloc'd memory
        mov     eax, dword [fire]
        mov     [esp], eax
        call    _free

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

; the gl keybord function
_keybord_func:
        mov     eax,[esp+4]       ;load keaystroke
        sub     esp,28 ;add to get rid of 16-bit-alignment-problem

        cmp     eax,27            ;check for ESC key
        jnz     _k1
        mov     [esp],dword 0
        call    _exit             ;exit of prog
        jmp     _ke
    
_k1:    cmp     eax,'f'           ;check for 'f' key
        jnz     _ke
        cmp     [fullscreen],dword 0
        jnz     _k2
        mov     [fullscreen],dword 1
        call    _glutFullScreen   ;enable Full Screen
        jmp     _ke
_k2:    mov     [fullscreen],dword 0
        mov     [esp+4],dword height
        mov     [esp],dword width
        call    _glutReshapeWindow ;disable Full Screen
_ke:    add     esp,28
        ret

;##############################################################################

; the gl draw function (here is the content of OpenGL drawn to screen)
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

        ;Zoom Frame Buffer if in Fullscreen
        cmp     [fullscreen], dword 1
        jnz     _d1
        mov     eax,dword [fl_scale_full_screen]
        mov     [esp+4],eax
        mov     [esp],eax
        call    _glPixelZoom
        jmp     _d2
_d1:        
        mov     eax,dword [fl_one]
        mov     [esp+4],eax
        mov     [esp],eax
        call    _glPixelZoom
_d2:        
 
        ;draw frame buffer to screen
        mov     eax, dword [fbuff]
        mov     [esp+16],eax
        mov     [esp+12],dword GL_UNSIGNED_BYTE 
        mov     [esp+8],dword GL_RGBA
        mov     [esp+4],dword height
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

        ;make random fire (heat points at lowest line)
        mov     eax,firepoints    
        call    _random
        mov     ecx,eax
        inc     ecx
heat:
        mov     eax,width-100   ;max right line of heading(plus max. left line)
        call    _random
        add     eax,50          ;max left line of heading
        mov     edi,[fire]
        add     edi,width*(height-1)
        add     edi,eax
        mov     eax,firemaxdiff
        call    _random
        add     eax,fireminlevel
        mov     [edi],al
        dec     ecx
        jnz     heat

        ;calculate expansion of fire plasma to top
        mov     eax,0       ;max height of calculation from top (above this line noc calculation of expansion) 0=no limit
        mov     [y_pos],eax
y_sch: 
        mov     ecx,40      ;max right line of calculation of expansion
        mov     eax,width
        mul     dword [y_pos]
        add     eax,ecx
        mov     edi,[fire]
        add     edi,eax
x_sch:  ;calculate the average heat of actual pixel and the 3 pixels on line beneath
        mov     esi,edi
        xor     ebx,ebx
        mov     bl,[esi]
        add     esi,width-1
        mov     eax,[esi]
        xor     edx,edx
        mov     dl,al
        add     ebx,edx
        mov     dl,ah
        add     ebx,edx
        shr     eax,16
        xor     ah,ah
        add     ebx,eax
        shr     ebx,2

%ifdef USE_SMOOTH_COOLING
        ;make an extra cooling of minus one from the new average heat pixel (but triggert by random)
        ;this need much calc power since it is used for each pixel !
        mov     eax,cool_while_up
        call    _random
        test    eax,eax
        jnz     ab1
        dec     ebx         ;extra cooling
ab1:    test    ebx,ebx
%else
        ;simple cooling (fire level not so high, but lower calc power)
        dec     ebx
%endif
            
        jns     ab0
        xor     ebx,ebx
ab0:
        mov     [edi],bl
        inc     edi
        inc     ecx
        cmp     ecx,width-40    ;mac left line of calculation of expansion 
        jnz     x_sch
        inc     dword [y_pos]
        cmp     dword [y_pos],height-1
        jnz     y_sch

        ;cool random points of lowest line
        mov     eax,coolingpoints
        call    _random
        mov     ecx,eax
        inc     ecx
cool:
        mov     eax,width-100
        call    _random
        add     eax,50
        mov     edi,[fire]
        add     edi,width*(height-1)
        add     edi,eax
        mov     eax,coolingmaxdiff
        call    _random
        add     eax,coolingminlevel
        mov     [edi],al
        dec     ecx
        jnz     cool

        ;change plasma fieled (1 byte per pixel) to RGB colors (of fire palete) and write to frame buffer
        mov     ecx,width*height
        mov     esi,[fire]
        mov     edi,[fbuff]
        add     edi,width*height*colordeep-4
transf:
        xor     eax,eax
        mov     al,[esi]
        inc     esi
        call    _toFireColor
        mov     [edi],eax
        sub     edi,4
        dec     ecx
        jnz     transf

        add     esp,28
        ret


;##############################################################################

;Init the random number seeds with system time
_randomize:
        ;parameter:
        ;none

        ;return value:
        ;none

        push    eax
        push    edx
        xor     eax,eax
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
        pop     edx
        pop     eax
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

;##############################################################################
; convert fire intensity (1 byte) to RGB fire palete 
_toFireColor:
        ;parameter:
        ;EAX = intensity, range : 0 - 255

        ;return value:
        ;EAX = RGB color of fire (0x00BBGGRR)
       
        push    ebx
        push    esi

        xor     esi,esi       ;clear the result holder

        mov     ebx,eax       ;save intensity also to ebx
        cmp     eax,85        ;min (eax,85)
        jl      _f1
        mov     eax,0xFF
        jmp     _f2
_f1:    shl     eax,1         ;multip "min" with 3
        add     eax,ebx

_f2:    mov     esi,eax       ;save "red" to esi

        sub     ebx,85        ;decrease intensity by 85 and save to ebx
        jle     _fexit        ;if it was allready below 85 job is still done

        mov     eax,ebx       ;save new intensity to eax
        cmp     eax,85        ;min (eax,85)
        jle     _f3
        mov     eax,0xFF
        jmp     _f4
_f3:    shl     eax,1         ;multip "min" with 3
        add     eax,ebx

_f4:    shl     eax,8         ;byte 2 will be "green" 
        or      esi,eax       ;save "green" to esi

        sub     ebx,85        ;decrease intensity by 85 and save to ebx
        jle     _fexit        ;if it was allready below 85 job is still done

        mov     eax,ebx       ;save new intensity to eax
        cmp     eax,85        ;min (eax,85)
        jle     _f5
        mov     eax,0xFF
        jmp     _f6
_f5:    shl     eax,1         ;multip "min" with 3
        add     eax,ebx

_f6:    shl     eax,16        ;byte 3 will be "blue"
        or      esi,eax       ;save "blue" to esi

_fexit: mov     eax,esi       ;mov result back to eax
        pop     esi
        pop     ebx
        ret

