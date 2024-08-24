local parser = require("bined.parser")
local ffi = require("ffi")
local M = {}

---@class bined_bufinfo
---@field cached_data bined_data?
---@field augroup integer
---@field bufnum integer
---@field winnum integer
---@field edit_buf integer
---@field edit_win integer
---@field base base
---@field width integer
---@field elems_per_line integer

---@type bined_bufinfo[]
local bufinfos = {}

local dinamespace = vim.api.nvim_create_namespace("BinedDiagnostic")
local hlnamespace = vim.api.nvim_create_namespace("BinedHighlight")

---@param target_bufnum integer
---@param data bined_data
---@param base base
---@param elems_per_line integer
local function draw_buffer(target_bufnum, data, base, elems_per_line)
    local baseinfo = parser.base_data[base]

    -- if its cached already, use that
    local string_repr = data[base]
    if not string_repr then
        string_repr = {}
        for i = 0, data.length - 1 do
            table.insert(string_repr, baseinfo.fmt(data.bytes[i]))
        end
        data[base] = string_repr
    end

    local lines = {}
    local bytes_as_chars = data[base]
    local cur_line = ""
    local cur_hl = {}
    local hl_groups = {}

    for i = 0, #bytes_as_chars do
        if i % elems_per_line == 0 then
            if #cur_line > 0 then
                table.insert(lines, cur_line)
                table.insert(hl_groups, cur_hl)
            end
            cur_hl   = {}
            cur_line = string.format("%08X:", i)
        end
        local oldlen = #cur_line
        if bytes_as_chars[i + 1] then
            cur_line = cur_line .. (i % baseinfo.group == 0 and " " or "") .. bytes_as_chars[i + 1]
        end
        -- highlight ascii characters
        if data.bytes[i] >= 32 and data.bytes[i] < 127 then
            table.insert(cur_hl, { "BinedString", oldlen, #cur_line })
        end
    end
    if #cur_line > #"00000000: " then
        table.insert(lines, cur_line)
        table.insert(hl_groups, cur_hl)
    end

    vim.api.nvim_buf_set_lines(target_bufnum, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(target_bufnum, hlnamespace, 0, -1)
    for i, line in ipairs(hl_groups) do
        for _, hl in pairs(line) do
            vim.api.nvim_buf_add_highlight(target_bufnum, hlnamespace, hl[1], i - 1, hl[2], hl[3])
        end
    end
end


local function redraw_edit_buffer(bufnum, reload)
    local info = bufinfos[bufnum]
    local data = info.cached_data
    if reload or not data then
        data = parser.buffer_to_repr(info.bufnum)
        info.cached_data = data
    else
        data = info.cached_data
    end
    draw_buffer(info.edit_buf, data, info.base, info.elems_per_line)
    vim.bo[bufnum].modified = false
end


local function get_elems_per_line(len, size, mult, max)
    local usable_line_length = len - 20 -- reserve for address and diagnostics
    local bytes_per_line = math.floor(usable_line_length / size)
    if bytes_per_line % mult ~= 0 then
        bytes_per_line = mult * math.floor(bytes_per_line / mult)
    end

    return math.min(max, math.max(1, bytes_per_line))
end

local function update_width(bufnum)
    local data = bufinfos[bufnum]
    data.width = vim.api.nvim_win_get_width(data.edit_win)
    local baseinfo = parser.base_data[data.base]
    local new_num_elems = get_elems_per_line(data.width, baseinfo.word_size,
        baseinfo.mult, baseinfo.max)
    data.elems_per_line = new_num_elems
end

local function write_to_bin(bufnum)
    local data = bufinfos[bufnum]
    local baseinfo = parser.base_data[data.base]

    local lines = vim.api.nvim_buf_get_lines(data.edit_buf, 0, -1, false)
    local filtered_lines = vim.tbl_map(function(ln)
        return ln:gsub("^[%x]*: ", "")
    end, lines)

    local index = 0
    local errors = {}
    local bytes = parser.create_buffer(data.elems_per_line * #lines + 512)
    for i, line in pairs(filtered_lines) do
        local fields = vim.split(line, "%s+", { trimempty = true })
        for _, field in ipairs(fields) do
            local ok, num = pcall(tonumber, field, baseinfo.int_value)
            if not ok or not num then
                table.insert(errors, {
                    message = "Invalid int for base" .. baseinfo.int_value .. ": `" .. field .. "`",
                    lnum = i - 1,
                    col = 0,
                })
                goto continue
            end

            if num > 0xFFFF then
                table.insert(errors, {
                    message = "Too large: (" .. num .. " > 0xFF)",
                    lnum = i - 1,
                    col = 0,
                })
                goto continue
            end


            if (data.base == "hex" or data.base == "oct") and (num > 0xFF or vim.startswith(field, "00")) then
                ---@FIXME: right now this is little-endian specific
                local high = bit.rshift(num, 8)
                local low = bit.band(num, 0xFF)
                bytes[index] = high
                bytes[index + 1] = low

                index = index + 2
            else
                bytes[index] = num
                index = index + 1
            end
            ::continue::
        end
    end

    if #errors > 0 then
        vim.diagnostic.set(dinamespace, data.edit_buf, errors)
        return false
    end
    local as_string = ffi.string(bytes, index)
    local as_table = vim.split(as_string, "\n")

    -- force reload
    data.cached_data = nil
    vim.api.nvim_buf_set_lines(data.bufnum, 0, -1, false, as_table)
    return true
end

local function mirror_cursor_movement(bufnum)
    local info = bufinfos[bufnum]
    local data = info.cached_data
    if not data then
        return
    end
    local row, col = unpack(vim.api.nvim_win_get_cursor(info.edit_win))
    row = row - 1
    local b_start = row * info.elems_per_line
    local b_end = (b_start + info.elems_per_line)

    local found_closing = false
    local found_opening = false

    local lines_to_hl = {}
    for i, line in ipairs(data.line_starts) do
        local l_start = line[1]
        local l_end   = line[2] - 1

        local r_start = b_start - l_start
        local r_end   = b_end - l_start

        -- all the highlights are in a single line
        if b_start >= l_start and b_start <= l_end and b_end <= l_end and b_end >= l_start then
            lines_to_hl = { { i - 1, r_start, r_end } }
            break
            -- starts in line, ends in another
        elseif b_start >= l_start and b_start < l_end then
            table.insert(lines_to_hl, { i - 1, r_start, -1 })
            -- ends in this line, starts in another
        elseif b_end >= l_start and b_end <= l_end then
            table.insert(lines_to_hl, { i - 1, 0, r_end })
        end

        -- early exit if were at the start of the buffer
        if found_opening and found_closing then
            break
        end
    end

    vim.api.nvim_buf_clear_namespace(info.bufnum, hlnamespace, 0, -1)
    if #lines_to_hl < 1 then
        return
    end

    -- focus the relevant region
    vim.api.nvim_win_set_cursor(info.winnum, { lines_to_hl[1][1] + 1, lines_to_hl[1][2] })
    for _, hl in pairs(lines_to_hl) do
        vim.api.nvim_buf_add_highlight(info.bufnum, hlnamespace, "BinedContext", hl[1], hl[2], hl[3])
    end
end

---@param bufnum integer
---@param winnum integer
---@param base string
function M.attach_to_or_upd_buffer(bufnum, winnum, base)
    if bufinfos[bufnum] then
        local info = bufinfos[bufnum]
        info.base = base
        update_width(bufnum)
        redraw_edit_buffer(bufnum)
    else
        local edit_buf = vim.api.nvim_create_buf(true, false)
        local edit_win = vim.api.nvim_open_win(edit_buf, true, { win = winnum, split = "left" })

        local augroup = vim.api.nvim_create_augroup("bined_win" .. edit_win .. "_buf" .. bufnum, { clear = true })
        bufinfos[edit_buf] = {
            cached_data = nil,
            augroup = augroup,
            bufnum = bufnum,
            winnum = winnum,
            base = base,
            width = 0,
            elems_per_line = 0,
            edit_win = edit_win,
            edit_buf = edit_buf,
        }

        vim.wo[edit_win].cursorlineopt = "both"
        vim.bo[edit_buf].buftype = "acwrite"
        vim.bo[edit_buf].filetype = "bined"
        vim.api.nvim_buf_set_name(edit_buf, "bined://" .. vim.api.nvim_buf_get_name(bufnum))
        update_width(edit_buf)

        vim.api.nvim_create_autocmd("WinResized", {
            group = augroup,
            buffer = edit_buf,
            callback = function(args)
                update_width(edit_buf)
                redraw_edit_buffer(edit_buf)
            end
        })

        local function shutdown()
            bufinfos[edit_buf] = nil
            vim.api.nvim_buf_delete(edit_buf, { force = true })
            vim.api.nvim_del_augroup_by_id(augroup)
        end
        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            buffer = edit_buf,
            callback = shutdown
        })
        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            buffer = bufnum,
            callback = shutdown
        })

        vim.api.nvim_create_autocmd("BufWriteCmd", {
            group = augroup,
            buffer = edit_buf,
            callback = function(args)
                if write_to_bin(edit_buf) then
                    redraw_edit_buffer(edit_buf, true)
                end
            end
        })

        vim.api.nvim_create_autocmd("BufWritePost", {
            group = augroup,
            buffer = bufnum,
            callback = function(args)
                redraw_edit_buffer(edit_buf, true)
            end
        })

        vim.api.nvim_create_autocmd("CursorMoved", {
            group = augroup,
            buffer = edit_buf,
            callback = function(args)
                mirror_cursor_movement(edit_buf)
            end
        })
        redraw_edit_buffer(edit_buf)
    end
end

return M
