if exists("b:current_syntax") 
    finish
endif

syn match BinedAddress '^\x*:'
syn match BinedNull '\(\s\|^\)\(00\+\)\(\s\|$\)'
let b:current_syntax = "bined"
