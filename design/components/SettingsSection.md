# SettingsSection

Un grupo de la ventana de Configuración: título corto y filas de ajuste, cada una con su etiqueta, su control y su unidad.

**Es un `Form` de SwiftUI con `.formStyle(.grouped)`.** Los controles son nativos (Toggle, TextField, Picker). Este componente fija la estructura y los textos; el sistema dibuja el resto con el acento del usuario. En las vistas previas el acento se representa con `accent`.

**Qué provee quien lo usa:** el título del grupo y las filas, cada una con etiqueta, control, unidad opcional y ayuda opcional.

**Reglas:**
- Títulos de grupo como sustantivo corto, sin emoji ni "·": "Pausa corta", "Pausa larga", "Posponer", "Pantalla", "Reuniones", "Claude", "General".
- Etiqueta a la izquierda; número alineado a la derecha con cifras tabulares; unidad después del campo en `ink-muted` ("min", "s", "veces").
- La ayuda va debajo de la etiqueta en `caption` y `ink-muted`: "0 = sin límite", "Botón "Saltar" y tecla Esc".
- Los switches dicen el estado prendido en positivo: "Permitir saltar", no "Bloquear saltar".
- Cada cambio se guarda al instante en config.yml: no hay botón Guardar.
- Separación entre grupos: `space-8`.
