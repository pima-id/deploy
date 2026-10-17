# Publicación del checkout embebido

**Estado vigente, 2026-10-17: corrección implementada en main y validada localmente.**
La primera acreditación exige webhook auténtico y consulta autoritativa. Refresh y mantenimiento
no sustituyen la notificación. El cierre y reapertura siguientes son el registro histórico;
publicación pendiente, sin despliegue al VPS por este cambio.

Publicar coordinadamente las ramas codex/mercadopago-embedded de Platform, BitFront y deploy.
Antes de reiniciar, configurar MERCADOPAGO_PUBLIC_KEY junto al access token y secreto existentes,
los tres de la misma aplicación/entorno mexicano. El compose lo pasa como MercadoPago__PublicKey.
La clave pública identifica la aplicación en MercadoPago.js; no sustituye la credencial privada.

El migrador agrega PaymentAttemptId, PaymentPayloadHash y PaymentAttemptRejected a Orders.
Combinar el snapshot EF con otras migraciones concurrentes, conservando ambas migraciones.
La respuesta de crear la compra deja de contener checkoutUrl: desplegar frontend y backend juntos.

En la aplicación de Mercado Pago registrar la URL HTTPS de Platform terminada en
/api/v1/payments/notifications y el evento Order (Mercado Pago), tópico order. Mantener payment
para compras históricas. Orders no admite configurar notification_url en el body.

Probar con una cuenta de pruebas: tarjeta aprobada, rechazo y segundo intento, cuotas,
notificación repetida, resultado tardío y reembolso. Los tests aislados no certifican esa cuenta.

## Cierre registrado — 2026-10-17

PR deploy #1, Platform #2 y web #5 fusionados; pagos cerrado por instrucción del usuario.
El usuario confirmó que funciona el POST público al webhook en api.pima-id.com.
La respuesta esperada sin firma es 200 con status=rejected: confirma enrutamiento al controller,
no una notificación firmada ni un cobro real. No se inspeccionó directamente el VPS.

Nuxt recibe NUXT_PLATFORM_API_URL=http://platform-api:8080 y alcanza Platform por la red services
de Docker; no necesita DNS público del API. Compose inyecta PLATFORM_DOMAIN a Caddy desde .env
o el archivo indicado con --env-file. Esa variable no crea DNS. El ingreso público se limita
a /api/v1/payments/notifications*. Mantener los eventos order y payment histórico.

La auditoría de devoluciones está en PIMAPlatform/docs/refunds-audit.md y en el tablero global.
No hay cambios de Compose, secretos, imágenes ni migraciones por esta auditoría. El plan deberá
añadir conciliación de devoluciones inciertas y pruebas de webhook firmado al implementarse.

## Publicación de confirmación obligatoria por webhook

1. Usar el migrador de la nueva versión Platform: aplicar
   20261017185044_RequireVerifiedPaymentWebhook antes de arrancar ese backend.
   Añade PaymentNotifications.AuthenticatedAtUtc y Orders.ConfirmedByNotificationId/
   PaymentConfirmedAtUtc, todos nullable. No elimina datos ni presume autenticación histórica.
2. Publicar Platform primero y la consola después. El backend cierra la vía de acreditación
   por refresh incluso para la consola anterior. No se cambia el compose ni se agregan secretos.
3. Mantener URL HTTPS /api/v1/payments/notifications y eventos order y payment histórico.
   Nuxt usa http://platform-api:8080 por Docker; la notificación entra por Caddy.
4. Validar en cuenta de pruebas: Orders procesado sin webhook mantiene Pending/awaitingWebhook,
   cero créditos y sin nuevo plan. Después de un webhook válido del mismo recurso más GET correcto,
   Fulfilled tiene confirmedByNotificationId y paymentConfirmedAtUtc, sin entrega duplicada.
5. Un POST sin firma sigue respondiendo rejected: sólo prueba el enrutamiento. Un pago sin
   webhook no se acredita por el job; genera advertencia con OrderId/ResourceId. El job puede
   retomar únicamente recibos autenticados Received/Retry, con el intervalo configurado.

No backfillear autenticación ni revertir compras históricas automáticamente: una orden previa
con columnas nuevas vacías requiere contrastar pagos, inbox y fechas. No se hicieron cobros reales,
no se certificó Mercado Pago ni se accedió al VPS en esta entrega. Validación local: 1,057 backend,
586 frontend, lint, tipos, build y 4 Chrome con webhook firmado explícito y pasarela simulada.
Modelo EF coherente; Docker no disponible para repetir la migración en MariaDB.
