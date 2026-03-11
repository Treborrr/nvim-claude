-- Punto de entrada del plugin para nvim.
-- nvim ejecuta automáticamente los archivos en plugin/ al iniciar.
-- Llama a setup() con la configuración por defecto; el usuario puede
-- llamar a require('nvim-claude').setup(opts) en su propia config
-- para sobreescribir cualquier valor (lazy.nvim lo hace via `opts = {}`).
require('nvim-claude').setup()
