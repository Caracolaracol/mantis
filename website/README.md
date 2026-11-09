# Sitio de Mantis

Sitio estático Astro de portada, documentación y licencia. Vive en este mismo repositorio, independiente de la app Swift.

- URL de producción: `https://caracolaracol.github.io/mantis/`.
- Inglés por defecto; español en `/mantis/es/`. Documentación: `/documentation/` y `/documentacion/`; licencia: `/license/` y `/licencia/`.
- Node 22.23.4 o posterior; Astro fijado en `package.json` y lockfile.
- `npm run build` sincroniza captura e icono desde los recursos del repositorio.
- El caracol es el mismo recurso de la identidad personal usado en Raigambre.

## Desarrollo

```bash
cd website
npm ci
npm run dev
```

El paquete `node` de desarrollo mantiene un runtime local; los scripts de npm lo encuentran sin reemplazar el Node global. También puedes usar tu propio Node compatible y `.nvmrc`.

```bash
npm run build
npm test
npm run preview
```

Abre la ruta `/mantis/`, también durante el desarrollo. Los enlaces internos usan el prefijo de GitHub Pages.

## Grano en movimiento

Una textura SVG pequeña con `feTurbulence` se repite en una capa decorativa recortada al viewport. CSS mueve la capa en saltos mediante `transform` y `steps()`, sin recalcular el filtro sobre toda la pantalla en cada cuadro. El grano no captura clics ni se expone al lector de pantalla.

Se detiene con `prefers-reduced-motion`, puede pausarse desde el pie y deja de animarse al ocultar la pestaña. No requiere canvas, fuentes remotas, analítica ni servicios externos.

Un ataque SVG decorativo comienza a los 3,5 segundos y luego se repite a intervalos de 26–52 segundos. Un brazo entra desde la derecha; otro, reflejado desde la izquierda, comienza 300 ms después. Cada brazo se retira y deja una silueta que se desvanece durante los siguientes segundos. El dibujo original incluye coxa, fémur, tibia plegada, dos filas opuestas de espinas tipo sierra y espolón terminal, basado en [referencias anatómicas de S. lineola](https://www.nature.com/articles/s41598-025-06427-6/figures/3). Está detrás del contenido, no captura eventos y se oculta con pausa, pestaña no visible o movimiento reducido. No requiere imágenes generadas ni dependencias de animación.

El header y el footer ocupan todo el ancho del viewport, con márgenes internos adaptativos. El contenido principal mantiene un ancho máximo de 1280 px (antes 1200 px), con márgenes móviles sin cambios; las páginas de lectura conservan sus límites específicos.
El hero ofrece descargas separadas: edición estándar para macOS 15+ como botón principal y edición Sonoma para macOS 14 como enlace secundario, identificada como versión de prueba para Apple Silicon y con enlace a los detalles de compatibilidad.
La home termina en la franja AUDIO ONLY / LOCAL FIRST / NO ACCOUNTS / MIT / OPEN SOURCE (localizada en español): solo conserva hero, captura y franja, sin secciones inferiores ni footer. Documentación y licencia conservan su footer. Los brazos siguen activos en la home; el control de pausa se encuentra junto al contenido del hero.
Si el contenido no llena la pantalla, la franja queda al borde inferior gracias a un layout flexible con altura mínima de 100svh. No es una capa fija: cuando el hero requiere más espacio, la franja sigue el flujo y no lo tapa.

Los brazos y las siluetas usan rellenos sin contornos, con blur suave de 1,5 px y 2,5 px respectivamente. Cada ataque dura 800 ms: entrada acelerada de 320 ms, apoyo de 160 ms y retirada rápida de 320 ms. La silueta aparece al llegar el brazo y mantiene su desvanecimiento independiente de 8 segundos.
Los brazos usan verdes claros (base #7aa66a, tibia #a0c786, espinas #c0dca5 y articulaciones #628c55); la silueta conserva el verde oscuro #07140e para dejar una sombra, no un contorno luminoso.

Referencias técnicas: [MDN: feTurbulence](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/feTurbulence) y [técnica de textura con saltos CSS](https://webdevpuneet.com/ui-snippets/noise-background/). Implementación propia bajo la licencia MIT del repositorio.

## Publicación

`.github/workflows/website.yml` compila y valida el sitio. En `main` publica `website/dist` usando GitHub Pages; los pull requests solo compilan y prueban. La web no compila, firma ni reemplaza Mantis ni el DMG.

El despliegue usa acciones fijadas a commits, lockfile y permisos de Pages limitados al job de publicación. Las vulnerabilidades moderadas, altas o críticas bloquean la compilación en CI. Al preparar el sitio quedó una alerta baja de esbuild relativa a su servidor de desarrollo en Windows; no se sirve un servidor de desarrollo en GitHub Pages. No se ejecutó `npm audit fix --force`.
