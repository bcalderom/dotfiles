# install-arch

Para el recorrido completo desde Ubuntu hasta el escritorio y las aplicaciones,
consultar la [guía de instalación paso a paso](../../../docs/arch-installation.md).

Instalación automatizada del sistema base para el equipo nuevo. Se ejecuta desde
la ISO oficial **2026.10.01**, con **archinstall 4.5.x**. Es independiente de
`setup.sh`: el primero prepara el SSD y el sistema; el segundo configura el entorno
personal después del primer arranque.

La comprobación del live admite tanto el medio ISO montado en `bootmnt` como
`copytoram`, donde ese montaje puede desaparecer. En ambos casos se exige la raíz
overlay de archiso sobre squashfs de solo lectura; para RAM también se comprueba
el tmpfs y que el loop utilice `/run/archiso/copytoram/airootfs.sfs`. No hay una
opción para desactivar esta protección.

## Perfil aprobado

- SSD interno de aproximadamente 500/512 GB; selección explícita, nunca automática.
- UEFI/GPT, systemd-boot, sin cifrado y sin conservar otro sistema operativo.
- ESP FAT32 de 2 GiB en `/boot`, ext4 de 100 GiB en `/`, ext4 con el resto en `/home`.
- 1 MiB libre al principio y al menos 1 MiB al final para alineación y GPT.
- Kernel `linux`, firmware actual, microcódigo AMD y NetworkManager.
- RAM prevista: 16 GB. Zram zstd: mitad de RAM, máximo 8 GiB; sin swap en disco
  y sin hibernación. Se habilita el temporizador de TRIM del SSD.
- Usuario `boris`, UID esperado 1000 y sudo con contraseña; hostname `arch-ryzen`.
- Zona `America/Santiago`, locale `en_US.UTF-8`, consola `us`.
- No se instala el escritorio ni AUR en esta fase; se continúa con `setup.sh`.

## Previsualizar sin tocar discos

Ejemplo ficticio, seguro también en el host antiguo:

```bash
python3 scripts/system/install-arch/install_arch.py --example
```

Inventario de discos (solo lectura):

```bash
python3 scripts/system/install-arch/install_arch.py --list-disks
```

En el equipo nuevo, elegir el SSD por **modelo, capacidad y serial/WWN**. Preferir
su ruta persistente de `/dev/disk/by-id/`, que no debe terminar en `-partN`:

```bash
DISK=/dev/disk/by-id/REEMPLAZAR_POR_EL_SSD_REAL
python3 scripts/system/install-arch/install_arch.py --disk "$DISK"
```

Sin `--install` solo se muestra el plan. `--json` permite examinar el JSON generado,
que no contiene contraseñas; no debe ejecutarse directamente saltándose las
comprobaciones y confirmación del wrapper.

## Llevarlo a la ISO

El USB ya grabado sigue siendo válido: no hay que modificarlo ni volver a grabarlo.
El instalador no se ejecuta automáticamente al arrancar; se inicia explícitamente
después de verificar el hardware y conectar la ISO a Internet.

Usar el kit **actualizado**, `setup-kit-automated-guide.tar.gz`, que incorpora la
corrección para copytoram. Los kits antiguos deben reemplazarse antes de instalar.
Este archivo no contiene dotfiles completos ni secretos.
Si los cambios no están publicados, clonar GitHub no basta para obtenerlos.

Desde la ISO se puede transferir por SSH desde el host antiguo, si SSH ya está
disponible y se ha comprobado su clave de host por otro canal:

```bash
scp boris@IP_HOST_ANTIGUO:/home/boris/Downloads/arch-migration-nl1vvxc7/setup-kit-automated-guide.tar.gz /root/
tar -tzf /root/setup-kit-automated-guide.tar.gz
mkdir /root/arch-migration
tar -xzf /root/setup-kit-automated-guide.tar.gz -C /root/arch-migration
cd /root/arch-migration
```

No habilitar SSH ni cambiar su autenticación en el host antiguo a ciegas; como
alternativa, transferir el kit mediante otro medio. No introducir contraseñas en
comandos, argumentos o archivos de configuración. El Wi-Fi de la ISO se configura
localmente; no se incluyen sus credenciales en el kit.

## Instalar: operación destructiva

**Este paso borra todas las particiones y los datos del SSD seleccionado.** No
ejecutarlo en el equipo antiguo. Desde la terminal root de la ISO en el AMD:

```bash
DISK=/dev/disk/by-id/REEMPLAZAR_POR_EL_SSD_REAL
python3 scripts/system/install-arch/install_arch.py --disk "$DISK"
python3 scripts/system/install-arch/install_arch.py --disk "$DISK" --install
```

Antes de permitir el borrado, el wrapper comprueba:

1. Live ISO con raíz overlay, UEFI, CPU AMD, terminal interactiva, Internet y
   archinstall 4.5.x.
2. Disco completo, interno, escribible, de la capacidad prevista y con serial/WWN.
3. Ausencia de montajes, swap activa y consumidores LVM/RAID/crypt en ese disco;
   `/mnt` vacío y sin montajes. No desmonta ni limpia nada automáticamente.
4. El JSON generado mediante `archinstall --silent --dry-run`: esta fase no
   particiona ni instala. El esquema se contrastó con el paquete 4.5 de la ISO,
   no solo con ejemplos antiguos de la documentación.
5. Confirmación escrita **`BORRAR SERIAL_DEL_SSD`**, mostrando el serial real.
6. Nueva lectura del disco y comprobación de `/mnt` para detectar cambios desde
   la previsualización.

Solo entonces invoca `archinstall --silent`. Ese modo hace la instalación sin
menús adicionales: **el permiso de borrado lo proporciona la confirmación anterior**.
No existe una opción `--yes` para omitirla y no se acepta confirmación por pipe.
El JSON temporal, con permisos 0600, se crea bajo `/run` y se elimina al terminar.
Los procesos de archinstall reciben explícitamente umask `022`, para no heredar
una máscara restrictiva que deje `/etc` o los metadatos públicos de pacman
inaccesibles. Esto no cambia el modo privado del JSON ni el de las credenciales.

Se comprueban después GPT, los tres montajes, kernel/initramfs y systemd-boot,
fstab, zram, hostname, UID/GID 1000 de `boris`, grupo administrativo, sintaxis de
sudoers, NetworkManager habilitado, root bloqueado, locale generado y consultas de
pacman como `boris`. El script nunca reinicia automáticamente.

### Contraseña sin archivo de credenciales

Durante la instalación se crean `root` y `boris` con el marcador de bloqueo `!`;
**no se usan contraseñas vacías ni predeterminadas**. Archinstall puede guardar sus
propios logs/configuraciones, pero solo recibe ese marcador, no tu contraseña.

Al verificar el sistema instalado, el wrapper ejecuta:

```bash
arch-chroot /mnt passwd boris
```

Escribir y confirmar la contraseña directamente en esa terminal. `passwd` no la
revela ni la pasa como argumento; el hash definitivo queda en el `/etc/shadow` del
sistema instalado, como corresponde. Root permanece bloqueado y se administra con
sudo. No compartir logs o archivos de credenciales generados por otros intentos.

Si se cancela/falla este paso, **no reiniciar**: ejecutar el comando anterior
manualmente y comprobar `arch-chroot /mnt passwd -S boris` (estado `P`). No repetir
el instalador completo como método de recuperación: volvería a borrar el disco.

## Continuar con el entorno personal

Antes de reiniciar se puede conservar el kit en el HOME nuevo, con UID/GID 1000
ya verificados por el wrapper:

```bash
install -o 1000 -g 1000 -m 0644 /root/setup-kit-automated-guide.tar.gz /mnt/home/boris/setup-kit-automated-guide.tar.gz
```

Reiniciar cuando se haya comprobado el resultado y arrancar desde el SSD sin el
USB. Si se instaló mediante Wi-Fi, puede ser necesario volver a conectarse con
NetworkManager: no se copian las credenciales de red de la ISO.

Como `boris`, clonar los dotfiles por HTTPS, revisar y extraer el kit sobre ese
checkout **recién clonado, sin cambios propios**, y continuar con la
[guía de migración](../../../docs/migration.md). No ejecutar `setup.sh` como root
para AUR/Stow, ni cambiar todavía el shell a Zsh.

## Pruebas y límites

```bash
python3 -B scripts/system/install-arch/tests/test_install_arch.py
bash scripts/tests/test-script-structure.sh
```

Las pruebas usan dispositivos y comandos simulados, sin red ni privilegios.
Comprueban geometría de sectores 512/4096, credenciales bloqueadas, filtros de
discos, entorno live, cancelación, cambio de disco, errores y verificación del
destino. **No sustituyen una instalación completa en VM o en el hardware nuevo**.
Si archinstall cambia de versión/esquema, el wrapper se detiene para revisarlo;
no se recomienda quitar esa protección.
