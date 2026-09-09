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
| `engineer` | primary | GLM-5.3-Flash | Implementación y orquestación |
| `explore` | subagent | GLM-5.3-Flash (`low`) | Descubrimiento read-only |
| `advisor` | subagent | GPT-5.6 Sol (`high`) | Escalamiento excepcional |
| `document` | subagent | GLM-5.3-Flash | Documentación del estado real |
| `review` | subagent | GLM-5.3-Flash | Auditoría independiente (PASS/CHANGES_REQUIRED) |
| `version` | subagent | GLM-5.3-Flash | Commit local tras PASS; nunca publica |

- `architect` delega automáticamente en `explore` y planifica en dos pasos:
  primero propone el plan en el chat **sin escribir archivos** y pregunta si se
  acepta o se modifica; solo tras una aceptación explícita persiste exactamente
  un roadmap y la documentación de planificación anunciada.
- Tras persistir, `architect` pregunta si se desea implementar. Para continuar,
  cambia manualmente a `engineer` con `Tab` y pídele la ruta exacta del roadmap.
- `engineer` ejecuta el roadmap y delega en los cinco especialistas.
- La continuidad vive en repositorio + roadmap + git, no en la conversación:
  una sesión nueva de `engineer` retoma desde el roadmap.
- `review` es obligatorio antes de versionar (máximo 2 ciclos de corrección).
- `version` puede hacer commit local automático tras PASS; `push`, tags y
  operaciones destructivas permanecen denegadas.
- Uso general no-desarrollo: seguir con `plan` / `build`.

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
