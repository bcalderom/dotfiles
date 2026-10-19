# Instalar Arch Linux reemplazando Ubuntu

Guía operativa para el equipo nuevo, usando el USB ya preparado con **Arch Linux
2026.10.01**, el instalador `install_arch.py` y el bootstrap `setup.sh`.

> **El particionado elimina Ubuntu y todos los datos del SSD elegido.** No es
> dual boot, no conserva `/home` de Ubuntu y no se debe ejecutar en el host antiguo.
> Hacer una copia independiente y comprobarla antes de autorizar el borrado.
> Leer la guía completa antes de empezar; ejecutar cada bloque en su fase, no
> pegar todo el documento como un script.

## 1. Resultado previsto y responsabilidades

| Elemento | Configuración |
| --- | --- |
| Equipo | AMD Ryzen AI 5 430, 16 GB RAM, SSD interno de aproximadamente 500/512 GB |
| Arranque | UEFI, GPT, systemd-boot; sin GRUB y sin dual boot |
| Partición 1 | ESP FAT32 de 2 GiB, montada en `/boot` |
| Partición 2 | ext4 de 100 GiB, montada en `/` |
| Partición 3 | ext4 con el espacio restante, montada en `/home` |
| Swap | Zram zstd, mitad de RAM hasta 8 GiB; sin hibernación ni swap en disco |
| Cifrado | No; el SSD y sus datos no estarán cifrados |
| Cuenta | `boris`, UID/GID 1000, sudo con contraseña; root bloqueado |
| Región | `America/Santiago`, `en_US.UTF-8`, teclado de consola `us` |
| Hostname | `arch-ryzen` |

Un SSD anunciado como 500 GB tiene unos 465,7 GiB: es normal que la capacidad
mostrada por Linux sea menor. El generador reserva espacio de alineación/GPT y
calcula `/home` según la capacidad real; no usa tamaños copiados del host antiguo.

Hay dos scripts con funciones diferentes:

- **`install_arch.py`**, como root **desde la ISO en el equipo nuevo**: particiona,
  formatea, instala Arch, kernel/firmware AMD, NetworkManager, systemd-boot y cuenta.
- **`setup.sh`**, como **`boris` después de arrancar Arch desde el SSD**: instala
  herramientas, escritorio y aplicaciones; opcionalmente habilita servicios y
  enlaza dotfiles. No particiona ni instala el sistema base.

El instalador admite **archinstall 4.5.x**, incluido en esta ISO. Su código y el
setup tienen pruebas simuladas. El sistema base y los paquetes se comprobaron en
el equipo nuevo, tras recuperar un fallo de permisos del primer intento; esto no
equivale a una validación completa del escritorio ni de todas las funciones del
hardware. Las comprobaciones de seguridad no sustituyen la copia de seguridad ni
la comprobación del disco.

## 2. Preparación antes de borrar Ubuntu

En el equipo nuevo, todavía desde Ubuntu:

1. Guardar documentos, proyectos y cualquier archivo que se quiera conservar.
   Revisar también datos ocultos y aplicaciones con bases de datos locales.
2. Comprobar la copia en otro almacenamiento; si interesa conservar una vía de
   recuperación del fabricante, prepararla antes de eliminar sus particiones.
3. Anotar modelo, capacidad y serial del SSD. No asumir que se llamará
   `/dev/nvme0n1`, ni que conservará el mismo nombre al arrancar la ISO.
4. Conectar el equipo a corriente. Tener el host antiguo disponible en la red
   para transferir el kit, o llevarlo en otro medio independiente.

En el firmware del equipo nuevo:

- Elegir arranque **UEFI**, no Legacy/CSM.
- Para este procedimiento sin firma propia, desactivar Secure Boot si impide
  arrancar la ISO oficial o el sistema nuevo. **No borrar las claves del firmware
  ni limpiar el TPM**. Si la política del equipo exige Secure Boot, detenerse y
  diseñar antes el flujo de firma; no está automatizado aquí.
- No cambiar ajustes de almacenamiento arbitrariamente. Registrar cualquier cambio
  necesario para poder diagnosticarlo después.

### Material preparado

Directorio en el host antiguo:

```text
/home/boris/Downloads/arch-migration-nl1vvxc7/
```

Contiene la ISO `archlinux-2026.10.01-x86_64.iso`, su firma y los kits separados.
La ISO se verificó con PGP/SHA256 y el USB Kingston se comparó byte a byte tras
grabarlo. **El instalador y el setup no están dentro de ese USB**: hay que
transferirlos por red u otro medio; no es necesario volver a grabar la ISO.

Para llevar también esta guía, usar el kit actualizado:

```text
setup-kit-automated-guide.tar.gz
setup-kit-automated-guide.tar.gz.sha256
```

El kit anterior `setup-kit-automated.tar.gz` no contiene esta guía ni la corrección
para copytoram. Usar la versión actualizada de `setup-kit-automated-guide.tar.gz`,
no reextraer un kit anterior encima del instalador corregido. Los kits no incluyen
dotfiles completos, contraseñas, perfiles de navegador ni otros datos personales.

## 3. Arrancar la ISO y conectar Internet

**Lugar: equipo nuevo, terminal root de la ISO.**

Arrancar el USB desde el menú UEFI y elegir la entrada normal de instalación
Arch Linux x86_64. Comprobar:

```bash
test -d /sys/firmware/efi/efivars
findmnt --noheadings --output FSTYPE --target /
archinstall --version
```

El primer comando debe terminar sin error; el segundo debe mostrar `overlay` y
archinstall debe ser `4.5` o `4.5.x`. Si no coincide, no omitir la protección de
versión ni actualizar paquetes aislados para intentar forzarla.

Es normal que `/run/archiso/bootmnt` no exista si la ISO se copió a RAM. El
instalador actualizado acepta `copytoram` tras verificar overlay, squashfs de
solo lectura, tmpfs y la imagen real del dispositivo loop; no se debe montar un
directorio artificial ni eliminar la comprobación para continuar.

La consola está prevista en US. Si el teclado físico es distinto, comprobar su
distribución antes de escribir contraseñas; el perfil instalado usa `us`.

### Ethernet o Wi-Fi

Con Ethernet, comprobar primero si ya hay conexión. Para Wi-Fi:

```bash
iwctl
```

Dentro de `iwctl`, sustituir `wlan0` por la interfaz que muestre `device list`:

```text
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "TU_SSID"
exit
```

Introducir la clave solo cuando se solicite: no incluirla en un argumento ni
compartirla en el chat. La configuración Wi-Fi del entorno live no se transporta
en el kit ni se copia automáticamente al Arch instalado.

Comprobar red y hora:

```bash
ip -brief address
curl --fail --head https://archlinux.org/
timedatectl status
```

Si falla DNS, TLS o la conexión, resolverlo antes del particionado. No continuar
con portales cautivos pendientes ni usar opciones para saltarse las comprobaciones.

## 4. Transferir y verificar el kit

**Lugar: root de la ISO, con el host antiguo accesible por SSH.** No es necesario
habilitar un servidor SSH en el equipo nuevo para descargar desde el antiguo.

Sustituir `IP_HOST_ANTIGUO`. Antes de aceptar una clave SSH por primera vez,
comparar su huella con la del host antiguo mediante un canal independiente. Si
SSH no está disponible, usar otro medio; no cambiar su autenticación a ciegas.

```bash
scp boris@IP_HOST_ANTIGUO:/home/boris/Downloads/arch-migration-nl1vvxc7/setup-kit-automated-guide.tar.gz /root/
scp boris@IP_HOST_ANTIGUO:/home/boris/Downloads/arch-migration-nl1vvxc7/setup-kit-automated-guide.tar.gz.sha256 /root/
cd /root
sha256sum --check setup-kit-automated-guide.tar.gz.sha256
tar -tzf setup-kit-automated-guide.tar.gz
mkdir /root/arch-migration
tar -xzf setup-kit-automated-guide.tar.gz -C /root/arch-migration
cd /root/arch-migration
```

Debe aparecer `OK` para el checksum. Revisar el listado antes de extraer; usar un
directorio nuevo, sin archivos propios. Si `mkdir` indica que ya existe, revisar
su contenido y elegir otro destino: no borrarlo ni extraer encima automáticamente.

Este kit funciona aunque los cambios todavía no estén publicados en GitHub. No
suponer que un clon del repositorio por sí solo contiene el instalador actualizado.

## 5. Identificar el SSD y revisar el particionado

**Lugar: root de la ISO. Solo lectura en este paso.**

```bash
lsblk -o NAME,PATH,TRAN,RM,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL
python3 scripts/system/install-arch/install_arch.py --list-disks
ls -l /dev/disk/by-id/
```

Identificar por **modelo + capacidad + serial** el SSD interno que contiene Ubuntu.
No elegir el Kingston USB, un disco de respaldo ni una ruta que termine en
`-part1`, `-part2`, etc. El perfil solo admite un disco interno de aproximadamente
500/512 GB y no acepta dispositivos removibles.

Definir la ruta real del SSD completo, preferentemente por su identificador:

```bash
DISK=/dev/disk/by-id/REEMPLAZAR_POR_EL_SSD_REAL
INSTALLER=scripts/system/install-arch/install_arch.py
python3 "$INSTALLER" --disk "$DISK"
```

**Sin `--install` no se formatea nada.** Revisar las particiones existentes, el
serial y las tres particiones nuevas. Se eliminarán también las particiones EFI,
swap, recuperación o `/home` que pertenezcan a Ubuntu en ese SSD.

Si se detectan montajes, swap activa, LUKS/LVM/RAID o consumidores del dispositivo,
el script se detiene. No usar `swapoff -a`, desactivar todos los grupos LVM ni
desmontar discos indiscriminadamente. Revisar qué está activo y sobre qué disco
antes de decidir cómo liberarlo. `/mnt` debe estar vacío y sin montajes.

No hay que ejecutar antes `fdisk`, `wipefs`, `mkfs` ni formatear desde Ubuntu:
**el instalador se encarga de la tabla GPT y los sistemas de archivos** después
de la confirmación. Este particionado tampoco equivale a un borrado seguro del SSD.

## 6. Instalar Arch y establecer la contraseña

**Punto destructivo: root de la ISO, solo en el SSD confirmado del equipo nuevo.**

```bash
python3 "$INSTALLER" --disk "$DISK" --install
```

El wrapper comprueba el entorno y la configuración con `archinstall --dry-run`
antes de solicitar el permiso de borrado. Para autorizarlo hay que escribir:

```text
BORRAR SERIAL_REAL_DEL_SSD
```

Usar el serial exacto que muestra el programa, no el texto del ejemplo. No hay
selección automática ni `--yes`. Después de esa autorización, archinstall trabaja
en modo automático: mantener corriente/red y esperar sin interrumpir.

Se instalan el sistema base, kernel, firmware/microcódigo AMD, systemd-boot,
NetworkManager, herramientas para continuar, zram y la cuenta con sudo. **Todavía
no se instalan Hyprland ni los demás programas de `setup.sh`.**

Al acabar y verificar el sistema, aparecerá `passwd` para establecer la contraseña
de `boris`. Escribirla y confirmarla localmente; no se muestra ni se guarda en el
kit. Hasta entonces la cuenta está bloqueada con `!`, no con contraseña vacía.
Root queda bloqueado y se utilizará sudo después del primer arranque.

Si hay un error, conservar el mensaje y no reiniciar sin comprobar el estado.
**No repetir el instalador como reparación: volvería a borrar el SSD.** Si solo
falló/cancelaste la contraseña y el destino sigue correctamente montado:

```bash
arch-chroot /mnt passwd boris
arch-chroot /mnt passwd -S boris
```

El estado de `boris` debe ser `P`. Para otros fallos, diagnosticar primero las
particiones y los montajes; no asumir que el sistema quedó instalado.

Si falla D-Bus al configurar el teclado dentro del contenedor temporal, revisar
los permisos del destino. Una sesión lanzada con umask `077` puede dejar `/etc`
en `700` y ciertos metadatos de pacman ilegibles para usuarios normales. El script
actual fuerza `022` solo para los procesos de archinstall, conserva el JSON en
`0600` y comprueba después consultas de pacman como `boris`. No resolver este caso
con un chmod recursivo ni repitiendo `--install`: una recuperación requiere
verificar las particiones existentes y usar `pre_mounted_config` sin borrado.

## 7. Comprobar systemd-boot y `bootctl`

**`bootctl` es una herramienta de systemd, no un paquete llamado `bootctl`.** Al
seleccionar systemd-boot, archinstall ya instala el cargador mediante esa herramienta
y genera la entrada del kernel. No hay que instalar GRUB ni repetir normalmente
`bootctl install`.

**Lugar: root de la ISO, después de una instalación satisfactoria.**

```bash
findmnt --mountpoint /mnt
findmnt --mountpoint /mnt/home
findmnt --mountpoint /mnt/boot
arch-chroot /mnt bootctl --esp-path=/boot is-installed
arch-chroot /mnt bootctl --esp-path=/boot list
ls -l /mnt/boot/EFI/systemd/systemd-bootx64.efi
ls -l /mnt/boot/vmlinuz-linux /mnt/boot/initramfs-linux.img
```

Esperado: ext4 en `/mnt` y `/mnt/home`, vfat en `/mnt/boot`, systemd-boot instalado,
y una entrada para el kernel `linux`. `bootctl is-installed` debe terminar con
éxito. El wrapper también revisa fstab, zram y los archivos de arranque.

Desde la ISO, el cargador **actualmente en ejecución** es el del USB; eso no
demuestra qué cargador se usará al arrancar el SSD. La comprobación definitiva de
`bootctl status` se hace después de reiniciar sin el USB.

### Solo si hay que reinstalar el cargador

Antes, verificar que `/mnt` y su `/boot` corresponden al **SSD nuevo confirmado** y
que existen kernel, initramfs y entradas correctas. Si el problema es únicamente
la instalación del cargador, desde la ISO UEFI:

```bash
arch-chroot -S /mnt bootctl --esp-path=/boot install
```

Este comando **escribe en la ESP y puede modificar las entradas UEFI/NVRAM**;
no es un diagnóstico de solo lectura. `-S` evita la limitación de namespaces del
chroot normal al registrar la entrada UEFI. No repara por sí solo una instalación
incompleta, ni genera los archivos del kernel o una entrada de arranque ausente.

La entrada esperada del firmware es **Linux Boot Manager**. Puede seguir figurando
una entrada antigua `ubuntu` en NVRAM aunque el SSD ya se haya reformateado: no
significa que Ubuntu siga instalado. No borrar entradas de otros discos a ciegas.

## 8. Conservar el kit y arrancar desde el SSD

**Lugar: root de la ISO, con instalación y cuenta verificadas.**

```bash
install -o 1000 -g 1000 -m 0644 /root/setup-kit-automated-guide.tar.gz /mnt/home/boris/setup-kit-automated-guide.tar.gz
install -o 1000 -g 1000 -m 0644 /root/setup-kit-automated-guide.tar.gz.sha256 /mnt/home/boris/setup-kit-automated-guide.tar.gz.sha256
sync
```

Cuando se hayan cerrado procesos que usen `/mnt` y no haya errores pendientes:

```bash
cd /root
umount -R /mnt
reboot
```

Si el desmontaje falla, averiguar qué lo mantiene ocupado; no usar desmontaje
forzado como solución genérica. Retirar el USB cuando el equipo reinicie o elegir
**Linux Boot Manager** del SSD en el menú del firmware.

## 9. Primer arranque: entrar como `boris` y reconectar

**Lugar: Arch instalado en el SSD, usuario `boris`, inicialmente en Bash.**

```bash
whoami
hostnamectl
findmnt /
findmnt /boot
sudo bootctl --esp-path=/boot status
sudo bootctl --esp-path=/boot list
systemctl is-active NetworkManager
nmcli device status
```

Esperado: usuario `boris`, hostname `arch-ryzen`, raíz del SSD y systemd-boot como
cargador actual, no el USB. Confirmar también que puedes usar sudo.

Para Wi-Fi, puede ser necesario configurar de nuevo la conexión:

```bash
nmcli device wifi list
nmcli --ask device wifi connect "TU_SSID"
curl --fail --head https://archlinux.org/
```

La clave se solicita de forma interactiva. Si faltan permisos de red en la
consola, usar `sudo nmcli --ask device wifi connect "TU_SSID"`, sin añadir la
contraseña a la línea de comandos. No poner en marcha simultáneamente otros
gestores de red para intentar resolver el mismo enlace.

## 10. Obtener la versión actual de los dotfiles

La configuración actual del host antiguo está en la rama **`lenovo`**. La rama
predeterminada `main` puede ser más antigua. Como `boris`, en un HOME nuevo sin un
checkout previo con trabajo propio:

```bash
cd "$HOME"
git clone --branch lenovo https://github.com/bcalderom/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
git log -1 --oneline
bash setup.sh --list-groups
```

HTTPS evita necesitar una clave SSH privada para el primer clon. Si la versión
actual ya está publicada, usar ese checkout: **no extraer encima un kit anterior**.
El kit complementa el repositorio, no sustituye los dotfiles completos. Solo si
contiene cambios necesarios que todavía no están publicados, revisar su versión
y contenido antes de aplicarlo en un clon recién creado y sin cambios propios:

```bash
cd "$HOME"
sha256sum --check setup-kit-automated-guide.tar.gz.sha256
tar -tzf "$HOME/setup-kit-automated-guide.tar.gz"
tar -xzf "$HOME/setup-kit-automated-guide.tar.gz" -C "$HOME/dotfiles"
```

Si `~/dotfiles` ya existe o contiene cambios, detenerse y comparar antes: no
sobrescribirlo automáticamente. Revisar los ajustes de hardware del host antiguo.
**No ejecutar todavía `stow .` ni cambiar el shell a Zsh.**

## 11. Instalar paquetes oficiales y AUR

**Todos los comandos `setup.sh` y `makepkg` de esta sección se ejecutan como
`boris`, no con `sudo bash` ni desde root.** El setup solicita sudo solo donde hace
falta y mantiene las confirmaciones de pacman y del gestor AUR.

### 11.1 Seleccionar los paquetes

Los grupos predeterminados cubren shell, desarrollo, Hyprland, UI, audio, red,
Bluetooth, fuentes, Kanata y VPN; incluyen, entre otros, Neovim, tmux, sesh,
OpenCode, AWS CLI, Brave y Dolphin. CPU y GPU se detectan de forma independiente.
No se debe instalar el perfil Intel en el Ryzen.

Para instalar **también todos los grupos de aplicaciones opcionales actuales**:

```bash
EXTRAS=docker,printing,obs,office,comms,media,optional
bash setup.sh --dry-run --with "$EXTRAS"
```

| Grupo adicional | Incluye |
| --- | --- |
| `docker` | Docker y Compose |
| `printing` | CUPS, descubrimiento de impresoras y escáner |
| `obs` | OBS Studio |
| `office` | Calibre, Pandoc, Thunderbird, OnlyOffice y MarkText |
| `comms` | Teams y Zoom |
| `media` | mpv, FFmpeg y Spotify |
| `optional` | Diagnósticos y utilidades adicionales |

Revisar el listado completo que imprime el setup; los paquetes efectivos están
definidos en sus arrays, no en esta tabla abreviada. Eliminar de `EXTRAS` los grupos
que no se quieran. Para solo lo habitual, omitir `--with "$EXTRAS"` **en todos los
comandos siguientes y en la comprobación final**.

Si la GPU no se detecta o aparece NVIDIA, resolver sus controladores antes de
abrir Hyprland. `--cpu amd --gpu amd` solo debe usarse después de comprobar que
ambos componentes corresponden a esos perfiles; no identifica hardware remoto.

### 11.2 Instalar primero los paquetes oficiales

```bash
bash setup.sh --with "$EXTRAS"
```

Se hace una transacción completa `pacman -Syu --needed`. No usar `pacman -Sy` ni
`--no-update` para saltarse una actualización pendiente. Si se actualiza el kernel,
tener presente que sus módulos nuevos se usan tras reiniciar.

En una instalación limpia faltarán paquetes AUR. En ese caso el script instala
los oficiales, muestra **`Pending manual AUR review/install`** y termina con
código **1**: aún no está completo. No confundir ese caso con un error de pacman,
red o firmas. Si falló una transacción oficial, resolverla antes de continuar;
no ocultar el error ni encadenar estos pasos con un `|| true`.

### 11.3 Preparar un único gestor AUR

El setup no instala yay/paru automáticamente. Si se elige yay, los paquetes
oficiales anteriores ya deben haber instalado `base-devel` y `git`:

```bash
mkdir -p "$HOME/aur-builds"
git clone https://aur.archlinux.org/yay.git "$HOME/aur-builds/yay"
cd "$HOME/aur-builds/yay"
less PKGBUILD .SRCINFO
```

Antes de construir, revisar fuentes, dependencias y cualquier archivo `.install`
o parche referenciado. Los PKGBUILD son código ejecutable, no solo metadatos.
Si ese directorio ya existe, revisar su estado: no borrarlo ni sobrescribirlo.

Solo tras aprobar lo revisado, como usuario normal:

```bash
makepkg -si
yay --version
```

No ejecutar `sudo makepkg`. Respetar las preguntas de revisión y las firmas de
las fuentes; no desactivarlas para forzar una compilación. Paru es una alternativa,
pero no hace falta instalar ambos gestores.

### 11.4 Completar los grupos seleccionados

```bash
cd "$HOME/dotfiles"
EXTRAS=docker,printing,obs,office,comms,media,optional
bash setup.sh --with "$EXTRAS" --aur yay
```

Si elegiste menos grupos antes, conservar esa selección en `EXTRAS`; la asignación
mostrada es el ejemplo completo. Con paru ya revisado/instalado, sustituir
`--aur yay` por `--aur paru`. No pasar `--noconfirm` ni desactivar comprobaciones
de construcción. Resolver los errores antes de configurar el escritorio.

## 12. Enlazar dotfiles y habilitar servicios

Antes de enlazar, revisar las configuraciones de pantalla, teclado, tapa y rutas
del host anterior. El escritorio usa una configuración Lua de Hyprland: confirmar
compatibilidad con la versión instalada. Consultar la documentación de pantallas
y de los scripts en el repositorio.

```bash
cd "$HOME/dotfiles"
bash setup.sh --dry-run --with "$EXTRAS" --aur yay --enable-services --stow
bash setup.sh --with "$EXTRAS" --aur yay --enable-services --stow
```

- `--stow` realiza una simulación real antes de enlazar; si hay conflictos, se
  detiene. Comparar/respaldar manualmente los archivos propios, incluido `.zshrc`,
  antes de repetir; no usar `--adopt` para absorberlos sin revisión.
- `--enable-services` habilita red/hora, Bluetooth y energía según los grupos,
  **pero no inicia servicios**. No habilita SSH, Docker, CUPS ni las VPN.
- Kanata y el servicio de tapa requieren revisar y ejecutar sus despliegues
  específicos. Esos scripts sí escriben configuración y arrancan/reinician sus
  servicios; hacerlo conscientemente después de revisar el hardware nuevo.
- Los plugins de Zsh, Neovim y tmux necesitan su preparación/red. TPM figura como
  gitlink sin garantizar contenido tras el clon: no suponer que `git submodule
  update` lo resolverá. Seguir las instrucciones del repositorio y fuentes oficiales.

`~/.zshrc` intenta iniciar Hyprland automáticamente al entrar por **tty1**. Mantener
Bash hasta completar dependencias y plugins. Para probar Zsh sin disparar ese
arranque, abrir **tty2** con `Ctrl+Alt+F2`, entrar como `boris` y verificar `tty`
antes de abrir `zsh`. No cambiar el shell hasta que esa prueba sea satisfactoria.

Cuando ya esté listo, cambiar el shell como `boris`:

```bash
chsh -s /usr/bin/zsh
```

Reiniciar de forma normal cuando se hayan guardado los trabajos y resuelto los
errores, para usar el kernel actual y activar las unidades habilitadas. No instalar
un gestor gráfico de login adicional sin necesidad: este entorno arranca desde TTY.

## 13. Comprobación final y migración de datos

Con la **misma selección de grupos** utilizada al instalar:

```bash
cd "$HOME/dotfiles"
EXTRAS=docker,printing,obs,office,comms,media,optional
bash setup.sh --check --with "$EXTRAS" --enable-services --stow
sudo bootctl --esp-path=/boot status
systemctl --failed
systemctl --user --failed
zramctl
swapon --show
```

El check del setup debe terminar con código 0; eso comprueba paquetes, unidades
consultadas y ausencia de conflictos de Stow, **no** autenticación, plugins,
rendimiento físico ni que todos los enlaces ya estuvieran creados. Comprobar:

- Arranque desde SSD sin USB y uso de systemd-boot.
- Red/DNS, GPU, monitor interno/externo, teclado y touchpad.
- Sonido/micrófono, Bluetooth, suspensión/reanudación y tapa.
- Neovim, tmux/sesh/tds, OpenCode y proyectos de trabajo.
- Configuración/autenticación separada de AWS, VPN, Docker e impresión.
- Dependencias de Python/Node recreadas, sin asumir portabilidad de entornos viejos.

Restaurar los datos seleccionados por red siguiendo la guía de migración. No copiar
encima `/etc`, fstab, claves de host SSH, configuración EFI ni perfiles Intel del
host antiguo. Tampoco restaurar a ciegas configuraciones de Ubuntu sobre Arch.
Mantener el host antiguo y las copias hasta comprobar datos y herramientas.

## Referencias

- [Instalador: controles y recuperación](../scripts/system/install-arch/README.md)
- [Migración de datos y configuración](migration.md)
- [Pantallas, tapa y audio](display-setup/README.md)
- [Guía oficial de Arch](https://wiki.archlinux.org/title/Installation_guide)
- [systemd-boot y bootctl](https://wiki.archlinux.org/title/Systemd-boot)
- [AUR](https://wiki.archlinux.org/title/Arch_User_Repository)

Esta guía prepara el procedimiento; escribirla o distribuir el kit **no ejecuta
el particionado, no modifica Ubuntu y no autoriza borrar otros dispositivos**.
