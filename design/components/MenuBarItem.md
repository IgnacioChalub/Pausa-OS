# MenuBarItem

El ítem de Pausa en la barra de menú: un SF Symbol que dice el estado y, si corresponde, un tiempo o una palabra.

**Qué provee quien lo usa:** el estado (próxima pausa, aviso previo, en pausa, pospuesta, reunión, pausado, esperando a Claude, en una jam, todo apagado) y los segundos restantes.

**Reglas:**
- Íconos en modo plantilla (`isTemplate = true`): toman el color de la barra solos, en claro, oscuro y con fondo de pantalla. No les pongas color. La única excepción es `moon.zzz` en `amber` mientras la pausa está pospuesta.
- Texto en `menubar`: `NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)`. Formato `m:ss`, sin ceros a la izquierda en los minutos.
- Ícono a texto: `space-1`. Nunca más de un ícono, salvo en una jam, que suma `person.2` adelante.
- Palabras permitidas en vez de tiempo: "ahora", "después". Nada más largo: el detalle va en el menú.
- Con `mostrar_contador: false` queda solo el ícono.

**Mapa de estados → SF Symbol:**

| Estado | Símbolo | Texto |
| --- | --- | --- |
| Próxima pausa corta | `eye` | `18:42` |
| Próxima pausa larga | `figure.walk` | `4:10` |
| Aviso previo | el de la pausa | `3` |
| En pausa | el de la pausa | `ahora` |
| Pospuesta | `moon.zzz` | `4:59` |
| En reunión con pausa pendiente | `phone` | `después` |
| Pausado | `pause` | — |
| Esperando a Claude | `hourglass` | — |
| En una jam | `person.2` + el de la pausa | `12:03` |
| Todo apagado | `eye.slash` | — |
