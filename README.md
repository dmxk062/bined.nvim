# bined.nvim

The next generation `xxd`

<!-- TOC -->
- [Requirements](#requirements)
- [Rationale](#rationale)
- [Usage](#usage)
- [Known issues](#known-issues)
<!-- /TOC -->

## Requirements
- A Neovim with LuaJIT

## Rationale

Right now the best way to edit some binary data using Neovim uses `xxd`. But there are a couple of problems with this workflow wise:
- Reading and writing binary data are separate from built in commands: `:%!xxd` to read and then `:%xxd -r` to write
- The buffer contents are replaced in place, there is no way to view both the full plaintext and the hexdump
- `xxd` needs to be manually rerun and the size specified manually to adapt to window size changes, otherwise the clear column layout might be lost

## Usahe

Right now there is only a single command you need to memorize: `:Bined`

When you run `:Bined`, a new split will open, allowing you to edit the contents of the current buffer in hexadecimal, octal or binary.
A highlight in the original buffer will show you where you are.  
Whenever you `:w` the dump buffer, the contents will by synchronized back to the main buffer, the same applies if you `:w` the main buffer. 
This allows you to use Neovim itself for entering and editing plaintext and only use the hex editor part for the thing it is good at.

## Known issues

- Highlights don't change with input: This will require a vim syntax file or a treesitter parser
