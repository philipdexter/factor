! Copyright (C) 2009 Slava Pestov.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors assocs combinators combinators.short-circuit
kernel math namespaces sequences compiler.cfg.def-use
compiler.cfg.liveness ;
IN: compiler.cfg.coalescing.interference

! Local interference testing. Requires live-out information
<PRIVATE

SYMBOLS: def-index kill-index ;

: compute-local-live-ranges ( bb -- )
    H{ } clone def-index set
    H{ } clone kill-index set
    [
        instructions>> [
            [ swap defs-vregs [ def-index get set-at ] with each ]
            [ swap uses-vregs [ kill-index get set-at ] with each ]
            2bi
        ] each-index
    ]
    [ live-out keys [ [ 1/0. ] dip kill-index get set-at ] each ]
    bi ;

: kill-after-def? ( vreg1 vreg2 -- ? )
    ! If first register is killed after second one is defined, they interfere
    [ kill-index get at ] [ def-index get at ] bi* >= ;

: interferes-same-block? ( vreg1 vreg2 -- ? )
    ! If both are defined in the same basic block, they interfere if their
    ! local live ranges intersect.
    { [ kill-after-def? ] [ swap kill-after-def? ] } 2|| ;

: interferes-first-dominates? ( vreg1 vreg2 -- ? )
    ! If vreg1 dominates vreg2, then they interfere if vreg2's definition
    ! occurs before vreg1 is killed.
    kill-after-def? ;

: interferes-second-dominates? ( vreg1 vreg2 -- ? )
    ! If vreg2 dominates vreg1, then they interfere if vreg1's definition
    ! occurs before vreg2 is killed.
    swap kill-after-def? ;

PRIVATE>

SYMBOLS: +same-block+ +first-dominates+ +second-dominates+ ;

: interferes? ( vreg1 vreg2 bb mode -- ? )
    ! local interference test - mode is one of the above symbols
    [ compute-local-live-ranges ] dip
    {
        { +same-block+ [ interferes-same-block? ] }
        { +first-dominates+ [ interferes-first-dominates? ] }
        { +second-dominates+ [ interferes-second-dominates? ] }
    } case ;