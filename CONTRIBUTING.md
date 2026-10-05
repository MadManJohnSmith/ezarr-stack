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

No hay `LICENSE`. Mientras no haya una, manda el copyright por defecto y no se
acepta nada que se pueda distribuir. Si eres el dueño y quieres elegir licencia,
eso se decide antes de recibir contribuciones.
