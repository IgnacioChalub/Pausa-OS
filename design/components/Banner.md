# Banner

Aviso flotante arriba al centro de la pantalla que no roba el foco: cuenta regresiva antes de una pausa, pausa pospuesta y mensajes cortos.

**Qué provee quien lo usa:** un ícono de estado (SF Symbol), el texto principal, un texto secundario opcional y hasta dos botones.

**Anatomía:** `surface` con `shadow-float` y `radius-lg`, alto mínimo 44px, padding `space-4` a la izquierda y `space-2` a la derecha si hay botón (`space-4` si no). Ícono a texto `space-2`, texto a botón `space-3`. Texto en `banner`, el secundario en `ink-muted`. Queda a `space-4` del borde superior del área visible.

**Variantes:**
- Aviso previo: ícono de la pausa que viene (`eye` o `figure.walk`), "Pausa corta en 3". Botón secundario "Posponer 5 min".
- Pospuesta: ícono `moon.zzz` en `amber`, "Pausa pospuesta" + "vuelve en 4:12" en `ink-muted`. Botón principal "Empezar ahora".
- Error o info: ícono `exclamationmark.triangle` en `danger`. Sin botones, se va solo a los 4 segundos. El texto dice qué pasó y qué hacer.

**Reglas:**
- Un solo banner a la vez. El nuevo reemplaza al anterior.
- El número cambia en el lugar, con cifras tabulares, para que el ancho no salte.
- En la app se arma con `NSVisualEffectView` (material `.hudWindow`). En las vistas previas, ese material se representa con `surface`.
