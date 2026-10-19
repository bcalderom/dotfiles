# Migración a un nuevo host Arch

Para reemplazar Ubuntu en el equipo nuevo, seguir primero la
[guía de instalación paso a paso](arch-installation.md): ISO, particionado,
systemd-boot/bootctl y paquetes del setup. Este documento amplía la transferencia
de datos y las decisiones de migración.

Destino previsto: Ryzen AI 5 430, SSD de 500 GB, Arch sin cifrado,
usuario `boris`, conexión a Internet y transferencia por red desde el host antiguo.
Este procedimiento no autoriza por sí mismo a borrar ningún dispositivo.

## 1. ISO oficial y USB

1. Descargar la ISO vigente y su firma desde <https://archlinux.org/download/>.
2. Verificar la firma siguiendo la [guía oficial de instalación](https://wiki.archlinux.org/title/Installation_guide#Acquire_an_installation_image).
   Usar un llavero de confianza; un checksum por sí solo no autentica la descarga.
3. Identificar el USB por modelo, capacidad y ruta. Confirmar el dispositivo
   completo antes de grabarlo: **la grabación borra su contenido**.
4. Grabar la ISO como imagen con una herramienta apropiada. No basta con copiar
   el archivo `.iso` a una partición normal.

El setup no va dentro de la ISO. Mantenerlo en el repositorio o transferir el
kit separado por red. Un USB grabado como imagen no se debe tratar como un
almacenamiento escribible para añadir scripts o datos personales.

No se genera una ISO personalizada ni se incluyen credenciales, perfiles de
navegador o datos privados en el medio de instalación.

## 2. Instalar el sistema base

Arrancar la ISO y comprobar primero red, GPU, almacenamiento, UEFI y estado de
Secure Boot. Para este hardware reciente usar una ISO, kernel y firmware actuales.
La GPU y el adaptador Wi-Fi exactos todavía deben comprobarse en el equipo nuevo.

Para automatizar esta fase está disponible el
[instalador protegido del sistema base](../scripts/system/install-arch/README.md).
Usa archinstall **4.5.x**, incluido en la ISO 2026.10.01. El kit actualizado es
`setup-kit-automated.tar.gz`: transferirlo por red a la ISO; no hay que volver a
grabar el USB ni publicar/commitear los cambios para usar ese kit.

Previsualización ficticia, sin acceso a discos:

```bash
python3 scripts/system/install-arch/install_arch.py --example
```

Desde la ISO, elegir explícitamente el SSD y revisar modelo/capacidad/serial.
El wrapper se detiene si el disco está en uso o no coincide con el perfil, valida
el JSON sin instalar y exige escribir `BORRAR SERIAL_DEL_SSD` antes de iniciar
archinstall en modo automático. No existe selección automática ni flag `--yes`.
Al terminar establece la contraseña de `boris` directamente mediante `passwd`;
no se guarda una contraseña en el kit/JSON y no se reinicia automáticamente.

También se puede seguir la guía oficial o ejecutar `archinstall` manualmente.
El perfil aprobado es:

- Disco: comprobar modelo y capacidad del SSD destino, no asumir `/dev/nvme0n1`.
- Sin dual boot y sin cifrado, según la decisión del usuario.
- UEFI/GPT: ESP de 2 GiB, `/` ext4 de 100 GiB y `/home` ext4 con el resto.
- 16 GB de RAM; zram zstd con mitad de RAM, máximo 8 GiB. Sin swap en disco ni
  hibernación.
- Kernel `linux`, firmware `linux-firmware` y microcódigo `amd-ucode`.
- Cargador UEFI, por ejemplo systemd-boot; comprobar su entrada de arranque.
- Usuario `boris` con sudo, hostname `arch-ryzen`, zona `America/Santiago`, locale
  `en_US.UTF-8` y consola `us`. Root permanece bloqueado.
- Perfil mínimo, NetworkManager y paquetes `git`, `stow`, `pciutils`, `openssh`
  y `rsync`. Habilitar la conectividad para el primer arranque.

No copiar `/etc`, `fstab`, entradas EFI ni identificadores de máquina del host
Intel. No restaurar automáticamente `thermald`, claves SSH de host ni ajustes
de almacenamiento antiguos. Antes de migrar datos, comparar `id boris` en ambos
hosts para revisar UID/GID y permisos.

## 3. Preparar el setup en el nuevo host

Ejecutar como `boris`, después de arrancar el Arch instalado, no desde la ISO:

```bash
git clone --branch lenovo https://github.com/bcalderom/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
bash setup.sh --list-groups
bash setup.sh --dry-run
```

HTTPS evita necesitar una clave privada para el primer clon. La configuración
actual del host antiguo está en `lenovo`, no en la rama predeterminada `main`;
revisar igualmente los ajustes específicos del hardware. Si estos cambios
todavía no están publicados, transferir explícitamente `setup.sh`,
`docs/migration.md`, `scripts/tests/test-setup.sh` y `README.md` al checkout nuevo.
No transferir a ciegas todo el directorio local de dotfiles: contiene archivos
ignorados y estado local que Git no transporta.

Si se utiliza el archivo `setup-kit.tar.gz`, es un complemento del repositorio,
no una copia completa de los dotfiles. Transferirlo por red, revisar su contenido
y extraerlo **solo en un checkout recién clonado, sin trabajo local que sobrescribir**:

```bash
tar -tzf setup-kit.tar.gz
tar -xzf setup-kit.tar.gz -C "$HOME/dotfiles"
```

El kit automatizado nuevo incluye además el instalador base y sus pruebas. Usar
`setup-kit-automated.tar.gz` en los comandos anteriores si se recibió esa versión.
Ningún kit incluye dotfiles completos, estado local ni credenciales. Después,
repetir la previsualización. Si la rama publicada ya contiene la versión actual,
usar ese checkout sin extraer encima un kit anterior.

La detección distingue CPU y GPU. Si ya se confirmó que la GPU es AMD, se puede
previsualizar el destino explícitamente, incluso desde el host Intel:

```bash
bash setup.sh --dry-run --cpu amd --gpu amd
```

Esto no comprueba físicamente el hardware remoto. Si hay NVIDIA o una GPU no
identificada, revisar sus controladores antes de iniciar Hyprland.

### Selección basada en uso

La selección se revisó usando recuentos locales de nombres de ejecutables del
historial, paquetes instalados, atajos y dependencias de configuraciones. El
setup **no lee el historial**, no guarda sus comandos y no incorpora telemetría.
La ausencia de un programa en el historial no demuestra que no se utilice.

| Grupo | Contenido / motivo |
| --- | --- |
| `base` | SSH/rsync, Neovim, Zsh, Git, tmux, fzf, fd, eza y herramientas de scripts |
| `dev` | OpenCode/tds/sesh, AWS CLI, GitHub CLI, LazyGit, Node, Python/pyenv/uv y compilación |
| `hypr`, `ui` | Escritorio existente, Brave, Dolphin, captura, bloqueo, notificaciones y tapa |
| `audio`, `network`, `bluetooth`, `fonts` | Dependencias de un escritorio funcional |
| `keyboard`, `vpn` | Kanata, NordVPN y NetBird; configuración/autenticación aparte |
| `amd`, `intel`, `amd-gpu`, `intel-gpu` | Microcódigo y gráficos independientes, según detección |
| `docker` | Docker y Compose; no arranca ni habilita Docker |
| `printing` | CUPS, descubrimiento y escáner; controladores y colas aparte |
| `obs` | OBS; consultar también el verificador existente |
| `office` | Calibre, Pandoc, Thunderbird, OnlyOffice y MarkText |
| `comms`, `media` | Teams/Zoom y mpv/FFmpeg/Spotify |
| `optional` | Herramientas de diagnóstico adicionales |

Los primeros seis renglones son predeterminados. Docker, impresión, OBS,
ofimática, comunicaciones, multimedia y diagnósticos se eligen explícitamente:

```bash
bash setup.sh --dry-run --with docker,printing,obs,office,comms,media
```

`--only base,dev` selecciona exactamente esos grupos, sin escritorio ni hardware
automático. Para incluir hardware en esa modalidad, usar por ejemplo
`--only base,dev,amd,amd-gpu`. `--with` añade grupos y no elimina los predeterminados.
Ningún perfil desinstala programas existentes.

### Repositorios oficiales y AUR

```bash
bash setup.sh
```

El setup realiza una actualización completa e instalación con `pacman -Syu
--needed`, respetando sus confirmaciones. Los paquetes AUR no se instalan por
defecto: se listan como pendientes y la ejecución termina con código **1** si
faltan. No interpretar ese resultado como una instalación completa del escritorio.

No se descarga ni se ejecuta automáticamente un instalador de yay/paru. Si se
quiere usar AUR, instalar y revisar primero **uno** de estos gestores siguiendo
la [documentación de AUR](https://wiki.archlinux.org/title/Arch_User_Repository).
Revisar PKGBUILD, archivos de instalación, fuentes y cambios antes de construir.
Después, como usuario normal:

```bash
bash setup.sh --aur yay
# O, si se eligió paru:
bash setup.sh --aur paru
```

No usar sudo para ejecutar el setup con AUR o Stow. Solo las operaciones que
necesitan privilegios invocan sudo. Los helpers conservan sus preguntas de revisión.
Un paquete antes externo que ya exista en un repositorio habilitado se trata
como paquete de repositorio.

`--no-update` omite la sincronización y actualización; usarlo solo inmediatamente
después de una actualización completa exitosa. Nunca hacer `pacman -Sy` seguido
de instalaciones aisladas. Si una transacción falla, resolverla antes de continuar.

### Servicios y dotfiles: acciones explícitas

```bash
bash setup.sh --dry-run --aur yay --enable-services --stow
bash setup.sh --aur yay --enable-services --stow
```

Añadir los mismos `--with` o `--only` a cada ejecución si se usan perfiles propios.
`--enable-services` solo habilita para el próximo arranque las unidades de red,
hora, Bluetooth y energía cuyos grupos estén seleccionados. **No las inicia**, ni
habilita SSH, Docker, CUPS o VPN. Revisar conflictos de gestores de red existentes.
La configuración DNS/resolved y sus enlaces se revisa aparte; no se modifica.

`--stow` hace una simulación real antes de enlazar y se detiene ante conflictos.
No usa `--adopt` ni sobrescribe archivos. Excluye documentación y el propio setup
de los enlaces a HOME. También excluye directorios systemd `.wants` y `.requires`:
son estado de habilitación local, que se debe recrear mediante systemctl después
de revisar los servicios, no enlazar desde el repositorio. Comparar o respaldar
manualmente cualquier archivo en conflicto, incluido el `.zshrc` creado por otro
instalador, antes de repetir.

El `.zshrc` actual intenta iniciar Hyprland al entrar por tty1: no cambiar el shell
a Zsh hasta completar los paquetes, revisar la configuración y preparar los plugins.

## 4. Transferencia de datos por red

Se observaron unos 49 GB utilizados en `/home`; confirmar tamaño final y espacio
libre del destino. Mantener el host antiguo disponible hasta terminar la validación.
Una transferencia entre equipos **no sustituye una copia de seguridad independiente**.

1. Instalar `rsync` también en el host antiguo, con una transacción completa de
   pacman cuando se decida hacerlo. El inventario inicial no lo encontró.
2. En el host nuevo, arrancar SSH solo cuando se autorice y comprobar su clave de
   host por un canal independiente antes de aceptar la conexión. No copiar claves
   privadas ni claves de host para resolver el acceso inicial.
3. Preparar `~/migration-incoming` en el nuevo host. Copiar primero a ese staging,
   no encima del HOME configurado.
4. Seleccionar directorios reales: proyectos, documentos y libros. Incluir cambios
   sin commit, archivos ocultos y archivos necesarios ignorados por Git. No excluir
   globalmente `.env` si contiene configuración necesaria: tratarlo aparte como secreto.

Ejemplo desde HOME del host antiguo, **solo para los directorios mostrados**:

```bash
cd "$HOME"
DEST=boris@IP_NUEVO
ssh "$DEST" 'mkdir -p "$HOME/migration-incoming"'
rsync -aHAXS --no-owner --no-group --relative --dry-run --itemize-changes -- \
  ./Desarrollos/ ./Downloads/boris/ "${DEST}:migration-incoming/"
```

Revisar nombres, destino y salida localmente; puede contener rutas privadas. Quitar
`--dry-run` solo después de aprobar la selección. Repetir con `--checksum --dry-run
--itemize-changes` para verificar contenido y metadatos. No ignorar errores de ACL,
xattrs o permisos. No se usa `--delete`; esta comprobación no detecta archivos
sobrantes en destino. Los enlaces se conservan, no se siguen; comprobar sus destinos.
El receptor conserva la propiedad de `boris`, no se fuerzan UID/GID del host viejo.

Cerrar las aplicaciones afectadas antes de la sincronización final, con autorización
del usuario. No copiar bases SQLite activas, volúmenes Docker o bases de datos en
escritura como si fueran documentos: usar copias consistentes/exportaciones y
restauraciones específicas. Revisar volúmenes que vivan fuera de `/home`.

Integrar únicamente las rutas verificadas en su ubicación final. Si ya existen,
comparar antes de reemplazar; no hacer una restauración genérica encima de HOME.

### Estado privado: revisión independiente

Seleccionar expresamente qué conservar y por qué, sin incluirlo en Git ni en la ISO:

- SSH/GPG, AWS, VPN y tokens de herramientas; preferir reautenticar o rotar cuando
  proceda. Revisar identidades y permisos por separado.
- Perfiles de navegador, correo, Obsidian, OBS y aplicaciones de escritorio.
- Estado y sesiones de herramientas de desarrollo, y configuraciones locales que
  el repositorio excluye. No asumir que clonar los dotfiles restaura todo ese estado.
- Versiones pyenv, herramientas uv, dependencias y archivos de bloqueo de proyectos.
  Recrear entornos virtuales, módulos nativos y `node_modules`; no copiarlos como
  garantía de compatibilidad con el nuevo sistema.

## 5. Pasos finales y aceptación

- Revisar descriptores de monitores, escala y rutas de dispositivo:
  [documentación de pantallas](display-setup/README.md). El panel del portátil
  anterior está identificado explícitamente en `hyprland.lua`.
- Verificar que la versión instalada de Hyprland acepta la configuración Lua.
- Instalar los plugins de Neovim y Zsh desde sus fuentes revisadas. La configuración
  de Zsh descarga Zinit/plugins al abrirse por primera vez: necesita red.
- Revisar TPM: el repositorio registra `.config/tmux/plugins/tpm` como gitlink, sin
  garantizar que un clon descargue su contenido. Obtener TPM de su fuente oficial
  en esa ruta si falta, y usar su instalador de plugins. No sobrescribir uno existente.
- Revisar y desplegar Kanata y el servicio de tapa con sus scripts existentes solo
  cuando se autoricen los cambios y arranques que realizan:
  [Kanata](../scripts/keyboard/kanata-deploy/README.md) y
  [tapa](../scripts/desktop/hypr-lid-deploy/README.md).
- Configurar VPN, impresión, Docker y servicios remotos por separado, sin copiar
  ciegamente reglas o identidades de red del host antiguo.
- Para OBS, ejecutar primero `bash scripts/obs/setup-obs/setup-obs.sh --check-only`.
- Configurar versión de Python y recrear entornos; probar proyectos representativos,
  AWS, SSH, OpenCode, `tds`, sesh y selección de sesiones.
- Comprobar arranque sin USB, red/DNS, GPU, audio/micrófono, Bluetooth, teclado,
  suspensión/reanudación, tapa y monitores externos.
- Cambiar el shell con `chsh -s /usr/bin/zsh` solo tras completar esas revisiones.

Diagnóstico repetible, sin cambios:

```bash
bash setup.sh --check --enable-services --stow
```

Usar la misma selección de grupos que al instalar. Código 0 significa que los
paquetes seleccionados están instalados, los servicios consultados habilitados y
Stow no encuentra conflictos; **no** garantiza autenticación, plugins, que los
enlaces ya estén creados ni funcionamiento físico del hardware. No retirar ni
borrar el host antiguo hasta comprobar los datos y las herramientas de trabajo.

## Pruebas del setup

```bash
bash -n setup.sh scripts/tests/test-setup.sh
shellcheck setup.sh scripts/tests/test-setup.sh
bash scripts/tests/test-setup.sh
bash scripts/tests/test-script-structure.sh
python3 -B scripts/system/install-arch/tests/test_install_arch.py
```

Las pruebas de instalación usan comandos simulados y un HOME temporal: no instalan
paquetes, no cambian servicios ni enlazan los dotfiles reales. Si Stow está disponible
y se ejecutan como usuario normal, también prueban enlaces reales exclusivamente
en un checkout y HOME generados dentro del directorio temporal.
