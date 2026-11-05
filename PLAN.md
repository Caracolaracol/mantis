# Mantis — estado y próximos pasos

## Implementado en 0.2.2

- [x] App nativa macOS 15+ con SwiftUI/AppKit y barra de menús.
- [x] Cinco modos de captura de solo audio y selección de entrada/canales.
- [x] Exportación M4A verificada y recuperación de temporales ante fallos.
- [x] Biblioteca con búsqueda, importación, reproducción, títulos editables y acciones Finder.
- [x] Arrastre nativo de archivos desde las filas de la biblioteca.
- [x] Audio/TXT planos juntos por defecto y ubicaciones independientes configurables.
- [x] Onboarding inicial y ajustes separados: General, Grabación, Modelos, Archivos y Privacidad.
- [x] Inicio sin ventana e inicio de sesión opcional con ServiceManagement.
- [x] Transcripción local opcional con transcribe.cpp 0.4.1 integrado.
- [x] Catálogo de cinco modelos, descargas confirmadas y verificación SHA-256.
- [x] Restablecimiento confirmado y acotado del permiso de pantalla/audio de Mantis.
- [x] Control local de instancia única, CLI e integración opcional con SketchyBar.
- [x] Scripts de bundle, firma local, DMG y verificación de solo lectura.

## Validación automatizada

- [x] 81 pruebas Swift con integraciones locales y vistas sintéticas.
- [x] 7 pruebas Python de SketchyBar en modo dry-run.
- [x] Las pruebas de recuperación de permisos usan un ejecutor falso: no ejecutan `tccutil` real.
- [x] Las pruebas de inicio de sesión usan un servicio falso: no registran la app al login.

## Validación manual pendiente

- [ ] Confirmar permisos y recuperación desde la copia instalada de esta versión.
- [ ] Probar las fuentes reales de Meet/Zoom/Teams y la sincronización con micrófono/interfaz.
- [ ] Probar desconexiones de entrada, falta de espacio y recuperación de capturas interrumpidas.
- [ ] Medir reuniones de 30–60 minutos, calidad en español, memoria y consumo de disco.
- [ ] Validar arrastre de archivos en Gemini/NotebookLM y límites de los receptores.
- [ ] Validar reinicio sin ventana y próxima sesión real de macOS.
- [ ] Validar descargas reales de cada modelo, cancelación y selección.
- [ ] Validar copia de bibliotecas anteriores con datos de prueba y copia de seguridad.

## Próximas mejoras

- [ ] Identidad de firma estable, Developer ID y notarización.
- [ ] Medidores por canal y nombres de canales de interfaces.
- [ ] Reanudación de transcripción por segmentos y mejores cortes de palabras.
- [ ] Evaluar diarización anónima como función separada, sin prometer identificación personal.
- [ ] Definir licencia del código propio antes de anunciarlo como software de código abierto.

Las pruebas técnicas no certifican reuniones reales ni recuperación completa tras un cierre abrupto. No usar Mantis como única copia de una grabación importante sin completar las validaciones correspondientes.
