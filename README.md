# Pausa

App de barra de menú para macOS que te recuerda descansar la vista y pararte.

- **Cada 20 min:** pausa corta a pantalla completa, "Mirá algo lejos", por 20 segundos.
- **Cada 1 hora:** pausa larga, "Levantate", por 5 minutos.
- **Antes de cada pausa** aparece una cuenta regresiva arriba: 3 segundos para la corta, 10 para la larga.
- **Posponer:** desde la cuenta regresiva o desde la pausa. Mientras está pospuesta queda un cartel arriba ("Pausa pospuesta, activala apenas puedas") con un botón para empezarla ya.
- **Saltar** (botón y Esc) viene apagado: las pausas no se pueden cortar. Se prende en Configuración → Pantalla.
- **Al volver de una pausa** el contador no arranca hasta que muevas el mouse o toques una tecla (`general.retomar_al_volver`, se apaga en Configuración → General).
- **En reuniones** (alguna app usando el micrófono) los avisos esperan a que cortes.
- **Cmd+Esc:** modo "Esperando a Claude", una pantalla de espera hasta que Claude Code termina de responder.
- Suena un "pop" cada vez que Claude Code termina de responder.

## Jams: pausas en grupo

Para hacer las pausas en grupo con gente en la misma red (wifi de la oficina, por ejemplo):

1. Uno toca **Crear una jam** en el menú. Su jam se anuncia en la red como "Jam de <su Mac>".
2. Los demás van a **Unirme a una jam** y la eligen.
3. Todos pasan a usar el horario y las duraciones de quien la arrancó: la cuenta regresiva y las pausas aparecen a la vez en todas las Macs. En la barra de menú se ve el ícono de dos personas.

Posponer, pausar y las reuniones son de cada uno: si posponés, esa pausa la hacés solo y te volvés a enganchar en la siguiente. Si se corta la conexión o salís, volvés a tu horario normal.

La primera vez macOS pide permiso de **Red local**. Hace falta que la red deje pasar Bonjour (algunas redes de invitados lo bloquean).

## Instalar

```sh
./build.sh
open ~/Applications/Pausa.app
```

Para que arranque sola: Configuración del Sistema → General → Ítems de inicio → agregar `Pausa.app`.


## Empaquetar para otros

```sh
./package.sh          # → dist/Pausa-<versión>.dmg
```

Arma un `.dmg` con ventana propia (fondo eucalipto con la marca, flecha de arrastrar, sin barras de Finder) y el ícono de Pausa en el disco: el otro lo abre y arrastra Pausa a Aplicaciones. El fondo lo dibuja `tools/make-dmg-background.swift` y la ventana la arma [dmgbuild](https://github.com/dmgbuild/dmgbuild) con `tools/dmg-settings.py`; la primera vez se instala solo en `tools/.venv`. La app es universal (Apple Silicon e Intel) y abre desde macOS 13. La versión sale de `VERSION`.

- **Sin certificado Developer ID**, la primera vez en otra Mac macOS avisa que no puede verificarla: clic derecho en Pausa → **Abrir**, o **Ajustes del Sistema → Privacidad y seguridad → Abrir igual**.
- **Con un certificado "Developer ID Application"** en el llavero, `package.sh` lo usa solo. Para que abra sin ninguna advertencia, además hay que notarizar: guardá una vez las credenciales con `xcrun notarytool store-credentials pausa …` y corré `NOTARY_PROFILE=pausa ./package.sh`.
- El ícono se genera con `swift tools/make-icon.swift` (queda en `assets/`). La marca sola está en `assets/Logos/pausa-mark.svg`.
## Integración con Claude Code

Agregar en `~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [{ "type": "command", "command": "\"$HOME/Applications/Pausa.app/Contents/MacOS/Pausa\" --claude-done >/dev/null 2>&1 || true", "timeout": 5 }] }
  ],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "\"$HOME/Applications/Pausa.app/Contents/MacOS/Pausa\" --claude-done >/dev/null 2>&1 || true", "timeout": 5 }] }
  ]
}
```

## Diseño

El design system (colores, tipografía, íconos, componentes y textos) está en [`design/`](design/README.md) y en Swift en `Design.swift`. Sin emojis: los íconos son SF Symbols.

## Configuración

Todo se configura en `config.yml`: qué está prendido, cada cuánto, cuánto dura, la cuenta regresiva, posponer, textos, sonidos, el atajo de Claude, etc. La plantilla con todas las opciones comentadas es `config.example.yml`.

- `./build.sh` crea `config.yml` a partir del example si todavía no existe (no va a git) y lo enlaza en `~/.config/pausa/config.yml`, que es lo que lee la app.
- La app lo relee sola cuando guardás. Si hay una clave mal escrita aparece "⚠️ Revisá config.yml" en el menú.
- **Desde Spotlight:** escribí "Pausa Config" y Enter (abre la mini-app *Pausa Configuración*, que Pausa deja a su lado al arrancar), o abrí Pausa cuando ya está corriendo. También anda `open pausa://configuracion`.
- **Configuración…** (Cmd+,) en el menú abre una ventana para editar todo sin tocar el archivo. Cada cambio se guarda al toque en `config.yml`.

