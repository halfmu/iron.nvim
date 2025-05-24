local is_windows = require("iron.util.os").is_windows
local extend = require("iron.util.tables").extend
local open_code = "\27[200~"
local close_code = "\27[201~"
local cr = "\13"

local common = {}


---@param table table table of strings
---@param substring string
--- Checks in any sting in the table contains the substring
local contains = function(table, substring)
  for _, v in ipairs(table) do
    if string.find(v, substring) then
      return true
    end
  end
  return false
end


---@param lines table
-- Removes empty lines. On unix this includes lines only with whitespaces.
local function remove_empty_lines(lines)
  local newlines = {}

  for _, line in pairs(lines) do
    if string.len(line:gsub("[ \t]", "")) > 0 then
      table.insert(newlines, line)
    end
  end

  return newlines
end


---@param lines table
-- Removes comments
local function remove_comments(lines)
  local newlines = {}

  for _, line in pairs(lines) do
    if string.match(line, "^#") == nil then
      table.insert(newlines, line)
    end
  end

  return newlines
end


---@param s string
--- A helper function using in bracked_paste_python.
-- Checks in a string starts with any of the exceptions.
local function python_close_indent_exceptions(s)
  local exceptions = { "elif", "else", "except", "finally", "#" }
  for _, exception in ipairs(exceptions) do
    local pattern0 = "^" .. exception .. "[%s:]"
    local pattern1 = "^" .. exception .. "$"
    if string.match(s, pattern0) or string.match(s, pattern1) then
      return true
    end
  end
  return false
end


common.format = function(repldef, lines)
  assert(type(lines) == "table", "Supplied lines is not a table")

  local new

  -- passing the command is for python. this will not affect bracketed_paste.
  if repldef.format then
    return repldef.format(lines, { command = repldef.command })
  elseif #lines == 1 then
    new = lines
  else
    new = extend(repldef.open, lines, repldef.close)
  end

  if #new > 0 then
    if not is_windows() then
      new[#new] = new[#new] .. cr
    end
  end

  return new
end


common.bracketed_paste = function(lines)
  if #lines == 1 then
    return { lines[1] .. cr }
  else
    local new = { open_code .. lines[1] }
    for line = 2, #lines do
      table.insert(new, lines[line])
    end

    table.insert(new, close_code .. cr)

    return new
  end
end


--- @param lines table  "each item of the table is a new line to send to the repl"
--- @return table  "returns the table of lines to be sent the the repl with
-- the return carriage added"
common.bracketed_paste_python = function(lines, extras)
  local result = {}

  local cmd = extras["command"]
  local pseudo_meta = { current_buffer = vim.api.nvim_get_current_buf()}
  if type(cmd) == "function" then
    cmd = cmd(pseudo_meta)
  end

  local windows = is_windows()
  local python = false
  local ipython = false
  local ptpython = false

  if contains(cmd, "ipython") then
    ipython = true
  elseif contains(cmd, "ptpython") then
    ptpython = true
  else
    python = true
  end

  lines = remove_empty_lines(lines)
  lines = remove_comments(lines)

  local indent_open = false
  local inside_triple_quote = false
  local triple_quote_type = ""

  for i, line in ipairs(lines) do
    -- Detect entering or exiting triple-quoted blocks
    if not inside_triple_quote then
      local match_start = string.match(line, "'''") or string.match(line, '"""')
      if match_start then
        inside_triple_quote = true
        triple_quote_type = match_start
      end
    else
      if string.find(line, triple_quote_type) then
        inside_triple_quote = false
        triple_quote_type = ""
      end
    end

    -- Directly add lines if inside triple-quoted block
    if inside_triple_quote then
      table.insert(result, line)
    else
      -- Process lines normally
      if string.match(line, "^%s") ~= nil then
        indent_open = true
      end

      table.insert(result, line)

      if windows and python or not windows then
        if i < #lines and indent_open and string.match(lines[i + 1], "^%s") == nil then
          if not python_close_indent_exceptions(lines[i + 1]) then
            indent_open = false
            table.insert(result, cr)
          end
        end
      end
    end
  end

  local newline = windows and "\r\n" or cr
  if #result == 0 then  -- handle sending blank lines
    table.insert(result, cr)
  elseif #result > 0 and result[#result]:sub(1, 1) == " " then
    -- Since the last line of code is indented, the Python REPL
    -- requires and extra newline in order to execute the code
    table.insert(result, newline)
  else
    table.insert(result, "")
  end

  if ptpython then
    table.insert(result, 1, open_code)
    table.insert(result, close_code)
    table.insert(result, "\n")
  end

  return result
end


return common
