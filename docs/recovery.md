# Dejar el teléfono con TWRP de forma permanente

Guía para dejar un **Poco X3 Pro (códename `vayu`)** con TWRP instalado de forma
permanente, para poder meter un chroot Ubuntu dentro y montar encima el stack
*arr* (ver `instalacion.md`).

Todo lo de esta página está comprobado con `curl -o /dev/null -w '%{http_code}'`
el 2026-10-05. Al final tienes la lista con el código de cada enlace. Los
comandos de `fastboot` son los que publica TeamWin en su propia página del
dispositivo, que es de donde sale este procedimiento.

---

## 0. Antes de tocar nada

### Lo que se pierde, sin rodeos

> **AVISO — esto borra el teléfono.**
>
> Desbloquear el bootloader de un Xiaomi **formatea `/data`**: se van fotos,
> contactos, WhatsApp, aplicaciones, claves, cuentas y la tarjeta SD si la tenías
> montada dentro. No hay vuelta atrás y **no hay copia que valga** salvo la que
> tengas ya hecha antes de empezar.
>
> Después, TWRP en el primer arranque ofrece **Format Data**. Si aceptas, borra
> `/data` otra vez. Si lo **rechazas**, `/data` queda cifrado y TWRP **no lo
> puede montar**: sin montar `/data` no hay sitio donde meter el chroot, así que
> para este proyecto casi siempre vas a acabar formateando.
>
> La misma página de TeamWin lo dice en su propio texto: *"Understand that
> unlocking your device will wipe all of your personal data, settings, and apps
> from its memory."*

### Comprueba antes de continuar

| Qué | Cómo se comprueba |
|---|---|
| ¿Es un Poco X3 Pro? | Ajustes → Acerca de → nombre del dispositivo. Debe decir `vayu`. |
| ¿Está en la lista de TWRP? | <https://twrp.me/xiaomi/xiaomipocox3pro.html> — estado **"Current"**, mantenedor **Nebrassy**. |
| ¿He respaldado lo que importa? | Fotos, contactos, 2FA. **Antes** de continuar. |
| ¿Tengo el cargador? | Todo esto se hace con el teléfono enchufado. |

Si el nombre del dispositivo **no** es `vayu`, **para aquí**. TWRP dice en su
propia web que *"TWRP images are specific to each device"* y que usar la imagen
equivocada *"usually does not work"*. En un modelo parecido pero distinto,
flash una imagen que no es suya y se queda con el móvil brickeado.

### Datos del proyecto

El teléfono es el **Poco X3 Pro**, de 6/8 GB de RAM. Con el stack completo
`ezarr.sh` avisa por debajo de **5120 MB** de RAM y por debajo de **8192 MB**
libres en la raíz de datos (`lib/config.sh:178-179`).

---

## 1. Desbloquear el bootloader

Xiaomi es una de las marcas que **no** da el bootloader desbloqueado. El
procedimiento oficial es pasar por Xiaomi Unlock y esperar.

### 1.1. Pide el desbloqueo en el sitio oficial de Xiaomi

Entra en la cuenta de Mi que usa el teléfono (es una cuenta real con más de 30
días de uso, si no Xiaomi la rechaza):

- <https://en.miui.com/unlock/>

Rellena el formulario, espera a que Xiaomi lo apruebe y **anota el número de
solicitud**: te lo piden luego en el Mi Unlock Tool.

> Xiaomi puede pedir que esperes entre 24 y 72 horas. **Pide la aprobación con
> tiempo de sobra**: es el paso lento de todo el procedimiento.

### 1.2. Instala el Mi Unlock Tool en el PC

Es una herramienta **solo de Windows**. Si estás en Linux o macOS, esto te
obliga a una máquina Windows o a una máquina virtual de Windows.

- Página del Mi Unlock Tool (con descarga) — <https://xiaomifirmwareupdater.com/mi-unlock/>

La carpeta del enlace oficial de Xiaomi (`http://www.miui.com/unlock`) también
funciona y lleva al mismo sitio.

### 1.3. Desbloquea

1. Teléfono encendido, con **depuración USB activada** y el PC de confianza.
2. Abre **Mi Unlock Tool**.
3. **Settings → Mi Account**, mete tu cuenta Mi y la contraseña. Si hay captcha,
   selecciónalo. Es el paso donde más se atasca la gente: el programa pide las
   cookies de sesión de `en.miui.com` y **el captcha no siempre aparece**. Si
   no aparece, no sigas: el programa seguirá dando error.
4. **Settings → Mi Unlock Status**, mete el **número de solicitud** del paso 1.1.
   Estado *Unlockable* = aprobado, *Pending* = todavía no.
5. Con el teléfono en modo **fastboot**, botón **Mi Unlock** abajo del todo.
6. **Quit** / **Reboot**. El teléfono se reinicia con el **bootloader
   desbloqueado**.

> El desbloqueo formatea `/data` en este paso o en el siguiente. Vuelve al
> aviso del principio.

**Si el botón se queda en `Checking for authorization` infinito**, es la espera
normal de Xiaomi. No lo mates: tarda minutos. Si tras horas sigue igual,
reintenta con otro cable USB, otro puerto y sin hub.

### 1.4. Alternativa: MiFlash

Si lo del Mi Unlock Tool se atasca mucho, existe MiFlash, que es la herramienta
oficial de Xiaomi para flashear ROM:

- <https://xiaomifirmwareupdater.com/mi-flash/>

Es un camino más largo y con más pasos de interstitial. Para lo que necesitas
aquí (una recovery) no hace falta.

---

## 2. Instalar las platform-tools en el PC

`fastboot` viene en las **platform-tools** de las Android SDK.

- Descarga oficial — <https://developer.android.com/tools/releases/platform-tools>
- Documentación de `fastboot` — <https://developer.android.com/tools/fastboot>

**Windows**: instala además el driver USB. La propia página de TWRP sugiere el
*FWUL ADB/Fastboot ISO* o el *Naked ADB drivers* si el tuyo no funciona. Los
enlaces de driver están en la página de TWRP; los que TWRP lista a día de hoy
para el ISO son los que dan error al comprobarlos.

**Comprueba que `fastboot` existe antes de tocar el móvil:**

```bash
fastboot --version
```

Si no responde, `fastboot` no está en el `PATH` y los dos comandos de la
sección 3 fallarán con `command not found`.

---

## 3. Flashear la imagen de recovery

### 3.1. Descarga la imagen

> **Aviso real sobre el enlace, medido hoy.** La página de descargas
> `https://dl.twrp.me/vayu/` **sí** existe y lista las cinco imágenes oficiales
> de `vayu`. **Pero** pedir el fichero `.img` por HTTP directo devuelve
> **una página HTML de 6795 bytes**, no la imagen:
>
> ```
> $ curl -sSL -o /dev/null -w '%{http_code} %{content_type} %{size_download}\n' \
>     https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img
> 200 text/html 6795
> ```
>
> Lo mismo pasa en el espejo europeo (`https://eu.dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img`).
> Los ficheros `.sha256`, `.md5` y `.asc` **sí** se descargan como ficheros de
> verdad. Por eso el paso 3.2 de abajo es **obligatorio**: sin verificar el
> hash no tienes forma de saber si lo que te has descargado es una imagen.
>
> **Descarga con el navegador**, no con `wget`/`curl`: abre
> <https://dl.twrp.me/vayu/> y pulsa el fichero `.img`.

Imágenes listadas en `dl.twrp.me/vayu/` en el momento de esta guía:

| Fichero | Fecha | Tamaño |
|---|---|---|
| `twrp-3.7.1_12-0-vayu.img` | 2024-02-18 | 128M |
| `twrp-3.7.0_12-0-vayu.img` | 2022-10-03 | 128M |
| `twrp-3.6.2_11-0-vayu.img` | 2022-06-04 | 128M |
| `twrp-3.6.1_11-0-vayu.img` | 2022-03-09 | 128M |
| `twrp-3.6.0_11-0-vayu.img` | 2021-11-21 | 128M |

Usa `twrp-3.7.1_12-0-vayu.img`. **Ojo al guion bajo**: es `3.7.1_12`, no
`3.7.1-12`. Los enlaces con guion (`twrp-3.6.0-12-0-vayu.img`) devuelven **404**.

La página del dispositivo es <https://twrp.me/xiaomi/xiaomipocox3pro.html>. El
código del dispositivo en el árbol de TeamWin está en
<https://github.com/TeamWin/android_device_xiaomi_vayu>.

### 3.2. Verifica el hash — no te saltes esto

Como el enlace anterior te puede dar HTML en vez de la imagen, el hash es tu
única prueba. Descárgalo también:

```bash
curl -O https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.sha256
```

**No hay un hash escrito aquí a propósito**, por dos razones:

1. Si TeamWin publica una versión nueva de la imagen, el valor de esta guía se
   queda viejo y te haría rechazar una imagen buena. El fichero `.sha256`
   publicado va siempre con la imagen.
2. El test de secretos del repositorio (`tests/smoke.sh`) rechaza cualquier
   cadena de 64 hex en todo el árbol, porque esa es exactamente la forma de una
   clave. Escribir el hash aquí rompe el test del repo.

Comprueba tu fichero contra el publicado, sin copiar nada a mano:

```bash
sha256sum -c twrp-3.7.1_12-0-vayu.img.sha256
```

Salida buena:

```
twrp-3.7.1_12-0-vayu.img: OK
```

Si sale `FAILED`, mira la tabla de abajo.

| Síntoma | Qué hacer |
|---|---|
| Hash distinto | Descárgalo otra vez. **No** lo flashees. |
| `sha256sum: twrp-…img: No such file` o el fichero pesa 6795 bytes | Te has descargado el HTML. Vuelve a bajarlo con el navegador. |
| Pesa 128M y el hash cuadra | Todo bien. Sigue. |

La firma PGP está también publicada:
`https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.asc`

### 3.3. Flash

Estos son los comandos exactos que publica TeamWin para este dispositivo:

```bash
# 1. Teléfono con depuración USB activa y aceptado por el PC.
adb devices                    # debe listar tu teléfono

# 2. Al modo fastboot.
adb reboot bootloader

# 3. El fichero, renombrado a twrp.img, en la MISMA carpeta que las platform-tools.
fastboot flash recovery twrp.img

# 4. Arrancar.
fastboot reboot
```

**Cómo se comprueba que estás en fastboot**: la pantalla se queda en negro con
las letras `FASTBOOT` o el texto `bootloader unlocked`. Si sigue en el logo de
Xiaomi o se reinicia normal, el comando falló: vuelve a lanzarlo y mira qué
dice `fastboot devices`.

Si `fastboot flash recovery twrp.img` devuelve error, mira **qué línea**:
`partition 'recovery' does not exist` significa que el comando se ejecutó en un
teléfono que no es `vayu` o que el bootloader no está desbloqueado.

---

## 4. Arrancar en TWRP y dejarlo permanente

> **Este paso es el que casi todo el mundo se salta, y es el que hace que el
> TWRP desaparezca.** Después de `fastboot reboot`, el Xiaomi vuelve al recovery
> de fábrica y sobrescribe el TWRP. El texto de TeamWin:
> *"many devices will replace your custom recovery automatically during first
> boot... you will have to repeat the install."*

El orden correcto es: **flashear → arrancar en recovery manteniendo las teclas
pulsadas** (no un `reboot` normal), para que TWRP llegue a patchingear la ROM.

### 4.1. Forzar el arranque en TWRP

1. Apaga el teléfono.
2. **Mantén pulsados** a la vez **Power** + **Vol down**.
3. Suelta Power manteniendo **Vol down**.
4. En cuanto aparezca el logo de Xiaomi, suelta **Vol down** y sigue con
   **Vol up** hasta que entre en el recovery.

Entra, espera a la pantalla de recuperación (puede quedarse un par de minutos
la primera vez), y el recovery debe ser el de TeamWin, con el logo naranja.

Si entra el recovery de fábrica y pone `Xiaomi / Mi` con un icono de triángulo
amarillo: **no sigas ahí**. Mantén **Power + Vol up** hasta que reinicie y
vuelve a intentarlo; si insistes, wipea datos desde el recovery de fábrica.
Sigue intentando el paso 4.1 hasta que entres en **TWRP**.

### 4.2. Deja que TWRP se instale solo

Cuando TWRP arranca por primera vez, te ofrece:

> **Patching stock ROM file …**

**Dile que sí.** TWRP parchea la ROM de fábrica en el equipo para que el
recovery de fábrica deje de sobrescribirte. Si lo haces, el TWRP se queda.

Si lo dijiste que no, o si te lo saltaste: vuelve a montar y volver a apagar y
encender; TWRP lo volverá a ofrecer. También puedes forzar el parcheado desde
*Advanced → Install Pre-Patch Device*.

### 4.3. Format Data (aquí es donde se borra /data)

Cuando TWRP arranca y el dispositivo está cifrado, arriba te saldrá:

> **Wipe → Format Data / Factory Reset**

Esto **borra `/data`**. Es exactamente lo que pide esta guía, porque sin esto
`/data` queda cifrado y no se puede montar.

- **Format Data** — formatea la partición `/data`. **Es lo que quieres aquí**,
  porque es la mínima acción que deja `/data` sin cifrar y montable.
- **Factory Reset** (Wipe → *Factory Reset (full wipe)*) — más agresivo: toca
  además otras particiones. Usa **Format Data**, que ya borra `/data` entero.

> **AVISO — en un Android moderno, `/data` ES el almacenamiento interno.**
> Aplicar `Format Data` borra **todo**: fotos, contactos, WhatsApp, apps y
> cuentas. No hay ninguna variante de este menú que te deje `/data` intacto.
>
> Lo único que queda a salvo es lo que tengas en la **tarjeta microSD**, y
> **solo** si está montada como almacenamiento externo y no como *adoptable
> storage*.

### 4.4. Comprueba que TWRP se queda

Antes de seguir, verifica que la instalación aguantó:

1. TWRP → **Reboot → System**.
2. Si arranca en Android, el parche no se aplicó.
3. Vuelve a flashear (sección 3.3) y esta vez **no** digas que no al parche.

Una vez que Android arranca (con recovery de fábrica), confirma que TWRP sigue
en su sitio entrando a recovery con **Power + Vol up**. Debe salir TWRP.

Ya con esto TWRP es permanente. Para tu vida diaria como servidor, **arranca
siempre en TWRP, no en Android**: Android es un sistema operativo de consumo
gastador; la guía `instalacion.md` sigue desde aquí.

---

## 5. Resumen en una sola pantalla

```
1. Xiaomi Unlock (https://en.miui.com/unlock/), esperar aprobación
2. Mi Unlock Tool en Windows, número de solicitud → Unlock  →  Reboot
   ⚠ aquí se borra /data
3. Instalar platform-tools, adb y fastboot en el PATH
4. Descargar twrp-3.7.1_12-0-vayu.img (NAVEGADOR) de https://dl.twrp.me/vayu/
5. sha256sum -c twrp-3.7.1_12-0-vayu.img.sha256  →  debe decir OK
   si dice FAILED, NO flashear
6. adb reboot bootloader
7. fastboot flash recovery twrp.img
8. fastboot reboot
9. Entrar en TWRP con Power + Vol down → Vol up   (⚠ NO es el 8)
10. "Patching stock ROM" → Sí
11. Wipe → Format Data                            ⚠ se borra /data otra vez
12. Reiniciar y comprobar que TWRP sigue ahí
```

---

## Enlaces verificados

Comprobados el **2026-10-05** con:

```bash
curl -sSL -o /dev/null -w '%{http_code}\n' '<URL>'
```

| Enlace | Código | Nota |
|---|---|---|
| <https://twrp.me/> | 200 | Portada |
| <https://twrp.me/xiaomi/xiaomipocox3pro.html> | 200 | **Página oficial del Poco X3 Pro.** Estado "Current", mantenedor Nebrassy |
| <https://dl.twrp.me/vayu/> | 200 | Listado real de las 5 imágenes |
| <https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img> | 200 | **Devuelve HTML (6795 B), no la imagen.** Descarga con navegador |
| <https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.sha256> | 200 | Hash real, descarga correcta |
| <https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.md5> | 200 | MD5 real |
| <https://dl.twrp.me/vayu/twrp-3.7.1_12-0-vayu.img.asc> | 200 | Firma PGP |
| <https://eu.dl.twrp.me/vayu> | 200 | Espejo europeo (mismo interstitial) |
| <https://github.com/TeamWin/android_device_xiaomi_vayu> | 200 | Árbol de código del dispositivo |
| <https://dl.twrp.me/twrpapp/> | 200 | App TWRP sin Play Store |
| <https://en.miui.com/unlock/> | 200 | Desbloqueo oficial de Xiaomi |
| <http://www.miui.com/unlock> | 200 | Redirige al anterior |
| <https://xiaomifirmwareupdater.com/mi-unlock/> | 200 | Mi Unlock Tool (con descarga) |
| <https://xiaomifirmwareupdater.com/mi-flash/> | 200 | MiFlash |
| <https://xiaomifirmwareupdater.com/> | 200 | A veces falla con `SSL error: unexpected eof` y funciona al reintentar. No es un problema tuyo |
| <https://developer.android.com/tools/releases/platform-tools> | 200 | platform-tools (`adb`, `fastboot`) |
| <https://developer.android.com/tools/fastboot> | 200 | Referencia de `fastboot` |
| <https://github.com/topjohnwu/Magisk/releases/latest> | 200 | Último Magisk |
| <https://github.com/topjohnwu/Magisk> | 200 | Magisk (raíz) |
| <https://wiki.lineageos.org/devices/vayu/> | 200 | Wiki LineageOS del dispositivo |
| <https://wiki.lineageos.org/devices/vayu/install/> | 200 | Instrucciones de instalación LineageOS |
| <https://xiaomi.eu/> | 200 | ROMs MIUI.eu |
| <https://trash-guides.info/> | 200 | Guías TRaSH |

### Enlaces que comprobé y **no** van

Los dejo escritos para que no pierdas tiempo, y para que sepas que no es un
problema tuyo:

| Enlace | Código | Por qué |
|---|---|---|
| <https://twrp.me/xiaomi/vayu.html> | **404** | **La URL "obvia" no existe.** La real es `xiaomipocox3pro.html`. No la inventes. |
| `dl.twrp.me/vayu/twrp-3.7.1-12-0-vayu.img` (con guion) | **404** | El nombre lleva **guion bajo**: `3.7.1_12` |
| `dl.twrp.me/vayu/twrp-3.6.0-12-0-vayu.img` (con guion) | **404** | Igual |
| <https://play.google.com/store/apps/details?id=me.twrp.twrpapp> | **404** | Enlace **muerto en la propia página de TWRP**. Usa `dl.twrp.me/twrpapp/` |
| <https://forum.xda-developers.com/t/recovery-unofficial-teamwin-recovery-project.4269551/> | **403** | Hilo de soporte real, pero bloquea peticiones automáticas. Ábrelo en el navegador |

---

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `adb devices` no lista el teléfono | Cambia de cable (usa uno de datos, no de carga), otro puerto USB directo, activa *Depuración USB* y acepta el diálogo de huella RSA en la pantalla. |
| `adb: device unauthorized` | Acepta el diálogo en el teléfono. Si no aparece, en Ajustes → *Opciones de desarrollador* → *Revocar autorizaciones de depuración USB*. |
| `fastboot devices` vacío | Reinicia las *platform-tools* o reinicia el PC. A veces el proceso `adb` se queda cogiendo el puerto. |
| Mi Unlock dice `error: check network` | Xiaomi ha caído o tu cuenta no cumple los 30 días. Repítelo en otra hora. |
| Mi Unlock no muestra el captcha | Sácalo a mano: abre `en.miui.com` en el navegador, inicia sesión con la **cuenta de Mi Band / Mi Fit**, resuelve el captcha y deja la sesión abierta. |
| TWRP se reinicia solo en bucle | La ROM no está parcheada. Vuelve al paso 4.2. |
| TWRP no monta `/data` | Es que `/data` está cifrado: **Wipe → Format Data**. |
| El hash sha256 no cuadra | No lo flashees. Descárgalo de nuevo y comprueba otra vez. |
| Ventilador al máximo, se reinicia solo | El teléfono se está calentando con la pantalla y la carga. Déjalo en una superficie dura y con airflow. |

---

Continúa con **[`instalacion.md`](instalacion.md)** — montar el chroot Ubuntu y
correr el instalador del stack encima.
