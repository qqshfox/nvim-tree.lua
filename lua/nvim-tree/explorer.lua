-- TODOS
-- refresh the tree nodes (for each tree with values, refresh the content if atime or ctime has been changed in the folder)
-- find a node in the fs under the root
-- change root cwd
local uv = vim.loop
local a = vim.api

local M = {}

M.Explorer = {
  cwd = uv.cwd(),
  cursor = nil,
  node_tree = {},
  file_pool = {}
}

local path_sep = vim.fn.has('win32') == 1 and [[\]] or '/'

local function path_join(root, path)
  return root..path_sep..path
end

local node_type_funcs = {
  directory = {
    create = function(parent, name)
      local absolute_path = path_join(parent, name)
      return {
        name = name,
        absolute_path = absolute_path,
        opened = false,
        entries = {}
      }
    end,
    check = function(node)
      return uv.fs_access(node.absolute_path, 'R')
    end
  },
  file = {
    create = function(parent, name)
      local absolute_path = path_join(parent, name)
      local executable = uv.fs_access(absolute_path, 'X')
      return {
        name = name,
        absolute_path = absolute_path,
        executable = executable,
        extension = vim.fn.fnamemodify(name, ':e') or ""
      }
    end
  },
  link = {
    create = function(parent, name)
      local absolute_path = path_join(parent, name)
      local link_to = uv.fs_realpath(absolute_path)
      return {
        name = name,
        absolute_path = absolute_path,
        link_to = link_to
      }
    end,
    check = function(node) return node.link_to ~= nil end
  }
}

function M.Explorer:is_file_ignored(file)
  return (M.config.ignore_dotfiles and file:sub(1, 1) == '.')
    or (M.config.show_ignored and M.config.ignore[file] == true)
end

function M.Explorer:explore(root)
  local cwd = root or self.cwd
  local handle = uv.fs_scandir(cwd)
  if type(handle) == 'string' then
    return nil
  end

  local entries = {
    directory = {},
    symlink = {},
    file = {}
  }

  while true do
    local entry_name, entry_type = uv.fs_scandir_next(handle)
    if not entry_name then break end

    if not self:is_file_ignored(entry_name) then
      local funcs = node_type_funcs[entry_type]
      local entry = funcs.create(cwd, entry_name)

      if not funcs.check or funcs.check(entry) then
        self.file_pool[entry.absolute_path] = 1
        table.insert(entries[entry_type], entry)
      end
    end
  end

  for _, node in pairs(entries.symlink) do
    table.insert(entries.directory, node)
  end
  for _, node in pairs(entries.file) do
    table.insert(entries.directory, node)
  end

  return entries.directory
end

local function find_node(e, row)
  local idx = 1

  local function iter(entries)
    for _, node in ipairs(entries) do
      if idx == row then return node end

      idx = idx + 1
      if node.opened and #node.entries > 0 then
        local n = iter(node.entries)
        if n then return n end
      end
    end
  end

  return iter(e), idx
end

function M.Explorer:get_node_under_cursor()
  local row = a.nvim_win_get_cursor(0)[1]
  if row == 1 then
    return nil
  end
  return find_node(self.node_tree, row-1)
end

function M.Explorer:switch_open_dir(node)
  node.opened = not node.opened

  if not node.opened then return end
  if #node.entries > 0 then return end

  local entries = self:explore(node.absolute_path)
  if entries then
    node.entries = require'nvim-tree.git'.gitify(entries)
  end
end

function M.Explorer:new()
  self.cwd = uv.cwd()
  local entries = self:explore()
  if entries then
    self.node_tree = require'nvim-tree.git'.gitify(entries)
  end

  return self
end

function M.configure(opts)
  M.config = {
    ignore = {},
    show_ignored = opts.show_ignored,
    ignore_dotfiles = opts.hide_dotfiles
  }

  for _, ignore_pattern in ipairs(opts.ignore) do
    M.config.ignore[ignore_pattern] = true
  end
end

return M
