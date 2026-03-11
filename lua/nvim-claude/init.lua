--[[
nvim-claude · init.lua
======================
Punto de entrada del plugin. Responsabilidades:
  1. Definir la configuración por defecto.
  2. Inicializar los submódulos (ui, watcher).
  3. Registrar los keymaps globales.

El usuario llama a `require('nvim-claude').setup(opts)` desde su config,
opcionalmente pasando una tabla que sobreescribe los defaults.

Submódulos:
  · nvim-claude.terminal  → gestión de jobs de claude (instancias)
  · nvim-claude.ui        → split izquierdo, tab bar, toggle
  · nvim-claude.watcher   → recarga archivos editados externamente
--]]

local M = {}

-- Valores por defecto. El usuario puede sobreescribir cualquiera via setup().
local defaults = {
  -- Ancho en columnas del split izquierdo donde aparece claude.
  width = 60,

  -- Comando que se ejecuta para lanzar claude.
  -- Debe estar en el PATH del sistema. Se llama igual que desde la terminal.
  claude_cmd = 'claude',

  -- Keymaps en modo normal. Cambia cualquiera pasando keymaps = { ... } a setup().
  keymaps = {
    toggle = '<leader>cc',  -- abrir/cerrar el panel de claude
    new    = '<leader>cn',  -- crear una nueva instancia de claude
    kill   = '<leader>cq',  -- matar la instancia activa
  },
}

--[[
M.setup(opts?)
--------------
Inicializa el plugin. Llámalo una sola vez desde tu config de nvim.

Parámetros:
  opts (table, opcional): Overrides de la configuración por defecto.
    · width      (number) : ancho del panel en columnas. Default: 60
    · claude_cmd (string) : comando para lanzar claude.    Default: 'claude'
    · keymaps    (table)  : { toggle, new, kill }

Ejemplo:
  require('nvim-claude').setup({
    width = 80,
    keymaps = { toggle = '<C-t>' },
  })
--]]
function M.setup(opts)
  -- Mezcla profunda: los opts del usuario sobreescriben los defaults
  -- sin borrar las claves que no se especificaron.
  M.config = vim.tbl_deep_extend('force', defaults, opts or {})

  local ui      = require('nvim-claude.ui')
  local watcher = require('nvim-claude.watcher')

  ui.setup(M.config)   -- registra autocmds de ventana/buffer
  watcher.setup()      -- activa autoread + fs_event watchers

  -- Registrar keymaps globales en modo normal
  local km = M.config.keymaps
  vim.keymap.set('n', km.toggle, function() ui.toggle() end,       { desc = 'Claude: toggle panel' })
  vim.keymap.set('n', km.new,    function() ui.new_instance() end, { desc = 'Claude: nueva instancia' })
  vim.keymap.set('n', km.kill,   function() ui.kill_active() end,  { desc = 'Claude: matar instancia activa' })
end

return M
