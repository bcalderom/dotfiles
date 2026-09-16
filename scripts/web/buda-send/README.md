# buda-send

Publica un archivo Markdown en el sitio Hugo remoto mediante SSH. El comando
valida `publication_type`, `slug` y `draft`, clasifica la publicacion como
`essay` o `note`, y evita sobrescribir una publicacion existente.

## Uso

```bash
buda-send articulo.md
buda-send --draft nota.md
```

Por defecto usa el host SSH `home_docker` y la raiz remota
`/docker/hugo/site/content`. Se pueden cambiar sin editar el script:

```bash
BUDA_SERVER=servidor BUDA_CONTENT_ROOT=/ruta/al/content buda-send articulo.md
```

El frontmatter debe contener valores TOML con este formato:

```toml
publication_type = "essay"
slug = "mi-articulo"
draft = true
```

`publication_type` acepta `essay` o `note`. El slug solo acepta minusculas,
numeros y guiones.

## Dependencias

- `bash`
- `ssh`
- `scp`
- En el servidor: `bash`, `mktemp`, `sed`, `cp`, `ln` y `rm`

## Pruebas

```bash
bash tests/test-buda-send.sh
bash ../../tests/test-script-structure.sh
```
