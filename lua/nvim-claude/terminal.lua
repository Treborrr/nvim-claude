--[[
nvim-claude · terminal.lua
==========================
Gestiona las instancias de claude: cada instancia es un proceso `claude`
corriendo dentro de un buffer de terminal de nvim.

Conceptos clave:
  · Instancia  : { id, buf, job, name }
  · buf        : nvim buffer de tipo terminal (`:h terminal`)
  · job        : job_id devuelto por termopen(), usado para matar el proceso
  · bufhidden=hide : cuando se cierra la ventana el buffer NO se destruye,
                     el job sigue corriendo en background. Esto permite
                     ocultar/mostrar el panel sin matar claude.

Flujo de vida:
  create()      → crea el buffer vacío, sin job todavía
  start_job()   → abre el proceso claude dentro del buffer
                  (se llama la primera vez que el buffer se muestra en pantalla)
  kill(id)      → detiene el job y destruye el buffer
  _on_exit(id)  → callback cuando claude termina solo (p.ej. el usuario
                  escribe /exit en claude); limpia estado y notifica a ui.lua
--]]

local M = {}

-- Tabla de instancias activas. Clave: id (number), valor: tabla de instancia.
-- Ejemplo: M.instances[1] = { id=1, buf=5, job=3, name='Claude 1' }
M.instances = {}

-- Contador interno para asignar IDs únicos y crecientes.
local next_id = 1

-- ─── Creación ────────────────────────────────────────────────────────────────

--[[
M.create() → id
---------------
Crea una nueva instancia: reserva un buffer de nvim y registra la instancia
en M.instances. NO lanza el proceso claude todavía (eso lo hace start_job).

Retorna el id asignado a la instancia.
--]]
function M.create()
  local id  = next_id
  next_id   = next_id + 1

  -- Buffer no listado (no aparece en :ls) y de scratch (sin archivo asociado)
  local buf = vim.api.nvim_create_buf(false, true)

  -- bufhidden=hide: al cerrar la ventana, el buffer (y el job) sobreviven.
  -- Sin esto, nvim mataría el proceso al cerrar la ventana.
  vim.bo[buf].bufhidden = 'hide'

  M.instances[id] = {
    id   = id,
    buf  = buf,
    job  = nil,          -- se asigna en start_job()
    name = 'Claude ' .. id,
  }

  return id
end

-- ─── Job ─────────────────────────────────────────────────────────────────────

--[[
M.start_job(id, cmd)
--------------------
Lanza el proceso claude dentro del buffer de la instancia `id`.
Solo se puede llamar cuando el buffer ya está asignado a alguna ventana,
porque termopen() necesita un contexto de ventana activo.

Parámetros:
  id  (number) : id de la instancia
  cmd (string) : comando a ejecutar (normalmente 'claude')

Nota: si el job ya está corriendo, no hace nada (guarda contra doble inicio).
--]]
function M.start_job(id, cmd)
  local inst = M.instances[id]
  if not inst or inst.job then return end  -- ya existe job o instancia inválida

  -- nvim_buf_call ejecuta la función con el buffer `inst.buf` como contexto,
  -- lo que permite que termopen() lo use como buffer de destino.
  vim.api.nvim_buf_call(inst.buf, function()
    inst.job = vim.fn.termopen(cmd, {
      on_exit = function()
        -- vim.schedule para evitar llamar a la API de nvim desde un callback
        -- de libuv (contexto no seguro para la API de nvim)
        vim.schedule(function() M._on_exit(id) end)
      end,
    })
  end)
end

--[[
M._on_exit(id)   [privado]
--------------------------
Callback invocado cuando el proceso claude termina por sí solo.
Limpia el estado de la instancia y notifica a ui.lua para que
actualice la UI (cambiar de instancia o cerrar el panel).
--]]
function M._on_exit(id)
  local inst = M.instances[id]
  if not inst then return end
  inst.job            = nil
  M.instances[id]     = nil
  require('nvim-claude.ui').on_instance_closed(id)
end

-- ─── Destrucción ─────────────────────────────────────────────────────────────

--[[
M.kill(id)
----------
Mata el proceso claude de la instancia `id` y destruye su buffer.
Es la forma explícita de cerrar una instancia (keybind <leader>cq,
o cuando el usuario elimina el buffer con :bd!).
--]]
function M.kill(id)
  local inst = M.instances[id]
  if not inst then return end

  -- jobstop envía SIGTERM al proceso. pcall por si el job ya terminó.
  if inst.job then
    pcall(vim.fn.jobstop, inst.job)
  end

  -- Forzar eliminación del buffer (force=true porque es un terminal activo)
  if vim.api.nvim_buf_is_valid(inst.buf) then
    vim.api.nvim_buf_delete(inst.buf, { force = true })
  end

  M.instances[id] = nil
end

--[[
M.kill_all()
------------
Mata todas las instancias activas. Útil para limpiar al salir de nvim.
--]]
function M.kill_all()
  for id in pairs(M.instances) do
    M.kill(id)
  end
end

-- ─── Consulta ────────────────────────────────────────────────────────────────

--[[
M.get_ordered() → list
----------------------
Retorna una lista de todas las instancias activas ordenadas por id ascendente.
Se usa para renderizar la tab bar en el orden correcto.
--]]
function M.get_ordered()
  local list = {}
  for _, inst in pairs(M.instances) do
    table.insert(list, inst)
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

return M
