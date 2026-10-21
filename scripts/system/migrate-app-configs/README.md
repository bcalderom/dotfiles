# migrate-app-configs

Migración optativa de configuraciones de aplicaciones desde un HOME de respaldo
local o desde el usuario del host antiguo por SSH. La integra `setup.sh`; no
instala paquetes, no copia todo HOME y nunca detiene ni inicia aplicaciones.

## Aplicaciones y rutas permitidas

| Nombre | Rutas relativas al HOME del origen y destino |
| --- | --- |
| `onlyoffice` | `.config/onlyoffice`, `.local/share/onlyoffice` si existen |
| `marktext` | `.config/marktext` |
| `heidisql` | `.config/heidisql` (versión nativa Qt6, no Wine) |
| `chromium` | `.config/chromium` |
| `brave` | `.config/BraveSoftware/Brave-Browser` |
| `teams-for-linux` | `.config/teams-for-linux` (Microsoft Teams for Linux) |
| `thunderbird` | `.thunderbird`, `.config/thunderbird` si existen; incluye correo local |
| `spotify` | `.config/spotify` (sin caché multimedia) |
| `opencode` | Ajustes y definiciones globales de OpenCode v2; selección detallada abajo |
| `ssh` | `.ssh/config`, `.ssh/known_hosts`; identidades solo con `--ssh-key BASENAME` |

Se exige elegir nombres explícitos; no hay un selector `all`. Se omiten cachés
gráficas, Crashpad y locks transitorios. Cookies, preferencias, extensiones y
sesiones guardadas pueden contener información privada: no se muestran sus
valores, no se incluyen en Git y solo se copian con consentimiento explícito.

## SSH: aliases y llaves expresamente autorizadas

Por defecto, `ssh` selecciona únicamente los aliases/configuración y los hosts
conocidos que existan. No recorre ni copia todo `~/.ssh`. Para incluir una llave,
indicar su nombre exacto, relativo a `.ssh`, con una opción por identidad:

```bash
bash setup.sh --configs-only --copy-app-configs-from boris@HOST_ANTIGUO \
  --config-apps ssh --ssh-key id_rsa --dry-run
```

La simulación solo lee metadatos, no el contenido de las llaves. Para ejecutar,
reemplazar `--dry-run` por `--include-private-configs` y escribir en la terminal
`COPY ssh KEYS id_rsa`. La selección de una llave no autoriza otras. Se incluye su
archivo `.pub` solo si existe en el origen; si falta allí pero existe un `.pub`
anterior en destino, se detiene la migración para revisar el par antes de sustituirlo.

Se verifican checksums antes de integrar. La carpeta SSH queda en `700` y los
archivos seleccionados en `600`; los anteriores se respaldan en el lote privado.
`config` y `known_hosts` se **reemplazan con respaldo**, no se fusionan: revisar el
plan para no perder aliases o entradas de confianza nuevas del destino. Las demás
llaves, `authorized_keys`, certificados y sockets de agente quedan intactos. No se
inicia `sshd`, no se cierran sesiones y no se relaja la verificación del servidor.

Solo se admiten archivos normales del usuario, sin enlaces; las llaves privadas
del origen no pueden tener permisos para grupo/otros. No se reescriben rutas
absolutas ni se siguen directivas `Include`: revisar esos archivos por separado.
Los aliases sin `IdentityFile` usan las rutas predeterminadas de OpenSSH, por
ejemplo `~/.ssh/id_rsa`; una llave con otro nombre necesita `IdentityFile` o `-i`.

NetBird **no** es una aplicación migrable con este helper: sus perfiles contienen
identidad de peer. Usar [la configuración explícita de NetBird](../../network/netbird-setup/README.md)
para registrar el nuevo equipo sin clonar claves privadas.

## Uso mediante setup

Desde el **equipo nuevo**, como usuario normal. `HOME_DIR` representa un respaldo
con estructura de HOME, no la carpeta individual de una aplicación:

```bash
bash setup.sh --configs-only --copy-app-configs-from /ruta/al/home-respaldado \
  --config-apps onlyoffice,marktext,heidisql --dry-run
```

Para un origen remoto, ambos hosts necesitan Python 3 y rsync. Preparar la
autenticación SSH y verificar primero la huella del host antiguo por un canal
independiente. El helper usa `BatchMode=yes` y `StrictHostKeyChecking=yes`; no
solicita ni almacena contraseñas SSH. Puede usar la configuración habitual de SSH
o un socket maestro ya autenticado:

```bash
bash setup.sh --configs-only --copy-app-configs-from boris@HOST_ANTIGUO \
  --config-ssh-control-path /ruta/al/socket-existente \
  --config-apps onlyoffice,marktext,heidisql,chromium,brave,teams-for-linux,thunderbird,spotify,opencode \
  --dry-run
```

Cerrar las aplicaciones de escritorio seleccionadas **en ambos hosts** y revisar
la simulación. Los archivos cliente de SSH no requieren cerrar sesiones SSH.
El control se hace por nombres de procesos del usuario; no detecta programas con
nombres personalizados o escritores externos. No abrir las aplicaciones mientras
se realiza la copia. No se mata ningún proceso automáticamente.

Para copiar, reemplazar `--dry-run` por `--include-private-configs`. Se exige una
TTY y escribir la frase `COPY` seguida de los nombres seleccionados separados por
comas, como los muestra el programa. No usar sudo. `--check` también es una
previsualización sin cambios; no prueba que una copia anterior ya se haya aplicado.

## Particularidades de las aplicaciones nuevas

- **Teams for Linux:** incluye preferencias y perfil Electron. La sesión puede
  necesitar reautenticación o el llavero original, que no se copia.
- **Thunderbird:** se copia el perfil completo, con cuentas, filtros, libretas,
  extensiones, correo local y archivos de contraseñas que estén dentro del perfil.
  Puede ocupar mucho más que una configuración. Se omiten `lock`, `.parentlock`,
  `parent.lock`, `cache2` y `startupCache` únicamente para Thunderbird. No se copian
  almacenes de correo externos al perfil ni se reescriben rutas absolutas en
  `profiles.ini` o preferencias. Mantener la ruta de HOME o revisarlas manualmente.
- **Spotify:** incluye preferencias y estado guardado en `.config/spotify`, no las
  descargas/cachés de audio de `.cache/spotify`. Puede requerir iniciar sesión.
- **OpenCode v2 (`opencode`):** dentro de `.config/opencode`, solo se seleccionan
  `cli.json`, `opencode.json`, `opencode.jsonc`, `config.local.json`,
  `config.local.jsonc`, `AGENTS.md` y los directorios `agents/`, `commands/`,
  `skills/`, `plugins/` y `themes/`, si existen. También conserva los directorios
  compatibles `agent/`, `command/` y `skill/`, sin renombrarlos ni perder sus
  recursos auxiliares. `config.local.json(c)` se conserva
  como archivo local del usuario; la copia no valida que OpenCode lo cargue.
  No se reemplaza todo `.config/opencode`: archivos ajenos a la selección quedan
  intactos. Se omiten dependencias `node_modules`, `.git` y `__pycache__`; revisar
  dependencias de plugins en el destino antes de iniciarlos.
  **No incluye** `service.json`, registro/estado del servicio, bases de sesiones,
  logs, cachés ni credenciales externas de proveedores/MCP. Los ajustes copiados
  podrían contener secretos inline, sujetos al consentimiento privado habitual.
  Si hay rutas XDG personalizadas, no se detectan: este helper solo admite las
  rutas de HOME indicadas. Configuraciones de proyecto viajan con sus proyectos.
  Cerrar todos los clientes y detener el servicio de OpenCode **manualmente, con
  trabajo guardado**, en ambos hosts antes de copiar; no ejecutar esta migración
  desde una sesión de OpenCode que siga activa. No se detiene nada automáticamente.

Las rutas gestionadas por Stow que sean enlaces se rechazan para no modificar
indirectamente el repositorio. Restaurar esas rutas mediante Stow; no eliminar ni
reemplazar enlaces a ciegas para forzar la copia.

Referencias de OpenCode v2: [configuración global](https://opencode.ai/v2/docs/config),
[ajustes CLI](https://opencode.ai/v2/docs/cli/config) y
[servicio en segundo plano](https://opencode.ai/v2/docs/cli).

## Seguridad y recuperación

- El destino es el HOME del usuario que ejecuta el helper y debe tener modo `700`.
- Solo se aceptan directorios y archivos normales del usuario. Se rechazan raíces
  enlazadas, enlaces dentro del perfil (salvo locks/cachés omitidos) y archivos
  especiales. No se siguen enlaces a otros datos privados.
- La copia se prepara en un directorio privado, se compara con el origen usando
  `rsync --checksum --dry-run` y solo después se integra en las rutas definitivas.
- Los ajustes existentes no se mezclan: se conservan íntegros en
  `~/.local/state/dotfiles-app-configs/migration-*/backup/`, con un manifiesto
  privado en el mismo lote. Se mantienen permisos y metadatos, pero la propiedad
  queda en el usuario del destino. No se usa `--delete` ni se borra el origen.
- El lote y los perfiles deben estar en el mismo sistema de archivos para moverlos
  sin copiar/borrar el original. Ante fallos se conserva el staging y el respaldo;
  las rutas ya integradas figuran en `manifest.json`. No repetir ni restaurar a
  ciegas: cerrar las aplicaciones y comparar las rutas con ese manifiesto.
- No se copian llaveros, AWS ni otros datos fuera de las rutas indicadas. De SSH
  solo se copian los archivos y las identidades elegidos expresamente, nunca la carpeta entera.
  Las contraseñas/sesiones de navegadores pueden necesitar su llavero original o
  reautenticación. La copia del perfil no garantiza poder descifrarlas.
- No se traducen rutas internas ni se garantiza compatibilidad con versiones
  distintas de la aplicación. Probar la aplicación antes de descartar el respaldo.

## Pruebas

```bash
python3 -B scripts/system/migrate-app-configs/tests/test_migrate_app_configs.py
bash scripts/tests/test-setup.sh
```

Solo utilizan directorios sintéticos temporales; no acceden a perfiles reales ni
ejecutan conexiones SSH. La integración de rsync requiere rsync y un usuario normal.
