# Publicación del checkout embebido

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
