--[[
nvim-claude · ui.lua
====================
Controla toda la interfaz visual del plugin:
  · El split izquierdo fijo donde se muestra el terminal de claude.
  · La tab bar (winbar) en la parte superior del split, con una pestaña
    por instancia y un botón [+] para crear nuevas.
  · El toggle (mostrar/ocultar) sin matar los jobs.

Layout resultante:
  ┌──────────────┬──────────────────────────┐
  │ Claude 1 [+] │                          │
  │──────────────│      Editor (nvim)       │
  │              │                          │
  │   Terminal   │                          │
  │   claude     │                          │
  └──────────────┴──────────────────────────┘

Estado del módulo:
  M.win       → handle de la ventana izquierda (nil si está oculta)
  M.active_id → id de la instancia visible en este momento
  M.visible   → bool, refleja si el panel está abierto

Tab bar (winbar):
  Se construye con la sintaxis de statusline de nvim. Las regiones clickeables
  usan `%@v:lua.FuncName@label%X`. Los handlers se registran en _G para que
  nvim pueda llamarlos desde el contexto de Vimscript.
--]]

local M = {}
local terminal = require('nvim-claude.terminal')

-- Estado del panel
M.config    = {}
M.win       = nil    -- ventana izquierda activa (nil = oculta)
M.active_id = nil    -- id de la instancia mostrada actualmente
M.visible   = false  -- true mientras el split está en pantalla

-- ─── setup ───────────────────────────────────────────────────────────────────

--[[
M.setup(config)
---------------
Registra los autocmds necesarios para el ciclo de vida del panel.
Llamado una vez desde init.lua.

Autocmds registrados:
  · BufDelete  : si se elimina un buffer de claude (p.ej. :bd!), mata el job.
  · WinClosed  : si el usuario cierra la ventana con :q, actualiza M.visible.
--]]
function M.setup(config)
  M.config = config

  -- Detectar eliminación forzada de un buffer de claude (:bd!, etc.)
  vim.api.nvim_create_autocmd('BufDelete', {
    callback = function(ev)
      for id, inst in pairs(terminal.instances) do
        if inst.buf == ev.buf then
          terminal.kill(id)
          -- Si era la instancia activa, cambiar a otra o cerrar el panel
          if M.active_id == id then
            local rest = terminal.get_ordered()
            if #rest > 0 then
              M.active_id = rest[1].id
              M._set_buf()
              M._update_winbar()
            else
              M.visible = false
              M.win     = nil
            end
          end
          break
        end
      end
    end,
  })

  -- Detectar cierre de la ventana con :q (no destruye el buffer ni el job,
  -- solo cierra la ventana; bufhidden=hide mantiene el job vivo)
  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      if closed_win == M.win then
        M.win     = nil
        M.visible = false
      end
    end,
  })
end

-- ─── toggle / show / hide ────────────────────────────────────────────────────

--[[
M.toggle()
----------
Alterna la visibilidad del panel. Si está visible lo oculta; si está oculto
lo muestra (reutilizando los jobs existentes si los hay).
--]]
function M.toggle()
  if M.visible and M.win and vim.api.nvim_win_is_valid(M.win) then
    M.hide()
  else
    M.show()
  end
end

--[[
M.show()
--------
Abre el split izquierdo y muestra la instancia activa (o crea una nueva
si no existe ninguna). Configura las opciones de ventana y pone el cursor
en modo terminal (startinsert).
--]]
function M.show()
  -- Si no hay instancias, crear la primera automáticamente
  local instances = terminal.get_ordered()
  if #instances == 0 then
    M.active_id = M.new_instance()
  elseif not M.active_id or not terminal.instances[M.active_id] then
    -- Instancia activa inválida (fue matada); usar la primera disponible
    M.active_id = terminal.get_ordered()[1].id
  end

  local width = M.config.width or 60

  -- `topleft Nvsplit` abre un split vertical en el extremo izquierdo de la pantalla,
  -- empujando todo el contenido existente a la derecha.
  vim.cmd('topleft ' .. width .. 'vsplit')
  M.win     = vim.api.nvim_get_current_win()
  M.visible = true

  -- Opciones visuales de la ventana: limpia de decoraciones innecesarias
  local wo = vim.wo[M.win]
  wo.number         = false   -- sin números de línea
  wo.relativenumber = false   -- sin números relativos
  wo.signcolumn     = 'no'    -- sin columna de signos (git, lsp, etc.)
  wo.wrap           = false   -- sin wrap (las líneas de claude pueden ser largas)
  wo.winfixwidth    = true    -- ancho fijo: otros splits no lo comprimen

  M._set_buf()         -- asigna el buffer de la instancia activa a la ventana
  M._update_winbar()   -- renderiza la tab bar
  vim.cmd('startinsert')
end

--[[
M.hide()
--------
Oculta la ventana sin destruir los buffers ni los jobs.
Los procesos de claude siguen corriendo en background.
--]]
function M.hide()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    -- nvim_win_hide cierra la ventana pero mantiene el buffer y el job
    vim.api.nvim_win_hide(M.win)
  end
  M.win     = nil
  M.visible = false
end

-- ─── Gestión de instancias ───────────────────────────────────────────────────

--[[
M.new_instance() → id
---------------------
Crea una nueva instancia de claude y la muestra en el panel (si está abierto).
Retorna el id de la nueva instancia.
--]]
function M.new_instance()
  local id    = terminal.create()
  M.active_id = id

  -- Si el panel ya está visible, cambiar a la nueva instancia inmediatamente
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M._set_buf()
    M._update_winbar()
    vim.cmd('startinsert')
  end

  return id
end

--[[
M.switch_to(id)
---------------
Cambia la instancia visible en el panel a la instancia con el id dado.
Llamado al hacer click en una pestaña de la tab bar.
--]]
function M.switch_to(id)
  if not terminal.instances[id] then return end
  M.active_id = id
  M._set_buf()
  M._update_winbar()
  vim.cmd('startinsert')
end

--[[
M.kill_active()
---------------
Mata la instancia actualmente visible. on_instance_closed() se encarga
de actualizar la UI después (cambiar a otra instancia o cerrar el panel).
--]]
function M.kill_active()
  if M.active_id then
    terminal.kill(M.active_id)
    -- terminal.kill() → _on_exit() → on_instance_closed() (vía terminal.lua)
  end
end

--[[
M.on_instance_closed(id)
------------------------
Callback invocado por terminal.lua cuando un job de claude termina
(sea porque el usuario escribió /exit, o porque se llamó kill()).
Actualiza la UI: cambia a otra instancia o cierra el panel si no quedan más.
--]]
function M.on_instance_closed(id)
  if M.active_id == id then
    -- La instancia visible cerró; buscar otra para mostrar
    local rest = terminal.get_ordered()
    if #rest > 0 then
      M.active_id = rest[1].id
      if M.win and vim.api.nvim_win_is_valid(M.win) then
        M._set_buf()
        M._update_winbar()
      end
    else
      -- No quedan instancias: cerrar el panel
      M.hide()
    end
  else
    -- Una instancia de fondo cerró; solo actualizar la tab bar
    M._update_winbar()
  end
end

-- ─── Internos ────────────────────────────────────────────────────────────────

--[[
M._set_buf()   [privado]
------------------------
Asigna el buffer de M.active_id a M.win. Si el job no ha iniciado todavía,
lo arranca ahora (lazy start: el job solo comienza cuando el buffer se muestra).
--]]
function M._set_buf()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  local inst = terminal.instances[M.active_id]
  if not inst then return end

  vim.api.nvim_win_set_buf(M.win, inst.buf)

  -- Inicio diferido del job: si es la primera vez que se muestra este buffer,
  -- lanzar el proceso claude ahora.
  if not inst.job then
    terminal.start_job(M.active_id, M.config.claude_cmd)
  end
end

--[[
M._update_winbar()   [privado]
------------------------------
Construye y aplica la tab bar (winbar) de la ventana izquierda.

Formato de cada pestaña:
  %@v:lua.NvimClaude_switchN@%#HL# Nombre %X
  └── clickeable ──────────────────────────┘

  %@v:lua.FuncName@  → inicio de región clickeable, llama a FuncName al hacer click
  %X                 → fin de región clickeable
  %#NombreHL#        → aplicar highlight group

Los handlers de click se registran en _G (tabla global de Lua) porque nvim
necesita acceder a ellos desde el contexto de Vimscript via `v:lua.FuncName`.

Firma de los handlers: function(minwid, clicks, button, mods)
  · button: 'l' = clic izquierdo, 'r' = derecho, 'm' = medio
--]]
function M._update_winbar()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end

  local instances = terminal.get_ordered()
  local parts     = {}

  for _, inst in ipairs(instances) do
    -- La pestaña activa usa TabLineSel (más brillante); las demás usan TabLine
    local hl      = (inst.id == M.active_id) and '%#TabLineSel#' or '%#TabLine#'
    local fn_name = 'NvimClaude_switch' .. inst.id

    -- Registrar el handler de click en la tabla global de Lua
    _G[fn_name] = function(_, _, btn, _)
      if btn == 'l' then require('nvim-claude.ui').switch_to(inst.id) end
    end

    table.insert(parts, string.format('%%@v:lua.%s@%s %s %%X', fn_name, hl, inst.name))
  end

  -- Botón [+] para crear una nueva instancia con un click
  _G['NvimClaude_new'] = function(_, _, btn, _)
    if btn == 'l' then require('nvim-claude.ui').new_instance() end
  end
  table.insert(parts, '%@v:lua.NvimClaude_new@%#TabLine# [+] %X')

  -- Unir con separador y aplicar al winbar de la ventana izquierda
  vim.wo[M.win].winbar = table.concat(parts, '%#TabLine# ')
end

return M
