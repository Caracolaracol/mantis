# Mantis — estado y próximos pasos

## Implementado en 0.4.0

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
- [x] Inglés y español en bienvenida, ajustes, biblioteca, modelos, mensajes y barra de menús; inglés por defecto y selección persistente.
- [x] Tablas nativas EN/ES generadas desde un catálogo compartido, sin traducir datos del usuario.
- [x] Avisos de nuevas Releases estables, búsqueda manual y revisión automática opcional (apagada por defecto, un intento por día), sin instalar ni interrumpir grabaciones.

## Validación automatizada

- [x] 103 pruebas Swift con integraciones locales, localización, avisos de versiones y vistas sintéticas.
- [x] 12 pruebas Python de SketchyBar en modo dry-run, incluidos idioma, registro del widget y rutas con espacios/comillas.
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

## Edición Sonoma separada (0.4.1 de prueba)

- [x] Build opt-in `MANTIS_MACOS14=1`, directorio `.build-sonoma/` y DMG `Mantis-0.4.1-macOS14.dmg`; estándar macOS 15 intacto.
- [x] Captura de micrófono con AVAudioEngine y salida interna independiente del enum de micrófono de macOS 15; audio de sistema/aplicación con ScreenCaptureKit.
- [x] Comprobación sintética de desfase de 0,5 s entre tonos de las dos fuentes, medida sobre audio decodificado, y exportación M4A de 2,5 s.
- [x] Canal de avisos que solo acepta Releases `-sonoma`, sin ofrecer descargas estándar incompatibles.
- [x] 108 pruebas Swift por variante (Sonoma y estándar), más 12 del widget y 12 del sitio.
- [ ] Probar lanzamiento, permisos, fuentes reales, sincronización y sesiones largas en un Mac con macOS 14 real antes de considerar estable esta edición.

## Sitio de la aplicación

- [x] Astro estático en `website/`, sin backend ni servicios de analítica.
- [x] Portada con captura sintética, documentación, licencia MIT, descarga y enlace al autor con su caracol.
- [x] Paleta verde bosque/rosa claro y grano SVG animado mediante CSS, con pausa, pestaña oculta y movimiento reducido.
- [x] Inglés por defecto, español y páginas equivalentes enlazadas con selector EN/ES y hreflang.
- [x] Cabeza de mantis sin recuadro como logo, caracol menor y ataque SVG ocasional con silueta que desaparece.
- [x] Doce pruebas de estructura, idiomas, recursos, enlaces, licencia y efectos; seis páginas revisadas en 375/768/1440 px.
- [x] Workflow GitHub Pages con lockfile, acciones fijadas a commit y permisos de despliegue limitados.

## Próximas mejoras

- [ ] Identidad de firma estable, Developer ID y notarización.
- [ ] Medidores por canal y nombres de canales de interfaces.
- [ ] Reanudación de transcripción por segmentos y mejores cortes de palabras.
- [ ] Evaluar diarización anónima como función separada, sin prometer identificación personal.
- [x] Código propio publicado bajo licencia MIT; avisos de terceros y licencias de modelos independientes.

Las pruebas técnicas no certifican reuniones reales ni recuperación completa tras un cierre abrupto. No usar Mantis como única copia de una grabación importante sin completar las validaciones correspondientes.
