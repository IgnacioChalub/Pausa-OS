# BreakScreen

La pantalla completa de cada pausa: dice qué hacer, cuánto falta y, si la config lo permite, cómo posponer o saltar.

**Cuándo:** pausa corta (vista), pausa larga (pararse) y modo "Esperando a Claude". Nada más ocupa la pantalla entera.

**Qué provee quien la usa:** `eyebrow` (tipo y duración), `title` (la instrucción), `sub` (el detalle), `remaining` y `total` en segundos (o ninguno, en la espera de Claude), y los botones habilitados por config (`posponer.activado`, `pantalla.permitir_saltar`).

**Anatomía, de arriba a abajo:**
- Fondo `rest-ground` a `rest-opacity` sobre cada pantalla. Mismo color en tema claro y oscuro.
- `eyebrow` en `rest-muted`, mayúsculas: "PAUSA CORTA · 20 S", "PAUSA LARGA · 5 MIN", "EN ESPERA".
- `rest-title` en `rest-ink`, `space-3` debajo del eyebrow.
- `rest-sub` en `rest-muted`, `space-2` debajo.
- `rest-timer` en `rest-ink`, `space-12` debajo. Cifras tabulares, formato `m:ss`.
- Barra de progreso de 280×4 en `rest-track` con relleno `rest-accent`, `space-6` debajo. Avanza a medida que pasa la pausa.
- Botones `Button` en variante sobre-reposo, `space-16` debajo, separados `space-4`. Secundario para "Posponer 5 min", silencioso para "Saltar".

**Reglas:**
- Sin emoji en el título. El tipo de pausa lo dice el eyebrow.
- Si no hay botones (saltar apagado y posponer agotado), no dejes el hueco: el bloque queda centrado sin ellos.
- En la espera de Claude no hay barra: la cifra cuenta hacia arriba en `rest-muted` a 96px y abajo va el atajo para salir.
- Aparece con un fundido de 400 ms y se va con uno de 250 ms. Con "Reducir movimiento" activado, sin fundido.
