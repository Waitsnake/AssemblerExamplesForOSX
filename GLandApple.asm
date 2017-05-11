;
; Basic OS X calls to GLUT and OpenGL
;
; Example by Waitsnake
;
; compile with:
; nasm -g -f macho32 GLandApple.asm
; xcrun gcc -framework GLUT -framework OpenGL -m32 -o GLandApple.out GLandApple.o
;

;inclut GLUT/OpenGL stuff
%include "gl.inc"
%include "glut.inc"

;glibc stuff
extern _clock, _malloc, _free, _usleep, _system, _exit

;different ways to use OpenGL (all should work)
%define USE_TIMER_UPDATE 1
;%define USE_DEPTH_BUFFER 1
;%define USE_DOUBLE_BUFFER 1
%define USE_VSYNC 1
;%define USE_FIRE_COLORS      1


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
%define it_tief	            10h			;Fraktalparameter
%define xrand		        0fffde667h
%define yrand		        0fffea800h
%define seite		        00002b000h
%define z_r_anf	            0fffd0000h		;Animationsparameter
%define z_r_end	            000048000h
%define anistep	            400h
%define increase_intensety  15

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
window_name:    db "GL and Apple", 10, 0
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

;simulation vars
z_r:		    dd z_r_anf
z_i:		    dd 0
r_i:		    dw 0
i_i:		    dw 0
a:		        dd 0
b:		        dd 0

; for pointer to gl frame buffer
fbuff:          dd  0

; for pointer to dos frame buffer
dbuff:          dd  0

; variables for argc/argv
argc:           dd  0
argv:           dd  0

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
        mov     ecx,width*height
        mov     edi,[fbuff]
        rep     stosd
        
        ;get memory for the dos-frame-buffer
        mov     eax,width*height
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [dbuff],eax
        
        ;clear new mem
        xor     eax,eax
        mov     ecx,width*height
        mov     edi,[dbuff]
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
        mov     eax, dword [fbuff]
        mov     [esp], eax
        call    _free

        ; free the malloc'd memory
        mov     eax, dword [dbuff]
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


        mov	    word [r_i],word -1
r_sch:
        cmp	    word [r_i],word width-1
        jz	    fine
        inc	    word [r_i]

        mov	    ax,word [r_i]
        shl	    eax,16
        mov     ebx,width * 10000h

        mov	    edx,eax
        shr	    edx,16
        shl	    eax,16
        div	    ebx

        mov	    ebx,seite
        imul	ebx
        mov	    ax,dx
        ror	    eax,16	

        add	    eax,xrand
        mov	    [a],eax

        mov	    word [i_i],word -1
i_sch:
        cmp	    word [i_i],word height-1
        jz	    r_sch
        inc	    word [i_i]

        mov	    ax,word [i_i]
        shl	    eax,16
        mov	    ebx,height * 10000h
        mov	    edx,eax
        shr	    edx,16
        div	    ebx

        mov	    ebx,seite
        imul	ebx
        mov	    ax,dx
        ror	    eax,16	

        add	    eax,yrand
        mov	    [b],eax

        mov	    esi,[z_r]		;x2 = 0
        mov	    edi,[z_i]		;y2 = 0
        xor	    ebp,ebp			;farbe = 0
        xor	    ecx,ecx			;x = 0
        xor	    edx,edx			;y = 0

do_sch:
        mov	    eax,ecx		;y=2*x*y+b
        imul	edx
        mov 	ax,dx
        ror	    eax,16	

        mov	    ebx,20000h	;”” Optimieren, 20000h=2^17

        imul	ebx
        mov	    ax,dx
        ror	    eax,16	

        add	    eax,[b]
        mov	    edx,eax

        mov	    eax,esi		;x=x2-y2+a
        sub	    eax,edi
        add	    eax,[a]
        mov	    ecx,eax
	
        push	edx		;x2=x*x
        imul	eax
        mov	    ax,dx
        ror	    eax,16	
        pop	    edx
        xchg	esi,eax

        mov	    eax,edx		;y2=y*y
        push	edx
        imul	eax
        mov	    ax,dx
        ror	    eax,16	
        pop	    edx

        mov	    edi,eax

        inc	    ebp		

        cmp	    ebp,it_tief
        jz	    do_ex

        mov	    eax,esi		;(x2+y2)>4
        add	    eax,edi
        cmp	    eax,40000h
        jle	    do_sch	

do_ex:
        mov	    ax,word [i_i]
        mov	    bx,word width
        mul	    bx
        add	    ax,word [r_i]
        xchg    di,ax

        push    edi             ;new
        push    eax             ;new
        and     edi,0xffff      ;new
        mov     eax,[dbuff]     ;new
        add     edi,eax         ;new
        mov	    ax,bp
        stosb
        pop     eax             ;new
        pop     edi             ;new
        
        xchg	di,ax
        mov	    ax,height-1
        mov	    bx,word [i_i]
        sub	    ax,bx
        mov	    bx,width
        mul	    bx
        add	    ax,word [r_i]
        xchg	di,ax

        jmp	    i_sch

fine: 
        add	    [z_r],dword anistep
        cmp	    [z_r],dword z_r_end
        jl	    no_reset

        ;reset animation parameter
        mov	    [z_r],dword z_r_anf

no_reset:        




        ;change dos field (1 byte per pixel) to RGB colors (of fire palete) and write to frame buffer
        mov     ecx,width*height
        mov     esi,[dbuff]
        mov     edi,[fbuff]
        add     edi,width*height*colordeep-4
transf:
        xor     eax,eax
        mov     al,[esi]
        inc     esi

        ;increase intensety of eax to see more details
        mov     ebx,dword increase_intensety
        mul     ebx

%ifdef  USE_FIRE_COLORS      
        call    _toFireColor
%else        
        call    _toRgbColor
%endif        
        mov     [edi],eax
        sub     edi,4
        dec     ecx
        jnz     transf



        add     esp,28
        ret


;##############################################################################


;##############################################################################

;##############################################################################
; convert intensity (1 byte) to RGB palette(3byte) 
_toRgbColor:
        ;parameter:
        ;EAX = intensity, range : 0 - 255

        ;return value:
        ;EAX = RGB color of fire (0x00BBGGRR)
      
        push    ebx

        xor     ebx,ebx
        mov     bl,al
        shl     ebx,16
        mov     bh,al
        mov     bl,al
        mov     eax,ebx

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

