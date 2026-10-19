#!/usr/bin/env python3
"""Guarded Arch installer for the approved arch-ryzen profile (archinstall 4.5)."""

import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.request import urlopen
import uuid


MIB = 1024**2
GIB = 1024**3
TARGET = Path("/mnt")
USERNAME = "boris"
HOSTNAME = "arch-ryzen"
SUPPORTED_VERSION = "4.5"
COLUMNS = "PATH,TYPE,TRAN,RM,RO,SIZE,LOG-SEC,MODEL,SERIAL,WWN,PTTYPE,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS"


class InstallError(Exception):
    """A failed safety check; never silently continue."""


def walk(device):
    yield device
    for child in device.get("children", []):
        yield from walk(child)


def lsblk(disk=None):
    command = ["lsblk", "--json", "--tree", "--bytes", "--paths", "--output", COLUMNS]
    if disk is not None:
        command.append(str(disk))
    return json.loads(subprocess.run(command, check=True, capture_output=True, text=True).stdout)["blockdevices"]


def identity(device):
    return tuple(device.get(key) for key in ("path", "serial", "wwn", "size", "log-sec", "model"))


def disk_token(device):
    token = str(device.get("serial") or device.get("wwn") or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9._:+-]{1,128}", token):
        raise InstallError("El disco necesita un serial/WWN inequívoco para confirmar el borrado.")
    return token


def validate_disk(device, unused=True):
    if device.get("type") != "disk" or device.get("ro"):
        raise InstallError("Selecciona un disco completo, escribible; no una partición.")
    if device.get("rm") or device.get("tran") == "usb":
        raise InstallError("Se rechazan discos USB/removibles: el destino debe ser el SSD interno.")
    if not 450_000_000_000 <= int(device["size"]) <= 550_000_000_000:
        raise InstallError("Este perfil solo admite el SSD confirmado de aproximadamente 500/512 GB.")
    if device.get("log-sec") not in (512, 4096):
        raise InstallError("Tamaño de sector no compatible con este perfil.")
    disk_token(device)
    for node in walk(device):
        if node["type"] not in ("disk", "part"):
            raise InstallError("El disco tiene capas LVM/RAID/crypt; no se desmontan automáticamente.")
        if unused and any(node.get("mountpoints") or []):
            raise InstallError(f"Dispositivo en uso: {node['path']}. No se desmontará automáticamente.")


def inspect_disk(path, unused=True):
    resolved = path.resolve(strict=True)
    if not resolved.is_block_device():
        raise InstallError("La ruta seleccionada no es un dispositivo de bloques.")
    devices = lsblk(resolved)
    if len(devices) != 1 or devices[0]["path"] != str(resolved):
        raise InstallError("No se pudo identificar un único disco destino.")
    device = devices[0]
    validate_disk(device, unused=unused)
    if unused:
        for node in walk(device):
            holders = Path("/sys/class/block") / Path(node["path"]).name / "holders"
            if not holders.is_dir() or any(holders.iterdir()):
                raise InstallError(f"No se puede garantizar que {node['path']} esté libre de consumidores.")
    return device


def build_config(device):
    sector = {"unit": "B", "value": device["log-sec"]}

    def size(value):
        return {"unit": "MiB", "value": value, "sector_size": dict(sector)}

    # Reserve 1 MiB at either end, including space for the backup GPT header.
    home_start = 1 + 2048 + 100 * 1024
    home_size = int(device["size"]) // MIB - 1 - home_start
    if home_size < 32 * 1024:
        raise InstallError("No queda espacio suficiente para /home.")
    partitions = []
    for mount, fs, start, length, flags in (
        ("/boot", "fat32", 1, 2048, ["boot", "esp"]),
        ("/", "ext4", 2049, 100 * 1024, []),
        ("/home", "ext4", home_start, home_size, []),
    ):
        partitions.append({
            "obj_id": str(uuid.uuid4()), "status": "create", "type": "primary",
            "start": size(start), "size": size(length), "fs_type": fs,
            "mountpoint": mount, "mount_options": [], "flags": flags,
            "btrfs": [], "dev_path": None,
        })
    return {
        "version": SUPPORTED_VERSION, "archinstall-language": "English",
        "disk_config": {
            "config_type": "manual_partitioning",
            "device_modifications": [{"device": device["path"], "wipe": True, "partitions": partitions}],
        },
        "bootloader_config": {"bootloader": "Systemd-boot", "uki": False, "removable": False},
        "hostname": HOSTNAME, "timezone": "America/Santiago",
        "locale_config": {"kb_layout": "us", "sys_lang": "en_US.UTF-8", "sys_enc": "UTF-8"},
        "kernels": ["linux"], "network_config": {"type": "nm"}, "ntp": True,
        "swap": {"enabled": True, "algorithm": "zstd"},
        # Lock both accounts during installation. passwd sets the real user
        # password afterwards, directly on the target, without a credentials file.
        "root_enc_password": "!",
        "users": [{"username": USERNAME, "enc_password": "!", "sudo": True, "groups": []}],
        "packages": ["amd-ucode", "linux-firmware", "sudo", "git", "stow", "pciutils", "openssh", "rsync"],
        "services": ["fstrim.timer"],
        "custom_commands": [
            "printf '%s\\n' '[zram0]' 'zram-size = min(ram / 2, 8192)' "
            "'compression-algorithm = zstd' > /etc/systemd/zram-generator.conf",
        ],
    }


def show_plan(device, config):
    print(f"Destino: {device['path']} | {device.get('model')} | {device['size'] / GIB:.2f} GiB")
    print(f"Serial/WWN: {disk_token(device)}")
    print("Se BORRARÁ TODO el disco. GPT/UEFI, sin cifrado; NO es una actualización.")
    for node in list(walk(device))[1:]:
        print(f"  Existente: {node['path']} | {node.get('fstype')} | {node.get('label') or '-'}")
    for part in config["disk_config"]["device_modifications"][0]["partitions"]:
        print(f"  Nuevo: {part['mountpoint']:6} | {part['fs_type']:5} | {part['size']['value'] / 1024:.2f} GiB")
    print(f"Usuario: {USERNAME} con sudo; root bloqueado. Hostname: {HOSTNAME}.")
    print("America/Santiago | en_US.UTF-8 | consola us | zram: mitad de RAM, máximo 8 GiB.")
    print("Sin hibernación. La contraseña se establece al finalizar, antes de reiniciar.")


def check_target_empty():
    if TARGET.is_symlink() or TARGET.is_mount() or (TARGET.exists() and any(TARGET.iterdir())):
        raise InstallError("/mnt debe estar vacío y sin montajes. No se limpia ni se desmonta automáticamente.")


def check_live_environment():
    result = subprocess.run(
        ["findmnt", "--json", "--list", "--output", "TARGET,SOURCE,FSTYPE,OPTIONS"],
        check=True, text=True, capture_output=True,
    )
    mounts = {entry["target"]: entry for entry in json.loads(result.stdout)["filesystems"]}
    root = mounts.get("/", {})
    lowerdirs = []
    for option in root.get("options", "").split(","):
        if option.startswith("lowerdir="):
            lowerdirs = option.removeprefix("lowerdir=").split(":")
    if root.get("fstype") != "overlay" or "/run/archiso/airootfs" not in lowerdirs:
        raise InstallError("La raíz no es el overlay live de Arch. No se instala desde el host existente.")
    base = mounts.get("/run/archiso/airootfs", {})
    if base.get("fstype") != "squashfs" or "ro" not in base.get("options", "").split(","):
        raise InstallError("No se verificó la raíz squashfs de solo lectura de la ISO.")
    if mounts.get("/run/archiso/bootmnt", {}).get("fstype") == "iso9660":
        return "bootmnt"

    # Archiso may copy the image into tmpfs and unmount its boot medium. Verify
    # the actual squashfs loop backing file, not merely a directory named archiso.
    if mounts.get("/run/archiso/copytoram", {}).get("fstype") != "tmpfs":
        raise InstallError("No se verificó ni el medio ISO montado ni el modo copytoram.")
    image = Path("/run/archiso/copytoram/airootfs.sfs")
    loop = re.fullmatch(r"/dev/(loop\d+)", base.get("source", ""))
    if loop is None or not image.is_file():
        raise InstallError("No se verificó la imagen y el dispositivo loop de copytoram.")
    backing_file = Path("/sys/class/block") / loop.group(1) / "loop/backing_file"
    if Path(backing_file.read_text().strip()) != image:
        raise InstallError("La raíz live no utiliza la imagen de copytoram esperada.")
    return "copytoram"


def check_environment():
    if os.geteuid() != 0:
        raise InstallError("--install requiere root desde la ISO; no ejecutes sudo en el host actual.")
    check_live_environment()
    if not Path("/sys/firmware/efi/efivars").is_dir():
        raise InstallError("Arranca la ISO en modo UEFI; este perfil no admite BIOS/CSM.")
    if "AuthenticAMD" not in Path("/proc/cpuinfo").read_text():
        raise InstallError("Este perfil es para el destino AMD, no para el host Intel antiguo.")
    for command in ("archinstall", "arch-chroot", "lsblk", "findmnt"):
        if not shutil.which(command):
            raise InstallError(f"Falta una herramienta de la ISO: {command}")
    version = importlib.metadata.version("archinstall")
    if not re.fullmatch(r"4\.5(?:\.\d+)?", version):
        raise InstallError(f"archinstall {version} no validado; se requiere 4.5.x (ISO 2026.10.01).")
    check_target_empty()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise InstallError("Se requiere una terminal interactiva; no se admite confirmación por pipe.")
    # Check connectivity before allowing any destructive action. No private data
    # is included in the request; TLS also catches many incorrect live-ISO clocks.
    with urlopen("https://archlinux.org/", timeout=20) as response:
        if response.status != 200:
            raise InstallError("No se pudo comprobar la conexión a Internet.")


def verify_boot_files():
    for relative in ("boot/vmlinuz-linux", "boot/initramfs-linux.img", "boot/EFI/systemd/systemd-bootx64.efi", "boot/loader/loader.conf"):
        if not (TARGET / relative).is_file():
            raise InstallError(f"Falta un archivo de arranque: {relative}. No se considera terminada la instalación.")
    entries = list((TARGET / "boot/loader/entries").glob("*.conf"))
    if not any("vmlinuz-linux" in path.read_text() and "initramfs-linux.img" in path.read_text() for path in entries):
        raise InstallError("No se encontró una entrada systemd-boot para el kernel instalado.")
    fstab = {}
    for line in (TARGET / "etc/fstab").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 3 and not fields[0].startswith("#"):
            fstab[fields[1]] = fields[2]
    if any(fstab.get(mount) != fs for mount, fs in (("/", "ext4"), ("/home", "ext4"), ("/boot", "vfat"))):
        raise InstallError("fstab no contiene los tres sistemas de archivos esperados.")
    zram = (TARGET / "etc/systemd/zram-generator.conf").read_text()
    if "zram-size = min(ram / 2, 8192)" not in zram or "compression-algorithm = zstd" not in zram:
        raise InstallError("No se verificó la configuración de zram.")


def verify_installation(original):
    installed = inspect_disk(Path(original["path"]), unused=False)
    if identity(installed) != identity(original) or installed.get("pttype") != "gpt":
        raise InstallError("El disco instalado o la tabla GPT no coincide con el destino autorizado.")
    mounted_devices = set()
    for mount, fs in (("/mnt", "ext4"), ("/mnt/home", "ext4"), ("/mnt/boot", "vfat")):
        matches = [node for node in walk(installed) if mount in (node.get("mountpoints") or [])]
        if len(matches) != 1 or matches[0].get("fstype") != fs:
            raise InstallError(f"No se verificó el montaje esperado {mount}; no se ejecutará passwd.")
        mounted_devices.add(matches[0]["path"])
    if len(mounted_devices) != 3:
        raise InstallError("Los tres montajes deben corresponder a particiones distintas.")
    verify_boot_files()
    if (TARGET / "etc/hostname").read_text().strip() != HOSTNAME:
        raise InstallError("El hostname instalado no coincide.")
    uid = subprocess.run(["arch-chroot", str(TARGET), "id", "-u", USERNAME], check=True, text=True, capture_output=True)
    if uid.stdout.strip() != "1000":
        raise InstallError("El UID de boris no es 1000; revisar antes de restaurar datos o continuar.")
    gid = subprocess.run(["arch-chroot", str(TARGET), "id", "-g", USERNAME], check=True, text=True, capture_output=True)
    if gid.stdout.strip() != "1000":
        raise InstallError("El GID de boris no es 1000; revisar antes de restaurar datos o continuar.")
    groups = subprocess.run(["arch-chroot", str(TARGET), "id", "-nG", USERNAME], check=True, text=True, capture_output=True)
    if "wheel" not in groups.stdout.split():
        raise InstallError("No se verificó el grupo administrativo de boris.")
    subprocess.run(["arch-chroot", str(TARGET), "visudo", "-c"], check=True, capture_output=True, text=True)
    subprocess.run(["arch-chroot", str(TARGET), "systemctl", "is-enabled", "--quiet", "NetworkManager.service"], check=True)
    root_status = subprocess.run(["arch-chroot", str(TARGET), "passwd", "-S", "root"], check=True, text=True, capture_output=True)
    if root_status.stdout.split()[:2] != ["root", "L"]:
        raise InstallError("La cuenta root no está bloqueada como requiere el perfil.")
    locales = subprocess.run(["arch-chroot", str(TARGET), "locale", "-a"], check=True, text=True, capture_output=True)
    if "en_us.utf8" not in {name.lower().replace("-", "") for name in locales.stdout.split()}:
        raise InstallError("El locale en_US.UTF-8 no está generado; revisar antes de reiniciar.")
    # Package queries must also work without root for setup.sh and AUR tools.
    for query in (("-Qi", "git"), ("-Si", "bash")):
        subprocess.run(["arch-chroot", str(TARGET), "runuser", "-u", USERNAME, "--", "pacman", *query], check=True, text=True, capture_output=True)


def install(path, device, config):
    # Validate the parser in archinstall's read-only mode before the human gate.
    # Its generated logs contain only locked markers, not a usable password/hash.
    with tempfile.TemporaryDirectory(prefix="arch-ryzen-", dir="/run") as directory:
        config_file = Path(directory) / "config.json"
        with open(config_file, "x", opener=lambda name, flags: os.open(name, flags, 0o600)) as handle:
            json.dump(config, handle, indent=2)
        # Keep the config private, but do not let a restrictive caller umask
        # create an unreadable /etc or public configuration in the target OS.
        subprocess.run(["archinstall", "--config", str(config_file), "--silent", "--dry-run"], check=True, umask=0o022)
        phrase = f"BORRAR {disk_token(device)}"
        print(f"\nPara autorizar el borrado de ESTE disco escribe exactamente: {phrase}")
        if input("> ").strip() != phrase:
            raise InstallError("Confirmación incorrecta o cancelada. No se ha iniciado el particionado.")
        # Detect reconnection, renaming, new mounts and layout changes since preview.
        current = inspect_disk(path)
        if current != device:
            raise InstallError("El disco cambió desde la previsualización. Vuelve a revisar el plan.")
        check_target_empty()
        subprocess.run(["archinstall", "--config", str(config_file), "--silent"], check=True, umask=0o022)
    verify_installation(device)
    print("\nEstablece ahora la contraseña de boris. No se guarda en el kit ni en el JSON.")
    try:
        subprocess.run(["arch-chroot", str(TARGET), "passwd", USERNAME], check=True)
    except subprocess.CalledProcessError as exc:
        raise InstallError("Contraseña no establecida. NO reinicies: ejecuta arch-chroot /mnt passwd boris.") from exc
    status = subprocess.run(["arch-chroot", str(TARGET), "passwd", "-S", USERNAME], check=True, text=True, capture_output=True)
    fields = status.stdout.split()
    if len(fields) < 2 or fields[:2] != [USERNAME, "P"]:
        raise InstallError("La cuenta no tiene contraseña activa. NO reinicies; revisa passwd dentro de /mnt.")
    print("Base instalada y cuenta activa. No se reinicia automáticamente.")
    print("Tras arrancar el SSD, entra como boris y continúa con setup.sh y docs/migration.md.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", type=Path, help="Disco completo elegido explícitamente; preferir /dev/disk/by-id/...")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--install", action="store_true", help="Instalar SOLO desde la ISO y tras confirmación por serial")
    modes.add_argument("--json", action="store_true", help="Mostrar configuración no secreta, sin instalar")
    parser.add_argument("--example", action="store_true", help="Ejemplo ficticio de 500 GB, sin acceder a discos")
    parser.add_argument("--list-disks", action="store_true", help="Inventario de discos, sin cambios")
    args = parser.parse_args(argv)
    if args.list_disks:
        if args.disk or args.example or args.install or args.json:
            parser.error("--list-disks no admite otras opciones")
        print(json.dumps(lsblk(), indent=2))
        return 0
    if args.example and (args.disk or args.install):
        parser.error("--example no admite --disk ni --install")
    if not args.example and args.disk is None:
        parser.error("Selecciona --disk explícitamente, o usa --example/--list-disks")
    if args.install:
        check_environment()
    if args.example:
        device = {"path": "/dev/disk/by-id/SELECCIONAR_SSD_REAL", "type": "disk", "tran": "nvme",
                  "size": 500_000_000_000, "log-sec": 512, "serial": "EJEMPLO-NO-INSTALABLE", "model": "EJEMPLO"}
    else:
        device = inspect_disk(args.disk)
    config = build_config(device)
    if args.json:
        print(json.dumps(config, indent=2))
    else:
        show_plan(device, config)
        if args.install:
            install(args.disk, device, config)
        else:
            print("\nSolo previsualización: no se ha escrito ningún archivo ni disco.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit("Interrumpido. No asumas que la instalación terminó; revisa el estado antes de reiniciar.")
    except (InstallError, OSError, ValueError, subprocess.CalledProcessError, importlib.metadata.PackageNotFoundError) as error:
        sys.exit(f"Error: {error}")
