# Button

Botón en forma de píldora para la pantalla de pausa y los banners. En Configuración y diálogos se usan los botones nativos de macOS.

**Qué provee quien lo usa:** el texto (un verbo y, si hace falta, el tiempo: "Posponer 5 min") y la variante. Opcionalmente, el atajo de teclado a la derecha en `pa-kbd`.

**Variantes:**
- Principal: `accent` con texto `on-accent`. Uno solo por superficie. "Empezar ahora".
- Secundario: `surface` con borde `line-strong` y texto `ink`. "Posponer 5 min".
- Silencioso: sin relleno, texto `ink-muted`. "Saltar".
- Sobre la pausa (`pa-on-rest`): principal en `rest-accent` con `rest-on-accent`, secundario en `rest-raised` con borde `rest-line`, silencioso en `rest-muted`. Tamaño grande: 40px de alto.

**Medidas:** 32px de alto (40 en la pausa), padding `space-4` (`space-6` en la pausa), `radius-pill`, texto `body` a 500 (15px en la pausa).

**Foco:** anillo sólido de 2px en `focus-ring` (o `rest-accent` sobre la pausa), separado 2px del botón.

**No:** íconos solos sin texto, mayúsculas, dos principales juntos.
