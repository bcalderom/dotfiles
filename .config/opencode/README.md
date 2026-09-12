# Configuración De OpenCode

Este directorio es la fuente canónica de la configuración personal de OpenCode.
GNU Stow lo expone como `~/.config/opencode`.

## Contenido

- `config.json`: configuración base cargada en todas las sesiones.
- `AGENTS.md`: reglas globales mínimas; cada repositorio puede ampliarlas.
- `agent/`: subagentes genéricos y reutilizables.
- `toolbox/`: wrapper y consultas de diagnóstico MySQL de solo lectura.
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
  (`task` denegado vía `config.json`).

## MCP Opcionales

Playwright, Grafana y MySQL están declarados con `enabled: false`. No inician
procesos, no se conectan ni publican herramientas hasta que los habilitas desde
el selector MCP de OpenCode.

Abre la paleta con `Ctrl+;`, busca la opción de MCP y cambia el interruptor del
servidor requerido. Vuelve a cambiarlo para desconectarlo. La activación dura
solo durante la instancia actual; al reiniciar vuelve al valor de `config.json`.

También puedes revisar todos los estados con `opencode mcp list`.

Los perfiles MySQL comparten el mismo usuario y contraseña. Antes de utilizarlos,
comprueba en cada destino que la cuenta mantenga exclusivamente permisos de
lectura. El wrapper no modifica grants ni configuración del servidor.

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
