;
; Basic OS X calls to GLUT and OpenGL
;
; Example by Stino / ByTeGeiZ 
;
; compile with:
; nasm -g -f macho32 GLwing1.asm
; xcrun gcc -framework GLUT -framework OpenGL -m32 -o GLwing1.out GLwing1.o
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
%define width               800
%define height              600
%define colordeep           4

;Parameter Fluegel:

%define re	    1.05523694	;re=1.05*r
%define de	    0.105		;de=1.05*d
%define ce	    0.05		;ce=0.05
%define step	0.004
%define steps	1571		;steps = 2*Pi/step

;Parameter Skalierung:
%define xrand	390
%define yrand	220
%define skale	200.0



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
window_name:    db "GL wing 1", 10, 0
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

; variables for wing sim
memptr:         dd 0
memptr2:        dd 0
counterx:       dd 0
countery:       dd 0
trx:            dd 0
try:            dd 0
once:           dd 0

;Flügelkonstanten
f_re:           dd re
f_de:           dd de
f_ce:           dd ce
f_step:         dd step
f_skale:        dd skale

;Flügelvariablen
x:              dd 0
y:              dd 0
sig:            dd 0


; for pointer to frame buffer
fbuff:          dd 0

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

        ;get memory 1 for the wing simulation
        mov     eax,width*height*4
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [memptr],eax

        ;clear new mem
        xor     al,al
        mov     ecx,width*height*4
        mov     edi,[memptr]
        rep     stosb
        
        ;get memory 2 for the wing simulation
        mov     eax,width*height*4
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [memptr2],eax

        ;clear new mem
        xor     al,al
        mov     ecx,width*height*4
        mov     edi,[memptr2]
        rep     stosb
       
        ;precalculate wing data
        call    _initFrame

        ;get memory for the gl-frame-buffer
        mov     eax,width*height*colordeep
        mov     [esp+4], dword 0
        mov     [esp], eax
        call    _malloc
        ; check if the malloc failed
        test    eax, eax
        jz      _fail_exit
        mov     [fbuff],eax
        
        ;clear new mem
        xor     al,al
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

        ; free the malloc'd memory 1
        mov     eax, dword [memptr]
        mov     [esp], eax
        call    _free

        ; free the malloc'd memory 2
        mov     eax, dword [memptr2]
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


      mov   eax,[once]
      cmp   eax,1
      jz    draw_end
      inc   dword [once]

;Fluegel zeichnen
      mov   esi,[memptr]
      mov   eax,height-1
      mov   [countery],eax
m_1:  mov   eax,width-1
      mov   [counterx],eax
m_2:  
      mov   eax,[countery]
      mov   ebx,width
      mul   ebx
      shl   eax,2
      mov   ebx,[counterx]
      shl   ebx,2
      add   eax,ebx
      mov   edi,eax
            
      mov   eax,[counterx]
      mov   ebx,[countery]
      mov   ecx,[esi+edi]      
      call  _setpixel
      
      dec   dword [counterx]
      jnz   m_2
      dec   dword [countery]
      jnz   m_1



;Druck Feld zeichnen
      mov   eax,height-2
      mov   dword [countery],eax
n_3:

      mov   eax,width-1
      mov   dword [counterx],eax
n_1:  mov   eax,dword [counterx]
      mov   ebx,dword [countery]
      call  _transform
      jc    n_2
      mov   dword [trx],eax
      mov   dword [try],ebx
      finit
      fld   dword [trx]
      fld   dword [try]
      fld   dword [counterx]
      fld   dword [countery]
      fsub  st0,st2
      fmul  st0,st0
      fstp  st2
      fsub  st0,st2
      fmul  st0,st0
      fstp  st2
      faddp st1,st0
      fsqrt
      fst   dword [trx]
      mov   ecx,dword [trx]
      shl   ecx,18
      call  _setpixel
n_2:  dec   dword [counterx]
      jnz   n_1
      dec   dword [countery]
      jnz   n_3

draw_end:
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
;-----------------------------------------------------------;
;                Setpixel                 		      ;
;-----------------------------------------------------------;
        ;Parameter:
        ;eax = x-Punkt
        ;ebx = y-Punkt
        ;ecx = color
        
_setpixel:
        push    edx
        xchg    eax,ebx
        mov     edx,width*colordeep
        mul     edx
        shl     ebx,2
        add     eax,ebx                                      
        add     eax,[fbuff]
        mov     edx,[eax]       ;altes Pixel holen
        test    edx,0ff000000h  ;Schreibschutz?
        jnz     sp1
        mov     [eax],ecx        
sp1:    pop     edx
        ret

;-----------------------------------------------------------;
;                Transform Point          		      ;
;-----------------------------------------------------------;
        ;Parameter:
        ;eax = alter x-Punkt
        ;ebx = alter y-Punkt
        
        ;Rückgabe:
        ;eax = neuer x-Punkt
        ;ebx = neuer y-Punkt
        ;Carryflag = 1, wenn außerhalb vom Bildbereich
        ;Carryflag = 0, wenn alles ok

_transform:
        push    edx
        ;Transformation   
        xchg    eax,ebx
        mov     edx,width
        mul     edx             ;y* width
        add     eax,ebx         ;y* width + x
        shl     eax,2           ;mal4
        add     eax,[memptr2]     ;Transformationsfeld
        mov     ebx,[eax]       ;neuen Koordinaten holen
        ;Koordinaten entpacken  nach eax:ebx
        xor     eax,eax
        shld    eax,ebx,16
        and     ebx,0ffffh
        ;Clipping
        cmp     eax,width
        jge     tf_1
        cmp     ebx,height
        jge     tf_1
        clc                     ;Carryflag = 0
        jmp     tf_2
tf_1:   stc                     ;Carryflag = 1
tf_2:   pop     edx
        ret

;-----------------------------------------------------------;
;                Init Frame                     		      ;
;-----------------------------------------------------------;

_initFrame:
;-----------------------------------------------------------;
;Flügel vorberechnen

    mov edi,[memptr]
    mov	ebx,width
    mov	ecx,steps

	finit
	fld	dword [f_re]
	fld	dword [f_de]
	fld	dword [f_ce]
	fldpi
	fchs

schl:	;Im(z) brechenen
	fld	st0		;lade t
	fsin			;sin(t)
 	fmul	st0,st4	;re*sin(t)
	fadd	st0,st3	;de+re*sin(t)
	fstp	st5		;sichern von Im

	;Re(z) berechen
	fld	st0		;lade t
	fcos			;cos(t)
	fmul	st0,st4	;re*cos(t)
	fadd	st0,st2	;ce+re*cos(t)
	fst	    st6		;sichern von Re

	;f(z) = (z+1/z)/2 berechen
	fmul	st0,st0	;Re*Re
	fstp	st7
	fld	    st4		;Im
	fmul	st0,st0	;Im*Im
	faddp	st7,st0	;Re^2+Im^2	
	fld	    st5		;Re
	fdiv	st0,st7	;Re/(Re^2+Im^2)
	faddp	st6,st0	;Re=Re/(Re^2+Im^2)+Re
	fld	    st4		;Im
	fchs			;-Im
	fdiv	st0,st7	;-Im/(Re^2+Im^2)
	faddp	st5,st0	;-Im/(Re^2+Im^2)+Im
    fld1           
    fadd    st0,st0   ;2
    fdiv    st6,st0  ;re/2
    fdivp   st5,st0  ;im/2

	;Skalierung
	fld	    dword [f_skale]
	fmul	st5,st0	;Im*Skale
	fmulp	st6,st0	;Re*Skale

	;Ergebnis holen
	fdecstp
	fdecstp
	fdecstp
	fdecstp
	fistp	dword [y]
	fistp	dword [x]
	fstp	st0
	fincstp	

	;Y korrigieren
	mov	eax,[y]
	add	eax,yrand      ;Y-Rand korrigieren

    ;In den Speicher
	mul	ebx	         ;mal width
    shl eax,2          ;mal 4
	mov	edx,[x]
	add	edx,xrand	   ;X-Rand korriegieren
    shl edx,2          ;mal 4
	add	eax,edx
    add eax,edi
    mov edx,00ffffffffh
    mov [eax],edx

	;t erhöhen
	fld	    dword [f_step]
	faddp	st1,st0
    dec     ecx
	jnz	    schl

;-----------------------------------------------------------;
;Ablenkung vorberechnen

        mov     edi,[memptr2]

        mov     ebx,height
calc_y: mov     ecx,width
calc_x: push    ebx
        push    ecx

        dec     ecx
        dec     ebx
        mov     dword [x],ecx
        mov     dword [y],ebx
        

        ;Rand korrigieren
        mov     eax,xrand
        sub     dword [x],eax
        mov     eax,yrand
        sub     dword [y],eax

        ;Skalierung rückgängig machen
        finit
        fld1
        fld1
        fld1
        fld1
        fild    dword [x]
        fild    dword [y]
        fld     dword [f_skale]
        fdiv    st2,st0    ;x/f_skale
        fdivp   st1,st0    ;y/f_skale

        ;** Transformation vom Urbildbereich in den Bildbereich(- -> O) **
        ;** z(w) = w +- sqrt(w*w-1)                                     **
        ;1.) w*w
        fld     st0          ;y
        fmul    st0,st0       ;y*y
        fstp    st3       ;y*y
        fld     st1       ;x
        fmul    st0,st0       ;x*x
        fsub    st0,st3    ;wr = x*x-y*y
        fstp    st3       ;wr = x*x-y*y
        fld     st0          ;y
        fmul    st0,st2    ;y*x
        fadd    st0,st0       ;wi = y*x+y*x
        fstp    st4       ;wi = y*x+y*x
        ;2.) (w*w - 1)
        fld1                ;1
        fsubp   st3,st0    ;wr - 1
        ;3.) Radius r = sqrt(x*x+y*y)
        fld     st2       ;wr
        fmul    st0,st0       ;wr*wr
        fld     st4       ;wi
        fmul    st0,st0       ;wi*wi
        faddp   st1,st0    ;wr*wr+wi*wi
        fsqrt               ;r = sqrt(wr*wr+wi*wi)
        fstp    st5       ;r
        ;4.) Winkel a = arctan(wi/wr)
        fld     st3       ;wi
        fdiv    st0,st3    ;wi/wr
        fld1                ;1 für fpatan
        fpatan              ;a = parctan(wi/wr)
        ;Nu und was ist mit dem Quadranten?
        fld     st3       ;wr
        fstp    dword [sig]
        mov     eax,[sig]
        test    eax,10000000000000000000000000000000b
        jz      t_rp
        ;II oder III Quadrant -> a = a + Pi
        fldpi
        faddp   st1,st0
        jmp     t_end
t_rp:   fld     st4       ;wi
        fstp    dword [sig]
        mov     eax,[sig]
        test    eax,10000000000000000000000000000000b
        jz      t_end
        ;IV Quadrant -> a = a + 2*Pi
        fldpi
        fadd    st0,st0
        faddp   st1,st0
t_end:  ;Bei I Quadrant ist keine korrektur nötig!
        ;5.) sqrt(w) = sqrt(r)*(cos(a/2)+I*sin(a/2))
        fld1                ;1
        fadd    st0,st0       ;2
        fdivp   st1,st0    ;a/2
        fst     st6       ;a/2
        fcos                ;cos(a/2)
        fstp    st3       ;wr = cos(a/2)
        fld     st5       ;a/2
        fsin                ;sin(a/2)
        fstp    st4       ;wi = sin(a/2)
        fld     st4       ;r
        fsqrt               ;sqrt(r)
        fmul    st3,st0    ;wr = wr * sqrt(r)
        fmulp   st4,st0    ;wi = wi * sqrt(r)
        ;6.) z(w) = w1[x,y] +/- w2[wr,wi]
        mov     eax,[y]
        test    eax,10000000000000000000000000000000b
        jnz     vz_1
        ;Plus rechnen
        fadd    st0,st3
        fstp    st5
        fadd    st0,st1
        fstp    st3
        fstp    st0
        fstp    st0
        jmp     vz_2
vz_1:   ;Minus rechnen
        fsub    st0,st3
        fstp    st5
        fsub    st0,st1
        fstp    st3
        fstp    st0
        fstp    st0
vz_2:   ;Ergebnis in st = zr und st(1) = zi

        ;** Verschhiebung des Punktes im Bildbereich(dafür also der ganze Aufwand:) **
        ;** z = (f_re*z + I*f_de)+f_ce                                              **
        fld     dword [f_ce]
        fld     dword [f_de]
        fld     dword [f_re]
        fmul    st3,st0    ;zr*f_re
        fmulp   st4,st0    ;zi*f_re
        faddp   st3,st0    ;zi+f_de
        faddp   st1,st0    ;zr+f_ce
        ;Ergebnis in st = zr und st(1) = zi

        ;** Transformation von den Bildbereich in den Urbildbereich(O -> -) **
        ;** w(z) = (z+1/z)/2
        fld1
        fxch    st2
        fxch    st1
        fld1
        fxch    st2         ;zi
        fst     st2
        fld1
        fxch    st2         ;zr
        fst     st2
	    fmul    st0,st0		;zr*zr
	    fstp    st4         ;zr^2 sichern
        fmul    st0,st0		;zi*zi
        faddp   st3,st0	;zr^2+zi^2	
        fld	    st0		;zr
        fdiv    st0,st3      ;zr/(zr^2+zi^2)
        faddp   st1,st0	;zr=zr/(zr^2+zi^2)+ze
        fld	    st1		;zi       
	    fchs			;-zi
        fdiv    st0,st3	;-zi/(zr^2+zi^2)
        faddp   st2,st0	;-zi/(zr^2+zi^2)+zi
        fld1           
        fadd    st0,st0       ;2
        fdiv    st1,st0    ;re/2
        fdivp   st2,st0    ;im/2

        ;Skalierung
        fld     dword [f_skale]       
        fmul    st1,st0    ;zr*f_skale
        fmulp   st2,st0    ;zi*f_skale
        fistp   dword [x]
        fistp   dword [y]

        ;Rand korrigieren
        mov     eax,xrand
        add     dword [x],eax
        mov     eax,yrand
        add     dword [y],eax
        
        ;In Speicher schreiben
        mov     eax,width
        mul     ebx
        add     eax,ecx
        shl     eax,2
        add     eax,edi
        mov     ebx,[y]
        mov     ecx,[x]
        shl     ebx,16
        shld    ecx,ebx,16
        mov     [eax],ecx

        pop     ecx
        pop     ebx
        dec     ecx
        jnz     calc_x
        dec     ebx
        jnz     calc_y
       

        ret

