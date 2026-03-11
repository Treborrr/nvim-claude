--[[
nvim-claude · watcher.lua
=========================
Recarga automáticamente los buffers de nvim cuando claude (u otro proceso
externo) modifica un archivo en disco.

Problema que resuelve:
  nvim mantiene su propia copia del archivo en memoria (el buffer). Si claude
  edita el archivo desde la terminal, nvim no se entera a menos que el usuario
  ejecute `:checktime` manualmente o cambie de ventana (con autoread).
  Este módulo usa un watcher del sistema de archivos para detectar cambios
  en tiempo real y llamar `:checktime` inmediatamente.

Tecnología usada:
  · vim.loop (alias de libuv) → `new_fs_event()` crea un watcher nativo del SO
    (inotify en Linux, FSEvents en macOS, ReadDirectoryChangesW en Windows).
  · vim.o.autoread = true → le dice a nvim que acepte recargar archivos cuando
    detecta que cambiaron en disco (checktime los recarga si autoread está on).

Flujo:
  setup()        → habilita autoread, registra autocmd para vigilar buffers
  _watch(path, buf) → crea un fs_event handle para ese archivo
  callback       → cuando el archivo cambia, llama checktime en el buffer
  _unwatch(path) → libera el handle cuando el buffer se cierra

Protección contra conflictos:
  Si el buffer tiene cambios sin guardar en nvim (bo.modified = true), NO
  se recarga automáticamente para no pisar el trabajo del usuario.
--]]

local M = {}

-- Tabla de handles activos. Clave: ruta absoluta, valor: handle de fs_event.
-- Se usa para evitar watchers duplicados en el mismo archivo.
M._handles = {}

-- ─── setup ───────────────────────────────────────────────────────────────────

--[[
M.setup()
---------
Inicializa el sistema de watchers. Llamado una vez desde init.lua.

Efectos:
  · Activa vim.o.autoread globalmente.
  · Registra autocmd BufReadPost/BufEnter para vigilar cada buffer que se abra.
--]]
function M.setup()
  -- autoread: nvim recargará el buffer cuando detecte cambios externos
  -- (necesario para que checktime tenga efecto)
  vim.o.autoread = true

  -- Por cada buffer de archivo que se abra, iniciar un watcher
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
    callback = function(ev)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      -- Ignorar buffers sin nombre y buffers de terminal (term://)
      if path == '' or path:match('^term://') then return end
      M._watch(path, ev.buf)
    end,
  })
end

-- ─── Internos ────────────────────────────────────────────────────────────────

--[[
M._watch(path, buf)   [privado]
-------------------------------
Crea un fs_event watcher para el archivo `path`, vinculado al buffer `buf`.

Parámetros:
  path (string) : ruta del archivo (puede ser relativa, se normaliza)
  buf  (number) : handle del buffer de nvim que muestra ese archivo

El watcher se destruye automáticamente cuando el buffer se cierra (on_detach).
--]]
function M._watch(path, buf)
  if M._handles[path] then return end  -- ya hay un watcher para esta ruta

  -- Normalizar a ruta absoluta para consistencia entre llamadas
  local abs = vim.fn.fnamemodify(path, ':p')
  if M._handles[abs] then return end  -- misma ruta, forma absoluta

  local handle = vim.loop.new_fs_event()
  if not handle then return end  -- libuv no pudo crear el handle (raro)

  -- Iniciar el watcher. El callback se invoca cada vez que el archivo cambia.
  -- Los parámetros del callback son (err, filename, events), pero solo usamos err.
  local ok = handle:start(abs, {}, function(err, _, _)
    if err then return end  -- error del SO (archivo eliminado, sin permisos, etc.)

    -- vim.schedule: necesario para llamar a la API de nvim desde un callback
    -- de libuv (que corre en un hilo diferente al loop principal de nvim)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          -- Solo recargar si el buffer no tiene cambios sin guardar.
          -- Protege al usuario de perder ediciones que aún no guardó.
          if not vim.bo[buf].modified then
            vim.cmd('checktime')  -- nvim comprueba si el archivo cambió y recarga
          end
        end)
      else
        -- El buffer ya no existe; limpiar el watcher huérfano
        M._unwatch(abs)
      end
    end)
  end)

  if not ok then return end  -- start() falló (p.ej. archivo no existe todavía)

  M._handles[abs] = handle

  -- Liberar el watcher cuando el buffer se cierre o destruya
  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function()
      M._unwatch(abs)
    end,
  })
end

--[[
M._unwatch(path)   [privado]
-----------------------------
Detiene y libera el watcher del archivo en `path`.
--]]
function M._unwatch(path)
  local handle = M._handles[path]
  if handle then
    pcall(function() handle:stop() end)  -- pcall: handle puede ya estar cerrado
    M._handles[path] = nil
  end
end

return M
