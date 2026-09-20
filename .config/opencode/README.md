# Configuración De OpenCode

Este directorio es la fuente canónica de la configuración personal de OpenCode.
GNU Stow lo expone como `~/.config/opencode`.

## Contenido

- `opencode.json`: configuración pública base cargada en todas las sesiones.
- `config.local.json`: overlay privado opcional, ignorado por Git.
- `AGENTS.md`: reglas globales mínimas; cada repositorio puede ampliarlas.
- `agent/`: subagentes genéricos y reutilizables.
- `toolbox/examples/`: plantillas públicas de diagnóstico de solo lectura.
- `toolbox/local/`: wrappers y consultas privadas, ignorados por Git.
- `tests/`: validaciones locales que no requieren infraestructura activa.

Las Skills instaladas y los archivos generados por OpenCode no son fuente
canónica de este repositorio.

## Workflow Multiagente De Desarrollo

Junto a los agentes nativos `plan` y `build` (sin modificar) existe un workflow
de desarrollo con dos agentes primary y cinco subagentes ocultos:

| Agente | Tipo | Modelo | Función |
|---|---|---|---|
| `architect` | primary | GPT-5.6 Sol (`medium`) | Planificación y roadmap persistente |
| `engineer` | primary | GPT-5.6 Luna (`medium`) | Implementación y orquestación |
| `explore` | subagent | GPT-5.6 Luna (`low`) | Descubrimiento read-only |
| `advisor` | subagent | GPT-5.6 Sol (`high`) | Escalamiento excepcional |
| `document` | subagent | GPT-5.6 Luna (`low`) | Documentación del estado real |
| `review` | subagent | GPT-5.6 Luna (`medium`) | Auditoría independiente (PASS/CHANGES_REQUIRED) |
| `version` | subagent | GPT-5.6 Luna (`low`) | Commit local tras PASS; nunca publica |

- `architect` delega automáticamente en `explore` y planifica en dos pasos:
  primero propone el plan en el chat **sin escribir archivos** y pregunta si se
  acepta o se modifica; solo tras una aceptación explícita persiste exactamente
  un roadmap, la documentación de planificación anunciada y el índice
  (`docs/roadmap/INDEX.md`, con el estado `ACTIVE`/`DONE`/`BLOCKED`/`SUPERSEDED`
  de cada roadmap). Su edición está limitada por permisos a `docs/roadmap/**`;
  si el repositorio usa otra convención, solicita una excepción a nivel de
  proyecto en lugar de escribir fuera de alcance.
- Tras persistir, `architect` pregunta si se desea implementar. Para continuar,
  cambia manualmente a `engineer` con `Tab` y pídele la ruta exacta del roadmap.
- `engineer` ejecuta el roadmap y delega en los cinco especialistas. Ante fallos
  de subagente reintenta una sola vez con contexto corregido; el segundo fallo
  detiene con evidencia. Tras versionar, marca el roadmap como `DONE` en el
  índice.
- `document` documenta el estado real del producto y no puede modificar
  `docs/roadmap/**`, `AGENTS.md` ni `.opencode/**`.
- La continuidad vive en repositorio + roadmap + git, no en la conversación:
  una sesión nueva de `engineer` retoma desde el roadmap activo del índice.
- `review` es obligatorio antes de versionar (máximo 2 ciclos de corrección).
- `version` puede hacer commit local automático tras PASS; exige una lista
  explícita de archivos esperados, deniega `git add .`/`-A`/`--all`,
  `git commit --amend` y `--no-verify`; `push`, tags y operaciones destructivas
  permanecen denegadas.
- Uso general no-desarrollo: seguir con `plan` / `build`. `build` no ofrece las
  garantías del workflow (sin roadmap, review ni versionado); úsalo sabiéndolo.
  El subagente nativo `general` no puede lanzar especialistas del pipeline
  (`task` denegado vía `opencode.json`).

## MCP Opcionales

Playwright está declarado en la configuración pública con `enabled: false`.
Grafana, MySQL y cualquier otro MCP privado se declaran exclusivamente en
`config.local.json`, tomando `config.local.example.json` como referencia.
Ningún servidor opcional inicia procesos ni se conecta hasta que lo habilitas
desde el selector MCP de OpenCode.

Abre la paleta con `Ctrl+;`, busca la opción de MCP y cambia el interruptor del
servidor requerido. Vuelve a cambiarlo para desconectarlo. La activación dura
solo durante la instancia actual; al reiniciar vuelve al valor de `opencode.json`.

También puedes revisar todos los estados con `opencode mcp list`.

Para cargar el overlay, la configuración de Zsh define `OPENCODE_CONFIG` solo
cuando `config.local.json` existe. Los archivos privados bajo `toolbox/local/`
pueden contener nombres de infraestructura y no deben copiarse a las plantillas
públicas. Antes de usar un perfil de base de datos, comprueba que la cuenta tenga
exclusivamente permisos de lectura.

## Secretos

Los secretos viven bajo `secrets/` y nunca se versionan. El directorio debe usar
modo `0700` y cada archivo modo `0600`.

No incluyas tokens, contraseñas, contenido de clientes o salidas de producción en
prompts enviados a servicios externos de documentación.

## Validación

```bash
bash ~/.config/opencode/tests/test-config.sh
opencode debug config >/dev/null
opencode agent list
opencode debug skill
```

Reinicia OpenCode después de cambiar configuración, agentes o definiciones MCP.
