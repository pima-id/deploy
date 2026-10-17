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
