# nvim-claude

Plugin de Neovim que integra [Claude Code](https://claude.ai/code) como un panel lateral persistente con soporte para múltiples instancias simultáneas.

```
┌──────────────────────┬──────────────────────────────────┐
│ Claude 1  Claude 2 [+]                                   │
│──────────────────────│                                   │
│                      │         Tu editor                 │
│   Claude Code        │                                   │
│                      │                                   │
└──────────────────────┴──────────────────────────────────┘
```

## Características

- **Panel toggle** — abre y cierra el panel sin matar el proceso de claude
- **Multi-instancia** — crea varias sesiones de claude y cambia entre ellas desde una tab bar clickeable
- **Recarga automática** — cuando claude edita un archivo, nvim lo recarga en tiempo real sin perder el foco

## Requisitos

- Neovim >= 0.9
- `claude` instalado y disponible en el PATH

## Instalación

### lazy.nvim

```lua
{
  dir = '~/Documents/nvim-claude',
}
```

Con opciones personalizadas:

```lua
{
  dir = '~/Documents/nvim-claude',
  opts = {
    width = 80,
    keymaps = {
      toggle = '<C-t>',
      new    = '<C-n>',
      kill   = '<C-q>',
    },
  },
}
```

### Manual

```lua
-- en tu init.lua
vim.opt.runtimepath:prepend('~/Documents/nvim-claude')
require('nvim-claude').setup()
```

## Configuración

| Opción           | Default         | Descripción                          |
|------------------|-----------------|--------------------------------------|
| `width`          | `60`            | Ancho del panel en columnas          |
| `claude_cmd`     | `'claude'`      | Comando para lanzar claude           |
| `keymaps.toggle` | `<leader>cc`    | Abrir / cerrar el panel              |
| `keymaps.new`    | `<leader>cn`    | Nueva instancia de claude            |
| `keymaps.kill`   | `<leader>cq`    | Matar la instancia activa            |

## Uso

| Acción                  | Cómo                              |
|-------------------------|-----------------------------------|
| Abrir / cerrar panel    | `<leader>cc`                      |
| Nueva instancia         | `<leader>cn` o click en `[+]`     |
| Cambiar de instancia    | Click en la pestaña               |
| Matar instancia activa  | `<leader>cq`                      |
| Cerrar sin matar claude | `:q` en el panel (el proceso sigue vivo) |

## Licencia

MIT
