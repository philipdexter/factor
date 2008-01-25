! Copyright (C) 2005, 2007 Slava Pestov.
! Portions copyright (C) 2007 Eduardo Cavazos.
! See http://factorcode.org/license.txt for BSD license.
USING: alien alien.c-types continuations kernel libc math namespaces sequences
math.vectors math.constants math.functions opengl.gl opengl.glu
combinators arrays ;
IN: opengl

: coordinates [ first2 ] 2apply ;

: fix-coordinates [ first2 [ >fixnum ] 2apply ] 2apply ;

: gl-color ( color -- ) first4 glColor4d ; inline

: gl-clear-color ( color -- )
    first4 glClearColor ;

: gl-clear ( color -- )
    gl-clear-color GL_COLOR_BUFFER_BIT glClear ;

: gl-error ( -- )
    glGetError dup zero? [
        "GL error: " over gluErrorString append throw
    ] unless drop ;

: do-state ( what quot -- )
    swap glBegin call glEnd ; inline

: do-enabled ( what quot -- )
    over glEnable dip glDisable ; inline

: do-matrix ( mode quot -- )
    swap [ glMatrixMode glPushMatrix call ] keep
    glMatrixMode glPopMatrix ; inline

: gl-vertex ( point -- )
    dup length {
        { 2 [ first2 glVertex2d ] }
        { 3 [ first3 glVertex3d ] }
        { 4 [ first4 glVertex4d ] }
    } case ;

: gl-normal ( normal -- ) first3 glNormal3d ;

: gl-material ( face pname params -- )
    >c-float-array glMaterialfv ;

: gl-line ( a b -- )
    GL_LINES [ gl-vertex gl-vertex ] do-state ;

: gl-fill-rect ( loc ext -- )
    coordinates glRectd ;

: gl-rect ( loc ext -- )
    GL_FRONT_AND_BACK GL_LINE glPolygonMode
    >r { 0.5 0.5 } v+ r> { 0.5 0.5 } v- gl-fill-rect
    GL_FRONT_AND_BACK GL_FILL glPolygonMode ;

: (gl-poly) [ [ gl-vertex ] each ] do-state ;

: gl-fill-poly ( points -- )
    dup length 2 > GL_POLYGON GL_LINES ? (gl-poly) ;

: gl-poly ( points -- )
    GL_LINE_LOOP (gl-poly) ;

: circle-steps dup length v/n 2 pi * v*n ;

: unit-circle dup [ sin ] map swap [ cos ] map ;

: adjust-points [ [ 1 + 0.5 * ] map ] 2apply ;

: scale-points 2array flip [ v* ] with map [ v+ ] with map ;

: circle-points ( loc dim steps -- points )
    circle-steps unit-circle adjust-points scale-points ;

: gl-circle ( loc dim steps -- )
    circle-points gl-poly ;

: gl-fill-circle ( loc dim steps -- )
    circle-points gl-fill-poly ;

: prepare-gradient ( direction dim -- v1 v2 )
    tuck v* [ v- ] keep ;

: gl-gradient ( direction colors dim -- )
    GL_QUAD_STRIP [
        swap >r prepare-gradient r>
        [ length dup 1- v/n ] keep [
            >r >r 2dup r> r> gl-color v*n
            dup gl-vertex v+ gl-vertex
        ] 2each 2drop
    ] do-state ;

: (gen-gl-object) ( quot -- id )
    >r 1 0 <uint> r> keep *uint ; inline
: gen-texture ( -- id )
    [ glGenTextures ] (gen-gl-object) ;
: gen-framebuffer ( -- id )
    [ glGenFramebuffersEXT ] (gen-gl-object) ;
: gen-renderbuffer ( -- id )
    [ glGenRenderbuffersEXT ] (gen-gl-object) ;
: gen-buffer ( -- id )
    [ glGenBuffers ] (gen-gl-object) ;

: (delete-gl-object) ( id quot -- )
    >r 1 swap <uint> r> call ; inline
: delete-texture ( id -- )
    [ glDeleteTextures ] (delete-gl-object) ;
: delete-framebuffer ( id -- )
    [ glDeleteFramebuffersEXT ] (delete-gl-object) ;
: delete-renderbuffer ( id -- )
    [ glDeleteRenderbuffersEXT ] (delete-gl-object) ;
: delete-buffer ( id -- )
    [ glDeleteBuffers ] (delete-gl-object) ;

: framebuffer-incomplete? ( -- ? )
    GL_FRAMEBUFFER_EXT glCheckFramebufferStatusEXT
    dup GL_FRAMEBUFFER_COMPLETE_EXT = f rot ? ;

: framebuffer-error ( status -- * )
    { { GL_FRAMEBUFFER_COMPLETE_EXT [ "framebuffer complete" ] }
      { GL_FRAMEBUFFER_UNSUPPORTED_EXT [ "framebuffer configuration unsupported" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT_EXT [ "framebuffer incomplete (incomplete attachment)" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT_EXT [ "framebuffer incomplete (missing attachment)" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS_EXT [ "framebuffer incomplete (dimension mismatch)" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_FORMATS_EXT [ "framebuffer incomplete (format mismatch)" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER_EXT [ "framebuffer incomplete (draw buffer(s) have no attachment)" ] }
      { GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER_EXT [ "framebuffer incomplete (read buffer has no attachment)" ] }
      [ drop gl-error "unknown framebuffer error" ] } case throw ;

: check-framebuffer ( -- )
    framebuffer-incomplete? [ framebuffer-error ] when* ;

: with-framebuffer ( id quot -- )
    GL_FRAMEBUFFER_EXT rot glBindFramebufferEXT
    call
    GL_FRAMEBUFFER_EXT 0 glBindFramebufferEXT ; inline

: bind-texture-unit ( id target unit -- )
    glActiveTexture swap glBindTexture gl-error ;

: framebuffer-attachment ( attachment -- id )
    GL_FRAMEBUFFER_EXT swap GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME_EXT
    0 <uint> [ glGetFramebufferAttachmentParameterivEXT ] keep *uint ;
    
: set-draw-buffers ( buffers -- )
    dup length swap >c-uint-array glDrawBuffers ;

: do-attribs ( bits quot -- )
    swap glPushAttrib call glPopAttrib ; inline

: gl-look-at ( eye focus up -- )
    >r >r first3 r> first3 r> first3 gluLookAt ;

TUPLE: sprite loc dim dim2 dlist texture ;

: <sprite> ( loc dim dim2 -- sprite )
    f f sprite construct-boa ;

: sprite-size2 sprite-dim2 first2 ;

: sprite-width sprite-dim first ;

: gray-texture ( sprite pixmap -- id )
    gen-texture [
        GL_TEXTURE_BIT [
            GL_TEXTURE_2D swap glBindTexture
            >r >r GL_TEXTURE_2D 0 GL_RGBA r>
            sprite-size2 0 GL_LUMINANCE_ALPHA
            GL_UNSIGNED_BYTE r> glTexImage2D
        ] do-attribs
    ] keep ;
    
: gen-dlist ( -- id ) 1 glGenLists ;

: make-dlist ( type quot -- id )
    gen-dlist [ rot glNewList call glEndList ] keep ; inline

: init-texture ( -- )
    GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_LINEAR glTexParameteri
    GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_LINEAR glTexParameteri
    GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_CLAMP glTexParameterf
    GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_CLAMP glTexParameterf ;

: gl-translate ( point -- ) first2 0.0 glTranslated ;

: top-left drop 0 0 glTexCoord2i 0.0 0.0 glVertex2d ; inline

: top-right 1 0 glTexCoord2i first 0.0 glVertex2d ; inline

: bottom-left 0 1 glTexCoord2i second 0.0 swap glVertex2d ; inline

: bottom-right 1 1 glTexCoord2i gl-vertex ; inline

: four-sides ( dim -- )
    dup top-left dup top-right dup bottom-right bottom-left ;

: draw-sprite ( sprite -- )
    dup sprite-loc gl-translate
    GL_TEXTURE_2D over sprite-texture glBindTexture
    init-texture
    GL_QUADS [ dup sprite-dim2 four-sides ] do-state
    dup sprite-dim { 1 0 } v*
    swap sprite-loc v- gl-translate
    GL_TEXTURE_2D 0 glBindTexture ;

: draw-rectangle ( lower-left upper-right -- )
    GL_QUADS [
        over first2 glVertex2d
        dup first pick second glVertex2d
        dup first2 glVertex2d
        swap first swap second glVertex2d
    ] do-state ;

: make-sprite-dlist ( sprite -- id )
    GL_MODELVIEW [
        GL_COMPILE [ draw-sprite ] make-dlist
    ] do-matrix ;

: init-sprite ( texture sprite -- )
    [ set-sprite-texture ] keep
    [ make-sprite-dlist ] keep set-sprite-dlist ;

: delete-dlist ( id -- ) 1 glDeleteLists ;

: free-sprite ( sprite -- )
    dup sprite-dlist delete-dlist
    sprite-texture delete-texture ;

: free-sprites ( sprites -- ) [ [ free-sprite ] when* ] each ;

: with-translation ( loc quot -- )
    GL_MODELVIEW [ >r gl-translate r> call ] do-matrix ; inline

: gl-set-clip ( loc dim -- )
    fix-coordinates glScissor ;

: gl-viewport ( loc dim -- )
    fix-coordinates glViewport ;

: init-matrices ( -- )
    GL_PROJECTION glMatrixMode
    glLoadIdentity
    GL_MODELVIEW glMatrixMode
    glLoadIdentity ;

! Shaders

: c-true? ( int -- ? ) zero? not ; inline

: with-gl-shader-source-ptr ( string quot -- )
    swap dup length 1+ [ tuck string>memory <void*> swap call ] with-malloc ; inline

: <gl-shader> ( source kind -- shader )
    glCreateShader dup rot [ 1 swap f glShaderSource ] with-gl-shader-source-ptr
    [ glCompileShader ] keep
    gl-error ;

: (gl-shader?) ( object -- ? )
    dup integer? [ glIsShader c-true? ] [ drop f ] if ;

: gl-shader-get-int ( shader enum -- value )
    0 <int> [ glGetShaderiv ] keep *int ;

: gl-shader-ok? ( shader -- ? )
    GL_COMPILE_STATUS gl-shader-get-int c-true? ;

: <vertex-shader> ( source -- vertex-shader )
    GL_VERTEX_SHADER <gl-shader> ; inline

: (vertex-shader?) ( object -- ? )
    dup (gl-shader?) [ GL_SHADER_TYPE gl-shader-get-int GL_VERTEX_SHADER = ] [ drop f ] if ;

: <fragment-shader> ( source -- fragment-shader )
    GL_FRAGMENT_SHADER <gl-shader> ; inline

: (fragment-shader?) ( object -- ? )
    dup (gl-shader?) [ GL_SHADER_TYPE gl-shader-get-int GL_FRAGMENT_SHADER = ] [ drop f ] if ;

: gl-shader-info-log-length ( shader -- log-length )
    GL_INFO_LOG_LENGTH gl-shader-get-int ; inline

: gl-shader-info-log ( shader -- log )
    dup gl-shader-info-log-length dup [ [ 0 <int> swap glGetShaderInfoLog ] keep alien>char-string ] with-malloc ;

: check-gl-shader ( shader -- shader* )
    dup gl-shader-ok? [ dup gl-shader-info-log throw ] unless ;

: delete-gl-shader ( shader -- ) glDeleteShader ; inline

PREDICATE: integer gl-shader (gl-shader?) ;
PREDICATE: gl-shader vertex-shader (vertex-shader?) ;
PREDICATE: gl-shader fragment-shader (fragment-shader?) ;

! Programs

: <gl-program> ( shaders -- program )
    glCreateProgram swap
    [ dupd glAttachShader ] each
    [ glLinkProgram ] keep
    gl-error ;
    
: (gl-program?) ( object -- ? )
    dup integer? [ glIsProgram c-true? ] [ drop f ] if ;

: gl-program-get-int ( program enum -- value )
    0 <int> [ glGetProgramiv ] keep *int ;

: gl-program-ok? ( program -- ? )
    GL_LINK_STATUS gl-program-get-int c-true? ;

: gl-program-info-log-length ( program -- log-length )
    GL_INFO_LOG_LENGTH gl-program-get-int ; inline

: gl-program-info-log ( program -- log )
    dup gl-program-info-log-length
    dup [ [ 0 <int> swap glGetProgramInfoLog ] keep
          alien>char-string ] with-malloc ;

: check-gl-program ( program -- program* )
    dup gl-program-ok? [ dup gl-program-info-log throw ] unless ;

: gl-program-shaders-length ( program -- shaders-length )
    GL_ATTACHED_SHADERS gl-program-get-int ; inline

: gl-program-shaders ( program -- shaders )
    dup gl-program-shaders-length
    [ dup "GLuint" <c-array> [ 0 <int> swap glGetAttachedShaders ] keep ] keep
    c-uint-array> ;

: delete-gl-program-only ( program -- ) glDeleteProgram ; inline

: detach-gl-program-shader ( program shader -- ) glDetachShader ; inline

: delete-gl-program ( program -- )
    dup gl-program-shaders [ 2dup detach-gl-program-shader delete-gl-shader ] each
    delete-gl-program-only ;

: with-gl-program ( program quot -- )
    swap glUseProgram [ call ] [ 0 glUseProgram ] [ ] cleanup ; inline

PREDICATE: integer gl-program (gl-program?) ;

: <simple-gl-program> ( vertex-shader-source fragment-shader-source -- program )
    >r <vertex-shader> check-gl-shader
    r> <fragment-shader> check-gl-shader
    2array <gl-program> check-gl-program ;

