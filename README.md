# Medidor de mechones por densidad (Flutter + visión artificial)

Aplicación Flutter que mide en tiempo real hasta dónde llega el **volumen principal** de N mechones colocados en una tabla con X líneas horizontales, ignorando cabellos sueltos, y clasifica cada mechón en un rango con color.

## 0. Modo foto fija (versión actual)

La medición ya no es en tiempo real. Se toma **una foto** y se analiza:

1. **Encuadre**: la pantalla muestra un marco con esquinas, una **línea roja**
   (altura de la base de los sujetadores) y una **cruz central**. Centre la
   tabla en el marco, alinee la base de los sujetadores con la línea roja y
   mantenga el teléfono quieto. El botón de linterna ayuda con poca luz.
2. **Análisis** (`lib/vision/photo_analyzer.dart`):
   - se cuentan **todos los mechones** primero (componentes de cabello que
     llegan a la base);
   - para cada mechón se busca la **punta** y se cuentan las **líneas
     dibujadas** que alcanza;
   - el valor es **fijo**: si la punta queda entre la línea 8 y la 9 cm, el
     mechón se reporta como **8 cm**. Si queda bajo la primera línea,
     "< 7 cm"; si supera la última, "≥ 14 cm" (según las líneas detectadas).
3. **Resultado**: la foto con las líneas, las cajas y las puntas; la lista de
   mechones; un resumen por valor; y avisos de calidad (borrosa, oscura,
   sobreexpuesta o sin líneas).

Archivos nuevos o reemplazados:

- `lib/core/config/photo_params.dart`: parámetros del análisis de foto.
- `lib/core/config/capture_config.dart`: orientación, marco de la tabla
  (`kTableRoi`) y altura de la base (`kBaseLineFraction`).
- `lib/core/models/photo_analysis.dart`: `HairStrand`, `PhotoAnalysis`, `PhotoQuality`.
- `lib/vision/photo_analyzer.dart`: análisis puro en Dart sobre RGB.
- `lib/vision/photo_pipeline.dart`: decodifica, corrige EXIF, recorta y analiza en un isolate.
- `lib/ui/screens/capture_screen.dart`, `lib/ui/screens/result_screen.dart`.
- `lib/ui/painters/guide_painter.dart`, `lib/ui/painters/photo_overlay_painter.dart`.
- `test/photo_analyzer_test.dart`: foto sintética con tres mechones.

Eliminados por ser sólo del modo en vivo: `vision_worker.dart`,
`frame_sampler.dart`, `temporal_smoother.dart`, `line_stabilizer.dart`,
`measure_screen.dart` y `strand_overlay_painter.dart`.
`density_analyzer.dart` (y su test) se conservan, pero la app ya no los usa.

**Cambios de esta versión**

- Cada mechón tiene su color (en la foto y en la lista).
- La altura de un mechón es su cabello **más alto**, no la zona donde hay más
  cabello. Los cabellos finos que se separan del cuerpo se conectan por contraste
  local sobre el papel (`tipMinContrast`, `tipBackgroundRadius`).
- Hasta **20 mechones** a la vez: el umbral mínimo de área por mechón bajó a
  0.15 % del marco (`minAreaFraction`), para que los mechones finos no se descarten.
  Los colores son por **nivel** (`kLevelPalette` en `photo_overlay_painter.dart`): todos los mechones de un mismo valor (p. ej. 8 cm) tienen el mismo color; los que quedan bajo la primera línea van en gris.

**Pendiente de verificar en un equipo real**: compilar (`flutter pub get`,
`flutter test`), la orientación de la foto (EXIF) y el encuadre. Las marcas de
la pantalla y el marco del análisis deben coincidir; si la foto sale con otro
recorte, ajuste `kTableRoi`.

---

## 0. Cambios: orientación horizontal y líneas detectadas

- **Horizontal.** La app se bloquea en landscape (`kCaptureOrientation` en `lib/core/config/capture_config.dart`) para que la cámara abarque más superficie de la tabla. La rotación del buffer se calcula en `FrameSampler.uprightRotation`. Si la imagen aparece de cabeza, cambia la constante a `DeviceOrientation.landscapeRight`.
- **Líneas detectadas.** Ya no se usan líneas equiespaciadas por defecto. Al abrir la app, `LineDetector` busca las líneas dibujadas sobre el papel (con una transformada de Hough que admite pendiente, porque se dibujan a mano) y `LineStabilizer` fija el resultado cuando varios frames coinciden. La línea más cercana a los sujetadores es la **primera** (7 cm) y las demás suben de 1 en 1 cm. El botón **Redetectar líneas** (⟳) vuelve a buscarlas si se mueve la tabla.
- **Medición por carril.** Cada mechón se compara contra la altura de la línea en su propio centro, porque las líneas pueden estar ligeramente inclinadas.

Parámetros de la detección (en `AnalysisParams`): `lineMinContrast` (contraste mínimo trazo/papel), `lineColumnStart` (se ignora la columna izquierda, donde están las etiquetas impresas), `lineMaxSlope` y `lineSlopeStep` (pendientes que se prueban), `lineMinCover` (fracción de columnas que debe cubrir una línea) y `lineMinSeparation` (separación mínima entre líneas).

El ROI (`BoardConfig.uniform`, `roi` y `clipY`) sigue siendo una guía de encuadre: alinea el recuadro con la tabla y la base de los sujetadores.

## 1. Recomendación: ¿OpenCV clásico o TFLite?

**Empieza con procesamiento clásico; deja ML como fase 2 detrás de una interfaz.**

El escenario es un entorno controlado: tabla fija, fondo uniforme, líneas en posiciones conocidas y sujetadores en la base. En ese contexto el procesamiento clásico tiene ventajas decisivas: no necesita dataset etiquetado, es determinista y explicable (puedes justificar ante un cliente por qué un mechón cayó en un rango), corre en pocos milisegundos en Dart puro sin dependencias nativas, y el requisito central, "ignorar cabellos sueltos", es exactamente lo que resuelve una **apertura morfológica** combinada con un **perfil de densidad**.

Ni siquiera hace falta OpenCV completo: las operaciones necesarias (umbral de Otsu, umbral adaptativo, erosión/dilatación separable, proyecciones por filas) están implementadas aquí en Dart con sumas prefijas, lo que evita el peso de `opencv_dart` (~30–60 MB por ABI) y los problemas de compilación nativa.

TFLite tiene sentido cuando aparezcan estos casos: cabello rubio o canoso sobre tabla blanca (poco contraste de luminancia), iluminación muy variable o reflejos, o tablas de distinto color. Para eso la arquitectura ya define `HairMaskProvider`: un modelo de segmentación binaria ligero (p. ej. U-Net/MobileNetV3 a 256×256, INT8, ~1–3 MB) implementa la misma interfaz devolviendo la máscara, y **todo lo demás (morfología, densidad, rangos, colores) no cambia**. La medición por densidad sigue siendo necesaria incluso con ML, porque el modelo segmentará también los cabellos sueltos (son cabello de verdad).

| Criterio | Clásico (implementado) | TFLite segmentación (fase 2) |
|---|---|---|
| Datos de entrenamiento | No | Sí (cientos de fotos etiquetadas) |
| Latencia típica | 3–10 ms | 15–40 ms (GPU/NNAPI delegate) |
| Robustez a color de cabello/luz | Media | Alta |
| Explicabilidad | Alta | Media |
| Tamaño de la app | +0 MB | +2–5 MB (modelo + runtime) |

## 2. Estructura del proyecto

```
hair_strand_meter/
├── pubspec.yaml
├── README.md
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── config/board_config.dart      # N mechones, X líneas, ROI, colores, parámetros
│   │   ├── config/capture_config.dart    # orientación fija de la app y la captura
│   │   └── models/strand_result.dart     # StrandResult, FrameAnalysis
│   │   └── models/detected_line.dart     # línea detectada (posición y pendiente)
│   ├── vision/
│   │   ├── frame_sampler.dart            # CameraImage → gris vertical del ROI (filtro de área)
│   │   ├── hair_mask.dart                # HairMaskProvider: Otsu, adaptativo (y TFLite en fase 2)
│   │   ├── morphology.dart               # erosión / dilatación / apertura O(w·h)
│   │   ├── density_analyzer.dart         # ★ algoritmo de medición por densidad
│   │   ├── line_detector.dart            # ★ detección de líneas dibujadas (Hough con pendiente)
│   │   ├── line_stabilizer.dart          # consenso entre frames para fijar las líneas
│   │   ├── temporal_smoother.dart        # moda + histéresis entre frames
│   │   └── vision_worker.dart            # Isolate dedicado, política drop-frames
│   └── ui/
│       ├── painters/strand_overlay_painter.dart   # ★ CustomPainter de rangos y colores
│       └── screens/measure_screen.dart            # cámara + overlay + panel de resultados
└── test/
    ├── density_analyzer_test.dart        # imagen sintética: volumen en línea 2, sueltos en línea 4
    └── line_detector_test.dart           # líneas inclinadas, etiquetado desde 7 cm, consenso y rango
```

### Puesta en marcha

```bash
flutter create --org com.tuempresa hair_strand_meter
# copiar pubspec.yaml, lib/ y test/ de este paquete sobre el proyecto generado
flutter pub get
flutter test
flutter run
```

En Android, `minSdkVersion` debe ser 21 o superior (`android/app/build.gradle`). En iOS, agrega a `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>La cámara se usa para medir la longitud de los mechones sobre la tabla.</string>
```

## 3. Flujo en tiempo real

```
Cámara (YUV420 / BGRA) ──► FrameSampler (hilo UI, <2 ms)
        │  ROI recortado, rotado a vertical y reducido a 180×270 en gris
        ▼
VisionWorker (Isolate) ──► DensityAnalyzer
        │  máscara → apertura → perfiles → punto final → rango
        ▼
TemporalSmoother (hilo UI) ──► setState ──► StrandOverlayPainter
```

Se analizan como máximo ~15 frames/s y, si el Isolate está ocupado, el frame se descarta: la latencia nunca se acumula y la vista previa sigue a 30 fps de forma independiente. Toda la geometría (ROI, carriles, líneas, final del mechón) se expresa en **coordenadas normalizadas del ROI**, compartidas por el analizador y el `CustomPainter`, así que no hay transformaciones adicionales entre visión y UI.

## 4. Algoritmo: medición por densidad ignorando cabellos sueltos

Notación: la imagen de análisis tiene W×H píxeles; el carril del mechón i ocupa las columnas [x₀, x₁) con ancho Wᵢ; la fila `base` está justo encima de los sujetadores; y crece hacia abajo (el mechón crece hacia y menores).

### Paso 0 — Muestreo con filtro de área

Cada píxel de análisis es el promedio de s×s muestras (s = 3) de la imagen de la cámara. Un cabello de 1–2 px en la cámara ocupa una fracción pequeña de la celda y queda como un gris claro: el filtro **ya atenúa los cabellos sueltos antes de binarizar**, mientras que el volumen denso permanece oscuro.

### Paso 1 — Segmentación

Máscara binaria M(x, y) ∈ {0, 1} con umbral de Otsu, que maximiza la varianza entre clases:

```
t* = argmax_t  ω_B(t) · ω_F(t) · (μ_B(t) − μ_F(t))²
M(x,y) = 1  si  I(x,y) ≤ t*   (cabello oscuro sobre tabla clara)
```

Con iluminación irregular se usa el umbral adaptativo `I(x,y) < media_local(41×41) − C` (activar `useAdaptiveThreshold`).

### Paso 2 — Apertura morfológica con kernel rectangular

```
M' = (M ⊖ K) ⊕ K,      K = rectángulo kw × kh  (por defecto 5 × 3)
```

La apertura elimina toda estructura en la que no cabe el kernel completo. Esto separa limpiamente los tres tipos de objetos de la tabla:

| Objeto | Ancho | Alto | ¿Sobrevive? |
|---|---|---|---|
| Cabello suelto (vertical) | 1–2 px < kw | largo | No (lo borra kw) |
| Línea impresa (horizontal) | largo | 1–2 px < kh | No (lo borra kh) |
| Volumen del mechón | ≫ kw | ≫ kh | Sí, con su forma intacta |

Varios cabellos sueltos juntos podrían formar un grupo más ancho que kw y sobrevivir; para eso está el paso 4.

### Paso 3 — Perfil de densidad por carril

```
Dᵢ(y) = (1 / Wᵢ) · Σ_{x=x₀}^{x₁−1} M'(x, y)        ∈ [0, 1]
```

Es la fracción del ancho del carril cubierta por cabello en cada fila. Las filas de las líneas impresas (±1) se marcan como inválidas y se interpolan linealmente para que la tinta nunca cuente como cabello. Luego se suaviza con media móvil centrada de ventana w = 5:

```
D̃ᵢ(y) = (1 / w) · Σ_{j=−⌊w/2⌋}^{⌊w/2⌋} Dᵢ(y + j)
```

### Paso 4 — Densidad de referencia del mechón

El volumen principal se mide justo encima de los sujetadores, donde el mechón está completo:

```
D_ref = mediana{ D̃ᵢ(y) : y ∈ (base − 0.15·base, base] }
```

Si `D_ref < 0.12`, el carril se marca como **vacío**. La mediana hace que la referencia sea robusta a una sombra o un hueco puntual.

### Paso 5 — Punto final del volumen principal

Se recorre el perfil desde la base hacia arriba con umbral relativo τ (0.45) y tolerancia de huecos G (4 filas):

```
y_end = mín { y :  D̃ᵢ(y) ≥ τ · D_ref  y  ninguna racha de más de G filas
                   consecutivas entre y y base tiene D̃ᵢ < τ · D_ref }
```

Por qué funciona: el umbral es **relativo a la densidad del propio mechón**, no absoluto. Si el volumen ocupa el 70 % del carril, D_ref ≈ 0.70 y el umbral es ≈ 0.31. Tres cabellos sueltos que sobrevivieran a la morfología sumarían ≈ 3/23 ≈ 0.13 del carril: muy por debajo, así que nunca extienden el final. Un mechón ralo y uno tupido se miden con el mismo criterio ("hasta dónde llega al menos el 45 % de su densidad normal").

Con τ = 0.45 y ventana 5 el estimador es insesgado ante un borde nítido: la fila del borde vale 3/5 = 0.6 de D_ref (se acepta) y la siguiente 2/5 = 0.4 (se rechaza).

Alternativa disponible por configuración (`EndpointStrategy.massQuantile`), el cuantil de masa:

```
y_end = máx { y :  Σ_{j=y}^{base} D̃ᵢ(j)  ≥  q · Σ_{j=0}^{base} D̃ᵢ(j) },   q = 0.97
```

y `conservative`, que toma el más corto de ambos.

### Paso 6 — Clasificación en rango

Con las X líneas ordenadas desde la base (ℓ₁ más cercana a los sujetadores), el rango es la cantidad de líneas alcanzadas:

```
k = | { j : y_end ≤ y(ℓⱼ) + ε } |        ε = 0.004 (tolerancia de contacto)
```

X líneas generan X + 1 rangos: k = 0 "antes de ℓ₁", 1 ≤ k < X "entre ℓₖ y ℓₖ₊₁", k = X "más allá de ℓ_X". Cada rango tiene un color: el de la paleta configurada o, por defecto, una rampa de tono HSV equiespaciada, `hue = (190 + 300·k/X) mod 360`, que mantiene distinguibles los rangos vecinos sea cual sea X. Si tu negocio prefiere que "terminar entre la línea 1 y la 2" se llame "rango línea 2", basta con cambiar `rangeLabel`; la clasificación no se toca.

### Paso 7 — Confianza y estabilidad temporal

La confianza es el contraste entre el cuerpo y la franja inmediatamente superior al final:

```
c = clamp( (media(D̃, cuerpo) − media(D̃, franja superior)) / media(D̃, cuerpo), 0, 1 )
```

y se reduce a la mitad si el mechón toca el borde superior del ROI (puede salirse del encuadre). El `TemporalSmoother` toma la **moda** del rango en los últimos 7 frames, aplica **histéresis** (solo cambia de rango si el nuevo tiene mayoría absoluta) y usa la mediana de los puntos finales. Así el color no parpadea cuando el final cae justo sobre una línea.

### Escalabilidad N × X

Nada en el algoritmo depende de 6 u 8: los carriles se generan con `laneRect(i)` para i < N, las líneas son una lista arbitraria (no necesitan estar equiespaciadas, así que puedes cargar posiciones medidas de una tabla real), y los colores se derivan de X. El costo es O(W·H) por frame, independiente de N y X. La pantalla incluye un panel para cambiarlos en caliente y el test unitario valida una tabla de 10 × 4.

## 5. El `CustomPainter`

`StrandOverlayPainter` dibuja en este orden: oscurece el exterior del ROI para guiar el encuadre; traza carriles, líneas de medición con su etiqueta y la línea de sujetadores; y para cada mechón dibuja la **banda del rango** (el tramo entre las dos líneas que lo delimitan, relleno y borde del color del rango), el **cuerpo** con degradado desde los sujetadores hasta el final, el **marcador** del final y una etiqueta con el número de mechón y el rango. La opacidad se modula por la confianza, de modo que los resultados dudosos se ven tenues. Con el botón de perfiles se dibuja D̃(y) dentro de cada carril, muy útil para calibrar τ, kw y kh con tablas reales. `shouldRepaint` solo repinta cuando cambia el análisis, la configuración o las opciones de visualización.

## 6. Calibración en campo

Ajusta en este orden, usando el modo de perfiles:

1. **ROI y posiciones de línea**: mide las líneas de tu tabla real en una foto y carga sus `y` normalizadas. Más adelante puedes automatizarlo detectando las líneas por proyección horizontal de la imagen sin cabello, o con 4 marcadores ArUco en las esquinas para una homografía (aquí sí vale la pena `opencv_dart`).
2. **kw**: debe ser mayor que el grosor de un cabello en la imagen de análisis y bastante menor que el ancho de un mechón. Con 180 px de ancho y 6 carriles, 5 es un buen punto de partida.
3. **τ**: más alto (0.55) es más estricto con las puntas ralas; más bajo (0.35) incluye más punta.
4. **Hardware**: imprime las líneas en un color claro en luminancia (amarillo, rojo claro) para que casi no aparezcan en la máscara, usa fondo mate y luz difusa, y mantén el teléfono paralelo a la tabla (un soporte fijo elimina la perspectiva).

## 7. Próximos pasos sugeridos

Detección automática de la tabla (ArUco + homografía) para no depender del encuadre manual; captura de foto con los resultados superpuestos para auditoría; modo "congelar" que promedia 15 frames y fija el resultado; y recolección de imágenes con su máscara corregida durante el uso, que servirá como dataset si se pasa a TFLite.
