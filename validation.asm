; Validation
[ORG 0x7c00]

;Init the environment
xor ax, ax                ; make it zero
mov ds, ax                ; DS=0
mov ss, ax                ; stack starts at 0
mov sp, 0x9c00            ; 200h past code start
mov ah, 0xb8              ; text video memory
mov es, ax                ; ES=0xB800
mov al, 0x03
int 0x10
mov ah, 1
mov ch, 0x26
int 0x10
;Fill in all black
mov cx, 0x07d0            ; whole screens worth
;cbw                       ; clear ax (black on black with null char)
mov ah, 0x88              ; Fill screen with dark grey color
xor di, di                ; first coordinate of video mem
rep stosw                 ; push it to video memory
mov bp, 0x100             ; initialize validation to 100
mov [0x046C], cx          ; initilize timer to zero (cx already is 0 at this point)

waitkey:
  ; Print the Score
  push di              ; don't interfere with current video location
  mov di, 12           ; video location to print score
  call score           ; Update validation score
  pop di               ; restore old video location

  ; IRL Bonus Check
  push bp              ; keep a backup of the score
  mov bp, [0x046C]     ; get current time
  mov ax, bp           ; get a copy of the time
  cmp al, 0x42         ; compare the last byte with 0x42 (will occur up to 38 times in gameplay assuming no user interaction)
  jne no_irl           ; If it wasn't 0x42, skip the 'IRL' bonus
  pop bp               ; Get our score back for a second
  inc bp               ; Add a point to it
  push bp              ; put score back on the stack (because it's going to get popped in a few instructions)
  inc word [0x046c]    ; Also increment the clock by a tic, otherwise the score will climb unrestrained.

no_irl:
  push di              ; Keep back up of old video location
  mov di, 2            ; video location of life-timer
  call score           ; Display the timer on screen
  pop di               ; restore old video location

  cmp bp, 0x25FF       ; Almost 9 minutes (8:55)...and 2600!
  ja win               ; If times up, die

  pop bp               ; Restore actual score (was being used in conjuction with time before this)

  ; Key-Press checking
  mov ah, 1               ; Is there a key
  int 0x16                ; ""
  jz waitkey              ; If not wait for a key
  cbw                     ; clear ax (Get the key)
  int 0x16                ; ""
  call pull_lever         ; If there was a key press, pull the lever
  jmp waitkey             ; 'Infinite Loop'


pull_lever:
mov di, 160 * 9 + 20      ; Coordinate of first slot peice (upper left)
; Routine for entire column (slot), this will run 3 times
column_spin:
  cmp di, 160 * 9 + 74      ; Check to see if it is trying for the 4th time
  je results                ; If so, it's now time to see if player won validation
  mov si, retweet - 9       ; Get address of ghost sprite before the first one
  in al,(0x40)              ; Get random
  and al, 0x07              ; Mask with 7 possibilities
  mov bl, 9                 ; We want to multiply by 9 (for sprite size offset)
  mul bl
  cbw                       ; clear upper part of ax
  add si, ax                ; add random offset to base sprite offset
  add di, 18                ; Go to the next column
  mov dl, 2; Initialize delay (starts fast, gets slower)
  spin:
    ; Delay Loop
    mov bx, [0x046C]        ; Get timer
    add bx,dx               ; Add deley
    delay:
      cmp [0x046C], bx      ; Is it there yet
      jne delay             ; If not, check again
  ; First Row
  add si, 9                 ; Go to next sprite
  sub di, 1280              ; Go down to next row
  call drawsprite           ; Draw the sprite

  ; Rotating - Draw the next two sprites.
  ; I hate this algorithm. Make sure rotate effect appears from top to bottom
  ; and that there is out of bounds detection and correction.
  ; Second Row
  cmp si, retweet     ; Is the second row the first sprite
  jne next_item_a     ; If not, don't worry
  add si, 63          ; If so, correct next row for last sprite
  next_item_a:
  sub si, 9           ; Go back another sprite
  call drawsprite     ; Draw the sprite
  ; Third Row
  cmp si, retweet     ; Is the third row the first sprite
  jne next_item_b     ; If not, don't worry
  add si, 63          ; If so, correct next row for last sprite
  next_item_b:
  sub si, 9           ; Go back another sprite
  call drawsprite     ; Draw the sprite
  ; Cleanup
  add si, 18          ; Adjust for next rotation
  cmp si, bus + 9     ; First Bounds check
  jne next_item_c     ; Skip if within
  mov si, retweet     ; Correct
  next_item_c:
  cmp si, bus + 18    ; Second Bounds check
  jne next_item_d     ; Skip if within
  mov si, fbthumb     ; Correct
  next_item_d:
  sub di, 2560        ; Vertical Adjust graphic coordinate

  add dl, 1    ; Get a little slower of spin (0xb4)
  cmp dl, 18   ; Check if spinning is done
  je column_spin                ; If so start to spin the next slot
  cmp si, retweet + 54          ; Normal out of bounds check
  jne spin                      ; if not out of bounds, then keep rotating
  mov si, retweet - 9           ; if so, reset back to first sprite
  jmp spin

  results:
    ; Note that there are some es:addresses being checked, these are a selected pixel
    ; from one of each of the 3 middle row images. The pixel color happens to be unique
    ; for each of the 7 image types. So checking for matches can actually work accurately
    xor bx,bx           ; init amount
    mov ax, [es:0x5cb]
    cmp ax, [es:0x5dd]  ; compare 1 and 2
    jne next_slot_a
      inc bx            ; there was a match
    next_slot_a:
    cmp ax, [es:0x5ef]  ; compare 1 and 3
    jne next_slot_b
      inc bx            ; there was a match
    next_slot_b:
    mov ax, [es:0x5dd]
    cmp ax, [es:0x5ef]  ; compare 2 and 3
    jne last_slot
      inc bx            ; there was a match
    last_slot:
    ; At this point, if any two match, bx will have 1. If all 3 match, bx will have 3.
    ; Now, adjust points won
    xchg ax,bx
    cbw
    mov bl, 10           ; multiply score by 10
    mul bl
    add al, 5            ; add 5 to the results
    cmp al, 5            ; (0*10) + 5 = 5, in other words, no matches, so:
    je results_done      ;   skip to results_done
    ; In other words, if there was a match of any 2, then 10 points are awarded, otherwise, 30 points
    add bp, ax           ; add to score

    ; Now check for penalties, cyberbullying/bus. Note that these checks only happen after the
    ; checking for matches of two or more
    cmp byte [es:0x5cb], 0x99                   ; is cyberbully?
    jne next_accident_a                         ; if not, check next image
    sub bp, 73                                  ; if so, subtract 73 points
    next_accident_a: cmp byte [es:0x5dd], 0x99  ; is cyberbully?
    jne next_accident_b                         ; if not, check next image
    sub bp, 73                                  ; if so, subtract 73 points
    next_accident_b: cmp byte [es:0x5ef], 0x99  ; is cyberbully?
    jne bus_check                               ; if not, then start checking for busses
    sub bp, 73                                  ; if so, subtract 73 points
    bus_check: cmp byte [es:0x5cb], 0x66        ; is it a bus?
    jne results_done                            ; if not, then not all 3 were busses, results are done
    cmp byte [es:0x5dd], 0x66                   ; is it a bus?
    jne results_done                            ; if not, then not all 3 were busses, results are done
    cmp byte [es:0x5ef], 0x66                   ; is it a bus?
    jne results_done                            ; if not, then not all 3 were busses, results are done
    jmp ded                                     ; all 3 were busses, you ded

    results_done:
    ; Subtract a point just for checking your status
    sub bp, 5

    ; Check for suicide death (there's gotta be a better/smaller way to check for negative in bp)
    bt bp, 15    ; test bit at row (bx) (see if negative, 4 byte instruction)
    jc ded
ret

win:
mov ah, 0x22              ; Color for Green
pop bp                    ; Get score from the stack
cmp bp, 0x126             ; Compare it to the minimum winning score
jae ded_win               ; If it's sufficient, stay green and die
ded: 
mov ah, 0x44              ; Otherwise, dishonorable death
ded_win:
; Fill in color with everything exept top score line and middle slot row, this way you
; can see time of death, validation at death, and last slot roll
mov di, 160               ; start at 2nd row of screen (so timer and score is still visible)
mov cx, 640               ; fill until 2nd slot row
rep stosw                 ; push it to video memory
add di, 1280              ; start again at 3rd slot row
mov cx, 640               ; enough to fill that row
rep stosw
halt: jmp halt

drawsprite:
  ; Gets and unpacks bits that define changes in color for 2 color sprite
  xor ax, ax         ; ax, must be cleared
  mov al, byte [si]  ; get the packed colors
  shl ax, 4          ; get upper color into ah
  shr al, 4          ; restore lower color nibble in al
  mov bx, 0x0011     ; have color doubles in each register (xxyy)
  push dx            ; mul mangles dx, so save it
  mul bx             ;
  pop dx             ; restore dx

  ; Check color and print it
  mov bl, 1          ; init index to 2nd byte in sprite data structure
  columns:
  mov cl, 8          ; 8 pixels a row
  row:
  pixel_check: bt word [si + bx], 7    ; test bit at row (bx)
  jnc noswitch                         ; see if we need to switch colors
  xchg ah, al                          ; switch the colors
  noswitch:
  stosw                                ; paint the color
  dec byte [pixel_check + 3]           ; next pixel
  loop row

  ; Next column
  mov byte [pixel_check + 3], 7        ; reset bit test location
  inc bl                               ; next column (memory)
  add di, 144                          ; adjust horizontal screen area
  cmp bl, 9                            ; are we done with rows
  jne columns

ret

score:
  ; Most of this routine is some magic from Peter Ferrie
  mov ax, bp
  push ax
  xchg ah,al
  call hex2asc
  pop ax ;<----------;
  hex2asc:           ;
    aam 16           ;
    call hex2nib     ;
  hex2nib: ;<------; |
    xchg ah,al     ; |
    cmp al,0ah     ; |
    sbb al,69h     ; |
    das            ; |   Caller
    stosb          ; |     ^
    mov al,7       ; |     |
    stosb          ; |     |
ret ; -------------1-2-----3

; =========== SPRITE DATA ==========
; 63 bytes total
; 9 bytes per sprite
; Sprite Data structure:
;   1st byte is color data, first nibble is color 1, and 2nd nibble is color 2
;   Each byte after is a full row of pixels, however, a 1 or 0 does not correspond
;   to a color, it corresponds to if there is a change in color. This makes for a 
;   more space optimized drawing routine
retweet: db 0x82, 0x00, 0x69, 0x93, 0x63, 0x63, 0x64, 0xcb, 0x00
fbthumb: db 0xf1, 0x06, 0x0a, 0x14, 0x10, 0x30, 0x31, 0xb1, 0xa0
pow: db 0x9e, 0x00, 0x7b, 0x36, 0x17, 0x74, 0x36, 0x6f, 0x00
heart: db 0x04, 0x00, 0x2d, 0x40, 0xc0, 0xa1, 0x12, 0x0c, 0x00
plusone: db 0x4f, 0x00, 0x03, 0x35, 0x4b, 0x33, 0x03, 0x00, 0x00
igheart: db 0xfd, 0x41, 0xbf, 0x27, 0x1b, 0x00, 0xc1, 0x14, 0x00
bus: db 0x6e, 0x00, 0x18, 0x30, 0x60, 0x00, 0x21, 0x41, 0x36

;BIOS sig and padding
times 510-($-$$) db 0
dw 0xAA55
