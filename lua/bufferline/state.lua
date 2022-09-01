--
-- m.lua
--

local table_insert = table.insert
local table_remove = table.remove

local buf_get_name = vim.api.nvim_buf_get_name
local buf_get_option = vim.api.nvim_buf_get_option
local buf_get_var = vim.api.nvim_buf_get_var
local buf_set_var = vim.api.nvim_buf_set_var
local list_bufs = vim.api.nvim_list_bufs
local list_extend = vim.list_extend
local tbl_filter = vim.tbl_filter

local Buffer = require'bufferline.buffer'
local utils = require'bufferline.utils'

local PIN = 'bufferline_pin'

--------------------------------
-- Section: Application state --
--------------------------------

--- @class bufferline.State.Data
--- @field closing boolean whether the buffer is being closed
--- @field name nil|string the name of the buffer
--- @field position nil|integer the absolute position of the buffer
--- @field real_width nil|integer the width of the buffer + invisible characters
--- @field width nil|integer the width of the buffer - invisible characters

--- @class bufferline.State
--- @field is_picking_buffer boolean whether the user is currently in jump-mode
--- @field buffers table<integer> the open buffers, in visual order.
--- @field buffers_by_id table<integer, bufferline.State.Data> the buffer data
local State = {
  is_picking_buffer = false,
  buffers = {},
  buffers_by_id = {},
}

--- Get the state of the `id`
--- @param id integer the `bufnr`
--- @return bufferline.State.Data
function State.get_buffer_data(id)
  local data = State.buffers_by_id[id]

  if data ~= nil then
    return data
  end

  State.buffers_by_id[id] = {
    closing = false,
    name = nil,
    position = nil,
    real_width = nil,
    width = nil,
  }

  return State.buffers_by_id[id]
end

--- Get the list of buffers
function State.get_buffer_list()
  local opts = vim.g.bufferline
  local buffers = list_bufs()
  local result = {}

  --- @type nil|table
  local exclude_ft   = opts.exclude_ft
  local exclude_name = opts.exclude_name

  for _, buffer in ipairs(buffers) do
    if not buf_get_option(buffer, 'buflisted') then
      goto continue
    end

    if not utils.is_nil(exclude_ft) then
      local ft = buf_get_option(buffer, 'filetype')
      if utils.has(exclude_ft, ft) then
        goto continue
      end
    end

    if not utils.is_nil(exclude_name) then
      local fullname = buf_get_name(buffer)
      local name = utils.basename(fullname)
      if utils.has(exclude_name, name) then
        goto continue
      end
    end

    table_insert(result, buffer)

    ::continue::
  end

  return result
end

-- Pinned buffers

--- @param bufnr integer
--- @return boolean pinned `true` if `bufnr` is pinned
function State.is_pinned(bufnr)
  local ok, val = pcall(buf_get_var, bufnr, PIN)
  return ok and val
end

--- Sort the pinned tabs to the left of the bufferline.
function State.sort_pins_to_left()
  local unpinned = {}

  local i = 1
  while i <= #State.buffers do
    if State.is_pinned(State.buffers[i]) then
      i = i + 1
    else
      table_insert(unpinned, table_remove(State.buffers, i))
    end
  end

  State.buffers = list_extend(State.buffers, unpinned)
end

--- Toggle the `bufnr`'s "pin" state.
--- WARN: does not redraw the bufferline. See `Render.toggle_pin`.
--- @param bufnr integer
function State.toggle_pin(bufnr)
  buf_set_var(bufnr, PIN, not State.is_pinned(bufnr))
  State.sort_pins_to_left()
end

-- Open/close buffers

--- Close the `bufnr`.
--- @param bufnr integer
--- @param do_name_update nil|boolean refreshes all buffer names iff `true`
function State.close_buffer(bufnr, do_name_update)
  State.buffers = tbl_filter(function(b) return b ~= bufnr end, State.buffers)
  State.buffers_by_id[bufnr] = nil

  if do_name_update then
    State.update_names()
  end
end

-- Read/write state

-- Return the bufnr of the buffer to the right of `buffer_number`
-- @param buffer_number int
-- @return int|nil
function State.find_next_buffer(buffer_number)
  local index = utils.index_of(State.buffers, buffer_number)
  if index == nil then return nil end
  if index + 1 > #State.buffers then
    index = index - 1
    if index <= 0 then
      return nil
    end
  else
    index = index + 1
  end
  return State.buffers[index]
end

--- Update the names of all buffers in the bufferline.
function State.update_names()
  local opts = vim.g.bufferline
  local buffer_index_by_name = {}

  -- Compute names
  for i, buffer_n in ipairs(State.buffers) do
    local name = Buffer.get_name(opts, buffer_n)

    if buffer_index_by_name[name] == nil then
      buffer_index_by_name[name] = i
      State.get_buffer_data(buffer_n).name = name
    else
      local other_i = buffer_index_by_name[name]
      local other_n = State.buffers[other_i]
      local new_name, new_other_name =
        Buffer.get_unique_name(
          buf_get_name(buffer_n),
          buf_get_name(State.buffers[other_i]))

      State.get_buffer_data(buffer_n).name = new_name
      State.get_buffer_data(other_n).name = new_other_name
      buffer_index_by_name[new_name] = i
      buffer_index_by_name[new_other_name] = other_i
      buffer_index_by_name[name] = nil
    end

  end
end

--- @deprecated exists for backwards compatability
function State.set_offset(width, text, hl)
  vim.notify(
    "`require'bufferline.state'.set_offset` is deprecated, use `require'bufferline.render'.set_offset` instead",
    vim.log.levels.WARN,
    {title = 'barbar.nvim'}
  )
  require'bufferline.render'.set_offset(width, text, hl)
end

-- Exports
return State
