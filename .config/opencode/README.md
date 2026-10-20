# Configuración De OpenCode

Este directorio es la fuente canónica de la configuración personal de OpenCode.
GNU Stow lo expone como `~/.config/opencode`.

## Contenido

- `opencode.json`: configuración pública base cargada en todas las sesiones.
- `config.local.json`: overlay privado mínimo, ignorado por Git; solo diferencias locales.
- `cli.json`: preferencias del terminal v2, locales e ignoradas por Git.
- `AGENTS.md`: reglas globales mínimas; cada repositorio puede ampliarlas.
- `agent/`: agentes genéricos y reutilizables; ubicación compatible con v2.
- `toolbox/examples/`: plantillas públicas de diagnóstico de solo lectura.
- `toolbox/local/`: wrappers y consultas privadas, ignorados por Git.
- `tests/`: validaciones locales que no requieren infraestructura activa.

Las Skills instaladas y los archivos generados por OpenCode no son fuente
canónica de este repositorio.
Se conserva `agent/` para no cambiar rutas existentes; v2 también lo descubre.
Las nuevas instalaciones pueden usar `agents/`. El migrador conserva ambas formas.

## Formato V2 Y Permisos

La base utiliza `agents`, reglas ordenadas `permissions` y `mcp.servers`.
Los modelos y esfuerzos se expresan como `provider/model#variant` en cada agente;
se mantienen los modelos del workflow. El agente `title` usa GPT-5.5.

La compactación automática conserva hasta 15 000 tokens recientes y mantiene un
buffer de 10 000, equivalente a la reserva anterior. No se usa `prune`, que v2
ignora. La profundidad explícita vive en `experimental.subagent_depth: 1`.
Acceder fuera del proyecto solicita permiso mediante `external_directory`.

Los especialistas parten de denegar todas las herramientas y habilitan solo las
necesarias. `review`, `advisor`, `document`, `version` y `architect` no reciben
Code Mode ni herramientas MCP. `explore` sí recibe `execute` y exclusivamente
`jcodemunch_route`, `jcodemunch_menu` y `jcodemunch_order` para consultas de código;
no puede ejecutar shell, editar, habilitar otros MCP ni lanzar hijos. Su prompt
prohíbe indexar, cambiar estado o usar la red desde Code Mode. Estos permisos no
son un sandbox del sistema operativo: `order` depende también de las garantías
del servidor y Code Mode admite `fetch`; no activar herramientas desconocidas.

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

- `architect` delega exploraciones amplias en `explore`, no la lectura de un único
  archivo conocido, y planifica en dos pasos:
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
  detiene con evidencia. Tras el PASS actualiza el índice a `DONE` antes de
  versionar para que el commit incluya ese estado. No edita archivos después del
  commit. Cualquier cambio no mecánico tras PASS exige validar y revisar el delta.
  La lista de trabajo de la sesión es un checklist Markdown, sin exigir una
  herramienta TODO inexistente. Las delegaciones usan `subagent` y se retoman con
  `sessionID`.
- `document` documenta el estado real del producto y no puede modificar
  `docs/roadmap/**`, `AGENTS.md`, `.opencode/**` ni `.config/opencode/**`.
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
  (`subagent` denegado vía `opencode.json`).

## MCP Opcionales

Playwright está declarado en la configuración pública con `disabled: true`.
Grafana, MySQL y cualquier otro MCP privado se declaran exclusivamente en
`config.local.json`, tomando `config.local.example.json` como referencia.
Ningún servidor opcional inicia procesos ni se conecta hasta que lo habilitas
desde el selector MCP de OpenCode.

Usa `/mcps` para conectar o desconectar un servidor o iniciar su autenticación.
La conexión temporal no cambia la configuración; para una activación persistente
cambia su `disabled` en el archivo correspondiente. Context7 utiliza el archivo
de token existente, sin OAuth; Context7 y jcodemunch usan Code Mode.

También puedes revisar todos los estados con `opencode mcp list`.

Para cargar el overlay, la configuración de Zsh define `OPENCODE_CONFIG` solo
cuando `config.local.json` existe. Los archivos privados bajo `toolbox/local/`
pueden contener nombres de infraestructura y no deben copiarse a las plantillas
públicas. Antes de usar un perfil de base de datos, comprueba que la cuenta tenga
exclusivamente permisos de lectura.
El overlay no debe repetir agentes, compactación ni MCP públicos: sus valores
prevalecen sobre la base y podrían ocultar futuras correcciones. Los servidores
privados se declaran bajo `mcp.servers`, con `disabled: true` si son optativos y
timeouts separados en `catalog` y `execution`. El servicio v2 es persistente:
debe recibir `OPENCODE_CONFIG` al arrancar; no basta con exportarlo en una terminal
posterior. Comprobar siempre las fuentes con `opencode debug config`.

## Secretos

Los secretos viven bajo `secrets/` y nunca se versionan. El directorio debe usar
modo `0700` y cada archivo modo `0600`.
El overlay privado usa modo `0600`. `service.json` es estado local generado, no
configuración portable: se ignora en Git y nunca debe copiarse al equipo nuevo.

No incluyas tokens, contraseñas, contenido de clientes o salidas de producción en
prompts enviados a servicios externos de documentación.

## Validación

```bash
bash ~/.config/opencode/tests/test-config.sh
bash ~/.config/opencode/tests/test-config.sh --runtime
opencode debug config >/dev/null
opencode debug agents >/dev/null
opencode api get /api/skill >/dev/null
```

La validación estática usa Python y go-yq (ya incluido en el setup), sin ejecutar
modelos ni conectar infraestructura. Comprueba reglas por su resultado, no solo
por la presencia de texto. `--runtime` compara agentes/permisos con los que carga
el binario v2; requiere OpenCode y no ejecuta los agentes. Evitar publicar las
salidas completas de depuración: pueden incluir configuración privada.

Para aplicar cambios a un servicio ya activo, usar `opencode reload` en un momento
apropiado; no hace falta reiniciar el servicio. Esta configuración no lo recarga
automáticamente. Verificar después modelos, MCP y permisos en el proyecto real.

Referencias: [migración v2](https://opencode.ai/v2/docs/migrate-v1),
[permisos](https://opencode.ai/v2/docs/permissions) y
[skills](https://opencode.ai/v2/docs/skills). Las skills editoriales existentes se
mantienen intactas y se cargan bajo demanda; no hace falta añadir más por sistema.
