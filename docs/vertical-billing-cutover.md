# Corte coordinado de planes por vertical

Estado26/10: implementación y ensayo local completados; no autoriza producción, push o merge. Diez checkouts permanecen en ramas codex. Los sitios públicos externos quedan excluidos por decisión del usuario.

Platform recauda todos los pagos y atribuye cada recurso financiero a su línea y moneda. El administrador usa su sesión global existente en la consola; el BFF solicita una delegación específica para el catálogo o para inspección de beneficios de una línea registrada, activa y correctamente enlazada. Ningún token de servicio se entrega al navegador.

## Configuración preparada

El archivo docker-compose.vertical-billing.yml es un overlay opcional para docker-compose.yml. Los ocho interruptores nuevos de venta, administración, catálogo público, transporte, beneficios, mantenimiento, evaluación y retiro parten apagados. La entrega de publicaciones conserva su configuración independiente. No se modifican .env ni .env.local activos.

Las cuatro imágenes necesitan el directorio operation-keys preparado con propietario1654. Los cuatro volúmenes son independientes por servicio y deben persistir entre reinicios y réplicas del mismo servicio. Respaldar las claves junto a la base correspondiente; perderlas impide recuperar pruebas de autorización protegidas. Mantener esas rutas y la recuperación aunque se pausen nuevas ventas o evaluaciones. No compartir un anillo entre servicios.

Registrar primero cada vertical y su cliente enlazado con businesslines.resolve, catalogue.offers.sync y billing.coverage.deliver para PimaPlatform.Services; agregar searchwidgets.resolve y searchwidgets.log para su widget y public-directory.read en PimaCore.Services. Las solicitudes de evaluación requieren evaluations.request en PimaCore.Services; el motor registrado necesita credits.charge y possession.read en Platform. Las capacidades humanas siguen sus roles vigentes. Los scopes no se conceden por configurar el overlay.

**Acceso de máquina de un contrato (credencial de la API y página de búsqueda).** Ambos gastan en la cuenta de una sola línea y de una sola empresa; no hay cobro por contrato. El motor registrado necesita además en Platform `contractapi.authenticate` (comprobar la credencial y pedir su autorización) y `searchwidgets.authorize` (autorización de una página de búsqueda; Platform confirma contrato, línea y cobertura con buscador). Cada contrato debe elegir la línea de sus credenciales (`PUT /api/v1/tenants/{id}/contract-api/billing`, con empresa opcional cuando hay varias en la línea): sin esa elección las credenciales responden 403 `CONTRACT_API_BILLING_LINE_REQUIRED`, y con varias empresas y sin elegir una 409 `BILLING_ORGANIZATION_REQUIRED`. La cobertura que cuenta es la de la línea elegida; una línea retirada o sin cobertura rechaza la credencial en la siguiente llamada. Antes de abrir tráfico por credenciales, cada contrato que ya las tenga debe haber elegido su línea. Aplicar la migración `MachineBillingLine` de Platform antes de la API; es aditiva.

## Entrada y suspensión

1. Fijar imágenes y versiones del Kit revisadas; publicar referencias del submódulo antes de exigir su descarga en CI. Este trabajo aún no publica ningún repositorio.
2. Suspender nuevas escrituras comerciales en todos los llamadores. Drenar o registrar las operaciones anteriores aceptadas; conservar sus recibos y compensaciones. Verificar que no ingresan ventas mientras se prepara el backfill.
3. Obtener respaldo consistente de las cuatro bases y de sus anillos de claves. Ensayar la restauración antes del primer cobro nuevo. Nunca guardar secretos o dumps con datos personales en Git.
4. Comparar la entrada con el manifiesto aprobado:20 planes,2 paquetes,105 registros históricos y1,280 créditos, con órdenes históricas vacías. El delta posterior de pruebas no está aprobado: excluirlo sólo en una copia limpia de staging, verificando sus identidades y valores exactos. No borrar ni reasignar la fuente principal por inferencia.

## Aplicación ensayable

5. Aplicar migraciones compatibles; Platform31 agrega sólo recibos de dinero auténtico y no inventa pagos anteriores. Repetir el migrador y verificar valores previos idénticos.
6. Aplicar la transacción de ownership con guardas y locks del manifiesto105: Turismo conserva IDs, cuentas, lotes, expiraciones, cargos y libro; Automotriz recibe cero saldos. Repetir no debe duplicar revisiones ni valores.
7. Importar por las APIs propias los20 planes Turismo con sus IDs,20 espejos Automotriz con IDs independientes y los2 paquetes únicamente Turismo. Declarar V1 como versión inicial nueva; no escribirla como la versión aceptada de suscripciones anteriores. Verificar hash, términos, nombre, beneficios y replay de cada publicación. Un solo arranque publicado por línea; conservar el registro de su uso por cada contrato.
8. Retirar sin continuidad los15 períodos históricos, conforme a la decisión del usuario. Preparar un manifiesto exacto con identidades, términos, revisiones y fecha UTC de la ventana; ejecutar `Platform.Migrator.dll --historical-period-deprecation /manifest.json` para validar sin escribir. Sólo agregar `--apply-historical-period-deprecation` en una ventana autorizada. El comando separado cancela15 y genera15 hechos de cobertura negativa en la misma transacción; replay estable. No borra filas, concede créditos, altera fechas originales ni fabrica aceptación histórica. Conservar archivo financiero y saldos sin duplicación. El manifiesto privado del ensayo no autoriza ni sustituye el de la fuente real.
9. Activar recepción y conciliación con ventas aún pausadas. Resolver eventos pendientes, diferencias de revisión, versiones propias faltantes y los casos de evidencia incompleta. No habilitar beneficios manualmente basándose sólo en que el pago existe.
10. Activar conjuntamente el retiro en Platform/PIMA y las redirecciones de consola. Platform responde410 a nuevas operaciones comerciales globales; PIMA a POST /api/v1/evaluations. Historial, webhooks, recibos y compensaciones aceptados siguen disponibles. Después imponer restricciones definitivas contra nuevas filas comerciales sin línea; no imponerlas antes del backfill y del drenaje.
11. Verificar reportes por línea/moneda y CSV contra recursos de pago auténticos y devoluciones confirmadas. Los importes incorrectos y pagos adicionales se muestran para revisión sin otorgar derechos. El uso de créditos se concilia por contexto con el libro, no representa el saldo actual.
12. Habilitar ventas únicamente en un despliegue posterior autorizado, tras validar retiro histórico, restricciones, recuperación, configuración y aceptación integral. Los sitios públicos externos no condicionan este alcance. Los proveedores externos requieren su propia cuenta de pruebas; los dobles locales no certifican MercadoPago ni colectores reales.

## Recuperación y alertas

Antes del primer cobro nuevo puede restaurarse el respaldo coordinado comprobado. Después, conservar nuevas notificaciones, recursos de pasarela y operaciones; priorizar corrección hacia adelante y conciliación. Restaurar una copia antigua sin recuperar esos hechos externos perdería evidencia de dinero recibido.

La pantalla separa período financiero, último período reservado, entrega, revisión de fuente y diagnóstico local de beneficios. Alerta a los cinco minutos de cola pendiente; el diagnóstico fresco caduca como máximo a los15 segundos. El reintento manual exige rol financiero vigente, contrato/línea exactos y revisión CAS; nunca reabre un evento entregado ni concede otra suscripción. Supervisar también errores del receptor, huecos de revisión, pagos en revisión y falta de versiones locales.

La aceptación local está documentada en bit-core/docs/superpowers/iterations/2026-10-25-vertical-billing-27 y28. Retiro histórico12 comprobaciones, restauración conjunta8 y motor/corte73; fuentes principales28/10/6/4 con ownership0. No faltan decisiones sobre continuidad o sitios. La publicación de commits/imágenes/Kit, integración, despliegue, corte principal y purga física son trabajo posterior fuera de la autorización actual.


## Restauración de un único receptor de ofertas

Si sólo Platform pierde sus proyecciones de catálogo, los ACK anteriores en cada vertical no provocan un reenvío automático. Pausar escrituras comerciales y publicaciones antes de recuperar. Respaldar Platform y obtener en cada dueño el historial completo de publicaciones selladas, incluidas las ya reconocidas; contrastar producto, versión y términos con sus versiones inmutables. Rechazar huecos o hashes distintos antes de enviar.

Reenviar mediante la API autenticada existente `POST /api/v1/catalogue/lines/{code}/offer-publications`, con el cliente propio de esa línea y `catalogue.offers.sync`, en secuencia1..N por producto, conservando OperationId, versión, acción, términos y hash originales. Verificar todos los campos del recibo; si hay una interrupción, repetir el mismo historial completo. No crear versiones, operaciones nuevas, cambiar el orden ni reabrir los ACK del dueño. Contrastar proyección final, disponibilidad y términos con el dueño; conciliar caja, libro, cuentas y períodos antes de reanudar. El helper `tools/vertical_offer_restore_replay_checks.py:recover` valida y ordena el lote; su función `exercise` es inyección destructiva exclusivamente para el fixture privado, nunca un comando de producción. Este procedimiento es explícito, no un reconciliador automático nuevo.

El respaldo coordinado de cuatro bases se ensayó sobre una entrada quiescente sin operaciones protegidas pendientes. Para otra entrada deben drenarse o inventariarse las operaciones y respaldarse también sus anillos reales; la prueba separada de cuatro volúmenes no sustituye ese respaldo.
