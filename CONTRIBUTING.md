# Cómo colaborar

Proyecto personal y experimental. Sin empresa detrás, sin maintainers, sin
promesas de tiempo de respuesta. Sigue si te sirve, y no pasa nada si no.

## Lo mínimo

1. Abre una issue o un PR describiendo **qué se rompe y cómo se reproduce**. Un
   `ezarrctl doctor` y el `--json` de la orden que falla valen más que un párrafo.
2. Un cambio de código viene con su cambio en `tests/smoke.sh` o con la
   explicación de por qué no lo necesita.
3. Nada de secretos: ni claves, ni tokens, ni IPs de tu red local. La suite lo
   comprueba y falla (`bash tests/smoke.sh`), y está bien que falle.

## Qué entra en este repositorio y qué no

Este repo es el producto: instalador, operación, pruebas y documentación. No es
un volcado de la configuración de un servidor concreto.

**Sí entra:** código del instalador y del plano de control (`ezarr.sh`,
`ezarrctl`, `arr-stack`, `lib/`), pruebas, documentación en inglés y español,
diagramas, y plantillas `etc/ezarr/*.sample` con placeholders.

**No entra:**

- Credenciales reales de cualquier tipo: API keys, tokens, contraseñas, hashes,
  URLs con `usuario:clave@`, topics de notificación. Tampoco cifradas.
- Datos de una red real: dominio, IPs de LAN o VPN, usuario del sistema, rutas
  personales, hostnames. El handle de GitHub solo como atribución.
- Configuración de un servidor en marcha: se convierte en `.sample` con
  placeholder, o se pide y se genera al instalar.
- Backups, logs, bases de datos, medios o binarios.
- Referencias a la topología o a la historia del servidor del autor.

Los placeholders deben reconocerse como tales: vacío, `CHANGE_ME`, `<...>`,
`PLACEHOLDER` o una variable. La red de ejemplo es `192.168.1.0/24` y el test
solo admite `.0`, `.1` y `.10`; cualquier otra IP privada falla.

`bash tests/smoke.sh` comprueba la forma de las credenciales, las asignaciones
con valor y las IPs. No sustituye una revisión: si añades un valor que el test
no sabe buscar, la responsabilidad sigue siendo tuya.

## Antes de abrir el PR

```bash
bash -n ezarr.sh ezarrctl arr-stack lib/*.sh   # sintaxis
bash tests/smoke.sh                            # suite de contrato
./ezarr.sh --dry-run --profile minimal         # el plan sigue siendo valido
```

Si tocas un componente, toca también su fila en `docs/`. Si cambias un flag,
cámbialo en `ezarr.sh --help`, en el `README.md` y en `docs/instalacion.md`: que
los tres digan cosas distintas es exactamente el bug que este repo quiere evitar.

## Lo que se acepta y lo que no

**Sí:** correcciones de codigo, documentacion que se entienda, diagramas, y
cualquier cosa que haga mas cierto el README.

**No:** prometer disponibilidad, rendimiento o hardware que no esten medidos. Si
un PR añade una cifra, que traiga el comando con el que se obtuvo. La honestidad
de este proyecto es lo único que lo hace distinto de un `docker-compose` más.

## Licencia

El proyecto se distribuye bajo MIT (ver `LICENSE`). Al abrir un PR aceptas que
tu contribución se distribuya bajo esa misma licencia.
